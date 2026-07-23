// Requires config.js and the Supabase CDN script to be loaded first.
const supa = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

let CURRENT_RESTAURANT = null; // populated by loadRestaurant()

async function loadRestaurant() {
  try {
    const { data, error } = await supa
      .from("restaurants")
      .select("*")
      .eq("slug", RESTAURANT_SLUG)
      .single();
    if (error) {
      console.error("Could not load restaurant — check config.js credentials/slug.", error);
      return null;
    }
    CURRENT_RESTAURANT = data;
    return data;
  } catch (err) {
    console.error("Network/connection error reaching Supabase — check config.js.", err);
    return null;
  }
}

// Swaps the plain "D" brand-mark for the restaurant's real logo, if it
// has one set. Falls back to the letter mark for restaurants without
// a logo_url (e.g. the demo data) — never left blank either way.
function applyBrandMark(elId) {
  const el = document.getElementById(elId);
  if (!el || !CURRENT_RESTAURANT) return;
  if (CURRENT_RESTAURANT.logo_url) {
    el.innerHTML = `<img src="${CURRENT_RESTAURANT.logo_url}" alt="${CURRENT_RESTAURANT.name}" class="brand-logo-img" onerror="this.parentElement.textContent='${(CURRENT_RESTAURANT.name || 'D')[0]}'">`;
  } else {
    el.textContent = (CURRENT_RESTAURANT.name || "D")[0];
  }
}

async function loadMenu(restaurantId) {
  const { data: categories, error: catErr } = await supa
    .from("categories")
    .select("*")
    .eq("restaurant_id", restaurantId)
    .order("sort_order");
  const { data: items, error: itemErr } = await supa
    .from("menu_items")
    .select("*")
    .eq("restaurant_id", restaurantId)
    .eq("is_available", true)
    .order("sort_order");
  if (catErr || itemErr) {
    console.error(catErr || itemErr);
    return [];
  }
  return categories.map((c) => ({
    ...c,
    items: items.filter((i) => i.category_id === c.id),
  }));
}

// Same as loadMenu but WITHOUT the is_available filter — used on the
// staff side (POS) so cashiers/waiters/owners/managers can see and
// toggle out-of-stock items, not just the ones customers can order.
async function loadFullMenu(restaurantId) {
  const { data: categories, error: catErr } = await supa
    .from("categories")
    .select("*")
    .eq("restaurant_id", restaurantId)
    .order("sort_order");
  const { data: items, error: itemErr } = await supa
    .from("menu_items")
    .select("*")
    .eq("restaurant_id", restaurantId)
    .order("sort_order");
  if (catErr || itemErr) {
    console.error(catErr || itemErr);
    return [];
  }
  return categories.map((c) => ({
    ...c,
    items: items.filter((i) => i.category_id === c.id),
  }));
}

// Marks a dish out of stock (or back in stock). Any signed-in staff
// member can call this — cashier/waiter/owner/manager all reach it
// through the POS, which is exactly the four roles the feature was
// asked for. Customer menu (loadMenu) already filters on is_available,
// so this takes effect the moment the customer's menu next polls.
async function setItemAvailability(itemId, isAvailable) {
  const { data, error } = await supa.rpc("set_item_availability", {
    p_item_id: itemId,
    p_is_available: isAvailable,
  });
  if (error || !data || data.length === 0) { console.error(error); return null; }
  return data[0];
}

// Creates an order + its line items via the create_order() database
// function — the client never inserts into orders/order_items/customers
// directly, so a stolen anon key can't forge arbitrary rows.
async function createOrder({ restaurantId, tableId, source, cart, customerPhone, staffId, marketingOptIn }) {
  const items = cart.map((l) => ({
    menu_item_id: l.id,
    name: l.name,
    price: l.price,
    qty: l.qty,
  }));
  const { data, error } = await supa.rpc("create_order", {
    p_restaurant_id: restaurantId,
    p_table_id: tableId || null,
    p_source: source,
    p_items: items,
    p_customer_phone: customerPhone || null,
    p_staff_id: staffId || null,
    p_marketing_opt_in: marketingOptIn !== undefined ? marketingOptIn : true,
  });
  if (error) {
    console.error(error);
    return null;
  }
  return data[0];
}

async function updateOrderStatus(orderId, status, paymentMethod) {
  const { error } = await supa.rpc("update_order_status", {
    p_order_id: orderId,
    p_status: status,
    p_payment_method: paymentMethod || null,
  });
  if (error) { console.error(error); return false; }
  return true;
}

// Returns every order still in progress (open/preparing/ready) for the
// staff-facing "incoming orders" panel — this is how a cashier sees a
// QR order the moment a customer places it, without refreshing blind.
async function getOpenOrders(restaurantId) {
  const { data, error } = await supa.rpc("get_open_orders", { p_restaurant_id: restaurantId });
  if (error) {
    console.error(error);
    return [];
  }
  return data;
}

// Checks a PIN via the check_staff_pin() database function. The staff
// table itself is not directly readable by the anon key — this never
// exposes passwords, only the matched staff member's id/name/role,
// and only when the password is correct and its role is in allowedRoles.
async function checkStaffPassword(restaurantId, password, allowedRoles) {
  const { data, error } = await supa.rpc("check_staff_password", {
    p_restaurant_id: restaurantId,
    p_password: password,
    p_allowed_roles: allowedRoles,
  });
  if (error || !data || data.length === 0) return null;
  return data[0];
}

async function getSalesSummary(restaurantId, since) {
  const { data, error } = await supa.rpc("get_sales_summary", { p_restaurant_id: restaurantId, p_since: since });
  if (error) { console.error(error); return { total_sales: 0, order_count: 0, avg_order: 0 }; }
  return data[0];
}
async function getTopItems(restaurantId, since, limit = 5) {
  const { data, error } = await supa.rpc("get_top_items", { p_restaurant_id: restaurantId, p_since: since, p_limit: limit });
  if (error) { console.error(error); return []; }
  return data;
}
async function getSourceSplit(restaurantId, since) {
  const { data, error } = await supa.rpc("get_source_split", { p_restaurant_id: restaurantId, p_since: since });
  if (error) { console.error(error); return []; }
  return data;
}
async function getRecentOrders(restaurantId, since, limit = 8) {
  const { data, error } = await supa.rpc("get_recent_orders", { p_restaurant_id: restaurantId, p_since: since, p_limit: limit });
  if (error) { console.error(error); return []; }
  return data;
}

async function ringBell(restaurantId, tableId) {
  const { data, error } = await supa.rpc("ring_bell", { p_restaurant_id: restaurantId, p_table_id: tableId });
  if (error) { console.error(error); return null; }
  return data;
}

async function getActiveCalls(restaurantId) {
  const { data, error } = await supa.rpc("get_active_calls", { p_restaurant_id: restaurantId });
  if (error) { console.error(error); return []; }
  return data;
}

async function acknowledgeCalls(tableId, staffId) {
  const { error } = await supa.rpc("acknowledge_calls", { p_table_id: tableId, p_staff_id: staffId || null });
  if (error) console.error(error);
}

async function getActiveOrderForTable(tableId) {
  const { data, error } = await supa.rpc("get_active_order_for_table", { p_table_id: tableId });
  if (error || !data || data.length === 0) return null;
  return data[0];
}

async function getOrderStatus(orderId) {
  const { data, error } = await supa.rpc("get_order_status", { p_order_id: orderId });
  if (error || !data || data.length === 0) return null;
  return data[0];
}

async function listStaff(restaurantId) {
  const { data, error } = await supa.rpc("list_staff", { p_restaurant_id: restaurantId });
  if (error) { console.error(error); return []; }
  return data;
}

async function addStaff(restaurantId, name, password, role) {
  const { data, error } = await supa.rpc("add_staff", {
    p_restaurant_id: restaurantId,
    p_name: name,
    p_password: password,
    p_role: role,
  });
  if (error) return { error: error.message };
  return { data: data[0] };
}

async function updateStaff(staffId, name, password, role) {
  const { data, error } = await supa.rpc("update_staff", {
    p_staff_id: staffId,
    p_name: name,
    p_password: password,
    p_role: role,
  });
  if (error) return { error: error.message };
  return { data: data[0] };
}

async function removeStaff(staffId) {
  const { error } = await supa.rpc("remove_staff", { p_staff_id: staffId });
  if (error) { console.error(error); return false; }
  return true;
}

// Builds a real, working WhatsApp link — no Meta Business API, no
// approval, no waiting, works today. It opens WhatsApp with the
// receipt text pre-filled in a chat with the RESTAURANT's own number;
// the customer taps Send. Two things happen from that one tap: the
// customer gets a copy of their receipt sitting in their own WhatsApp
// (their chat history with the restaurant), and the restaurant gains
// that customer's number as a real WhatsApp contact for future
// marketing — the same end goal as the original automated-send plan,
// just requiring one tap instead of happening silently.
//
// The trade-off, stated plainly: this can't fire on its own the moment
// an order is placed — a person has to tap the button. Fully silent,
// automatic sending needs the Meta WhatsApp Business Cloud API, which
// is free but requires Meta Business verification + template approval
// (days, not money). Swap this function out for that API later without
// changing anything else in the app — every call site just expects a
// URL back.
// Adds more items to an order that's already been placed — used when a
// customer rescans the table QR mid-meal and chooses "add to my order"
// instead of viewing the waiting page. Kitchen sees it because a
// preparing/ready order gets bumped back to "open".
async function addItemsToOrder(orderId, cart) {
  const items = cart.map((l) => ({ menu_item_id: l.id, name: l.name, price: l.price, qty: l.qty }));
  const { data, error } = await supa.rpc("add_items_to_order", { p_order_id: orderId, p_items: items });
  if (error || !data || data.length === 0) { console.error(error); return null; }
  return data[0];
}

// Replaces an order's full item list — used for editing/fixing an
// order (wrong item, wrong quantity), as opposed to addItemsToOrder
// which only ever adds more on top.
async function updateOrderItems(orderId, cart) {
  const items = cart.map((l) => ({ menu_item_id: l.id, name: l.name, price: l.price, qty: l.qty }));
  const { data, error } = await supa.rpc("update_order_items", { p_order_id: orderId, p_items: items });
  if (error || !data || data.length === 0) { console.error(error); return null; }
  return data[0];
}

async function voidOrder(orderId) {
  const { error } = await supa.rpc("void_order", { p_order_id: orderId });
  if (error) { console.error(error); return false; }
  return true;
}

async function listTables(restaurantId) {
  const { data, error } = await supa.rpc("list_tables", { p_restaurant_id: restaurantId });
  if (error) { console.error(error); return []; }
  return data;
}

async function addTable(restaurantId, label) {
  const { data, error } = await supa.rpc("add_table", { p_restaurant_id: restaurantId, p_label: label });
  if (error) return { error: error.message };
  return { data: data[0] };
}

async function removeTable(tableId) {
  const { error } = await supa.rpc("remove_table", { p_table_id: tableId });
  if (error) { console.error(error); return false; }
  return true;
}

// A stable per-device id (not tied to a login) so two phones scanning
// the same table's QR can be told apart as "player 1" / "player 2" in
// the waiting-room game, and so a page refresh doesn't lose your seat.
function getDeviceId() {
  const key = "dastarkhwan_device_id";
  let id = localStorage.getItem(key);
  if (!id) {
    id = (window.crypto && crypto.randomUUID) ? crypto.randomUUID() : `dev-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    localStorage.setItem(key, id);
  }
  return id;
}

function buildWhatsAppReceiptLink(order, cart) {
  if (!CURRENT_RESTAURANT.whatsapp_number) return null;
  const lines = cart.map((l) => `${l.qty}x ${l.name} - ${CURRENT_RESTAURANT.currency} ${Math.round(l.price * l.qty)}`);
  const text = [
    `Order receipt - ${CURRENT_RESTAURANT.name}`,
    "",
    ...lines,
    "",
    `Total: ${CURRENT_RESTAURANT.currency} ${Math.round(order.total)}`,
  ].join("\n");
  const digits = CURRENT_RESTAURANT.whatsapp_number.replace(/[^0-9]/g, "");
  return `https://wa.me/${digits}?text=${encodeURIComponent(text)}`;
}
