#!/usr/bin/env python3
"""
Servidor API REST y Simulador Web para Origo.
Funciona 100% con la librería estándar de Python (sin requerir dependencias externas).
"""

import sys
import os
import json
import time
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

# Asegurar importación de módulos hermanos
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "core_nlp")))
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from parser import RegionalNLPParser
from ledger import LocalLedger
from collective import CollectivePurchasingEngine
from auth import AuthManager
from models import Movement

STATIC_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "static"))
MIME_TYPES = {
    ".html": "text/html; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".svg": "image/svg+xml",
    ".png": "image/png"
}

# Inicialización de estado global persistente en SQLite
DB_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "origo_data.db")
PARSER = RegionalNLPParser()
LEDGER = LocalLedger(DB_PATH)
AUTH = AuthManager(DB_PATH)
COLLECTIVE_ENGINE = CollectivePurchasingEngine(freight_cost_cop=120000.0)

def seed_opening_stock_for_business(business_id: str, include_today_samples: bool = False):
    """Precarga saldo inicial (antes de 00:00) para una tienda."""
    now = datetime.now()
    start_of_today = datetime(now.year, now.month, now.day, 0, 0, 0).timestamp()
    opening_ts = start_of_today - 3600  # Cierre de ayer = Saldo inicial de hoy 00:00

    init_movements = [
        {"product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "type": "IN", "quantity": 20, "unit": "bultos", "timestamp": opening_ts},
        {"product_id": "prod_aceite_vegetal", "product_name": "Aceite Vegetal 900ml", "type": "IN", "quantity": 10, "unit": "cajas", "timestamp": opening_ts},
        {"product_id": "prod_sal_marina", "product_name": "Sal Marina Refinada", "type": "IN", "quantity": 8, "unit": "bultos", "timestamp": opening_ts},
        {"product_id": "prod_panela_criolla", "product_name": "Panela Criolla", "type": "IN", "quantity": 15, "unit": "pacas", "timestamp": opening_ts},
        {"product_id": "prod_papa_pastusa", "product_name": "Papa Pastusa / Criolla", "type": "IN", "quantity": 12, "unit": "arrobas", "timestamp": opening_ts},
        {"product_id": "prod_abono_triple15", "product_name": "Abono Triple 15", "type": "IN", "quantity": 15, "unit": "bultos", "timestamp": opening_ts},
        {"product_id": "prod_cemento_gris", "product_name": "Cemento Gris 50kg", "type": "IN", "quantity": 30, "unit": "bultos", "timestamp": opening_ts},
        {"product_id": "prod_harina_pan", "product_name": "Harina de Maíz Precocida", "type": "IN", "quantity": 12, "unit": "pacas", "timestamp": opening_ts}
    ]
    if include_today_samples:
        init_movements.extend([
            {"product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "type": "OUT", "quantity": 5, "unit": "bultos", "timestamp": max(start_of_today + 60, time.time() - 1800)},
            {"product_id": "prod_papa_pastusa", "product_name": "Papa Pastusa / Criolla", "type": "OUT", "quantity": 4, "unit": "arrobas", "timestamp": max(start_of_today + 120, time.time() - 900)}
        ])
    for m in init_movements:
        LEDGER.record_movement(Movement.from_dict({**m, "business_id": business_id, "synced": True}))

# Precargar saldo inicial demo solo si la tienda demo está vacía
def seed_demo_data(force: bool = False):
    if not force and len(LEDGER.get_all_movements(business_id="tienda_demo")) > 0:
        return
    if force:
        with LEDGER.conn:
            LEDGER.conn.execute("DELETE FROM movements WHERE business_id = ?", ("tienda_demo",))
    seed_opening_stock_for_business("tienda_demo", include_today_samples=True)

seed_demo_data()

class OrigoHandler(BaseHTTPRequestHandler):
    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode('utf-8'))

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        self.end_headers()

    def _get_auth_token(self):
        auth_header = self.headers.get('Authorization', '')
        if auth_header.startswith('Bearer '):
            return auth_header[7:].strip()
        return None

    def _get_current_user(self):
        return AUTH.get_session_user(self._get_auth_token())

    def _get_business_id(self) -> str:
        user = self._get_current_user()
        return user["id"] if user else "tienda_demo"

    def _serve_static(self, rel_path: str):
        safe_path = os.path.abspath(os.path.join(STATIC_DIR, rel_path.lstrip("/")))
        if not safe_path.startswith(STATIC_DIR) or not os.path.isfile(safe_path):
            self._send_json({"error": "Archivo estático no encontrado"}, status=404)
            return
        ext = os.path.splitext(safe_path)[1].lower()
        content_type = MIME_TYPES.get(ext, "application/octet-stream")
        try:
            with open(safe_path, "rb") as f:
                content = f.read()
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Cache-Control', 'no-cache')
            self.end_headers()
            self.wfile.write(content)
        except Exception as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(f"Error cargando recurso estático: {str(e)}".encode('utf-8'))

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path in ["/", "/index.html"]:
            self._serve_static("index.html")
        elif path.startswith("/css/") or path.startswith("/js/"):
            self._serve_static(path)
        elif path == "/api/privacy":
            self._send_json(AUTH.get_privacy_policy())
        elif path == "/api/auth/me":
            user = self._get_current_user()
            if not user:
                self._send_json({"error": "Sesión no iniciada"}, status=401)
            else:
                self._send_json({"user": user})
        elif path == "/api/stock":
            business_id = self._get_business_id()
            stock = LEDGER.compute_stock(PARSER.catalog["products"], business_id=business_id)
            self._send_json(stock)
        elif path == "/api/stock/daily":
            business_id = self._get_business_id()
            daily = LEDGER.compute_daily_stock(PARSER.catalog["products"], business_id=business_id)
            self._send_json(daily)
        elif path == "/api/movements":
            business_id = self._get_business_id()
            now = datetime.now()
            start_ts = datetime(now.year, now.month, now.day, 0, 0, 0).timestamp()
            end_ts = datetime(now.year, now.month, now.day, 23, 59, 59, 999999).timestamp()
            movements = []
            for m in LEDGER.get_all_movements(business_id=business_id):
                d = m.to_dict()
                is_today = start_ts <= m.timestamp <= end_ts
                d["is_today"] = is_today
                d["time_str"] = datetime.fromtimestamp(m.timestamp).strftime("%H:%M") if is_today else "Saldo 00:00"
                movements.append(d)
            movements.reverse()  # Más recientes primero
            self._send_json(movements)
        elif path == "/api/catalog":
            self._send_json(PARSER.catalog)
        else:
            self._send_json({"error": "Ruta no encontrada"}, status=404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        length = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(length).decode('utf-8') if length > 0 else "{}"
        try:
            payload = json.loads(body)
        except Exception:
            payload = {}

        if path == "/api/auth/register":
            res, err = AUTH.register_user(
                phone=payload.get("phone", ""),
                pin=payload.get("pin", ""),
                owner_name=payload.get("owner_name", ""),
                business_name=payload.get("business_name", ""),
                zone=payload.get("zone", "Comuna 2, Yopal"),
                habeas_data_accepted=bool(payload.get("habeas_data_accepted", False))
            )
            if err:
                self._send_json({"error": err}, status=400)
                return
            seed_opening_stock_for_business(res["user"]["id"], include_today_samples=False)
            self._send_json(res, status=201)

        elif path == "/api/auth/login":
            res, err = AUTH.login(
                phone=payload.get("phone", ""),
                pin=payload.get("pin", "")
            )
            if err:
                self._send_json({"error": err}, status=401)
                return
            self._send_json(res)

        elif path == "/api/auth/logout":
            AUTH.logout(self._get_auth_token())
            self._send_json({"status": "ok"})

        elif path == "/api/nlp/parse":
            phrase = payload.get("phrase", "")
            items = PARSER.parse_phrase(phrase)
            self._send_json(items)

        elif path == "/api/movements":
            business_id = self._get_business_id()
            items = payload.get("items", [])
            synced = payload.get("synced", True)
            recorded = []
            for it in items:
                mov = Movement.from_dict({
                    "business_id": business_id,
                    "product_id": it["product_id"],
                    "product_name": it["product_name"],
                    "type": "OUT" if it["action"] == "SALIDA" else "IN",
                    "quantity": it["quantity"],
                    "unit": it["unit"],
                    "synced": synced
                })
                LEDGER.record_movement(mov)
                recorded.append(mov.to_dict())
            daily_stock = LEDGER.compute_daily_stock(PARSER.catalog["products"], business_id=business_id)
            self._send_json({"status": "ok", "recorded": recorded, "daily_stock": daily_stock})

        elif path == "/api/sync/movements":
            business_id = self._get_business_id()
            incoming = payload.get("movements", [])
            synced_ids = []
            for m in incoming:
                raw_ts = float(m.get("timestamp", time.time()))
                # Normalizar milisegundos (Dart/Android) a segundos Unix
                ts_sec = raw_ts / 1000.0 if raw_ts > 1e11 else raw_ts
                mov = Movement.from_dict({
                    "id": m["id"],
                    "business_id": m.get("business_id") or business_id,
                    "product_id": m["product_id"],
                    "product_name": m.get("product_name", ""),
                    "type": m["type"],
                    "quantity": m["quantity"],
                    "unit": m.get("unit", "unidades"),
                    "timestamp": ts_sec,
                    "device_id": m.get("device_id", "android_mobile"),
                    "synced": True
                })
                LEDGER.record_movement(mov)
                synced_ids.append(mov.id)
            daily_stock = LEDGER.compute_daily_stock(PARSER.catalog["products"], business_id=business_id)
            self._send_json({"status": "ok", "synced_ids": synced_ids, "synced_count": len(synced_ids), "daily_stock": daily_stock})

        elif path == "/api/sync":
            business_id = self._get_business_id()
            pending = [m for m in LEDGER.get_pending_sync_movements() if m.business_id == business_id]
            ids = [m.id for m in pending]
            LEDGER.mark_as_synced(ids)
            self._send_json({"status": "ok", "synced_count": len(ids)})

        elif path == "/api/collective/simulate":
            user = self._get_current_user()
            my_id = user["id"] if user else "t1"
            my_business = user["business_name"] if user else "Tienda La Esperanza"
            collective_orders = [
                {"business_id": my_id, "business_name": my_business, "product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "quantity": 15, "unit": "bultos", "retail_price_cop": 185000, "wholesale_price_cop": 155000},
                {"business_id": "t2", "business_name": "Agroinsumos Doña Martha", "product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "quantity": 25, "unit": "bultos", "retail_price_cop": 185000, "wholesale_price_cop": 155000},
                {"business_id": "t3", "business_name": "Minimarket El Llano", "product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "quantity": 20, "unit": "bultos", "retail_price_cop": 185000, "wholesale_price_cop": 155000},
                {"business_id": "t4", "business_name": "Comercializadora El Triunfo", "product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "quantity": 10, "unit": "bultos", "retail_price_cop": 185000, "wholesale_price_cop": 155000}
            ]
            res = COLLECTIVE_ENGINE.aggregate_orders(collective_orders)
            self._send_json(res)

        elif path == "/api/reset":
            seed_demo_data(force=True)
            self._send_json({"status": "ok", "message": "Datos reiniciados"})

        else:
            self._send_json({"error": "Endpoint no encontrado"}, status=404)

def run(port=8000):
    server_address = ('', port)
    httpd = HTTPServer(server_address, OrigoHandler)
    print(f"🚀 Servidor Origo activo en http://localhost:{port}")
    httpd.serve_forever()

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    run(port)
