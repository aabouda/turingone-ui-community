#!/bin/bash
# ═════════════════════════════════════════════════════════════════════════════
# TuringOne Community — Initialisation PostgreSQL
#
# Exécuté UNE SEULE FOIS par l'image officielle postgres/pgvector, au premier
# démarrage (volume vide), en tant que superutilisateur "postgres".
#
# Principe de moindre privilège :
#   - rôle "keycloak"        → base keycloak uniquement
#   - rôle applicatif        → bases billing + tenant (propriétaire, pas superuser)
#   - superuser "postgres"   → jamais utilisé par l'application, jamais exposé
#
# L'extension pgvector nécessite un superuser : elle est créée ICI, une fois,
# pour que ni le backend ni le bootstrap n'aient besoin de droits élevés.
# ═════════════════════════════════════════════════════════════════════════════
set -euo pipefail

APP_DB_USER="${APP_DB_USER:-turingone}"
TENANT_NAME="${TENANT_NAME:-community}"
BILLING_DATABASE_NAME="${BILLING_DATABASE_NAME:-turingone}"

echo "🔧 Init TuringOne : user=${APP_DB_USER} tenant=${TENANT_NAME} billing=${BILLING_DATABASE_NAME}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL
    -- Rôle Keycloak (accès limité à sa base)
    CREATE ROLE keycloak LOGIN PASSWORD '${KC_DB_PASSWORD}';
    CREATE DATABASE keycloak OWNER keycloak;

    -- Rôle applicatif TuringOne (propriétaire des bases métier, non superuser)
    CREATE ROLE ${APP_DB_USER} LOGIN PASSWORD '${APP_DB_PASSWORD}';

    -- Base billing (tenants, licences, quotas IA)
    CREATE DATABASE ${BILLING_DATABASE_NAME} OWNER ${APP_DB_USER};

    -- Base tenant (projets, exigences, cas de test, embeddings pgvector…)
    CREATE DATABASE ${TENANT_NAME} OWNER ${APP_DB_USER};
EOSQL

# Extension pgvector dans la base tenant (superuser requis)
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "${TENANT_NAME}" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL

echo "✅ Bases TuringOne initialisées (keycloak, ${BILLING_DATABASE_NAME}, ${TENANT_NAME} + pgvector)"
