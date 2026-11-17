# ORIGO 🌾📲

> **Inventario por voz sin internet y central de compras colectiva para las MiPymes de Casanare**  
> Proyecto desarrollado por el equipo **NexoTECH** para la convocatoria de innovación abierta **CREATIC Casanare**  
> *Gobernación de Casanare – Dirección TIC / EON CASANARE S.A.S.*

![TRL Level](https://img.shields.io/badge/Madurez-TRL%204--5-brightgreen)
![Status](https://img.shields.io/badge/Estado-Prototipo%20Funcional-blue)
![Licencia](https://img.shields.io/badge/Licencia-MIT-orange)

---

## 🎯 1. El Problema en el Comercio Casanareño

En municipios y zonas rurales de Casanare (Yopal, Aguazul, Villanueva, Tauramena, Maní, etc.), la mayoría de tenderos, dueños de ferreterías, agroinsumos y pequeños restaurantes llevan sus cuentas "en la cabeza o en un cuaderno" y compran mercancía de manera solitaria.

Esto genera tres pérdidas críticas diarias:
1. **Productos perdidos o agotados sin saberlo:** Falta de trazabilidad y desabastecimiento imprevisto.
2. **Precios altos de compra y fletes individuales:** Al negociar en bajo volumen frente a molinos y distribuidores, pagan precio minorista y asumen altos costos de transporte.
3. **Abandono tecnológico:** El software tradicional exige internet permanente (que falla frecuentemente en la región), digitación en formularios pequeños y habilidades digitales avanzadas.

---

## 💡 2. La Solución: Origo

**Origo** integra los dos procesos clave de la cadena de valor en una solución accesible y de alto impacto:

```mermaid
flowchart LR
    A["🎙️ Voz del Comerciante<br/>(Sin Internet)"] --> B["⚡ Motor NLP Local<br/>(Modismos Llaneros)"]
    B --> C["📦 Libro Mayor Inmutable<br/>(Stock Reactivo)"]
    C --> D["🤝 Central de Compras<br/>(Agrupación por Comuna/Vereda)"]
    D --> E["💰 Descuento Mayorista &<br/>Ahorro en Fletes"]
```

### Pilares de la Solución:
* **Inventario por Voz 100% Offline:** El comerciante simplemente presiona un botón y dicta con su vocabulario habitual:  
  * *"Llegaron 20 bultos de arroz y 5 de sal"*  
  * *"Vendí 3 arrobas de papa y 2 pacas de panela"*  
  La aplicación transcribe en el propio celular, extrae la intención, cantidad, unidad de medida local y nombre del producto, mostrando una pantalla de confirmación rápida antes de guardar.
* **Central de Compras Colectiva:** Al registrar el movimiento real, la aplicación detecta cuándo el producto está por agotarse y propone el pedido de reposición. Agrupa la demanda de comercios vecinos de la misma zona para negociar con distribuidores a precios mayoristas y compartir el costo del flete.

---

## 🏛️ 3. Arquitectura del Proyecto

El repositorio está organizado bajo una estructura modular orientada a desacoplamiento y escalabilidad:

```text
MyPymes/
├── core_nlp/                 # Motor de procesamiento de lenguaje natural heurístico local
│   ├── catalog.json          # Catálogo tipificado con métricas y unidades regionales
│   ├── parser.py             # Normalización léxica, extracción de entidades y fuzzy matching
│   └── test_parser.py        # Suite de pruebas unitarias de interpretación lingüística
├── backend/                  # Servicios de sincronización y motor de agregación
│   ├── models.py             # Modelos de dominio y contratos de datos
│   ├── ledger.py             # Modelo inmutable de transacciones (Event Sourcing)
│   ├── server.py             # Servidor de servicios REST y consola de monitoreo
│   ├── simulate_workflow.py  # Módulo de validación de flujo integral y red colectiva
│   ├── static/               # Consola web de interacción en tiempo real
│   └── test_ledger.py        # Pruebas unitarias de integridad transaccional
├── mobile/                   # Cliente móvil multiplataforma (Flutter / Dart)
│   ├── lib/                  # Vistas operativas y controlador de captura oral (PTT)
│   ├── assets/               # Catálogo regional para resolución sin conectividad
│   └── pubspec.yaml          # Definición de arquitectura y dependencias móviles
├── .gitignore                # Reglas de exclusión de artefactos y entorno
└── README.md                 # Documento técnico principal
```

---

## ⚡ 4. Guía de Ejecución y Validación Técnica

La arquitectura del prototipo fue concebida para garantizar una validación técnica ágil e independiente, ejecutándose de forma nativa bajo **Python 3.8+** sin dependencias externas requeridas.

### 4.1. Verificación del Motor Lingüístico Local (NLP Heurístico):
Ejecución de la suite de pruebas automatizadas para comprobar el reconocimiento de modismos regionales, normalización numérica y extracción estructurada de entidades:
```bash
python3 core_nlp/test_parser.py
```

### 4.2. Simulación de Flujo Operativo Integral (Modo Desconectado y Red Colectiva):
Demostración del ciclo completo de inventario bajo arquitectura Event Sourcing, cálculo reactivo de existencias críticas y consolidación de demanda mayorista entre comercios geolocalizados:
```bash
python3 backend/simulate_workflow.py
```

### 4.3. Inicialización del Servidor y Consola de Monitoreo:
Despliegue del servicio local para interacción en tiempo real mediante interfaz gráfica:
```bash
python3 backend/server.py
```
Acceso a la consola operativa en: `http://localhost:8000`

---

## 🛡️ 5. Cumplimiento Normativo y Seguridad
* **Protección de Datos Personales:** Cumple estrictamente con la **Ley 1581 de 2012** (Habeas Data Colombia), minimizando la recolección de datos personales de clientes finales.
* **Ciberseguridad:** Transacciones inmutables mediante UUIDs v4 (*Event Sourcing*) para evitar inconsistencias en sincronización fuera de línea y cifrado en reposo y en tránsito.
