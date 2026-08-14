#!/usr/bin/env bash
# TuringOne UI Community
# Copyright (C) 2026 TuringOne
# SPDX-License-Identifier: AGPL-3.0-only
# ═════════════════════════════════════════════════════════════════════════════
# TuringOne Community — Installation en un clic (Linux / macOS / Git Bash)
#
#   ./install.sh            installation complète (génère .env + démarre la stack)
#   ./install.sh --env-only génère uniquement le .env (pour inspection avant démarrage)
#
# Moteurs supportés : Docker (recommandé) ou Podman (voir notes dans README.md).
# Sous Windows, préférez PowerShell :  .\install.ps1
#
# Idempotent : un .env existant n'est JAMAIS écrasé (les secrets générés — dont
# la master key de chiffrement — doivent survivre aux réinstallations).
# ═════════════════════════════════════════════════════════════════════════════
set -euo pipefail

cd "$(dirname "$0")"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${BLUE}ℹ️  $*${NC}"; }
ok()    { echo -e "${GREEN}✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}⚠️  $*${NC}"; }
fail()  { echo -e "${RED}❌ $*${NC}"; exit 1; }

# ── Plateforme ───────────────────────────────────────────────────────────────
if [[ -n "${SUDO_USER:-}" ]]; then
    warn "Running through sudo: this is normally NOT required (Docker Desktop, or a"
    warn "user in the 'docker' group). Generated files are handed back to"
    warn "${SUDO_USER}, but prefer running ./install.sh without sudo."
fi

case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
        warn "Windows detected (Git Bash). This script can work, but Docker output"
        warn "renders badly in some terminals (MinTTY)."
        warn "👉 Recommended on Windows:  PowerShell →  .\\install.ps1"
        ;;
esac

# ── Moteur de conteneurs : Docker ou Podman ──────────────────────────────────
# ENGINE  : binaire pour inspect/info (docker | podman)
# COMPOSE : commande compose ("docker compose" | "podman compose")
ENGINE=""; COMPOSE=""
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    ENGINE="docker"; COMPOSE="docker compose"
    docker info >/dev/null 2>&1 || fail "The Docker daemon is not responding — start Docker (Desktop)"
elif command -v podman >/dev/null 2>&1; then
    podman info >/dev/null 2>&1 || fail "Podman is not responding (is the podman machine started?)"
    if podman compose version >/dev/null 2>&1; then
        ENGINE="podman"; COMPOSE="podman compose"
        warn "Podman detected. Works with the 'docker-compose' provider (recommended)."
        warn "The python 'podman-compose' provider handles 'depends_on: service_completed_successfully' badly:"
        warn "if the backend starts before the bootstrap finishes, re-run:  podman compose up -d"
    else
        fail "Podman found but 'podman compose' is unavailable — install docker-compose or podman-compose"
    fi
else
    fail "Neither Docker nor Podman found: https://docs.docker.com/get-docker/"
fi
info "Engine: ${ENGINE} (${COMPOSE})"

# ── Bits d'exécution des scripts montés ──────────────────────────────────────
# postgres/init/*.sh est monté dans /docker-entrypoint-initdb.d : l'image
# officielle PostgreSQL EXÉCUTE ces fichiers (elle ne les "source" pas toujours).
# Sans bit +x → exec échoue (code 126), l'init est abandonnée, le cluster reste
# vide et Keycloak boucle sur « role "keycloak" does not exist ».
# Les archives ZIP/tar perdent les permissions : on les rétablit à chaque run.
chmod +x postgres/init/*.sh 2>/dev/null || true

# ── Génération de secrets ────────────────────────────────────────────────────
gen_secret()   { openssl rand -hex 24; }                                    # 48 hex chars
gen_keyid()    { echo "turingone$(openssl rand -hex 8)"; }                  # access key id
gen_masterkey(){ openssl rand -base64 32 | tr '+/' '-_' | tr -d '\n'; }     # b64 url-safe 32o

set_var() {  # set_var NOM VALEUR — remplace la ligne NOM=... dans .env
    local name="$1" value="$2"
    # sed -i portable macOS/Linux
    sed -i.bak "s|^${name}=.*|${name}=${value}|" .env && rm -f .env.bak
}

if [[ -f .env ]]; then
    warn "Existing .env kept (secrets preserved). Delete it to start from scratch."
else
    info "Generating the .env file with random secrets…"
    cp .env.example .env

    DB_PASSWORD="$(gen_secret)"
    set_var POSTGRES_SUPERUSER_PASSWORD  "$(gen_secret)"
    set_var DATABASE_PASSWORD            "$DB_PASSWORD"
    set_var BILLING_DATABASE_PASSWORD    "$DB_PASSWORD"
    set_var KC_DB_PASSWORD               "$(gen_secret)"
    set_var KEYCLOAK_PASSWORD_ADMIN      "$(gen_secret)"
    set_var TURINGONE_ADMIN_PASSWORD     "$(gen_secret)"
    set_var RABBITMQ_PASSWORD            "$(gen_secret)"
    set_var S3_ACCESS_KEY                "$(gen_keyid)"
    set_var S3_SECRET_KEY                "$(gen_secret)"
    set_var TURINGONE_MASTER_KEY         "$(gen_masterkey)"

    chmod 600 .env
    # Sous sudo, .env appartiendrait à root en 600 → illisible pour l'utilisateur,
    # et tout 'docker compose' ultérieur échouerait sur « permission denied ».
    if [[ -n "${SUDO_USER:-}" ]]; then
        chown "$SUDO_USER" .env 2>/dev/null || true
    fi
    ok ".env generated (permissions 600)"
    warn "BACK UP this file: TURINGONE_MASTER_KEY is required to decrypt your data."
fi

if grep -q "CHANGE-ME" .env; then
    warn "Remember to set VLLM_API_KEY in .env (OpenAI key or local LLM server) —"
    warn "without it, the AI features will not respond."
fi

[[ "${1:-}" == "--env-only" ]] && { ok "The .env file is ready. Run: ${COMPOSE} up -d"; exit 0; }

# ── Étape 1/3 : telechargement des images (la partie LONGUE) ─────────────────────────
info "Step 1/3 — Downloading the images…"
info "  ⏳ The FIRST download is around 2 GB:"
info "     allow 5 to 15 min depending on your connection. Progress is shown below."
$COMPOSE pull || fail "Image download failed (see the output above)"
ok "Images downloaded"

# ── Étape 2/3 : démarrage de la stack ────────────────────────────────────────
info "Step 2/3 — Starting the services…"
# Ne pas mourir ici (set -e) : backend dépend du bootstrap, donc un échec de
# provisioning fait échouer 'up' — on veut alors afficher les logs bootstrap.
COMPOSE_RC=0
$COMPOSE up -d || COMPOSE_RC=$?

# ── Diagnostic : cluster PostgreSQL présent mais non initialisé ──────────────
# L'image PostgreSQL ne rejoue JAMAIS /docker-entrypoint-initdb.d sur un volume
# non vide. Si une installation précédente a échoué pendant l'init (script non
# exécutable, mot de passe manquant…), le volume pgdata existe sans les rôles ni
# les bases : Keycloak boucle indéfiniment et relancer install.sh n'y change rien.
if [[ "$COMPOSE_RC" != "0" ]]; then
    PG_CID="$($COMPOSE ps -q postgres 2>/dev/null || true)"
    if [[ -n "$PG_CID" ]] && ! $ENGINE exec "$PG_CID" \
            psql -U postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'keycloak'" \
            2>/dev/null | grep -q '^1$'; then
        echo
        warn "The PostgreSQL cluster exists but the 'keycloak' role is missing:"
        warn "initialisation (postgres/init/01-init-databases.sh) did not complete."
        warn "Init only runs once, on an EMPTY volume — it has to be recreated."
        warn "The commands below DELETE the existing PostgreSQL data"
        warn "(your .env and its master key are preserved):"
        echo "    ${COMPOSE} down"
        echo "    ${ENGINE} volume rm turingone-community_pgdata"
        echo "    ./install.sh"
        fail "Incomplete PostgreSQL initialisation — see above."
    fi
fi

# ── Étape 3/3 : provisioning automatique (bootstrap) ─────────────────────────
info "Step 3/3 — Automatic provisioning (databases, Keycloak, buckets)…"
BOOT_CID="$($COMPOSE ps -aq bootstrap 2>/dev/null || true)"
if [[ -z "$BOOT_CID" ]]; then
    fail "Bootstrap container not found — startup failed (code $COMPOSE_RC). Logs: ${COMPOSE} logs"
fi

# Logs du bootstrap en DIRECT pendant l'attente (arrière-plan, coupé à la fin)
$COMPOSE logs -f bootstrap 2>/dev/null &
LOGS_PID=$!

ELAPSED=0
while [[ "$($ENGINE inspect -f '{{.State.Running}}' "$BOOT_CID" 2>/dev/null)" == "true" ]]; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    # Battement de cœur discret toutes les 30 s si les logs sont silencieux
    if (( ELAPSED % 30 == 0 )); then
        info "…provisioning in progress (${ELAPSED}s) — services: $($COMPOSE ps --format '{{.Service}}={{.State}}' 2>/dev/null | tr '\n' ' ')"
    fi
done
kill "$LOGS_PID" >/dev/null 2>&1 || true
BOOT_EXIT="$($ENGINE inspect -f '{{.State.ExitCode}}' "$BOOT_CID" 2>/dev/null || echo 1)"

if [[ "$BOOT_EXIT" != "0" || "$COMPOSE_RC" != "0" ]]; then
    echo
    $COMPOSE logs bootstrap 2>/dev/null | tail -40
    fail "Bootstrap failed (see the logs above): ${COMPOSE} logs bootstrap"
fi

# ── Résumé ───────────────────────────────────────────────────────────────────
source <(grep -E '^(FRONTEND_URL|TURINGONE_ADMIN_USERNAME|TURINGONE_ADMIN_PASSWORD|KEYCLOAK_PUBLIC_URL|KEYCLOAK_USERNAME_ADMIN|KEYCLOAK_PASSWORD_ADMIN)=' .env | sed 's/^/export /')
echo
ok "TuringOne Community is installed! 🎉"
echo
echo    "   🌐 Application : ${FRONTEND_URL}"
echo    "   👤 Username    : ${TURINGONE_ADMIN_USERNAME}"
echo    "   🔑 Password    : ${TURINGONE_ADMIN_PASSWORD}"
echo
echo    "   🔐 Keycloak console (technical admin): ${KEYCLOAK_PUBLIC_URL}"
echo    "      ${KEYCLOAK_USERNAME_ADMIN} / ${KEYCLOAK_PASSWORD_ADMIN}"
echo
echo    "   These credentials are also stored in the .env file (permissions 600)."
echo
echo    "   First backend startup: it downloads the embedding models"
echo    "   (a few minutes). Follow with:  ${COMPOSE} logs -f backend"
echo
warn    "Back up the .env file (encryption master key) together with your backups!"
