# RuleUp Supabase Phase 5 rewards and redemption audit

This audit records Phase 5 implementation and hosted validation completed on
2026-09-11. It covers reward catalog synchronization, private reward images,
reward-redemption execution, redemption-ledger convergence, and wallet effects.
It does not bulk-migrate historical D1 data, make Supabase the default backend,
remove Cloudflare/D1, or begin Phase 6.

## Verified legacy and local behavior

- Rewards use application-generated UUIDs, positive integer point costs,
  optional nonnegative monetary caps, sort order, nullable image keys, and
  archive/restore rather than product-level deletion.
- Reward creation, edits, archive/restore, and image-key changes commit to Drift
  before entering the durable queue. Drift remains the catalog source of truth.
- The legacy R2 flow accepts JPEG/WebP up to 1 MiB. It uploads a replacement,
  updates the reward reference, then attempts old-object cleanup. Reads require
  the user's Worker bearer token. Cloudflare uses
  `rewards/<user UUID>/<object UUID>.<ext>` and owner metadata.
- Legacy local redemption uses a caller-stable redemption UUID as the
  `reward_redemption` ledger source, reads the current local ledger sum, inserts
  one negative row, and relies on `(user_id, source_type, source_id)` for local
  idempotency. Redemption is immutable: there is no cancel, refund, edit, or
  deletion workflow.
- Wallet totals are derived from ledger rows. Only negative
  `reward_redemption` entries contribute to spent points.

## Reward synchronization

Supabase mode now includes `reward` in the typed push/pull entity set. Reward
snapshots preserve stable UUID, owner, name, authoritative point cost, monetary
cap, image object path, sort order, timestamps, and archive state. Generic
reward writes use authenticated JWTs and existing owner RLS. Incremental pull
uses the shared append-only sequence cursor, validates the owner, protects
pending local mutations, and applies upserts/archive/delete tombstones inside a
Drift transaction.

Queue dependency order is upload → reward metadata → redemption → old-image
delete. This ensures a remote reward never receives a new object path before
the object exists and the previous object is not deleted before the new
reference is synchronized.

## Private reward image architecture

The authoritative Supabase Storage key format is:

`<user UUID>/<reward UUID>/<object UUID>.jpg|webp`

`reward-images` remains private, owner-scoped, limited to 1 MiB, and restricted
to JPEG/WebP. PostgreSQL also constrains `rewards.image_key` so its first two
segments match the row owner and reward UUID. Flutter never persists a signed
URL; it stores the object path and creates a five-minute signed URL when an
image is displayed.

Drift schema version 12 adds `reward_image_operations`. Before changing a local
reward reference, replacement bytes, MIME type, stable path, and operation are
committed locally. Upload and deletion queue rows therefore survive restart.
On successful upload, bytes are cleared and the operation becomes an idempotent
completed record. A replacement queues the new upload, the reward reference,
and old deletion separately. Removal clears the reward reference before the
old-object delete is processed. Missing-network failures remain retryable.

Storage objects are not removed by PostgreSQL Auth cascades. Normal replacement
and removal perform authenticated owner-scoped cleanup. Account-wide object
cleanup remains an operational responsibility for Phase 6/account-deletion
orchestration; service-role credentials are not introduced into Flutter.

## Authoritative redemption behavior

Supabase mode does not treat offline redemption as completed spending. Drift
schema version 12 adds `reward_redemption_requests`, which stores only the
stable request UUID, ledger UUID, owner, reward dependency, status, and error
state. No optimistic negative ledger row is created.

The request is durable and retried through the sync queue. A successful remote
RPC emits the authoritative ledger row into `sync_changes`; normal pull then
merges it into Drift and updates the derived wallet. An offline attempt remains
pending with no local deduction, preventing two devices from independently
finalizing spends against stale balances.

Phase 4 deferred `point_ledger` redemption rows now use `redeem_reward`, never a
raw ledger insert. New rows carry an explicit `reward_id`. A legacy deferred row
without it is mapped only when exactly one owned local reward matches its
recorded name and cost; missing dependencies stay retryable and ambiguous
matches become permanent diagnosed integrity failures.

Migration `20260911000800_phase5_rewards_redemption.sql` adds nullable
`point_ledger.reward_id` with an owned composite foreign key, retains legacy-row
compatibility, and recreates `redeem_reward`. The function:

1. derives owner identity from `auth.uid()`;
2. serializes all spending for that owner with an advisory transaction lock;
3. returns an existing stable redemption before doing new work;
4. loads the active owned reward and its authoritative database cost;
5. calculates availability from the ledger inside the same transaction;
6. returns deterministic `P0001` when funds are insufficient; and
7. inserts exactly one negative `reward_redemption` row bound to the reward.

The RPC has no cost parameter. Direct authenticated ledger mutation remains
revoked. Reward pricing cannot be replaced by client input, and both duplicate
deduction and concurrent overspending are prevented by the owner lock plus the
unique ledger-source constraint.

## Hosted disposable-project validation

The dry run listed only `20260911000800_phase5_rewards_redemption.sql`; push
succeeded; all eight local and hosted migration versions match.

Three disposable authenticated users validated:

- own reward create/read/update/archive/restore/delete and cross-user
  invisibility/write denial;
- ownership-spoof rejection;
- private JPEG upload/read/overwrite/delete and owner/reward image reference;
- cross-user read/overwrite/delete/path-upload denial;
- PNG and 1,048,577-byte upload rejection while the bucket stayed private;
- successful 60-point redemption from 80 available;
- ten repeats and twenty concurrent calls with one redemption UUID returning
  one original ledger identity;
- concurrent 80-point spends against 100 available, both across two rewards and
  against one reward with different redemption IDs: exactly one succeeded and
  the other returned `P0001`, leaving 20;
- 50 available against an 80-point reward: `P0001`, no ledger row, and unchanged
  wallet;
- rejection of an invented cost parameter and another user's reward;
- direct redemption-ledger insertion denial;
- exact wallet result after `+50`, `+30`, `-60` redemption, and `-5` missed:
  available 15, lifetime earned 80, spent 60;
- correctly owned, monotonic reward and redemption-ledger change events; and
- successful object, row, and Auth-user cleanup with account-cascade triggers
  still functioning.

The validator held administrative credentials only in process environment
variables and was deleted afterward.

## Phase 6 boundary

Cloudflare/D1 remains the default complete path. Phase 6 must decide historical
data migration, cutover/backfill sequencing, legacy deferred-row review,
account-wide Storage garbage collection, and whether/when Supabase becomes the
default or sole backend. None of those actions occurred in Phase 5.
