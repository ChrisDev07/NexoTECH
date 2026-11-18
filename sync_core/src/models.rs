use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

/// Evento inmutable del Libro Mayor de Inventario (compatible con SQLite y PostgreSQL).
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct LocalMovement {
    pub id: Uuid,
    pub business_id: String,
    pub product_id: String,
    pub product_name: String,
    pub movement_type: String, // "IN" o "OUT"
    pub quantity: f64,
    pub unit: String,
    pub occurred_at: DateTime<Utc>,
    pub device_id: String,
    pub synced: bool,
}

/// Reporte estructurado de un ciclo de sincronización.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SyncReport {
    pub pending_found: usize,
    pub synced_count: usize,
    pub skipped_duplicates: usize,
    pub remaining_pending: usize,
    pub attempts: u32,
}

/// Errores tipados del núcleo de sincronización.
#[derive(Debug, Error)]
pub enum SyncError {
    #[error("Error accediendo a SQLite local: {0}")]
    Sqlite(#[from] rusqlite::Error),

    #[error("Error de conexión o consulta en PostgreSQL: {0}")]
    Postgres(#[from] tokio_postgres::Error),

    #[error("UUID inválido en registro local: {0}")]
    InvalidUuid(#[from] uuid::Error),

    #[error("Dispositivo revocado en el servidor central (requiere re-autenticación)")]
    DeviceRevoked,

    #[error("Sin conectividad tras {0} reintentos; los datos permanecen seguros en SQLite")]
    MaxRetriesExceeded(u32),
}
