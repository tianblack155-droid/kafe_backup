# TASK: RESPONSIVE UI, DATE FILTER, BUTTON LABELS & ORDER WORKFLOW UPDATE — TERAS KAYUMANIS CASHIER APP

## 1. ROLE AND OBJECTIVE

Act as a senior Flutter developer and UI/UX engineer.

Modify the existing TerasKayumanis Cashier App directly in the current project. Implement the following improvements:

1. Make the entire application automatically responsive for Android phones and tablets.
2. Add a date-by-date filter to the order history.
3. Rename the specified buttons to Indonesian labels.
4. Change the order workflow so the payment countdown stops when the cashier has accepted and started processing an incoming order.
5. Preserve all existing API integrations, realtime updates, payment validation, authentication, and business logic that is not explicitly changed by this task.

Do not merely provide a plan or example code. Inspect the project, implement the changes, and verify the result.

## 2. FIRST: AUDIT THE EXISTING PROJECT

Before making changes:

* Identify the actual Flutter application root.
* Read `pubspec.yaml`.
* Inspect the current dashboard, active order list, history, order details, review/edit screen, payment screen, and completion screen.
* Inspect the order model, status definitions, countdown/timer implementation, API services, repositories, state management, and realtime event handling.
* Determine how the current backend stores order status, payment deadlines, review versions, and payment results.
* Identify whether the countdown is calculated by the client, server, or both.
* Determine how the backend currently distinguishes an incoming order, a reviewed order, a paid order, and a completed order.

Use the existing architecture and APIs wherever possible. Do not assume endpoint names, database columns, status values, or payload structures before inspecting the code.

## 3. FEATURE A — FULLY RESPONSIVE PHONE AND TABLET UI

The application must automatically adapt to different screen sizes and orientations without requiring a separate tablet version or manual configuration.

### A.1 Responsive behavior

Support:

* Small Android phones.
* Standard Android phones.
* Large phones.
* Android tablets.
* Small and large tablet screens.
* Portrait and landscape orientations.

Use Flutter's responsive layout tools, such as `LayoutBuilder`, `MediaQuery`, `SafeArea`, `Flexible`, `Expanded`, `Wrap`, and adaptive layout components, where appropriate.

Do not simply scale every widget proportionally. Adjust the layout structure based on available space.

### A.2 Phone layout

For narrow screens:

* Use a single-column layout.
* Keep order cards compact and easy to scan.
* Stack order information vertically when necessary.
* Keep important action buttons accessible.
* Allow long customer names, order IDs, and product names to wrap safely.
* Make forms and payment inputs comfortable to use.
* Ensure the keyboard does not hide the active field or primary action.
* Use scrolling when the content exceeds the viewport.

### A.3 Tablet layout

For wider screens:

* Use the additional space effectively.
* Allow more order information to appear in a single row.
* Use a two-column layout for order list and order details where appropriate.
* If suitable for the current navigation architecture, show the order list on the left and the selected order details on the right.
* Use wider forms and clearer grouping of payment and order information.
* Display summary cards in a row when sufficient space is available.
* Avoid stretching buttons, text fields, and cards to unreasonable widths.
* Apply a sensible maximum content width for reading and form-heavy screens.

On tablets, do not simply display a phone layout stretched across the entire screen.

### A.4 Responsive breakpoints

Create a centralized responsive layout strategy.

Use the actual available width rather than checking only the device name or physical device type.

Suggested starting points:

* Narrow layout: below 600 logical pixels.
* Medium layout: 600–899 logical pixels.
* Wide layout: 900 logical pixels and above.

These values may be adjusted based on the existing application structure and actual testing.

Do not scatter inconsistent breakpoint values throughout the codebase.

### A.5 Orientation and window resizing

The layout must adapt when:

* A device rotates from portrait to landscape.
* The application is opened on a tablet.
* The available window size changes, where supported.

Do not lock the application to portrait orientation merely to avoid responsive layout problems.

### A.6 Responsive dashboard and history

On phones:

* Display active orders and history in a readable vertical list.
* Keep tabs and filtering controls compact.
* Place the date filter in a space-efficient layout.

On tablets:

* Make better use of horizontal space.
* Allow search and date-filter controls to appear side by side.
* Keep order cards and status labels aligned.
* Avoid excessive empty space or overly wide text lines.

### A.7 Responsive order detail, review, and payment screens

* Group related fields into sections.
* Use a side-by-side layout on wider screens when it improves usability.
* Keep order totals and important actions easy to locate.
* Ensure dialogs fit within the available screen size.
* Use scrolling for long item lists.
* Prevent keyboard-related overflow.
* Ensure confirmation dialogs remain readable in landscape mode.

### A.8 Responsive quality requirements

Check for:

* `RenderFlex overflowed` errors.
* Clipped text.
* Buttons extending beyond screen boundaries.
* Inputs hidden behind the keyboard.
* Dialogs that exceed the screen.
* Excessively wide cards or forms.
* Broken layouts when rotating the device.
* Overlapping navigation elements.

Do not fix overflow by shrinking all text indiscriminately.

## 4. FEATURE B — FILTER ORDER HISTORY BY DATE

Add a date filter to the existing order history screen.

The cashier must be able to select a specific date and view orders associated with that date.

### B.1 User interface

Add a clearly labeled date-filter control in the History screen.

Suggested interface:

* Label: `Filter Tanggal`
* Date picker: opens a calendar.
* Selected date: clearly displayed, for example `12 Oktober 2026`.
* Apply action: `Terapkan`, if the current UI uses an explicit apply action.
* Reset action: `Reset Filter` or a suitable clear-filter icon with a tooltip.

Use the device's Indonesian locale if the project already supports it. Otherwise, configure the necessary Flutter localization appropriately.

The date picker must be responsive on phones and tablets.

### B.2 Date-by-date filtering

The cashier must be able to select one particular date, not just a broad month or year.

For example:

* Select 10 October 2026 → show history for 10 October 2026.
* Select 11 October 2026 → show history for 11 October 2026.
* Select 12 October 2026 → show history for 12 October 2026.

Changing the selected date must refresh the results using the existing data flow.

### B.3 Date range semantics

Define a selected calendar day as the interval:

`start of selected day <= order timestamp < start of next day`

Use the appropriate timezone for the application's intended business location. Do not assume UTC and local time are interchangeable.

Avoid filtering with a timestamp equality check because timestamps commonly include hours, minutes, seconds, or milliseconds.

Use the correct timestamp field based on the existing business definition of order history. Inspect whether the history should be based on order creation time, completion time, or another established field. Prefer the field already used by the application's current history behavior.

### B.4 Data fetching and backend compatibility

Inspect how order history is currently loaded.

* If the backend already supports date filtering, use the existing supported request parameters.
* If the backend does not support date filtering, implement a safe and maintainable solution compatible with the current architecture.
* Prefer server-side filtering for large datasets when the backend can support it.
* If the available API only returns a bounded dataset, do not falsely present incomplete local filtering as the complete history.
* If a backend change is necessary, inspect the backend implementation first and keep the change minimal.
* Do not invent endpoint names or request parameters.
* Preserve authentication and authorization.
* Avoid fetching the same data repeatedly on every widget rebuild.

### B.5 History states

Support:

* Initial history loading.
* Loading a newly selected date.
* Results found.
* No orders for the selected date.
* Network or API failure.
* Clearing the selected date.

When no orders match, display a message such as:

`Tidak ada pesanan pada tanggal ini.`

The message should be concise and accompanied by a clear reset-filter action when appropriate.

### B.6 Filter consistency

* Changing the date must not accidentally modify order status.
* Clearing the date filter must restore the existing default history behavior.
* The selected date must remain visible while its filter is active.
* Do not mix active orders with completed history unless the current application explicitly does so.
* Preserve existing pagination or loading behavior if present.
* Do not create duplicate orders in the displayed history.

## 5. FEATURE C — CHANGE BUTTON LABELS

Update the following button labels throughout the cashier application.

| Existing label              | New label                  |
| --------------------------- | -------------------------- |
| `Tinjau & edit pesanan`     | `Proses Pemesanan`         |
| `Simpan tinjauan ke server` | `Konfirmasi Pemesanan`     |
| `Periksa pembayaran tunai`  | `Periksa Pembayaran Tunai` |

Apply these changes consistently wherever the corresponding actions appear, including relevant dialogs or alternate layouts.

### Important rules

* Change the visible text only where the action genuinely corresponds to the same operation.
* Preserve the underlying callback, API request, validation, loading state, and error handling.
* Do not change API names, backend status identifiers, enum values, or database fields just because a button label changes.
* Use consistent capitalization and natural Indonesian.
* Ensure buttons remain readable on narrow screens and tablets.
* If the same existing label appears in unrelated functionality, inspect its context before changing it.

## 6. FEATURE D — STOP THE PAYMENT COUNTDOWN AFTER CASHIER PROCESSING

### D.1 Required business behavior

Change the workflow for incoming orders.

**Before the cashier starts processing an incoming order:**

* The order follows its existing payment countdown rules.
* The remaining payment time is displayed normally.
* The existing expiration behavior remains active.

**When the cashier presses `Proses Pemesanan` and the backend successfully accepts the processing/review transition:**

* The order enters the appropriate existing processing or approved state.
* The payment countdown stops.
* The order must no longer lose remaining payment time while the cashier processes it.
* The displayed remaining time must not continue decreasing.
* The application must not automatically expire the order based on the paused payment countdown.
* The new state must remain consistent across the order list, order details, and review screen.
* The transition must survive navigation, application rebuilds, app restarts, and realtime updates.

**After the cashier presses `Konfirmasi Pemesanan`:**

* Execute the existing review confirmation workflow.
* Preserve all current server validation, review versioning, and conflict handling.
* Continue to the appropriate payment flow according to the existing business rules.
* Do not restart the old countdown unless the established business rules explicitly require a new deadline.
* Do not invent a new countdown duration.

**When the customer payment is successfully verified:**

* Follow the existing paid-order flow.
* Preserve payment verification and order completion behavior.

### D.2 Critical distinction: stopping versus resetting the timer

Do not merely hide the countdown widget.

Do not simply set the displayed remaining time to zero.

Do not reset the countdown to its original duration every time the order screen opens.

Do not stop the timer only in the current widget while the backend continues to expire the order.

The intended behavior is to **pause the existing payment deadline when the cashier successfully begins processing the order**, preserving the remaining time and preventing expiration during the paused state.

### D.3 State and backend persistence

Inspect the existing backend and data model before implementation.

Prefer a persistent server-side representation of the paused state and remaining payment time, using the existing architecture where possible.

Possible implementation approaches, depending on the current backend:

* An explicit processing/approved state that disables payment expiration.
* A persistent `payment_paused` flag, if compatible with the current model.
* A stored remaining duration or adjusted deadline.
* A dedicated processing timestamp and corresponding deadline logic.

These are implementation options, not mandatory new field names. Reuse the existing status model if it already expresses the required behavior.

If the countdown currently depends on a fixed expiration timestamp, ensure the backend expiration worker and every relevant API path respect the paused state.

If the backend does not currently support pausing the countdown, make the smallest necessary backend change and update all affected validation and expiration logic.

Do not implement a client-only pause that allows the UI to show a stopped timer while the server still rejects or expires the order.

### D.4 Preserve remaining time

At the moment the cashier successfully begins processing, calculate and persist the remaining payment duration using the authoritative timestamp and timezone strategy already used by the application.

Example:

* Original remaining payment time: 08:35.
* Cashier successfully starts processing.
* Display remains at 08:35 while processing is paused.
* Cashier spends 15 minutes reviewing the order.
* Display must still show the preserved remaining duration, rather than 00:00.
* When the existing workflow resumes a running payment countdown, if such a transition is supported, resume from the preserved remaining duration instead of restarting the full original duration.

Do not assume that the countdown should resume at a particular step unless the existing business requirements or code clearly establish that step.

If payment remains paused until the customer pays, keep it paused throughout that interval.

### D.5 Atomic transition and failure handling

The processing transition must be handled safely.

* Pause the countdown only after the server successfully confirms the processing transition.
* If the request fails, keep the existing authoritative order state and countdown behavior.
* Prevent duplicate processing requests where practical.
* Handle retries and duplicate requests idempotently when supported by the backend.
* Ensure realtime events do not accidentally resume the countdown.
* Ensure refreshing the order list does not revert the paused state.
* Ensure two cashiers cannot accidentally overwrite a newer order state when existing concurrency controls are available.
* Preserve review-version conflict detection.

### D.6 Expiration worker and background processing

Inspect any backend cron job, worker, scheduled task, or API middleware that marks orders as expired.

Update it so that a successfully paused order is not expired merely because its original payment deadline passes during processing.

Ensure this behavior is enforced by the authoritative backend, not only by Flutter.

If there is no backend expiration worker and expiration is managed elsewhere, identify the actual mechanism and apply the same rule there.

### D.7 Countdown UI

When the payment countdown is paused:

* Stop the ticking animation or timer updates.
* Preserve the remaining duration in a readable format.
* Display a small badge or label such as `Waktu pembayaran dijeda`.
* Optionally display `Sedang diproses kasir` if that wording accurately reflects the actual order state.
* Do not show a misleading active countdown.
* Do not display a countdown at all in screens where it is no longer relevant, according to the existing workflow.

Use clear Indonesian text and a subtle neutral or blue informational style.

## 7. ORDER STATE TRANSITIONS

Before modifying the workflow, document the actual existing state transitions.

Then update only the transitions needed to support the new behavior.

The intended high-level sequence is:

`Pesanan Masuk → Proses Pemesanan → Konfirmasi Pemesanan → Periksa Pembayaran Tunai → Lunas → Selesaikan Pesanan → Selesai`

This sequence represents the desired user-facing flow. It does not authorize inventing backend states or bypassing existing server validations.

Requirements:

* Preserve the existing review and payment operations.
* Map the new labels to the correct existing actions.
* Ensure the countdown pause is associated with the successful processing transition.
* Keep the UI consistent with the actual server state.
* Do not mark an order paid before payment verification succeeds.
* Do not mark an order completed before completion succeeds.
* Preserve cancellation, expiry, and error handling where already supported.
* Do not allow an invalid transition simply because a button is visible.

If the current backend's workflow differs from this sequence, reconcile it with the intended behavior using the smallest safe change and explain any necessary differences in the final report.

## 8. REALTIME AND DATA CONSISTENCY

The application already uses realtime order updates. Preserve that functionality.

Ensure:

* New incoming orders appear without breaking existing notifications.
* Processing an order broadcasts or exposes the updated state through the existing realtime mechanism.
* All screens show the same authoritative order status.
* The paused countdown state is included in whatever data the client needs to render the correct state.
* History filtering does not disrupt realtime updates.
* Realtime events cannot overwrite a newer state with stale information.
* Reconnecting to the server restores the correct order state and remaining time.
* Reopening the application does not reactivate a paused countdown.

Avoid duplicate listeners, duplicate network requests, and timers that continue running after a widget is disposed.

## 9. TESTING REQUIREMENTS

Add or update tests where the existing test infrastructure supports them.

### Responsive UI tests

Check representative narrow, medium, and wide viewport widths, including:

* Small phone width.
* Standard phone width.
* Tablet portrait.
* Tablet landscape.

Check for overflow, clipped text, and inaccessible actions.

### History filter tests

Verify:

* Selecting a date displays only orders for that date.
* Orders near midnight are handled using the correct timezone.
* Orders on the following day are excluded.
* Clearing the filter restores the default history.
* Empty dates show the correct empty state.
* API failures are handled correctly.

### Countdown tests

Verify:

1. Incoming orders initially follow the existing countdown.
2. Failed processing requests do not pause the authoritative countdown.
3. Successful processing pauses the countdown.
4. The remaining time does not decrease while paused.
5. A paused order is not expired by the backend merely because the original deadline passes.
6. Reopening the application preserves the paused state.
7. Realtime refreshes do not resume the countdown incorrectly.
8. Review confirmation preserves the correct countdown state.
9. Payment verification and order completion remain functional.
10. Existing concurrency and version checks still work.

Use deterministic clocks or injectable time sources if appropriate. Avoid fragile tests that depend on waiting for real-world minutes to pass.

## 10. IMPLEMENTATION ORDER

Proceed in this order:

1. Inspect the Flutter app and relevant backend code.
2. Map the existing order state machine and countdown implementation.
3. Establish centralized responsive breakpoints and layout helpers.
4. Update the dashboard, history, detail, review, and payment layouts for phones and tablets.
5. Implement the history date filter.
6. Update the three button labels.
7. Implement persistent countdown pausing in the authoritative backend and corresponding Flutter state handling.
8. Verify realtime consistency and expiration logic.
9. Add or update tests.
10. Format the changed Dart files and any modified backend files.
11. Run Flutter analysis and relevant tests.
12. Review the final diff for unrelated or destructive changes.

Do not stop after writing a plan. Implement the changes directly.

## 11. SAFETY AND COMPATIBILITY RULES

* Do not replace real API data with mock data.
* Do not invent endpoint URLs, request fields, database columns, or state names.
* Do not disable authentication or authorization.
* Do not weaken payment validation.
* Do not remove review-version checks.
* Do not break the existing cashier login or realtime connection.
* Do not delete unrelated features.
* Do not overwrite unrelated user changes.
* Do not make a client-only countdown pause if the server remains authoritative for expiration.
* Do not claim a backend behavior has been fixed unless the relevant backend code has actually been updated and verified.
* Keep changes minimal, maintainable, and consistent with the existing project architecture.

If the Flutter app and backend are in separate repositories or the backend source is unavailable, implement the safe client-side responsive and filtering changes that can be verified, clearly identify the missing backend work, and do not pretend the server-side countdown pause is complete.

## 12. FINAL REPORT

After implementation, report:

1. Which screens are now responsive and how tablet layouts differ from phone layouts.
2. How the history date filter works.
3. The updated button labels.
4. How the payment countdown pause is persisted and enforced.
5. Which backend files and Flutter files were modified.
6. Whether the expiration worker/API validation respects paused orders.
7. Results from `flutter analyze`, tests, and any backend test commands actually executed.
8. Any remaining limitations, migration requirements, or backend work that could not be completed.

Start by inspecting the real source code, then implement the changes. Do not fabricate successful tests or claim that an unimplemented backend change is complete.
