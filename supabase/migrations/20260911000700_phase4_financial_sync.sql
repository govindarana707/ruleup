-- Phase 4 financial writes are RPC-only. The stable client mutation timestamp
-- makes concurrent/replayed check-in edits converge without duplicating points.
alter table public.check_ins
add column client_updated_at timestamptz;

update public.check_ins
set client_updated_at = updated_at
where client_updated_at is null;

alter table public.check_ins
alter column client_updated_at set not null,
alter column client_updated_at set default now();

drop policy if exists check_ins_insert_own on public.check_ins;
drop policy if exists check_ins_update_own on public.check_ins;
drop policy if exists check_ins_delete_own on public.check_ins;
drop policy if exists point_ledger_insert_own on public.point_ledger;
drop policy if exists point_ledger_update_own on public.point_ledger;
drop policy if exists point_ledger_delete_own on public.point_ledger;

revoke insert, update, delete on public.check_ins, public.point_ledger
from authenticated;

create or replace function public.upsert_check_in_with_ledger(
  p_check_in jsonb,
  p_ledger_id uuid
) returns public.check_ins
language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  check_in_id uuid := (p_check_in->>'id')::uuid;
  incoming_updated_at timestamptz := coalesce(
    (p_check_in->>'updated_at')::timestamptz,
    (p_check_in->>'created_at')::timestamptz,
    now()
  );
  submitted_points integer := (p_check_in->>'awarded_points')::integer;
  submitted_rule_id uuid := nullif(p_check_in->>'matched_rule_id', '')::uuid;
  selected_habit public.habits;
  selected_rule public.point_rules;
  selected_option public.habit_options;
  effective_value double precision;
  rule_matches boolean := false;
  existing public.check_ins;
  result public.check_ins;
begin
  if owner_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if check_in_id is null or p_ledger_id is null then
    raise exception 'stable check-in and ledger IDs are required' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(owner_id::text || ':' || check_in_id::text, 0));

  select * into selected_habit
  from public.habits
  where id = (p_check_in->>'habit_id')::uuid and user_id = owner_id;
  if not found then
    raise exception 'habit not found for authenticated owner' using errcode = 'P0002';
  end if;

  effective_value := nullif(p_check_in->>'measured_value', '')::double precision;
  if nullif(p_check_in->>'option_id', '') is not null then
    select * into selected_option
    from public.habit_options
    where id = (p_check_in->>'option_id')::uuid
      and user_id = owner_id
      and habit_id = selected_habit.id;
    if not found then
      raise exception 'option not found for authenticated habit' using errcode = 'P0002';
    end if;
    effective_value := coalesce(effective_value, selected_option.numeric_value);
  end if;

  if submitted_rule_id is null then
    if submitted_points <> 0 then
      raise exception 'non-zero points require an owned matching rule' using errcode = '22023';
    end if;
  else
    select * into selected_rule
    from public.point_rules
    where id = submitted_rule_id
      and user_id = owner_id
      and habit_id = selected_habit.id
      and archived_at is null;
    if not found or selected_rule.points <> submitted_points then
      raise exception 'submitted points do not match the owned rule' using errcode = '22023';
    end if;
    rule_matches := case selected_rule.operator
      when 'completed' then true
      when 'eq' then effective_value = selected_rule.value_min
      when 'lt' then effective_value < selected_rule.value_min
      when 'lte' then effective_value <= selected_rule.value_min
      when 'gt' then effective_value > selected_rule.value_min
      when 'gte' then effective_value >= selected_rule.value_min
      when 'between' then effective_value between selected_rule.value_min and selected_rule.value_max
      else false
    end;
    if not coalesce(rule_matches, false) then
      raise exception 'submitted point rule does not match the check-in value' using errcode = '22023';
    end if;
  end if;

  select * into existing from public.check_ins where id = check_in_id;
  if found and existing.user_id <> owner_id then
    raise exception 'check-in belongs to another user' using errcode = '42501';
  end if;

  if existing.id is not null and incoming_updated_at < existing.client_updated_at then
    result := existing;
  elsif existing.id is not null and incoming_updated_at = existing.client_updated_at then
    if existing.habit_id is distinct from selected_habit.id
      or existing.habit_date is distinct from (p_check_in->>'habit_date')::date
      or existing.option_id is distinct from nullif(p_check_in->>'option_id', '')::uuid
      or existing.measured_value is distinct from nullif(p_check_in->>'measured_value', '')::double precision
      or existing.note is distinct from nullif(p_check_in->>'note', '')
      or existing.awarded_points is distinct from submitted_points
      or existing.matched_rule_id is distinct from submitted_rule_id then
      raise exception 'conflicting check-in mutations have the same timestamp' using errcode = '40001';
    end if;
    result := existing;
  elsif existing.id is not null then
    update public.check_ins set
      option_id = nullif(p_check_in->>'option_id', '')::uuid,
      measured_value = nullif(p_check_in->>'measured_value', '')::double precision,
      note = nullif(p_check_in->>'note', ''),
      awarded_points = submitted_points,
      matched_rule_id = submitted_rule_id,
      client_updated_at = incoming_updated_at
    where id = check_in_id and user_id = owner_id
    returning * into result;
  else
    insert into public.check_ins (
      id, user_id, habit_id, habit_date, option_id, measured_value, note,
      awarded_points, matched_rule_id, checked_in_at, editable_until,
      created_at, client_updated_at
    ) values (
      check_in_id, owner_id, selected_habit.id,
      (p_check_in->>'habit_date')::date,
      nullif(p_check_in->>'option_id', '')::uuid,
      nullif(p_check_in->>'measured_value', '')::double precision,
      nullif(p_check_in->>'note', ''), submitted_points, submitted_rule_id,
      (p_check_in->>'checked_in_at')::timestamptz,
      (p_check_in->>'editable_until')::timestamptz,
      coalesce((p_check_in->>'created_at')::timestamptz, now()),
      incoming_updated_at
    ) returning * into result;
  end if;

  insert into public.point_ledger(
    id, user_id, source_type, source_id, points, updated_at
  ) values (
    p_ledger_id, owner_id, 'check_in', result.id::text,
    result.awarded_points, result.updated_at
  )
  on conflict (user_id, source_type, source_id) do update set
    points = excluded.points,
    updated_at = excluded.updated_at
  where public.point_ledger.points is distinct from excluded.points;

  return result;
end;
$$;

create or replace function public.record_missed_check_in_penalty(
  p_habit_id uuid,
  p_habit_date date,
  p_points integer,
  p_ledger_id uuid
) returns public.point_ledger
language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  source_key text := p_habit_id::text || ':' || p_habit_date::text;
  result public.point_ledger;
begin
  if owner_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_points > 0 then
    raise exception 'penalty must be non-positive' using errcode = '22003';
  end if;
  if not exists (
    select 1 from public.habits where id = p_habit_id and user_id = owner_id
  ) then
    raise exception 'habit not found' using errcode = 'P0002';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(owner_id::text || ':' || source_key, 0));
  insert into public.point_ledger(
    id, user_id, source_type, source_id, points, reason
  ) values (
    p_ledger_id, owner_id, 'missed_check_in', source_key, p_points,
    'Missed check-in on ' || p_habit_date::text
  )
  on conflict (user_id, source_type, source_id) do nothing
  returning * into result;
  if result is null then
    select * into result from public.point_ledger
    where user_id = owner_id
      and source_type = 'missed_check_in'
      and source_id = source_key;
  end if;
  return result;
end;
$$;

revoke all on function public.upsert_check_in_with_ledger(jsonb, uuid)
from public, anon;
revoke all on function public.record_missed_check_in_penalty(uuid, date, integer, uuid)
from public, anon;
grant execute on function public.upsert_check_in_with_ledger(jsonb, uuid)
to authenticated;
grant execute on function public.record_missed_check_in_penalty(uuid, date, integer, uuid)
to authenticated;
