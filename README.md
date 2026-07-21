# Dastarkhwan Restaurant OS — Setup Guide

This is a real, working app — not a demo. Order data is saved to an actual
database, and it will keep working after you close the tab. Total cost to
run this for your first several restaurants: **$0/month.**

> **Already set up a Supabase project?** Ten migration files may apply
> to you, run in your Supabase SQL Editor in this order if you haven't
> already:
> 1. `supabase/migration_v2_security.sql` — locks down the database (see below)
> 2. `supabase/migration_v3_menu_images.sql` — adds photos to the demo menu items
> 3. `supabase/migration_v4_order_status.sql` — adds the function powering the customer's live order tracker
> 4. `supabase/migration_v5_whatsapp.sql` — fills in the demo restaurant's WhatsApp number
> 5. `supabase/migration_v6_fix_create_order.sql` — **fixes a real bug** that broke placing orders ("column reference item is ambiguous") — run this one even if you've already run everything else
> 6. `supabase/migration_v7_staff_management.sql` — adds the functions powering the new Staff panel on the owner dashboard
> 7. `supabase/migration_v8_staff_edit.sql` — adds the ability to edit an existing staff member, completing full CRUD
> 8. `supabase/migration_v9_receipt_printing.sql` — adds per-item pricing to incoming orders, needed for real receipt printing
> 9. `supabase/migration_v10_ring_bell_and_resume.sql` — adds the call-waiter ring bell system and order-resume-on-rescan
> 10. `supabase/migration_v11_password_login.sql` — **replaces 4-digit PINs with real hashed passwords** — your team's old PINs still work as their password after this runs, nobody gets locked out
>
> All are safe to run more than once and don't touch your existing
> tables or data.

It has three pages:
- `pos.html` — the cashier screen — now also shows **live incoming
  orders** (including QR orders customers placed themselves), and
  requires a staff password to open.
- `menu.html` — the customer-facing QR ordering page — no login, this
  one's meant to be open to anyone who scans the table code.
- `dashboard.html` — the owner's sales dashboard — requires an
  **owner/manager** account specifically; a cashier's password won't open it.

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

## Editable cart on the customer menu

Tapping "View order" on the QR menu now expands a full line-item list —
each item shows +/− quantity buttons and a Remove button, so a
customer who tapped the wrong dish (or changes their mind) can fix it
before placing the order, instead of only being able to add more.

## Call waiter — real ring bell, with escalation

The "Call waiter" button on the customer menu now actually does
something:
- It logs a real call to the database (with a 15-second cooldown so
  one accidental double-tap doesn't spam staff).
- Staff see it immediately on the POS in a red **"Tables calling for
  service"** panel, with a beep sound (generated in-browser — no audio
  file needed, works identically on the website, desktop app, and
  mobile app) and an **"On my way"** button to dismiss it.
- Each staff member can mute/unmute the beep for their own device via
  the 🔔/🔕 icon next to their name — this is per-device, not global,
  so muting it at the counter doesn't silence it on a waiter's phone.
- **The customer never gets a mute option** — only staff can mute the
  alert sound; the call itself always goes through.
- If a table rings **more than 5 times** without being acknowledged,
  it's flagged urgent, and a red banner appears on the **owner's**
  dashboard specifically — this is the escalation path when the floor
  staff seem to have missed it.
- **Browser sound rule, and how this handles it:** browsers (and
  mobile webviews) refuse to play any sound until the page has had at
  least one real tap — otherwise sites could blast audio the instant
  they load. The beep is "unlocked" the moment staff tap "Sign in" at
  login, then stays unlocked for the rest of that session, on the
  website, the desktop app, and the mobile app alike.

## Order resume — customer accidentally closes the tracker screen

If a customer places an order, then closes the tab or their phone
locks and they lose the tracker screen, scanning the **same table's
QR code again** now takes them straight back to their live order
tracker instead of showing the menu from scratch — as long as that
order hasn't been closed out yet. No login, no order number to
remember, just rescan the same code.

## Manager/owner password opening the cashier POS — this is correct

If you tried logging into `pos.html` with a manager or owner password
and it opened the full till screen — that's intentional, not a bug.
Only **waiter** accounts get the restricted "send to kitchen, no
payment" screen; owner, manager, and cashier all get full POS access,
since an owner or manager covering a shift should be able to do
everything a cashier can.

## Role-based POS behavior

The POS screen now looks different depending on who's logged in — same
app, same URL, no separate builds needed:

- **Waiter** — sees the menu and can build an order, but the button
  reads **"Send to kitchen"** instead of "Print receipt & close
  order," and there's no payment method selector. The order goes
  straight into the incoming-orders queue as `open`, same as a QR
  order would. In that same queue, a waiter can still move an order
  through "Start preparing" → "Mark ready" (kitchen coordination), but
  the final "Close & print receipt" step is replaced with **"Ask
  cashier to close"** — waiters can't take payment or trigger a print.
- **Cashier / Manager / Owner** — full access: build orders, take
  payment, print receipts, close out any order including ones a waiter
  sent in.

No new database changes were needed for this — it's driven entirely
by the `role` value already returned from the password check, applied
in `pos.html`'s `applyRolePermissions()` function.

## Receipt printing — how it actually works now

Clicking **"Print receipt & close order"** (or **"Close & print receipt"**
on an incoming QR order) now triggers a real browser print, formatted
to look like an actual thermal receipt — 80mm width, monospace, dashed
section dividers, itemized lines, totals, "Thank you" footer — instead
of just closing the order silently.

**How to actually connect a printer:**
1. Connect your thermal receipt printer to the till's computer/tablet
   the normal way (USB, or Bluetooth pairing in Windows/Android
   settings) — most receipt printers install as a regular system
   printer once connected, even though they print narrow receipt paper
   instead of full sheets.
2. The first time you click print in the app, your browser's print
   dialog appears — choose that printer from the list.
3. Most browsers let you set it as the **default printer for this
   site**, so future clicks skip the dialog and print straight away.

**Why this approach instead of raw ESC/POS commands:** sending raw
printer commands (via Web Bluetooth or Web USB) only works in specific
browsers, needs a pairing permission dialog nearly every session, and
doesn't work at all inside the Capacitor mobile app's webview. Using
the browser's own print function works with virtually any printer
already set up on the device, works identically in the website, the
desktop Electron app, and the mobile app, and needs zero extra
software. The trade-off: it can't automatically pop the cash drawer or
control paper-cut hardware the way raw ESC/POS commands sometimes can
— if a specific printer model needs that, tell me which model and I
can look into a targeted integration for it.

**Paper width:** set to 80mm (the most common size) in
`css/style.css` — search for `@page` and `.receipt-print-area` if your
printer uses 58mm paper instead; it's a couple of number changes.

## Menu photos

Every demo menu item now has a relevant photo, both in the customer QR
menu and on the cashier POS grid. These come from a free keyword-based
photo service (loremflickr.com) — good enough to demo, but they're
stock photos of the *dish type*, not your restaurant's actual food, so
swap them out before showing this to a real customer.

To set your own photo for an item: in Supabase's **Table Editor** →
`menu_items` → find the row → paste a direct image URL into the
`image_url` column. Any publicly accessible image URL works (e.g. one
you've uploaded to Supabase's free file **Storage**, or any image
hosting you already use). Leave it blank and the app just skips
showing a photo for that item — nothing breaks either way.

## Installing the POS as an app (no APK needed for most cases)

`pos.html` is now a proper installable app — on the tablet or phone
you'll use at the counter:

1. Open your live Vercel link → `pos.html` in Chrome.
2. Tap the browser menu → **"Add to Home Screen"** (Android) or
   **"Install app"** (if Chrome shows that prompt directly).
3. It installs a real icon on the home screen, opens full-screen with
   no browser address bar, and keeps working for a few minutes even if
   the wifi drops (it caches the app itself — not sales data, so it
   never shows stale numbers, just stays open instead of going blank).

This gets you 95% of what a native Android app gives you, with zero
app-store approval wait and instant updates whenever you redeploy.

**If you specifically need a real, sideloadable `.apk` file** — e.g. to
install without visiting a URL first, or to distribute to multiple
tablets at once — the fastest path is a free tool called
[PWABuilder.com](https://www.pwabuilder.com): paste in your live
`pos.html` URL, it reads the `manifest.json` already set up here, and
generates a signed Android package for you. I can't run that tool or
sign a package from here since it needs your live URL and a Google
signing key tied to your account, but the manifest and icons it needs
are already built and included in this project.

## Customer wait screen — order tracker + engaging content

After a customer places an order via QR, they now see:
- A **live progress tracker** (Order received → Preparing → Ready →
  Complete) that updates automatically every few seconds as staff move
  the order along in the POS's incoming-orders panel.
- A rotating **"while you wait"** card with short food facts, so the
  screen isn't just sitting there blank. Edit the `WAIT_FACTS` array
  near the bottom of `menu.html` to swap in facts about your actual
  restaurant, its history, or its specific dishes.

## WhatsApp integration — real and free, with one honest trade-off

**Cost was never actually the blocker here** — Meta's official WhatsApp
API is free for the volume a single restaurant needs. What blocks fully
silent, automatic sending is Meta's approval process (Business
verification + message template review), which takes days, not money.

So instead of waiting on that, the app now uses a different approach
that's **genuinely free and works today, zero signup required**:

- After a customer places an order, they see a **"Get my receipt on
  WhatsApp"** button.
- Tapping it opens WhatsApp with the full itemized receipt already
  typed into a chat with the restaurant's own WhatsApp number — they
  just tap Send.
- That one tap does two things at once: the customer keeps their
  receipt in their own WhatsApp chat history, and the restaurant gains
  that customer's number as a real contact for future offers — the
  same end goal as automatic sending, just requiring one tap instead
  of firing silently.

**The honest limitation:** this can't happen without the customer
tapping something — true zero-touch automation still needs the Meta
API. If getting Meta approval is worth it to you later, swap out
`buildWhatsAppReceiptLink()` in `js/supabaseClient.js` for a real API
call — the rest of the app doesn't need to change, since every call
site just expects a link back.

**Setup:** the restaurant's own WhatsApp number lives in the
`restaurants` table, column `whatsapp_number` — set it in Supabase's
Table Editor (digits only, with country code, no `+` or spaces, e.g.
`923001234567`). The demo data already has a placeholder number so you
can see the button working immediately.

## Adding your own restaurant instead of the demo one

In Supabase's **Table Editor**:
1. Add a row to `restaurants` (give it a unique `slug`, e.g. `my-restaurant`).
2. Add rows to `categories` and `menu_items` for that restaurant's `id`.
3. Add rows to `restaurant_tables` with unique `qr_token` values.
4. Update `RESTAURANT_SLUG` in `js/config.js` to match.

Once your on-spot setup wizard exists (see Phase 2 below), you won't need
to do this by hand — for now, the Table Editor works fine for onboarding
your first few pilot restaurants.

## Staff password login

Both `pos.html` and `dashboard.html` now open on a password sign-in
screen — a real text password field, not a 4-digit PIN pad.

- **POS** accepts any staff role (owner, manager, cashier, waiter).
- **Dashboard** only accepts `owner` or `manager` accounts — a
  cashier's password won't open it.
- The demo data includes two logins:
  - **Owner** — password `owner123` — works on both screens
  - **Ali (Cashier)** — password `cashier123` — POS only, dashboard
    will reject it

Add, remove, or edit staff (including setting their password) from
the **Staff panel on the owner dashboard** — no code changes, no
Supabase Table Editor needed. Every order created on the POS is
stamped with which staff member rang it up.

**Passwords are properly hashed now, not stored in plain text.** This
uses Postgres's `pgcrypto` extension (bcrypt-style hashing via
`crypt()`) — the actual password is never stored anywhere, only a
one-way hash of it, and even a full database leak wouldn't expose
anyone's real password. This is a genuine security upgrade over the
original PIN system, not just a longer PIN. Minimum length is 6
characters.

---

## Security model — what's actually locked down now

The public API key in `js/config.js` is meant to be public — it's
visible to anyone who views your website's code, by design, the same
way it works for every Supabase app. What matters is what that key is
*allowed to do*, and that's what changed:

- **The `staff` table is not readable at all** through the public key —
  not even indirectly. Password checks happen inside a database function
  (`check_staff_password`) that never returns the password or its hash,
  only whether it matched and who it belongs to. Passwords themselves
  are stored as one-way bcrypt-style hashes via Postgres's `pgcrypto`
  extension, never in plain text.
- **Orders, order items, customers, cash sessions, and expenses are not
  directly writable** through the public key. Every order is created
  through a `create_order` database function that calculates totals
  itself server-side (the browser can't submit a fake discounted total).
- **Only menu/restaurant/table data is directly readable** by the public
  key — which is intentional, since the QR menu has to work for a
  customer who isn't logged into anything.

What this does *not* yet cover: one restaurant's staff password
currently only works for that one restaurant because there's only one
restaurant in your database. The moment you add a second restaurant,
you'd want to scope each database function so restaurant A's staff
can't touch restaurant B's orders. That's the next real step if you're
onboarding multiple restaurants — tell me when you're there and I'll
add that scoping. For a single-restaurant pilot, what's here now is
solid.

---

## What's included vs. what's next

**Working now:** menu browsing with dish photos, an **editable cart**
(add/adjust/remove before ordering), order creation, order closing
with payment method, table-based QR ordering, owner dashboard with
real sales/top-items/order-source queries filtered by day/week/month
and **auto-refreshing every 20 seconds**, **real hashed password
login** on both POS and dashboard (role-restricted, full CRUD via the
Staff panel), a live **incoming orders panel on the POS**,
**role-based POS screens** (waiters can't take payment), **real
receipt printing**, a **live order tracker + rotating facts +
resume-on-rescan + a call-waiter button** on the customer's screen, a
**real call-waiter ring bell that reaches POS and the owner dashboard
together**, with staff mute and owner escalation past 5 rings, a **QR
code generator/printer page**, an **installable POS app** (PWA, with
a path to a real `.apk` via PWABuilder or the Capacitor project in
`native/mobile`), a working **desktop app** (`native/desktop`), a
**real, working WhatsApp receipt button** (tap-to-send, free, no Meta
approval needed), and a locked-down database where writes and staff
data only go through safe functions instead of open table access.

**Stubbed / not yet built:** fully silent/automatic WhatsApp sending
(possible later via Meta's API once you have approval — see above, not
required for the current tap-to-send version to work), a dedicated
kitchen-only display screen (the incoming-orders panel on the POS
covers the core of this already), inventory deduction, cash
reconciliation UI (table exists, no screen yet), CSV menu import
wizard, multi-restaurant account scoping (see security section above),
multi-branch view.

Tell me which of these you want built next and I'll keep going.
