# =============================================================================
# TuringOne Community - Installation en un clic (Windows PowerShell)
#
#   .\install.ps1            installation complete (genere .env + demarre la stack)
#   .\install.ps1 -EnvOnly   genere uniquement le .env
#
# Idempotent : un .env existant n'est JAMAIS ecrase (les secrets generes - dont
# la master key de chiffrement - doivent survivre aux reinstallations).
# =============================================================================
param(
    [switch]$EnvOnly
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

function Info($msg)  { Write-Host "[i]  $msg" -ForegroundColor Cyan }
function Ok($msg)    { Write-Host "[OK] $msg" -ForegroundColor Green }
function Warn($msg)  { Write-Host "[!]  $msg" -ForegroundColor Yellow }
function Fail($msg)  { Write-Host "[X]  $msg" -ForegroundColor Red; exit 1 }

# --- Prerequis ---------------------------------------------------------------
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Fail "Docker n'est pas installe : https://docs.docker.com/get-docker/"
}
docker compose version *> $null
if ($LASTEXITCODE -ne 0) { Fail "Docker Compose v2 requis (commande 'docker compose')" }
docker info *> $null
if ($LASTEXITCODE -ne 0) { Fail "Le demon Docker ne repond pas - demarrez Docker Desktop" }

# --- Generation de secrets ----------------------------------------------------
function New-RandomBytes([int]$n) {
    $bytes = New-Object byte[] $n
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return $bytes
}
function New-Secret {           # 48 caracteres hexadecimaux
    return ((New-RandomBytes 24) | ForEach-Object { $_.ToString("x2") }) -join ""
}
function New-KeyId {
    return "turingone" + (((New-RandomBytes 8) | ForEach-Object { $_.ToString("x2") }) -join "")
}
function New-MasterKey {        # 32 octets en base64 url-safe
    $b64 = [Convert]::ToBase64String((New-RandomBytes 32))
    return $b64.Replace('+', '-').Replace('/', '_')
}
# Lecture/ecriture en UTF-8 SANS BOM : Get-Content/Set-Content de Windows
# PowerShell 5.1 decoderaient le fichier en ANSI (commentaires UTF-8 corrompus)
# et ajouteraient un BOM que certains parseurs dotenv digerent mal.
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
function Set-EnvVar([string]$Name, [string]$Value) {
    $path = Join-Path $PSScriptRoot ".env"
    $content = [System.IO.File]::ReadAllText($path, $script:Utf8NoBom)
    $content = $content -replace "(?m)^$([regex]::Escape($Name))=.*$", "$Name=$Value"
    [System.IO.File]::WriteAllText($path, $content, $script:Utf8NoBom)
}

if (Test-Path .env) {
    Warn ".env existant conserve (secrets preserves). Supprimez-le pour repartir de zero."
} else {
    Info "Generation du fichier .env avec des secrets aleatoires..."
    Copy-Item .env.example .env

    $dbPassword = New-Secret
    Set-EnvVar "POSTGRES_SUPERUSER_PASSWORD" (New-Secret)
    Set-EnvVar "DATABASE_PASSWORD"           $dbPassword
    Set-EnvVar "BILLING_DATABASE_PASSWORD"   $dbPassword
    Set-EnvVar "KC_DB_PASSWORD"              (New-Secret)
    Set-EnvVar "KEYCLOAK_PASSWORD_ADMIN"     (New-Secret)
    Set-EnvVar "TURINGONE_ADMIN_PASSWORD"    (New-Secret)
    Set-EnvVar "RABBITMQ_PASSWORD"           (New-Secret)
    Set-EnvVar "S3_ACCESS_KEY"               (New-KeyId)
    Set-EnvVar "S3_SECRET_KEY"               (New-Secret)
    Set-EnvVar "TURINGONE_MASTER_KEY"        (New-MasterKey)

    # Equivalent du chmod 600 : acces restreint a l'utilisateur courant
    icacls .env /inheritance:r /grant:r "$($env:USERNAME):(R,W)" *> $null

    Ok ".env genere (acces restreint a $($env:USERNAME))"
    Warn "SAUVEGARDEZ ce fichier : TURINGONE_MASTER_KEY est indispensable pour dechiffrer vos donnees."
}

$envContent = Get-Content .env -Raw
if ($envContent -match "CHANGE-ME") {
    Warn "Pensez a renseigner VLLM_API_KEY dans .env (cle OpenAI ou serveur LLM local)."
}

if ($EnvOnly) { Ok "Fichier .env pret. Lancez : docker compose up -d"; exit 0 }

# --- Etape 1/3 : telechargement des images (la partie LONGUE) ---------------------------
Info "Etape 1/3 - Téléchargement des images..."
Info "  Le PREMIER telechargement represente environ 2 Go :"
Info "  comptez 10 a 30 min selon la connexion. La progression s'affiche ci-dessous."
docker compose pull
if ($LASTEXITCODE -ne 0) { Fail "Le telechargement des images a echoue (voir la sortie ci-dessus)" }
Ok "Images construites"

# --- Etape 2/3 : demarrage ------------------------------------------------------
Info "Etape 2/3 - Demarrage des services..."
# Ne pas echouer ici : backend depend du bootstrap, donc un echec de provisioning
# fait echouer 'up' — on veut alors afficher les logs du bootstrap.
docker compose up -d
$composeRc = $LASTEXITCODE

# --- Etape 3/3 : provisioning automatique (bootstrap) ---------------------------
Info "Etape 3/3 - Provisioning automatique (bases, Keycloak, buckets)..."
$bootCid = (docker compose ps -aq bootstrap | Select-Object -First 1)
if (-not $bootCid) { Fail "Conteneur bootstrap introuvable - le demarrage a echoue (code $composeRc). Logs : docker compose logs" }

$elapsed = 0
while ((docker inspect -f '{{.State.Running}}' $bootCid) -eq "true") {
    Start-Sleep -Seconds 5
    $elapsed += 5
    if ($elapsed % 15 -eq 0) {
        # Affiche l'avancement reel du bootstrap toutes les 15 s
        Write-Host "--- provisioning en cours (${elapsed}s) - dernieres lignes du bootstrap :" -ForegroundColor DarkGray
        docker compose logs --tail 3 bootstrap 2>$null | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    }
}
$bootExit = [int](docker inspect -f '{{.State.ExitCode}}' $bootCid)
if ($bootExit -ne 0 -or $composeRc -ne 0) {
    docker compose logs bootstrap | Select-Object -Last 40
    Fail "Le bootstrap a echoue (voir logs ci-dessus) : docker compose logs bootstrap"
}
Ok "Provisioning termine"

# --- Resume ---------------------------------------------------------------------
$frontendUrl  = (Select-String -Path .env -Pattern '^FRONTEND_URL=(.*)$').Matches[0].Groups[1].Value
$adminUser    = (Select-String -Path .env -Pattern '^TURINGONE_ADMIN_USERNAME=(.*)$').Matches[0].Groups[1].Value
$keycloakUrl  = (Select-String -Path .env -Pattern '^KEYCLOAK_PUBLIC_URL=(.*)$').Matches[0].Groups[1].Value

Write-Host ""
Ok "TuringOne Community est installe !"
Write-Host ""
Write-Host "   Application  : $frontendUrl"
Write-Host "   Connexion    : $adminUser / (TURINGONE_ADMIN_PASSWORD dans .env)"
Write-Host "   Console Keycloak (admin technique) : $keycloakUrl"
Write-Host ""
Write-Host "   Premier demarrage du backend : telechargement des modeles d'embeddings"
Write-Host "   (quelques minutes). Suivre :  docker compose logs -f backend"
Write-Host ""
Warn "Sauvegardez le fichier .env (master key de chiffrement) avec vos backups !"
