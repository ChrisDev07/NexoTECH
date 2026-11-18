//! # Origo Sync Core
//!
//! Núcleo de sincronización Offline-First en Rust para Origo (CREATIC Casanare).
//! Conecta el Libro Mayor SQLite local del comerciante con PostgreSQL central
//! garantizando idempotencia por UUID v4, reintentos exponenciales y revocación de dispositivos.

pub mod config;
pub mod local_store;
pub mod models;
pub mod remote_pg;
pub mod sync_engine;

use config::SyncConfig;
use models::{SyncError, SyncReport};
use sync_engine::SyncEngine;

/// Punto de entrada de alto nivel reutilizable desde Flutter vía FFI (`flutter_rust_bridge`).
pub async fn sync_sqlite_to_postgres(
    sqlite_path: String,
    postgres_url: String,
    device_id: String,
) -> Result<SyncReport, SyncError> {
    let mut cfg = SyncConfig::from_env();
    cfg.sqlite_path = sqlite_path;
    cfg.postgres_url = postgres_url;
    cfg.device_id = device_id;

    let engine = SyncEngine::new(cfg);
    engine.run_sync_once().await
}
