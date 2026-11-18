-- ============================================================================
-- ORIGO · Esquema Central de Base de Datos (PostgreSQL 16+)
-- Equipo NexoTECH · Convocatoria CREATIC Casanare
-- Arquitectura: Event Sourcing (Ledger Inmutable) + Auth Híbrida + Compras Colectivas
-- Cumplimiento: Ley 1581 de 2012 (Habeas Data Colombia) & Capítulos 4.3, 4.4, 4.5
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ----------------------------------------------------------------------------
-- 1. Zonas y Municipios de Casanare (Geolocalización para Compras Colectivas)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS zones (
    id                  TEXT PRIMARY KEY,
    name                TEXT NOT NULL UNIQUE,
    municipality        TEXT NOT NULL,
    base_freight_cop    NUMERIC(12, 2) NOT NULL DEFAULT 120000.00,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 2. Comercios / Usuarios MiPyme (Minimización de datos - Ley 1581 de 2012)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
    id                      TEXT PRIMARY KEY,
    phone                   VARCHAR(20) NOT NULL UNIQUE,
    owner_name              VARCHAR(80) NOT NULL,
    business_name           VARCHAR(120) NOT NULL,
    zone_id                 TEXT NOT NULL REFERENCES zones(id),
    role                    VARCHAR(30) NOT NULL DEFAULT 'comerciante'
                            CHECK (role IN ('comerciante', 'coordinador_zona', 'admin_tic')),
    pin_salt                TEXT NOT NULL,
    pin_hash                TEXT NOT NULL,
    habeas_data_accepted    BOOLEAN NOT NULL CHECK (habeas_data_accepted = TRUE),
    habeas_data_accepted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_users_zone ON users(zone_id);

-- ----------------------------------------------------------------------------
-- 3. Sesiones y Dispositivos Vinculados (Revocación remota ante pérdida/robo)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS device_sessions (
    device_id           TEXT PRIMARY KEY,
    user_id             TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    refresh_token_hash  TEXT NOT NULL,
    device_label        VARCHAR(120),
    revoked             BOOLEAN NOT NULL DEFAULT FALSE,
    last_sync_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at          TIMESTAMPTZ NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_device_sessions_user ON device_sessions(user_id);

-- ----------------------------------------------------------------------------
-- 4. Catálogo Regional de Productos de Casanare
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS products (
    id                  TEXT PRIMARY KEY,
    name                VARCHAR(120) NOT NULL,
    category            VARCHAR(60) NOT NULL,
    default_unit        VARCHAR(30) NOT NULL,
    retail_price_cop    NUMERIC(12, 2) NOT NULL DEFAULT 0,
    wholesale_price_cop NUMERIC(12, 2) NOT NULL DEFAULT 0,
    min_threshold       NUMERIC(12, 2) NOT NULL DEFAULT 5,
    synonyms            JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ----------------------------------------------------------------------------
-- 5. Libro Mayor Inmutable de Inventario (Event Sourcing / Idempotencia UUID)
--    El núcleo Rust inserta con ON CONFLICT (id) DO NOTHING para cero duplicados.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS inventory_movements (
    id              UUID PRIMARY KEY,
    business_id     TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id      TEXT NOT NULL REFERENCES products(id),
    product_name    VARCHAR(120) NOT NULL,
    movement_type   VARCHAR(3) NOT NULL CHECK (movement_type IN ('IN', 'OUT')),
    quantity        NUMERIC(12, 2) NOT NULL CHECK (quantity > 0),
    unit            VARCHAR(30) NOT NULL,
    device_id       TEXT NOT NULL,
    occurred_at     TIMESTAMPTZ NOT NULL,
    synced_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_movements_business_time
    ON inventory_movements(business_id, occurred_at DESC);

CREATE INDEX IF NOT EXISTS idx_movements_business_product
    ON inventory_movements(business_id, product_id);

-- ----------------------------------------------------------------------------
-- 6. Central de Compras Colectivas (Consolidación Semanal por Zona)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS collective_orders (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    zone_id             TEXT NOT NULL REFERENCES zones(id),
    product_id          TEXT NOT NULL REFERENCES products(id),
    status              VARCHAR(20) NOT NULL DEFAULT 'OPEN'
                        CHECK (status IN ('OPEN', 'LOCKED', 'DISPATCHED', 'COMPLETED')),
    target_quantity     NUMERIC(12, 2) NOT NULL DEFAULT 100,
    total_quantity      NUMERIC(12, 2) NOT NULL DEFAULT 0,
    shared_freight_cop  NUMERIC(12, 2) NOT NULL DEFAULT 120000,
    estimated_saving_cop NUMERIC(14, 2) NOT NULL DEFAULT 0,
    opened_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at           TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS collective_order_items (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    collective_order_id UUID NOT NULL REFERENCES collective_orders(id) ON DELETE CASCADE,
    business_id         TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    quantity            NUMERIC(12, 2) NOT NULL CHECK (quantity > 0),
    unit                VARCHAR(30) NOT NULL,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (collective_order_id, business_id)
);

-- ----------------------------------------------------------------------------
-- 7. Bitácora de Auditoría de Seguridad (Sin datos sensibles - Cap. 4.4)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS security_audit_log (
    id              BIGSERIAL PRIMARY KEY,
    event_type      VARCHAR(50) NOT NULL,
    business_id     TEXT,
    device_id       TEXT,
    status          VARCHAR(20) NOT NULL,
    details         JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================================
-- VISTAS ANALÍTICAS Y OPERATIVAS (CÁLCULO REACTIVO DE EXISTENCIAS)
-- ============================================================================

-- Stock actual por tienda y alerta de reposición
CREATE OR REPLACE VIEW v_current_stock AS
SELECT
    u.id AS business_id,
    u.business_name,
    u.zone_id,
    p.id AS product_id,
    p.name AS product_name,
    p.default_unit AS unit,
    p.min_threshold,
    COALESCE(SUM(CASE WHEN m.movement_type = 'IN' THEN m.quantity ELSE -m.quantity END), 0) AS current_stock,
    (COALESCE(SUM(CASE WHEN m.movement_type = 'IN' THEN m.quantity ELSE -m.quantity END), 0) <= p.min_threshold) AS needs_reorder
FROM users u
CROSS JOIN products p
LEFT JOIN inventory_movements m
    ON m.business_id = u.id AND m.product_id = p.id
GROUP BY u.id, u.business_name, u.zone_id, p.id, p.name, p.default_unit, p.min_threshold;

-- Inventario diario exacto (00:00:00 - 23:59:59 hora Colombia America/Bogota)
CREATE OR REPLACE VIEW v_daily_inventory AS
WITH bounds AS (
    SELECT
        date_trunc('day', NOW() AT TIME ZONE 'America/Bogota') AT TIME ZONE 'America/Bogota' AS day_start,
        (date_trunc('day', NOW() AT TIME ZONE 'America/Bogota') + INTERVAL '1 day' - INTERVAL '1 microsecond') AT TIME ZONE 'America/Bogota' AS day_end
)
SELECT
    u.id AS business_id,
    p.id AS product_id,
    p.name AS product_name,
    p.default_unit AS unit,
    COALESCE(SUM(CASE WHEN m.occurred_at < b.day_start THEN (CASE WHEN m.movement_type = 'IN' THEN m.quantity ELSE -m.quantity END) ELSE 0 END), 0) AS opening_stock_0000,
    COALESCE(SUM(CASE WHEN m.occurred_at BETWEEN b.day_start AND b.day_end AND m.movement_type = 'IN' THEN m.quantity ELSE 0 END), 0) AS today_in,
    COALESCE(SUM(CASE WHEN m.occurred_at BETWEEN b.day_start AND b.day_end AND m.movement_type = 'OUT' THEN m.quantity ELSE 0 END), 0) AS today_out,
    COALESCE(SUM(CASE WHEN m.occurred_at <= b.day_end THEN (CASE WHEN m.movement_type = 'IN' THEN m.quantity ELSE -m.quantity END) ELSE 0 END), 0) AS closing_stock_2359
FROM users u
CROSS JOIN products p
CROSS JOIN bounds b
LEFT JOIN inventory_movements m
    ON m.business_id = u.id AND m.product_id = p.id
GROUP BY u.id, p.id, p.name, p.default_unit;

-- ============================================================================
-- DATOS SEMILLA DE CASANARE (IDEMPOTENTES)
-- ============================================================================
INSERT INTO zones (id, name, municipality, base_freight_cop) VALUES
    ('yopal_comuna_2', 'Comuna 2, Yopal', 'Yopal', 120000),
    ('yopal_comuna_5', 'Comuna 5, Yopal', 'Yopal', 120000),
    ('aguazul_centro', 'Centro, Aguazul', 'Aguazul', 130000),
    ('villanueva', 'Villanueva', 'Villanueva', 140000),
    ('tauramena', 'Tauramena', 'Tauramena', 140000),
    ('mani', 'Maní', 'Maní', 150000),
    ('paz_de_ariporo', 'Paz de Ariporo', 'Paz de Ariporo', 160000),
    ('monterrey', 'Monterrey', 'Monterrey', 145000)
ON CONFLICT (id) DO NOTHING;

INSERT INTO products (id, name, category, default_unit, retail_price_cop, wholesale_price_cop, min_threshold, synonyms) VALUES
    ('prod_arroz_casanare', 'Arroz Casanareño', 'Granos y Víveres', 'bultos', 185000, 155000, 10, '["arroz","arroz casanare","arros","arrosito"]'::jsonb),
    ('prod_aceite_vegetal', 'Aceite Vegetal 900ml', 'Víveres', 'cajas', 115000, 94000, 5, '["aceite","aceite vegetal","aceite de cocina"]'::jsonb),
    ('prod_panela_criolla', 'Panela Criolla', 'Víveres', 'pacas', 68000, 54000, 8, '["panela","panela criolla"]'::jsonb),
    ('prod_papa_pastusa', 'Papa Pastusa / Criolla', 'Perecederos', 'arrobas', 48000, 38000, 6, '["papa","papa pastusa","papa criolla"]'::jsonb),
    ('prod_abono_triple15', 'Abono Triple 15', 'Agroinsumos', 'bultos', 210000, 178000, 12, '["abono","triple 15","fertilizante"]'::jsonb),
    ('prod_cemento_gris', 'Cemento Gris 50kg', 'Ferretería', 'bultos', 34000, 28500, 20, '["cemento","cemento gris"]'::jsonb),
    ('prod_sal_marina', 'Sal Marina Refinada', 'Víveres', 'bultos', 55000, 43000, 5, '["sal","sal marina"]'::jsonb),
    ('prod_harina_pan', 'Harina de Maíz Precocida', 'Víveres', 'pacas', 72000, 59000, 7, '["harina","harina pan","harina de maiz"]'::jsonb)
ON CONFLICT (id) DO NOTHING;
