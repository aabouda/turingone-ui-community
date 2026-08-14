#!/usr/bin/env python3
# ═════════════════════════════════════════════════════════════════════════════
# TuringOne Community — Bootstrap de la plateforme (one-shot, idempotent)
#
# Lancé par le service docker-compose "bootstrap" AVANT le backend, avec
# l'image backend (mêmes dépendances/modèles). Relançable sans danger :
# chaque étape vérifie l'existant avant de créer.
#
# Étapes :
#   1. Attente de PostgreSQL, Keycloak et MinIO (healthchecks applicatifs)
#   2. Schéma base TENANT   : create_all + migrations colonnes + ai_points_events
#   3. Schéma base BILLING  : create_all + new_client.sql + seed plan community
#   4. Provisioning tenant + licence (plan community) + compteur LLM legacy
#   5. Lien tenant_link.UUU (base tenant ↔ billing) — critique pour les quotas
#   6. Buckets MinIO (S3_BUCKET + bucket au nom du tenant)
#   7. Keycloak : realm, clients OIDC, rôle admin, utilisateur administrateur
#
# Réplique la spécification de backend/tenant-onboarding/onboard_tenant.sh
# (étapes 8-22) sans dump template ni interaction, adaptée au mono-tenant.
# ═════════════════════════════════════════════════════════════════════════════
import json
import logging
import os
import sys
import time

sys.path.insert(0, "/app")  # code backend (settings, app.*)

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] bootstrap - %(message)s")
log = logging.getLogger("bootstrap")

# ── Paramètres (fournis par .env via docker-compose) ─────────────────────────
TENANT_NAME          = os.environ.get("TENANT_NAME", "community").lower()
TENANT_DISPLAY_NAME  = os.environ.get("TENANT_DISPLAY_NAME", "TuringOne Community")
TENANT_CONTACT_EMAIL = os.environ.get("TENANT_CONTACT_EMAIL", "admin@example.com")
PLAN_KEY             = os.environ.get("COMMUNITY_PLAN_KEY", "community")
FRONTEND_URL         = os.environ.get("FRONTEND_URL", "http://community.localhost:5173").rstrip("/")
ADMIN_USERNAME       = os.environ.get("TURINGONE_ADMIN_USERNAME", "admin")
ADMIN_PASSWORD       = os.environ.get("TURINGONE_ADMIN_PASSWORD", "")
LOGIN_THEME          = os.environ.get("LOGIN_THEME", "turingone")
WAIT_TIMEOUT         = int(os.environ.get("BOOTSTRAP_WAIT_TIMEOUT", "300"))


def fail(msg: str) -> None:
    log.error("❌ %s", msg)
    sys.exit(1)


def wait_for(name: str, probe, timeout: int = WAIT_TIMEOUT) -> None:
    """Boucle d'attente générique : probe() doit retourner True."""
    log.info("⏳ Attente de %s (max %ss)…", name, timeout)
    deadline = time.time() + timeout
    last_err = None
    while time.time() < deadline:
        try:
            if probe():
                log.info("✅ %s est prêt", name)
                return
        except Exception as exc:  # noqa: BLE001 — on veut retenter quoi qu'il arrive
            last_err = exc
        time.sleep(3)
    fail(f"{name} indisponible après {timeout}s (dernière erreur : {last_err})")


# ─────────────────────────────────────────────────────────────────────────────
# 1. Attente des services
# ─────────────────────────────────────────────────────────────────────────────
def wait_services() -> None:
    import psycopg2
    import requests

    def pg_ok() -> bool:
        conn = psycopg2.connect(
            host=os.environ["DATABASE_HOST"],
            port=int(os.environ.get("DATABASE_PORT", "5432")),
            user=os.environ["DATABASE_USER"],
            password=os.environ["DATABASE_PASSWORD"],
            dbname=os.environ["BILLING_DATABASE_NAME"],
            connect_timeout=3,
        )
        conn.close()
        return True

    def kc_ok() -> bool:
        r = requests.get(f"{os.environ['KEYCLOAK_SERVER']}/realms/master", timeout=5)
        return r.status_code == 200

    def minio_ok() -> bool:
        r = requests.get(f"{os.environ['S3_ENDPOINT']}/minio/health/live", timeout=5)
        return r.status_code == 200

    wait_for("PostgreSQL (billing DB)", pg_ok)
    wait_for("Keycloak", kc_ok)
    wait_for("MinIO", minio_ok)


# ─────────────────────────────────────────────────────────────────────────────
# 2. Schéma de la base TENANT
# ─────────────────────────────────────────────────────────────────────────────
def run_sql_file(engine, path: str) -> None:
    """Exécute un fichier SQL (contenant BEGIN/COMMIT) en autocommit psycopg2."""
    if not os.path.exists(path):
        log.warning("Fichier SQL absent, ignoré : %s", path)
        return
    with open(path, encoding="utf-8") as fh:
        sql = fh.read()
    raw = engine.raw_connection()
    try:
        # L'autocommit doit être posé sur la connexion DBAPI (psycopg2) —
        # l'attribut sur le proxy SQLAlchemy (_ConnectionFairy) serait un no-op
        # silencieux et le script dépendrait de son propre COMMIT final.
        raw.dbapi_connection.autocommit = True
        with raw.cursor() as cur:
            cur.execute(sql)
    finally:
        raw.close()
    log.info("   SQL appliqué : %s", os.path.basename(path))


# Migrations réservées à la base BILLING — elles portent l'avertissement
# « Run ONCE against the BILLING database (not the tenant DBs) ».
BILLING_ONLY_MIGRATIONS = {
    "new_client.sql",
    "billing_v2_ai_points.sql",
}


def run_tenant_migrations(engine, directory: str = "/app/migrations") -> None:
    """
    Applique TOUTES les migrations SQL de la base tenant, par ordre alphabétique.

    Pourquoi c'est nécessaire : Base.metadata.create_all() crée les tables à
    partir des modèles SQLAlchemy, mais ne reproduit ni les valeurs par défaut,
    ni les contraintes CHECK, ni les conversions json→jsonb, ni les index
    déclarés uniquement en SQL. Le schéma obtenu divergeait donc de celui d'une
    installation ayant reçu ces migrations au fil du temps.

    Chaque fichier est idempotent (IF NOT EXISTS / DROP ... IF EXISTS) : la
    fonction est rejouable à chaque démarrage sans effet de bord.

    Un fichier en échec n'interrompt pas le bootstrap : il est journalisé et la
    boucle continue. Une migration écrite pour un schéma plus ancien ne doit pas
    empêcher la plateforme de démarrer.
    """
    if not os.path.isdir(directory):
        log.warning("Dossier de migrations absent : %s", directory)
        return

    files = sorted(
        name for name in os.listdir(directory)
        if name.endswith(".sql") and name not in BILLING_ONLY_MIGRATIONS
    )
    if not files:
        log.warning("Aucune migration tenant trouvée dans %s", directory)
        return

    log.info("🏗️  Base tenant : application de %d migration(s) SQL…", len(files))

    failed = []
    for name in files:
        try:
            run_sql_file(engine, os.path.join(directory, name))
        except Exception as exc:  # noqa: BLE001 — non bloquant, voir docstring
            first_line = str(exc).splitlines()[0][:180]
            failed.append((name, first_line))

    if failed:
        log.warning(
            "%d migration(s) non appliquée(s) — le schéma peut être incomplet :",
            len(failed),
        )
        for name, err in failed:
            log.warning("   • %s → %s", name, err)
    log.info("✅ Migrations tenant : %d appliquée(s), %d en échec",
             len(files) - len(failed), len(failed))


def import_all_models() -> None:
    """
    Importe TOUS les modules de modèles pour peupler Base.metadata.

    app/models/__init__.py n'importe qu'une partie des modèles (56/109) : un
    simple `import app.models` laisserait de côté tenant_link, user_action_logs,
    ui_global_variables, dataset_files… et create_all produirait un schéma
    incomplet. Au runtime, ce sont les imports des routers qui complètent le
    metadata — le bootstrap doit faire l'équivalent explicitement.
    """
    import importlib
    import pkgutil
    import app.models

    failures = []
    for mod in pkgutil.walk_packages(app.models.__path__, prefix="app.models."):
        try:
            importlib.import_module(mod.name)
        except Exception as exc:  # noqa: BLE001 — modèle legacy non bloquant
            failures.append((mod.name, str(exc).splitlines()[0][:120]))
    for name, err in failures:
        log.warning("Modèle non importable (table absente du schéma) : %s → %s", name, err)
    log.info("Modèles importés pour create_all (%d modules ignorés)", len(failures))


def ensure_tenant_schema():
    from sqlalchemy import create_engine, inspect, text

    import_all_models()  # peuple Base.metadata AVANT create_all (voir docstring)
    from app.database import Base, _run_column_migrations, get_database_url

    engine = create_engine(get_database_url(TENANT_NAME))

    with engine.connect() as conn:
        has_vector = conn.execute(
            text("SELECT 1 FROM pg_extension WHERE extname = 'vector'")
        ).scalar()
    if not has_vector:
        fail(
            f"L'extension pgvector est absente de la base '{TENANT_NAME}'. "
            "Le volume PostgreSQL date-t-il d'une ancienne installation ? "
            "Exécutez CREATE EXTENSION vector; en superuser, ou repartez d'un volume vide."
        )

    log.info("🏗️  Base tenant '%s' : création du schéma (create_all, %d tables déclarées)…",
             TENANT_NAME, len(Base.metadata.tables))
    Base.metadata.create_all(bind=engine, checkfirst=True)
    log.info("🏗️  Base tenant '%s' : migrations de colonnes…", TENANT_NAME)
    _run_column_migrations(engine)
    run_tenant_migrations(engine)

    # Tables sans lesquelles la plateforme ne fonctionne pas : échec franc ici
    # plutôt que des 500 incompréhensibles au premier appel API.
    critical = {"projects", "tenant_link", "user_action_logs", "ui_global_variables"}
    existing = set(inspect(engine).get_table_names())
    missing = sorted(critical - existing)
    if missing:
        fail(f"Tables critiques absentes après create_all : {missing} — "
             "voir les warnings d'import de modèles ci-dessus.")

    log.info("✅ Schéma tenant prêt (%d tables)", len(existing))
    return engine


# ─────────────────────────────────────────────────────────────────────────────
# 3. Schéma de la base BILLING + seed des plans
# ─────────────────────────────────────────────────────────────────────────────
def ensure_billing_schema():
    from sqlalchemy import text
    # L'import crée l'engine billing et la table platform_news
    from app.billing_db import engine as billing_engine, BillingBase
    import app.models.billing  # noqa: F401 — enregistre les modèles billing

    log.info("🏗️  Base billing : création du schéma (create_all)…")
    BillingBase.metadata.create_all(bind=billing_engine, checkfirst=True)
    # Colonnes/index/plans additionnels + seed des plans commerciaux
    run_sql_file(billing_engine, "/app/migrations/new_client.sql")

    # Seed/refresh du plan community depuis la config YAML (source de vérité)
    from app.constants.ai_points_costs import PLAN_DEFINITIONS
    plan = PLAN_DEFINITIONS.get(PLAN_KEY)
    if not plan:
        fail(f"Plan '{PLAN_KEY}' introuvable dans config/ai_points_config.yaml")
    with billing_engine.begin() as conn:
        conn.execute(
            text("""
                INSERT INTO license_plans
                    (plan_key, label, ai_points_per_month, max_users, max_projects,
                     price_eur, billing_cycle_days, features, is_public)
                VALUES
                    (:k, :label, :pts, :users, :projects, :price, :cycle,
                     CAST(:features AS jsonb), TRUE)
                ON CONFLICT (plan_key) DO UPDATE SET
                    label               = EXCLUDED.label,
                    ai_points_per_month = EXCLUDED.ai_points_per_month,
                    max_users           = EXCLUDED.max_users,
                    max_projects        = EXCLUDED.max_projects,
                    price_eur           = EXCLUDED.price_eur,
                    updated_at          = NOW()
            """),
            {
                "k": PLAN_KEY,
                "label": plan["label"],
                "pts": plan["ai_points_per_month"],
                "users": plan["max_users"],
                "projects": plan["max_projects"],
                "price": plan["price_eur"],
                "cycle": plan["billing_cycle_days"],
                "features": json.dumps(plan.get("features", [])),
            },
        )
    log.info("✅ Schéma billing prêt (plan '%s' seedé)", PLAN_KEY)
    return billing_engine


# ─────────────────────────────────────────────────────────────────────────────
# 4. Tenant + licence + compteur LLM legacy
# ─────────────────────────────────────────────────────────────────────────────
def provision_tenant(billing_engine) -> str:
    from sqlalchemy import text
    from app.billing_db import SessionLocal
    from app.services.license_service import LicenseService

    db = SessionLocal()
    try:
        existing = db.execute(
            text("SELECT id FROM tenants WHERE name = :n"), {"n": TENANT_NAME}
        ).scalar()
        if existing:
            tenant_id = str(existing)
            log.info("ℹ️  Tenant '%s' déjà provisionné (id=%s)", TENANT_NAME, tenant_id)
        else:
            result = LicenseService(db).provision_tenant(
                realm_name=TENANT_NAME,
                display_name=TENANT_DISPLAY_NAME,
                contact_email=TENANT_CONTACT_EMAIL,
                plan_key=PLAN_KEY,
            )
            tenant_id = str(result["tenant"]["id"])
            log.info("✅ Tenant '%s' provisionné (plan %s, id=%s)", TENANT_NAME, PLAN_KEY, tenant_id)

        # Compteur legacy llm_usage_counters (utilisé par QuotaService) —
        # même logique que l'étape 12 de onboard_tenant.sh.
        lic = db.execute(
            text("""SELECT id, ai_points_per_month, billing_cycle_days
                    FROM licenses WHERE tenant_id = CAST(:t AS uuid) AND is_active
                    ORDER BY created_at DESC LIMIT 1"""),
            {"t": tenant_id},
        ).first()
        if lic:
            has_counter = db.execute(
                text("SELECT 1 FROM llm_usage_counters WHERE tenant_id = CAST(:t AS uuid) LIMIT 1"),
                {"t": tenant_id},
            ).scalar()
            if not has_counter:
                db.execute(
                    text("""
                        INSERT INTO llm_usage_counters
                            (id, tenant_id, license_id, cycle_start, cycle_end,
                             max_calls, used_calls, extra_calls, remaining_calls)
                        VALUES
                            (gen_random_uuid(), CAST(:t AS uuid), :l, CURRENT_DATE,
                             CURRENT_DATE + CAST(:days AS integer),
                             :max, 0, 0, :max)
                    """),
                    {"t": tenant_id, "l": lic[0], "days": lic[2], "max": lic[1]},
                )
                db.commit()
                log.info("✅ Compteur LLM initialisé (%s points / cycle)", lic[1])
        return tenant_id
    finally:
        db.close()


# ─────────────────────────────────────────────────────────────────────────────
# 5. Lien tenant_link.UUU dans la base tenant
# ─────────────────────────────────────────────────────────────────────────────
def link_tenant(tenant_engine, tenant_id: str) -> None:
    from sqlalchemy import text

    with tenant_engine.begin() as conn:
        current = conn.execute(text('SELECT "UUU" FROM tenant_link LIMIT 1')).scalar()
        if current is None:
            conn.execute(text('INSERT INTO tenant_link ("UUU") VALUES (:u)'), {"u": tenant_id})
            log.info("✅ tenant_link.UUU initialisé (%s)", tenant_id)
        elif str(current) != tenant_id:
            fail(
                f"La base '{TENANT_NAME}' est déjà liée à un autre tenant "
                f"(UUU={current}, attendu {tenant_id}). Refus d'écraser."
            )
        else:
            log.info("ℹ️  tenant_link.UUU déjà correct")


# ─────────────────────────────────────────────────────────────────────────────
# 6. Buckets MinIO
# ─────────────────────────────────────────────────────────────────────────────
def ensure_buckets() -> None:
    import boto3
    from botocore.exceptions import ClientError

    s3 = boto3.client(
        "s3",
        endpoint_url=os.environ["S3_ENDPOINT"],
        aws_access_key_id=os.environ["S3_ACCESS_KEY"],
        aws_secret_access_key=os.environ["S3_SECRET_KEY"],
        region_name=os.environ.get("S3_REGION_NAME", "us-east-1"),
    )
    # S3_BUCKET (global) + bucket au nom du tenant (utilisé par la lecture des
    # scripts de test : bucket = nom de la base — cf. test_case_apis_view.py)
    for bucket in dict.fromkeys([os.environ["S3_BUCKET"], TENANT_NAME]):
        try:
            s3.head_bucket(Bucket=bucket)
            log.info("ℹ️  Bucket '%s' existe déjà", bucket)
        except ClientError:
            s3.create_bucket(Bucket=bucket)
            log.info("✅ Bucket '%s' créé", bucket)


# ─────────────────────────────────────────────────────────────────────────────
# 7. Keycloak : realm, clients, rôle admin, utilisateur admin
# ─────────────────────────────────────────────────────────────────────────────
class KeycloakAdmin:
    def __init__(self) -> None:
        import requests

        self.rq = requests
        self.base = os.environ["KEYCLOAK_SERVER"].rstrip("/")
        self._login()

    def _login(self) -> None:
        r = self.rq.post(
            f"{self.base}/realms/master/protocol/openid-connect/token",
            data={
                "grant_type": "password",
                "client_id": "admin-cli",
                "username": os.environ["KEYCLOAK_USERNAME_ADMIN"],
                "password": os.environ["KEYCLOAK_PASSWORD_ADMIN"],
            },
            timeout=10,
        )
        if r.status_code != 200:
            fail(f"Authentification admin Keycloak impossible (HTTP {r.status_code})")
        self.headers = {"Authorization": f"Bearer {r.json()['access_token']}"}

    def call(self, method: str, path: str, ok=(200, 201, 204), **kwargs):
        r = self.rq.request(
            method, f"{self.base}/admin{path}", headers=self.headers, timeout=15, **kwargs
        )
        if r.status_code == 401:  # token expiré → relogin puis retry unique
            self._login()
            r = self.rq.request(
                method, f"{self.base}/admin{path}", headers=self.headers, timeout=15, **kwargs
            )
        if r.status_code not in ok and r.status_code != 409:  # 409 = existe déjà
            fail(f"Keycloak {method} {path} → HTTP {r.status_code} : {r.text[:300]}")
        return r


def keycloak_setup() -> None:
    kc = KeycloakAdmin()

    # Realm
    r = kc.call("GET", f"/realms/{TENANT_NAME}", ok=(200, 404))
    realm_payload = {
        "realm": TENANT_NAME,
        "enabled": True,
        "displayName": TENANT_DISPLAY_NAME,
        "sslRequired": "none",          # installation locale HTTP ; passer à
                                        # "external" derrière un reverse-proxy TLS
        "registrationAllowed": False,
        "resetPasswordAllowed": True,
        "bruteForceProtected": True,
    }
    # Thème de login uniquement s'il est déployé sur ce serveur
    themes = kc.call("GET", "/serverinfo", ok=(200,)).json().get("themes", {})
    if any(t.get("name") == LOGIN_THEME for t in themes.get("login", [])):
        realm_payload["loginTheme"] = LOGIN_THEME
    else:
        log.warning("Thème '%s' non déployé — thème Keycloak par défaut utilisé", LOGIN_THEME)

    if r.status_code == 404:
        kc.call("POST", "/realms", json=realm_payload, ok=(201,))
        log.info("✅ Realm '%s' créé", TENANT_NAME)
    else:
        kc.call("PUT", f"/realms/{TENANT_NAME}", json=realm_payload, ok=(204,))
        log.info("ℹ️  Realm '%s' déjà présent (mis à jour)", TENANT_NAME)

    # Clients publics (mêmes clients que le SaaS : turingone-frontend + frontend-app)
    for client_id, direct_access in (("turingone-frontend", False), ("frontend-app", True)):
        payload = {
            "clientId": client_id,
            "protocol": "openid-connect",
            "publicClient": True,
            "standardFlowEnabled": True,
            "directAccessGrantsEnabled": direct_access,
            "implicitFlowEnabled": False,
            "serviceAccountsEnabled": False,
            "fullScopeAllowed": True,
            "rootUrl": FRONTEND_URL,
            "baseUrl": FRONTEND_URL,
            "redirectUris": [f"{FRONTEND_URL}/*"],
            "webOrigins": [FRONTEND_URL],
            "attributes": {
                "post.logout.redirect.uris": f"{FRONTEND_URL}/*",
                "pkce.code.challenge.method": "S256",
            },
        }
        existing = kc.call(
            "GET", f"/realms/{TENANT_NAME}/clients?clientId={client_id}", ok=(200,)
        ).json()
        if existing:
            kc.call(
                "PUT", f"/realms/{TENANT_NAME}/clients/{existing[0]['id']}",
                json=payload, ok=(204,),
            )
            log.info("ℹ️  Client '%s' mis à jour", client_id)
        else:
            kc.call("POST", f"/realms/{TENANT_NAME}/clients", json=payload, ok=(201,))
            log.info("✅ Client '%s' créé", client_id)

    # Rôle realm "admin" (contrôles /billing/admin/* : voir billing_view._require_admin)
    kc.call("POST", f"/realms/{TENANT_NAME}/roles",
            json={"name": "admin", "description": "TuringOne platform administrator"},
            ok=(201,))

    # Utilisateur administrateur applicatif
    users = kc.call(
        "GET", f"/realms/{TENANT_NAME}/users?username={ADMIN_USERNAME}&exact=true", ok=(200,)
    ).json()
    if users:
        user_id = users[0]["id"]
        log.info("ℹ️  Utilisateur '%s' déjà présent", ADMIN_USERNAME)
    else:
        if not ADMIN_PASSWORD:
            fail("TURINGONE_ADMIN_PASSWORD est vide — impossible de créer l'administrateur")
        kc.call("POST", f"/realms/{TENANT_NAME}/users", json={
            "username": ADMIN_USERNAME,
            "email": TENANT_CONTACT_EMAIL,
            "enabled": True,
            "emailVerified": True,
        }, ok=(201,))
        user_id = kc.call(
            "GET", f"/realms/{TENANT_NAME}/users?username={ADMIN_USERNAME}&exact=true", ok=(200,)
        ).json()[0]["id"]
        kc.call("PUT", f"/realms/{TENANT_NAME}/users/{user_id}/reset-password", json={
            "type": "password",
            "value": ADMIN_PASSWORD,
            "temporary": False,
        }, ok=(204,))
        log.info("✅ Utilisateur '%s' créé", ADMIN_USERNAME)

    # Rôle realm "admin" → utilisateur
    role = kc.call("GET", f"/realms/{TENANT_NAME}/roles/admin", ok=(200,)).json()
    kc.call("POST", f"/realms/{TENANT_NAME}/users/{user_id}/role-mappings/realm",
            json=[{"id": role["id"], "name": role["name"]}], ok=(204,))

    # Rôles clients realm-management (gestion des utilisateurs depuis l'UI)
    rm = kc.call(
        "GET", f"/realms/{TENANT_NAME}/clients?clientId=realm-management", ok=(200,)
    ).json()
    if rm:
        rm_id = rm[0]["id"]
        rm_roles = kc.call("GET", f"/realms/{TENANT_NAME}/clients/{rm_id}/roles", ok=(200,)).json()
        wanted = [r for r in rm_roles if r["name"] in ("realm-admin",)]
        if wanted:
            kc.call(
                "POST",
                f"/realms/{TENANT_NAME}/users/{user_id}/role-mappings/clients/{rm_id}",
                json=[{"id": r["id"], "name": r["name"]} for r in wanted],
                ok=(204,),
            )
    log.info("✅ Rôles administrateur affectés à '%s'", ADMIN_USERNAME)

    ensure_profile_attributes(kc)


# ─────────────────────────────────────────────────────────────────────────────
# Attributs du User Profile ajoutés par TuringOne Community.
#
# `required` n'est VOLONTAIREMENT pas positionné sur les consentements : le
# rendre obligatoire côté realm ferait échouer toute écriture Admin API sur un
# utilisateur qui n'a pas encore accepté (y compris nos propres appels de
# synchronisation). L'obligation est portée là où elle a un sens :
#   - le formulaire login-update-profile.ftl (attribut HTML `required`)
#   - UserProfileUpdateSchema côté backend
#   - le service d'enregistrement, qui refuse d'inscrire sans acceptation
PROFILE_ATTRIBUTES = [
    {
        "name": "company",
        "displayName": "Company",
        "validations": {"length": {"min": 1, "max": 255}},
        "required": {"roles": ["user"]},
        "permissions": {"view": ["admin", "user"], "edit": ["admin", "user"]},
        "multivalued": False,
        "group": "user-metadata",
    },
    {
        "name": "termsAccepted",
        "displayName": "Terms of Service and DPA accepted",
        "validations": {"options": {"options": ["true", "false"]}},
        "permissions": {"view": ["admin", "user"], "edit": ["admin", "user"]},
        "multivalued": False,
        "group": "user-metadata",
    },
    {
        "name": "newsletterOptIn",
        "displayName": "Newsletter opt-in",
        "validations": {"options": {"options": ["true", "false"]}},
        "permissions": {"view": ["admin", "user"], "edit": ["admin", "user"]},
        "multivalued": False,
        "group": "user-metadata",
    },
]


def ensure_profile_attributes(kc: "KeycloakAdmin") -> None:
    """
    Déclare les attributs TuringOne dans le User Profile du realm.

    Depuis Keycloak 24, le User Profile déclaratif est actif par défaut et
    `unmanagedAttributePolicy` est absent : tout attribut NON déclaré est
    silencieusement rejeté à l'écriture. Sans cette déclaration, la société et
    les consentements saisis à la première connexion seraient perdus sans
    erreur — le pire des cas pour une preuve de consentement RGPD.

    Idempotent : seuls les attributs manquants sont ajoutés, les attributs
    existants (username, email, firstName, lastName) sont préservés.
    """
    path = f"/realms/{TENANT_NAME}/users/profile"

    r = kc.call("GET", path, ok=(200, 404))
    if r.status_code == 404:
        log.warning("User Profile indisponible sur ce Keycloak — attributs non déclarés")
        return

    profile = r.json()
    attributes = profile.get("attributes", [])
    existing = {a.get("name") for a in attributes}

    added = [a["name"] for a in PROFILE_ATTRIBUTES if a["name"] not in existing]
    if not added:
        log.info("ℹ️  Attributs du profil déjà déclarés (%s)", ", ".join(
            a["name"] for a in PROFILE_ATTRIBUTES))
        return

    attributes.extend(a for a in PROFILE_ATTRIBUTES if a["name"] not in existing)
    profile["attributes"] = attributes

    kc.call("PUT", path, json=profile, ok=(200, 204))
    log.info("✅ Attributs déclarés dans le User Profile : %s", ", ".join(added))


# ─────────────────────────────────────────────────────────────────────────────
def main() -> None:
    log.info("🚀 TuringOne Community — bootstrap (tenant=%s, plan=%s)", TENANT_NAME, PLAN_KEY)

    if os.environ.get("KMS_PROVIDER", "aws") == "local" and not os.environ.get("TURINGONE_MASTER_KEY"):
        fail("KMS_PROVIDER=local mais TURINGONE_MASTER_KEY est vide — lancez install.sh")

    wait_services()
    tenant_engine = ensure_tenant_schema()
    billing_engine = ensure_billing_schema()
    tenant_id = provision_tenant(billing_engine)
    link_tenant(tenant_engine, tenant_id)
    ensure_buckets()
    keycloak_setup()

    log.info("═" * 70)
    log.info("🎉 Bootstrap terminé avec succès")
    log.info("   Frontend  : %s", FRONTEND_URL)
    log.info("   Connexion : %s / (mot de passe TURINGONE_ADMIN_PASSWORD du .env)", ADMIN_USERNAME)
    log.info("═" * 70)


if __name__ == "__main__":
    main()
