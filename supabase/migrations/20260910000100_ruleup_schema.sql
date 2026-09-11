-- RuleUp Phase 1 Supabase foundation.
-- Additive only: Cloudflare D1 remains the active remote data store.

create extension if not exists pgcrypto;
create extension if not exists btree_gist;

create type public.measurement_type as enum ('yes_no', 'duration', 'count', 'value');
create type public.schedule_type as enum ('daily', 'specific_days', 'times_per_week', 'custom');
create type public.point_rule_operator as enum ('completed', 'eq', 'lt', 'lte', 'gt', 'gte', 'between');
create type public.ledger_source_type as enum ('check_in', 'missed_check_in', 'reward_redemption');
create type public.sync_entity_type as enum (
  'category', 'habit', 'habit_option', 'habit_schedule', 'point_rule',
  'check_in', 'point_ledger', 'habit_pause', 'reward', 'habit_reminder'
);
create type public.sync_operation as enum ('upsert', 'archive', 'delete');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_normalized check (
    username = lower(btrim(username)) and username ~ '^[a-z0-9_]{3,30}$'
  )
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (id, user_id)
);

create table public.habits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category_id uuid,
  name text not null,
  measurement_type public.measurement_type not null,
  sort_order integer not null default 0,
  missed_penalty_enabled boolean not null default false,
  missed_penalty_points integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (id, user_id),
  constraint habits_category_owner_fk foreign key (category_id, user_id)
    references public.categories(id, user_id),
  constraint habits_missed_penalty_nonpositive check (missed_penalty_points <= 0)
);

create table public.habit_options (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  habit_id uuid not null,
  label text not null,
  numeric_value double precision,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (id, user_id),
  unique (id, user_id, habit_id),
  constraint habit_options_habit_owner_fk foreign key (habit_id, user_id)
    references public.habits(id, user_id) on delete cascade
);

create table public.habit_schedules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  habit_id uuid not null,
  schedule_type public.schedule_type not null,
  schedule_config jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  constraint habit_schedules_habit_owner_fk foreign key (habit_id, user_id)
    references public.habits(id, user_id) on delete cascade,
  constraint habit_schedules_config_object check (jsonb_typeof(schedule_config) = 'object')
);

create table public.point_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  habit_id uuid not null,
  operator public.point_rule_operator not null,
  value_min double precision,
  value_max double precision,
  points integer not null,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (id, user_id),
  unique (id, user_id, habit_id),
  constraint point_rules_habit_owner_fk foreign key (habit_id, user_id)
    references public.habits(id, user_id) on delete cascade,
  constraint point_rules_values_match_operator check (
    (operator = 'completed' and value_min is null and value_max is null)
    or (operator = 'between' and value_min is not null and value_max is not null and value_min <= value_max)
    or (operator in ('eq', 'lt', 'lte', 'gt', 'gte') and value_min is not null and value_max is null)
  )
);

create table public.check_ins (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  habit_id uuid not null,
  habit_date date not null,
  option_id uuid,
  measured_value double precision,
  note text,
  awarded_points integer not null,
  matched_rule_id uuid,
  checked_in_at timestamptz not null,
  editable_until timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  unique (user_id, habit_id, habit_date),
  constraint check_ins_habit_owner_fk foreign key (habit_id, user_id)
    references public.habits(id, user_id) on delete cascade,
  constraint check_ins_option_same_habit_fk foreign key (option_id, user_id, habit_id)
    references public.habit_options(id, user_id, habit_id),
  constraint check_ins_rule_same_habit_fk foreign key (matched_rule_id, user_id, habit_id)
    references public.point_rules(id, user_id, habit_id)
);

create table public.point_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_type public.ledger_source_type not null,
  source_id text not null,
  points integer not null,
  reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  unique (user_id, source_type, source_id),
  constraint point_ledger_source_shape check (
    (source_type = 'check_in' and source_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
    or (source_type = 'missed_check_in' and source_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}:[0-9]{4}-[0-9]{2}-[0-9]{2}$' and points <= 0)
    or (source_type = 'reward_redemption' and source_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' and points < 0)
  )
);

create table public.habit_pauses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  habit_id uuid not null,
  start_date date not null,
  end_date date not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  constraint habit_pauses_habit_owner_fk foreign key (habit_id, user_id)
    references public.habits(id, user_id) on delete cascade,
  constraint habit_pauses_ordered_dates check (end_date >= start_date),
  constraint habit_pauses_no_overlap exclude using gist (
    user_id with =,
    habit_id with =,
    daterange(start_date, end_date, '[]') with &&
  )
);

create table public.rewards (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  points_cost integer not null,
  monetary_cap double precision,
  image_key text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  unique (id, user_id),
  constraint rewards_positive_cost check (points_cost > 0),
  constraint rewards_nonnegative_cap check (monetary_cap is null or monetary_cap >= 0)
);

create table public.habit_reminders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  habit_id uuid not null,
  enabled boolean not null default true,
  time_of_day time without time zone not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id),
  unique (user_id, habit_id),
  constraint habit_reminders_habit_owner_fk foreign key (habit_id, user_id)
    references public.habits(id, user_id) on delete cascade
);

create table public.sync_changes (
  sequence bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  entity_type public.sync_entity_type not null,
  entity_id uuid not null,
  operation public.sync_operation not null,
  updated_at timestamptz not null default now()
);

create index categories_user_order_idx on public.categories(user_id, archived_at, sort_order);
create index habits_user_order_idx on public.habits(user_id, archived_at, sort_order);
create index habits_category_idx on public.habits(category_id);
create index habit_options_user_habit_order_idx on public.habit_options(user_id, habit_id, archived_at, sort_order);
create index habit_schedules_user_habit_idx on public.habit_schedules(user_id, habit_id);
create index point_rules_user_habit_order_idx on public.point_rules(user_id, habit_id, archived_at, sort_order);
create index check_ins_user_date_idx on public.check_ins(user_id, habit_date);
create index point_ledger_user_created_idx on public.point_ledger(user_id, created_at);
create index habit_pauses_user_habit_dates_idx on public.habit_pauses(user_id, habit_id, start_date, end_date);
create index rewards_user_order_idx on public.rewards(user_id, archived_at, sort_order);
create index sync_changes_user_sequence_idx on public.sync_changes(user_id, sequence);

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function public.record_sync_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  change_operation public.sync_operation;
begin
  if tg_op = 'DELETE' then
    insert into public.sync_changes(user_id, entity_type, entity_id, operation, updated_at)
    values (old.user_id, tg_argv[0]::public.sync_entity_type, old.id, 'delete', old.updated_at);
    return old;
  end if;
  change_operation := case
    when to_jsonb(new)->>'archived_at' is not null then 'archive'::public.sync_operation
    else 'upsert'::public.sync_operation
  end;
  insert into public.sync_changes(user_id, entity_type, entity_id, operation, updated_at)
  values (new.user_id, tg_argv[0]::public.sync_entity_type, new.id, change_operation, new.updated_at);
  return new;
end;
$$;

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles', 'categories', 'habits', 'habit_options', 'habit_schedules',
    'point_rules', 'check_ins', 'point_ledger', 'habit_pauses', 'rewards',
    'habit_reminders'
  ] loop
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
      table_name || '_set_updated_at',
      table_name
    );
  end loop;
end;
$$;

create trigger categories_sync_change after insert or update or delete on public.categories for each row execute function public.record_sync_change('category');
create trigger habits_sync_change after insert or update or delete on public.habits for each row execute function public.record_sync_change('habit');
create trigger habit_options_sync_change after insert or update or delete on public.habit_options for each row execute function public.record_sync_change('habit_option');
create trigger habit_schedules_sync_change after insert or update or delete on public.habit_schedules for each row execute function public.record_sync_change('habit_schedule');
create trigger point_rules_sync_change after insert or update or delete on public.point_rules for each row execute function public.record_sync_change('point_rule');
create trigger check_ins_sync_change after insert or update or delete on public.check_ins for each row execute function public.record_sync_change('check_in');
create trigger point_ledger_sync_change after insert or update or delete on public.point_ledger for each row execute function public.record_sync_change('point_ledger');
create trigger habit_pauses_sync_change after insert or update or delete on public.habit_pauses for each row execute function public.record_sync_change('habit_pause');
create trigger rewards_sync_change after insert or update or delete on public.rewards for each row execute function public.record_sync_change('reward');
create trigger habit_reminders_sync_change after insert or update or delete on public.habit_reminders for each row execute function public.record_sync_change('habit_reminder');

create view public.wallet_totals with (security_invoker = true) as
select
  user_id,
  coalesce(sum(points), 0)::bigint as available_points,
  coalesce(sum(points) filter (where points > 0), 0)::bigint as lifetime_earned,
  coalesce(abs(sum(points) filter (where points < 0 and source_type = 'reward_redemption')), 0)::bigint as spent_points
from public.point_ledger
group by user_id;

-- Phase 2 repositories should call this RPC for atomic check-in/ledger writes.
-- The conflict target updates points only, preserving the existing ledger id.
create or replace function public.upsert_check_in_with_ledger(
  p_check_in jsonb,
  p_ledger_id uuid
) returns public.check_ins
language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  result public.check_ins;
begin
  if owner_id is null then raise exception 'authentication required' using errcode = '42501'; end if;
  insert into public.check_ins (
    id, user_id, habit_id, habit_date, option_id, measured_value, note,
    awarded_points, matched_rule_id, checked_in_at, editable_until, created_at, updated_at
  ) values (
    (p_check_in->>'id')::uuid, owner_id, (p_check_in->>'habit_id')::uuid,
    (p_check_in->>'habit_date')::date, nullif(p_check_in->>'option_id', '')::uuid,
    (p_check_in->>'measured_value')::double precision, p_check_in->>'note',
    (p_check_in->>'awarded_points')::integer, nullif(p_check_in->>'matched_rule_id', '')::uuid,
    (p_check_in->>'checked_in_at')::timestamptz, (p_check_in->>'editable_until')::timestamptz,
    coalesce((p_check_in->>'created_at')::timestamptz, now()),
    coalesce((p_check_in->>'updated_at')::timestamptz, now())
  )
  on conflict (id) do update set
    option_id = excluded.option_id, measured_value = excluded.measured_value,
    note = excluded.note, awarded_points = excluded.awarded_points,
    matched_rule_id = excluded.matched_rule_id, updated_at = excluded.updated_at
  where public.check_ins.user_id = owner_id
  returning * into result;

  insert into public.point_ledger(id, user_id, source_type, source_id, points, updated_at)
  values (p_ledger_id, owner_id, 'check_in', result.id::text, result.awarded_points, result.updated_at)
  on conflict (user_id, source_type, source_id) do update set
    points = excluded.points, updated_at = excluded.updated_at;
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
  existing_entry public.point_ledger;
  result public.point_ledger;
begin
  if owner_id is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if p_points > 0 then raise exception 'penalty must be non-positive' using errcode = '22003'; end if;
  if not exists (select 1 from public.habits where id = p_habit_id and user_id = owner_id) then
    raise exception 'habit not found' using errcode = 'P0002';
  end if;
  select * into existing_entry from public.point_ledger
    where user_id = owner_id and source_type = 'missed_check_in' and source_id = source_key;
  if found then return existing_entry; end if;
  insert into public.point_ledger(id, user_id, source_type, source_id, points, reason)
  values (p_ledger_id, owner_id, 'missed_check_in', source_key, p_points, 'Missed check-in on ' || p_habit_date::text)
  on conflict (user_id, source_type, source_id) do nothing
  returning * into result;
  if result is null then
    select * into result from public.point_ledger
      where user_id = owner_id and source_type = 'missed_check_in' and source_id = source_key;
  end if;
  return result;
end;
$$;

create or replace function public.redeem_reward(
  p_reward_id uuid,
  p_redemption_id uuid,
  p_ledger_id uuid
) returns public.point_ledger
language plpgsql security definer set search_path = '' as $$
declare
  owner_id uuid := auth.uid();
  selected_reward public.rewards;
  existing_entry public.point_ledger;
  available bigint;
  result public.point_ledger;
begin
  if owner_id is null then raise exception 'authentication required' using errcode = '42501'; end if;
  perform pg_advisory_xact_lock(hashtextextended(owner_id::text, 0));
  select * into existing_entry from public.point_ledger
    where user_id = owner_id and source_type = 'reward_redemption' and source_id = p_redemption_id::text;
  if found then return existing_entry; end if;
  select * into selected_reward from public.rewards
    where id = p_reward_id and user_id = owner_id and archived_at is null;
  if not found then raise exception 'reward not found' using errcode = 'P0002'; end if;
  select coalesce(sum(points), 0) into available from public.point_ledger where user_id = owner_id;
  if available < selected_reward.points_cost then raise exception 'insufficient points' using errcode = 'P0001'; end if;
  insert into public.point_ledger(id, user_id, source_type, source_id, points, reason)
  values (p_ledger_id, owner_id, 'reward_redemption', p_redemption_id::text, -selected_reward.points_cost, 'Reward: ' || selected_reward.name)
  returning * into result;
  return result;
end;
$$;
