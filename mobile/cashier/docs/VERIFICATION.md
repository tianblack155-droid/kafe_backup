# Verification handoff

## Executed on Linux build host

- Flutter3.47.4 / Dart3.13.3, Android SDK36, JDK17.
- `flutter analyze`: no issues.
- `flutter test --concurrency=1`:34 tests passed; live test skipped by default.
- Explicit live test:1 passed against real preview Supabase Auth + REST + native WSS.
  It verifies order_items content, list, review, cash, complete and exact checkout retry.
  Temporary Auth user/profile/orders were removed and exact absence verified.
- `flutter build apk --debug`:APK compiled, no release signing/production approval.
- Independent source review of blockers passed after fixes. Live follow-up also caught
  a same-user Auth event race; identity synchronization was fixed and live test rerun.

## Fixed review blockers

1. Parse backend `order_items` rather than checkout payload `items`.
2. Native WSS handshake refuses redirects before token subscription can be sent.
3. Authorization denial invalidates pending successful snapshots.
4. Business/token acquisition deadlines; obsolete refresh work detaches on session change.
5. Password authentication has a transport-level deadline before SDK session installation,
   so a late timed-out response cannot install a session.
6. Cash intent is saved encrypted before sending. Uncertain responses retain exact
   order/version/received amount across relaunch; differing retries are blocked.
   Newer committed unpaid version safely invalidates an old version intent because
   backend review/payment serialize on the order row and paid cannot become unpaid.
   Amounts above backend1e12 cap are rejected before persistence/send.
7. UI shows unresolved cash amount/version and an exact-retry action; never request
   customer payment again solely because a network response was lost.

## Not verified / not implemented

- Physical Android device: touchscreen, OS Keystore, audio, background lifecycle.
- iOS build/device/signing:requires Mac/Xcode and team configuration.
- FCM/background/terminated alerts:not implemented, roadmap only.
- Release signing/store upload:not configured.
- APK built without private local defines shows setup instructions. Developer must
  configure publishable/anon key and build again to log in; never embed server keys.

SDK XML/root warnings in build host do not indicate test failures. Earlier helper
processes were interrupted; no success claim relies on their exit code or missing logs.
