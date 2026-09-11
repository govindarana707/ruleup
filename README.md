# RuleUp

RuleUp contains the Flutter application, its production Supabase backend, and
the retained Cloudflare Worker/D1 rollback backend.

## Full local run

1. Start the backend in one terminal:

```powershell
npm install
npm run db:migrate:local
npm run dev -- --ip 0.0.0.0
```

2. Run Flutter in another terminal. The Android emulator uses `10.0.2.2:8787`
by default:

```powershell
flutter run
```

For a physical Android device on the same Wi-Fi network, bind Wrangler to
`0.0.0.0` as above and pass the development computer's LAN IPv4 address:

```powershell
flutter run --dart-define=RULEUP_API_HOST=192.168.1.50
```

Replace `192.168.1.50` with the development computer's LAN IPv4 address. Allow
TCP port `8787` through the computer firewall and keep the Worker bound to
`0.0.0.0`. `RULEUP_API_PORT` can override the development port.

Debug builds default to the local Worker/D1 backend. Production builds default
to Supabase and require both values:

```powershell
flutter build apk --release --dart-define=SUPABASE_URL=https://PROJECT.supabase.co --dart-define=SUPABASE_ANON_KEY=PUBLIC_KEY
```

The explicit rollback build uses
`--dart-define=RULEUP_BACKEND=legacy --dart-define=RULEUP_API_BASE_URL=https://api.example.com`.
There is no dual-write mode. Cleartext HTTP is enabled only in the Android debug
manifest. Configuration remains centralized in `lib/core/config/app_config.dart`.
Keep service-role keys, `.dev.vars`, API tokens, and passwords out of source
control. See `docs/supabase_phase7_cutover.md` before a release or rollback.

The older `RULEUP_HABIT_SYNC_BACKEND` switch remains accepted for rollback
compatibility, but `RULEUP_BACKEND=local|supabase|legacy` is canonical.
