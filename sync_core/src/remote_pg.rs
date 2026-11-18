use tokio_postgres::{Client, NoTls};
use uuid::Uuid;

use crate::models::{LocalMovement, SyncError};

/// Resultado de la inserción idempotente por lote en PostgreSQL.
pub struct BatchPushResult {
    pub confirmed_ids: Vec<Uuid>,
    pub inserted_new: usize,
    pub skipped_duplicates: usize,
}

/// Cliente asíncrono de sincronización contra PostgreSQL central.
pub struct PostgresRemoteClient {
    client: Client,
}

impl PostgresRemoteClient {
    /// Conecta a PostgreSQL (en producción usar TLS 1.2+ con `tokio-postgres-rustls`).
    pub async fn connect(postgres_url: &str) -> Result<Self, SyncError> {
        let (client, connection) = tokio_postgres::connect(postgres_url, NoTls).await?;
        tokio::spawn(async move {
            if let Err(e) = connection.await {
                eprintln!("[origo_sync_core] Conexión PostgreSQL cerrada: {e}");
            }
        });
        Ok(Self { client })
    }

    /// Verifica en `device_sessions` que el dispositivo no haya sido revocado por pérdida o robo.
    pub async fn ensure_device_active(&self, device_id: &str) -> Result<(), SyncError> {
        let row = self
            .client
            .query_opt(
                "SELECT revoked FROM device_sessions WHERE device_id = $1",
                &[&device_id],
            )
            .await?;

        if let Some(r) = row {
            let revoked: bool = r.get(0);
            if revoked {
                return Err(SyncError::DeviceRevoked);
            }
        }
        Ok(())
    }

    /// Inserta un lote de movimientos de forma atómica e idempotente (`ON CONFLICT (id) DO NOTHING`).
    pub async fn push_movements_batch(
        &mut self,
        device_id: &str,
        movements: &[LocalMovement],
    ) -> Result<BatchPushResult, SyncError> {
        self.ensure_device_active(device_id).await?;

        let tx = self.client.transaction().await?;
        let stmt = tx
            .prepare(
                "INSERT INTO inventory_movements
                 (id, business_id, product_id, product_name, movement_type, quantity, unit, device_id, occurred_at)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
                 ON CONFLICT (id) DO NOTHING",
            )
            .await?;

        let mut confirmed_ids = Vec::with_capacity(movements.len());
        let mut inserted_new = 0usize;
        let mut skipped_duplicates = 0usize;

        for m in movements {
            let rows_affected = tx
                .execute(
                    &stmt,
                    &[
                        &m.id,
                        &m.business_id,
                        &m.product_id,
                        &m.product_name,
                        &m.movement_type,
                        &m.quantity,
                        &m.unit,
                        &m.device_id,
                        &m.occurred_at,
                    ],
                )
                .await?;

            if rows_affected > 0 {
                inserted_new += 1;
            } else {
                skipped_duplicates += 1;
            }
            // Tanto los recién insertados como los duplicados previos están confirmados en PostgreSQL
            confirmed_ids.push(m.id);
        }

        // Registrar marca de tiempo de última sincronización del dispositivo
        let _ = tx
            .execute(
                "UPDATE device_sessions SET last_sync_at = NOW() WHERE device_id = $1",
                &[&device_id],
            )
            .await;

        tx.commit().await?;

        Ok(BatchPushResult {
            confirmed_ids,
            inserted_new,
            skipped_duplicates,
        })
    }
}
