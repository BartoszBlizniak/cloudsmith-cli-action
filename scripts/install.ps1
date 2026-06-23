#!/usr/bin/env pwsh
# install.ps1 — Cloudsmith CLI installer for native Windows (PUBLIC repo only).
# PowerShell sibling of install.sh: detects host -> resolves the tagged archive ->
# downloads + extracts the onedir bundle -> puts cloudsmith.exe on PATH ->
# authenticates with available credentials. NO pip. NO zipapp. NO tokens.

[CmdletBinding()]
param(
  [string]$Repo        = "bart-demo-org-terraform/cli-binary-release-test",  # OWNER/REPOSITORY (public)
  [string]$Version     = "latest",                                           # e.g. 1.19.0, or 'latest'
  [string]$InstallRoot = (Join-Path $HOME ".cloudsmith"),
  [switch]$NoAuth
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# 1) Detect host. Only windows-x86_64 is built; on Arm64 Windows the x64 binary
#    runs under emulation, so we still select windows-x86_64.
$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
if ($arch -notin @("X64", "Arm64")) { throw "install.ps1: unsupported arch: $arch" }
$Target = "windows-x86_64"
$Name   = "cloudsmith-cli-$Target"
$Ext    = ".zip"
Write-Host "install.ps1: host $Target"

# 2) Resolve the concrete version. Pinned = deterministic. 'latest' = tag query (public).
if ([string]::IsNullOrEmpty($Version) -or $Version -eq "latest") {
  $q   = "tag:standalone-binary tag:windows tag:x86_64" -replace ' ', '%20'
  $api = "https://api.cloudsmith.io/v1/packages/$Repo/?query=$q&page_size=1&sort=-version"
  # The packages API returns a top-level JSON array of packages.
  $resp = Invoke-RestMethod -Uri $api -UseBasicParsing
  $Version = @($resp)[0].version
  if ([string]::IsNullOrEmpty($Version)) { throw "install.ps1: could not resolve latest version for $Target" }
  Write-Host "install.ps1: resolved latest -> $Version"
}

$File = "cloudsmith-$Version-$Target$Ext"
$Url  = "https://dl.cloudsmith.io/public/$Repo/raw/names/$Name/versions/$Version/$File"
Write-Host "install.ps1: downloading $Url"

# 3) Download + extract the onedir bundle (yields $InstallRoot\cloudsmith\).
New-Item -ItemType Directory -Force -Path $InstallRoot | Out-Null
$zip = Join-Path ([System.IO.Path]::GetTempPath()) $File
Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $zip
Expand-Archive -Path $zip -DestinationPath $InstallRoot -Force
Remove-Item $zip -Force

$binDir = Join-Path $InstallRoot "cloudsmith"
$bin    = Join-Path $binDir "cloudsmith.exe"
if (-not (Test-Path $bin)) { throw "install.ps1: cloudsmith.exe not found in archive" }
if ($env:GITHUB_PATH) { Add-Content -Path $env:GITHUB_PATH -Value $binDir }
$env:PATH = "$binDir;$env:PATH"

& $bin --version
Write-Host "install.ps1: installed to $binDir"
if (-not $env:GITHUB_PATH) { Write-Host "install.ps1: add to PATH -> `$env:PATH = `"$binDir;`$env:PATH`"" }

# 4) Authenticate with whatever credentials are available (API key env, or native
#    OIDC via CLOUDSMITH_ORG + CLOUDSMITH_SERVICE_SLUG with id-token granted in CI).
if (-not $NoAuth) {
  & $bin whoami
  if ($LASTEXITCODE -eq 0) { Write-Host "install.ps1: authenticated" }
  else { Write-Warning "install.ps1: no usable credentials (CLI installed, not authenticated)" }
}
