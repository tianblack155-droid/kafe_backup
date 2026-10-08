# Customer UI reference implementation

Reference inspected: https://order.bakmigm.co.id/bgm.cwk (mobile390×844).
Goal: restaurant entry, category-led catalog and full-page product inspection with
TerasKayuManis branding. No Bakmi GM logo/photos/menu text copied into application.

## Observed vs adapted

Observed: photo-cover entry with overlapping circular logo/information card; tutorial
and dine-in rows; Montserrat typography; white/gray surfaces; black active category
pills/circular add buttons; single-column large-image product list; full-screen product
detail with sticky quantity/add action.

Adapted: TKM has no verified address/hours/cover/promo fields yet. Do not invent these
or label the restaurant closed. Neutral asset placeholders and truthful copy are used.
The reference restaurant was closed when inspected, so its final cart/checkout behavior
was not accessible. TKM cart/tracking preserve existing transactions, not an invented
claim of pixel-exact checkout cloning.

## Functional constraints

- `/` is entry; `/menu` still works directly from a shared QR.
- No table identity, QR scan inside app, or table-cookie checkout gate.
- Cash only; review before cash; completion separately; expiry/reorder unchanged.
- Product choices must remain valid/available and quantities bounded.
- Cart uncertainty uses exact stored checkout identity, never a new POST key by default.
- Web cashier/Flutter/backend mutation contracts remain unchanged.
- New customer-only styles must not restyle cashier/admin UI globally.

## Hosting

Target frontend remains Vercel and backend/WSS VPS. A local Node/Vercel build is not a
Vercel deployment. This UI task does not migrate DNS, expose Go routes, or shut down the
existing preview. Separate hosting migration must configure public API/WSS origins and
Flutter endpoints before switching domains. No automatic VPS frontend redeploy here.

## Required verification

Unit/behavior selection tests, existing checkout/reorder/realtime regression tests,
Nuxt typecheck, Node build, Vercel build, mobile/desktop browser navigation and overflow,
visual inspection of landing/catalog/detail/cart. Screenshot fixtures are local synthetic
catalog data, not production menu changes. Physical camera QR test is separate.
