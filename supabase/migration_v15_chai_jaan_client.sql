-- ============================================================
-- Migration: onboard real client "Chai Jaan" (v15)
-- ------------------------------------------------------------
-- This does NOT touch or remove the demo "Zaiqa Grill House" data —
-- it adds a second, real restaurant: Chai Jaan, with its actual menu
-- (98 items across 18 categories, matching the menu photo you shared),
-- 8 starter tables (add more anytime from the dashboard's Tables
-- panel), and a starter owner/cashier login.
--
-- Also adds a `logo_url` column to restaurants (used by the header on
-- every screen), and sets Chai Jaan's logo to the real uploaded one.
--
-- IMPORTANT — after running this, you also need to change one line in
-- js/config.js:
--   const RESTAURANT_SLUG = "chai-jaan";
-- (it currently says "zaiqa-grill" — that's the demo data). Change
-- this AFTER running this migration, not before, or the site will
-- show "Could not connect" in between.
--
-- Starter login — CHANGE THESE before handing off to the client:
--   Owner:   password "chaijaan123"
--   Cashier: password "cashier123"
-- Change them from the dashboard's Staff panel once you're logged in.
--
-- Safe to run more than once EXCEPT the data insert itself — running
-- this a second time will create a SECOND "Chai Jaan" restaurant with
-- duplicate data. If you need to re-run just the column addition,
-- run only the first two lines below.
-- ============================================================

alter table restaurants add column if not exists logo_url text;

do $$
declare
  v_restaurant_id uuid;
  v_cat_burgers uuid;
  v_cat_sandwiches uuid;
  v_cat_chickenstrips uuid;
  v_cat_loadedfries uuid;
  v_cat_wings uuid;
  v_cat_specialchaat uuid;
  v_cat_chaijan uuid;
  v_cat_paratha uuid;
  v_cat_eggs uuid;
  v_cat_mocktails uuid;
  v_cat_smoothies uuid;
  v_cat_icecreamshakes uuid;
  v_cat_icecream uuid;
  v_cat_waffles uuid;
  v_cat_hotcoffee uuid;
  v_cat_icecoffee uuid;
  v_cat_frappe uuid;
  v_cat_beverages uuid;
begin
  insert into restaurants (name, slug, tax_rate, logo_url)
  values ('Chai Jaan', 'chai-jaan', 0.05, 'branding/chai-jaan-logo.png')
  returning id into v_restaurant_id;

  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Burgers', 1) returning id into v_cat_burgers;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Sandwiches & Wraps', 2) returning id into v_cat_sandwiches;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Chicken Strips', 3) returning id into v_cat_chickenstrips;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Loaded Fries', 4) returning id into v_cat_loadedfries;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Wings', 5) returning id into v_cat_wings;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Special Chaat', 6) returning id into v_cat_specialchaat;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Chai Jan', 7) returning id into v_cat_chaijan;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Paratha', 8) returning id into v_cat_paratha;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Eggs', 9) returning id into v_cat_eggs;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Mocktails', 10) returning id into v_cat_mocktails;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Smoothies', 11) returning id into v_cat_smoothies;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Ice Cream Shakes', 12) returning id into v_cat_icecreamshakes;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Ice Cream', 13) returning id into v_cat_icecream;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Waffles', 14) returning id into v_cat_waffles;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Hot Coffee', 15) returning id into v_cat_hotcoffee;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Ice Coffee', 16) returning id into v_cat_icecoffee;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Frappe', 17) returning id into v_cat_frappe;
  insert into categories (restaurant_id, name, sort_order) values (v_restaurant_id, 'Beverages', 18) returning id into v_cat_beverages;

  insert into menu_items (restaurant_id, category_id, name, price, image_url, sort_order) values
    (v_restaurant_id, v_cat_burgers, 'Classic Zingo', 550, 'https://loremflickr.com/400/300/burger,fastfood', 1),
    (v_restaurant_id, v_cat_burgers, 'Korean Zingo', 590, 'https://loremflickr.com/400/300/koreanburger,burger', 2),
    (v_restaurant_id, v_cat_burgers, 'Thai Zingo', 590, 'https://loremflickr.com/400/300/thaifood,burger', 3),
    (v_restaurant_id, v_cat_burgers, 'Smashed Classic Beef', 790, 'https://loremflickr.com/400/300/smashburger,beefburger', 4),
    (v_restaurant_id, v_cat_burgers, 'Smashed Mushroom Beef', 790, 'https://loremflickr.com/400/300/mushroomburger,beefburger', 5),
    (v_restaurant_id, v_cat_sandwiches, 'Chipotle Feast Sandwich', 670, 'https://loremflickr.com/400/300/sandwich,chipotle', 1),
    (v_restaurant_id, v_cat_sandwiches, 'Cocktail Sandwich', 750, 'https://loremflickr.com/400/300/clubsandwich,sandwich', 2),
    (v_restaurant_id, v_cat_sandwiches, 'Crispy Peri Peri Wrap', 530, 'https://loremflickr.com/400/300/chickenwrap,wrap', 3),
    (v_restaurant_id, v_cat_sandwiches, 'Crispy Chilli Blast Wrap', 530, 'https://loremflickr.com/400/300/spicywrap,wrap', 4),
    (v_restaurant_id, v_cat_chickenstrips, 'Fried Chicken Strips', 490, 'https://loremflickr.com/400/300/chickenstrips,friedchicken', 1),
    (v_restaurant_id, v_cat_chickenstrips, 'Nashville Chicken Fingers', 520, 'https://loremflickr.com/400/300/nashvillechicken,chickenfingers', 2),
    (v_restaurant_id, v_cat_chickenstrips, 'Sweet Chilli Chicken Strips', 500, 'https://loremflickr.com/400/300/chickentenders,chickenstrips', 3),
    (v_restaurant_id, v_cat_loadedfries, 'Plain Fries', 390, 'https://loremflickr.com/400/300/frenchfries', 1),
    (v_restaurant_id, v_cat_loadedfries, 'Smoky Kick Loaded Fries', 490, 'https://loremflickr.com/400/300/loadedfries,fries', 2),
    (v_restaurant_id, v_cat_loadedfries, 'Smoky Sriracha Fries', 490, 'https://loremflickr.com/400/300/srirachafries,fries', 3),
    (v_restaurant_id, v_cat_loadedfries, 'Crispy Sriracha Fries', 490, 'https://loremflickr.com/400/300/spicyfries,fries', 4),
    (v_restaurant_id, v_cat_wings, 'Korean Wings', 430, 'https://loremflickr.com/400/300/koreanwings,chickenwings', 1),
    (v_restaurant_id, v_cat_wings, 'Peri Peri Wings', 430, 'https://loremflickr.com/400/300/chickenwings,periperi', 2),
    (v_restaurant_id, v_cat_wings, 'Cocktail Fried Chicken Wings', 430, 'https://loremflickr.com/400/300/friedwings,chickenwings', 3),
    (v_restaurant_id, v_cat_specialchaat, 'Pani Puri', 390, 'https://loremflickr.com/400/300/panipuri,chaat', 1),
    (v_restaurant_id, v_cat_specialchaat, 'Meethi Puri', 390, 'https://loremflickr.com/400/300/chaat,indiansnack', 2),
    (v_restaurant_id, v_cat_specialchaat, 'Gappa Gotalo', 590, 'https://loremflickr.com/400/300/chaat,streetfood', 3),
    (v_restaurant_id, v_cat_specialchaat, 'Samosa Chaat', 490, 'https://loremflickr.com/400/300/samosachaat,samosa', 4),
    (v_restaurant_id, v_cat_specialchaat, 'Chai Jan Special Chaat', 490, 'https://loremflickr.com/400/300/chaat,streetfood', 5),
    (v_restaurant_id, v_cat_specialchaat, 'Bhalla Spicy Chaat', 390, 'https://loremflickr.com/400/300/dahibhalla,chaat', 6),
    (v_restaurant_id, v_cat_specialchaat, 'Mix Chaat', 390, 'https://loremflickr.com/400/300/chaat,indiansnack', 7),
    (v_restaurant_id, v_cat_specialchaat, 'Chana Chaat', 350, 'https://loremflickr.com/400/300/chanachaat,chickpeas', 8),
    (v_restaurant_id, v_cat_specialchaat, 'Dahi Baray', 350, 'https://loremflickr.com/400/300/dahibhalla,yogurt', 9),
    (v_restaurant_id, v_cat_chaijan, 'Doodh Patti', 160, 'https://loremflickr.com/400/300/chai,milktea', 1),
    (v_restaurant_id, v_cat_chaijan, 'Karak Tea', 160, 'https://loremflickr.com/400/300/karakchai,tea', 2),
    (v_restaurant_id, v_cat_chaijan, 'Cardamom Tea', 190, 'https://loremflickr.com/400/300/cardamomtea,chai', 3),
    (v_restaurant_id, v_cat_chaijan, 'Cinnamon Tea', 190, 'https://loremflickr.com/400/300/cinnamontea,tea', 4),
    (v_restaurant_id, v_cat_chaijan, 'Green Tea', 160, 'https://loremflickr.com/400/300/greentea', 5),
    (v_restaurant_id, v_cat_chaijan, 'Lemon Grass', 160, 'https://loremflickr.com/400/300/lemongrasstea,tea', 6),
    (v_restaurant_id, v_cat_chaijan, 'Black Tea', 130, 'https://loremflickr.com/400/300/blacktea,tea', 7),
    (v_restaurant_id, v_cat_paratha, 'Lachha Paratha', 290, 'https://loremflickr.com/400/300/paratha,flatbread', 1),
    (v_restaurant_id, v_cat_paratha, 'Beef Lachha Paratha', 590, 'https://loremflickr.com/400/300/beefparatha,paratha', 2),
    (v_restaurant_id, v_cat_paratha, 'Aalu Paratha', 290, 'https://loremflickr.com/400/300/alooparatha,paratha', 3),
    (v_restaurant_id, v_cat_paratha, 'Alu Cheese Paratha', 390, 'https://loremflickr.com/400/300/cheeseparatha,paratha', 4),
    (v_restaurant_id, v_cat_paratha, 'Cheese Paratha', 390, 'https://loremflickr.com/400/300/cheeseparatha,flatbread', 5),
    (v_restaurant_id, v_cat_paratha, 'BBQ Chicken Paratha', 440, 'https://loremflickr.com/400/300/chickenparatha,bbqchicken', 6),
    (v_restaurant_id, v_cat_paratha, 'BBQ Chicken Cheese Paratha', 590, 'https://loremflickr.com/400/300/chickencheeseparatha,paratha', 7),
    (v_restaurant_id, v_cat_paratha, 'Pizza Paratha', 490, 'https://loremflickr.com/400/300/pizzaparatha,paratha', 8),
    (v_restaurant_id, v_cat_paratha, 'Chocolate Paratha', 390, 'https://loremflickr.com/400/300/chocolateparatha,paratha', 9),
    (v_restaurant_id, v_cat_eggs, 'Omelette', 190, 'https://loremflickr.com/400/300/omelette,eggs', 1),
    (v_restaurant_id, v_cat_eggs, 'Special Omelette', 210, 'https://loremflickr.com/400/300/omelette,breakfast', 2),
    (v_restaurant_id, v_cat_eggs, 'Half Fry', 120, 'https://loremflickr.com/400/300/friedegg,eggs', 3),
    (v_restaurant_id, v_cat_mocktails, 'Mint Lemonade', 340, 'https://loremflickr.com/400/300/mintlemonade,mocktail', 1),
    (v_restaurant_id, v_cat_mocktails, 'Mint Margarita', 340, 'https://loremflickr.com/400/300/mintmocktail,margarita', 2),
    (v_restaurant_id, v_cat_mocktails, 'Lemon Margarita', 340, 'https://loremflickr.com/400/300/lemonmocktail,margarita', 3),
    (v_restaurant_id, v_cat_mocktails, 'Strawberry Margarita', 370, 'https://loremflickr.com/400/300/strawberrymocktail,margarita', 4),
    (v_restaurant_id, v_cat_mocktails, 'Blue Margarita', 370, 'https://loremflickr.com/400/300/bluemocktail,margarita', 5),
    (v_restaurant_id, v_cat_mocktails, 'Pina Colada', 560, 'https://loremflickr.com/400/300/pinacolada,mocktail', 6),
    (v_restaurant_id, v_cat_mocktails, 'Peach Colada', 560, 'https://loremflickr.com/400/300/peachdrink,mocktail', 7),
    (v_restaurant_id, v_cat_mocktails, 'Strawberry Colada', 560, 'https://loremflickr.com/400/300/strawberrydrink,mocktail', 8),
    (v_restaurant_id, v_cat_mocktails, 'Cold Coffee', 620, 'https://loremflickr.com/400/300/coldcoffee,icedcoffee', 9),
    (v_restaurant_id, v_cat_mocktails, 'Blue Lagoon', 370, 'https://loremflickr.com/400/300/bluelagoon,mocktail', 10),
    (v_restaurant_id, v_cat_mocktails, 'Peach Ice Tea', 370, 'https://loremflickr.com/400/300/peachicetea,icedtea', 11),
    (v_restaurant_id, v_cat_mocktails, 'Strawberry Ice Tea', 370, 'https://loremflickr.com/400/300/strawberryicetea,icedtea', 12),
    (v_restaurant_id, v_cat_smoothies, 'Strawberry Smoothie', 410, 'https://loremflickr.com/400/300/strawberrysmoothie,smoothie', 1),
    (v_restaurant_id, v_cat_smoothies, 'Blueberry Smoothie', 410, 'https://loremflickr.com/400/300/blueberrysmoothie,smoothie', 2),
    (v_restaurant_id, v_cat_smoothies, 'Peach Smoothie', 410, 'https://loremflickr.com/400/300/peachsmoothie,smoothie', 3),
    (v_restaurant_id, v_cat_smoothies, 'Meethi Lassi', 390, 'https://loremflickr.com/400/300/sweetlassi,lassi', 4),
    (v_restaurant_id, v_cat_smoothies, 'Namkeen Lassi', 390, 'https://loremflickr.com/400/300/saltylassi,lassi', 5),
    (v_restaurant_id, v_cat_icecreamshakes, 'Vanilla Shake', 480, 'https://loremflickr.com/400/300/vanillashake,milkshake', 1),
    (v_restaurant_id, v_cat_icecreamshakes, 'Chocolate Shake', 480, 'https://loremflickr.com/400/300/chocolateshake,milkshake', 2),
    (v_restaurant_id, v_cat_icecreamshakes, 'Strawberry Shake', 480, 'https://loremflickr.com/400/300/strawberryshake,milkshake', 3),
    (v_restaurant_id, v_cat_icecreamshakes, 'Fresh Banana Shake', 390, 'https://loremflickr.com/400/300/bananashake,milkshake', 4),
    (v_restaurant_id, v_cat_icecreamshakes, 'Oreo Shake', 590, 'https://loremflickr.com/400/300/oreoshake,milkshake', 5),
    (v_restaurant_id, v_cat_icecreamshakes, 'Kitkat Shake', 590, 'https://loremflickr.com/400/300/kitkatshake,milkshake', 6),
    (v_restaurant_id, v_cat_icecream, 'Strawberry Single Scoop', 340, 'https://loremflickr.com/400/300/strawberryicecream,icecream', 1),
    (v_restaurant_id, v_cat_icecream, 'Strawberry Double Scoop', 380, 'https://loremflickr.com/400/300/strawberryicecream,icecream', 2),
    (v_restaurant_id, v_cat_icecream, 'Vanilla Single Scoop', 340, 'https://loremflickr.com/400/300/vanillaicecream,icecream', 3),
    (v_restaurant_id, v_cat_icecream, 'Vanilla Double Scoop', 380, 'https://loremflickr.com/400/300/vanillaicecream,icecream', 4),
    (v_restaurant_id, v_cat_icecream, 'Chocolate Single Scoop', 340, 'https://loremflickr.com/400/300/chocolateicecream,icecream', 5),
    (v_restaurant_id, v_cat_icecream, 'Chocolate Double Scoop', 380, 'https://loremflickr.com/400/300/chocolateicecream,icecream', 6),
    (v_restaurant_id, v_cat_waffles, 'Kitkat Waffle', 700, 'https://loremflickr.com/400/300/kitkatwaffle,waffle', 1),
    (v_restaurant_id, v_cat_waffles, 'Oreo Waffle', 700, 'https://loremflickr.com/400/300/oreowaffle,waffle', 2),
    (v_restaurant_id, v_cat_waffles, 'Lotus Waffle', 700, 'https://loremflickr.com/400/300/lotuswaffle,waffle', 3),
    (v_restaurant_id, v_cat_waffles, 'Choco Crispies Waffle', 700, 'https://loremflickr.com/400/300/chocolatewaffle,waffle', 4),
    (v_restaurant_id, v_cat_hotcoffee, 'Cappuccino', 430, 'https://loremflickr.com/400/300/cappuccino,hotcoffee', 1),
    (v_restaurant_id, v_cat_hotcoffee, 'Cafe Latte', 300, 'https://loremflickr.com/400/300/cafelatte,coffee', 2),
    (v_restaurant_id, v_cat_hotcoffee, 'Americano', 300, 'https://loremflickr.com/400/300/americano,coffee', 3),
    (v_restaurant_id, v_cat_hotcoffee, 'Espresso', 220, 'https://loremflickr.com/400/300/espresso,coffee', 4),
    (v_restaurant_id, v_cat_hotcoffee, 'Caramel Coffee', 560, 'https://loremflickr.com/400/300/caramelcoffee,coffee', 5),
    (v_restaurant_id, v_cat_hotcoffee, 'Vanilla Coffee', 560, 'https://loremflickr.com/400/300/vanillacoffee,coffee', 6),
    (v_restaurant_id, v_cat_hotcoffee, 'Hazelnut Coffee', 560, 'https://loremflickr.com/400/300/hazelnutcoffee,coffee', 7),
    (v_restaurant_id, v_cat_icecoffee, 'Cappuccino', 530, 'https://loremflickr.com/400/300/icedcappuccino,icedcoffee', 1),
    (v_restaurant_id, v_cat_icecoffee, 'Cafe Latte', 590, 'https://loremflickr.com/400/300/icedlatte,icedcoffee', 2),
    (v_restaurant_id, v_cat_icecoffee, 'Caramel', 590, 'https://loremflickr.com/400/300/icedcaramelcoffee,icedcoffee', 3),
    (v_restaurant_id, v_cat_icecoffee, 'Vanilla', 590, 'https://loremflickr.com/400/300/icedvanillacoffee,icedcoffee', 4),
    (v_restaurant_id, v_cat_icecoffee, 'Hazelnut', 590, 'https://loremflickr.com/400/300/icedhazelnutcoffee,icedcoffee', 5),
    (v_restaurant_id, v_cat_frappe, 'Caramel Frappe', 780, 'https://loremflickr.com/400/300/caramelfrappe,frappe', 1),
    (v_restaurant_id, v_cat_frappe, 'Vanilla Frappe', 780, 'https://loremflickr.com/400/300/vanillafrappe,frappe', 2),
    (v_restaurant_id, v_cat_frappe, 'Hazelnut Frappe', 780, 'https://loremflickr.com/400/300/hazelnutfrappe,frappe', 3),
    (v_restaurant_id, v_cat_beverages, 'Mineral Water Small', 120, 'https://loremflickr.com/400/300/mineralwater,waterbottle', 1),
    (v_restaurant_id, v_cat_beverages, 'Mineral Water Large', 140, 'https://loremflickr.com/400/300/mineralwater,waterbottle', 2),
    (v_restaurant_id, v_cat_beverages, 'Soft Drinks', 100, 'https://loremflickr.com/400/300/softdrink,cola', 3);

  insert into restaurant_tables (restaurant_id, label, qr_token) values
    (v_restaurant_id, 'Table 1', 'cj-t1'),
    (v_restaurant_id, 'Table 2', 'cj-t2'),
    (v_restaurant_id, 'Table 3', 'cj-t3'),
    (v_restaurant_id, 'Table 4', 'cj-t4'),
    (v_restaurant_id, 'Table 5', 'cj-t5'),
    (v_restaurant_id, 'Table 6', 'cj-t6'),
    (v_restaurant_id, 'Table 7', 'cj-t7'),
    (v_restaurant_id, 'Table 8', 'cj-t8');

  insert into staff (restaurant_id, name, password_hash, role) values
    (v_restaurant_id, 'Owner', crypt('chaijaan123', gen_salt('bf')), 'owner'),
    (v_restaurant_id, 'Cashier', crypt('cashier123', gen_salt('bf')), 'cashier');

end $$;
