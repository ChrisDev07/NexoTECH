use chrono::{DateTime, Utc};
use rusqlite::{params, Connection};
use uuid::Uuid;

use crate::models::{LocalMovement, SyncError};

/// Adaptador de lectura y marcado atómico sobre la base SQLite local de Origo.
pub struct LocalSqliteStore {
    conn: Connection,
}

impl LocalSqliteStore {
    pub fn open(path: &str) -> Result<Self, SyncError> {
        let conn = Connection::open(path)?;
        Ok(Self { conn })
    }

    /// Obtiene hasta `limit` movimientos pendientes (`synced = 0`) en orden cronológico.
    pub fn fetch_pending(&self, limit: usize) -> Result<Vec<LocalMovement>, SyncError> {
        let mut stmt = self.conn.prepare(
            "SELECT id, business_id, product_id, product_name, type, quantity, unit, timestamp, device_id
             FROM movements
             WHERE synced = 0
             ORDER BY timestamp ASC
             LIMIT ?1",
        )?;

        let rows = stmt.query_map(params![limit as i64], |row| {
            let id_str: String = row.get(0)?;
            let business_id: String = row.get(1)?;
            let product_id: String = row.get(2)?;
            let product_name: String = row.get(3)?;
            let movement_type: String = row.get(4)?;
            let quantity: f64 = row.get(5)?;
            let unit: String = row.get(6)?;
            let raw_ts: f64 = row.get(7)?;
            let device_id: String = row.get(8)?;
            Ok((
                id_str,
                business_id,
                product_id,
                product_name,
                movement_type,
                quantity,
                unit,
                raw_ts,
                device_id,
            ))
        })?;

        let mut pending = Vec::new();
        for item in rows {
            let (id_str, business_id, product_id, product_name, movement_type, quantity, unit, raw_ts, device_id) =
                item?;
            let id = Uuid::parse_str(&id_str)?;
            // Soportar timestamps en segundos (Python) o milisegundos (Dart/Flutter)
            let secs = if raw_ts > 1e11 {
                (raw_ts / 1000.0) as i64
            } else {
                raw_ts as i64
            };
            let occurred_at = DateTime::<Utc>::from_timestamp(secs, 0).unwrap_or_else(Utc::now);

            pending.push(LocalMovement {
                id,
                business_id,
                product_id,
                product_name,
                movement_type,
                quantity,
                unit,
                occurred_at,
                device_id,
                synced: false,
            });
        }
        Ok(pending)
    }

    /// Marca como sincronizados (`synced = 1`) los UUID confirmados por PostgreSQL.
    pub fn mark_synced(&mut self, synced_ids: &[Uuid]) -> Result<usize, SyncError> {
        if synced_ids.is_empty() {
            return Ok(0);
        }
        let tx = self.conn.transaction()?;
        let mut updated = 0usize;
        {
            let mut stmt = tx.prepare("UPDATE movements SET synced = 1 WHERE id = ?1")?;
            for id in synced_ids {
                updated += stmt.execute(params![id.to_string()])?;
            }
        }
        tx.commit()?;
        Ok(updated)
    }

    pub fn count_pending(&self) -> Result<usize, SyncError> {
        let count: i64 = self
            .conn
            .query_row("SELECT COUNT(*) FROM movements WHERE synced = 0", [], |r| r.get(0))?;
        Ok(count as usize)
    }
}
