#!/bin/bash
set -e

echo "Esperando a que PostgreSQL esté listo..."
# Wait for PostgreSQL to be ready
until pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"; do
  echo "Esperando PostgreSQL..."
  sleep 1
done

echo "Iniciando configuración de base de datos PostgreSQL con extensiones..."

# Create extensions first
echo "Instalando extensiones..."
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Enable core extensions
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
    CREATE EXTENSION IF NOT EXISTS postgis;
    CREATE EXTENSION IF NOT EXISTS pgjwt CASCADE;
    CREATE EXTENSION IF NOT EXISTS pgaudit;
    CREATE EXTENSION IF NOT EXISTS pg_cron;
    CREATE EXTENSION IF NOT EXISTS hypopg;
    CREATE EXTENSION IF NOT EXISTS index_advisor;
    CREATE EXTENSION IF NOT EXISTS pg_stat_monitor;
    CREATE EXTENSION IF NOT EXISTS pg_hashids;
    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
    CREATE EXTENSION IF NOT EXISTS vector;
    CREATE EXTENSION IF NOT EXISTS plpython3u;
    CREATE EXTENSION IF NOT EXISTS timescaledb;
    CREATE EXTENSION IF NOT EXISTS ai;
    
    -- Verificar que todas las extensiones se hayan cargado correctamente
    SELECT extname, extversion FROM pg_extension;
EOSQL

# Create tablespace for indexes if path is provided
if [ -n "${INDEX_TABLESPACE_PATH:-}" ]; then
  echo "Creando tablespace optimizado para índices..."
  # Ensure directory exists and has proper permissions
  mkdir -p "${INDEX_TABLESPACE_PATH}"
#  chown -R postgres:postgres "${INDEX_TABLESPACE_PATH}"
#  chmod 700 "${INDEX_TABLESPACE_PATH}"
  
  # Check if tablespace exists
  TABLESPACE_EXISTS=$(psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -t -c "SELECT COUNT(*) FROM pg_tablespace WHERE spcname = 'index_space'")
  
  # Create tablespace if it doesn't exist
  if [ "$TABLESPACE_EXISTS" = "0" ]; then
    psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c "CREATE TABLESPACE index_space LOCATION '${INDEX_TABLESPACE_PATH}';"
    echo "Tablespace index_space creado exitosamente"
  else
    echo "Tablespace index_space ya existe, no se creará nuevamente"
  fi
fi

# Create monitoring schema
echo "Configurando esquema de monitoreo..."
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE SCHEMA IF NOT EXISTS monitoring;
    
    -- Crear tablas para almacenar métricas históricas
    CREATE TABLE IF NOT EXISTS monitoring.query_stats_hourly (
      collected_at TIMESTAMP WITH TIME ZONE NOT NULL,
      query_id BIGINT NOT NULL,
      calls BIGINT,
      total_time DOUBLE PRECISION,
      mean_time DOUBLE PRECISION,
      query TEXT,
      PRIMARY KEY (collected_at, query_id)
    );
    
    -- Crear función para snapshot periódico
    CREATE OR REPLACE FUNCTION monitoring.collect_query_stats() RETURNS VOID AS \$\$
    BEGIN
      INSERT INTO monitoring.query_stats_hourly
      SELECT 
        date_trunc('hour', now()) AS collected_at,
        queryid AS query_id,
        calls,
        total_time,
        mean_time,
        query
      FROM pg_stat_statements
      WHERE calls > 10
      ON CONFLICT (collected_at, query_id) DO UPDATE
      SET calls = EXCLUDED.calls,
          total_time = EXCLUDED.total_time,
          mean_time = EXCLUDED.mean_time;
    END;
    \$\$ LANGUAGE plpgsql;
    
    -- Configurar pg_cron para recopilar datos periódicamente
    SELECT cron.schedule('0 * * * *', 'SELECT monitoring.collect_query_stats()');
EOSQL

# Create readonly role if specified
if [ "${CREATE_READONLY_ROLE:-false}" = "true" ]; then
  echo "Creando rol de solo lectura..."
  psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    DO \$\$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'readonly') THEN
        CREATE ROLE readonly;
        GRANT CONNECT ON DATABASE "$POSTGRES_DB" TO readonly;
        GRANT USAGE ON SCHEMA public TO readonly;
        GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly;
        ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO readonly;
      ELSE
        RAISE NOTICE 'Rol readonly ya existe, no se creará nuevamente';
      END IF;
    END
    \$\$;
EOSQL
fi

# Create pgvector test table and index
echo "Configurando índices para pgvector..."
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    -- Crear índice de prueba para verificar pgvector
    CREATE TABLE IF NOT EXISTS vector_test (
        id SERIAL PRIMARY KEY,
        embedding VECTOR(3)
    );
    
    -- Insertar algunos vectores de prueba
    INSERT INTO vector_test (embedding) VALUES 
        ('[1,2,3]'), 
        ('[4,5,6]'), 
        ('[7,8,9]')
    ON CONFLICT DO NOTHING;
    
    -- Crear índice de ejemplo
    CREATE INDEX IF NOT EXISTS vector_test_idx ON vector_test USING ivfflat (embedding vector_l2_ops);
EOSQL

echo "Configuración de base de datos completada exitosamente."