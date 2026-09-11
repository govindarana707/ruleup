# RuleUp Phase 2 authentication and identity foundation

This audit reflects repository code inspected on 2026-09-11. Phase 2 does not
move domain data or make Supabase the production source of truth.

## Verified legacy authentication

Registration posts `username` and `password` to `POST /auth/signup`. The Worker
trims the username, applies Unicode NFKC normalization, lowercases it, and then
requires `^[a-z0-9_]{3,30}$`. Passwords must contain 12–128 JavaScript string
characters. The Worker—not Flutter—creates the application UUID with
`crypto.randomUUID()`.

Passwords use PBKDF2-HMAC-SHA256 with 600,000 iterations, a random 16-byte salt,
and a 256-bit result. D1 stores
`pbkdf2_sha256$600000$<base64url salt>$<base64url hash>`. Verification derives
the candidate hash and compares equal-length bytes without early exit. Plaintext
passwords are neither returned nor persisted.

`POST /auth/login` resolves the normalized username and verifies its hash.
Sessions use 32 random bytes encoded as a 43-character base64url bearer token.
Only a SHA-256 token hash is stored in D1. Sessions last 30 days, may be revoked,
and are accepted only when unexpired and unrevoked. `POST /auth/logout` revokes
the current token; `GET /auth/me` joins the hashed session to its user.

Flutter's `ApiAuthRepository` stores the legacy bearer token in secure storage,
calls `/auth/me` at startup, and mirrors the returned UUID into Drift's
`local_users`. `AuthController` is a Riverpod `AsyncNotifier`; its providers
construct the HTTP client, token storage, local user store, and repository.
Current offline domain rows remain in Drift, while initial user restoration
still requires the legacy `/auth/me` request.

D1 auth tables are `users(id, username, password_hash, created_at, updated_at,
auth_migrated_at, supabase_auth_email)` and `sessions(id, user_id, token_hash,
expires_at, created_at, revoked_at)`. Authentication tests cover normalization,
duplicates, hashing, login failure/success, current-user lookup, logout,
restoration, secure token handling, and local user provisioning.

## Identity strategy

The Supabase Auth server's administrative create-user payload supports an
explicit `id`. Its current implementation parses `AdminUserParams.Id`, requires
a UUIDv4, rejects the nil UUID, and assigns it before inserting the user. The
typed Flutter admin attributes do not expose that field, so RuleUp uses the
server-side Admin REST endpoint rather than client-side admin SDK calls. See the
[Supabase Auth server implementation](https://github.com/supabase/auth/blob/master/internal/api/admin.go#L25-L38)
and its [explicit-ID validation](https://github.com/supabase/auth/blob/master/internal/api/admin.go#L481-L493).

For every migrated account:

```text
D1 users.id == Supabase auth.users.id == public.profiles.id == auth.uid()
```

The unauthenticated request never supplies this UUID. The Worker first resolves
the normalized username to the D1 user and derives the UUID from that verified
record. An existing Supabase UUID is accepted only when its immutable synthetic
email and protected app metadata both identify the same RuleUp legacy UUID.

## Username strategy

Supabase email/password authentication uses:

```text
<lowercase legacy UUID>@auth.ruleup.invalid
```

`.invalid` is a reserved non-deliverable top-level domain, so these internal
addresses cannot accidentally receive email. Users never see or enter them.
The email is derived from immutable identity—not username—so a future display
username change cannot break login. D1 and `profiles.username` retain the exact
existing normalization and uniqueness rules. Username-to-identity resolution
continues in the trusted Worker and never exposes an identity lookup endpoint.

## Lazy password migration

For an unmigrated legacy account, the Worker:

1. resolves the normalized username in D1;
2. verifies the existing PBKDF2 password;
3. creates `auth.users` through the server-only Admin endpoint using the exact
   D1 UUID, synthetic email, submitted password, and protected legacy metadata;
4. verifies/reconciles an already-created exact identity on retry;
5. upserts `profiles.id` and username through server-side REST;
6. signs in with the synthetic email and the just-verified password;
7. writes `auth_migrated_at` and `supabase_auth_email` in the same D1 batch that
   persists the new legacy session; and
8. returns the Supabase access/refresh session alongside the legacy session.

The password exists only in request memory and outbound TLS request bodies. It
is never logged, returned, or stored as plaintext. If creation succeeds but a
later step fails, the D1 marker remains null; retry verifies the exact existing
identity, refreshes its password and metadata, and continues without creating a
duplicate.

## Transitional flows

```text
Already migrated
username + password -> D1 username lookup -> Supabase password sign-in
                    -> matching UUID session -> legacy session + Supabase session

Unmigrated legacy user
username + password -> PBKDF2 verification -> exact-UUID Supabase creation
                    -> profile synchronization -> Supabase sign-in
                    -> migration marker -> legacy session + Supabase session

Supabase unavailable or migration fails
username + password -> PBKDF2 verification -> legacy session only
```

For a migrated account, a definitive Supabase invalid-credentials response is
not bypassed with the stale legacy hash. Network, Supabase-service,
identity-conflict, and configuration failures are represented separately and
may fall back to a valid legacy password so transient Supabase problems do not
lock the user out. Legacy D1 failures remain ordinary backend failures rather
than being mislabeled as Supabase failures.

Flutter maps the optional Supabase response into a provider-neutral
`AuthSession`, verifies its user ID against the legacy `AuthUser`, and stores the
refresh/access session separately in secure storage. Restoration validates the
same identity and allows the Supabase SDK to refresh expired access tokens.
Malformed, expired, or mismatched Supabase state is cleared without invalidating
the still-authoritative legacy session. Logout clears both stores.

## New registrations

New registrations remain legacy-only (option A) during Phase 2. This preserves
the production signup transaction and prevents a failed external dual write
from creating an unusable half-account. The server-created UUID is still ready
for exact preservation. The account lazily migrates on its next successful
login when the optional bridge is enabled. Phase 3 may change the identity
authority only after staging validation.

## Profile synchronization

The Phase 2 PostgreSQL migration adds an insert-only `auth.users` trigger. When
RuleUp `user_metadata.username` is present, it idempotently creates the matching
`profiles` row. The Worker also performs an explicit profile upsert after Admin
creation, making partial retries easy to reason about. The trigger does not
derive authentication email from mutable username and ignores unrelated Auth
users that do not carry RuleUp username metadata.

## Security and rollback

`SUPABASE_SERVICE_ROLE_KEY` exists only in the Worker environment. Flutter
contains only `SUPABASE_ANON_KEY`. Admin request headers, password hashes,
passwords, and tokens are never logged. Generic invalid-credential responses
preserve the existing username-enumeration behavior. There is no new endpoint
that accepts a user ID, so an unauthenticated caller cannot select a victim UUID.

The existing service has no explicit application-level login rate limiter;
Phase 2 adds no public route or additional unauthenticated capability, so abuse
behavior is not worsened. Rate limiting remains an operational improvement to
consider before making Supabase the authority.

Rollback is configuration-only: remove the Worker Supabase secrets and omit the
Flutter Supabase build defines. Legacy D1 login, sessions, `/auth/me`, sync, and
all Drift data continue unchanged. Migration markers and Supabase identities may
remain dormant and need not be deleted.

## Disposable validation commands

No Supabase CLI, PostgreSQL client, Docker runtime, or authorized disposable
project was available during implementation. Later validation should use a
non-production checkout and project:

```sh
npx supabase start
npx supabase db reset
npm --prefix backend run typecheck
npm --prefix backend test
flutter test
```

Then create a disposable legacy user, invoke the login bridge, and verify in SQL
that `auth.users.id = profiles.id = users.id`, RLS rejects another authenticated
UUID, retries do not add users, and the returned JWT `sub` equals the legacy ID.
