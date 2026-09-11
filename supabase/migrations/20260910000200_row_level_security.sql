-- Every application-owned row is private to auth.uid().

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'profiles', 'categories', 'habits', 'habit_options', 'habit_schedules',
    'point_rules', 'check_ins', 'point_ledger', 'habit_pauses', 'rewards',
    'habit_reminders', 'sync_changes'
  ] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('alter table public.%I force row level security', table_name);
  end loop;
end;
$$;

create policy profiles_select_own on public.profiles for select using (id = auth.uid());
create policy profiles_insert_own on public.profiles for insert with check (id = auth.uid());
create policy profiles_update_own on public.profiles for update using (id = auth.uid()) with check (id = auth.uid());

do $$
declare
  table_name text;
begin
  foreach table_name in array array[
    'categories', 'habits', 'habit_options', 'habit_schedules', 'point_rules',
    'check_ins', 'point_ledger', 'habit_pauses', 'rewards', 'habit_reminders'
  ] loop
    execute format('create policy %I on public.%I for select using (user_id = auth.uid())', table_name || '_select_own', table_name);
    execute format('create policy %I on public.%I for insert with check (user_id = auth.uid())', table_name || '_insert_own', table_name);
    execute format('create policy %I on public.%I for update using (user_id = auth.uid()) with check (user_id = auth.uid())', table_name || '_update_own', table_name);
    execute format('create policy %I on public.%I for delete using (user_id = auth.uid())', table_name || '_delete_own', table_name);
  end loop;
end;
$$;

-- Clients can pull their change feed. Inserts are produced only by trusted
-- table triggers; clients cannot forge, edit, or delete cursor history.
create policy sync_changes_select_own on public.sync_changes
for select using (user_id = auth.uid());

grant usage on schema public to authenticated;
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.categories, public.habits,
  public.habit_options, public.habit_schedules, public.point_rules,
  public.habit_pauses, public.rewards, public.habit_reminders to authenticated;
grant select on public.check_ins, public.point_ledger, public.sync_changes,
  public.wallet_totals to authenticated;
revoke all on function public.upsert_check_in_with_ledger(jsonb, uuid) from public, anon;
revoke all on function public.record_missed_check_in_penalty(uuid, date, integer, uuid) from public, anon;
revoke all on function public.redeem_reward(uuid, uuid, uuid) from public, anon;
grant execute on function public.upsert_check_in_with_ledger(jsonb, uuid) to authenticated;
grant execute on function public.record_missed_check_in_penalty(uuid, date, integer, uuid) to authenticated;
grant execute on function public.redeem_reward(uuid, uuid, uuid) to authenticated;

revoke all on public.profiles, public.categories, public.habits,
  public.habit_options, public.habit_schedules, public.point_rules,
  public.check_ins, public.point_ledger, public.habit_pauses, public.rewards,
  public.habit_reminders, public.sync_changes, public.wallet_totals from anon;
