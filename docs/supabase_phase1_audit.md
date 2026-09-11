# RuleUp Phase 1 audit and migration map

This document records the repository state audited on 2026-09-10. It is a
design artifact only: Cloudflare remains the active backend and no production
data is migrated by these files.

## Existing architecture

- Flutter uses Riverpod 3 providers/notifiers and feature-oriented folders.
- Drift/SQLite is the offline-first source used by repositories. Every domain
  repository scopes reads and writes by `user_id`, then enqueues mutations in
  `sync_queue`. `sync_metadata` stores each user's pull cursor.
- A Cloudflare Worker exposes `GET /health`, `/auth/signup`, `/auth/login`,
  `/auth/me`, `/auth/logout`, `POST /sync/:entity`, `GET /sync/pull`, and
  authenticated `POST|GET|DELETE /reward-images[/key]` endpoints.
- The Worker persists remote state in D1. Push uses last-write-wins by
  `updated_at`; pull reads the append-only `sync_changes` sequence. Server
  relation checks prevent cross-user and cross-habit references.
- Authentication is custom username/password authentication. Usernames are
  trimmed, NFKC-normalized and lowercased. D1 stores PBKDF2-SHA256 password
  hashes. Opaque 32-byte bearer tokens are stored only as hashes in `sessions`
  and expire after 30 days. IDs are `crypto.randomUUID()` UUID strings. Flutter
  stores the bearer token in secure storage and mirrors the authenticated user
  ID into `local_users`.
- R2 reward images are private. The Worker accepts JPEG/WebP up to 1 MiB and
  stores `rewards/<user UUID>/<object UUID>.<ext>` with owner metadata. The
  `rewards.image_key` value is synchronized with the rest of the reward row.

## Domain flows

- Habit CRUD is split across category, habit, option, schedule, point-rule,
  pause, and reminder repositories. Archivable entities use `archived_at`;
  schedules, pauses, and reminders can be deleted.
- Check-in creation validates ownership and schedule/pause applicability,
  snapshots the winning point rule into `awarded_points`/`matched_rule_id`, and
  sets the edit deadline. The same local Drift transaction reconciles one
  `point_ledger` row whose source is the check-in ID. An edit updates that row's
  points without changing its ID.
- Missed penalties use the stable source key `<habit UUID>:YYYY-MM-DD`, are
  non-positive, and are inserted idempotently. Reward redemption uses a caller-
  stable UUID source key, checks the current ledger sum, and writes a negative
  `reward_redemption` entry idempotently.
- Wallets are never stored. `available_points` is the sum of every ledger row;
  `lifetime_earned` is the sum of positive rows; `spent_points` is the absolute
  sum of negative `reward_redemption` rows only. Negative check-ins and missed
  penalties reduce availability but are not counted as spending.

## D1 to PostgreSQL mapping

All D1 `TEXT` UUIDs become PostgreSQL `uuid` except `point_ledger.source_id`,
which must remain `text` because missed-check-in keys combine a UUID and date.
D1 ISO-8601 timestamp text becomes `timestamptz`; habit-day text becomes
`date`; `time_of_day` text becomes `time`; SQLite `REAL` becomes `double
precision`; and 0/1 integers become `boolean`. Client-provided UUIDs remain
accepted even though PostgreSQL supplies `gen_random_uuid()` defaults.

| D1 source | Supabase target | Key and relation mapping | Uniqueness / indexes | Nulls, defaults, conversions |
|---|---|---|---|---|
| `users` | Supabase `auth.users` plus `public.profiles` | User UUID remains the identity; `profiles.id -> auth.users.id` cascade | username unique | password hashes move to Supabase Auth, never `profiles`; normalized username remains required; timestamps use `timestamptz` |
| `sessions` | Supabase Auth-managed sessions | managed auth user relation | token/session uniqueness is managed by Auth | custom `token_hash`, expiry, and revocation columns are not copied into a public table |
| `categories` | `public.categories` | UUID PK; `user_id -> auth.users` cascade; `(id,user_id)` retained for owned FKs | `(user_id,archived_at,sort_order)` | `sort_order=0`; archive nullable; timestamps default to `now()` |
| `habits` | `public.habits` | UUID PK; owned user/category FKs | user/order and category indexes | measurement enum; missed-enabled boolean default false; penalty integer default 0 and <= 0; category/archive nullable |
| `habit_options` | `public.habit_options` | UUID PK; owned habit FK cascade; `(id,user_id,habit_id)` supports same-habit check-in FK | user/habit/archive/order index | numeric value and archive nullable; order 0; REAL to double precision |
| `habit_schedules` | `public.habit_schedules` | UUID PK; owned habit FK cascade | user/habit index | schedule enum; JSON string becomes validated `jsonb` object |
| `point_rules` | `public.point_rules` | UUID PK; owned habit FK cascade; same-habit lookup key retained | user/habit/archive/order index | operator enum; nullable min/max doubles; check constraint preserves each operator's value shape |
| `check_ins` | `public.check_ins` | UUID PK; owned habit FK cascade; option and rule FKs require the same user and habit | unique `(user_id,habit_id,habit_date)`; user/date index | day `TEXT` to `date`; timestamps to `timestamptz`; option/value/note/rule nullable |
| `point_ledger` | `public.point_ledger` | UUID PK; user FK cascade; polymorphic source remains type + text ID | unique `(user_id,source_type,source_id)` prevents duplicate awards; user/created index | enum source; reason nullable; points integer; `updated_at` retained from D1 sync contract |
| `habit_pauses` | `public.habit_pauses` | UUID PK; owned habit FK cascade | user/habit/date index; GiST exclusion prevents overlapping inclusive date ranges | dates use `date`; `end_date >= start_date` |
| `rewards` | `public.rewards` | UUID PK; user FK cascade | user/archive/order index | cost > 0; nullable nonnegative double cap; nullable image key and archive; order 0 |
| `habit_reminders` | `public.habit_reminders` | UUID PK; owned habit FK cascade | unique `(user_id,habit_id)` | enabled integer becomes boolean; `HH:mm` text becomes `time`; enabled defaults true to match Drift (D1 always supplied it) |
| `sync_changes` | `public.sync_changes` | identity `bigint` sequence; user FK; entity UUID | `(user_id,sequence)` | SQLite AUTOINCREMENT becomes identity; entity/operation checks become enums; timestamp becomes `timestamptz` |

The local-only Drift tables do not migrate: `local_users` remains the local
auth-user mirror, `sync_queue` remains the durable offline outbox, and
`sync_metadata` remains local pull-cursor state.

## PostgreSQL behavior and transaction boundaries

- `wallet_totals` is a security-invoker view over the ledger; there is no
  mutable balance column or table.
- `upsert_check_in_with_ledger` is the required Phase 2 write boundary. It
  creates/reconciles the check-in and its award atomically. Its conflict update
  changes points on the existing source row and deliberately does not replace
  the ledger ID.
- Authenticated clients have read-only table privileges for `check_ins` and
  `point_ledger`; writes go through the ownership-checking atomic functions.
  `record_missed_check_in_penalty` provides the idempotent penalty boundary.
- The ledger source uniqueness constraint makes duplicate awards impossible.
  Source-shape checks keep missed penalties non-positive and redemptions
  negative and distinguishable.
- `redeem_reward` takes stable redemption and ledger UUIDs, serializes spending
  per user with an advisory transaction lock, calculates availability from the
  ledger, and writes exactly one redemption row.
- Table triggers normalize `updated_at` and append `sync_changes`. PostgreSQL
  foreign keys and a pause exclusion constraint replace application-only or
  SQLite-specific integrity behavior.

## Authentication decision before Phase 2

Supabase RLS requires the JWT subject returned by `auth.uid()` to equal each
row's `user_id`. Existing D1 user UUIDs therefore need an explicit identity
migration strategy. The recommended path is to import users into Supabase Auth
while preserving their UUIDs, then force a password reset because the existing
PBKDF2 credential representation must not be exposed to the app. Until that is
tested in a staging project, custom Worker auth and D1 remain authoritative.

## Tests audited

Flutter tests cover schema creation/upgrades, user isolation, auth/session
client behavior, sync queue deduplication and pull merging, full entity
serialization, category/habit/option/schedule/rule/pause/reminder CRUD,
check-in snapshots and edit reconciliation, missed-penalty idempotency, wallet
totals, reward redemption idempotency/insufficient funds, and UI/integration
flows. Worker Vitest suites cover health, custom authentication, and sync.
There is not yet a Supabase-connected integration test because no project or
credentials are part of Phase 1.
