"""
Libro Mayor Inmutable (Ledger) y Motor de Compras Colectivas para Origo.
Garantiza cero pérdida de información y consistencia matemática offline-first.
"""

import sqlite3
import json
import os
import uuid
import time
from datetime import datetime, date
from typing import List, Dict, Any, Optional
from models import Movement, StockItem

class LocalLedger:
    def __init__(self, db_path: str = ":memory:"):
        self.db_path = db_path
        self.conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self.create_tables()

    def create_tables(self):
        with self.conn:
            self.conn.execute("""
                CREATE TABLE IF NOT EXISTS movements (
                    id TEXT PRIMARY KEY,
                    business_id TEXT NOT NULL,
                    product_id TEXT NOT NULL,
                    product_name TEXT NOT NULL,
                    type TEXT NOT NULL,
                    quantity REAL NOT NULL,
                    unit TEXT NOT NULL,
                    timestamp REAL NOT NULL,
                    device_id TEXT NOT NULL,
                    synced INTEGER NOT NULL
                )
            """)

    def record_movement(self, movement: Movement) -> Movement:
        with self.conn:
            self.conn.execute("""
                INSERT OR REPLACE INTO movements 
                (id, business_id, product_id, product_name, type, quantity, unit, timestamp, device_id, synced)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                movement.id, movement.business_id, movement.product_id, movement.product_name,
                movement.type, movement.quantity, movement.unit, movement.timestamp,
                movement.device_id, 1 if movement.synced else 0
            ))
        return movement

    def get_all_movements(self, business_id: Optional[str] = None) -> List[Movement]:
        cursor = self.conn.cursor()
        if business_id:
            cursor.execute("SELECT id, business_id, product_id, product_name, type, quantity, unit, timestamp, device_id, synced FROM movements WHERE business_id = ? ORDER BY timestamp ASC", (business_id,))
        else:
            cursor.execute("SELECT id, business_id, product_id, product_name, type, quantity, unit, timestamp, device_id, synced FROM movements ORDER BY timestamp ASC")
        rows = cursor.fetchall()
        return [
            Movement(
                id=r[0], business_id=r[1], product_id=r[2], product_name=r[3],
                type=r[4], quantity=r[5], unit=r[6], timestamp=r[7], device_id=r[8],
                synced=bool(r[9])
            ) for r in rows
        ]

    def compute_stock(self, catalog: List[Dict[str, Any]], business_id: str = "tienda_demo") -> List[Dict[str, Any]]:
        """Calcula de manera reactiva: Stock = sum(Entradas) - sum(Salidas)"""
        movements = self.get_all_movements(business_id=business_id)
        stock_map = {}
        for m in movements:
            if m.product_id not in stock_map:
                stock_map[m.product_id] = 0.0
            if m.type == "IN":
                stock_map[m.product_id] += m.quantity
            elif m.type == "OUT":
                stock_map[m.product_id] -= m.quantity

        result = []
        for prod in catalog:
            pid = prod["id"]
            current_qty = stock_map.get(pid, 0.0)
            threshold = prod.get("min_threshold", 5)
            needs_reorder = current_qty <= threshold
            result.append({
                "product_id": pid,
                "product_name": prod["name"],
                "category": prod.get("category", "General"),
                "current_stock": round(current_qty, 2),
                "unit": prod.get("default_unit", "unidades"),
                "min_threshold": threshold,
                "needs_reorder": needs_reorder,
                "retail_price_cop": prod.get("retail_price_cop", 0),
                "wholesale_price_cop": prod.get("wholesale_price_cop", 0)
            })
        return result

    def compute_daily_stock(
        self,
        catalog: List[Dict[str, Any]],
        business_id: str = "tienda_demo",
        target_date: Optional[date] = None
    ) -> Dict[str, Any]:
        """
        Calcula el inventario del día en la ventana exacta de 00:00:00 a 23:59:59.
        Separa el saldo inicial (antes de 00:00) de las entradas y salidas del día.
        """
        d = target_date or datetime.now().date()
        start_ts = datetime(d.year, d.month, d.day, 0, 0, 0).timestamp()
        end_ts = datetime(d.year, d.month, d.day, 23, 59, 59, 999999).timestamp()

        movements = self.get_all_movements(business_id=business_id)
        opening_map: Dict[str, float] = {}
        today_in_map: Dict[str, float] = {}
        today_out_map: Dict[str, float] = {}
        today_count_map: Dict[str, int] = {}
        last_ts_map: Dict[str, float] = {}

        total_in_today = 0.0
        total_out_today = 0.0
        total_movements_today = 0

        for m in movements:
            pid = m.product_id
            if m.timestamp < start_ts:
                delta = m.quantity if m.type == "IN" else -m.quantity
                opening_map[pid] = opening_map.get(pid, 0.0) + delta
            elif start_ts <= m.timestamp <= end_ts:
                total_movements_today += 1
                today_count_map[pid] = today_count_map.get(pid, 0) + 1
                if pid not in last_ts_map or m.timestamp > last_ts_map[pid]:
                    last_ts_map[pid] = m.timestamp
                if m.type == "IN":
                    today_in_map[pid] = today_in_map.get(pid, 0.0) + m.quantity
                    total_in_today += m.quantity
                elif m.type == "OUT":
                    today_out_map[pid] = today_out_map.get(pid, 0.0) + m.quantity
                    total_out_today += m.quantity

        items = []
        critical_count = 0
        for prod in catalog:
            pid = prod["id"]
            opening_qty = round(opening_map.get(pid, 0.0), 2)
            in_today = round(today_in_map.get(pid, 0.0), 2)
            out_today = round(today_out_map.get(pid, 0.0), 2)
            current_qty = round(opening_qty + in_today - out_today, 2)
            threshold = prod.get("min_threshold", 5)
            needs_reorder = current_qty <= threshold
            if needs_reorder:
                critical_count += 1

            last_time_str = None
            if pid in last_ts_map:
                last_time_str = datetime.fromtimestamp(last_ts_map[pid]).strftime("%H:%M")

            items.append({
                "product_id": pid,
                "product_name": prod["name"],
                "category": prod.get("category", "General"),
                "opening_stock": opening_qty,
                "today_in": in_today,
                "today_out": out_today,
                "daily_net": round(in_today - out_today, 2),
                "current_stock": current_qty,
                "has_activity_today": today_count_map.get(pid, 0) > 0,
                "today_movements_count": today_count_map.get(pid, 0),
                "last_movement_time": last_time_str,
                "unit": prod.get("default_unit", "unidades"),
                "min_threshold": threshold,
                "needs_reorder": needs_reorder,
                "retail_price_cop": prod.get("retail_price_cop", 0),
                "wholesale_price_cop": prod.get("wholesale_price_cop", 0)
            })

        return {
            "date": d.isoformat(),
            "window": "00:00 - 23:59",
            "summary": {
                "total_in_today": round(total_in_today, 2),
                "total_out_today": round(total_out_today, 2),
                "movements_count_today": total_movements_today,
                "critical_products_count": critical_count
            },
            "items": items
        }

    def get_pending_sync_movements(self) -> List[Movement]:
        cursor = self.conn.cursor()
        cursor.execute("SELECT id, business_id, product_id, product_name, type, quantity, unit, timestamp, device_id, synced FROM movements WHERE synced = 0")
        rows = cursor.fetchall()
        return [
            Movement(
                id=r[0], business_id=r[1], product_id=r[2], product_name=r[3],
                type=r[4], quantity=r[5], unit=r[6], timestamp=r[7], device_id=r[8],
                synced=False
            ) for r in rows
        ]

    def mark_as_synced(self, movement_ids: List[str]):
        with self.conn:
            self.conn.executemany("UPDATE movements SET synced = 1 WHERE id = ?", [(mid,) for mid in movement_ids])


class CollectivePurchasingEngine:
    """Motor de Agrupación de Demanda y Cálculo de Ahorros por Comuna o Vereda"""
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

        # Agrupar por producto
        grouped_by_product = {}
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

        # Cálculo de Ahorro Mayorista
        total_product_savings = 0.0
        product_results = []

        for pid, data in grouped_by_product.items():
            qty = data["total_quantity"]
            retail_total = qty * data["retail_price"]
            wholesale_total = qty * data["wholesale_price"]
            saving = max(0.0, retail_total - wholesale_total)
            discount_pct = round(((data["retail_price"] - data["wholesale_price"]) / data["retail_price"] * 100), 1) if data["retail_price"] > 0 else 0
            
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

        # Cálculo de Ahorro en Flete
        # Si compran solas, cada una pagaría un flete completo (num_stores * freight_cost)
        # En compra colectiva, se paga un solo flete repartido entre todas
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
