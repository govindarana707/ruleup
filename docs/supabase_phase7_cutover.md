# Supabase Phase 7 production cutover

## Transport contract

Exactly one remote transport is active. A release with no backend override uses
Supabase for authentication, sync, rewards, images, and reminders. A debug build
with no override uses the local Worker/D1 development server. The only production
rollback switch is `RULEUP_BACKEND=legacy` with an HTTPS
`RULEUP_API_BASE_URL`. RuleUp never dual-writes. Drift remains the local source
used by the UI and its offline queue behavior is unchanged. Settings displays the
active backend so a build can be verified without inference.

`SUPABASE_URL` and the public anon/publishable key are build inputs. The service
role key is never an app input. It is restricted to the Edge Function environment
and the offline import operator.

## Identity prerequisite

Before freezing D1, every account must have completed the Phase 2 lazy identity
migration. Its Supabase Auth UUID must equal `users.id`, its synthetic email must
be `<UUID>@auth.ruleup.invalid`, and D1 must contain `auth_migrated_at` and the
matching `supabase_auth_email`. Accounts that have not met all three conditions
are rejected by the importer; migrate them through the legacy login path first.
Passwords and D1 password hashes are never exported or imported.

New production sign-up and username login use the `username-auth` Edge Function.
The function resolves the username with its server credential, but the resulting
session is an ordinary owner-scoped Supabase session. Errors do not disclose
whether a username exists.

## One-way D1 export/import

1. Back up D1 and R2, then announce the write-freeze window.
2. Stop legacy writes. Export one JSON bundle per user using owner-filtered D1
   queries. The required top-level shape is `user`, `tables`, and `images`.
   `tables` uses the names in `tool/legacy_d1_import.dart`; rows retain their
   UUIDs, `user_id`, timestamps, archive state, schedule JSON, ledger source IDs,
   reminder times, and reward image keys. Do not export `sessions`, password
   hashes, or D1 `sync_changes` sequence values. Each image entry supplies
   `reward_id`, the stable UUID parsed from its R2 object name as `object_id`,
   the original `source_key`, `mime_type`, SHA-256 digest, and a local backup
   `file` path. The importer rewrites the matching reward reference to the new
   owner/reward/object Storage path.
3. Run the importer once with `--dry-run`, then without it:

   `dart run tool/legacy_d1_import.dart account.json --dry-run`

   `dart run tool/legacy_d1_import.dart account.json`

   Set `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` only in the operator
   environment. Never place them in the bundle or repository.
4. Repeat the real command. It must report `Already imported`. Keep D1/R2 frozen
   and retained through the rollback window.

The importer validates normalized identity, UUIDs, timestamps, every owner and
foreign reference, unique ledger source identities, redemption debits, reward
image ownership, MIME, and size. It creates a SHA-256 account checkpoint before
rows are written. Existing IDs are compared field-by-field: an identical row is
skipped; an owner mismatch or changed row aborts. A failed run stays
`in_progress`, so the same snapshot resumes at the first missing row. A changed
snapshot is rejected. Stable primary keys and the ledger `(user_id, source_type,
source_id)` constraint prevent duplicate check-in, penalty, or redemption effects.
Because legacy D1 redemption rows predate `reward_id`, the importer links them
only when exactly one owned reward matches both the recorded `Reward: <name>`
reason and debit amount; missing or ambiguous matches are rejected.

The target triggers create a new monotonic Supabase `sync_changes` feed while
rows are imported. D1 sequence values are intentionally not portable. Device
cursors remain backend-scoped, so the first Supabase pull replays the imported
state safely into Drift.

Legacy R2 objects are copied to the owner-scoped key
`<user>/<reward>/<object>.(jpg|webp)`. The reward row in the export must use that
target key. Unsupported, oversized, malformed, missing, or cross-owner objects
abort instead of being silently dropped.

## Cutover verification

Apply all hosted migrations and deploy `username-auth` with JWT verification
disabled (it is the session-issuing endpoint). Keep `cleanup-reward-images` JWT
verification enabled. Verify a fresh sign-up/login, an imported account, a repeat
and interrupted import, then round-trip categories, habits, options, schedules,
rules, check-ins, ledger entries, pauses, rewards, redemptions, images, and
reminders. Confirm a second user cannot see or mutate any of them. Build the
release without `RULEUP_BACKEND`; Settings must show `Supabase production`.

## Rollback

The legacy code is retained, but rollback is an operator decision—not an
automatic network fallback. Automatic fallback would split writes.

If no Supabase mutation occurred after cutover, distribute the last verified
legacy build (or build with `RULEUP_BACKEND=legacy` and the HTTPS Worker URL) and
unfreeze the preserved D1/R2 snapshot. Verify Settings says `Legacy
Cloudflare/D1`.

If Supabase accepted any mutation, first stop writes and reconcile the Supabase
delta into a copy of the D1/R2 snapshot with stable IDs and ledger source keys.
Validate counts and wallet totals, promote that copy, and only then enable the
legacy build. Do not simply flip the switch: without dual writes, D1 is stale.
Device Drift queues are useful recovery evidence but are not a complete
multi-device rollback ledger.

Rollback does not delete Supabase data. Returning to Supabase uses the same
production build and backend-scoped cursor; no reverse or repeated historical
import is run.

## Release gates and residual risks

The release gate includes Flutter analysis/tests, backend typecheck/tests,
hosted migration dry-run/apply state, Edge Function tests, two-account RLS,
credential scanning, and `git diff --check`. Operational risks are accounts that
missed the identity prerequisite, an incomplete R2 backup, and rolling back after
new Supabase writes without reconciliation. These must be measured and signed off
before release.
