-- Phase 5 binds redemption effects to their authoritative reward and restricts
-- durable image references to the owner/reward/object path convention.
alter table public.point_ledger
add column reward_id uuid;

alter table public.point_ledger
add constraint point_ledger_reward_owner_fk
foreign key (reward_id, user_id)
references public.rewards(id, user_id);

alter table public.point_ledger
drop constraint point_ledger_source_shape;

alter table public.point_ledger
add constraint point_ledger_source_shape check (
  (source_type = 'check_in'
    and reward_id is null
    and source_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')
  or (source_type = 'missed_check_in'
    and reward_id is null
    and source_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}:[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    and points <= 0)
  or (source_type = 'reward_redemption'
    and source_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    and points < 0)
) not valid;

alter table public.point_ledger
validate constraint point_ledger_source_shape;

alter table public.rewards
add constraint rewards_image_key_shape check (
  image_key is null or (
    split_part(image_key, '/', 1) = user_id::text
    and split_part(image_key, '/', 2) = id::text
    and image_key ~* '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}\.(jpg|webp)$'
  )
) not valid;

alter table public.rewards
validate constraint rewards_image_key_shape;

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
  if owner_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_reward_id is null or p_redemption_id is null or p_ledger_id is null then
    raise exception 'stable reward, redemption, and ledger IDs are required' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(owner_id::text, 0));

  select * into existing_entry
  from public.point_ledger
  where user_id = owner_id
    and source_type = 'reward_redemption'
    and source_id = p_redemption_id::text;
  if found then
    return existing_entry;
  end if;

  select * into selected_reward
  from public.rewards
  where id = p_reward_id
    and user_id = owner_id
    and archived_at is null;
  if not found then
    raise exception 'reward not found for authenticated owner' using errcode = 'P0002';
  end if;

  select coalesce(sum(points), 0)
  into available
  from public.point_ledger
  where user_id = owner_id;
  if available < selected_reward.points_cost then
    raise exception 'insufficient points' using errcode = 'P0001';
  end if;

  insert into public.point_ledger(
    id, user_id, source_type, source_id, points, reason, reward_id
  ) values (
    p_ledger_id, owner_id, 'reward_redemption', p_redemption_id::text,
    -selected_reward.points_cost, 'Reward: ' || selected_reward.name,
    selected_reward.id
  )
  returning * into result;
  return result;
end;
$$;

revoke all on function public.redeem_reward(uuid, uuid, uuid)
from public, anon;
grant execute on function public.redeem_reward(uuid, uuid, uuid)
to authenticated;
