//! Módulo de Autenticación Segura y Cumplimiento Ley 1581 de 2012 (Habeas Data) para Origo.
//! Implementa PBKDF2-HMAC-SHA256 (100.000 iteraciones) + compatibilidad con hash móvil offline (`sha256_iter2000:`).

use crate::models::{now_unix_secs, AuthResponse, PrivacyPolicy, PrivacyRoles, PublicUser};
use pbkdf2::pbkdf2_hmac;
use rand::RngCore;
use rusqlite::{params, Connection, OptionalExtension};
use sha2::{Digest, Sha256};
use std::sync::Mutex;
use subtle::ConstantTimeEq;

pub const PBKDF2_ITERATIONS: u32 = 100_000;
pub const SESSION_TTL_SECONDS: f64 = 7.0 * 24.0 * 3600.0;

pub fn hash_pin(pin: &str, salt_hex: Option<&str>) -> (String, String) {
    let salt_bytes: Vec<u8> = match salt_hex {
        Some(s) => hex::decode(s).unwrap_or_else(|_| random_bytes(16)),
        None => random_bytes(16),
    };
    let mut dk = [0u8; 32];
    pbkdf2_hmac::<Sha256>(pin.as_bytes(), &salt_bytes, PBKDF2_ITERATIONS, &mut dk);
    (hex::encode(&salt_bytes), hex::encode(dk))
}

pub fn hash_pin_mobile_sha256(pin: &str, salt_hex: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(format!("{salt_hex}:{pin}").as_bytes());
    let mut digest = hasher.finalize();
    let salt_bytes = salt_hex.as_bytes();
    for _ in 0..2000 {
        let mut h = Sha256::new();
        h.update(digest);
        h.update(salt_bytes);
        digest = h.finalize();
    }
    format!("sha256_iter2000:{}", hex::encode(digest))
}

pub fn verify_pin(pin: &str, salt_hex: &str, expected_hash_hex: &str) -> bool {
    let computed = if expected_hash_hex.starts_with("sha256_iter2000:") {
        hash_pin_mobile_sha256(pin, salt_hex)
    } else {
        let (_, h) = hash_pin(pin, Some(salt_hex));
        h
    };
    let a = computed.as_bytes();
    let b = expected_hash_hex.as_bytes();
    a.len() == b.len() && bool::from(a.ct_eq(b))
}

pub fn sanitize_phone(phone: &str) -> String {
    phone.chars().filter(|c| c.is_ascii_digit()).collect()
}

fn random_bytes(len: usize) -> Vec<u8> {
    let mut buf = vec![0u8; len];
    rand::thread_rng().fill_bytes(&mut buf);
    buf
}

fn random_token() -> String {
    hex::encode(random_bytes(32))
}

pub fn privacy_policy_ley_1581() -> PrivacyPolicy {
    PrivacyPolicy {
        title: "Aviso de Privacidad y Protección de Datos (Ley 1581 de 2012)".into(),
        summary: "En Origo aplicamos el principio de minimización de datos: solo solicitamos lo estrictamente necesario para operar tu inventario y compras colectivas (tu nombre, negocio, zona y celular). Nunca vendemos tus datos personales a terceros.".into(),
        roles: PrivacyRoles {
            responsable: "La MiPyme usuaria actúa como responsable de los datos de su negocio y de sus clientes.".into(),
            encargado: "La Dirección TIC de la Gobernación de Casanare y la plataforma Origo actúan como encargados del tratamiento técnico seguro.".into(),
        },
        rights: vec![
            "Conocer y consultar gratuitamente tus datos almacenados en cualquier momento.".into(),
            "Actualizar o corregir el nombre de tu negocio, zona o datos de contacto.".into(),
            "Revocar esta autorización y solicitar la eliminación de tu cuenta.".into(),
            "Tu clave/PIN se protege mediante cifrado unidireccional PBKDF2-SHA256 con sal única.".into(),
        ],
    }
}

pub struct AuthManager {
    conn: Mutex<Connection>,
}

impl AuthManager {
    pub fn open(db_path: &str) -> rusqlite::Result<Self> {
        let conn = if db_path == ":memory:" {
            Connection::open_in_memory()?
        } else {
            Connection::open(db_path)?
        };
        let mgr = Self {
            conn: Mutex::new(conn),
        };
        mgr.create_tables()?;
        mgr.seed_demo_account()?;
        Ok(mgr)
    }

    fn create_tables(&self) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        conn.execute_batch(
            "
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
            );
            CREATE TABLE IF NOT EXISTS sessions (
                token TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                created_at REAL NOT NULL,
                expires_at REAL NOT NULL,
                FOREIGN KEY (user_id) REFERENCES users(id)
            );
            ",
        )
    }

    pub fn seed_demo_account(&self) -> rusqlite::Result<()> {
        let conn = self.conn.lock().unwrap();
        let exists: Option<String> = conn
            .query_row(
                "SELECT id FROM users WHERE id = ?1",
                params!["tienda_demo"],
                |r| r.get(0),
            )
            .optional()?;
        if exists.is_some() {
            return Ok(());
        }
        let (salt_hex, hash_hex) = hash_pin("1234", None);
        let now = now_unix_secs();
        conn.execute(
            "INSERT INTO users
            (id, phone, owner_name, business_name, zone, role, pin_salt, pin_hash,
             habeas_data_accepted, habeas_data_timestamp, created_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            params![
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
            ],
        )?;
        Ok(())
    }

    fn create_session_locked(conn: &Connection, user_id: &str) -> rusqlite::Result<String> {
        let token = random_token();
        let now = now_unix_secs();
        conn.execute(
            "INSERT INTO sessions (token, user_id, created_at, expires_at) VALUES (?1, ?2, ?3, ?4)",
            params![token, user_id, now, now + SESSION_TTL_SECONDS],
        )?;
        Ok(token)
    }

    pub fn register_user(
        &self,
        phone: &str,
        pin: &str,
        owner_name: &str,
        business_name: &str,
        zone: &str,
        habeas_data_accepted: bool,
    ) -> Result<AuthResponse, String> {
        let clean_phone = sanitize_phone(phone);
        let clean_pin = pin.trim();
        let clean_owner = owner_name.trim();
        let clean_business = business_name.trim();
        let clean_zone = if zone.trim().is_empty() {
            "Comuna 2, Yopal"
        } else {
            zone.trim()
        };

        if !habeas_data_accepted {
            return Err(
                "Debes aceptar el Aviso de Privacidad (Ley 1581 de 2012) para continuar.".into(),
            );
        }
        if clean_owner.chars().count() < 2 || clean_owner.chars().count() > 60 {
            return Err("Escribe tu nombre (entre 2 y 60 caracteres).".into());
        }
        if clean_business.chars().count() < 2 || clean_business.chars().count() > 80 {
            return Err("Escribe el nombre de tu negocio (entre 2 y 80 caracteres).".into());
        }
        if clean_phone.len() < 7 || clean_phone.len() > 15 {
            return Err("Ingresa un número de celular válido (ej. 3101234567).".into());
        }
        if !(4..=6).contains(&clean_pin.len()) || !clean_pin.chars().all(|c| c.is_ascii_digit()) {
            return Err("Crea una clave sencilla de 4 a 6 números (ej. 1234).".into());
        }

        let conn = self.conn.lock().unwrap();
        let dup: Option<String> = conn
            .query_row(
                "SELECT id FROM users WHERE phone = ?1",
                params![clean_phone],
                |r| r.get(0),
            )
            .optional()
            .map_err(|e| e.to_string())?;

        if dup.is_some() {
            return Err(
                "Este número celular ya está registrado. Ingresa por la pestaña 'Entrar'.".into(),
            );
        }

        let user_id = format!("tienda_{}", hex::encode(random_bytes(4)));
        let (salt_hex, hash_hex) = hash_pin(clean_pin, None);
        let now = now_unix_secs();

        conn.execute(
            "INSERT INTO users
            (id, phone, owner_name, business_name, zone, role, pin_salt, pin_hash,
             habeas_data_accepted, habeas_data_timestamp, created_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            params![
                user_id,
                clean_phone,
                clean_owner,
                clean_business,
                clean_zone,
                "comerciante",
                salt_hex,
                hash_hex,
                1,
                now,
                now
            ],
        )
        .map_err(|e| e.to_string())?;

        let token = Self::create_session_locked(&conn, &user_id).map_err(|e| e.to_string())?;
        Ok(AuthResponse {
            token,
            user: PublicUser {
                id: user_id,
                phone: clean_phone,
                owner_name: clean_owner.to_string(),
                business_name: clean_business.to_string(),
                zone: clean_zone.to_string(),
                role: "comerciante".to_string(),
                habeas_data_accepted: true,
            },
        })
    }

    pub fn login(&self, phone: &str, pin: &str) -> Result<AuthResponse, String> {
        let clean_phone = sanitize_phone(phone);
        let clean_pin = pin.trim();
        if clean_phone.is_empty() || clean_pin.is_empty() {
            return Err("Ingresa tu número celular y tu clave.".into());
        }

        let conn = self.conn.lock().unwrap();
        let row: Option<(PublicUser, String, String)> = conn
            .query_row(
                "SELECT id, phone, owner_name, business_name, zone, role, habeas_data_accepted, pin_salt, pin_hash
                 FROM users WHERE phone = ?1",
                params![clean_phone],
                |r| {
                    let habeas: i64 = r.get(6)?;
                    Ok((
                        PublicUser {
                            id: r.get(0)?,
                            phone: r.get(1)?,
                            owner_name: r.get(2)?,
                            business_name: r.get(3)?,
                            zone: r.get(4)?,
                            role: r.get(5)?,
                            habeas_data_accepted: habeas != 0,
                        },
                        r.get::<_, String>(7)?,
                        r.get::<_, String>(8)?,
                    ))
                },
            )
            .optional()
            .map_err(|e| e.to_string())?;

        let (user, salt, hash) = match row {
            Some(v) => v,
            None => {
                return Err("Celular o clave incorrectos. Verifica e intenta de nuevo.".into());
            }
        };

        if !verify_pin(clean_pin, &salt, &hash) {
            return Err("Celular o clave incorrectos. Verifica e intenta de nuevo.".into());
        }

        let token = Self::create_session_locked(&conn, &user.id).map_err(|e| e.to_string())?;
        Ok(AuthResponse { token, user })
    }

    pub fn get_session_user(&self, token: Option<&str>) -> Option<PublicUser> {
        let tok = token?.trim();
        if tok.is_empty() {
            return None;
        }
        let conn = self.conn.lock().unwrap();
        let row: Option<(PublicUser, f64)> = conn
            .query_row(
                "SELECT u.id, u.phone, u.owner_name, u.business_name, u.zone, u.role, u.habeas_data_accepted, s.expires_at
                 FROM sessions s
                 JOIN users u ON u.id = s.user_id
                 WHERE s.token = ?1",
                params![tok],
                |r| {
                    let habeas: i64 = r.get(6)?;
                    Ok((
                        PublicUser {
                            id: r.get(0)?,
                            phone: r.get(1)?,
                            owner_name: r.get(2)?,
                            business_name: r.get(3)?,
                            zone: r.get(4)?,
                            role: r.get(5)?,
                            habeas_data_accepted: habeas != 0,
                        },
                        r.get::<_, f64>(7)?,
                    ))
                },
            )
            .optional()
            .ok()?;

        let (user, expires_at) = row?;
        if expires_at < now_unix_secs() {
            let _ = conn.execute("DELETE FROM sessions WHERE token = ?1", params![tok]);
            return None;
        }
        Some(user)
    }

    pub fn logout(&self, token: Option<&str>) {
        if let Some(tok) = token {
            let conn = self.conn.lock().unwrap();
            let _ = conn.execute("DELETE FROM sessions WHERE token = ?1", params![tok]);
        }
    }

    #[allow(clippy::too_many_arguments)]
    pub fn sync_offline_user(
        &self,
        user_id: &str,
        phone: &str,
        owner_name: &str,
        business_name: &str,
        zone: &str,
        pin_salt: &str,
        pin_hash: &str,
        habeas_data_accepted: bool,
        created_at: Option<f64>,
    ) -> rusqlite::Result<(String, &'static str)> {
        let clean_phone = sanitize_phone(phone);
        let mut ts = created_at.unwrap_or_else(now_unix_secs);
        if ts > 1e11 {
            ts /= 1000.0;
        }

        let conn = self.conn.lock().unwrap();
        let existing: Option<String> = conn
            .query_row(
                "SELECT id FROM users WHERE id = ?1 OR phone = ?2",
                params![user_id, clean_phone],
                |r| r.get(0),
            )
            .optional()?;

        if let Some(ex_id) = existing {
            return Ok((ex_id, "already_exists"));
        }

        let clean_zone = if zone.trim().is_empty() {
            "Comuna 2, Yopal"
        } else {
            zone.trim()
        };

        conn.execute(
            "INSERT INTO users
            (id, phone, owner_name, business_name, zone, role, pin_salt, pin_hash,
             habeas_data_accepted, habeas_data_timestamp, created_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)",
            params![
                user_id,
                clean_phone,
                owner_name.trim(),
                business_name.trim(),
                clean_zone,
                "comerciante",
                pin_salt,
                pin_hash,
                if habeas_data_accepted { 1 } else { 0 },
                ts,
                ts
            ],
        )?;
        Ok((user_id.to_string(), "created"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pbkdf2_unique_salt_and_verification() {
        let (s1, h1) = hash_pin("4567", None);
        let (s2, h2) = hash_pin("4567", None);
        assert_ne!(s1, s2);
        assert_ne!(h1, h2);
        assert!(verify_pin("4567", &s1, &h1));
        assert!(!verify_pin("0000", &s1, &h1));
    }

    #[test]
    fn test_register_requires_habeas_data() {
        let auth = AuthManager::open(":memory:").unwrap();
        let res = auth.register_user(
            "3209998877",
            "5678",
            "Doña Martha",
            "Agroinsumos Aguazul",
            "Centro, Aguazul",
            false,
        );
        assert!(res.is_err());
        assert!(res.unwrap_err().contains("Ley 1581"));
    }

    #[test]
    fn test_register_login_and_session_lifecycle() {
        let auth = AuthManager::open(":memory:").unwrap();
        let res = auth
            .register_user(
                "320-999-8877",
                "5678",
                "Doña Martha",
                "Agroinsumos Aguazul",
                "Centro, Aguazul",
                true,
            )
            .unwrap();
        assert_eq!(res.user.owner_name, "Doña Martha");
        assert_eq!(res.user.phone, "3209998877");

        let session_user = auth.get_session_user(Some(&res.token)).unwrap();
        assert_eq!(session_user.id, res.user.id);

        assert!(auth.login("3209998877", "5678").is_ok());
        assert!(auth.login("3209998877", "9999").is_err());

        auth.logout(Some(&res.token));
        assert!(auth.get_session_user(Some(&res.token)).is_none());
    }

    #[test]
    fn test_demo_account_and_offline_mobile_sync_login() {
        let auth = AuthManager::open(":memory:").unwrap();
        let demo = auth.login("3101234567", "1234").unwrap();
        assert_eq!(demo.user.id, "tienda_demo");
        assert_eq!(demo.user.owner_name, "Don Pedro");

        let salt = "0123456789abcdef0123456789abcdef";
        let mobile_hash = hash_pin_mobile_sha256("4321", salt);

        let (_, s1) = auth
            .sync_offline_user(
                "tienda_offline_1",
                "3158887766",
                "Doña Rosa",
                "Granero El Morichal",
                "Centro, Yopal",
                salt,
                &mobile_hash,
                true,
                Some(1_760_000_000_000.0),
            )
            .unwrap();
        assert_eq!(s1, "created");

        let (_, s2) = auth
            .sync_offline_user(
                "tienda_offline_1",
                "3158887766",
                "Doña Rosa",
                "Granero El Morichal",
                "Centro, Yopal",
                salt,
                &mobile_hash,
                true,
                None,
            )
            .unwrap();
        assert_eq!(s2, "already_exists");

        let web_login = auth.login("3158887766", "4321").unwrap();
        assert_eq!(web_login.user.id, "tienda_offline_1");
        assert_eq!(web_login.user.business_name, "Granero El Morichal");
    }
}
