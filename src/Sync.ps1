# Sync script (GLOSSARY.md): links the game's save to the VPS, run by a scheduled task every 15 minutes of the
# Windows session. Windows PowerShell 5.1; it never downloads code.
#   Sync.ps1 -Install : asks the friend's invitation code (Sync code) once, then creates the scheduled task, no admin.
#   Sync.ps1          : when a save changed, sends its new Comparisons and writes the addon's data file, Data.lua.
# Lives in <game>/Interface/AddOns/VepIndustriesMarket; its state (code, sent Comparisons, log) in
# %LOCALAPPDATA%\VepIndustriesMarket, which outlives the addon's updates.
param(
    [switch]$Install,
    [string]$Code,
    [string]$Api = 'https://api.vepindustries.com',
    [string]$TaskName = 'VepIndustriesMarket'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue' # Invoke-WebRequest's progress bar slows it down tenfold
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 'Tls12'

$game = Split-Path (Split-Path (Split-Path $PSScriptRoot))
$data = Join-Path $PSScriptRoot 'Data.lua'
$state = Join-Path $env:LOCALAPPDATA 'VepIndustriesMarket'
$config = Join-Path $state 'config.json'
$sent = Join-Path $state 'sent.txt'
$log = Join-Path $state 'sync.log'
$utf8 = New-Object Text.UTF8Encoding $false
$BATCH = 5 # the API takes 1 MiB per request, a real Comparison weighs ~125 KB
$IDLE_DAYS = 30

function Write-Log($message) {
    [IO.File]::AppendAllText($log, "$(Get-Date -Format s) $message`r`n", $utf8)
}

function Invoke-Api($api, $code, $method, $path, $body, $outFile) {
    $request = @{ Uri = "$api$path"; Method = $method; Headers = @{ 'Sync-Code' = $code }; UseBasicParsing = $true }
    if ($body) {
        # bytes: Windows PowerShell would encode a string body in ISO-8859-1
        $request.Body = $utf8.GetBytes((ConvertTo-Json $body -Depth 4 -Compress))
        $request.ContentType = 'application/json; charset=utf-8'
    }
    if ($outFile) { $request.OutFile = $outFile }
    Invoke-WebRequest @request | Out-Null
}

# $true when the API takes the code, $false when it refuses it (401); throws when it can't be reached
function Test-Code($api, $code) {
    try { Invoke-Api $api $code 'POST' '/v1/comparisons' @{ comparisons = @() }; $true }
    catch {
        if ($_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 401) { return $false }
        throw
    }
}

# The Comparisons of a save, as the game writes them: no indentation, one ["key"] = value per line.
function Read-Comparisons($text) {
    $block = [regex]::Match($text, '\["comparisons"\] = \{\r?\n((?:\{\r?\n(?:\["\w+"\] = [^\r\n]*\r?\n)*\},?[^\r\n]*\r?\n)*)\}')
    # a layout it can't read would otherwise empty sent.txt and send nothing, silently
    if (!$block.Success -and $text.Contains('["comparisons"] = {')) { throw 'Comparaisons illisibles dans la sauvegarde' }
    foreach ($entry in [regex]::Matches($block.Groups[1].Value, '\{\r?\n((?:\["\w+"\] = [^\r\n]*\r?\n)*)\}')) {
        $c = @{}
        foreach ($field in [regex]::Matches($entry.Groups[1].Value, '\["(\w+)"\] = (?:"((?:[^"\\]|\\.)*)"|(-?\d+))')) {
            $c[$field.Groups[1].Value] = if ($field.Groups[3].Success) { [long]$field.Groups[3].Value }
            else { $field.Groups[2].Value -replace '\\(.)', '$1' }
        }
        [ordered]@{ author = $c.author; realm = $c.realm; faction = $c.faction; start = $c.start; finish = $c.finish
            items = $c.items }
    }
}

# The code of config.json, encrypted for the Windows user (DPAPI); PSCredential only decrypts it, its name is unused.
function Read-Code($cfg) {
    (New-Object PSCredential 'unused', (ConvertTo-SecureString $cfg.code)).GetNetworkCredential().Password
}

if ($Install) {
    New-Item -ItemType Directory -Force $state | Out-Null
    if (!$Code -and (Test-Path $config)) { $Code = Read-Code (Get-Content $config -Raw | ConvertFrom-Json) }
    while (!$Code -or !(Test-Code $Api $Code)) {
        if ($Code) { Write-Host "Ce code d'invitation est refusé. Vérifiez-le auprès de Boris." }
        $Code = (Read-Host "Code d'invitation").Trim()
    }
    ConvertTo-Json @{ api = $Api; task = $TaskName; code = ConvertTo-SecureString $Code -AsPlainText -Force |
        ConvertFrom-SecureString } | Set-Content $config

    # The task outlives the addon's folder: it then removes itself instead of running the script, once the folder
    # stays away for 10 s (an update of the addon, or npm run deploy, removes it for a moment).
    $script = (Join-Path $PSScriptRoot 'Sync.ps1') -replace "'", "''"
    $run = "if (!(Test-Path -LiteralPath '$script')) { Start-Sleep 10 } " +
        "if (Test-Path -LiteralPath '$script') { & '$script' } " +
        "else { Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false }"
    # conhost --headless: no window, which would take the focus from the game every 15 minutes
    $action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument ("--headless powershell.exe -NoProfile " +
        "-NonInteractive -ExecutionPolicy Bypass -Command `"$run`"")
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Write-Host 'Script de synchro installé : toutes les 15 minutes, il envoie vos Comparaisons au VPS quand le jeu a écrit'
    Write-Host 'une nouvelle sauvegarde. Il se retire seul si vous supprimez l''addon ou ne jouez plus pendant 30 jours.'
    return
}

try {
    $cfg = Get-Content $config -Raw | ConvertFrom-Json
    $saves = @(Get-ChildItem "$game\WTF\Account\*\SavedVariables\VepIndustriesMarket.lua" -ErrorAction Ignore)
    $lastActivity = @($saves) + (Get-Item $config) | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($lastActivity.LastWriteTime -lt (Get-Date).AddDays(-$IDLE_DAYS)) {
        Unregister-ScheduledTask -TaskName $cfg.task -Confirm:$false
        Write-Log "aucune sauvegarde depuis $IDLE_DAYS jours : tâche retirée"
        return
    }
    if ((Test-Path $data) -and !($saves | Where-Object LastWriteTime -gt (Get-Item $data).LastWriteTime)) { return }

    $code = Read-Code $cfg
    $latest = $saves | Sort-Object LastWriteTime | Select-Object -Last 1
    $done = @{}
    if (Test-Path $sent) { foreach ($key in [IO.File]::ReadAllLines($sent, $utf8)) { $done[$key] = $true } }
    $all = @(foreach ($save in $saves) { Read-Comparisons ([IO.File]::ReadAllText($save.FullName, $utf8)) })
    $new = @($all | Where-Object { !$done["$($_.author)`t$($_.start)"] })
    for ($i = 0; $i -lt $new.Count; $i += $BATCH) {
        Invoke-Api $cfg.api $code 'POST' '/v1/comparisons' @{ comparisons = @($new[$i..($i + $BATCH - 1)]) }
    }
    [IO.File]::WriteAllLines($sent, [string[]]@($all | ForEach-Object { "$($_.author)`t$($_.start)" }), $utf8)

    # The data file of the auction house last scanned. Its full scan's table holds no other realm or faction key, and
    # its items no string key: the first ones after it are its own, whatever the order the game wrote them in.
    $text = [IO.File]::ReadAllText($latest.FullName, $utf8)
    $at = $text.IndexOf('["fullScan"] = {')
    if ($at -lt 0) { Write-Log "$($new.Count) Comparaison(s) envoyée(s), aucun Scan complet : pas de fichier de données"; return }
    $realm = ([regex]'\["realm"\] = "((?:[^"\\]|\\.)*)"').Match($text, $at).Groups[1].Value -replace '\\(.)', '$1'
    $faction = ([regex]'\["faction"\] = "(\w+)"').Match($text, $at).Groups[1].Value
    $dayZero = ([DateTimeOffset][datetime]'2020-01-01').ToUnixTimeSeconds() # Auctionator's day 0, local midnight
    $query = "realm=$([uri]::EscapeDataString($realm))&faction=$faction&dayZero=$dayZero"
    Invoke-Api $cfg.api $code 'GET' "/v1/addon-data?$query" $null "$data.tmp"
    Move-Item "$data.tmp" $data -Force
    # dated as the save it answers: one the game writes during this run stays newer, for the next run
    (Get-Item $data).LastWriteTime = $latest.LastWriteTime
    Write-Log "$($new.Count) Comparaison(s) envoyée(s), fichier de données écrit"
} catch {
    Write-Log "erreur : $_"
    exit 1
}
