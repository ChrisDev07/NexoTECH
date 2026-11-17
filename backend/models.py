"""
Modelos de Datos para Origo (CREATIC Casanare)
Arquitectura Event Sourcing / Ledger Inmutable y Compras Colectivas.
"""

from dataclasses import dataclass, field, asdict
from typing import Optional, List, Dict
import time
import uuid

@dataclass
class Movement:
    id: str
    business_id: str
    product_id: str
    product_name: str
    type: str  # "IN" o "OUT"
    quantity: float
    unit: str
    timestamp: float = field(default_factory=time.time)
    device_id: str = "device_default"
    synced: bool = False

    def to_dict(self) -> Dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, data: Dict) -> 'Movement':
        return cls(
            id=data.get("id", str(uuid.uuid4())),
            business_id=data.get("business_id", "tienda_demo"),
            product_id=data["product_id"],
            product_name=data.get("product_name", ""),
            type=data["type"],
            quantity=float(data["quantity"]),
            unit=data.get("unit", "unidades"),
            timestamp=float(data.get("timestamp", time.time())),
            device_id=data.get("device_id", "device_demo"),
            synced=bool(data.get("synced", False))
        )

@dataclass
class StockItem:
    product_id: str
    product_name: str
    current_stock: float
    unit: str
    min_threshold: float
    needs_reorder: bool
    retail_price_cop: float
    wholesale_price_cop: float

@dataclass
class CollectiveOrderItem:
    business_id: str
    business_name: str
    zone: str  # Ej: "Comuna 2 Yopal"
    product_id: str
    product_name: str
    quantity: float
    unit: str
