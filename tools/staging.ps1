# npm run staging [-- -Seed]: gets a VepIndustriesMarket_Data\Data.lua from the staging API for an in-game check.
#   1. Sync script not installed on staging yet: creates a Sync code with the Admin's bearer token, read from the
#      clipboard (copy(localStorage.getItem('bearerToken')) in the console of the staging web app), and installs the
#      Sync script and its scheduled task against staging. Back to production: installer.cmd without -Api.
#   2. -Seed: sends the real Comparison of tests/merge-cases.json (681 items), moved to the last hour, from the
#      author "Ami (test)": staging keeps every Comparison, so seed only when it holds none for the auction house.
#   3. Runs the Sync script once, Data.lua removed first so that it fetches the file whatever the dates.
# Game folder: env WOW_ADDONS, as for deploy (npm run deploy first).
param(
    [switch]$Seed,
    [string]$Friend = 'Boris',
    [string]$Faction = 'Horde',
    [string]$Api = 'https://api-staging.vepindustries.com'
)
$ErrorActionPreference = 'Stop'
$addons = if ($env:WOW_ADDONS) { $env:WOW_ADDONS } else { 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns' }
$sync = Join-Path $addons 'VepIndustriesMarket\Sync.ps1'
$data = Join-Path $addons 'VepIndustriesMarket_Data\Data.lua'
$state = Join-Path $env:LOCALAPPDATA 'VepIndustriesMarket'
if (!(Test-Path $sync) -or !(Test-Path (Split-Path $data))) { throw "addon absent de $addons : npm run deploy d'abord" }

function Read-Config { if (Test-Path "$state\config.json") { Get-Content "$state\config.json" -Raw | ConvertFrom-Json } }
function Read-Code($cfg) {
    (New-Object PSCredential 'unused', (ConvertTo-SecureString $cfg.code)).GetNetworkCredential().Password
}

$cfg = Read-Config
if (!$cfg -or $cfg.api -ne $Api) {
    $token = ("$(Get-Clipboard)").Trim().Trim('"')
    if ($token.Length -lt 20 -or $token -match '\s') {
        throw "pas de jeton dans le presse-papiers : sur l'application web du staging, console, copy(localStorage.getItem('bearerToken'))"
    }
    $created = Invoke-RestMethod -Method Post -Uri "$Api/v1/sync-codes" -ContentType 'application/json' `
        -Headers @{ Authorization = "Bearer $token" } -Body (ConvertTo-Json @{ friend = $Friend })
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sync -Install -Code $created.code -Api $Api
    if ($LASTEXITCODE) { throw "installation du Script de synchro en échec (code $LASTEXITCODE)" }
    Write-Host "Script de synchro installé sur le staging, Code de synchro « $($created.friend) »."
    $cfg = Read-Config
}

if ($Seed) {
    $real = (Get-Content (Join-Path $PSScriptRoot '..\tests\merge-cases.json') -Raw -Encoding UTF8 | ConvertFrom-Json).cases[-1]
    $start = [DateTimeOffset]::Now.ToUnixTimeSeconds() - 3600
    $comparison = @{ author = 'Ami (test)'; realm = ''; faction = $Faction; start = $start; finish = $start + 919
        items = $real.comparisons[0].items }
    $body = [Text.Encoding]::UTF8.GetBytes((ConvertTo-Json @{ comparisons = @($comparison) } -Depth 4 -Compress))
    Invoke-WebRequest -Uri "$Api/v1/comparisons" -Method Post -Headers @{ 'Sync-Code' = (Read-Code $cfg) } `
        -ContentType 'application/json; charset=utf-8' -Body $body -UseBasicParsing | Out-Null
    Write-Host "Comparaison réelle envoyée au staging : « Ami (test) », $Faction, début $([DateTimeOffset]::FromUnixTimeSeconds($start).LocalDateTime)."
}

Remove-Item $data -ErrorAction Ignore
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sync
$last = Get-Content "$state\sync.log" -Tail 1 -Encoding UTF8
if ($LASTEXITCODE -or !(Test-Path $data)) { throw "passage du Script de synchro en échec : $last" }
$text = [IO.File]::ReadAllText($data)
$generated = [long][regex]::Match($text, 'generated\s*=\s*(\d+)').Groups[1].Value
Write-Host ("Data.lua : {0} objets, {1} Comparaison(s) comptée(s), produit le {2}." -f `
    ([regex]::Matches($text, '(?m)^\[\d+\] = \{')).Count, ([regex]::Matches($text, '\[\d+\]\s*=\s*true')).Count,
    [DateTimeOffset]::FromUnixTimeSeconds($generated).LocalDateTime)
Write-Host 'En jeu : /reload (relance le jeu si npm run deploy a créé un dossier), hôtel des ventes, puis /vim item 4306.'
