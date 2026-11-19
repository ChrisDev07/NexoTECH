# ==============================================================================
# ORIGO Backend - Dockerfile Multi-Stage de Producción (Rust + Axum)
# Equipo NexoTECH · CREATIC Casanare
# Genera un binario ultraligero y seguro ejecutado por usuario no-root.
# ==============================================================================

# --- Etapa 1: Compilación ---
FROM rust:1.80-slim-bookworm AS builder

WORKDIR /build

# Dependencias de compilación
RUN apt-get update && apt-get install -y --no-install-recommends \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copiar manifiestos y código fuente
COPY Cargo.toml Cargo.lock ./
COPY src ./src

# Compilar en modo Release con optimizaciones máximas
RUN cargo build --release

# --- Etapa 2: Imagen Final Mínima de Ejecución ---
FROM debian:bookworm-slim AS runner

WORKDIR /app

# Instalar certificados CA para llamadas HTTPS salientes y librerías runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    libssl3 \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Crear usuario y grupo de sistema sin privilegios de root (OWASP A05)
RUN groupadd -r origo && useradd -r -g origo -d /app -s /sbin/nologin origo

# Crear directorio de datos persistentes con permisos adecuados
RUN mkdir -p /app/data /app/static && chown -R origo:origo /app

# Copiar el binario compilado y archivos estáticos
COPY --from=builder /build/target/release/origo-server /app/origo-server
COPY static /app/static

USER origo:origo

ENV PORT=8000
ENV ORIGO_DB_PATH=/app/data/origo_data.db
ENV ORIGO_STATIC_DIR=/app/static

EXPOSE 8000

VOLUME ["/app/data"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8000/api/health || exit 1

ENTRYPOINT ["/app/origo-server"]
CMD ["8000"]
