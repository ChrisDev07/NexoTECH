#!/usr/bin/env python3
"""
Servidor API REST y Simulador Web para NexoLlano.
Funciona 100% con la librería estándar de Python (sin requerir dependencias externas).
"""

import sys
import os
import json
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

# Asegurar importación de módulos hermanos
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "core_nlp")))
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from parser import RegionalNLPParser
from ledger import LocalLedger, CollectivePurchasingEngine
from models import Movement

# Inicialización de estado global en memoria
PARSER = RegionalNLPParser()
LEDGER = LocalLedger(":memory:")
COLLECTIVE_ENGINE = CollectivePurchasingEngine(freight_cost_cop=120000.0)

# Precargar inventario inicial para demostración
def seed_demo_data():
    init_movements = [
        {"product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "type": "IN", "quantity": 20, "unit": "bultos"},
        {"product_id": "prod_aceite_vegetal", "product_name": "Aceite Vegetal 900ml", "type": "IN", "quantity": 10, "unit": "cajas"},
        {"product_id": "prod_sal_marina", "product_name": "Sal Marina Refinada", "type": "IN", "quantity": 8, "unit": "bultos"},
        {"product_id": "prod_panela_criolla", "product_name": "Panela Criolla", "type": "IN", "quantity": 15, "unit": "pacas"},
        {"product_id": "prod_papa_pastusa", "product_name": "Papa Pastusa / Criolla", "type": "IN", "quantity": 12, "unit": "arrobas"},
        {"product_id": "prod_abono_triple15", "product_name": "Abono Triple 15", "type": "IN", "quantity": 15, "unit": "bultos"},
        {"product_id": "prod_cemento_gris", "product_name": "Cemento Gris 50kg", "type": "IN", "quantity": 30, "unit": "bultos"},
        {"product_id": "prod_harina_pan", "product_name": "Harina de Maíz Precocida", "type": "IN", "quantity": 12, "unit": "pacas"}
    ]
    for m in init_movements:
        LEDGER.record_movement(Movement.from_dict({**m, "synced": True}))

seed_demo_data()

class NexoLlanoHandler(BaseHTTPRequestHandler):
    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
        self.wfile.write(json.dumps(data, ensure_ascii=False).encode('utf-8'))

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path

        if path in ["/", "/index.html"]:
            static_file = os.path.join(os.path.dirname(__file__), "static", "index.html")
            try:
                with open(static_file, "rb") as f:
                    content = f.read()
                self.send_response(200)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.end_headers()
                self.wfile.write(content)
            except Exception as e:
                self.send_response(500)
                self.end_headers()
                self.wfile.write(f"Error cargando index.html: {str(e)}".encode('utf-8'))
        elif path == "/api/stock":
            stock = LEDGER.compute_stock(PARSER.catalog["products"])
            self._send_json(stock)
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

        if path == "/api/nlp/parse":
            phrase = payload.get("phrase", "")
            items = PARSER.parse_phrase(phrase)
            self._send_json(items)

        elif path == "/api/movements":
            items = payload.get("items", [])
            synced = payload.get("synced", True)
            recorded = []
            for it in items:
                mov = Movement.from_dict({
                    "product_id": it["product_id"],
                    "product_name": it["product_name"],
                    "type": "OUT" if it["action"] == "SALIDA" else "IN",
                    "quantity": it["quantity"],
                    "unit": it["unit"],
                    "synced": synced
                })
                LEDGER.record_movement(mov)
                recorded.append(mov.to_dict())
            self._send_json({"status": "ok", "recorded": recorded})

        elif path == "/api/sync":
            pending = LEDGER.get_pending_sync_movements()
            ids = [m.id for m in pending]
            LEDGER.mark_as_synced(ids)
            self._send_json({"status": "ok", "synced_count": len(ids)})

        elif path == "/api/collective/simulate":
            collective_orders = [
                {"business_id": "t1", "business_name": "Tienda Don Pedro", "product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "quantity": 15, "unit": "bultos", "retail_price_cop": 185000, "wholesale_price_cop": 155000},
                {"business_id": "t2", "business_name": "Agroinsumos Doña Martha", "product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "quantity": 25, "unit": "bultos", "retail_price_cop": 185000, "wholesale_price_cop": 155000},
                {"business_id": "t3", "business_name": "Minimarket El Llano", "product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "quantity": 20, "unit": "bultos", "retail_price_cop": 185000, "wholesale_price_cop": 155000},
                {"business_id": "t4", "business_name": "Comercializadora El Triunfo", "product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "quantity": 10, "unit": "bultos", "retail_price_cop": 185000, "wholesale_price_cop": 155000}
            ]
            res = COLLECTIVE_ENGINE.aggregate_orders(collective_orders)
            self._send_json(res)

        elif path == "/api/reset":
            seed_demo_data()
            self._send_json({"status": "ok", "message": "Datos reiniciados"})

        else:
            self._send_json({"error": "Endpoint no encontrado"}, status=404)

def run(port=8000):
    server_address = ('', port)
    httpd = HTTPServer(server_address, NexoLlanoHandler)
    print(f"🚀 Servidor NexoLlano activo en http://localhost:{port}")
    httpd.serve_forever()

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    run(port)
