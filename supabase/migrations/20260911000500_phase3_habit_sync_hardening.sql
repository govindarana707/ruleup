-- Phase 3: preserve explicit offline mutation timestamps and optimize the
-- authenticated, entity-filtered incremental habit-domain change feed.

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.updated_at is not distinct from old.updated_at then
    new.updated_at = now();
  end if;
  return new;
end;
$$;

create index if not exists sync_changes_user_entity_sequence_idx
on public.sync_changes(user_id, entity_type, sequence);

-- Keep private tables protected even if an earlier deployment changed flags.
alter table public.categories force row level security;
alter table public.habits force row level security;
alter table public.habit_options force row level security;
alter table public.habit_schedules force row level security;
alter table public.point_rules force row level security;
alter table public.habit_pauses force row level security;
alter table public.habit_reminders force row level security;
alter table public.sync_changes force row level security;
