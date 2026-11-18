use std::time::Duration;
use tokio::time::sleep;

use crate::config::SyncConfig;
use crate::local_store::LocalSqliteStore;
use crate::models::{SyncError, SyncReport};
use crate::remote_pg::PostgresRemoteClient;

/// Orquestador de sincronización con reintentos exponenciales (Cap. 4.3 del Anteproyecto).
pub struct SyncEngine {
    config: SyncConfig,
}

impl SyncEngine {
    pub fn new(config: SyncConfig) -> Self {
        Self { config }
    }

    /// Calcula el tiempo de espera exponencial (800ms, 1600ms, 3200ms...) con tope seguro.
    pub fn backoff_duration(&self, attempt: u32) -> Duration {
        let factor = 1u64.checked_shl(attempt.min(6)).unwrap_or(64);
        Duration::from_millis(self.config.initial_backoff_ms.saturating_mul(factor))
    }

    /// Ejecuta un ciclo completo: lee SQLite -> envía lote idempotente a PostgreSQL -> marca `synced = 1`.
    pub async fn run_sync_once(&self) -> Result<SyncReport, SyncError> {
        let mut local = LocalSqliteStore::open(&self.config.sqlite_path)?;
        let pending = local.fetch_pending(self.config.batch_size)?;

        if pending.is_empty() {
            return Ok(SyncReport {
                pending_found: 0,
                synced_count: 0,
                skipped_duplicates: 0,
                remaining_pending: 0,
                attempts: 0,
            });
        }

        let mut last_err: Option<SyncError> = None;

        for attempt in 1..=self.config.max_retries {
            match PostgresRemoteClient::connect(&self.config.postgres_url).await {
                Ok(mut remote) => match remote.push_movements_batch(&self.config.device_id, &pending).await {
                    Ok(batch_res) => {
                        local.mark_synced(&batch_res.confirmed_ids)?;
                        let remaining = local.count_pending()?;
                        return Ok(SyncReport {
                            pending_found: pending.len(),
                            synced_count: batch_res.inserted_new,
                            skipped_duplicates: batch_res.skipped_duplicates,
                            remaining_pending: remaining,
                            attempts: attempt,
                        });
                    }
                    Err(SyncError::DeviceRevoked) => return Err(SyncError::DeviceRevoked),
                    Err(e) => last_err = Some(e),
                },
                Err(e) => last_err = Some(e),
            }

            if attempt < self.config.max_retries {
                sleep(self.backoff_duration(attempt - 1)).await;
            }
        }

        eprintln!(
            "[origo_sync_core] Sincronización pospuesta tras {} intentos: {:?}",
            self.config.max_retries, last_err
        );
        Err(SyncError::MaxRetriesExceeded(self.config.max_retries))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_exponential_backoff_growth() {
        let cfg = SyncConfig::from_env();
        let engine = SyncEngine::new(cfg);
        assert_eq!(engine.backoff_duration(0), Duration::from_millis(800));
        assert_eq!(engine.backoff_duration(1), Duration::from_millis(1600));
        assert_eq!(engine.backoff_duration(2), Duration::from_millis(3200));
    }
}
