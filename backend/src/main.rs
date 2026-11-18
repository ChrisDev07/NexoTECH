//! Punto de entrada del servidor HTTP de Origo en Rust (Tokio + Axum).

use origo_backend::routes::{build_router, AppState};
use std::env;
use std::net::SocketAddr;
use std::path::PathBuf;

fn resolve_static_dir() -> PathBuf {
    if let Ok(custom) = env::var("ORIGO_STATIC_DIR") {
        return PathBuf::from(custom);
    }
    let local = PathBuf::from("static");
    if local.is_dir() {
        return local;
    }
    let from_root = PathBuf::from("backend/static");
    if from_root.is_dir() {
        return from_root;
    }
    local
}

fn resolve_db_path() -> String {
    if let Ok(custom) = env::var("ORIGO_DB_PATH") {
        return custom;
    }
    if PathBuf::from("backend").is_dir() && !PathBuf::from("Cargo.toml").is_file() {
        return "backend/origo_data.db".to_string();
    }
    "origo_data.db".to_string()
}

#[tokio::main]
async fn main() {
    let port: u16 = env::args()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .or_else(|| env::var("PORT").ok().and_then(|s| s.parse().ok()))
        .unwrap_or(8000);

    let db_path = resolve_db_path();
    let static_dir = resolve_static_dir();

    let state = AppState::open(&db_path).expect("Error inicializando SQLite de Origo");
    let app = build_router(state, Some(static_dir.clone()));

    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("No se pudo abrir el puerto HTTP");

    println!("🦀 Servidor Origo (Rust + Axum) activo en http://0.0.0.0:{port}");
    println!("   📦 Base de datos SQLite : {db_path}");
    println!("   🌐 Archivos estáticos   : {}", static_dir.display());

    axum::serve(listener, app)
        .await
        .expect("Error ejecutando el servidor HTTP de Origo");
}
