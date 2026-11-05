-- ==============================================================================
-- CAFE DE CASA SEED DATA (REPEATABLE & IDEMPOTENT)
-- ==============================================================================

-- 1. Insert Restaurant
INSERT INTO restaurants (id, name, tagline, description, phone, email, address, opening_hours, currency, currency_symbol)
VALUES (
    'a0000000-0000-0000-0000-000000000001',
    'Cafe de Casa',
    'Artisan Bistro, Curated Dining & Fine Beverages',
    'Where Art, Ambience & Gastronomy Meet. Crafted with 100% pure vegan integrity and French bistro finesse.',
    '+919876543210',
    'bonjour@cafedecasa.com',
    'Boulevard Montmartre Promenade, Heritage Quarter',
    'Open Daily 11:00 AM – 11:30 PM',
    'INR',
    '₹'
) ON CONFLICT (id) DO NOTHING;

-- 2. Insert Dining Tables
INSERT INTO dining_tables (id, restaurant_id, table_number, section, capacity) VALUES
    ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'TABLE 01', 'Veranda', 2),
    ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'TABLE 02', 'Veranda', 4),
    ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'TABLE 03', 'Garden Pavilion', 4),
    ('b0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'TABLE 04', 'Blossom Hall', 6),
    ('b0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'TABLE 05', 'Mezzanine Lounge', 2)
ON CONFLICT (id) DO NOTHING;

-- 3. Insert Table Token Hashes (SHA-256)
-- Only SHA-256 hex digests are stored in the database, never plaintext tokens.
INSERT INTO table_tokens (table_id, token_hash) VALUES
    -- Unexposed Cryptographic Production Tokens:
    -- TABLE 01 -> cdc_prod_t01_ee84bf679d5fbecfc467dc4f5932f8a5
    ('b0000000-0000-0000-0000-000000000001', 'ffbd3803b3b39d95487ff50160f33715562f3553afa238fb69c179ea9dc534f7'),
    -- TABLE 02 -> cdc_prod_t02_2b527409725bbc734e657aba42d6d08d
    ('b0000000-0000-0000-0000-000000000002', '6307ff283b7c280aa658332a403e32c0c2762155409c40ce6a96f5669cfccb33'),
    -- TABLE 03 -> cdc_prod_t03_20bc19ea2d0b20f1f9fea01baf8c7985
    ('b0000000-0000-0000-0000-000000000003', 'a948bcf93a816e52b0bfe4422f6993a951eb86bf3a992297eed03f3e9deb4530'),
    -- TABLE 04 -> cdc_prod_t04_39bf8f6c1d8b24f7766eb29fb3d55d24
    ('b0000000-0000-0000-0000-000000000004', '38d8564e6b3982a9796003acab4abfbfd45a1a1dbabae265aa8153b0a34070fc'),
    -- TABLE 05 -> cdc_prod_t05_0101e71b7f198951976b59e072a774e5
    ('b0000000-0000-0000-0000-000000000005', '878b82b978aefbbc93a30b65df61eaed0e1a410a856fc3a10b3a0889a3444871'),

    -- Testing-Only Demo Tokens (UNIQUE_TOKEN_01 through UNIQUE_TOKEN_05):
    ('b0000000-0000-0000-0000-000000000001', '6317373fab1c7637b29bac6f5ebb8b5a415d31d9480cce393fff2ff2b738d9ad'),
    ('b0000000-0000-0000-0000-000000000002', '34c66fcff0cb510ff571fbc1833b653ba2e30ee8938d396757581603a52f44a7'),
    ('b0000000-0000-0000-0000-000000000003', 'e783db72daa76f29c7dbe9f31f0aa74eff45bd76e28bf6b4ff4c6ff77ea8ec99'),
    ('b0000000-0000-0000-0000-000000000004', 'd2113d91b20e4a4b5d00ba31cae7dab92f79a478e2a4700b2ae8ffe92fceb7d4'),
    ('b0000000-0000-0000-0000-000000000005', '493c26e606da7ff78bc3899a119c2c466b625b26efab0f9fd50c2e96881d6107')
ON CONFLICT (token_hash) DO NOTHING;

-- 4. Insert Menu Categories
INSERT INTO menu_categories (id, restaurant_id, name, slug, subtitle, display_order) VALUES
    ('c0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Indian Tandoori & Street Chaat', 'starters-chaat', '— Hors-d''œuvre & Chaat —', 1),
    ('c0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Combos & Wholesome Meals', 'combos-meals', '— Plats Principaux & Combos —', 2),
    ('c0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Sandwiches & Burgers', 'sandwiches-burgers', '— Sandwiches & Casse-Croûte —', 3),
    ('c0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Pan-Asian Delights', 'pan-asian', '— Spécialités Asiatiques —', 4),
    ('c0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'Cold Pressed Juices & Beverages', 'beverages', '— Boissons & Rafraîchissements —', 5),
    ('c0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001', 'Signature Pastas', 'signature-pastas', '— Spécialités Du Chef —', 0)
ON CONFLICT (id) DO NOTHING;

-- 5. Insert Menu Items (With stable IDs and ON CONFLICT handling to prevent duplication)
INSERT INTO menu_items (id, restaurant_id, category_id, name, price, badge_label, is_vegan, is_available, display_order) VALUES
    ('e0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'Hara Bhara Kebab', 250, null, true, true, 1),
    ('e0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'Dahi Kebab', 275, 'Special', true, true, 2),
    ('e0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'Paneer Tikka', 350, 'Flavored', true, true, 3),
    ('e0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'Kandhari Mushroom Tikka', 400, null, true, true, 4),
    ('e0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'Tandoori Platter', 475, 'Chef''s Special', true, true, 5),
    ('e0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'Dahi Papdi Chaat', 130, null, true, true, 6),
    ('e0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'Pani Puri', 110, null, true, true, 7),
    ('e0000000-0000-0000-0000-000000000008', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000001', 'Mexican Cheese Vada Pav', 100, null, true, true, 8),

    -- Combos, Meals & Breads
    ('e0000000-0000-0000-0000-000000000009', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'Chole Bhature', 170, 'Popular', true, true, 1),
    ('e0000000-0000-0000-0000-000000000010', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'Pav Bhaji / Cheese Pav Bhaji', 175, null, true, true, 2),
    ('e0000000-0000-0000-0000-000000000011', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'Rice & Curry with Dal Makhani', 240, null, true, true, 3),
    ('e0000000-0000-0000-0000-000000000012', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'Royal Meal Combo: Butter Paneer', 320, 'Signature', true, true, 4),
    ('e0000000-0000-0000-0000-000000000013', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'Tandoori Paratha Platter (2 Pcs)', 200, null, true, true, 5),
    ('e0000000-0000-0000-0000-000000000014', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000002', 'Garlic Naan', 90, 'Tandoor Special', true, true, 6),

    -- Sandwiches & Burgers
    ('e0000000-0000-0000-0000-000000000015', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003', 'Avocado Toast', 220, 'Artisan', true, true, 1),
    ('e0000000-0000-0000-0000-000000000016', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003', 'Mumbai Masala Club Sandwich', 160, null, true, true, 2),
    ('e0000000-0000-0000-0000-000000000017', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003', 'Cheese Burst Sandwich', 190, null, true, true, 3),
    ('e0000000-0000-0000-0000-000000000018', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000003', 'Cafe de Casa Special Burger', 210, 'Bestseller', true, true, 4),

    -- Pan-Asian Delights
    ('e0000000-0000-0000-0000-000000000019', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000004', 'Honey Chilli Potato', 250, null, true, true, 1),
    ('e0000000-0000-0000-0000-000000000020', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000004', 'Burnt Garlic Noodles', 260, null, true, true, 2),
    ('e0000000-0000-0000-0000-000000000021', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000004', 'Thai Curry with Jasmine Rice', 375, 'Chef''s Pick', true, true, 3),
    ('e0000000-0000-0000-0000-000000000022', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000004', 'Veg Noodles with Manchurian Combo', 290, null, true, true, 4),

    -- Beverages & Juices
    ('e0000000-0000-0000-0000-000000000023', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000005', 'Power Punch Juice', 175, null, true, true, 1),
    ('e0000000-0000-0000-0000-000000000024', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000005', 'Green Glow Cleanser', 175, null, true, true, 2),
    ('e0000000-0000-0000-0000-000000000025', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000005', 'Cardamom or Masala Chai', 85, null, true, true, 3),
    ('e0000000-0000-0000-0000-000000000026', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000005', 'Hazelnut Latte / Hot Chocolate', 170, null, true, true, 4),

    -- Chef's Signature Pastas
    ('e0000000-0000-0000-0000-000000000027', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000006', 'Alfredo Pasta', 390, 'Customer Favorite', true, true, 1),
    ('e0000000-0000-0000-0000-000000000028', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000006', 'Pesto Pasta', 390, 'Chef Signature', true, true, 2),
    ('e0000000-0000-0000-0000-000000000029', 'a0000000-0000-0000-0000-000000000001', 'c0000000-0000-0000-0000-000000000006', 'Arrabbiata Pasta', 380, 'Spicy & Tangy', true, true, 3)
ON CONFLICT (restaurant_id, name) DO UPDATE SET
    price = EXCLUDED.price,
    badge_label = EXCLUDED.badge_label,
    is_available = EXCLUDED.is_available,
    display_order = EXCLUDED.display_order;
