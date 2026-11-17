"""
Módulo de Central de Compras Colectivas para Origo (CREATIC Casanare).
Agrupa demanda geolocalizada por comuna/vereda y calcula descuentos mayoristas y flete compartido.
"""

from typing import List, Dict, Any


class CollectivePurchasingEngine:
    """Motor de Agrupación de Demanda y Cálculo de Ahorros por Comuna o Vereda."""

    def __init__(self, freight_cost_cop: float = 120000.0):
        self.freight_cost_cop = freight_cost_cop

    def aggregate_orders(self, orders: List[Dict[str, Any]]) -> Dict[str, Any]:
        """
        Agrupa solicitudes de compra por producto en una misma zona.
        Calcula precio individual vs precio mayorista y ahorro en flete compartido.
        """
        if not orders:
            return {"total_savings_cop": 0, "groups": [], "participating_stores": 0}

        participating_businesses = set(o["business_id"] for o in orders)
        num_stores = len(participating_businesses)

        grouped_by_product: Dict[str, Dict[str, Any]] = {}
        for o in orders:
            pid = o["product_id"]
            if pid not in grouped_by_product:
                grouped_by_product[pid] = {
                    "product_id": pid,
                    "product_name": o["product_name"],
                    "unit": o["unit"],
                    "total_quantity": 0.0,
                    "retail_price": o.get("retail_price_cop", 0),
                    "wholesale_price": o.get("wholesale_price_cop", 0),
                    "contributions": []
                }
            grouped_by_product[pid]["total_quantity"] += o["quantity"]
            grouped_by_product[pid]["contributions"].append({
                "business_id": o["business_id"],
                "business_name": o["business_name"],
                "quantity": o["quantity"]
            })

        total_product_savings = 0.0
        product_results = []

        for pid, data in grouped_by_product.items():
            qty = data["total_quantity"]
            retail_total = qty * data["retail_price"]
            wholesale_total = qty * data["wholesale_price"]
            saving = max(0.0, retail_total - wholesale_total)
            discount_pct = (
                round(((data["retail_price"] - data["wholesale_price"]) / data["retail_price"] * 100), 1)
                if data["retail_price"] > 0
                else 0
            )

            total_product_savings += saving
            product_results.append({
                "product_id": pid,
                "product_name": data["product_name"],
                "total_quantity": qty,
                "unit": data["unit"],
                "retail_total_cop": retail_total,
                "wholesale_total_cop": wholesale_total,
                "savings_cop": saving,
                "discount_percentage": discount_pct,
                "stores_count": len(data["contributions"]),
                "contributions": data["contributions"]
            })

        individual_freight_total = num_stores * self.freight_cost_cop
        collective_freight_total = self.freight_cost_cop if num_stores > 0 else 0
        freight_savings = max(0.0, individual_freight_total - collective_freight_total)
        freight_per_store = round(collective_freight_total / num_stores, 0) if num_stores > 0 else 0

        total_net_savings = total_product_savings + freight_savings

        return {
            "participating_stores_count": num_stores,
            "total_product_savings_cop": total_product_savings,
            "freight_savings_cop": freight_savings,
            "individual_freight_cop": self.freight_cost_cop,
            "freight_per_store_cop": freight_per_store,
            "total_net_savings_cop": total_net_savings,
            "products": product_results
        }
