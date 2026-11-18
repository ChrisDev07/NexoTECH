//! Modelos de datos compartidos del backend de Origo (CREATIC Casanare).
//! Arquitectura Event Sourcing / Ledger Inmutable, Autenticación Ley 1581 y Compras Colectivas.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

pub fn now_unix_secs() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs_f64())
        .unwrap_or(0.0)
}

pub fn round2(v: f64) -> f64 {
    (v * 100.0).round() / 100.0
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Catalog {
    pub units: Vec<String>,
    pub intentions: HashMap<String, Vec<String>>,
    pub products: Vec<CatalogProduct>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CatalogProduct {
    pub id: String,
    pub name: String,
    #[serde(default = "default_category")]
    pub category: String,
    #[serde(default = "default_unit")]
    pub default_unit: String,
    #[serde(default)]
    pub retail_price_cop: f64,
    #[serde(default)]
    pub wholesale_price_cop: f64,
    #[serde(default = "default_threshold")]
    pub min_threshold: f64,
    #[serde(default)]
    pub synonyms: Vec<String>,
}

fn default_category() -> String {
    "General".to_string()
}

fn default_unit() -> String {
    "unidades".to_string()
}

fn default_threshold() -> f64 {
    5.0
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Movement {
    pub id: String,
    pub business_id: String,
    pub product_id: String,
    pub product_name: String,
    #[serde(rename = "type")]
    pub movement_type: String, // "IN" o "OUT"
    pub quantity: f64,
    pub unit: String,
    pub timestamp: f64,
    pub device_id: String,
    pub synced: bool,
}

impl Movement {
    pub fn new(
        business_id: String,
        product_id: String,
        product_name: String,
        movement_type: String,
        quantity: f64,
        unit: String,
        timestamp: Option<f64>,
        device_id: Option<String>,
        synced: bool,
    ) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            business_id,
            product_id,
            product_name,
            movement_type,
            quantity,
            unit,
            timestamp: timestamp.unwrap_or_else(now_unix_secs),
            device_id: device_id.unwrap_or_else(|| "device_demo".to_string()),
            synced,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MovementView {
    #[serde(flatten)]
    pub movement: Movement,
    pub is_today: bool,
    pub time_str: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StockItem {
    pub product_id: String,
    pub product_name: String,
    pub category: String,
    pub current_stock: f64,
    pub unit: String,
    pub min_threshold: f64,
    pub needs_reorder: bool,
    pub retail_price_cop: f64,
    pub wholesale_price_cop: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DailyStockItem {
    pub product_id: String,
    pub product_name: String,
    pub category: String,
    pub opening_stock: f64,
    pub today_in: f64,
    pub today_out: f64,
    pub daily_net: f64,
    pub current_stock: f64,
    pub has_activity_today: bool,
    pub today_movements_count: usize,
    pub last_movement_time: Option<String>,
    pub unit: String,
    pub min_threshold: f64,
    pub needs_reorder: bool,
    pub retail_price_cop: f64,
    pub wholesale_price_cop: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DailyStockSummary {
    pub total_in_today: f64,
    pub total_out_today: f64,
    pub movements_count_today: usize,
    pub critical_products_count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DailyStockResponse {
    pub date: String,
    pub window: String,
    pub summary: DailyStockSummary,
    pub items: Vec<DailyStockItem>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PublicUser {
    pub id: String,
    pub phone: String,
    pub owner_name: String,
    pub business_name: String,
    #[serde(default)]
    pub document_id: String,
    #[serde(default)]
    pub address: String,
    pub zone: String,
    pub role: String,
    pub habeas_data_accepted: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthResponse {
    pub token: String,
    pub user: PublicUser,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrivacyRoles {
    pub responsable: String,
    pub encargado: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrivacyPolicy {
    pub title: String,
    pub summary: String,
    pub roles: PrivacyRoles,
    pub rights: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ParsedEntity {
    pub raw_clause: String,
    pub action: String,
    pub quantity: f64,
    pub unit: String,
    pub product_id: String,
    pub product_name: String,
    pub category: String,
    pub retail_price_cop: f64,
    pub wholesale_price_cop: f64,
    pub min_threshold: f64,
    pub confidence: f64,
}
