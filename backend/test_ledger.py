"""
Pruebas del Ledger Inmutable y Central de Compras Colectivas.
"""

import unittest
from ledger import LocalLedger, CollectivePurchasingEngine
from models import Movement

class TestLedgerAndCollective(unittest.TestCase):
    def setUp(self):
        self.ledger = LocalLedger(":memory:")
        self.catalog = [
            {
                "id": "prod_arroz_casanare",
                "name": "Arroz Casanareño",
                "default_unit": "bultos",
                "min_threshold": 10,
                "retail_price_cop": 185000,
                "wholesale_price_cop": 155000
            }
        ]

    def test_immutable_stock_computation(self):
        # Entrada de 25 bultos
        m1 = Movement.from_dict({
            "product_id": "prod_arroz_casanare",
            "type": "IN",
            "quantity": 25,
            "unit": "bultos"
        })
        self.ledger.record_movement(m1)

        # Salida de 7 bultos
        m2 = Movement.from_dict({
            "product_id": "prod_arroz_casanare",
            "type": "OUT",
            "quantity": 7,
            "unit": "bultos"
        })
        self.ledger.record_movement(m2)

        stock = self.ledger.compute_stock(self.catalog)
        self.assertEqual(len(stock), 1)
        self.assertEqual(stock[0]["current_stock"], 18.0)
        self.assertFalse(stock[0]["needs_reorder"])

        # Salida de 10 más (quedan 8, debajo del umbral de 10)
        m3 = Movement.from_dict({
            "product_id": "prod_arroz_casanare",
            "type": "OUT",
            "quantity": 10,
            "unit": "bultos"
        })
        self.ledger.record_movement(m3)

        stock2 = self.ledger.compute_stock(self.catalog)
        self.assertEqual(stock2[0]["current_stock"], 8.0)
        self.assertTrue(stock2[0]["needs_reorder"])

    def test_collective_order_aggregation(self):
        engine = CollectivePurchasingEngine(freight_cost_cop=120000)
        orders = [
            {
                "business_id": "tienda_1",
                "business_name": "Tienda Don Pedro",
                "product_id": "prod_arroz_casanare",
                "product_name": "Arroz Casanareño",
                "quantity": 15,
                "unit": "bultos",
                "retail_price_cop": 185000,
                "wholesale_price_cop": 155000
            },
            {
                "business_id": "tienda_2",
                "business_name": "Agroinsumos Doña Martha",
                "product_id": "prod_arroz_casanare",
                "product_name": "Arroz Casanareño",
                "quantity": 25,
                "unit": "bultos",
                "retail_price_cop": 185000,
                "wholesale_price_cop": 155000
            },
            {
                "business_id": "tienda_3",
                "business_name": "Minimarket El Progreso",
                "product_id": "prod_arroz_casanare",
                "product_name": "Arroz Casanareño",
                "quantity": 30,
                "unit": "bultos",
                "retail_price_cop": 185000,
                "wholesale_price_cop": 155000
            }
        ]
        res = engine.aggregate_orders(orders)
        self.assertEqual(res["participating_stores_count"], 3)
        # Total 70 bultos * (185.000 - 155.000) = 70 * 30.000 = 2.100.000 COP
        self.assertEqual(res["total_product_savings_cop"], 2100000.0)
        # Flete individual: 3 * 120.000 = 360.000. Flete colectivo: 120.000. Ahorro flete: 240.000 COP
        self.assertEqual(res["freight_savings_cop"], 240000.0)
        self.assertEqual(res["total_net_savings_cop"], 2340000.0)

if __name__ == "__main__":
    unittest.main()
