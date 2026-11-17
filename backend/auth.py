"""
Módulo de Autenticación Segura y Cumplimiento Ley 1581 de 2012 (Habeas Data) para Origo.
Implementa hash criptográfico PBKDF2-HMAC-SHA256 con sal única por usuario y gestión de sesiones.
Cero dependencias externas (librería estándar de Python).
"""

import hashlib
import hmac
import re
import secrets
import sqlite3
import time
from typing import Dict, Any, Optional, Tuple


PBKDF2_ITERATIONS = 100_000
SESSION_TTL_SECONDS = 7 * 24 * 3600  # 7 días

PRIVACY_POLICY_LEY_1581 = {
    "title": "Aviso de Privacidad y Protección de Datos (Ley 1581 de 2012)",
    "summary": (
        "En Origo aplicamos el principio de minimización de datos: solo solicitamos lo estrictamente "
        "necesario para operar tu inventario y compras colectivas (tu nombre, negocio, zona y celular). "
        "Nunca vendemos tus datos personales a terceros."
    ),
    "roles": {
        "responsable": "La MiPyme usuaria actúa como responsable de los datos de su negocio y de sus clientes.",
        "encargado": "La Dirección TIC de la Gobernación de Casanare y la plataforma Origo actúan como encargados del tratamiento técnico seguro."
    },
    "rights": [
        "Conocer y consultar gratuitamente tus datos almacenados en cualquier momento.",
        "Actualizar o corregir el nombre de tu negocio, zona o datos de contacto.",
        "Revocar esta autorización y solicitar la eliminación de tu cuenta.",
        "Tu clave/PIN se protege mediante cifrado unidireccional PBKDF2-SHA256 con sal única."
    ]
}


def hash_pin(pin: str, salt_hex: Optional[str] = None) -> Tuple[str, str]:
    """Genera hash PBKDF2-HMAC-SHA256 con sal criptográfica única de 128 bits."""
    salt = bytes.fromhex(salt_hex) if salt_hex else secrets.token_bytes(16)
    dk = hashlib.pbkdf2_hmac("sha256", pin.encode("utf-8"), salt, PBKDF2_ITERATIONS)
    return salt.hex(), dk.hex()


def verify_pin(pin: str, salt_hex: str, expected_hash_hex: str) -> bool:
    """Verifica una clave/PIN en tiempo constante para evitar ataques de temporización."""
    _, computed_hash = hash_pin(pin, salt_hex)
    return hmac.compare_digest(computed_hash, expected_hash_hex)


def sanitize_phone(phone: str) -> str:
    """Conserva únicamente los dígitos del número celular."""
    return re.sub(r"\D+", "", (phone or "").strip())


class AuthManager:
    def __init__(self, db_path: str = ":memory:"):
        self.db_path = db_path
        self.conn = sqlite3.connect(self.db_path, check_same_thread=False)
        self.create_tables()
        self.seed_demo_account()

    def create_tables(self):
        with self.conn:
            self.conn.execute("""
                CREATE TABLE IF NOT EXISTS users (
                    id TEXT PRIMARY KEY,
                    phone TEXT UNIQUE NOT NULL,
                    owner_name TEXT NOT NULL,
                    business_name TEXT NOT NULL,
                    zone TEXT NOT NULL,
                    role TEXT NOT NULL DEFAULT 'comerciante',
                    pin_salt TEXT NOT NULL,
                    pin_hash TEXT NOT NULL,
                    habeas_data_accepted INTEGER NOT NULL,
                    habeas_data_timestamp REAL NOT NULL,
                    created_at REAL NOT NULL
                )
            """)
            self.conn.execute("""
                CREATE TABLE IF NOT EXISTS sessions (
                    token TEXT PRIMARY KEY,
                    user_id TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    expires_at REAL NOT NULL,
                    FOREIGN KEY (user_id) REFERENCES users(id)
                )
            """)

    def seed_demo_account(self):
        """Crea la cuenta de demostración (Don Pedro) si aún no existe."""
        cur = self.conn.cursor()
        cur.execute("SELECT id FROM users WHERE id = ?", ("tienda_demo",))
        if cur.fetchone():
            return
        salt_hex, hash_hex = hash_pin("1234")
        now = time.time()
        with self.conn:
            self.conn.execute("""
                INSERT INTO users
                (id, phone, owner_name, business_name, zone, role, pin_salt, pin_hash,
                 habeas_data_accepted, habeas_data_timestamp, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                "tienda_demo",
                "3101234567",
                "Don Pedro",
                "Tienda La Esperanza",
                "Comuna 2, Yopal",
                "comerciante",
                salt_hex,
                hash_hex,
                1,
                now,
                now
            ))

    def _create_session(self, user_id: str) -> str:
        token = secrets.token_urlsafe(32)
        now = time.time()
        with self.conn:
            self.conn.execute(
                "INSERT INTO sessions (token, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)",
                (token, user_id, now, now + SESSION_TTL_SECONDS)
            )
        return token

    @staticmethod
    def _row_to_public_user(row) -> Dict[str, Any]:
        return {
            "id": row[0],
            "phone": row[1],
            "owner_name": row[2],
            "business_name": row[3],
            "zone": row[4],
            "role": row[5],
            "habeas_data_accepted": bool(row[6])
        }

    def register_user(
        self,
        phone: str,
        pin: str,
        owner_name: str,
        business_name: str,
        zone: str,
        habeas_data_accepted: bool
    ) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
        clean_phone = sanitize_phone(phone)
        clean_pin = (pin or "").strip()
        clean_owner = (owner_name or "").strip()
        clean_business = (business_name or "").strip()
        clean_zone = (zone or "Comuna 2, Yopal").strip()

        # Validación estricta de entradas (Cap. 4.4 y 4.5 del Anteproyecto)
        if not habeas_data_accepted:
            return None, "Debes aceptar el Aviso de Privacidad (Ley 1581 de 2012) para continuar."
        if len(clean_owner) < 2 or len(clean_owner) > 60:
            return None, "Escribe tu nombre (entre 2 y 60 caracteres)."
        if len(clean_business) < 2 or len(clean_business) > 80:
            return None, "Escribe el nombre de tu negocio (entre 2 y 80 caracteres)."
        if len(clean_phone) < 7 or len(clean_phone) > 15:
            return None, "Ingresa un número de celular válido (ej. 3101234567)."
        if not re.match(r"^\d{4,6}$", clean_pin):
            return None, "Crea una clave sencilla de 4 a 6 números (ej. 1234)."

        cur = self.conn.cursor()
        cur.execute("SELECT id FROM users WHERE phone = ?", (clean_phone,))
        if cur.fetchone():
            return None, "Este número celular ya está registrado. Ingresa por la pestaña 'Entrar'."

        user_id = f"tienda_{secrets.token_hex(4)}"
        salt_hex, hash_hex = hash_pin(clean_pin)
        now = time.time()

        with self.conn:
            self.conn.execute("""
                INSERT INTO users
                (id, phone, owner_name, business_name, zone, role, pin_salt, pin_hash,
                 habeas_data_accepted, habeas_data_timestamp, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                user_id, clean_phone, clean_owner, clean_business, clean_zone,
                "comerciante", salt_hex, hash_hex, 1, now, now
            ))

        token = self._create_session(user_id)
        user = {
            "id": user_id,
            "phone": clean_phone,
            "owner_name": clean_owner,
            "business_name": clean_business,
            "zone": clean_zone,
            "role": "comerciante",
            "habeas_data_accepted": True
        }
        return {"token": token, "user": user}, None

    def login(self, phone: str, pin: str) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
        clean_phone = sanitize_phone(phone)
        clean_pin = (pin or "").strip()

        if not clean_phone or not clean_pin:
            return None, "Ingresa tu número celular y tu clave."

        cur = self.conn.cursor()
        cur.execute("""
            SELECT id, phone, owner_name, business_name, zone, role, habeas_data_accepted, pin_salt, pin_hash
            FROM users WHERE phone = ?
        """, (clean_phone,))
        row = cur.fetchone()
        if not row or not verify_pin(clean_pin, row[7], row[8]):
            return None, "Celular o clave incorrectos. Verifica e intenta de nuevo."

        token = self._create_session(row[0])
        return {"token": token, "user": self._row_to_public_user(row[:7])}, None

    def get_session_user(self, token: Optional[str]) -> Optional[Dict[str, Any]]:
        if not token:
            return None
        cur = self.conn.cursor()
        cur.execute("""
            SELECT u.id, u.phone, u.owner_name, u.business_name, u.zone, u.role, u.habeas_data_accepted, s.expires_at
            FROM sessions s
            JOIN users u ON u.id = s.user_id
            WHERE s.token = ?
        """, (token,))
        row = cur.fetchone()
        if not row:
            return None
        if row[7] < time.time():
            self.logout(token)
            return None
        return self._row_to_public_user(row[:7])

    def logout(self, token: Optional[str]):
        if not token:
            return
        with self.conn:
            self.conn.execute("DELETE FROM sessions WHERE token = ?", (token,))

    @staticmethod
    def get_privacy_policy() -> Dict[str, Any]:
        return PRIVACY_POLICY_LEY_1581
