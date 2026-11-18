//! Rutas HTTP REST y servidor de archivos estáticos de Origo en Rust (Axum).
//! Mantiene 100% compatibilidad con la app móvil Flutter y la interfaz web existente.

use crate::auth::{privacy_policy_ley_1581, sanitize_phone, AuthManager};
use crate::collective::CollectivePurchasingEngine;
use crate::ledger::LocalLedger;
use crate::models::{now_unix_secs, CatalogProduct, Movement, PublicUser};
use crate::nlp::RegionalNlpParser;
use crate::security::{
    self, log_security_event, mask_phone, validate_movement_quantity, RateLimiter,
};
use axum::extract::{DefaultBodyLimit, State};
use axum::http::{header, HeaderMap, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde::Deserialize;
use serde_json::{json, Value};
use std::path::PathBuf;
use std::sync::Arc;
use tower_http::cors::CorsLayer;
use tower_http::services::{ServeDir, ServeFile};

pub struct AppState {
    pub parser: RegionalNlpParser,
    pub ledger: LocalLedger,
    pub auth: AuthManager,
    pub collective: CollectivePurchasingEngine,
    pub auth_limiter: RateLimiter,
    pub nlp_limiter: RateLimiter,
}

impl AppState {
    pub fn open(db_path: &str) -> rusqlite::Result<Arc<Self>> {
        let parser = RegionalNlpParser::from_embedded();
        let ledger = LocalLedger::open(db_path)?;
        let auth = AuthManager::open(db_path)?;
        ledger.seed_demo_data(false)?;
        let collective = CollectivePurchasingEngine::new(120_000.0);
        let auth_limiter = RateLimiter::new(10, 60); // 10 intentos por minuto por cuenta
        let nlp_limiter = RateLimiter::new(60, 60);   // 60 peticiones por minuto
        Ok(Arc::new(Self {
            parser,
            ledger,
            auth,
            collective,
            auth_limiter,
            nlp_limiter,
        }))
    }
}

pub fn build_router(state: Arc<AppState>, static_dir: Option<PathBuf>) -> Router {
    let cors = CorsLayer::new()
        .allow_methods([
            axum::http::Method::GET,
            axum::http::Method::POST,
            axum::http::Method::OPTIONS,
        ])
        .allow_headers([
            axum::http::header::AUTHORIZATION,
            axum::http::header::CONTENT_TYPE,
            axum::http::header::ACCEPT,
            axum::http::header::ORIGIN,
        ])
        .allow_origin(tower_http::cors::Any);

    let mut router = Router::new()
        .route("/api/health", get(health_check))
        .route("/api/privacy", get(get_privacy))
        .route("/api/auth/me", get(auth_me))
        .route("/api/auth/register", post(auth_register))
        .route("/api/auth/login", post(auth_login))
        .route("/api/auth/logout", post(auth_logout))
        .route("/api/catalog", get(get_catalog))
        .route("/api/products", get(get_products).post(post_product))
        .route("/api/nlp/parse", post(nlp_parse))
        .route("/api/stock", get(get_stock))
        .route("/api/stock/daily", get(get_daily_stock))
        .route("/api/movements", get(get_movements).post(post_movements))
        .route("/api/sync/users", post(sync_users))
        .route("/api/sync/products", post(sync_products))
        .route("/api/sync/movements", post(sync_movements))
        .route("/api/sync", post(sync_local))
        .route("/api/collective", get(get_collective))
        .route("/api/collective/join", post(join_collective))
        .route("/api/collective/simulate", post(collective_simulate))
        .route("/api/reset", post(reset_demo))
        .with_state(state)
        .layer(axum::middleware::from_fn(security::security_headers_middleware))
        .layer(DefaultBodyLimit::max(2 * 1024 * 1024))
        .layer(cors);

    if let Some(dir) = static_dir {
        if dir.is_dir() {
            let index_path = dir.join("index.html");
            router = router
                .route_service("/", ServeFile::new(index_path.clone()))
                .route_service("/index.html", ServeFile::new(index_path))
                .nest_service("/css", ServeDir::new(dir.join("css")))
                .nest_service("/js", ServeDir::new(dir.join("js")));
        }
    }

    router
}

fn json_no_cache(status: StatusCode, body: Value) -> Response {
    let mut resp = (status, Json(body)).into_response();
    resp.headers_mut().insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("no-store, no-cache, must-revalidate, max-age=0"),
    );
    resp
}

fn extract_bearer(headers: &HeaderMap) -> Option<&str> {
    let auth = headers.get(header::AUTHORIZATION)?.to_str().ok()?;
    auth.strip_prefix("Bearer ").map(str::trim)
}

fn current_user(state: &AppState, headers: &HeaderMap) -> Option<PublicUser> {
    state.auth.get_session_user(extract_bearer(headers))
}

fn resolve_business_id(state: &AppState, headers: &HeaderMap) -> String {
    current_user(state, headers)
        .map(|u| u.id)
        .unwrap_or_else(|| "tienda_demo".to_string())
}

fn value_as_bool(v: Option<&Value>, default: bool) -> bool {
    match v {
        Some(Value::Bool(b)) => *b,
        Some(Value::Number(n)) => n.as_i64().unwrap_or(0) != 0,
        Some(Value::String(s)) => matches!(s.to_lowercase().as_str(), "true" | "1" | "yes"),
        _ => default,
    }
}

async fn health_check() -> Response {
    json_no_cache(
        StatusCode::OK,
        json!({
            "status": "ok",
            "engine": "rust-axum",
            "service": "origo-backend",
            "version": env!("CARGO_PKG_VERSION")
        }),
    )
}

async fn get_privacy() -> Response {
    json_no_cache(StatusCode::OK, json!(privacy_policy_ley_1581()))
}

async fn auth_me(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    match current_user(&state, &headers) {
        Some(user) => json_no_cache(StatusCode::OK, json!({ "user": user })),
        None => json_no_cache(
            StatusCode::UNAUTHORIZED,
            json!({ "error": "Sesión no iniciada" }),
        ),
    }
}

#[derive(Deserialize, Default)]
struct RegisterPayload {
    #[serde(default)]
    phone: String,
    #[serde(default)]
    pin: String,
    #[serde(default)]
    owner_name: String,
    #[serde(default)]
    business_name: String,
    #[serde(default)]
    document_id: String,
    #[serde(default)]
    address: String,
    #[serde(default)]
    zone: String,
    #[serde(default)]
    habeas_data_accepted: Value,
}

async fn auth_register(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<RegisterPayload>,
) -> Response {
    let clean_phone = sanitize_phone(&payload.phone);
    if let Err(wait) = state.auth_limiter.check_and_inc(&clean_phone) {
        log_security_event(
            "AUTH_REGISTER_RATE_LIMIT",
            &mask_phone(&clean_phone),
            "Exceso de intentos de registro",
            false,
        );
        return json_no_cache(
            StatusCode::TOO_MANY_REQUESTS,
            json!({
                "error": format!("Demasiadas solicitudes de registro. Por seguridad, espera {} segundos.", wait),
                "retry_after": wait
            }),
        );
    }

    let accepted = value_as_bool(Some(&payload.habeas_data_accepted), false);
    match state.auth.register_user(
        &payload.phone,
        &payload.pin,
        &payload.owner_name,
        &payload.business_name,
        if payload.document_id.trim().is_empty() { None } else { Some(&payload.document_id) },
        if payload.address.trim().is_empty() { None } else { Some(&payload.address) },
        &payload.zone,
        accepted,
    ) {
        Ok(res) => {
            log_security_event(
                "AUTH_REGISTER_SUCCESS",
                &mask_phone(&clean_phone),
                "Usuario registrado exitosamente",
                true,
            );
            json_no_cache(StatusCode::CREATED, json!(res))
        }
        Err(err) => {
            log_security_event(
                "AUTH_REGISTER_FAILED",
                &mask_phone(&clean_phone),
                &err,
                false,
            );
            json_no_cache(StatusCode::BAD_REQUEST, json!({ "error": err }))
        }
    }
}

#[derive(Deserialize, Default)]
struct LoginPayload {
    #[serde(default)]
    phone: String,
    #[serde(default)]
    pin: String,
}

async fn auth_login(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<LoginPayload>,
) -> Response {
    let clean_phone = sanitize_phone(&payload.phone);
    if let Err(wait) = state.auth_limiter.check_and_inc(&clean_phone) {
        log_security_event(
            "AUTH_LOGIN_RATE_LIMIT",
            &mask_phone(&clean_phone),
            "Exceso de intentos de login",
            false,
        );
        return json_no_cache(
            StatusCode::TOO_MANY_REQUESTS,
            json!({
                "error": format!("Demasiados intentos fallidos. Por seguridad, espera {} segundos.", wait),
                "retry_after": wait
            }),
        );
    }

    match state.auth.login(&payload.phone, &payload.pin) {
        Ok(res) => {
            state.auth_limiter.reset(&clean_phone);
            log_security_event(
                "AUTH_LOGIN_SUCCESS",
                &mask_phone(&clean_phone),
                "Sesión iniciada exitosamente",
                true,
            );
            json_no_cache(StatusCode::OK, json!(res))
        }
        Err(err) => {
            log_security_event(
                "AUTH_LOGIN_FAILED",
                &mask_phone(&clean_phone),
                "Credenciales incorrectas",
                false,
            );
            json_no_cache(StatusCode::UNAUTHORIZED, json!({ "error": err }))
        }
    }
}

async fn auth_logout(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    state.auth.logout(extract_bearer(&headers));
    json_no_cache(StatusCode::OK, json!({ "status": "ok" }))
}

async fn get_catalog(State(state): State<Arc<AppState>>) -> Response {
    json_no_cache(StatusCode::OK, json!(state.parser.catalog))
}

async fn get_products(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    let business_id = resolve_business_id(&state, &headers);
    match state.ledger.get_custom_products(&business_id) {
        Ok(custom) => json_no_cache(
            StatusCode::OK,
            json!({
                "business_id": business_id,
                "custom_products": custom
            }),
        ),
        Err(e) => json_no_cache(
            StatusCode::INTERNAL_SERVER_ERROR,
            json!({ "error": e.to_string() }),
        ),
    }
}

#[derive(Deserialize, Default)]
struct CreateProductPayload {
    #[serde(default)]
    id: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    category: String,
    #[serde(default)]
    default_unit: String,
    #[serde(default)]
    min_threshold: f64,
    #[serde(default)]
    retail_price_cop: f64,
    #[serde(default)]
    wholesale_price_cop: f64,
    #[serde(default)]
    synonyms: Vec<String>,
}

async fn post_product(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<CreateProductPayload>,
) -> Response {
    let business_id = resolve_business_id(&state, &headers);
    let clean_name = payload.name.trim();
    if clean_name.chars().count() < 2 {
        return json_no_cache(
            StatusCode::BAD_REQUEST,
            json!({ "error": "Escribe el nombre del producto (mínimo 2 caracteres)." }),
        );
    }

    let prod_id = if payload.id.trim().is_empty() {
        format!(
            "prod_custom_{}",
            &uuid::Uuid::new_v4().to_string()[..8]
        )
    } else {
        payload.id.trim().to_string()
    };

    let mut synonyms = payload.synonyms;
    if synonyms.is_empty() {
        synonyms.push(clean_name.to_lowercase());
    }

    let prod = CatalogProduct {
        id: prod_id,
        name: clean_name.to_string(),
        category: if payload.category.trim().is_empty() {
            "Mi Tienda".to_string()
        } else {
            payload.category.trim().to_string()
        },
        default_unit: if payload.default_unit.trim().is_empty() {
            "unidades".to_string()
        } else {
            payload.default_unit.trim().to_lowercase()
        },
        min_threshold: if payload.min_threshold > 0.0 {
            payload.min_threshold
        } else {
            5.0
        },
        retail_price_cop: payload.retail_price_cop,
        wholesale_price_cop: payload.wholesale_price_cop,
        synonyms,
    };

    if let Err(e) = state.ledger.upsert_custom_product(&business_id, &prod) {
        return json_no_cache(
            StatusCode::INTERNAL_SERVER_ERROR,
            json!({ "error": e.to_string() }),
        );
    }

    let merged = state
        .ledger
        .merged_catalog_for_business(&state.parser.catalog.products, &business_id)
        .unwrap_or_else(|_| state.parser.catalog.products.clone());

    match state
        .ledger
        .compute_daily_stock(&merged, &business_id, None)
    {
        Ok(daily_stock) => json_no_cache(
            StatusCode::CREATED,
            json!({
                "status": "ok",
                "product": prod,
                "daily_stock": daily_stock
            }),
        ),
        Err(e) => json_no_cache(
            StatusCode::INTERNAL_SERVER_ERROR,
            json!({ "error": e.to_string() }),
        ),
    }
}

async fn sync_products(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<Value>,
) -> Response {
    let fallback_bid = resolve_business_id(&state, &headers);
    let incoming = payload
        .get("products")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();

    let mut synced_ids = Vec::new();
    for p in incoming {
        let Some(id) = p.get("id").and_then(Value::as_str) else {
            continue;
        };
        let Some(name) = p.get("name").and_then(Value::as_str) else {
            continue;
        };
        let bid = p
            .get("business_id")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .unwrap_or(&fallback_bid);
        let synonyms: Vec<String> = match p.get("synonyms") {
            Some(Value::Array(arr)) => arr
                .iter()
                .filter_map(Value::as_str)
                .map(ToString::to_string)
                .collect(),
            Some(Value::String(s)) => s
                .split(',')
                .map(|x| x.trim().to_string())
                .filter(|x| !x.is_empty())
                .collect(),
            _ => vec![name.to_lowercase()],
        };
        let prod = CatalogProduct {
            id: id.to_string(),
            name: name.to_string(),
            category: p
                .get("category")
                .and_then(Value::as_str)
                .unwrap_or("Mi Tienda")
                .to_string(),
            default_unit: p
                .get("default_unit")
                .or_else(|| p.get("unit"))
                .and_then(Value::as_str)
                .unwrap_or("unidades")
                .to_string(),
            min_threshold: p
                .get("min_threshold")
                .and_then(Value::as_f64)
                .unwrap_or(5.0),
            retail_price_cop: p
                .get("retail_price_cop")
                .and_then(Value::as_f64)
                .unwrap_or(0.0),
            wholesale_price_cop: p
                .get("wholesale_price_cop")
                .and_then(Value::as_f64)
                .unwrap_or(0.0),
            synonyms,
        };
        if let Err(e) = state.ledger.upsert_custom_product(bid, &prod) {
            return json_no_cache(
                StatusCode::INTERNAL_SERVER_ERROR,
                json!({ "error": e.to_string() }),
            );
        }
        synced_ids.push(id.to_string());
    }

    let synced_count = synced_ids.len();
    json_no_cache(
        StatusCode::OK,
        json!({
            "status": "ok",
            "synced_ids": synced_ids,
            "synced_count": synced_count
        }),
    )
}

#[derive(Deserialize, Default)]
struct NlpPayload {
    #[serde(default)]
    phrase: String,
}

async fn nlp_parse(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<NlpPayload>,
) -> Response {
    let business_id = resolve_business_id(&state, &headers);
    if let Err(wait) = state.nlp_limiter.check_and_inc(&business_id) {
        return json_no_cache(
            StatusCode::TOO_MANY_REQUESTS,
            json!({
                "error": format!("Límite de procesamiento NLP alcanzado. Espera {} segundos.", wait),
                "retry_after": wait
            }),
        );
    }
    if payload.phrase.len() > 1000 {
        return json_no_cache(
            StatusCode::BAD_REQUEST,
            json!({ "error": "La frase excede la longitud máxima permitida (1000 caracteres)." }),
        );
    }
    let custom = state
        .ledger
        .get_custom_products(&business_id)
        .unwrap_or_default();
    let items = state
        .parser
        .parse_phrase_with_extra_products(&payload.phrase, &custom);
    json_no_cache(StatusCode::OK, json!(items))
}

async fn get_stock(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    let business_id = resolve_business_id(&state, &headers);
    let merged = state
        .ledger
        .merged_catalog_for_business(&state.parser.catalog.products, &business_id)
        .unwrap_or_else(|_| state.parser.catalog.products.clone());
    match state.ledger.compute_stock(&merged, &business_id) {
        Ok(stock) => json_no_cache(StatusCode::OK, json!(stock)),
        Err(e) => json_no_cache(
            StatusCode::INTERNAL_SERVER_ERROR,
            json!({ "error": e.to_string() }),
        ),
    }
}

async fn get_daily_stock(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    let business_id = resolve_business_id(&state, &headers);
    let merged = state
        .ledger
        .merged_catalog_for_business(&state.parser.catalog.products, &business_id)
        .unwrap_or_else(|_| state.parser.catalog.products.clone());
    match state
        .ledger
        .compute_daily_stock(&merged, &business_id, None)
    {
        Ok(daily) => json_no_cache(StatusCode::OK, json!(daily)),
        Err(e) => json_no_cache(
            StatusCode::INTERNAL_SERVER_ERROR,
            json!({ "error": e.to_string() }),
        ),
    }
}

async fn get_movements(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    let business_id = resolve_business_id(&state, &headers);
    match state.ledger.get_movements_for_api(&business_id) {
        Ok(moves) => json_no_cache(StatusCode::OK, json!(moves)),
        Err(e) => json_no_cache(
            StatusCode::INTERNAL_SERVER_ERROR,
            json!({ "error": e.to_string() }),
        ),
    }
}

#[derive(Deserialize)]
struct IncomingMovementItem {
    product_id: String,
    product_name: String,
    action: String,
    quantity: f64,
    unit: String,
}

#[derive(Deserialize, Default)]
struct PostMovementsPayload {
    #[serde(default)]
    items: Vec<IncomingMovementItem>,
    synced: Option<bool>,
}

async fn post_movements(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<PostMovementsPayload>,
) -> Response {
    let business_id = resolve_business_id(&state, &headers);
    let synced = payload.synced.unwrap_or(true);
    let merged = state
        .ledger
        .merged_catalog_for_business(&state.parser.catalog.products, &business_id)
        .unwrap_or_else(|_| state.parser.catalog.products.clone());

    // Validar existencias antes de registrar salidas (evita ventas imposibles / stock negativo)
    let current_stock_list = match state.ledger.compute_stock(&merged, &business_id) {
        Ok(list) => list,
        Err(e) => {
            return json_no_cache(
                StatusCode::INTERNAL_SERVER_ERROR,
                json!({ "error": e.to_string() }),
            );
        }
    };
    let mut available_map: std::collections::HashMap<String, f64> = current_stock_list
        .into_iter()
        .map(|s| (s.product_id, s.current_stock))
        .collect();

    // OWASP A03 / Mobile M4: Validación estricta de cantidades
    for it in &payload.items {
        if let Err(err) = validate_movement_quantity(it.quantity) {
            return json_no_cache(StatusCode::BAD_REQUEST, json!({ "error": err }));
        }
    }

    for it in &payload.items {
        let current_qty = available_map.get(&it.product_id).copied().unwrap_or(0.0);
        if it.action == "SALIDA" {
            if it.quantity > current_qty + 1e-6 {
                let msg = if current_qty <= 0.0 {
                    format!(
                        "No tienes existencias de {} en bodega (Stock: 0 {}). Registra primero una entrada.",
                        it.product_name, it.unit
                    )
                } else {
                    format!(
                        "Stock insuficiente para {}: solo tienes {} {} disponibles y estás intentando sacar {} {}.",
                        it.product_name, current_qty, it.unit, it.quantity, it.unit
                    )
                };
                return json_no_cache(StatusCode::BAD_REQUEST, json!({ "error": msg }));
            }
            available_map.insert(it.product_id.clone(), current_qty - it.quantity);
        } else {
            available_map.insert(it.product_id.clone(), current_qty + it.quantity);
        }
    }

    let mut recorded = Vec::new();

    for it in payload.items {
        let mov = Movement::new(
            business_id.clone(),
            it.product_id,
            it.product_name,
            if it.action == "SALIDA" {
                "OUT".to_string()
            } else {
                "IN".to_string()
            },
            it.quantity,
            it.unit,
            None,
            None,
            synced,
        );
        if let Err(e) = state.ledger.record_movement(&mov) {
            return json_no_cache(
                StatusCode::INTERNAL_SERVER_ERROR,
                json!({ "error": e.to_string() }),
            );
        }
        recorded.push(mov);
    }

    match state
        .ledger
        .compute_daily_stock(&merged, &business_id, None)
    {
        Ok(daily_stock) => json_no_cache(
            StatusCode::OK,
            json!({
                "status": "ok",
                "recorded": recorded,
                "daily_stock": daily_stock
            }),
        ),
        Err(e) => json_no_cache(
            StatusCode::INTERNAL_SERVER_ERROR,
            json!({ "error": e.to_string() }),
        ),
    }
}

async fn sync_users(
    State(state): State<Arc<AppState>>,
    Json(payload): Json<Value>,
) -> Response {
    let incoming = payload
        .get("users")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();

    let mut synced_ids = Vec::new();

    for u in incoming {
        let id = u.get("id").and_then(Value::as_str).unwrap_or("");
        let phone = u.get("phone").and_then(Value::as_str).unwrap_or("");
        if id.is_empty() || phone.is_empty() {
            continue;
        }
        let owner_name = u
            .get("owner_name")
            .and_then(Value::as_str)
            .unwrap_or("Comerciante");
        let business_name = u
            .get("business_name")
            .and_then(Value::as_str)
            .unwrap_or("Mi Tienda");
        let zone = u
            .get("zone")
            .and_then(Value::as_str)
            .unwrap_or("Yopal");
        let document_id = u.get("document_id").and_then(Value::as_str);
        let address = u.get("address").and_then(Value::as_str);
        let pin_salt = u.get("pin_salt").and_then(Value::as_str).unwrap_or("");
        let pin_hash = u.get("pin_hash").and_then(Value::as_str).unwrap_or("");
        let habeas = value_as_bool(u.get("habeas_data_accepted"), true);
        let created_at = u.get("created_at").and_then(Value::as_f64);

        if let Err(e) = state.auth.sync_offline_user(
            id,
            phone,
            owner_name,
            business_name,
            document_id,
            address,
            zone,
            pin_salt,
            pin_hash,
            habeas,
            created_at,
        ) {
            return json_no_cache(
                StatusCode::INTERNAL_SERVER_ERROR,
                json!({ "error": e.to_string() }),
            );
        }
        synced_ids.push(id.to_string());
    }

    let synced_count = synced_ids.len();
    json_no_cache(
        StatusCode::OK,
        json!({
            "status": "ok",
            "synced_ids": synced_ids,
            "synced_count": synced_count
        }),
    )
}

async fn sync_movements(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<Value>,
) -> Response {
    let fallback_business_id = resolve_business_id(&state, &headers);
    let incoming = payload
        .get("movements")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();

    let mut synced_ids = Vec::new();
    let mut last_business_id = fallback_business_id.clone();

    for m in incoming {
        let Some(id) = m.get("id").and_then(Value::as_str) else {
            continue;
        };
        let Some(product_id) = m.get("product_id").and_then(Value::as_str) else {
            continue;
        };
        let Some(mtype) = m.get("type").and_then(Value::as_str) else {
            continue;
        };
        let Some(quantity) = m.get("quantity").and_then(Value::as_f64) else {
            continue;
        };
        // OWASP A03 / Mobile M4: Descartar cantidades anómalas
        if validate_movement_quantity(quantity).is_err() {
            continue;
        }

        let raw_ts = m
            .get("timestamp")
            .and_then(Value::as_f64)
            .unwrap_or_else(now_unix_secs);
        let ts_sec = if raw_ts > 1e11 {
            raw_ts / 1000.0
        } else {
            raw_ts
        };

        let caller = current_user(&state, &headers);
        let bid = m
            .get("business_id")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .unwrap_or(&fallback_business_id)
            .to_string();

        // OWASP A01: Control de acceso estricto y prevención de IDOR
        if let Some(ref user) = caller {
            if bid != user.id {
                log_security_event(
                    "IDOR_PREVENTED",
                    &user.id,
                    &format!("Intento de sincronizar en tienda ajena {}", bid),
                    false,
                );
                return json_no_cache(
                    StatusCode::FORBIDDEN,
                    json!({ "error": "Acceso denegado: no tienes permisos para sincronizar movimientos en otra tienda." }),
                );
            }
        }
        last_business_id = bid.clone();

        let mov = Movement {
            id: id.to_string(),
            business_id: bid,
            product_id: product_id.to_string(),
            product_name: m
                .get("product_name")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string(),
            movement_type: mtype.to_string(),
            quantity,
            unit: m
                .get("unit")
                .and_then(Value::as_str)
                .unwrap_or("unidades")
                .to_string(),
            timestamp: ts_sec,
            device_id: m
                .get("device_id")
                .and_then(Value::as_str)
                .unwrap_or("android_mobile")
                .to_string(),
            synced: true,
        };

        if let Err(e) = state.ledger.record_movement(&mov) {
            return json_no_cache(
                StatusCode::INTERNAL_SERVER_ERROR,
                json!({ "error": e.to_string() }),
            );
        }
        synced_ids.push(mov.id);
    }

    let merged = state
        .ledger
        .merged_catalog_for_business(&state.parser.catalog.products, &last_business_id)
        .unwrap_or_else(|_| state.parser.catalog.products.clone());

    match state
        .ledger
        .compute_daily_stock(&merged, &last_business_id, None)
    {
        Ok(daily_stock) => {
            let synced_count = synced_ids.len();
            json_no_cache(
                StatusCode::OK,
                json!({
                    "status": "ok",
                    "synced_ids": synced_ids,
                    "synced_count": synced_count,
                    "daily_stock": daily_stock
                }),
            )
        }
        Err(e) => json_no_cache(
            StatusCode::INTERNAL_SERVER_ERROR,
            json!({ "error": e.to_string() }),
        ),
    }
}

async fn sync_local(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    let business_id = resolve_business_id(&state, &headers);
    let pending = match state.ledger.get_pending_sync_movements(&business_id) {
        Ok(p) => p,
        Err(e) => {
            return json_no_cache(
                StatusCode::INTERNAL_SERVER_ERROR,
                json!({ "error": e.to_string() }),
            );
        }
    };
    let ids: Vec<String> = pending.into_iter().map(|m| m.id).collect();
    if let Err(e) = state.ledger.mark_as_synced(&ids) {
        return json_no_cache(
            StatusCode::INTERNAL_SERVER_ERROR,
            json!({ "error": e.to_string() }),
        );
    }
    json_no_cache(
        StatusCode::OK,
        json!({ "status": "ok", "synced_count": ids.len() }),
    )
}

async fn get_collective(State(state): State<Arc<AppState>>) -> Response {
    match state.ledger.get_collective_contributions() {
        Ok(orders) => {
            let summary = state.collective.aggregate_orders(&orders);
            json_no_cache(StatusCode::OK, json!(summary))
        }
        Err(e) => json_no_cache(
            StatusCode::INTERNAL_SERVER_ERROR,
            json!({ "error": e.to_string() }),
        ),
    }
}

async fn collective_simulate(
    State(state): State<Arc<AppState>>,
    _headers: HeaderMap,
) -> Response {
    get_collective(State(state)).await
}

#[derive(Deserialize, Default)]
struct JoinCollectivePayload {
    #[serde(default)]
    business_id: String,
    #[serde(default)]
    business_name: String,
    #[serde(default)]
    zone: String,
    #[serde(default)]
    product_id: String,
    #[serde(default)]
    product_name: String,
    quantity: Option<f64>,
    #[serde(default)]
    unit: String,
    retail_price_cop: Option<f64>,
    wholesale_price_cop: Option<f64>,
}

async fn join_collective(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(payload): Json<JoinCollectivePayload>,
) -> Response {
    let user = current_user(&state, &headers);
    let bid = if !payload.business_id.trim().is_empty() {
        payload.business_id.trim().to_string()
    } else if let Some(u) = &user {
        u.id.clone()
    } else {
        "tienda_demo".to_string()
    };

    let bname = if !payload.business_name.trim().is_empty() {
        payload.business_name.trim().to_string()
    } else if let Some(u) = &user {
        u.business_name.clone()
    } else {
        "Tienda La Esperanza".to_string()
    };

    let zone = if !payload.zone.trim().is_empty() {
        payload.zone.trim().to_string()
    } else if let Some(u) = &user {
        u.zone.clone()
    } else {
        "Yopal".to_string()
    };

    let pid = if payload.product_id.trim().is_empty() {
        "prod_arroz_casanare".to_string()
    } else {
        payload.product_id.trim().to_string()
    };
    let pname = if payload.product_name.trim().is_empty() {
        let cat_prod = state.parser.catalog.products.iter().find(|p| p.id == pid);
        cat_prod
            .map(|p| p.name.clone())
            .unwrap_or_else(|| "Producto Casanareño".to_string())
    } else {
        payload.product_name.trim().to_string()
    };
    let unit = if payload.unit.trim().is_empty() {
        let cat_prod = state.parser.catalog.products.iter().find(|p| p.id == pid);
        cat_prod
            .map(|p| p.default_unit.clone())
            .unwrap_or_else(|| "bultos".to_string())
    } else {
        payload.unit.trim().to_string()
    };

    let cat_prod = state.parser.catalog.products.iter().find(|p| p.id == pid);
    let default_retail = cat_prod.map(|p| p.retail_price_cop).unwrap_or(185_000.0);
    let default_wholesale = cat_prod
        .map(|p| p.wholesale_price_cop)
        .unwrap_or(default_retail * 0.82);

    let retail = payload
        .retail_price_cop
        .filter(|v| *v > 0.0)
        .unwrap_or(default_retail);
    let wholesale = payload
        .wholesale_price_cop
        .filter(|v| *v > 0.0)
        .unwrap_or(default_wholesale);
    let qty = payload.quantity.unwrap_or(10.0).max(0.5);

    if let Err(e) = state.ledger.add_collective_contribution(
        &zone, &bid, &bname, &pid, &pname, qty, &unit, retail, wholesale,
    ) {
        return json_no_cache(
            StatusCode::INTERNAL_SERVER_ERROR,
            json!({ "error": e.to_string() }),
        );
    }

    get_collective(State(state)).await
}

async fn reset_demo(State(state): State<Arc<AppState>>) -> Response {
    match state.ledger.seed_demo_data(true) {
        Ok(()) => json_no_cache(
            StatusCode::OK,
            json!({ "status": "ok", "message": "Datos reiniciados" }),
        ),
        Err(e) => json_no_cache(
            StatusCode::INTERNAL_SERVER_ERROR,
            json!({ "error": e.to_string() }),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::auth::hash_pin_mobile_sha256;
    use axum::body::Body;
    use axum::http::Request;
    use http_body_util::BodyExt;
    use tower::ServiceExt;

    async fn call_json(
        app: &Router,
        method: &str,
        uri: &str,
        token: Option<&str>,
        payload: Option<Value>,
    ) -> (StatusCode, Value) {
        let mut builder = Request::builder().method(method).uri(uri);
        if let Some(tok) = token {
            builder = builder.header(header::AUTHORIZATION, format!("Bearer {tok}"));
        }
        let body = if let Some(val) = payload {
            builder = builder.header(header::CONTENT_TYPE, "application/json");
            Body::from(val.to_string())
        } else {
            Body::empty()
        };
        let req = builder.body(body).unwrap();
        let resp = app.clone().oneshot(req).await.unwrap();
        let status = resp.status();
        let bytes = resp.into_body().collect().await.unwrap().to_bytes();
        let json: Value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
        (status, json)
    }

    #[tokio::test]
    async fn test_e2e_offline_mobile_sync_and_store_isolation() {
        let state = AppState::open(":memory:").unwrap();
        let app = build_router(state, None);

        // 1. Health check
        let (st, health) = call_json(&app, "GET", "/api/health", None, None).await;
        assert_eq!(st, StatusCode::OK);
        assert_eq!(health["engine"], "rust-axum");

        // 2. Sincronizar tienda creada offline en Android (habeas como entero 1 desde SQLite)
        let salt = "abcdef0123456789abcdef0123456789";
        let mobile_hash = hash_pin_mobile_sha256("2468", salt);
        let (st, sync_u) = call_json(
            &app,
            "POST",
            "/api/sync/users",
            None,
            Some(json!({
                "users": [{
                    "id": "tienda_rust_1",
                    "phone": "3120001122",
                    "owner_name": "Carlos",
                    "business_name": "Tienda El Llano",
                    "zone": "Yopal",
                    "pin_salt": salt,
                    "pin_hash": mobile_hash,
                    "habeas_data_accepted": 1,
                    "created_at": 1760000000000.0
                }]
            })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
        assert_eq!(sync_u["synced_ids"][0], "tienda_rust_1");

        // 3. Sincronizar movimiento de esa tienda (timestamp en milisegundos)
        let (st, sync_m) = call_json(
            &app,
            "POST",
            "/api/sync/movements",
            None,
            Some(json!({
                "movements": [{
                    "id": "mov_rust_1",
                    "business_id": "tienda_rust_1",
                    "product_id": "prod_arroz_casanare",
                    "product_name": "Arroz Casanareño",
                    "type": "IN",
                    "quantity": 9.0,
                    "unit": "bultos",
                    "timestamp": 1760000005000.0
                }]
            })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
        assert_eq!(sync_m["synced_ids"][0], "mov_rust_1");

        // 4. Iniciar sesión en la web con la tienda sincronizada y validar aislamiento total
        let (st, login) = call_json(
            &app,
            "POST",
            "/api/auth/login",
            None,
            Some(json!({ "phone": "3120001122", "pin": "2468" })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
        let token = login["token"].as_str().unwrap();

        let (st, moves) = call_json(&app, "GET", "/api/movements", Some(token), None).await;
        assert_eq!(st, StatusCode::OK);
        let arr = moves.as_array().unwrap();
        assert_eq!(arr.len(), 1);
        assert_eq!(arr[0]["business_id"], "tienda_rust_1");
        assert_eq!(arr[0]["quantity"], 9.0);

        // 5. Verificar que Don Pedro sigue aislado con sus propios movimientos
        let (st, demo_login) = call_json(
            &app,
            "POST",
            "/api/auth/login",
            None,
            Some(json!({ "phone": "3101234567", "pin": "1234" })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
        let demo_tok = demo_login["token"].as_str().unwrap();
        let (st, demo_moves) = call_json(&app, "GET", "/api/movements", Some(demo_tok), None).await;
        assert_eq!(st, StatusCode::OK);
        assert!(demo_moves
            .as_array()
            .unwrap()
            .iter()
            .all(|m| m["business_id"] == "tienda_demo"));
    }

    #[tokio::test]
    async fn test_custom_products_nlp_and_persistent_collective() {
        let state = AppState::open(":memory:").unwrap();
        let app = build_router(state, None);

        // Registrar tienda nueva
        let (st, reg) = call_json(
            &app,
            "POST",
            "/api/auth/register",
            None,
            Some(json!({
                "phone": "3185554433",
                "pin": "5555",
                "owner_name": "Doña Elena",
                "business_name": "Tienda El Moriche",
                "zone": "Yopal",
                "habeas_data_accepted": true
            })),
        )
        .await;
        assert_eq!(st, StatusCode::CREATED);
        let tok = reg["token"].as_str().unwrap();

        // Crear producto personalizado "+ Nuevo producto"
        let (st, created) = call_json(
            &app,
            "POST",
            "/api/products",
            Some(tok),
            Some(json!({
                "name": "Café Tostado Yopal",
                "category": "Víveres",
                "default_unit": "libras",
                "min_threshold": 5,
                "synonyms": ["cafe", "cafecito", "cafe tostado"]
            })),
        )
        .await;
        assert_eq!(st, StatusCode::CREATED);
        assert_eq!(created["product"]["name"], "Café Tostado Yopal");

        // Verificar que el NLP reconoce al instante el producto propio
        let (st, parsed) = call_json(
            &app,
            "POST",
            "/api/nlp/parse",
            Some(tok),
            Some(json!({ "phrase": "vendí cuatro libras de cafe tostado" })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
        assert_eq!(parsed.as_array().unwrap().len(), 1);
        assert_eq!(parsed[0]["action"], "SALIDA");
        assert_eq!(parsed[0]["quantity"], 4.0);
        assert_eq!(parsed[0]["product_name"], "Café Tostado Yopal");

        // Unirse de verdad al pedido colectivo persistente
        let (st, col) = call_json(
            &app,
            "POST",
            "/api/collective/join",
            Some(tok),
            Some(json!({ "quantity": 10.0 })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
        assert_eq!(col["participating_stores_count"], 8);
        assert_eq!(col["products"][0]["stores_count"], 5);
        assert_eq!(col["products"][0]["total_quantity"], 80.0);
    }

    #[tokio::test]
    async fn test_prevent_sale_exceeding_stock() {
        let state = AppState::open(":memory:").unwrap();
        let app = build_router(state, None);

        // Registrar tienda limpia (stock = 0)
        let (st, reg) = call_json(
            &app,
            "POST",
            "/api/auth/register",
            None,
            Some(json!({
                "phone": "3194443322",
                "pin": "7777",
                "owner_name": "Don Luis",
                "business_name": "Tienda San Luis",
                "zone": "Yopal",
                "habeas_data_accepted": true
            })),
        )
        .await;
        assert_eq!(st, StatusCode::CREATED);
        let tok = reg["token"].as_str().unwrap();

        // 1. Intentar vender 15 con stock 0 -> 400 Bad Request
        let (st, err_zero) = call_json(
            &app,
            "POST",
            "/api/movements",
            Some(tok),
            Some(json!({
                "items": [{
                    "product_id": "prod_arroz_casanare",
                    "product_name": "Arroz Casanareño",
                    "action": "SALIDA",
                    "quantity": 15.0,
                    "unit": "bultos"
                }]
            })),
        )
        .await;
        assert_eq!(st, StatusCode::BAD_REQUEST);
        assert!(err_zero["error"].as_str().unwrap().contains("existencias"));

        // 2. Registrar entrada de 5 bultos -> OK
        let (st, _) = call_json(
            &app,
            "POST",
            "/api/movements",
            Some(tok),
            Some(json!({
                "items": [{
                    "product_id": "prod_arroz_casanare",
                    "product_name": "Arroz Casanareño",
                    "action": "ENTRADA",
                    "quantity": 5.0,
                    "unit": "bultos"
                }]
            })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);

        // 3. Intentar vender 15 teniendo 5 -> 400 Bad Request
        let (st, err_short) = call_json(
            &app,
            "POST",
            "/api/movements",
            Some(tok),
            Some(json!({
                "items": [{
                    "product_id": "prod_arroz_casanare",
                    "product_name": "Arroz Casanareño",
                    "action": "SALIDA",
                    "quantity": 15.0,
                    "unit": "bultos"
                }]
            })),
        )
        .await;
        assert_eq!(st, StatusCode::BAD_REQUEST);
        assert!(err_short["error"].as_str().unwrap().contains("insuficiente"));

        // 4. Vender 5 (exacto) -> OK
        let (st, _) = call_json(
            &app,
            "POST",
            "/api/movements",
            Some(tok),
            Some(json!({
                "items": [{
                    "product_id": "prod_arroz_casanare",
                    "product_name": "Arroz Casanareño",
                    "action": "SALIDA",
                    "quantity": 5.0,
                    "unit": "bultos"
                }]
            })),
        )
        .await;
        assert_eq!(st, StatusCode::OK);
    }

    #[tokio::test]
    async fn test_owasp_security_headers_and_controls() {
        let state = AppState::open(":memory:").unwrap();
        let app = build_router(state, None);

        let req = Request::builder()
            .method("GET")
            .uri("/api/health")
            .body(Body::empty())
            .unwrap();
        let resp = app.clone().oneshot(req).await.unwrap();

        assert_eq!(resp.status(), StatusCode::OK);
        let headers = resp.headers();
        assert_eq!(headers.get("x-frame-options").unwrap(), "DENY");
        assert_eq!(headers.get("x-content-type-options").unwrap(), "nosniff");
        assert!(headers.get("strict-transport-security").is_some());
        assert!(headers.get("content-security-policy").is_some());
        assert_eq!(headers.get("x-permitted-cross-domain-policies").unwrap(), "none");
    }

    #[tokio::test]
    async fn test_owasp_anti_idor_and_quantity_validation() {
        let state = AppState::open(":memory:").unwrap();
        let app = build_router(state, None);

        // 1. Registrar usuario legítimo
        let (st, reg) = call_json(
            &app,
            "POST",
            "/api/auth/register",
            None,
            Some(json!({
                "phone": "3159998877",
                "pin": "1234",
                "owner_name": "Usuario Legítimo",
                "business_name": "Mi Tienda Real",
                "zone": "Yopal",
                "habeas_data_accepted": true
            })),
        )
        .await;
        assert_eq!(st, StatusCode::CREATED);
        let tok = reg["token"].as_str().unwrap();

        // 2. Intentar registrar movimiento con cantidad negativa -> 400 Bad Request
        let (st, err_qty) = call_json(
            &app,
            "POST",
            "/api/movements",
            Some(tok),
            Some(json!({
                "items": [{
                    "product_id": "prod_arroz_casanare",
                    "product_name": "Arroz Casanareño",
                    "action": "ENTRADA",
                    "quantity": -10.0,
                    "unit": "bultos"
                }]
            })),
        )
        .await;
        assert_eq!(st, StatusCode::BAD_REQUEST);
        assert!(err_qty["error"].as_str().unwrap().contains("mayor a cero"));

        // 3. Intentar IDOR: Usuario legítimo intenta sincronizar movimientos con business_id de otra tienda -> 403 Forbidden
        let (st, err_idor) = call_json(
            &app,
            "POST",
            "/api/sync/movements",
            Some(tok),
            Some(json!({
                "movements": [{
                    "id": "mov_ataque_idor",
                    "business_id": "tienda_demo",
                    "product_id": "prod_arroz_casanare",
                    "product_name": "Arroz",
                    "type": "IN",
                    "quantity": 100.0,
                    "unit": "bultos",
                    "timestamp": 1760000000.0
                }]
            })),
        )
        .await;
        assert_eq!(st, StatusCode::FORBIDDEN);
        assert!(err_idor["error"].as_str().unwrap().contains("permisos"));
    }
}
