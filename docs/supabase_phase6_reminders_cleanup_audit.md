# RuleUp Supabase Phase 6 reminders and cleanup audit

This audit records the remaining support-domain and operational work for Phase
6. It does not start Phase 7, migrate historical D1 data, remove the legacy
transport, or make Supabase the default backend.

## Existing support-domain behavior

- `habit_reminders` is the only notification-related domain that is
  cloud-backed. It stores one owner-scoped reminder per habit, an enabled flag,
  and local wall-clock `HH:mm` time. Its UUID is stable across Drift and the
  selected remote transport.
- Reminder create, update, and delete commit to Drift and the durable queue
  before best-effort local notification rescheduling. Notification failures do
  not roll back persisted data.
- Habit, schedule, pause, and reminder changes can all affect local delivery.
  Pulled changes collect affected habit UUIDs transactionally and reschedule
  them after each successfully merged page.
- Notification permission, platform availability, scheduled OS notification
  identifiers, and delivery state are device-only. They are not synchronized.
- Settings currently displays device permission and local sync health. The
  authenticated profile is already Supabase-owned; no additional account
  setting exists in the current model that should become cloud metadata.
- Local sync cursors and queue diagnostics are device-specific operational
  metadata and remain in Drift. Settings now reads the cursor key exposed by
  the active transport, so Supabase sync health no longer consults the legacy
  Cloudflare cursor.

## Reminder synchronization hardening

Reminder push remains authenticated, owner-scoped, timestamp conflict-aware,
and idempotent. When two offline devices create different reminder UUIDs for
the same owner/habit pair, the existing Supabase row becomes canonical. A newer
local value updates that canonical row without replacing its UUID. Pull removes
the superseded local UUID only after its local mutation is no longer pending,
then merges the canonical row and reschedules the affected habit.

The Phase 6 migration reasserts forced RLS and least-privilege `sync_changes`
access, and constrains remote reminder times to minute precision. The existing
owned habit foreign key and unique `(user_id, habit_id)` constraint remain the
authoritative ownership and one-reminder boundary.

## Local retention

Completed reward image operations and completed redemption requests are kept
for 30 days. Cleanup runs after a successful push/pull synchronization and is
scoped to the current local user.

An image operation is pruned only when it is completed, older than the cutoff,
and no upload/delete queue item still references it. A completed redemption
request is pruned only when it is older than the cutoff, has no queued request,
and its exact authoritative `reward_redemption` ledger row is present locally.
Pending, retryable, permanently failed, rejected, recent, queued, or
not-yet-converged work is retained.

## Account-scoped Storage cleanup

`cleanup-reward-images` is an authenticated Edge Function with no caller-owned
user parameter. It derives the owner from the bearer JWT, lists only that
owner's UUID path through existing Storage RLS, and removes matching JPEG/WebP
objects through the Storage API in bounded batches. Repeating cleanup is safe.
It uses the project anon key with the caller's JWT, not a service-role key.

The cleanup primitive is intentionally not wired to new account-deletion UI.
Future account deletion orchestration must invoke it while the user session is
still valid and before deleting the Auth user.

## Hosted disposable-project validation

The Phase 6 dry run selected only migration `20260911000900`; applying it and
deploying `cleanup-reward-images` succeeded. Disposable authenticated users
validated own reminder create/read/update/delete, cross-user invisibility and
write denial, ownership-spoof rejection, minute-only time enforcement, and the
one-reminder-per-owner/habit conflict boundary.

Reminder, schedule, and pause change events were correctly owned and strictly
monotonic; replay after the last sequence returned no duplicates and another
user could not observe them. The cleanup function rejected unauthenticated
access, removed only the caller's physical reward image through the Storage
API, preserved another user's object, and returned zero on replay. All test
objects, rows, and Auth users were removed afterward.

## Phase 7 boundary

Historical D1 migration, transport cutover, making Supabase the default,
account-deletion product UX, and any broader server retention policy remain
Phase 7 decisions. Cloudflare/D1 remains rollback-compatible.
