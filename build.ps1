<#
.SYNOPSIS
  Builds a Jellyfin Tizen (Samsung TV) package that loads the server's web plugins.

.DESCRIPTION
  Downloads a prebuilt Jellyfin Tizen .wgt from jeppevinkel/jellyfin-tizen-builds,
  adds plugin-loader.js to the bundled jellyfin-web, bumps the package version, tags
  the app version string, strips the old signatures, and repackages it.

  The output is unsigned. Install it with Apps2Samsung's custom-WGT option, which
  signs it with your TV's certificate during install.

.PARAMETER Release
  Release tag of jellyfin-tizen-builds (e.g. 2026-09-27-1820), or "latest".

.PARAMETER Variant
  Asset name without .wgt. "Jellyfin" is the normal build whose jellyfin-web matches
  the current stable server; see the release notes for the others.

.PARAMETER Version
  Package version written to config.xml. Must be higher than what is on the TV
  for it to install as an update.

.EXAMPLE
  .\build.ps1 -Release latest -Version 0.1.2
#>
[CmdletBinding()]
param(
    [string]$Release = 'latest',
    [string]$Variant = 'Jellyfin',
    [string]$Version = '0.1.1',
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
# $PSScriptRoot is empty in param defaults on Windows PowerShell 5.1
if (-not $OutDir) { $OutDir = Join-Path $PSScriptRoot 'dist' }
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$api = 'https://api.github.com/repos/jeppevinkel/jellyfin-tizen-builds/releases'
$rel = if ($Release -eq 'latest') { (Invoke-RestMethod "$api`?per_page=1")[0] } else { Invoke-RestMethod "$api/tags/$Release" }
$asset = $rel.assets | Where-Object { $_.name -eq "$Variant.wgt" }
if (-not $asset) { throw "Release $($rel.tag_name) has no asset '$Variant.wgt'." }
Write-Host "Base: $($rel.tag_name) / $($asset.name) ($([math]::Round($asset.size / 1MB, 1)) MB)"

$work = Join-Path $PSScriptRoot 'work'
$src = Join-Path $work 'src'
if (Test-Path $work) { [IO.Directory]::Delete($work, $true) }
New-Item -ItemType Directory -Force -Path $src | Out-Null
$wgtIn = Join-Path $work $asset.name
Invoke-WebRequest $asset.browser_download_url -OutFile $wgtIn -UseBasicParsing
[IO.Compression.ZipFile]::ExtractToDirectory($wgtIn, $src)

# 1. loader into the bundled web client, right before </head>
Copy-Item (Join-Path $PSScriptRoot 'plugin-loader.js') (Join-Path $src 'www\plugin-loader.js')
$indexPath = Join-Path $src 'www\index.html'
$index = [IO.File]::ReadAllText($indexPath)
if ($index -notmatch 'plugin-loader\.js') {
    if ($index -notmatch '</head>') { throw 'www/index.html has no </head> to inject before.' }
    $index = $index.Replace('</head>', '<script src="plugin-loader.js"></script></head>')
    [IO.File]::WriteAllText($indexPath, $index, (New-Object Text.UTF8Encoding $false))
}

# 2. package version (the widget's, not the XML declaration's)
$cfgPath = Join-Path $src 'config.xml'
$cfg = [IO.File]::ReadAllText($cfgPath)
$cfg = [regex]::Replace($cfg, '(<widget\b[^>]*\bversion=")[^"]*(")', "`${1}$Version`${2}")
[IO.File]::WriteAllText($cfgPath, $cfg, (New-Object Text.UTF8Encoding $false))

# 3. tag the app version Jellyfin shows in Dashboard > Devices
$tizenPath = Join-Path $src 'tizen.js'
$tizen = [IO.File]::ReadAllText($tizenPath)
if ($tizen -notmatch '\+ server plugins') {
    $tizen = [regex]::Replace($tizen, '(compiled [^"]*?)"', '$1 + server plugins"', 1)
    [IO.File]::WriteAllText($tizenPath, $tizen, (New-Object Text.UTF8Encoding $false))
}

# 4. old signatures no longer match; the installer re-signs
Get-ChildItem $src -Filter '*signature*.xml' | ForEach-Object { [IO.File]::Delete($_.FullName) }

# 5. zip with forward-slash entry names (Tizen rejects backslashes)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$out = Join-Path $OutDir "Jellyfin-Frame-plugins-$Version.wgt"
if ([IO.File]::Exists($out)) { [IO.File]::Delete($out) }
$zip = [IO.Compression.ZipFile]::Open($out, 'Create')
try {
    foreach ($f in Get-ChildItem $src -Recurse -File) {
        $rel = $f.FullName.Substring($src.Length + 1) -replace '\\', '/'
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $rel, 'Optimal')
    }
} finally {
    $zip.Dispose()
}

$hash = (Get-FileHash $out -Algorithm SHA256).Hash.ToLower()
Write-Host "Built: $out"
Write-Host "SHA256: $hash"
