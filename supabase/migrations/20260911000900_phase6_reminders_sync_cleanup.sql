-- Phase 6 keeps reminder scheduling metadata cloud-backed while notification
-- permission and delivery state remain device-only.
alter table public.habit_reminders force row level security;
alter table public.sync_changes force row level security;

alter table public.habit_reminders
add constraint habit_reminders_minute_precision check (
  date_part('second', time_of_day) = 0
) not valid;

alter table public.habit_reminders
validate constraint habit_reminders_minute_precision;

-- Application clients can read their own feed through RLS; only trusted table
-- triggers append events.
revoke insert, update, delete, truncate on public.sync_changes
from public, anon, authenticated;
grant select on public.sync_changes to authenticated;

-- Same-owner updates must retain the complete owner/reward/object shape.
drop policy if exists reward_images_update_own on storage.objects;
create policy reward_images_update_own on storage.objects
for update to authenticated
using (
  bucket_id = 'reward-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'reward-images'
  and (storage.foldername(name))[1] = auth.uid()::text
  and name ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|webp)$'
);
