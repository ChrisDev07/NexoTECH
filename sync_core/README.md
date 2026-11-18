# 🦀 Origo Sync Core (`sync_core/`)

Núcleo de sincronización **Offline-First** escrito en **Rust**, encargado de replicar los movimientos inmutables del Libro Mayor desde la base **SQLite local** del comercio hacia **PostgreSQL central**.

## Características Clave
* **Idempotencia garantizada:** Inserción transaccional en PostgreSQL con `ON CONFLICT (id) DO NOTHING` usando UUID v4 generados en el dispositivo.
* **Resiliencia ante conectividad intermitente:** Reintentos automáticos con *backoff exponencial* para redes rurales de Casanare.
* **Revocación remota de dispositivos:** Verifica `device_sessions.revoked` antes de aceptar lotes.
* **Doble modo de despliegue:**
  1. **Biblioteca nativa (`cdylib`/`staticlib`)** integrable en Flutter vía FFI (`flutter_rust_bridge`).
  2. **Worker CLI (`origo-sync`)** para sincronización en segundo plano desde un equipo local.

## Ejecución Rápida (cuando Rust y PostgreSQL estén instalados)
```bash
# 1. Crear el esquema central en PostgreSQL
psql "$ORIGO_PG_URL" -f ../backend/schema_postgres.sql

# 2. Compilar y ejecutar pruebas unitarias del núcleo Rust
cd sync_core
cargo test

# 3. Ejecutar un ciclo de sincronización SQLite -> PostgreSQL
ORIGO_SQLITE_PATH=../backend/origo_data.db \
ORIGO_PG_URL="postgres://origo:clave@localhost:5432/origo_casanare" \
ORIGO_DEVICE_ID="origo_android_01" \
cargo run --bin origo-sync
```
