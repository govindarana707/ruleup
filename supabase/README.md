# RuleUp Supabase foundation

These migrations define the staged Supabase target through Phase 6. They have
been applied to an authorized disposable hosted project, but they do not replace
the Worker, D1 migrations, R2 binding, Drift repositories, or default sync
transport.

Apply the files in `migrations/` to other disposable Supabase projects in
filename order. The third migration creates the private `reward-images`
bucket with a 1 MiB limit and JPEG/WebP allowlist. Objects use:

```text
<auth user UUID>/<reward UUID>/<object UUID>.jpg
<auth user UUID>/<reward UUID>/<object UUID>.webp
```

Only the owning authenticated user may read or mutate objects. Private images
must be displayed with authenticated downloads or short-lived signed URLs;
never turn this bucket public.

The Flutter client foundation is dormant unless both values are supplied:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable-anon-key>
```

The anon key is build configuration, not a service-role secret. Never place a
service-role key in Flutter. Cloudflare remains the default habit transport. To
exercise the phased Supabase transport, opt in:

```sh
flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<publishable-anon-key> \
  --dart-define=RULEUP_HABIT_SYNC_BACKEND=supabase
```

Supabase mode handles categories, habits, options, schedules, point rules,
pauses, reminders, check-ins, point-ledger effects, rewards, private reward
images, and atomic reward redemption. Check-ins and redemption use trusted RPCs;
financial tables are directly read-only to authenticated clients; wallet totals
remain derived from ledger rows. Reward images use durable offline operations
and private five-minute signed URLs. There are no dual writes. Omit the backend
flag (or set it to `cloudflare`) to use the complete legacy Worker/D1 sync path.

Phase 6 keeps reminder time/enabled metadata owner-scoped while notification
permission and OS delivery state stay device-only. It also adds 30-day local
retention for safely converged reward operations and the authenticated
`cleanup-reward-images` Edge Function. The function derives its owner from the
session JWT and deletes through the Storage API; invoke it before Auth deletion
in any future account-deletion orchestration.

Deploy the cleanup primitive separately from database migrations:

```sh
npx supabase functions deploy cleanup-reward-images
```

See the phase audit documents under `docs/` for schema, authentication, and
habit-sync decisions.
