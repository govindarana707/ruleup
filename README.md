# RuleUp

RuleUp contains the Flutter application and a Cloudflare Worker/D1 backend.

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

For a non-local environment, provide the complete URL:

```powershell
flutter run --dart-define=RULEUP_API_BASE_URL=https://api.example.com
```

Release builds require an explicit HTTPS `RULEUP_API_BASE_URL`; RuleUp has no
hardcoded production endpoint. Cleartext HTTP is enabled only in the Android
debug manifest. The app checks `/health` on startup and shows a retry screen in
development when the Worker cannot be reached. Configuration remains centralized
in `lib/core/config/app_config.dart`. Keep `.dev.vars`, API tokens, passwords,
and other secrets out of source control.
