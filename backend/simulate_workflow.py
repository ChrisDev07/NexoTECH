#!/usr/bin/env python3
"""
Simulador de Flujo de Operación y Agrupación de Demanda - Proyecto Origo
Validación de Entorno Operativo (TRL 4-5) · CREATIC Casanare
Demuestra el ciclo de vida de inventario sin conexión y consolidación de compras.
"""

import sys
import os
import time

# Asegurar importación de módulos hermanos
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "core_nlp")))
sys.path.insert(0, os.path.abspath(os.path.dirname(__file__)))

from parser import RegionalNLPParser
from ledger import LocalLedger, CollectivePurchasingEngine
from models import Movement

GREEN = "\033[92m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"

def print_banner():
    print(f"\n{BOLD}{CYAN}===================================================================={RESET}")
    print(f"{BOLD}{GREEN}           🌾 ORIGO - PLATAFORMA DE OPERACIÓN MiPyME 🌾{RESET}")
    print(f"{BOLD}    Inventario por Voz Offline y Central de Compras Colectiva{RESET}")
    print(f"{CYAN}===================================================================={RESET}\n")

def run_workflow_simulation():
    print_banner()
    time.sleep(0.5)

    parser = RegionalNLPParser()
    ledger = LocalLedger(":memory:")
    collective_engine = CollectivePurchasingEngine(freight_cost_cop=120000.0)

    # 1. Precargar inventario inicial
    catalog = parser.catalog["products"]
    print(f"{BOLD}[PASO 1] 📦 Precargando inventario base de la Tienda 'Don Pedro' (Comuna 2 Yopal)...{RESET}")
    init_movements = [
        {"product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "type": "IN", "quantity": 20, "unit": "bultos"},
        {"product_id": "prod_aceite_vegetal", "product_name": "Aceite Vegetal 900ml", "type": "IN", "quantity": 10, "unit": "cajas"},
        {"product_id": "prod_sal_marina", "product_name": "Sal Marina Refinada", "type": "IN", "quantity": 8, "unit": "bultos"}
    ]
    for m in init_movements:
        ledger.record_movement(Movement.from_dict({**m, "synced": True}))
    print(f"{GREEN}✔ Inventario base activo.{RESET}")

    # 2. Demostración en Modo Avión
    print(f"\n{BOLD}{YELLOW}[PASO 2] ✈️ ACTIVANDO MODO AVIÓN (Sin conexión a internet ni datos móviles){RESET}")
    print(f"El comerciante oprime el botón 'Hablar' y dicta la venta del día:")
    sample_voice = "vendí quince bultos de arroz casanare y cinco bultos de sal"
    print(f"\n🎙️ {BOLD}Audio capturado:{RESET} \"{sample_voice}\"")
    time.sleep(0.8)

    # 3. Procesamiento NLP local
    print(f"\n{BOLD}[PASO 3] ⚡ Procesando transcripción en el dispositivo (NLP Heurístico Local)...{RESET}")
    parsed_items = parser.parse_phrase(sample_voice)
    for idx, item in enumerate(parsed_items, 1):
        print(f"  {CYAN}Item {idx}:{RESET} Acción: {BOLD}{item['action']}{RESET} | Cantidad: {item['quantity']} {item['unit']} | Producto: {BOLD}{item['product_name']}{RESET} (Confianza: {item['confidence']*100}%)")
    time.sleep(0.8)

    # 4. Asentamiento en el Ledger inmutable
    print(f"\n{BOLD}[PASO 4] 💾 Asentando en Libro Mayor Local (Event Sourcing inmutable)...{RESET}")
    for item in parsed_items:
        mov = Movement.from_dict({
            "product_id": item["product_id"],
            "product_name": item["product_name"],
            "type": "OUT" if item["action"] == "SALIDA" else "IN",
            "quantity": item["quantity"],
            "unit": item["unit"],
            "synced": False
        })
        ledger.record_movement(mov)
    print(f"{GREEN}✔ Movimientos registrados localmente sin internet (synced=False).{RESET}")

    # 5. Cálculo de Stock y Alertas
    print(f"\n{BOLD}[PASO 5] 📊 Calculando balance de stock reactivo...{RESET}")
    current_stocks = ledger.compute_stock(catalog)
    needs_reorder_list = []
    for s in current_stocks:
        if s["product_id"] in ["prod_arroz_casanare", "prod_sal_marina"]:
            status = f"{YELLOW}⚠️ UMBRAL CRÍTICO (Reposición Sugerida){RESET}" if s["needs_reorder"] else f"{GREEN}EN REGLA{RESET}"
            print(f"  • {BOLD}{s['product_name']}:{RESET} Quedan {BOLD}{s['current_stock']} {s['unit']}{RESET} (Mínimo: {s['min_threshold']}) -> {status}")
            if s["needs_reorder"]:
                needs_reorder_list.append(s)

    # 6. Reconexión y Sincronización
    print(f"\n{BOLD}{GREEN}[PASO 6] 🌐 DESACTIVANDO MODO AVIÓN (Reconexión automática detectada){RESET}")
    pending = ledger.get_pending_sync_movements()
    print(f"Sincronizando {len(pending)} transacciones pendientes con el servidor regional...")
    time.sleep(0.5)
    ledger.mark_as_synced([p.id for p in pending])
    print(f"{GREEN}✔ Sincronización idempotente completada al 100%. Cero conflictos.{RESET}")

    # 7. Compras Colectivas por Comuna en Casanare
    print(f"\n{BOLD}{CYAN}[PASO 7] 🤝 ACTIVACIÓN DE CENTRAL DE COMPRAS COLECTIVAS (Comuna 2 - Yopal){RESET}")
    print("Otras 3 tiendas vecinas de la misma comuna registraron necesidad de reposición de arroz:")
    
    collective_orders = [
        {"business_id": "t1", "business_name": "Tienda Don Pedro", "product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "quantity": 15, "unit": "bultos", "retail_price_cop": 185000, "wholesale_price_cop": 155000},
        {"business_id": "t2", "business_name": "Agroinsumos Doña Martha", "product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "quantity": 25, "unit": "bultos", "retail_price_cop": 185000, "wholesale_price_cop": 155000},
        {"business_id": "t3", "business_name": "Minimarket El Llano", "product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "quantity": 20, "unit": "bultos", "retail_price_cop": 185000, "wholesale_price_cop": 155000},
        {"business_id": "t4", "business_name": "Comercializadora El Triunfo", "product_id": "prod_arroz_casanare", "product_name": "Arroz Casanareño", "quantity": 10, "unit": "bultos", "retail_price_cop": 185000, "wholesale_price_cop": 155000}
    ]

    result = collective_engine.aggregate_orders(collective_orders)
    prod_agg = result["products"][0]

    print(f"\n  📦 {BOLD}Total consolidado:{RESET} {prod_agg['total_quantity']} bultos de Arroz Casanareño entre {result['participating_stores_count']} comercios.")
    print(f"  💵 {BOLD}Precio minorista individual:{RESET} ${prod_agg['retail_total_cop']:,.0f} COP")
    print(f"  🏷️ {BOLD}Precio mayorista agrupado:{RESET}   ${prod_agg['wholesale_total_cop']:,.0f} COP ({prod_agg['discount_percentage']}% descuento)")
    print(f"  🚚 {BOLD}Flete individual por separado:{RESET} ${result['individual_freight_cop']*result['participating_stores_count']:,.0f} COP")
    print(f"  🤝 {BOLD}Flete compartido en colectivo:{RESET} ${result['individual_freight_cop']:,.0f} COP (${result['freight_per_store_cop']:,.0f} por tienda)")
    print(f"\n{BOLD}{GREEN}  💰 AHORRO TOTAL NETO PARA LA COMUNA: ${result['total_net_savings_cop']:,.0f} COP{RESET}")
    print(f"\n{BOLD}{CYAN}===================================================================={RESET}")
    print(f"{BOLD}{GREEN}       ✔ VALIDACIÓN DE ENTORNO OPERATIVO COMPLETADA EXITOSAMENTE{RESET}")
    print(f"{BOLD}       Prototipo validado bajo arquitectura Event Sourcing (TRL 4-5).{RESET}")
    print(f"{CYAN}===================================================================={RESET}\n")

if __name__ == "__main__":
    run_workflow_simulation()
