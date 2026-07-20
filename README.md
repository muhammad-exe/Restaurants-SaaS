# Dastarkhwan Restaurant OS — Setup Guide

This is a real, working app — not a demo. Order data is saved to an actual
database, and it will keep working after you close the tab. Total cost to
run this for your first several restaurants: **$0/month.**

> **Already set up a Supabase project before this update?** Don't re-run
> the whole `schema.sql` — your tables already exist, so it'll error
> with "relation already exists." Instead, run the smaller file made
> for this: go to your Supabase project → **SQL Editor** → **New
> query** → open `supabase/migration_v2_security.sql` from this folder
> → paste it in → **Run**. It only swaps the security rules, doesn't
> touch your existing tables or data, and is safe to run more than
> once. This closes the security hole described below, so don't skip
> it.

It has three pages:
- `pos.html` — the cashier screen — now also shows **live incoming
  orders** (including QR orders customers placed themselves), and
  requires a staff PIN to open.
- `menu.html` — the customer-facing QR ordering page — no login, this
  one's meant to be open to anyone who scans the table code.
- `dashboard.html` — the owner's sales dashboard — requires an
  **owner/manager** PIN specifically; a cashier's PIN won't open it.

All three talk to one shared database (Supabase), so an order placed on
`menu.html` shows up instantly on `dashboard.html` **and** on the
`pos.html` incoming-orders panel, so staff always know a QR order came in.

---

## Step 1 — Create your free database (5 minutes)

1. Go to [supabase.com](https://supabase.com) → sign up (free, no card required).
2. Click **New project**. Name it anything, pick a region close to your restaurant, set a database password (save it somewhere).
3. Once it's created, go to the **SQL Editor** (left sidebar) → **New query**.
4. Open `supabase/schema.sql` from this folder, copy all of it, paste it into the SQL editor, and click **Run**.
   - This creates every table the app needs, adds one demo restaurant ("Zaiqa Grill House") with a sample menu, and — importantly — sets up the locked-down access rules described below.

## Step 2 — Connect the app to your database (2 minutes)

1. In Supabase: **Project Settings** (gear icon) → **API**.
2. Copy the **Project URL** and the **anon public** key.
3. Open `js/config.js` in this folder and paste them in:

```js
const SUPABASE_URL = "https://xxxxxxxx.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOi....";
```

That's it — the app is now live against your own database.

## Step 3 — Try it locally

You can't just double-click the HTML files (browsers block database
calls from `file://` pages). Run a tiny local server instead:

- **VS Code**: install the "Live Server" extension, right-click `pos.html` → "Open with Live Server".
- **Or, if you have Python installed**: open a terminal in this folder and run `python3 -m http.server 8000`, then visit `http://localhost:8000/pos.html`.

Open `pos.html`, add an item, and check `dashboard.html` — the sale should appear immediately.

## Step 4 — Put it online for free

1. Go to [vercel.com](https://vercel.com) → sign up free → **Add New Project**.
2. Drag this whole folder onto the upload area (or connect it via GitHub if you're using git).
3. Deploy. You'll get a free URL like `dastarkhwan.vercel.app`.
4. That URL is what you turn into QR codes for tables (see below) and what you open on the tablet at the counter.

---

## Generating table QR codes

There's now a page built for this — no external website needed.

1. Open `qr-codes.html` (also linked from the owner dashboard as
   "Table QR codes").
2. Paste your live Vercel URL into the box at the top (e.g.
   `https://your-app.vercel.app`) and click **Generate QR codes**.
3. You'll see one QR code per table, already pulled from your
   `restaurant_tables` data — each one correctly points to
   `menu.html?t=<that table's token>`.
4. Press **Ctrl/Cmd+P** to print — the page is laid out two-per-row
   with cut lines, ready to trim and put on tables.

It remembers the URL you entered, so you don't have to retype it next
time you add a table.

To add more tables or rename them, edit the `restaurant_tables` table
directly in Supabase's **Table Editor** — no code needed. Refresh
`qr-codes.html` afterward and the new table shows up automatically.

## Adding your own restaurant instead of the demo one

In Supabase's **Table Editor**:
1. Add a row to `restaurants` (give it a unique `slug`, e.g. `my-restaurant`).
2. Add rows to `categories` and `menu_items` for that restaurant's `id`.
3. Add rows to `restaurant_tables` with unique `qr_token` values.
4. Update `RESTAURANT_SLUG` in `js/config.js` to match.

Once your on-spot setup wizard exists (see Phase 2 below), you won't need
to do this by hand — for now, the Table Editor works fine for onboarding
your first few pilot restaurants.

## Staff PIN login

Both `pos.html` and `dashboard.html` now open on a PIN-entry screen —
no one gets in without a valid staff PIN.

- **POS** accepts any staff role (owner, manager, cashier, waiter).
- **Dashboard** only accepts `owner` or `manager` PINs — a cashier's PIN
  won't open it.
- The demo data includes two logins: PIN `1234` (Owner — works on both
  screens) and PIN `1111` (Ali, Cashier — POS only, dashboard will
  reject it).

Add, remove, or change staff PINs any time in Supabase's **Table
Editor** → `staff` table — no code changes needed. Every order created
on the POS is now stamped with which staff member rang it up.

Note on security: PINs are stored as plain text in the `staff` table
for now, matching the "pilot-grade, not production-grade" security
level described below. Fine for testing; hash them before real rollout.

## WhatsApp receipts

`js/supabaseClient.js` has a `sendWhatsAppReceipt()` function that
currently just logs to the browser console — it doesn't actually send a
message yet, because that requires a Meta WhatsApp Business account and
Meta's template approval process (not something I can set up on your
behalf). The commented-out code inside that function shows exactly what
the real API call looks like once you have:
1. A Meta Business account + WhatsApp Business Cloud API access
2. An approved message template
3. Your `WHATSAPP_ACCESS_TOKEN` and `PHONE_NUMBER_ID`

Until then, the order still saves correctly and the on-screen confirmation
still shows the customer their receipt — only the actual WhatsApp send is
stubbed out.

---

## Security model — what's actually locked down now

The public API key in `js/config.js` is meant to be public — it's
visible to anyone who views your website's code, by design, the same
way it works for every Supabase app. What matters is what that key is
*allowed to do*, and that's what changed:

- **The `staff` table is not readable at all** through the public key —
  not even indirectly. PIN checks happen inside a database function
  (`check_staff_pin`) that never returns the PIN itself, only whether it
  matched and who it belongs to.
- **Orders, order items, customers, cash sessions, and expenses are not
  directly writable** through the public key. Every order is created
  through a `create_order` database function that calculates totals
  itself server-side (the browser can't submit a fake discounted total).
- **Only menu/restaurant/table data is directly readable** by the public
  key — which is intentional, since the QR menu has to work for a
  customer who isn't logged into anything.

What this does *not* yet cover: one restaurant's staff PIN currently
only works for that one restaurant because there's only one restaurant
in your database. The moment you add a second restaurant, you'd want to
scope each database function so restaurant A's PIN can't touch
restaurant B's orders. That's the next real step if you're onboarding
multiple restaurants — tell me when you're there and I'll add that
scoping. For a single-restaurant pilot, what's here now is solid.

---

## What's included vs. what's next

**Working now:** menu browsing, live cart, order creation, order closing
with payment method, table-based QR ordering, owner dashboard with real
sales/top-items/order-source queries filtered by day/week/month, staff
PIN login on both POS and dashboard (role-restricted), a live
**incoming orders panel on the POS** so staff see QR orders the moment
a customer places one (updates every 6 seconds, with buttons to move an
order from open → preparing → ready → closed), and a locked-down
database where writes and staff data only go through safe functions
instead of open table access.

**Stubbed / not yet built:** WhatsApp sending (see above — this one
depends on you getting Meta Business API access, not on me), kitchen
display (KDS) screen — note the incoming-orders panel on the POS
already covers the core of this, a dedicated kitchen-only screen is a
smaller follow-up, inventory deduction, cash reconciliation UI (table
exists, no screen yet), CSV menu import wizard, multi-restaurant
scoping (see security section above), multi-branch view.

Tell me which of these you want built next and I'll keep going.
