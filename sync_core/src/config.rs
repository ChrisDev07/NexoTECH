use std::env;

/// Configuración del núcleo de sincronización Origo (SQLite local <-> PostgreSQL).
#[derive(Debug, Clone)]
pub struct SyncConfig {
    pub sqlite_path: String,
    pub postgres_url: String,
    pub device_id: String,
    pub batch_size: usize,
    pub max_retries: u32,
    pub initial_backoff_ms: u64,
}

impl SyncConfig {
    /// Carga configuración desde variables de entorno con valores seguros por defecto.
    pub fn from_env() -> Self {
        Self {
            sqlite_path: env::var("ORIGO_SQLITE_PATH")
                .unwrap_or_else(|_| "../backend/origo_data.db".to_string()),
            postgres_url: env::var("ORIGO_PG_URL")
                .unwrap_or_else(|_| "postgres://postgres:postgres@localhost:5432/origo".to_string()),
            device_id: env::var("ORIGO_DEVICE_ID")
                .unwrap_or_else(|_| "origo_device_local".to_string()),
            batch_size: env::var("ORIGO_SYNC_BATCH_SIZE")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(50),
            max_retries: env::var("ORIGO_SYNC_MAX_RETRIES")
                .ok()
                .and_then(|v| v.parse().ok())
                .unwrap_or(4),
            initial_backoff_ms: 800,
        }
    }
}
