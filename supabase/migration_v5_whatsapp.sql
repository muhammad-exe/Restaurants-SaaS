-- ============================================================
-- Migration: WhatsApp click-to-chat setup (v5)
-- ------------------------------------------------------------
-- Run this if you already ran schema.sql before this update.
-- Safe to run more than once.
-- ============================================================

-- whatsapp_number already exists as a column from the original schema —
-- this just fills in a demo value so the button works immediately.
update restaurants
set whatsapp_number = '923001234567'
where id = '11111111-1111-1111-1111-111111111111' and (whatsapp_number is null or whatsapp_number = '');
