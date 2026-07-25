-- ============================================================
-- Migration: owner-editable WhatsApp number (v17)
-- ------------------------------------------------------------
-- Chai Jaan's whatsapp_number was never set when it was onboarded in
-- migration_v15 — only the demo "Zaiqa Grill House" restaurant had a
-- number seeded. That's why the "Get my receipt on WhatsApp" button
-- on the customer menu has been showing "WhatsApp receipts aren't set
-- up for this restaurant yet." this whole time — not a bug, just a
-- missing value.
--
-- Run the one-off UPDATE below to fix Chai Jaan right now, then run
-- the function below it so you (or the owner) can change the number
-- anytime from the new Settings panel on the dashboard, instead of
-- needing Supabase's Table Editor.
--
-- Safe to run more than once.
-- ============================================================

-- ---------- One-off: set Chai Jaan's WhatsApp number now ----------
-- Replace the number below with the real one (country code, no +,
-- no spaces — e.g. 923001234567 for a Pakistani 0300-1234567 number),
-- then run this. Leave it out entirely if you'd rather set it from
-- the new dashboard Settings panel once the function below exists.
-- update restaurants set whatsapp_number = '92XXXXXXXXXX' where slug = 'chai-jaan';

-- ---------- Let the dashboard update it going forward ----------
create or replace function update_restaurant_settings(p_restaurant_id uuid, p_whatsapp_number text)
returns table (id uuid, whatsapp_number text)
language plpgsql security definer as $$
begin
  return query
    update restaurants
    set whatsapp_number = nullif(trim(p_whatsapp_number), '')
    where restaurants.id = p_restaurant_id
    returning restaurants.id, restaurants.whatsapp_number;
end;
$$;
grant execute on function update_restaurant_settings to anon;
