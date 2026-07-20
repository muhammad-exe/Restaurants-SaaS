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
  if (error) console.error(error);
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
// exposes PINs, only the matched staff member's id/name/role, and only
// when the PIN is correct and its role is in allowedRoles.
async function checkStaffPin(restaurantId, pin, allowedRoles) {
  const { data, error } = await supa.rpc("check_staff_pin", {
    p_restaurant_id: restaurantId,
    p_pin: pin,
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

async function getOrderStatus(orderId) {
  const { data, error } = await supa.rpc("get_order_status", { p_order_id: orderId });
  if (error || !data || data.length === 0) return null;
  return data[0];
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
