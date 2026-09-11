# RuleUp backend foundation

Cloudflare Worker and D1 foundation for RuleUp. The backend exposes `GET
/health` plus username/password session authentication under `/auth`.

## Local setup

```sh
npm install
npm run db:migrate:local
npm run typecheck
npm test
npm run dev
```

The local Worker is available at the address printed by Wrangler. Its health
endpoint returns `{"status":"ok"}`.

For a future remote deployment, create the D1 database with
`npx wrangler d1 create ruleup-db`, then replace the placeholder
`database_id` in `wrangler.jsonc` with the returned ID. Do not commit API tokens,
passwords, `.dev.vars`, or other secrets.

Usernames are trimmed, NFKC-normalized, and lowercased before lookup or storage.
Passwords are stored only as salted PBKDF2 hashes. Authentication uses opaque
bearer tokens; only token hashes are stored, and logout revokes the server-side
session. Treat returned bearer tokens as secrets.

## Optional Supabase Auth transition

Legacy authentication remains authoritative unless both `SUPABASE_URL` and
`SUPABASE_SERVICE_ROLE_KEY` are configured as Worker secrets. For local-only
testing, copy `.dev.vars.example` to `.dev.vars` and replace its placeholders.
Never commit `.dev.vars` or the service-role key. For a deployed development
Worker, configure values with:

```sh
npx wrangler secret put SUPABASE_URL
npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY
```

After a valid legacy password is verified, the Worker lazily creates the
matching Supabase Auth identity using the existing RuleUp UUID. Any Supabase
failure leaves legacy login available. New registrations remain legacy-only in
Phase 2 and migrate on a later successful login.
