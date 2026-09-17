# VPS preview deployment — 2026-09-17

Current QR contract: shared `/menu`, no table identity/cookie/query. Migration5
removes the table requirement without deleting old data; see
[shared QR checkout](../docs/shared-qr-checkout.md). Do not roll back to an older
application that requires table IDs after tableless orders exist: its reorder code
cannot read these new orders. Prefer a compatible forward fix.

## URLs and release

- Customer: https://teraskayumanis.alrizky.id/menu
- Cashier: https://teraskayumanis.alrizky.id/cashier
- Host: `168.235.65.141`, Ubuntu 24.04 amd64, New Jersey.
- Deployed application revision: `76b0976134921e0bacb1811afca33cb94103cd5f` from
  `refactor/monorepo-go-foundation`. Main was NOT merged or deployed.
- Application release `/opt/teraskayumanis/releases/76b097613492`; `current` symlink points there.
- Go statically compiled linux/amd64; Nuxt Node build and Node v24.20.0 executable.
- Release archive SHA256: `75d8082beabfafc84ef5eb3e49547926e4d140167db106d4a6c9c118cd3922ae`.
  Hash verified after SCP; binaries/libraries verified on destination, no broken/external symlinks.

## Service boundaries

- `tkm-api.service`: user/group tkm-api, Go on 127.0.0.1:8080.
- `tkm-web.service`: separate user/group tkm-web, Nuxt on 127.0.0.1:3000.
- `caddy.service`: HTTPS reverse proxy to Nuxt; Nuxt `/api/core/*` proxies to Go.
  `/ws` is upgraded and proxied directly to Go `/api/v1/realtime`.
- Both app units enabled on boot, Restart=on-failure and bounded memory/tasks.
- App files root-owned/read-only to service users. ProtectSystem/ProtectHome/PrivateTmp,
  no new privileges or ambient capabilities. Applications do not run as root.
- Caddy automatically issued a publicly trusted HTTPS certificate; HTTP redirects to HTTPS.
- UFW enabled with TCP 22/80/443 allowed; app ports are loopback only. SSH settings unchanged.
- Legacy `/admin*` and `/api/admin*` blocked at Caddy for this pilot, not advertised as complete.
- No Caddy request access log so QR/capability query values are not recorded there.

## Secrets and config

- `/etc/teraskayumanis/backend.env` and `frontend.env`: root-owned 0600, loaded by systemd.
- `/etc/teraskayumanis/prod-ca-2021.crt`: root:tkm-api 0640; directory root:tkm-api 0750.
- Web user cannot read backend env. Frontend receives only public auth key and Go URL.
- Go DATABASE_URL uses restricted `tkm_runtime`, Session pooler, TLS verify-full.
- `deploy/render_env.py` builds explicit allowlists and enforces bind addresses/ports.
  It rewrites the URL query's sslrootcert after decoding; literal replace fails when
  the old path is percent-encoded. That startup failure was reproduced and corrected.
- EnvironmentFile serialization is quoted, rejects multiline/NUL and never logs values.
- Do not commit output env, private keys, passwords or full DSNs.

## Verified on actual public deployment

- `/cashier` HTTPS 200; Chromium renders login form with no page exceptions.
- `/menu` loads; `/api/core/menu` 200, real Supabase settings/catalog (one sample Es Teh Manis (Uji), Rp5.000).
- `/api/core/admin/orders` without auth -> 401; legacy admin endpoint -> 404.
- Go `/ready` 200 on destination. All three services active.
- Public HTTP checkout test with management-seeded, explicitly temporary catalog/table:
  checkout201, idempotent retry, capability denial404, auth denial401, expiry and fresh reorder.
  Exact fixture cleanup verified; actual cashier profile was NOT deleted or changed.
- Restarted both app services and repeated readiness/public API checks successfully.
  Boot enablement verified; a whole VPS reboot was not performed.
- 17 renderer tests run normal/optimized Python. Type/build/business tests remain separate gates.

The host-reported memory is an idle snapshot, not a load/capacity guarantee. Public
transaction timing was measured from the Hermes host, NOT from Indonesia/the cafe.

## Reproduce a deployment (operator checklist)

1. Check reviewed branch/revision, DNS and trusted SSH host key, existing services and storage.
2. Build Nuxt Node (`npm run build`) and static Go for target architecture off the small VPS.
3. Package `.output` as `web/`, Go as `server`, compatible Node as `node`, and `REVISION`.
   Verify expected sha256 at destination. Do not package .env files. Scan for known secrets;
   this limited check is not comprehensive proof of absence of every possible secret.
4. Render systemd config, on trusted host, to a new PRIVATE directory:
   `python3 deploy/render_env.py backend/.env frontend/.env /private/new-output-dir`
5. Securely transfer env and official CA separately. Use owner/modes above; replace the
   `/etc/teraskayumanis/prod-ca-2021.crt` path consistently. Do not print DSNs in logs.
6. Install Caddy from its official signed apt repository; install ufw explicitly. Allow
   existing SSH before enabling firewall. Create app users if absent.
7. Install versioned root-owned release, update current symlink, install unit files and
   Caddyfile; run systemd-analyze verify and caddy validate. Check `node --version`, ldd,
   executable permissions as service users, and dependencies/symlinks on target.
8. daemon-reload, enable/restart app units; verify /ready + local proxy before Caddy reload.
9. Verify public TLS, unauthorized denial, customer/browser paths, and restart recovery.

Use a new immutable release path on updates. Preserve prior release/config until the new
release is verified; rollback by restoring previous symlink/config then restarting units.
Prior release `55018bd` is retained for rollback. Migration4 only grants the publication
column update and is compatible with the previous application. Do not run two active Go instances.
Do not re-run Supabase bootstrap migrations during deployment.

## Remaining gates

- User-owned cashier account exists in Supabase Auth, email confirmed, linked role cashier.
  We have NOT tested its password login; user should sign in at /cashier (never share password).
- One menu uji + Meja 1 seeded; final cafe catalog still not prepared.
- Real Supabase temporary cashier login -> WSS -> review -> payment -> completion passed
  on public deployment. Temporary user/profile/table/orders removed and absence checked.
- Customer isolation/invalid-token/origin/query denial and reconnect tested over WSS.
- No KDS, Flutter or FCM. WebSocket/outbox now implemented. Admin CRUD/report migration and production backup/restore,
  monitoring, abuse resistance and operational approval remain separate work.
- Public preview is not approval for live cafe operations or main merge.
