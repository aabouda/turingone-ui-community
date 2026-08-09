# TuringOne Community — Sécurité & modèle de menace

Ce document décrit **honnêtement** ce que l'édition community protège, comment,
et quelles sont les limites. À lire avant toute distribution à des clients.

---

## 1. Protection des données (base de données, stockage)

### Ce qui est en place

| Mesure | Détail |
|---|---|
| Réseau interne isolé | PostgreSQL, MinIO, RabbitMQ, Redis sont sur un réseau Docker `internal: true` : **aucun port publié**, pas de route sortante. Ils sont injoignables depuis l'hôte et depuis Internet. |
| Secrets générés | Tous les mots de passe sont générés aléatoirement à l'installation (48 caractères hex) — aucun secret par défaut, aucun secret commité. |
| Moindre privilège PostgreSQL | Rôle `keycloak` limité à sa base ; rôle applicatif `turingone` propriétaire des bases métier **sans** droits superuser ; le superuser n'est utilisé que par le script d'init au premier démarrage. |
| Chiffrement applicatif | Les credentials tiers (JIRA, Xray, Azure, Git, auth API) sont chiffrés par projet (RSA-4096 + AES-256-GCM). La clé privée de chaque projet est chiffrée par la master key (`TURINGONE_MASTER_KEY`), qui **n'est pas en base** : un dump SQL volé ne révèle aucun secret. |
| Conteneurs durcis | Backend non-root (uid 10001), système de fichiers applicatif en lecture seule de fait (seul `/data` est monté en écriture). |

### Les limites (à assumer)

- **Qui contrôle le démon Docker contrôle tout.** Un administrateur de la machine
  hôte peut faire `docker exec` dans les conteneurs, inspecter les volumes et
  lire l'environnement (`docker inspect` → variables, dont les mots de passe et
  la master key). C'est structurel à l'auto-hébergement : la protection vise les
  utilisateurs applicatifs et les attaquants réseau, **pas** le root de l'hôte.
- Les variables d'environnement du `.env` sont visibles via l'API Docker locale.
  Pour un durcissement supérieur : Docker secrets/Swarm, SOPS, ou Vault.
- Le trafic publié (frontend/API/Keycloak) est en **HTTP** par défaut (usage
  local). Pour toute exposition au-delà de la machine : placer un reverse-proxy
  TLS (Caddy, Traefik, nginx) devant les trois ports, passer `sslRequired` du
  realm à `external`, et mettre à jour les URLs publiques du `.env`.

## 2. Protection du code (propriété intellectuelle)

### Ce qui est en place

| Couche | Mesure |
|---|---|
| Backend | L'image `Dockerfile.community` **supprime tous les fichiers `.py`** après compilation : seul le bytecode (`.pyc`) est livré. L'outillage de dev (scripts AWS, `tenant-onboarding/`, `tmp/`, dumps) est retiré de l'image. |
| Frontend | Bundle Vite minifié standard (pas de sources, pas de sourcemaps). |
| Distribution | Le client final peut ne recevoir **que** `deploy/community/` + les images (registry) : aucun code source n'a besoin d'être livré. |

### Les limites (importantes — soyez transparent avec vous-même)

- **Le bytecode Python se décompile** (uncompyle6, decompyle3, pycdc). La
  suppression des `.py` élève le coût de la rétro-ingénierie, elle ne
  l'empêche pas. Un obfuscateur (PyArmor) ou Cython/Nuitka élèveraient encore
  le coût, avec la même conclusion de fond.
- **Règle d'or : ce qui doit rester secret ne doit pas être livré.** La seule
  protection forte est de garder côté SaaS ce qui a le plus de valeur (prompts
  avancés, pipelines d'IA propriétaires, algorithmes différenciants) et de ne
  mettre dans l'édition community que ce que vous acceptez de voir étudié.
  C'est le modèle « open-core » : la limite est **contractuelle (licence) +
  fonctionnelle (plan community)**, pas cryptographique.
- Recommandé : LICENSE explicite pour l'édition community (interdiction de
  rétro-ingénierie/redistribution selon votre juridiction) + images publiées
  sur un registry privé avec tokens d'accès par client si nécessaire.

## 3. Authentification & multi-tenant

- Authentification déléguée à **Keycloak** (OIDC, PKCE S256, brute-force
  protection activée sur le realm). Aucun mot de passe applicatif en base.
- Un seul tenant est provisionné (`TENANT_NAME`). Le backend acceptant tout
  realm présent sur le serveur Keycloak, **ne créez pas de realms de test** sur
  cette instance : chaque realm devient de facto un tenant valide.
- Le compte admin Keycloak (`KEYCLOAK_USERNAME_ADMIN`) est un compte
  **technique** : ne le distribuez pas aux utilisateurs finaux ; l'administration
  applicative passe par le compte `TURINGONE_ADMIN_USERNAME` du realm tenant.
- La console Keycloak est publiée (nécessaire au flux de login). Si vous n'avez
  pas besoin d'administrer Keycloak à distance, restreignez `/admin` au niveau
  du reverse-proxy.

## 4. Points d'attention applicatifs connus

| Point | État | Impact community |
|---|---|---|
| Validation JWT sans vérification d'audience (`verify_aud: False`) ni d'issuer attendu | héritage SaaS | Acceptable en mono-tenant isolé ; à durcir si multi-realm |
| JWKS re-téléchargé à chaque requête (pas de cache) | héritage SaaS | Latence + charge Keycloak ; interne au réseau Docker |
| `X-Turing-Token` (callbacks CI) stocké en clair en base | héritage SaaS | Jeton d'usage limité, régénérable dans l'UI |
| `/docs`, `/redoc` refusés hors loopback | en place | Swagger inaccessible à travers le port publié — voulu |
| Rate-limit `/config` 30 req/min | en place | OK |

## 5. Checklist avant de donner l'accès à un client

- [ ] `.env` généré sur la machine cible (jamais réutilisé d'une autre installation)
- [ ] `TURINGONE_MASTER_KEY` sauvegardée hors de la machine (coffre)
- [ ] Reverse-proxy TLS si accessible au-delà de `localhost`
- [ ] Images poussées sur un registry (le client ne reçoit pas les sources)
- [ ] LICENSE community jointe à la distribution
- [ ] Sauvegardes planifiées : `pg_dumpall` + volume MinIO + `.env`
- [ ] Compte admin Keycloak conservé par vous (pas transmis au client final)
