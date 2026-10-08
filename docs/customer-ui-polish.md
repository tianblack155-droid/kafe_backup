# Reference UI polish verification

Reference: https://order.bakmigm.co.id/bgm.cwk. Live DOM and screenshots inspected at 390x844 and 1280x844.

Matched geometry: landing card x24/y212/w342 on 390px, 120px logo, 18px title,
separate white 48px tutorial and dine-in rows, horizontal bottom attribution.
Desktop uses centered 360px surface (card width312). Menu uses 64px header,
12px row margins, 130px images where space allows, 14px names and 16px prices.
Detail image begins at page top, recommendations precede selection, red add CTA.

Intentional differences: TKM-owned assets/content, extra Instagram row, no fabricated
user distance, opening schedule, promotion carousel or language switch. Contact links
keep 44px touch targets. Cash-only/shared QR/product limits and transaction scripts
remain unchanged. Brand/content differences mean this is NOT a pixel-identical clone.
Cart/payment screens not claimed identical; only existing checkout regressions tested.

Evidence: local browser at mobile/desktop passed checkout payload with synthetic catalog
(no order created). Actual local Go/Postgres/Caddy WSS test passed checkout notification,
payment, completion, restart/reconnect and isolation with mock Auth. Node and Vercel builds
passed. New static regressions cover contact preservation and recommendation placement.
Original browser geometry test failed on missing separate entry row, then passed.
