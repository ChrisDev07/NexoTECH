use origo_sync_core::config::SyncConfig;
use origo_sync_core::sync_engine::SyncEngine;

#[tokio::main]
async fn main() {
    let config = SyncConfig::from_env();
    println!("🦀 Origo Sync Core iniciado");
    println!("   • SQLite local: {}", config.sqlite_path);
    println!("   • Dispositivo:  {}", config.device_id);

    let engine = SyncEngine::new(config);
    match engine.run_sync_once().await {
        Ok(report) => {
            println!(
                "✔ Sincronización completada: {} nuevos, {} duplicados omitidos, {} pendientes (intentos: {})",
                report.synced_count,
                report.skipped_duplicates,
                report.remaining_pending,
                report.attempts
            );
        }
        Err(err) => {
            eprintln!("⚠️ No se pudo sincronizar ahora: {err}");
            std::process::exit(1);
        }
    }
}
