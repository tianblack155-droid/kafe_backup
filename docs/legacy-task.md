# ROLE

Act as a senior full-stack engineer, software architect, product designer, and UX engineer.

You are building a production-oriented **digital cafe ordering system**, not a generic demo or tutorial project.

Prioritize:

1. Excellent mobile UX
2. Simple ordering flow
3. Elegant and flexible visual design
4. Maintainable architecture
5. Strong data integrity
6. Real-world cafe operational workflow
7. Security
8. Scalability without premature overengineering

Do not add unnecessary technologies or features just to make the stack look sophisticated.

---

# PROJECT CONTEXT

I am building a web-based ordering system for a cafe.

The product should combine:

* The **elegant, flexible, premium visual direction** inspired by Blue Turtle's digital menu.
* The **simple, clear, easy-to-understand ordering UX and structured menu approach** inspired by Bakmi GM's ordering system.

Reference websites:

Blue Turtle:
https://menu.klikit.io/menu/RgjmlQv61nv2TxkRb8dTYaucZuTzq3I%3D/brand/5121

Bakmi GM:
https://order.bakmigm.co.id/bgm.cwk/products-list?table=

Do NOT clone either website.
Use them only as UX/product references.

The final product should feel like a modern premium cafe ordering platform rather than a generic POS system.

Core principle:

> Blue Turtle's visual elegance + flexibility
> +
> Bakmi GM's clarity + straightforward ordering
> +
> QR-table ordering + cafe operational management

---

# PRODUCT GOAL

A customer should be able to:

QR table
→ immediately see the menu
→ browse categories
→ discover recommended/best-selling products
→ open product details
→ customize the product
→ add to cart
→ review order
→ confirm/payment
→ track order status

No customer account should be required for normal dine-in ordering.

The system should be mobile-first because customers primarily order from smartphones.

---

# UX PRINCIPLES

Follow these strictly:

* Customer should understand the interface almost immediately.
* Minimize cognitive load.
* Avoid unnecessary screens.
* Avoid mandatory customer registration/login.
* Make one-handed mobile usage comfortable.
* Product photography should be visually important.
* Keep product cards simple.
* Detailed customization belongs inside product detail/modal/bottom sheet.
* Cart should always be easily accessible.
* Use sticky cart CTA on mobile when appropriate.
* Category navigation should support horizontal scrolling.
* Checkout must be short.
* Clearly display price changes caused by variants/add-ons.
* Clearly communicate unavailable/sold-out products.
* Never hide important order information.
* Use clear visual hierarchy.
* Avoid excessive animations.
* Animations should support usability, not decoration.

---

# CUSTOMER FEATURES

## 1. QR TABLE ORDERING

Each physical cafe table has a QR code.

Example:

/order?t=<table-token>

The system should identify the table automatically.

Customer should NOT manually type/select the table in normal QR flow.

The QR token must not expose sensitive database identifiers unnecessarily.

Support future possibility of other order modes such as takeaway.

---

## 2. MENU

Menu should support:

* All
* Coffee
* Non Coffee
* Food
* Snack
* Dessert
* Other configurable categories

Categories must be database-driven, not hardcoded.

Admin can:

* create
* edit
* reorder
* activate/deactivate categories

Menu should support:

* Best Seller
* Recommended
* New
* Featured
* Sold Out

These labels should be configurable and not permanently hardcoded into the frontend.

---

## 3. PRODUCT CARD

Product card should normally contain:

* Product image
* Product name
* Short description
* Price
* Optional badge
* Add button

Do not overload the card.

---

## 4. PRODUCT DETAIL

Clicking a product opens a clean detail experience.

Support:

* Large product image
* Name
* Description
* Base price
* Quantity
* Variants
* Add-ons
* Special notes
* Dynamic price calculation
* Add to cart

Example:

Size:

* Regular
* Large +5K

Sugar:

* Normal
* Less Sugar
* No Sugar

Ice:

* Normal
* Less Ice
* No Ice

Add-ons:

* Extra Egg +5K
* Extra Cheese +7K
* Extra Chicken +10K

Special request:
"Less spicy, please"

The customization system must be flexible enough for different product types.

Do not hardcode coffee-specific options into the architecture.

---

# 5. CART

Cart should show:

* Product
* Selected variants
* Selected add-ons
* Notes
* Quantity
* Unit price
* Item subtotal
* Order subtotal
* Service charge if applicable
* Tax if applicable
* Discount if applicable
* Final total

Customer must be able to edit/remove items.

Important:

Order prices must be snapshotted when the order is created.

Historical orders must not change if the product's current price changes later.

---

# 6. CHECKOUT

Keep checkout minimal.

Possible information:

* Table (automatically detected from QR)
* Customer name (optional/configurable)
* Order type
* Payment method
* Order summary

Possible payment methods:

* Cash
* QRIS
* Payment gateway

For initial MVP, prioritize Cash + QRIS.

Do not implement a complicated payment system unless required.

---

# 7. ORDER STATUS

Customer should be able to see:

Order Received
→ Preparing
→ Ready
→ Completed

Potential future states:

* Cancelled
* Refunded

Use a clear visual progress indicator.

Order status must be driven by backend state, not fake frontend-only state.

---

# 8. REALTIME ORDER STATUS

Use realtime updates where useful.

Example:

Kitchen changes:

PREPARING → READY

Customer should receive the updated status without manually refreshing the page.

---

# 9. RECOMMENDATIONS / BEST SELLERS

Support sections such as:

* Best Sellers
* Most Loved
* Recommended
* New
* Today's Special

These should be configurable through the admin system.

---

# 10. SEARCH

Support menu search when the catalog becomes large.

Search should be simple and mobile-friendly.

Do not make search dominant if the cafe has only a small menu.

---

# 11. PROMOTIONS

Support configurable promotions.

Examples:

* Percentage discount
* Fixed discount
* Product-specific promotion
* Category-specific promotion
* Buy X Get Y
* Time-limited promotion

For MVP, implement only what is actually needed.

Avoid building a complicated promotion engine prematurely.

---

# 12. UPSELLING

Optional product recommendations such as:

"Complete your order"

or:

"You might also like"

Examples:

Latte → Croissant
Pasta → Iced Tea

This should be optional and configurable.

---

# ADMIN FEATURES

Create a separate protected admin area.

Suggested routes:

/admin
/admin/orders
/admin/kitchen
/admin/products
/admin/categories
/admin/promotions
/admin/tables
/admin/settings

---

# ADMIN DASHBOARD

Show useful operational metrics:

* Today's orders
* Today's revenue
* Active orders
* Completed orders
* Popular products

Do not build complex analytics unless required.

---

# ORDER MANAGEMENT

Admin can:

* View orders
* Filter by status
* Filter by table
* View order details
* Update order status
* View payment status

Order history must remain immutable where appropriate.

---

# KITCHEN DISPLAY SYSTEM

Create a kitchen-oriented interface.

Example:

NEW ORDER #A102

Table 12

2x Cafe Latte

* Less sugar
* Less ice

1x Carbonara

* Extra cheese

Actions:

ACCEPT / PREPARING / READY

Kitchen UI should prioritize readability and speed over visual decoration.

---

# PRODUCT MANAGEMENT

Admin can:

* Create product
* Edit product
* Delete/archive product
* Change price
* Upload product image
* Assign category
* Configure availability
* Mark featured
* Mark best seller
* Mark new
* Configure variants
* Configure add-ons

Support SOLD OUT.

When a product is unavailable, customer should not be able to order it.

---

# TABLE MANAGEMENT

Admin can:

* Create tables
* Edit table number
* Activate/deactivate tables
* Generate QR codes
* View table status

Each table should have a secure QR token.

---

# AUTHENTICATION

Customer:

* No mandatory account
* Anonymous ordering

Admin/staff:

* Authentication required

Suggested roles:

* admin
* manager
* kitchen
* cashier

Use authorization/RBAC properly.

Do not rely only on frontend route hiding for security.

---

# DATABASE

Use PostgreSQL through Supabase.

Initial logical schema:

categories
products
product_variants
addons
product_addons
tables
orders
order_items
order_item_addons
payments
promotions
order_status_history
users/profiles as required by authentication

Recommended important fields:

categories:

* id
* name
* slug
* sort_order
* is_active

products:

* id
* category_id
* name
* slug
* description
* price
* image_url
* is_available
* is_featured
* is_new
* created_at
* updated_at

product_variants:

* id
* product_id
* name
* price_modifier
* is_available

addons:

* id
* name
* price
* is_available

product_addons:

* product_id
* addon_id

tables:

* id
* number
* qr_token
* is_active

orders:

* id
* order_number
* table_id
* status
* subtotal
* discount
* tax
* service_charge
* total
* payment_status
* payment_method
* created_at
* updated_at

order_items:

* id
* order_id
* product_id
* product_name
* quantity
* unit_price
* subtotal
* notes

order_item_addons:

* id
* order_item_id
* addon_id
* addon_name
* price

order_status_history:

* id
* order_id
* old_status
* new_status
* changed_by
* created_at

IMPORTANT:

Store product_name and unit_price snapshots in order_items.

Do not depend only on product_id for historical order display or pricing.

---

# DATA INTEGRITY

Implement proper constraints and validation.

Examples:

* quantity > 0
* price >= 0
* valid order status transitions
* valid table
* product availability check
* variant/add-on validity
* server-side total calculation

Never trust totals sent by the client.

The server/database layer must calculate or verify:

subtotal
discount
tax
service charge
total

Do not allow users to manipulate prices through frontend requests.

---

# SECURITY

Apply production-oriented security:

* Supabase Row Level Security
* Server-side authorization
* Input validation
* Schema validation
* Protected admin routes
* Secure QR token handling
* No sensitive service-role keys in frontend
* Never expose private environment variables
* Validate order contents server-side
* Prevent ordering unavailable products
* Prevent unauthorized admin mutations
* Rate limiting where appropriate
* Safe error responses
* Avoid exposing internal database details

Use the principle of least privilege.

---

# STORAGE

Use Supabase Storage for:

* Product images
* Cafe logo
* Promotional images

Do not store images as base64 inside database rows.

Database should store references/URLs.

Prefer optimized images such as WebP/AVIF where practical.

---

# REALTIME

Use Supabase Realtime for operational events where it makes sense.

Primary use case:

orders/status updates

Potential realtime flows:

Customer
→ order created
→ kitchen receives order

Kitchen
→ status updated
→ customer sees updated status

Avoid unnecessary realtime subscriptions everywhere.

---

# BACKEND ARCHITECTURE

Start simple.

MVP architecture:

Nuxt 4
+
Supabase

Supabase provides:

* PostgreSQL
* Auth
* Storage
* Realtime

Do NOT introduce a separate backend server merely for the sake of having one.

If custom backend logic becomes necessary, use:

Node.js + TypeScript + Hono

and deploy it on Railway.

Possible architecture later:

Nuxt
→ Hono API on Railway
→ Supabase PostgreSQL/Auth/Storage/Realtime

Use Railway only when custom server-side business logic, payment webhooks, external integrations, scheduled jobs, or similar requirements justify it.

Do not overengineer the MVP.

---

# FRONTEND STACK

Use:

* Nuxt 4
* Vue 3
* TypeScript
* Tailwind CSS
* shadcn-vue
* Pinia
* VueUse where useful

Frontend should be responsive and mobile-first.

Desktop admin interfaces should still be supported.

---

# FRONTEND STRUCTURE

Use a maintainable structure similar to:

pages/
components/
layouts/
composables/
stores/
services/
types/
utils/
middleware/
assets/

Keep business logic out of giant Vue components.

Create reusable components for:

* ProductCard
* ProductDetail
* ProductCustomization
* CategoryTabs
* CartBar
* CartItem
* OrderStatus
* OrderSummary
* AdminSidebar
* OrderCard
* KitchenOrderCard
* etc.

Do not create unnecessary abstractions.

---

# CUSTOMER ROUTES

Suggested:

/
/menu
/product/[id]
/cart
/checkout
/order/[id]

QR entry can route into the menu while preserving table context.

---

# ADMIN ROUTES

Suggested:

/admin
/admin/orders
/admin/kitchen
/admin/products
/admin/categories
/admin/promotions
/admin/tables
/admin/settings

Use route middleware and server-side authorization.

---

# DESIGN DIRECTION

Visual direction:

Premium modern cafe.

Characteristics:

* Elegant
* Clean
* Flexible
* Warm/premium
* Strong photography
* Generous whitespace
* Clear typography
* Subtle rounded corners
* Minimal shadows
* Clear CTA
* Strong hierarchy

Do not blindly copy Blue Turtle.

Do not blindly copy Bakmi GM.

Create an original design system inspired by their strengths.

Avoid generic SaaS dashboard aesthetics for the customer-facing menu.

The customer menu should feel like a real cafe brand.

Admin can be more functional.

---

# MOBILE UX

Mobile is the primary platform.

Pay special attention to:

* thumb reach
* sticky cart
* bottom sheets
* modal sizing
* touch target size
* horizontal category scrolling
* image loading
* typography
* checkout simplicity
* avoiding accidental clicks

Do not make the mobile UI look like a shrunken desktop website.

---

# PERFORMANCE

Optimize for real cafe customers using normal mobile connections.

Prioritize:

* image optimization
* lazy loading
* responsive images
* minimal JavaScript where possible
* efficient queries
* pagination where necessary
* caching where useful
* avoid unnecessary realtime subscriptions
* avoid huge client bundles

Do not optimize prematurely at the expense of maintainability.

---

# SEO / DISCOVERABILITY

The customer menu should have sensible metadata and Open Graph data.

However, QR-based ordering is the primary use case, so do not overinvest in SEO features that do not provide value.

---

# PAYMENT

Payment gateway integration should be modular.

Potential provider:

* Midtrans
* Xendit

Never trust frontend payment success state.

Use provider webhook → server validation → update payment status.

For MVP, payment gateway can remain optional if the cafe primarily uses cash/QRIS.

---

# DEPLOYMENT

Recommended:

Frontend:
Vercel

Database/Auth/Storage/Realtime:
Supabase

Optional custom backend:
Railway

Repository:
GitHub

Production environment must use environment variables.

Never commit secrets.

---

# DEVELOPMENT PRINCIPLES

1. Build MVP first.
2. Keep architecture extensible.
3. Do not add libraries without a reason.
4. Prefer native/framework capabilities before adding dependencies.
5. Keep components reusable but not excessively abstract.
6. Use TypeScript properly.
7. Validate data at boundaries.
8. Keep server-side business rules authoritative.
9. Design database around real operational requirements.
10. Make UX decisions based on customer speed and clarity.
11. Do not create fake functionality.
12. Do not leave critical features as mocked UI if they are supposed to work.
13. If something is intentionally mocked for development, clearly isolate it.
14. Avoid hardcoded business data where database-driven configuration is appropriate.

---

# MVP SCOPE

Prioritize these first:

### Customer

* QR table detection
* Menu
* Categories
* Product detail
* Variants
* Add-ons
* Notes
* Cart
* Checkout
* Order creation
* Order status
* Realtime status
* Sold out

### Admin

* Login
* Dashboard
* Product CRUD
* Category CRUD
* Add-ons/variants
* Order management
* Kitchen view
* Status updates
* Table management
* QR generation

### Infrastructure

* Supabase database
* RLS
* Storage
* Realtime
* Production environment variables

Do NOT prioritize initially:

* customer accounts
* loyalty program
* reviews
* AI recommendations
* delivery tracking
* complex analytics
* complex membership
* unnecessary microservices
* unnecessary queues
* unnecessary Redis
* unnecessary API gateway

---

# PRODUCT ARCHITECTURE

Think of the product as three connected experiences:

## CUSTOMER

QR
→ Menu
→ Product
→ Customization
→ Cart
→ Checkout
→ Order Tracking

## KITCHEN

Login
→ Incoming Orders
→ Accept
→ Preparing
→ Ready
→ Completed

## ADMIN

Login
→ Dashboard
→ Orders
→ Products
→ Categories
→ Add-ons
→ Promotions
→ Tables
→ Settings

All three must use the same source of truth.

---

# IMPORTANT ORDER FLOW

Implement this logically:

1. Customer scans table QR.
2. Application resolves table token.
3. Customer browses menu.
4. Customer selects product.
5. Customer configures variants/add-ons.
6. Customer adds product to cart.
7. Customer reviews cart.
8. Checkout validates the current product availability/prices.
9. Server creates order.
10. Order receives unique human-readable order number.
11. Kitchen/admin receives the order.
12. Kitchen updates status.
13. Customer receives realtime status updates.
14. Payment status is tracked separately from preparation status.
15. Order is completed.

Do not mix payment status and preparation status into one field.

Example:

preparation_status:

* pending
* preparing
* ready
* completed
* cancelled

payment_status:

* unpaid
* pending
* paid
* failed
* refunded

---

# ORDER NUMBER

Use a human-friendly order number.

Example:

A102

Do not expose raw UUIDs as the primary customer-facing order identifier.

UUIDs can still be used internally.

---

# ERROR UX

Errors must be understandable to normal cafe customers.

Bad:

"foreign key constraint violated"

Good:

"Menu item is no longer available. Please remove it from your order."

Handle:

* product sold out
* invalid QR
* expired/invalid table
* network failure
* payment failure
* order creation failure
* stale cart price
* invalid customization

---

# EMPTY STATES

Design meaningful empty states.

Examples:

Cart:
"Your cart is empty"

Search:
"No menu items found"

Orders:
"No active orders"

Kitchen:
"No new orders"

Do not leave blank screens.

---

# ACCESSIBILITY

Use:

* semantic HTML
* keyboard accessibility for admin
* sufficient contrast
* visible focus states
* proper labels
* meaningful button text
* alt text for images
* accessible dialogs/sheets

---

# IMPLEMENTATION APPROACH

Before writing a large amount of code:

1. Define architecture.
2. Define database schema.
3. Define RLS/security model.
4. Define customer flow.
5. Define admin flow.
6. Define kitchen flow.
7. Define UI design system.
8. Define folder structure.
9. Define API/data access strategy.
10. Then implement incrementally.

Do not generate an enormous monolithic code dump.

Build the application in coherent phases.

Each phase should leave the project runnable.

---

# EXPECTED DEVELOPMENT ORDER

Phase 1:
Project setup + design system + Supabase connection

Phase 2:
Database schema + RLS

Phase 3:
Customer menu + categories + product detail

Phase 4:
Cart + customization

Phase 5:
Checkout + order creation

Phase 6:
Admin authentication + dashboard

Phase 7:
Order management + kitchen display

Phase 8:
Realtime order status

Phase 9:
Table/QR management

Phase 10:
Payment integration if required

Phase 11:
Performance/security/polish

---

# CODE QUALITY

Use:

* strict TypeScript
* clear naming
* composables for reusable logic
* service/data-access layer where useful
* server-side validation
* reusable UI components
* meaningful error handling
* environment variables
* database constraints
* migrations

Avoid:

* any unless genuinely necessary
* giant components
* duplicated business logic
* hardcoded prices
* hardcoded categories
* client-controlled totals
* secrets in source code
* unnecessary dependencies

---

# WHEN MAKING ARCHITECTURAL DECISIONS

Choose the simplest solution that satisfies the real requirement.

If Supabase can solve something cleanly, do not introduce Railway.

If Nuxt can solve something cleanly, do not add another frontend framework.

If Tailwind/shadcn-vue can solve UI requirements, do not add multiple UI libraries.

If a feature is not necessary for the MVP, defer it.

---

# YOUR TASK

Act as the technical lead for this project.

Start by producing:

1. Final recommended architecture
2. Technology stack with justification
3. System architecture diagram
4. Customer flow
5. Admin flow
6. Kitchen flow
7. Database ERD/schema
8. RLS/security strategy
9. Nuxt project structure
10. Supabase structure
11. MVP implementation roadmap
12. Important technical risks and how to avoid them

Then wait for the next implementation instruction.

Do NOT immediately generate the entire application in one response.

When implementation begins, work incrementally and keep every step runnable.

If you identify a better technical decision than the one specified above, explain the trade-off briefly and choose the better solution rather than blindly following the specification.

Primary objective:

> Build a production-oriented cafe ordering system that is elegant for customers, efficient for cafe staff, simple to maintain, secure, and capable of evolving into a real product.