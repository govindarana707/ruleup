-- RuleUp Auth users carry the normalized username in raw_user_meta_data.
-- The trigger is deliberately insert-only: username changes do not alter the
-- immutable synthetic authentication email or authentication identity.
create or replace function public.create_ruleup_profile_for_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_username text := new.raw_user_meta_data->>'username';
begin
  if normalized_username is null then
    return new;
  end if;
  insert into public.profiles(id, username, created_at, updated_at)
  values (new.id, normalized_username, new.created_at, new.created_at)
  on conflict (id) do update set
    username = excluded.username,
    updated_at = excluded.updated_at;
  return new;
end;
$$;

revoke all on function public.create_ruleup_profile_for_auth_user() from public, anon, authenticated;

create trigger ruleup_auth_user_profile
after insert on auth.users
for each row execute function public.create_ruleup_profile_for_auth_user();
