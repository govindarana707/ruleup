# RuleUp Supabase Phase 4 check-in and ledger sync audit

This audit records the implementation and hosted validation completed on
2026-09-11. It covers check-ins, point-ledger effects, missed penalties, and
derived wallet totals. Rewards, reward images, and reward-redemption execution
remain Phase 5 work. Cloudflare/D1 remains the default rollback-compatible
transport and Drift remains the local source of truth.

## Verified existing financial behavior

- `CheckInRepository.create` normalizes the habit day, rejects a second
  `(user, habit, day)` check-in, verifies owned habits/options, evaluates the
  current schedule and pauses, snapshots the selected rule and points, and
  writes the check-in, matching ledger effect, and durable queue records inside
  one Drift transaction.
- Check-ins have application-generated UUIDs. Editing is supported only through
  the local edit deadline. It recalculates the rule snapshot and updates the
  existing ledger row rather than appending another award. Product-level
  check-in deletion is not supported.
- Rule selection prefers the greatest positive match, then the most-negative
  penalty, then zero, with sort order and UUID tie breakers. Completed rules
  match any completed check-in; numeric operators use the measured value or the
  selected option's numeric value.
- Missed penalties use `<habit UUID>:YYYY-MM-DD`, must be non-positive, skip
  completed, paused, and non-applicable days, and use insert-or-ignore plus the
  ledger source uniqueness constraint for idempotency.
- Ledger source types remain `check_in`, `missed_check_in`, and
  `reward_redemption`. The unique `(user_id, source_type, source_id)` key is the
  logical exactly-once boundary. A check-in edit preserves the original ledger
  UUID and changes its contribution in place.
- Wallet totals are calculated, never persisted. Available points sum all
  entries; lifetime earned sums positive entries; spent points is the absolute
  sum of negative `reward_redemption` entries only. Negative check-in and missed
  entries reduce availability without becoming spending.
- The legacy Worker validates authenticated ownership and relations, upserts D1
  snapshots, writes its append-only change feed in D1 batches, and reports
  uniqueness conflicts. Its transport and tests remain unchanged.

## Phase 4 PostgreSQL hardening

Migration `20260911000700_phase4_financial_sync.sql` is additive. It removes
authenticated INSERT/UPDATE/DELETE policies and privileges from `check_ins` and
`point_ledger`; authenticated reads remain owner-scoped. Financial mutation is
therefore available only through the explicitly granted RPCs.

`upsert_check_in_with_ledger` derives ownership only from `auth.uid()`, verifies
the habit, option, rule, submitted amount, and rule/value match, and rejects a
non-zero award without an owned matching rule. A client cannot credit itself by
submitting an arbitrary amount. It takes an advisory transaction lock over the
owner/check-in identity, writes the check-in and ledger effect in one database
transaction, and reconciles on `(user_id, source_type, source_id)` without
replacing the first ledger UUID.

The additive `client_updated_at` column is a mutation ordering value distinct
from the trigger-maintained server `updated_at`. Newer client mutations win;
older replays return the current row; identical timestamp/content is
idempotent; differing mutations with the same timestamp return serialization
error `40001` for safe retry. This gives concurrent edits a deterministic
result without relying on request arrival order. The unique habit-day and
ledger-source constraints remain the final database-level duplicate barriers.

`record_missed_check_in_penalty` uses `auth.uid()`, rejects positive values,
verifies the owned habit, serializes by owner/occurrence source, and returns the
single existing row under retry or concurrency. Reward-redemption execution was
not modified.

The Phase 3 account-deletion guard remains in `record_sync_change`. Financial
triggers emit `check_in` and `point_ledger` changes during normal mutations but
do not recreate orphaned feed rows during Auth account cascade cleanup.

## Flutter offline-first synchronization

The Supabase transport now includes `check_in` and `point_ledger` in its
incremental change feed. Queue ordering remains parent-first: habits, options,
rules, pauses, and reminders precede check-ins; ledger work follows check-ins.
Missing remote dependencies remain retryable.

A queued check-in snapshot must have its local check-in ledger row. Both its
check-in queue item and its corresponding ledger queue item converge through
the same atomic check-in RPC, so crash/retry/replay cannot split the remote
financial effect. Independent missed-penalty ledger entries use the missed RPC.
Phase 5 `reward_redemption` ledger rows are deliberately left untouched in the
durable queue when Supabase mode is selected.

Pull uses the existing remote sequence cursor, validates the authenticated
owner, maps stable UUIDs, and applies each batch inside a Drift transaction.
Local queue rows protect pending check-in or ledger edits from being overwritten.
Upserts use conflict reconciliation, so replay does not duplicate either local
table. Financial tombstones are supported; a check-in tombstone also removes
its matching local check-in ledger effect. Realtime is not required.

There are no dual writes. `RULEUP_HABIT_SYNC_BACKEND=supabase` selects the
Supabase transport; omitting it continues to select the complete Worker/D1
transport.

## Hosted disposable-project validation

The migration dry run reported only `20260911000700_phase4_financial_sync.sql`.
It was applied successfully and all seven local/remote migration versions then
matched.

Two disposable Auth users signed in through normal public JWT sessions. Hosted
validation confirmed:

- exact owner-scoped check-in and ledger reads and cross-user invisibility;
- atomic check-in creation with stable check-in and ledger UUIDs;
- twelve identical retries and sixteen simultaneous duplicate creates produced
  one logical ledger effect each;
- concurrent edits converged to the newer mutation and an older replay could
  not replace it;
- `+10` reconciled to `+20` in the same logical ledger row, not `+30`;
- sixteen simultaneous missed-penalty calls produced one `-5` occurrence;
- an arbitrary `100000` credit was rejected with PostgreSQL `22023`;
- direct authenticated ledger INSERT, UPDATE, and DELETE were denied;
- another user's habit could not be used through the RPC;
- representative `+10`, `+20`, `-5` missed, and `-15` redemption-classified
  rows produced `available_points=10`, `lifetime_earned=30`, and
  `spent_points=15`;
- `sync_changes` contained correctly owned, monotonic `check_in` and
  `point_ledger` changes visible only to each owner; and
- both Auth users and all cascaded rows were deleted successfully, proving the
  Phase 3 account-cleanup fix remains compatible.

The disposable validation script was removed. Administrative credentials were
held only in process environment variables and were never written to Flutter or
repository files.

## Automated coverage and remaining scope

Flutter coverage includes local create/edit atomicity, stable ledger identity,
wallet classification, missed-penalty idempotency, queue persistence and retry,
financial RPC mapping, Phase 5 redemption deferral, incremental financial pull,
pending-mutation protection, ownership mapping, and migration security
assertions. Hosted validation supplies the PostgreSQL concurrency and RLS/RPC
coverage that mocks cannot prove. Existing Worker tests protect the legacy path.

Phase 5 must decide how reward catalog rows, private reward images, and atomic
reward-redemption execution enter the Supabase transport. Until then those rows
remain local/queued in Supabase mode and continue to work through Cloudflare/D1
when the default legacy backend is selected.
