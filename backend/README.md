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
