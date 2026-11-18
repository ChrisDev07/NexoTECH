//! Libro Mayor Inmutable (Event Sourcing Ledger) en Rust + SQLite para Origo.
//! Garantiza cero pérdida de información y cálculo diario exacto (00:00 – 23:59).

use crate::collective::CollectiveOrderInput;
use crate::models::{
    now_unix_secs, round2, CatalogProduct, DailyStockItem, DailyStockResponse, DailyStockSummary,
    Movement, MovementView, StockItem,
};
use chrono::{Local, NaiveDate, TimeZone};
use rusqlite::{params, Connection, OptionalExtension};
use std::collections::HashMap;
use std::sync::Mutex;

pub fn day_bounds_local(target_date: Option<NaiveDate>) -> (NaiveDate, f64, f64) {
    let date = target_date.unwrap_or_else(|| Local::now().date_naive());
    let start_naive = date.and_hms_opt(0, 0, 0).unwrap();
    let end_naive = date.and_hms_micro_opt(23, 59, 59, 999_999).unwrap();

    let start_ts = Local
        .from_local_datetime(&start_naive)
        .earliest()
        .map(|dt| dt.timestamp() as f64)
        .unwrap_or(0.0);
    let end_ts = Local
        .from_local_datetime(&end_naive)
        .latest()
        .map(|dt| dt.timestamp() as f64 + 0.999_999)
        .unwrap_or(start_ts + 86399.999_999);

    (date, start_ts, end_ts)
}

pub fn format_hhmm_local(ts_secs: f64) -> String {
    let secs = ts_secs.floor() as i64;
    Local
        .timestamp_opt(secs, 0)
        .single()
        .map(|dt| dt.format("%H:%M").to_string())
        .unwrap_or_else(|| "Hoy".to_string())
}

pub struct LocalLedger {
    conn: Mutex<Connection>,
}

impl LocalLedger {
    pub fn open(db_path: &str) -> rusqlite::Result<Self> {
        let conn = if db_path == ":memory:" {
            Connection::open_in_memory()?
        } else {
            Connection::open(db_path)?
        };
        let ledger = Self {
            conn: Mutex::new(conn),
        };
        ledger.create_tables()?;
        Ok(ledger)
    }

    fn create_tables(&self) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute_batch(
            "
            CREATE TABLE IF NOT EXISTS movements (
                id TEXT PRIMARY KEY,
                business_id TEXT NOT NULL,
                product_id TEXT NOT NULL,
                product_name TEXT NOT NULL,
                type TEXT NOT NULL,
                quantity REAL NOT NULL,
                unit TEXT NOT NULL,
                timestamp REAL NOT NULL,
                device_id TEXT NOT NULL,
                synced INTEGER NOT NULL
            );
            CREATE TABLE IF NOT EXISTS custom_products (
                id TEXT PRIMARY KEY,
                business_id TEXT NOT NULL,
                name TEXT NOT NULL,
                category TEXT NOT NULL,
                default_unit TEXT NOT NULL,
                min_threshold REAL NOT NULL,
                retail_price_cop REAL NOT NULL DEFAULT 0,
                wholesale_price_cop REAL NOT NULL DEFAULT 0,
                synonyms_json TEXT NOT NULL DEFAULT '[]',
                created_at REAL NOT NULL
            );
            CREATE TABLE IF NOT EXISTS collective_contributions (
                id TEXT PRIMARY KEY,
                zone TEXT NOT NULL,
                business_id TEXT NOT NULL,
                business_name TEXT NOT NULL,
                product_id TEXT NOT NULL,
                product_name TEXT NOT NULL,
                quantity REAL NOT NULL,
                unit TEXT NOT NULL,
                retail_price_cop REAL NOT NULL,
                wholesale_price_cop REAL NOT NULL,
                created_at REAL NOT NULL
            );
            ",
        )?;
        Ok(())
    }

    pub fn record_movement(&self, m: &Movement) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "INSERT OR REPLACE INTO movements
            (id, business_id, product_id, product_name, type, quantity, unit, timestamp, device_id, synced)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            params![
                m.id,
                m.business_id,
                m.product_id,
                m.product_name,
                m.movement_type,
                m.quantity,
                m.unit,
                m.timestamp,
                m.device_id,
                if m.synced { 1 } else { 0 }
            ],
        )?;
        Ok(())
    }

    pub fn get_all_movements(&self, business_id: Option<&str>) -> rusqlite::Result<Vec<Movement>> {
        let conn = self.conn.lock().unwrap();
        let mut results = Vec::new();

        if let Some(bid) = business_id {
            let mut stmt = conn.prepare(
                "SELECT id, business_id, product_id, product_name, type, quantity, unit, timestamp, device_id, synced
                 FROM movements WHERE business_id = ?1 ORDER BY timestamp ASC",
            )?;
            let rows = stmt.query_map(params![bid], Self::row_to_movement)?;
            for r in rows {
                results.push(r?);
            }
        } else {
            let mut stmt = conn.prepare(
                "SELECT id, business_id, product_id, product_name, type, quantity, unit, timestamp, device_id, synced
                 FROM movements ORDER BY timestamp ASC",
            )?;
            let rows = stmt.query_map([], Self::row_to_movement)?;
            for r in rows {
                results.push(r?);
            }
        }

        Ok(results)
    }

    pub fn get_movements_for_api(&self, business_id: &str) -> rusqlite::Result<Vec<MovementView>> {
        let (_, start_ts, end_ts) = day_bounds_local(None);
        let mut views: Vec<MovementView> = self
            .get_all_movements(Some(business_id))?
            .into_iter()
            .map(|m| {
                let is_today = m.timestamp >= start_ts && m.timestamp <= end_ts;
                let time_str = if is_today {
                    format_hhmm_local(m.timestamp)
                } else {
                    "Saldo 00:00".to_string()
                };
                MovementView {
                    movement: m,
                    is_today,
                    time_str,
                }
            })
            .collect();
        views.reverse(); // Más recientes primero
        Ok(views)
    }

    pub fn compute_stock(
        &self,
        catalog: &[CatalogProduct],
        business_id: &str,
    ) -> rusqlite::Result<Vec<StockItem>> {
        let movements = self.get_all_movements(Some(business_id))?;
        let mut stock_map: HashMap<String, f64> = HashMap::new();
        for m in movements {
            let entry = stock_map.entry(m.product_id).or_insert(0.0);
            if m.movement_type == "IN" {
                *entry += m.quantity;
            } else if m.movement_type == "OUT" {
                *entry -= m.quantity;
            }
        }

        Ok(catalog
            .iter()
            .map(|prod| {
                let current_qty = stock_map.get(&prod.id).copied().unwrap_or(0.0);
                StockItem {
                    product_id: prod.id.clone(),
                    product_name: prod.name.clone(),
                    category: prod.category.clone(),
                    current_stock: round2(current_qty),
                    unit: prod.default_unit.clone(),
                    min_threshold: prod.min_threshold,
                    needs_reorder: current_qty <= prod.min_threshold,
                    retail_price_cop: prod.retail_price_cop,
                    wholesale_price_cop: prod.wholesale_price_cop,
                }
            })
            .collect())
    }

    pub fn compute_daily_stock(
        &self,
        catalog: &[CatalogProduct],
        business_id: &str,
        target_date: Option<NaiveDate>,
    ) -> rusqlite::Result<DailyStockResponse> {
        let (date, start_ts, end_ts) = day_bounds_local(target_date);
        let movements = self.get_all_movements(Some(business_id))?;

        let mut opening_map: HashMap<String, f64> = HashMap::new();
        let mut today_in_map: HashMap<String, f64> = HashMap::new();
        let mut today_out_map: HashMap<String, f64> = HashMap::new();
        let mut today_count_map: HashMap<String, usize> = HashMap::new();
        let mut last_ts_map: HashMap<String, f64> = HashMap::new();

        let mut total_in_today = 0.0;
        let mut total_out_today = 0.0;
        let mut total_movements_today = 0usize;

        for m in movements {
            if m.timestamp < start_ts {
                let delta = if m.movement_type == "IN" {
                    m.quantity
                } else {
                    -m.quantity
                };
                *opening_map.entry(m.product_id).or_insert(0.0) += delta;
            } else if m.timestamp >= start_ts && m.timestamp <= end_ts {
                total_movements_today += 1;
                *today_count_map.entry(m.product_id.clone()).or_insert(0) += 1;
                last_ts_map
                    .entry(m.product_id.clone())
                    .and_modify(|ts| {
                        if m.timestamp > *ts {
                            *ts = m.timestamp;
                        }
                    })
                    .or_insert(m.timestamp);

                if m.movement_type == "IN" {
                    *today_in_map.entry(m.product_id).or_insert(0.0) += m.quantity;
                    total_in_today += m.quantity;
                } else if m.movement_type == "OUT" {
                    *today_out_map.entry(m.product_id).or_insert(0.0) += m.quantity;
                    total_out_today += m.quantity;
                }
            }
        }

        let mut critical_count = 0usize;
        let mut items = Vec::with_capacity(catalog.len());

        for prod in catalog {
            let opening_qty = round2(opening_map.get(&prod.id).copied().unwrap_or(0.0));
            let in_today = round2(today_in_map.get(&prod.id).copied().unwrap_or(0.0));
            let out_today = round2(today_out_map.get(&prod.id).copied().unwrap_or(0.0));
            let current_qty = round2(opening_qty + in_today - out_today);
            let needs_reorder = current_qty <= prod.min_threshold;
            if needs_reorder {
                critical_count += 1;
            }
            let count = today_count_map.get(&prod.id).copied().unwrap_or(0);
            let last_movement_time = last_ts_map.get(&prod.id).map(|&ts| format_hhmm_local(ts));

            items.push(DailyStockItem {
                product_id: prod.id.clone(),
                product_name: prod.name.clone(),
                category: prod.category.clone(),
                opening_stock: opening_qty,
                today_in: in_today,
                today_out: out_today,
                daily_net: round2(in_today - out_today),
                current_stock: current_qty,
                has_activity_today: count > 0,
                today_movements_count: count,
                last_movement_time,
                unit: prod.default_unit.clone(),
                min_threshold: prod.min_threshold,
                needs_reorder,
                retail_price_cop: prod.retail_price_cop,
                wholesale_price_cop: prod.wholesale_price_cop,
            });
        }

        Ok(DailyStockResponse {
            date: date.format("%Y-%m-%d").to_string(),
            window: "00:00 - 23:59".to_string(),
            summary: DailyStockSummary {
                total_in_today: round2(total_in_today),
                total_out_today: round2(total_out_today),
                movements_count_today: total_movements_today,
                critical_products_count: critical_count,
            },
            items,
        })
    }

    pub fn get_pending_sync_movements(&self, business_id: &str) -> rusqlite::Result<Vec<Movement>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, business_id, product_id, product_name, type, quantity, unit, timestamp, device_id, synced
             FROM movements WHERE synced = 0 AND business_id = ?1",
        )?;
        let rows = stmt.query_map(params![business_id], Self::row_to_movement)?;
        let mut results = Vec::new();
        for r in rows {
            results.push(r?);
        }
        Ok(results)
    }

    pub fn mark_as_synced(&self, ids: &[String]) -> rusqlite::Result<()> {
        let mut conn = self.conn.lock().unwrap();
        let tx = conn.transaction()?;
        for id in ids {
            tx.execute("UPDATE movements SET synced = 1 WHERE id = ?1", params![id])?;
        }
        tx.commit()
    }

    pub fn clear_business_movements(&self, business_id: &str) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute(
            "DELETE FROM movements WHERE business_id = ?1",
            params![business_id],
        )?;
        Ok(())
    }

    pub fn seed_opening_stock_for_business(
        &self,
        business_id: &str,
        include_today_samples: bool,
    ) -> rusqlite::Result<()> {
        let (_, start_ts, _) = day_bounds_local(None);
        let opening_ts = start_ts - 3600.0;

        let mut seeds = vec![
            ("prod_arroz_casanare", "Arroz Casanareño", "IN", 20.0, "bultos", opening_ts),
            ("prod_aceite_vegetal", "Aceite Vegetal 900ml", "IN", 10.0, "cajas", opening_ts),
            ("prod_sal_marina", "Sal Marina Refinada", "IN", 8.0, "bultos", opening_ts),
            ("prod_panela_criolla", "Panela Criolla", "IN", 15.0, "pacas", opening_ts),
            ("prod_papa_pastusa", "Papa Pastusa / Criolla", "IN", 12.0, "arrobas", opening_ts),
            ("prod_abono_triple15", "Abono Triple 15", "IN", 15.0, "bultos", opening_ts),
            ("prod_cemento_gris", "Cemento Gris 50kg", "IN", 30.0, "bultos", opening_ts),
            ("prod_harina_pan", "Harina de Maíz Precocida", "IN", 12.0, "pacas", opening_ts),
        ];

        if include_today_samples {
            let now = now_unix_secs();
            seeds.push((
                "prod_arroz_casanare",
                "Arroz Casanareño",
                "OUT",
                5.0,
                "bultos",
                (start_ts + 60.0).max(now - 1800.0),
            ));
            seeds.push((
                "prod_papa_pastusa",
                "Papa Pastusa / Criolla",
                "OUT",
                4.0,
                "arrobas",
                (start_ts + 120.0).max(now - 900.0),
            ));
        }

        for (pid, name, mtype, qty, unit, ts) in seeds {
            let mov = Movement::new(
                business_id.to_string(),
                pid.to_string(),
                name.to_string(),
                mtype.to_string(),
                qty,
                unit.to_string(),
                Some(ts),
                Some("seed_demo".to_string()),
                true,
            );
            self.record_movement(&mov)?;
        }
        Ok(())
    }

    pub fn seed_demo_data(&self, force: bool) -> rusqlite::Result<()> {
        self.seed_collective_baseline(force)?;
        if !force && !self.get_all_movements(Some("tienda_demo"))?.is_empty() {
            return Ok(());
        }
        if force {
            self.clear_business_movements("tienda_demo")?;
        }
        self.seed_opening_stock_for_business("tienda_demo", true)
    }

    // --- PRODUCTOS PERSONALIZADOS POR TIENDA ---

    pub fn upsert_custom_product(
        &self,
        business_id: &str,
        prod: &CatalogProduct,
    ) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        let syn_json = serde_json::to_string(&prod.synonyms).unwrap_or_else(|_| "[]".to_string());
        conn.execute(
            "INSERT OR REPLACE INTO custom_products
            (id, business_id, name, category, default_unit, min_threshold, retail_price_cop, wholesale_price_cop, synonyms_json, created_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
            params![
                prod.id,
                business_id,
                prod.name,
                prod.category,
                prod.default_unit,
                prod.min_threshold,
                prod.retail_price_cop,
                prod.wholesale_price_cop,
                syn_json,
                now_unix_secs()
            ],
        )?;
        Ok(())
    }

    pub fn get_custom_products(&self, business_id: &str) -> rusqlite::Result<Vec<CatalogProduct>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT id, name, category, default_unit, min_threshold, retail_price_cop, wholesale_price_cop, synonyms_json
             FROM custom_products WHERE business_id = ?1 ORDER BY created_at ASC",
        )?;
        let rows = stmt.query_map(params![business_id], |r| {
            let syn_raw: String = r.get(7)?;
            let synonyms: Vec<String> = serde_json::from_str(&syn_raw).unwrap_or_default();
            Ok(CatalogProduct {
                id: r.get(0)?,
                name: r.get(1)?,
                category: r.get(2)?,
                default_unit: r.get(3)?,
                min_threshold: r.get(4)?,
                retail_price_cop: r.get(5)?,
                wholesale_price_cop: r.get(6)?,
                synonyms,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    pub fn merged_catalog_for_business(
        &self,
        base_catalog: &[CatalogProduct],
        business_id: &str,
    ) -> rusqlite::Result<Vec<CatalogProduct>> {
        let mut merged = base_catalog.to_vec();
        let custom = self.get_custom_products(business_id)?;
        for cp in custom {
            if let Some(pos) = merged.iter().position(|p| p.id == cp.id) {
                merged[pos] = cp;
            } else {
                merged.push(cp);
            }
        }
        Ok(merged)
    }

    // --- CENTRAL DE COMPRAS COLECTIVAS PERSISTENTE ---

    pub fn seed_collective_baseline(&self, force: bool) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        if force {
            conn.execute("DELETE FROM collective_contributions", [])?;
        }
        let count: i64 = conn.query_row(
            "SELECT COUNT(*) FROM collective_contributions",
            [],
            |r| r.get(0),
        )?;
        if count > 0 {
            return Ok(());
        }
        let now = now_unix_secs();
        let defaults = [
            ("col_demo_1", "Comuna 2, Yopal", "tienda_demo", "Tienda La Esperanza", 15.0),
            ("col_demo_2", "Comuna 2, Yopal", "t2", "Agroinsumos Doña Martha", 25.0),
            ("col_demo_3", "Comuna 2, Yopal", "t3", "Minimarket El Llano", 20.0),
            ("col_demo_4", "Comuna 2, Yopal", "t4", "Comercializadora El Triunfo", 10.0),
        ];
        for (id, zone, bid, bname, qty) in defaults {
            conn.execute(
                "INSERT INTO collective_contributions
                (id, zone, business_id, business_name, product_id, product_name, quantity, unit, retail_price_cop, wholesale_price_cop, created_at)
                VALUES (?1, ?2, ?3, ?4, 'prod_arroz_casanare', 'Arroz Casanareño', ?5, 'bultos', 185000.0, 155000.0, ?6)",
                params![id, zone, bid, bname, qty, now],
            )?;
        }
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    pub fn add_collective_contribution(
        &self,
        zone: &str,
        business_id: &str,
        business_name: &str,
        product_id: &str,
        product_name: &str,
        quantity: f64,
        unit: &str,
        retail_price_cop: f64,
        wholesale_price_cop: f64,
    ) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        let existing: Option<(String, f64)> = conn
            .query_row(
                "SELECT id, quantity FROM collective_contributions WHERE business_id = ?1 AND product_id = ?2",
                params![business_id, product_id],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()?;

        if let Some((existing_id, current_qty)) = existing {
            conn.execute(
                "UPDATE collective_contributions SET quantity = ?1, business_name = ?2, zone = ?3 WHERE id = ?4",
                params![current_qty + quantity, business_name, zone, existing_id],
            )?;
        } else {
            let new_id = format!("col_{}", uuid::Uuid::new_v4());
            conn.execute(
                "INSERT INTO collective_contributions
                (id, zone, business_id, business_name, product_id, product_name, quantity, unit, retail_price_cop, wholesale_price_cop, created_at)
                VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
                params![
                    new_id,
                    zone,
                    business_id,
                    business_name,
                    product_id,
                    product_name,
                    quantity,
                    unit,
                    retail_price_cop,
                    wholesale_price_cop,
                    now_unix_secs()
                ],
            )?;
        }
        Ok(())
    }

    pub fn get_collective_contributions(&self) -> rusqlite::Result<Vec<CollectiveOrderInput>> {
        let conn = self.conn.lock().unwrap();
        let mut stmt = conn.prepare(
            "SELECT business_id, business_name, product_id, product_name, quantity, unit, retail_price_cop, wholesale_price_cop
             FROM collective_contributions ORDER BY created_at ASC",
        )?;
        let rows = stmt.query_map([], |r| {
            Ok(CollectiveOrderInput {
                business_id: r.get(0)?,
                business_name: r.get(1)?,
                product_id: r.get(2)?,
                product_name: r.get(3)?,
                quantity: r.get(4)?,
                unit: r.get(5)?,
                retail_price_cop: r.get(6)?,
                wholesale_price_cop: r.get(7)?,
            })
        })?;
        let mut out = Vec::new();
        for row in rows {
            out.push(row?);
        }
        Ok(out)
    }

    fn row_to_movement(r: &rusqlite::Row<'_>) -> rusqlite::Result<Movement> {
        let synced_int: i64 = r.get(9)?;
        Ok(Movement {
            id: r.get(0)?,
            business_id: r.get(1)?,
            product_id: r.get(2)?,
            product_name: r.get(3)?,
            movement_type: r.get(4)?,
            quantity: r.get(5)?,
            unit: r.get(6)?,
            timestamp: r.get(7)?,
            device_id: r.get(8)?,
            synced: synced_int != 0,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::nlp::RegionalNlpParser;

    #[test]
    fn test_immutable_stock_computation() {
        let ledger = LocalLedger::open(":memory:").unwrap();
        let catalog = RegionalNlpParser::from_embedded().catalog.products;

        ledger
            .record_movement(&Movement::new(
                "tienda_1".into(),
                "prod_arroz_casanare".into(),
                "Arroz Casanareño".into(),
                "IN".into(),
                20.0,
                "bultos".into(),
                None,
                None,
                true,
            ))
            .unwrap();
        ledger
            .record_movement(&Movement::new(
                "tienda_1".into(),
                "prod_arroz_casanare".into(),
                "Arroz Casanareño".into(),
                "OUT".into(),
                12.0,
                "bultos".into(),
                None,
                None,
                false,
            ))
            .unwrap();

        let stock = ledger.compute_stock(&catalog, "tienda_1").unwrap();
        let arroz = stock
            .iter()
            .find(|s| s.product_id == "prod_arroz_casanare")
            .unwrap();
        assert_eq!(arroz.current_stock, 8.0);
        assert!(arroz.needs_reorder);
    }

    #[test]
    fn test_daily_stock_window_00_to_2359() {
        let ledger = LocalLedger::open(":memory:").unwrap();
        let catalog = RegionalNlpParser::from_embedded().catalog.products;
        let (today, start_ts, _) = day_bounds_local(None);

        // Movimiento de ayer (saldo inicial 00:00)
        ledger
            .record_movement(&Movement::new(
                "tienda_daily".into(),
                "prod_arroz_casanare".into(),
                "Arroz Casanareño".into(),
                "IN".into(),
                25.0,
                "bultos".into(),
                Some(start_ts - 7200.0),
                None,
                true,
            ))
            .unwrap();

        // Movimiento de hoy: entrada +5 y salida -3
        ledger
            .record_movement(&Movement::new(
                "tienda_daily".into(),
                "prod_arroz_casanare".into(),
                "Arroz Casanareño".into(),
                "IN".into(),
                5.0,
                "bultos".into(),
                Some(start_ts + 3600.0),
                None,
                true,
            ))
            .unwrap();
        ledger
            .record_movement(&Movement::new(
                "tienda_daily".into(),
                "prod_arroz_casanare".into(),
                "Arroz Casanareño".into(),
                "OUT".into(),
                3.0,
                "bultos".into(),
                Some(start_ts + 7200.0),
                None,
                true,
            ))
            .unwrap();

        let daily = ledger
            .compute_daily_stock(&catalog, "tienda_daily", Some(today))
            .unwrap();
        let arroz = daily
            .items
            .iter()
            .find(|i| i.product_id == "prod_arroz_casanare")
            .unwrap();

        assert_eq!(arroz.opening_stock, 25.0);
        assert_eq!(arroz.today_in, 5.0);
        assert_eq!(arroz.today_out, 3.0);
        assert_eq!(arroz.daily_net, 2.0);
        assert_eq!(arroz.current_stock, 27.0);
        assert!(arroz.has_activity_today);
        assert_eq!(daily.summary.movements_count_today, 2);
    }
}
