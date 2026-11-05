-- ==============================================================================
-- CAFE DE CASA RESTAURANT SYSTEM SCHEMA - PRODUCTION-READY MVP
-- ==============================================================================
-- Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==============================================================================
-- 1. ENUMS & CUSTOM TYPES
-- ==============================================================================
DO $$ BEGIN
    CREATE TYPE order_status AS ENUM ('placed', 'confirmed', 'preparing', 'ready', 'served', 'completed', 'cancelled');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- ==============================================================================
-- 2. RESTAURANTS TABLE
-- ==============================================================================
CREATE TABLE IF NOT EXISTS restaurants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    tagline VARCHAR(255),
    description TEXT,
    logo_url TEXT,
    phone VARCHAR(50),
    email VARCHAR(255),
    address TEXT,
    currency VARCHAR(10) DEFAULT 'INR',
    currency_symbol VARCHAR(5) DEFAULT '₹',
    opening_hours VARCHAR(255) DEFAULT 'Open Daily 11:00 AM – 11:30 PM',
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 3. DINING TABLES
-- ==============================================================================
CREATE TABLE IF NOT EXISTS dining_tables (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    table_number VARCHAR(50) NOT NULL,
    section VARCHAR(100) DEFAULT 'Main Dining',
    capacity INT DEFAULT 4,
    qr_code_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(restaurant_id, table_number)
);

-- ==============================================================================
-- 4. TABLE TOKENS (Stores ONLY SHA-256 Hashes of tokens, never plaintext tokens)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS table_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id UUID NOT NULL REFERENCES dining_tables(id) ON DELETE CASCADE,
    token_hash VARCHAR(64) NOT NULL UNIQUE, -- SHA-256 hex digest (64 chars)
    is_revoked BOOLEAN DEFAULT false,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 5. MENU CATEGORIES
-- ==============================================================================
CREATE TABLE IF NOT EXISTS menu_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    slug VARCHAR(100) NOT NULL,
    subtitle VARCHAR(255),
    display_order INT DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(restaurant_id, slug)
);

-- ==============================================================================
-- 6. MENU ITEMS (Food items with stable uniqueness constraint)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS menu_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES menu_categories(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    badge_label VARCHAR(100),
    badge_type VARCHAR(50),
    image_url TEXT,
    is_vegan BOOLEAN DEFAULT true,
    is_featured BOOLEAN DEFAULT false,
    is_available BOOLEAN DEFAULT true,
    display_order INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(restaurant_id, name)
);

-- ==============================================================================
-- 7. ORDERS (Direct table association & idempotency key support)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
    table_id UUID NOT NULL REFERENCES dining_tables(id) ON DELETE CASCADE,
    order_number VARCHAR(50) NOT NULL UNIQUE,
    status order_status DEFAULT 'placed',
    total_amount NUMERIC(10, 2) NOT NULL DEFAULT 0.00,
    special_instructions TEXT,
    idempotency_key VARCHAR(100),
    placed_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 8. ORDER ITEMS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS order_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    menu_item_id UUID NOT NULL REFERENCES menu_items(id) ON DELETE RESTRICT,
    item_name VARCHAR(255) NOT NULL,
    quantity INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
    subtotal NUMERIC(10, 2) NOT NULL CHECK (subtotal >= 0),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 9. ORDER STATUS HISTORY (Audit trail & real-time tracking)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS order_status_history (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    from_status order_status,
    to_status order_status NOT NULL,
    remarks TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 10. INDEXES FOR HIGH PERFORMANCE
-- ==============================================================================
CREATE INDEX IF NOT EXISTS idx_tables_restaurant ON dining_tables(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_table_tokens_hash ON table_tokens(token_hash);
CREATE INDEX IF NOT EXISTS idx_categories_restaurant ON menu_categories(restaurant_id, display_order);
CREATE INDEX IF NOT EXISTS idx_menu_items_category ON menu_items(category_id, display_order);
CREATE INDEX IF NOT EXISTS idx_menu_items_restaurant ON menu_items(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_orders_table ON orders(table_id);
CREATE INDEX IF NOT EXISTS idx_orders_idempotency ON orders(idempotency_key);
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(restaurant_id, status);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);
CREATE INDEX IF NOT EXISTS idx_order_status_history_order ON order_status_history(order_id);

-- ==============================================================================
-- 11. SECURE RPC FOR TABLE-TOKEN RESOLUTION
-- Anonymous customers can only resolve valid table tokens; hashes are never exposed.
-- ==============================================================================
CREATE OR REPLACE FUNCTION resolve_table_by_token(raw_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    computed_hash VARCHAR(64);
    result JSONB;
BEGIN
    IF raw_token IS NULL OR length(trim(raw_token)) = 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Token is required');
    END IF;

    computed_hash := encode(digest(trim(raw_token), 'sha256'), 'hex');

    SELECT jsonb_build_object(
        'success', true,
        'table', jsonb_build_object(
            'id', t.id,
            'table_number', t.table_number,
            'section', t.section,
            'capacity', t.capacity,
            'restaurant_id', t.restaurant_id
        ),
        'restaurant', jsonb_build_object(
            'id', r.id,
            'name', r.name,
            'tagline', r.tagline,
            'currency', r.currency,
            'currency_symbol', r.currency_symbol
        )
    )
    INTO result
    FROM table_tokens tt
    JOIN dining_tables t ON t.id = tt.table_id
    JOIN restaurants r ON r.id = t.restaurant_id
    WHERE tt.token_hash = computed_hash
      AND tt.is_revoked = false
      AND (tt.expires_at IS NULL OR tt.expires_at > NOW())
      AND t.is_active = true
      AND r.is_active = true
    LIMIT 1;

    IF result IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired table token');
    END IF;

    RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION resolve_table_by_token(TEXT) TO anon, authenticated;

-- ==============================================================================
-- 12. SECURE SERVER-SIDE RPC FOR ORDER PLACEMENT
-- Validates token hash, verifies menu prices in PostgreSQL, prevents price tampering
-- ==============================================================================
CREATE OR REPLACE FUNCTION place_order_by_token(
    raw_token TEXT,
    items JSONB,
    special_instructions TEXT DEFAULT NULL,
    idempotency_key TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    computed_hash VARCHAR(64);
    target_table RECORD;
    new_order_id UUID;
    generated_order_number VARCHAR(50);
    computed_total NUMERIC(10, 2) := 0.00;
    item_record RECORD;
    found_menu_item RECORD;
    order_item_subtotal NUMERIC(10, 2);
    item_qty INT;
    confirmed_items JSONB := '[]'::jsonb;
    existing_order RECORD;
BEGIN
    IF raw_token IS NULL OR length(trim(raw_token)) = 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Table token is required.');
    END IF;

    IF items IS NULL OR jsonb_array_length(items) = 0 THEN
        RETURN jsonb_build_object('success', false, 'error', 'Order must contain at least one item.');
    END IF;

    computed_hash := encode(digest(trim(raw_token), 'sha256'), 'hex');

    SELECT t.id AS table_id, t.table_number, t.section, t.restaurant_id, r.name AS restaurant_name
    INTO target_table
    FROM table_tokens tt
    JOIN dining_tables t ON t.id = tt.table_id
    JOIN restaurants r ON r.id = t.restaurant_id
    WHERE tt.token_hash = computed_hash
      AND tt.is_revoked = false
      AND (tt.expires_at IS NULL OR tt.expires_at > NOW())
      AND t.is_active = true
      AND r.is_active = true
    LIMIT 1;

    IF target_table.table_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid or expired table token. Please rescan table QR code.');
    END IF;

    -- Idempotency check to prevent duplicate order placement
    IF idempotency_key IS NOT NULL AND length(trim(idempotency_key)) > 0 THEN
        SELECT id, order_number, total_amount, status, placed_at
        INTO existing_order
        FROM orders
        WHERE orders.idempotency_key = idempotency_key
          AND orders.table_id = target_table.table_id
        LIMIT 1;

        IF existing_order.id IS NOT NULL THEN
            RETURN jsonb_build_object(
                'success', true,
                'is_duplicate', true,
                'order', jsonb_build_object(
                    'id', existing_order.id,
                    'order_number', existing_order.order_number,
                    'table_number', target_table.table_number,
                    'table_section', target_table.section,
                    'total_amount', existing_order.total_amount,
                    'status', existing_order.status,
                    'placed_at', existing_order.placed_at
                )
            );
        END IF;
    END IF;

    generated_order_number := 'ORD-' || to_char(NOW(), 'YYMMDD') || '-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 5));

    INSERT INTO orders (
        restaurant_id,
        table_id,
        order_number,
        status,
        total_amount,
        special_instructions,
        idempotency_key,
        placed_at
    ) VALUES (
        target_table.restaurant_id,
        target_table.table_id,
        generated_order_number,
        'placed',
        0.00,
        special_instructions,
        idempotency_key,
        NOW()
    ) RETURNING id INTO new_order_id;

    FOR item_record IN SELECT * FROM jsonb_to_recordset(items) AS x(item_id UUID, item_name TEXT, quantity INT, notes TEXT)
    LOOP
        item_qty := COALESCE(item_record.quantity, 1);
        IF item_qty <= 0 OR item_qty > 100 THEN
            RAISE EXCEPTION 'Invalid quantity for item %', COALESCE(item_record.item_name, 'item');
        END IF;

        SELECT id, name, price, is_available
        INTO found_menu_item
        FROM menu_items
        WHERE restaurant_id = target_table.restaurant_id
          AND (
              (item_record.item_id IS NOT NULL AND id = item_record.item_id)
              OR (item_record.item_name IS NOT NULL AND (
                  lower(trim(name)) = lower(trim(item_record.item_name))
                  OR lower(name) LIKE '%' || lower(trim(item_record.item_name)) || '%'
              ))
          )
        LIMIT 1;

        IF found_menu_item.id IS NULL THEN
            RAISE EXCEPTION 'Item not found on menu: %', COALESCE(item_record.item_name, 'Unknown');
        END IF;

        IF found_menu_item.is_available = false THEN
            RAISE EXCEPTION 'Item currently unavailable: %', found_menu_item.name;
        END IF;

        order_item_subtotal := found_menu_item.price * item_qty;
        computed_total := computed_total + order_item_subtotal;

        INSERT INTO order_items (
            order_id,
            menu_item_id,
            item_name,
            quantity,
            unit_price,
            subtotal,
            notes
        ) VALUES (
            new_order_id,
            found_menu_item.id,
            found_menu_item.name,
            item_qty,
            found_menu_item.price,
            order_item_subtotal,
            item_record.notes
        );

        confirmed_items := confirmed_items || jsonb_build_object(
            'item_name', found_menu_item.name,
            'quantity', item_qty,
            'unit_price', found_menu_item.price,
            'subtotal', order_item_subtotal
        );
    END LOOP;

    UPDATE orders SET total_amount = computed_total WHERE id = new_order_id;

    INSERT INTO order_status_history (order_id, to_status, remarks)
    VALUES (new_order_id, 'placed', 'Order placed via customer QR token');

    RETURN jsonb_build_object(
        'success', true,
        'order', jsonb_build_object(
            'id', new_order_id,
            'order_number', generated_order_number,
            'table_number', target_table.table_number,
            'table_section', target_table.section,
            'status', 'placed',
            'total_amount', computed_total,
            'special_instructions', special_instructions,
            'placed_at', NOW(),
            'items', confirmed_items
        )
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

GRANT EXECUTE ON FUNCTION place_order_by_token(TEXT, JSONB, TEXT, TEXT) TO anon, authenticated;

-- ==============================================================================
-- 13. SECURE CUSTOMER ORDER STATUS CHECK
-- Allows anonymous customer to check their own order status safely without exposing other orders
-- ==============================================================================
CREATE OR REPLACE FUNCTION get_order_status_by_id(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    found_status order_status;
BEGIN
    SELECT status INTO found_status FROM orders WHERE id = p_order_id;
    IF found_status IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Order not found');
    END IF;
    RETURN jsonb_build_object('success', true, 'status', found_status);
END;
$$;

GRANT EXECUTE ON FUNCTION get_order_status_by_id(UUID) TO anon, authenticated;

-- ==============================================================================
-- 14. KITCHEN EXPEDITING RPCs (PROTECTED: AUTHENTICATED STAFF ONLY)
-- Anonymous users are strictly blocked.
-- ==============================================================================
CREATE OR REPLACE FUNCTION get_active_kitchen_orders()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    orders_data JSONB;
BEGIN
    -- Strict authorization check: Must be authenticated kitchen staff
    IF auth.role() != 'authenticated' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Kitchen staff authentication required.');
    END IF;

    SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
            'id', o.id,
            'order_number', o.order_number,
            'table_number', dt.table_number,
            'table_section', dt.section,
            'status', o.status,
            'total_amount', o.total_amount,
            'special_instructions', o.special_instructions,
            'placed_at', o.placed_at,
            'items', (
                SELECT COALESCE(jsonb_agg(
                    jsonb_build_object(
                        'id', oi.id,
                        'item_name', oi.item_name,
                        'quantity', oi.quantity,
                        'notes', oi.notes
                    )
                ), '[]'::jsonb)
                FROM order_items oi
                WHERE oi.order_id = o.id
            )
        ) ORDER BY o.placed_at ASC
    ), '[]'::jsonb)
    INTO orders_data
    FROM orders o
    JOIN dining_tables dt ON dt.id = o.table_id
    WHERE o.status IN ('placed', 'confirmed', 'preparing', 'ready');

    RETURN jsonb_build_object('success', true, 'orders', orders_data);
END;
$$;

-- Complete Kitchen Order (Updates status in PostgreSQL; does NOT delete record)
CREATE OR REPLACE FUNCTION complete_kitchen_order(p_order_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    target_order RECORD;
BEGIN
    -- Strict authorization check: Must be authenticated kitchen staff
    IF auth.role() != 'authenticated' THEN
        RETURN jsonb_build_object('success', false, 'error', 'Unauthorized: Kitchen staff authentication required.');
    END IF;

    SELECT * INTO target_order FROM orders WHERE id = p_order_id;
    IF target_order.id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Order not found.');
    END IF;

    -- Update status in PostgreSQL (preserves order record permanently)
    UPDATE orders
    SET status = 'completed', updated_at = NOW()
    WHERE id = p_order_id;

    INSERT INTO order_status_history (order_id, from_status, to_status, remarks)
    VALUES (p_order_id, target_order.status, 'completed', 'Expedited and completed by kitchen staff');

    RETURN jsonb_build_object('success', true, 'order_id', p_order_id, 'status', 'completed');
END;
$$;

-- Explicitly revoke from anon and grant ONLY to authenticated staff
REVOKE ALL ON FUNCTION get_active_kitchen_orders() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION get_active_kitchen_orders() TO authenticated;

REVOKE ALL ON FUNCTION complete_kitchen_order(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION complete_kitchen_order(UUID) TO authenticated;

-- ==============================================================================
-- 14. ROW LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================
ALTER TABLE restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE dining_tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE table_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_status_history ENABLE ROW LEVEL SECURITY;

-- Public / Anonymous Customers: Read-only access to menu & public restaurant info
CREATE POLICY "Public can view active restaurants"
    ON restaurants FOR SELECT
    USING (is_active = true);

CREATE POLICY "Public can view active menu categories"
    ON menu_categories FOR SELECT
    USING (is_active = true);

CREATE POLICY "Public can view available menu items"
    ON menu_items FOR SELECT
    USING (is_available = true);

-- Kitchen Staff (Authenticated role): Can read and update orders
CREATE POLICY "Authenticated kitchen staff can view orders"
    ON orders FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Authenticated kitchen staff can update orders"
    ON orders FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Authenticated kitchen staff can view order items"
    ON order_items FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Authenticated kitchen staff can view status history"
    ON order_status_history FOR SELECT
    TO authenticated
    USING (true);

-- Realtime Publication Enablement
DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE orders;
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE order_items;
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;
