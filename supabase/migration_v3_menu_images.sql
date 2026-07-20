-- ============================================================
-- Migration: add photos to menu items (v3)
-- ------------------------------------------------------------
-- Run this if you already ran schema.sql before this update.
-- Safe to run more than once.
-- ============================================================

alter table menu_items add column if not exists image_url text;

update menu_items set image_url = 'https://loremflickr.com/400/300/seekhkebab,kebab' where name = 'Chicken Seekh Kebab' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/chaplikebab,kebab' where name = 'Chapli Kebab' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/samosa' where name = 'Vegetable Samosa (4pc)' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/dahibhalla,chaat' where name = 'Dahi Bhalla' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/chickenkarahi,curry' where name = 'Chicken Karahi (Full)' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/nihari,curry' where name = 'Beef Nihari' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/biryani' where name = 'Mutton Biryani' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/daalmakhani,lentils' where name = 'Daal Makhani' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/butterchicken,curry' where name = 'Butter Chicken' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/naanbread' where name = 'Roghni Naan' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/garlicnaan,naanbread' where name = 'Garlic Naan' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/tandooriroti,flatbread' where name = 'Tandoori Roti' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/limesoda,drink' where name = 'Fresh Lime Soda' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/mangolassi,drink' where name = 'Mango Lassi' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/softdrink,cola' where name = 'Soft Drink' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/gulabjamun,dessert' where name = 'Gulab Jamun (2pc)' and restaurant_id = '11111111-1111-1111-1111-111111111111';
update menu_items set image_url = 'https://loremflickr.com/400/300/kheer,ricepudding' where name = 'Kheer' and restaurant_id = '11111111-1111-1111-1111-111111111111';
