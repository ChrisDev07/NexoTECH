//! Módulo de Seguridad y Controles OWASP para Origo (CREATIC Casanare).
//! Cumple con las directrices OWASP Top 10 (Web/API) y OWASP Mobile Top 10:
//! - A01: Control estricto de acceso (Anti-IDOR y aislamiento por business_id).
//! - A02: Mitigación de fallos criptográficos (PBKDF2 100k, tokens de alta entropía, defensas contra timing attacks).
//! - A03: Validación estricta de entradas y parámetros numéricos (Prevención de inyecciones y datos corruptos).
//! - A04: Limitación de tasa (Rate Limiting contra ataques de fuerza bruta y denegación de servicio).
//! - A05: Cabeceras de seguridad HTTP (CSP, HSTS, X-Frame-Options, nosniff, Permissions-Policy).
//! - A07: Prevención de enumeración de usuarios y protección de sesiones.
//! - A09: Registro y auditoría de eventos de seguridad sin fuga de PII (enmascaramiento).

use axum::{
    extract::Request,
    http::{header, HeaderName, HeaderValue},
    middleware::Next,
    response::Response,
};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

/// Limitador de tasa en memoria por ventana deslizante (OWASP A04 / ASVS 2.2).
#[derive(Debug, Clone)]
pub struct RateLimiter {
    records: Arc<Mutex<HashMap<String, (u32, Instant)>>>,
    max_requests: u32,
    window: Duration,
}

impl RateLimiter {
    pub fn new(max_requests: u32, window_secs: u64) -> Self {
        Self {
            records: Arc::new(Mutex::new(HashMap::new())),
            max_requests,
            window: Duration::from_secs(window_secs),
        }
    }

    /// Comprueba si la clave ha excedido el límite.
    /// Si excede, retorna `Err(segundos_a_esperar)`.
    /// Si es válido, incrementa el contador y retorna `Ok(())`.
    pub fn check_and_inc(&self, key: &str) -> Result<(), u64> {
        let mut map = self.records.lock().unwrap();
        let now = Instant::now();

        // Limpieza periódica si el número de claves activas supera 1000
        if map.len() > 1000 {
            map.retain(|_, (_, start)| now.duration_since(*start) < self.window);
        }

        if let Some((count, start)) = map.get_mut(key) {
            let elapsed = now.duration_since(*start);
            if elapsed >= self.window {
                *count = 1;
                *start = now;
                Ok(())
            } else if *count >= self.max_requests {
                let wait_secs = self.window.saturating_sub(elapsed).as_secs().max(1);
                Err(wait_secs)
            } else {
                *count += 1;
                Ok(())
            }
        } else {
            map.insert(key.to_string(), (1, now));
            Ok(())
        }
    }

    /// Reinicia el contador de una clave (ej. tras login exitoso).
    pub fn reset(&self, key: &str) {
        let mut map = self.records.lock().unwrap();
        map.remove(key);
    }
}

/// Middleware que inyecta cabeceras de seguridad estrictas según OWASP Secure Headers (OWASP A05).
pub async fn security_headers_middleware(req: Request, next: Next) -> Response {
    let mut response = next.run(req).await;
    let headers = response.headers_mut();

    // Anti-Clickjacking: previene que la aplicación sea embebida en iframes maliciosos
    headers.insert(header::X_FRAME_OPTIONS, HeaderValue::from_static("DENY"));

    // Anti-MIME Sniffing: fuerza al navegador a respetar los Content-Types declarados
    headers.insert(
        header::X_CONTENT_TYPE_OPTIONS,
        HeaderValue::from_static("nosniff"),
    );

    // HSTS: fuerza el uso exclusivo de canales cifrados HTTPS / TLS
    headers.insert(
        header::STRICT_TRANSPORT_SECURITY,
        HeaderValue::from_static("max-age=31536000; includeSubDomains"),
    );

    // Referrer Policy: evita fuga de rutas internas hacia dominios externos
    headers.insert(
        header::REFERRER_POLICY,
        HeaderValue::from_static("strict-origin-when-cross-origin"),
    );

    // Content Security Policy (CSP): restringe ejecución de scripts, estilos y fuentes
    headers.insert(
        header::CONTENT_SECURITY_POLICY,
        HeaderValue::from_static(
            "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; form-action 'self'",
        ),
    );

    // Permissions Policy: restringe acceso a hardware sensible
    headers.insert(
        HeaderName::from_static("permissions-policy"),
        HeaderValue::from_static("camera=(), microphone=(self), geolocation=()"),
    );

    // Cross-Domain Policy
    headers.insert(
        HeaderName::from_static("x-permitted-cross-domain-policies"),
        HeaderValue::from_static("none"),
    );

    response
}

/// Valida estrictamente cantidades de movimiento (OWASP A03 / Mobile M4).
pub fn validate_movement_quantity(qty: f64) -> Result<(), &'static str> {
    if qty.is_nan() || qty.is_infinite() {
        return Err("La cantidad no puede ser NaN o infinita");
    }
    if qty <= 0.0 {
        return Err("La cantidad debe ser estrictamente mayor a cero");
    }
    if qty > 100_000.0 {
        return Err("La cantidad excede el límite operativo máximo permitido (100,000)");
    }
    Ok(())
}

/// Enmascara números telefónicos en logs de auditoría para evitar fuga de PII (OWASP A09 / Ley 1581).
pub fn mask_phone(phone: &str) -> String {
    let clean = phone.trim();
    if clean.len() >= 6 {
        let start = &clean[..3];
        let end = &clean[clean.len() - 3..];
        format!("{}****{}", start, end)
    } else {
        "***".to_string()
    }
}

/// Enmascara tokens de sesión para logs de depuración seguros.
pub fn mask_token(token: &str) -> String {
    let clean = token.trim();
    if clean.len() >= 8 {
        format!("{}...{}", &clean[..4], &clean[clean.len() - 4..])
    } else {
        "***".to_string()
    }
}

/// Registra eventos de seguridad de forma estructurada sin exponer secretos ni contraseñas.
pub fn log_security_event(event_type: &str, actor: &str, details: &str, success: bool) {
    let ts = chrono::Utc::now().to_rfc3339();
    let status_str = if success { "SUCCESS" } else { "FAILED" };
    println!(
        "🛡️ [OWASP AUDIT {}] event={} actor={} status={} details=\"{}\"",
        ts, event_type, actor, status_str, details
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rate_limiter_blocks_and_resets() {
        let limiter = RateLimiter::new(3, 10);
        let key = "3101112233";

        assert!(limiter.check_and_inc(key).is_ok());
        assert!(limiter.check_and_inc(key).is_ok());
        assert!(limiter.check_and_inc(key).is_ok());

        // El 4to intento debe ser bloqueado
        let err = limiter.check_and_inc(key);
        assert!(err.is_err());
        assert!(err.unwrap_err() <= 10);

        // Tras resetear, debe permitir nuevamente
        limiter.reset(key);
        assert!(limiter.check_and_inc(key).is_ok());
    }

    #[test]
    fn test_quantity_validation() {
        assert!(validate_movement_quantity(5.0).is_ok());
        assert!(validate_movement_quantity(0.5).is_ok());
        assert!(validate_movement_quantity(100_000.0).is_ok());

        assert!(validate_movement_quantity(0.0).is_err());
        assert!(validate_movement_quantity(-1.0).is_err());
        assert!(validate_movement_quantity(f64::NAN).is_err());
        assert!(validate_movement_quantity(f64::INFINITY).is_err());
        assert!(validate_movement_quantity(100_001.0).is_err());
    }

    #[test]
    fn test_masking_pii() {
        assert_eq!(mask_phone("3101234567"), "310****567");
        assert_eq!(mask_phone("123"), "***");
        assert_eq!(mask_token("abcdef1234567890"), "abcd...7890");
    }
}
