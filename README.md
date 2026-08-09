# TuringOne — Community Edition

Plateforme de QA augmentée par l'IA : génération de cas de test API, exécution
E2E API et gestion des exigences, en auto-hébergé.

## 🚀 Installation en un clic

Toute la stack (PostgreSQL + pgvector, Keycloak, MinIO, RabbitMQ, Redis,
backend, worker, frontend) s'installe et se configure automatiquement :

```bash
# Linux / macOS
cd deploy/community && ./install.sh
```

```powershell
# Windows
cd deploy\community ; .\install.ps1
```

Puis ouvrez **http://community.localhost:5173**.

📖 Documentation complète : [deploy/community/README.md](deploy/community/README.md)
🔐 Sécurité & modèle de menace : [deploy/community/SECURITY.md](deploy/community/SECURITY.md)

## Ce que fait l'installation automatique

- Génère des secrets forts (aucun mot de passe par défaut) ;
- Crée les bases de données, le schéma, l'extension pgvector ;
- Provisionne le tenant, la licence `community` et les quotas de points IA ;
- Configure Keycloak (realm, clients OIDC, thème, compte administrateur) ;
- Crée les buckets S3 (MinIO local — aucune dépendance AWS) ;
- Chiffre les credentials par projet en RSA-4096/AES-256-GCM avec un
  provider de clés **local** (`KMS_PROVIDER=local`) protégé par la master key
  d'installation.

## Structure du dépôt

| Dossier | Contenu |
|---|---|
| `backend/` | API FastAPI, workers, moteur IA |
| `frontend/` | SPA Vue 3 (Vite + PrimeVue) |
| `deploy/community/` | Stack Docker Compose one-click + bootstrap + docs |
| `themes/` | Thème de login Keycloak |

## Limites de l'édition community

Plan `community` : 2 utilisateurs, 2 projets, 2 000 points IA / mois —
génération de tests API, tests E2E API, gestion des exigences.
Les éditions commerciales (Starter/Pro/Scale/Enterprise) ajoutent les tests UI,
les rapports IA avancés, l'analytique et le support dédié.
