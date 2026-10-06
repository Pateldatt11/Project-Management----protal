param(
  [Parameter(Mandatory = $true)]
  [string]$CredentialPath,
  [string]$ProjectId = "project-management-dashb-aa77a",
  [int]$Port = 8080
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $CredentialPath)) {
  throw "Firebase Admin SDK credential not found: $CredentialPath"
}

$env:NODE_ENV = "development"
$env:HOST = "127.0.0.1"
$env:PORT = "$Port"
$env:FIREBASE_PROJECT_ID = $ProjectId
$env:GOOGLE_APPLICATION_CREDENTIALS = (Resolve-Path $CredentialPath).Path
$env:ANDROID_PACKAGE_NAME = "com.example.test"
# Empty means local development origins are accepted. Do not use this setting
# on the public Oracle deployment.
$env:ADMIN_WEB_ORIGINS = ""
$env:ALLOW_START_WITHOUT_FIREBASE = "false"

Push-Location (Join-Path $PSScriptRoot "../..")
try {
  npm install
  npm run build
  npm start
} finally {
  Pop-Location
}
