//! Módulo de Central de Compras Colectivas para Origo (CREATIC Casanare).
//! Agrupa demanda geolocalizada por municipio/región y calcula descuentos mayoristas y flete compartido.

use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CollectiveOrderInput {
    pub business_id: String,
    pub business_name: String,
    pub product_id: String,
    pub product_name: String,
    pub quantity: f64,
    pub unit: String,
    pub retail_price_cop: f64,
    pub wholesale_price_cop: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoreContribution {
    pub business_id: String,
    pub business_name: String,
    pub quantity: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CollectiveProductResult {
    pub product_id: String,
    pub product_name: String,
    pub total_quantity: f64,
    pub target_quantity: f64,
    pub unit: String,
    pub retail_total_cop: f64,
    pub wholesale_total_cop: f64,
    pub savings_cop: f64,
    pub discount_percentage: f64,
    pub stores_count: usize,
    pub contributions: Vec<StoreContribution>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CollectiveSummary {
    pub participating_stores_count: usize,
    pub total_product_savings_cop: f64,
    pub freight_savings_cop: f64,
    pub individual_freight_cop: f64,
    pub freight_per_store_cop: f64,
    pub total_net_savings_cop: f64,
    pub products: Vec<CollectiveProductResult>,
}

pub fn default_target_for_product(product_id: &str, current_qty: f64) -> f64 {
    match product_id {
        "prod_arroz_casanare" => 100.0,
        "prod_aceite_vegetal" => 40.0,
        "prod_cemento_gris" => 80.0,
        "prod_abono_triple15" => 50.0,
        "prod_panela_criolla" => 40.0,
        "prod_papa_pastusa" => 50.0,
        "prod_sal_marina" => 40.0,
        "prod_harina_pan" => 40.0,
        _ => (current_qty * 1.5).max(30.0).round(),
    }
}

pub struct CollectivePurchasingEngine {
    freight_cost_cop: f64,
}

impl CollectivePurchasingEngine {
    pub fn new(freight_cost_cop: f64) -> Self {
        Self { freight_cost_cop }
    }

    pub fn aggregate_orders(&self, orders: &[CollectiveOrderInput]) -> CollectiveSummary {
        if orders.is_empty() {
            return CollectiveSummary {
                participating_stores_count: 0,
                total_product_savings_cop: 0.0,
                freight_savings_cop: 0.0,
                individual_freight_cop: self.freight_cost_cop,
                freight_per_store_cop: 0.0,
                total_net_savings_cop: 0.0,
                products: Vec::new(),
            };
        }

        let mut stores: HashSet<&str> = HashSet::new();
        let mut order_of_products: Vec<String> = Vec::new();
        let mut grouped: HashMap<String, CollectiveProductResult> = HashMap::new();
        let mut price_pairs: HashMap<String, (f64, f64)> = HashMap::new();

        for o in orders {
            stores.insert(o.business_id.as_str());
            if !grouped.contains_key(&o.product_id) {
                order_of_products.push(o.product_id.clone());
                price_pairs.insert(
                    o.product_id.clone(),
                    (o.retail_price_cop, o.wholesale_price_cop),
                );
                grouped.insert(
                    o.product_id.clone(),
                    CollectiveProductResult {
                        product_id: o.product_id.clone(),
                        product_name: o.product_name.clone(),
                        total_quantity: 0.0,
                        target_quantity: 100.0,
                        unit: o.unit.clone(),
                        retail_total_cop: 0.0,
                        wholesale_total_cop: 0.0,
                        savings_cop: 0.0,
                        discount_percentage: 0.0,
                        stores_count: 0,
                        contributions: Vec::new(),
                    },
                );
            }
            if let Some(entry) = grouped.get_mut(&o.product_id) {
                entry.total_quantity += o.quantity;
                entry.contributions.push(StoreContribution {
                    business_id: o.business_id.clone(),
                    business_name: o.business_name.clone(),
                    quantity: o.quantity,
                });
            }
        }

        let num_stores = stores.len();
        let mut total_product_savings = 0.0;
        let mut products = Vec::with_capacity(order_of_products.len());

        for pid in order_of_products {
            if let Some(mut item) = grouped.remove(&pid) {
                let (retail, wholesale) = price_pairs.get(&pid).copied().unwrap_or((0.0, 0.0));
                let retail_total = item.total_quantity * retail;
                let wholesale_total = item.total_quantity * wholesale;
                let saving = (retail_total - wholesale_total).max(0.0);
                let discount_pct = if retail > 0.0 {
                    (((retail - wholesale) / retail) * 1000.0).round() / 10.0
                } else {
                    0.0
                };
                item.retail_total_cop = retail_total;
                item.wholesale_total_cop = wholesale_total;
                item.savings_cop = saving;
                item.discount_percentage = discount_pct;
                item.stores_count = item.contributions.len();
                item.target_quantity = default_target_for_product(&pid, item.total_quantity);

                total_product_savings += saving;
                products.push(item);
            }
        }

        let individual_freight_total = (num_stores as f64) * self.freight_cost_cop;
        let collective_freight_total = if num_stores > 0 {
            self.freight_cost_cop
        } else {
            0.0
        };
        let freight_savings = (individual_freight_total - collective_freight_total).max(0.0);
        let freight_per_store = if num_stores > 0 {
            (collective_freight_total / (num_stores as f64)).round()
        } else {
            0.0
        };

        CollectiveSummary {
            participating_stores_count: num_stores,
            total_product_savings_cop: total_product_savings,
            freight_savings_cop: freight_savings,
            individual_freight_cop: self.freight_cost_cop,
            freight_per_store_cop: freight_per_store,
            total_net_savings_cop: total_product_savings + freight_savings,
            products,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_collective_order_aggregation() {
        let engine = CollectivePurchasingEngine::new(120_000.0);
        let orders = vec![
            CollectiveOrderInput {
                business_id: "t1".into(),
                business_name: "Tienda La Esperanza".into(),
                product_id: "prod_arroz_casanare".into(),
                product_name: "Arroz Casanareño".into(),
                quantity: 15.0,
                unit: "bultos".into(),
                retail_price_cop: 185_000.0,
                wholesale_price_cop: 155_000.0,
            },
            CollectiveOrderInput {
                business_id: "t2".into(),
                business_name: "Agroinsumos Doña Martha".into(),
                product_id: "prod_arroz_casanare".into(),
                product_name: "Arroz Casanareño".into(),
                quantity: 25.0,
                unit: "bultos".into(),
                retail_price_cop: 185_000.0,
                wholesale_price_cop: 155_000.0,
            },
            CollectiveOrderInput {
                business_id: "t3".into(),
                business_name: "Minimarket El Llano".into(),
                product_id: "prod_arroz_casanare".into(),
                product_name: "Arroz Casanareño".into(),
                quantity: 20.0,
                unit: "bultos".into(),
                retail_price_cop: 185_000.0,
                wholesale_price_cop: 155_000.0,
            },
            CollectiveOrderInput {
                business_id: "t4".into(),
                business_name: "Comercializadora El Triunfo".into(),
                product_id: "prod_arroz_casanare".into(),
                product_name: "Arroz Casanareño".into(),
                quantity: 10.0,
                unit: "bultos".into(),
                retail_price_cop: 185_000.0,
                wholesale_price_cop: 155_000.0,
            },
        ];

        let res = engine.aggregate_orders(&orders);
        assert_eq!(res.participating_stores_count, 4);
        assert_eq!(res.products[0].total_quantity, 70.0);
        assert_eq!(res.total_product_savings_cop, 2_100_000.0);
        assert_eq!(res.freight_savings_cop, 360_000.0);
        assert_eq!(res.freight_per_store_cop, 30_000.0);
        assert_eq!(res.total_net_savings_cop, 2_460_000.0);
    }
}
