# TuringOne UI Community
# Copyright (C) 2026 TuringOne
# SPDX-License-Identifier: AGPL-3.0-only
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
    Fail "Docker is not installed: https://docs.docker.com/get-docker/"
}
docker compose version *> $null
if ($LASTEXITCODE -ne 0) { Fail "Docker Compose v2 is required (the 'docker compose' command)" }
docker info *> $null
if ($LASTEXITCODE -ne 0) { Fail "The Docker daemon is not responding - start Docker Desktop" }

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
# Relit une valeur du .env pour le resume final. Retourne "" si la cle est
# absente : sans ce garde, $ErrorActionPreference = "Stop" ferait echouer tout
# le script sur .Matches[0] alors que l'installation, elle, a reussi.
function Get-EnvValue([string]$Name) {
    $match = Select-String -Path .env -Pattern "^$([regex]::Escape($Name))=(.*)$" | Select-Object -First 1
    if ($match) { return $match.Matches[0].Groups[1].Value }
    return ""
}

if (Test-Path .env) {
    Warn "Existing .env kept (secrets preserved). Delete it to start from scratch."
} else {
    Info "Generating the .env file with random secrets..."
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

    Ok ".env generated (access restricted to $($env:USERNAME))"
    Warn "BACK UP this file: TURINGONE_MASTER_KEY is required to decrypt your data."
}

$envContent = Get-Content .env -Raw
if ($envContent -match "CHANGE-ME") {
    Warn "Remember to set VLLM_API_KEY in .env (OpenAI key or local LLM server)."
}

if ($EnvOnly) { Ok "The .env file is ready. Run: docker compose up -d"; exit 0 }

# --- Etape 1/3 : telechargement des images (la partie LONGUE) ---------------------------
Info "Step 1/3 - Downloading the images..."
Info "  The FIRST download is around 2 GB:"
Info "  allow 10 to 30 min depending on your connection. Progress is shown below."
docker compose pull
if ($LASTEXITCODE -ne 0) { Fail "Image download failed (see the output above)" }
Ok "Images downloaded"

# --- Etape 2/3 : demarrage ------------------------------------------------------
Info "Step 2/3 - Starting the services..."
# Ne pas echouer ici : backend depend du bootstrap, donc un echec de provisioning
# fait echouer 'up' — on veut alors afficher les logs du bootstrap.
docker compose up -d
$composeRc = $LASTEXITCODE

# --- Etape 3/3 : provisioning automatique (bootstrap) ---------------------------
Info "Step 3/3 - Automatic provisioning (databases, Keycloak, buckets)..."
$bootCid = (docker compose ps -aq bootstrap | Select-Object -First 1)
if (-not $bootCid) { Fail "Bootstrap container not found - startup failed (code $composeRc). Logs: docker compose logs" }

$elapsed = 0
while ((docker inspect -f '{{.State.Running}}' $bootCid) -eq "true") {
    Start-Sleep -Seconds 5
    $elapsed += 5
    if ($elapsed % 15 -eq 0) {
        # Affiche l'avancement reel du bootstrap toutes les 15 s
        Write-Host "--- provisioning in progress (${elapsed}s) - last lines from the bootstrap:" -ForegroundColor DarkGray
        docker compose logs --tail 3 bootstrap 2>$null | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    }
}
$bootExit = [int](docker inspect -f '{{.State.ExitCode}}' $bootCid)
if ($bootExit -ne 0 -or $composeRc -ne 0) {
    docker compose logs bootstrap | Select-Object -Last 40
    Fail "Bootstrap failed (see the logs above): docker compose logs bootstrap"
}
Ok "Provisioning complete"

# --- Resume ---------------------------------------------------------------------
$frontendUrl   = Get-EnvValue "FRONTEND_URL"
$adminUser     = Get-EnvValue "TURINGONE_ADMIN_USERNAME"
$adminPassword = Get-EnvValue "TURINGONE_ADMIN_PASSWORD"
$keycloakUrl   = Get-EnvValue "KEYCLOAK_PUBLIC_URL"
$kcAdminUser   = Get-EnvValue "KEYCLOAK_USERNAME_ADMIN"
$kcAdminPass   = Get-EnvValue "KEYCLOAK_PASSWORD_ADMIN"

Write-Host ""
Ok "TuringOne Community is installed!"
Write-Host ""
Write-Host "   Application : $frontendUrl"
Write-Host "   Username    : $adminUser"
Write-Host "   Password    : $adminPassword"
Write-Host ""
Write-Host "   Keycloak console (technical admin): $keycloakUrl"
Write-Host "      $kcAdminUser / $kcAdminPass"
Write-Host ""
Write-Host "   These credentials are also stored in the .env file (restricted access)."
Write-Host ""
Write-Host "   First backend startup: it downloads the embedding models"
Write-Host "   (a few minutes). Follow with:  docker compose logs -f backend"
Write-Host ""
Warn "Back up the .env file (encryption master key) together with your backups!"
