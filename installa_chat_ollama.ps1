<#
  Installatore di Chat Ollama per Windows 10/11.

  Cosa fa, in ordine (salta tutto ciò che è già a posto):
    1. si apre come amministratore e senza blocchi per i criteri di esecuzione degli script;
    2. Python 3.10 o più recente, con il PATH di Windows sistemato;
    3. le librerie Python che servono a chat_ollama_web.py;
    4. Ollama (lo aggiorna solo se è troppo vecchio per i modelli scelti) e lo avvia;
    5. ti chiede quanta RAM ha il PC e installa il modello adatto, con agente (strumenti) e visione (immagini);
    6. prepara chat_ollama_web.py per questo PC, apre la porta nel firewall e crea l'icona sul desktop.
    7. se vuoi, fa partire la chat da sola (senza finestra) quando entri in Windows, con un codice di accesso fisso.

  Avvio consigliato: doppio clic su "Installa Chat Ollama.bat" (nella stessa cartella).
  Il registro completo finisce in "installa_log.txt", accanto a questo file.
#>
param([switch]$Elevato)

$ErrorActionPreference = 'Continue'   # gli errori li gestisco io, passo per passo
$ProgressPreference = 'SilentlyContinue'   # rende i download molto più veloci in PowerShell 5.1

# ---------------------------------------------------------------- impostazioni
$PYTHON_MINIMO   = [version]'3.10.0'
$PYTHON_VERSIONE = '3.12.10'               # versione installata se Python manca
$PYTHON_URL      = "https://www.python.org/ftp/python/$PYTHON_VERSIONE/python-$PYTHON_VERSIONE-amd64.exe"
$OLLAMA_URL_SETUP = 'https://ollama.com/download/OllamaSetup.exe'
$OLLAMA_MINIMO   = [version]'0.12.7'       # serve per i modelli qwen3-vl
$OLLAMA_API      = 'http://127.0.0.1:11434'
$PORTA_CHAT      = 8765
$SCRIPT_CHAT     = 'chat_ollama_web.py'

# modulo da importare -> pacchetto pip
$LIBRERIE = [ordered]@{
    'requests'     = 'requests'
    'ddgs'         = 'ddgs'
    'pypdf'        = 'pypdf'
    'docx'         = 'python-docx'
    'openpyxl'     = 'openpyxl'
    'cryptography' = 'cryptography'
}

# Modelli con agente (tools) e visione (vision). Il primo è quello scelto, gli altri sono riserve
# se il primo non si scarica. Dimensioni indicative del download.
$PROFILI = [ordered]@{
    '1' = @{ Ram = 8;  Titolo = '8 GB di RAM';  Modelli = @(
            @{ Nome = 'qwen3-vl:4b';      Gb = 3.3 },
            @{ Nome = 'ministral-3:3b';   Gb = 3.0 },
            @{ Nome = 'qwen3-vl:2b';      Gb = 1.9 }) }
    '2' = @{ Ram = 16; Titolo = '16 GB di RAM'; Modelli = @(
            @{ Nome = 'qwen3-vl:8b';      Gb = 6.1 },
            @{ Nome = 'ministral-3:8b';   Gb = 6.0 },
            @{ Nome = 'qwen3-vl:4b';      Gb = 3.3 }) }
    '3' = @{ Ram = 32; Titolo = '32 GB di RAM'; Modelli = @(
            @{ Nome = 'qwen3-vl:30b';     Gb = 20.0 },
            @{ Nome = 'mistral-small3.2:24b'; Gb = 15.0 },
            @{ Nome = 'qwen3-vl:8b';      Gb = 6.1 }) }
}

# ---------------------------------------------------------------- amministratore e criteri di esecuzione
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Write-Host 'Riavvio come amministratore: conferma la finestra di Windows...' -ForegroundColor Yellow
    $argomenti = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Elevato"
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argomenti -Verb RunAs -ErrorAction Stop
    } catch {
        Write-Host 'Permessi di amministratore non concessi: senza non posso installare. Riprova e premi Sì.' -ForegroundColor Red
        Read-Host 'Premi Invio per chiudere'
    }
    exit
}

# niente blocchi: in questa finestra gli script girano sempre
try { Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force } catch {}
# i file scaricati da internet hanno il "marchio del web": lo tolgo, così Windows non li blocca
Get-ChildItem -LiteralPath $PSScriptRoot -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

Set-Location -LiteralPath $PSScriptRoot
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$Host.UI.RawUI.WindowTitle = 'Installazione Chat Ollama'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$LOG = Join-Path $PSScriptRoot 'installa_log.txt'
try { Start-Transcript -Path $LOG -Append | Out-Null } catch {}

$TEMP = Join-Path $env:TEMP 'installa_chat_ollama'
New-Item -ItemType Directory -Force -Path $TEMP | Out-Null
$RIEPILOGO = New-Object System.Collections.Generic.List[string]

# ---------------------------------------------------------------- utilità
function Titolo($t)  { Write-Host ''; Write-Host "=== $t ===" -ForegroundColor Cyan }
function Ok($t)      { Write-Host "  [OK] $t" -ForegroundColor Green }
function Info($t)    { Write-Host "  $t" }
function Avviso($t)  { Write-Host "  [!] $t" -ForegroundColor Yellow }
function Errore($t)  { Write-Host "  [X] $t" -ForegroundColor Red }

function Chiedi-SiNo($domanda, [bool]$predefinito = $true) {
    $suff = if ($predefinito) { '[S/n]' } else { '[s/N]' }
    while ($true) {
        $r = (Read-Host "  $domanda $suff").Trim().ToLower()
        if ($r -eq '') { return $predefinito }
        if ($r -in @('s', 'si', 'sì', 'y', 'yes')) { return $true }
        if ($r -in @('n', 'no')) { return $false }
    }
}

function Scarica($url, $destinazione) {
    for ($i = 1; $i -le 3; $i++) {
        try {
            Info "Scarico $url (tentativo $i)..."
            Invoke-WebRequest -Uri $url -OutFile $destinazione -UseBasicParsing -ErrorAction Stop
            if ((Get-Item $destinazione).Length -gt 100KB) { return $true }
        } catch {
            try { Start-BitsTransfer -Source $url -Destination $destinazione -ErrorAction Stop; return $true } catch {}
            Avviso "Download non riuscito: $($_.Exception.Message)"
            Start-Sleep -Seconds (2 * $i)
        }
    }
    return $false
}

function Aggiorna-PathSessione {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = (@($m, $u) | Where-Object { $_ }) -join ';'
}

function Annuncia-Ambiente {
    # avvisa Windows che le variabili d'ambiente sono cambiate (le nuove finestre vedono il PATH nuovo)
    try {
        if (-not ('Win32.EnvAvviso' -as [type])) {
            Add-Type -Namespace Win32 -Name EnvAvviso -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
        }
        $r = [UIntPtr]::Zero
        [Win32.EnvAvviso]::SendMessageTimeout([IntPtr]0xffff, 0x1A, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$r) | Out-Null
    } catch {}
}

function Aggiungi-AlPath($cartella) {
    # aggiunge la cartella al PATH di sistema, se non c'è già (senza toccare le voci con %VARIABILI%)
    $chiave = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'
    $grezzo = (Get-Item $chiave).GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    $voci = @($grezzo -split ';' | Where-Object { $_.Trim() -ne '' })
    $norm = $cartella.TrimEnd('\')
    foreach ($v in $voci) {
        if ([Environment]::ExpandEnvironmentVariables($v).TrimEnd('\') -ieq $norm) { return $false }
    }
    $nuovo = (@($norm) + $voci) -join ';'   # in testa: vince sugli alias "python" del Microsoft Store
    Set-ItemProperty -Path $chiave -Name Path -Value $nuovo -Type ExpandString -ErrorAction Stop
    return $true
}

function Versione-Python($exe) {
    try {
        $v = & $exe -c "import sys;print('%d.%d.%d' % sys.version_info[:3])" 2>$null
        if ($LASTEXITCODE -eq 0 -and $v) { return [version]("$v".Trim()) }
    } catch {}
    return $null
}

function Trova-Python {
    $candidati = New-Object System.Collections.Generic.List[string]
    foreach ($c in @(Get-Command python.exe -All -ErrorAction SilentlyContinue)) { $candidati.Add($c.Source) }
    try {
        $p = & py -3 -c "import sys;print(sys.executable)" 2>$null
        if ($LASTEXITCODE -eq 0 -and $p) { $candidati.Add("$p".Trim()) }
    } catch {}
    foreach ($radice in @('HKLM:\SOFTWARE\Python\PythonCore', 'HKCU:\SOFTWARE\Python\PythonCore', 'HKLM:\SOFTWARE\WOW6432Node\Python\PythonCore')) {
        foreach ($k in @(Get-ChildItem $radice -ErrorAction SilentlyContinue)) {
            $ip = Get-Item (Join-Path $k.PSPath 'InstallPath') -ErrorAction SilentlyContinue
            if ($ip) {
                $exe = $ip.GetValue('ExecutablePath')
                if (-not $exe) { $exe = Join-Path ([string]$ip.GetValue('')) 'python.exe' }
                $candidati.Add($exe)
            }
        }
    }
    foreach ($schema in @("$env:ProgramFiles\Python3*\python.exe", "$env:LOCALAPPDATA\Programs\Python\Python3*\python.exe")) {
        foreach ($f in @(Get-ChildItem $schema -ErrorAction SilentlyContinue)) { $candidati.Add($f.FullName) }
    }
    $migliore = $null; $vMigliore = $null
    foreach ($exe in ($candidati | Select-Object -Unique)) {
        if (-not $exe -or -not (Test-Path -LiteralPath $exe)) { continue }
        if ($exe -like '*\WindowsApps\*') { continue }   # alias del Microsoft Store: non è un vero Python
        $v = Versione-Python $exe
        if ($v -and $v -ge $PYTHON_MINIMO -and (-not $vMigliore -or $v -gt $vMigliore)) { $migliore = $exe; $vMigliore = $v }
    }
    if ($migliore) { return @{ Exe = $migliore; Versione = $vMigliore } }
    return $null
}

function Trova-Ollama {
    $c = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($p in @("$env:LOCALAPPDATA\Programs\Ollama\ollama.exe", "$env:ProgramFiles\Ollama\ollama.exe")) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Ollama-Risponde {
    try { return Invoke-RestMethod -Uri "$OLLAMA_API/api/version" -TimeoutSec 3 -ErrorAction Stop } catch { return $null }
}

function Avvia-Ollama($exe) {
    if (Ollama-Risponde) { return $true }
    Info 'Avvio Ollama...'
    $app = Join-Path (Split-Path $exe) 'ollama app.exe'
    if (Test-Path -LiteralPath $app) { Start-Process -FilePath $app }
    else { Start-Process -FilePath $exe -ArgumentList 'serve' -WindowStyle Hidden }
    for ($i = 0; $i -lt 60; $i++) {
        Start-Sleep -Seconds 1
        if (Ollama-Risponde) { return $true }
    }
    return $false
}

function Versione-Ollama($exe) {
    $r = Ollama-Risponde
    $testo = if ($r) { $r.version } else { (& $exe --version 2>&1 | Out-String) }
    if ("$testo" -match '(\d+)\.(\d+)\.(\d+)') { return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" }
    return $null
}

function Installa-Ollama {
    $setup = Join-Path $TEMP 'OllamaSetup.exe'
    if (Scarica $OLLAMA_URL_SETUP $setup) {
        Info 'Installo Ollama (qualche minuto)...'
        $p = Start-Process -FilePath $setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-' -Wait -PassThru
        if ($p.ExitCode -eq 0) { return $true }
        Avviso "Il programma di installazione di Ollama ha restituito il codice $($p.ExitCode)."
    }
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Info 'Provo con winget...'
        & winget install -e --id Ollama.Ollama --silent --accept-package-agreements --accept-source-agreements
        return ($LASTEXITCODE -eq 0)
    }
    return $false
}

function Modelli-Installati {
    try { return @((Invoke-RestMethod -Uri "$OLLAMA_API/api/tags" -TimeoutSec 10 -ErrorAction Stop).models | ForEach-Object { $_.name }) } catch { return @() }
}

function Capacita-Modello($nome) {
    try {
        $corpo = @{ model = $nome } | ConvertTo-Json
        return @((Invoke-RestMethod -Uri "$OLLAMA_API/api/show" -Method Post -Body $corpo -ContentType 'application/json' -TimeoutSec 30 -ErrorAction Stop).capabilities)
    } catch { return @() }
}

function Cartella-Modelli {
    if ($env:OLLAMA_MODELS) { return $env:OLLAMA_MODELS }
    $m = [Environment]::GetEnvironmentVariable('OLLAMA_MODELS', 'User')
    if (-not $m) { $m = [Environment]::GetEnvironmentVariable('OLLAMA_MODELS', 'Machine') }
    if ($m) { return $m }
    return (Join-Path $env:USERPROFILE '.ollama\models')
}

function Spazio-LiberoGb($cartella) {
    try {
        $lettera = (Split-Path -Qualifier ([IO.Path]::GetFullPath($cartella))).TrimEnd(':')
        return [math]::Round((Get-PSDrive -Name $lettera).Free / 1GB, 1)
    } catch { return $null }
}

function Ip-DiRete {
    # l'indirizzo IPv4 della scheda che esce verso internet (quella con la rotta predefinita)
    try {
        $rotta = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction Stop | Sort-Object { $_.RouteMetric + $_.InterfaceMetric } | Select-Object -First 1
        $ip = Get-NetIPAddress -InterfaceIndex $rotta.InterfaceIndex -AddressFamily IPv4 -ErrorAction Stop |
              Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
        if ($ip) { return $ip.IPAddress }
    } catch {}
    return $null
}

function Ip-DelPc {
    try { return @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | ForEach-Object { $_.IPAddress }) } catch { return @() }
}

# ================================================================ inizio
Clear-Host
Write-Host 'Installazione di Chat Ollama' -ForegroundColor Cyan
Write-Host "Cartella: $PSScriptRoot"
Write-Host "Registro: $LOG"
if (-not [Environment]::Is64BitOperatingSystem) {
    Errore 'Serve Windows a 64 bit: Ollama non funziona su Windows a 32 bit.'
    Read-Host 'Premi Invio per chiudere'; exit 1
}
$os = Get-CimInstance Win32_OperatingSystem
$ramGb = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
Info "$($os.Caption) (build $($os.BuildNumber)), RAM: $ramGb GB"

# ---------------------------------------------------------------- 1. Python
Titolo '1/7  Python'
$py = Trova-Python
if ($py) {
    Ok "Python $($py.Versione) già installato: $($py.Exe) (non lo reinstallo)"
} else {
    Info "Python $PYTHON_MINIMO o più recente non trovato: installo Python $PYTHON_VERSIONE per tutti gli utenti."
    $setup = Join-Path $TEMP "python-$PYTHON_VERSIONE-amd64.exe"
    $installato = $false
    if (Scarica $PYTHON_URL $setup) {
        $p = Start-Process -FilePath $setup -Wait -PassThru -ArgumentList '/quiet', 'InstallAllUsers=1', 'PrependPath=1',
            'Include_pip=1', 'Include_launcher=1', 'InstallLauncherAllUsers=1', 'Include_test=0', 'Shortcuts=1'
        $installato = ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010)
        if (-not $installato) { Avviso "Il programma di installazione di Python ha restituito il codice $($p.ExitCode)." }
    }
    if (-not $installato -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        Info 'Provo con winget...'
        & winget install -e --id Python.Python.3.12 --scope machine --silent --accept-package-agreements --accept-source-agreements
    }
    Aggiorna-PathSessione
    $py = Trova-Python
    if (-not $py) {
        Errore 'Installazione di Python non riuscita. Installalo da https://www.python.org e rilancia questo programma.'
        Read-Host 'Premi Invio per chiudere'; exit 1
    }
    Ok "Python $($py.Versione) installato: $($py.Exe)"
    $RIEPILOGO.Add("Python $($py.Versione) installato")
}
# PATH: python e la cartella Scripts (pip) devono essere raggiungibili da qualsiasi finestra
$cartellaPy = Split-Path $py.Exe
$aggiunte = @()
foreach ($c in @($cartellaPy, (Join-Path $cartellaPy 'Scripts'))) { if (Aggiungi-AlPath $c) { $aggiunte += $c } }
if ($aggiunte.Count) {
    Annuncia-Ambiente; Aggiorna-PathSessione
    Ok ("Aggiunto al PATH di sistema: " + ($aggiunte -join ', '))
    $RIEPILOGO.Add('PATH di Python sistemato')
} else {
    Ok 'PATH di Python già a posto'
}
$PY = $py.Exe

# ---------------------------------------------------------------- 2. librerie Python
Titolo '2/7  Librerie Python per lo script'
& $PY -m pip --version *> $null
if ($LASTEXITCODE -ne 0) {
    Info 'pip manca: lo installo...'
    & $PY -m ensurepip --upgrade
}
$mancanti = @()
foreach ($modulo in $LIBRERIE.Keys) {
    & $PY -c "import $modulo" *> $null
    if ($LASTEXITCODE -eq 0) { Ok "$($LIBRERIE[$modulo]) già presente" } else { $mancanti += $LIBRERIE[$modulo] }
}
if ($mancanti.Count) {
    Info ("Installo: " + ($mancanti -join ', '))
    & $PY -m pip install --upgrade pip --disable-pip-version-check *> $null
    & $PY -m pip install --disable-pip-version-check @mancanti
    $falliti = @()
    foreach ($modulo in $LIBRERIE.Keys) {
        & $PY -c "import $modulo" *> $null
        if ($LASTEXITCODE -ne 0) { $falliti += $LIBRERIE[$modulo] }
    }
    if ($falliti.Count) { Avviso ("Non installati: " + ($falliti -join ', ') + ". Lo script ci riproverà da solo al primo avvio.") }
    else { Ok 'Librerie installate'; $RIEPILOGO.Add('Librerie Python installate: ' + ($mancanti -join ', ')) }
}

# ---------------------------------------------------------------- 3. Ollama
Titolo '3/7  Ollama'
$OLLAMA = Trova-Ollama
if ($OLLAMA) {
    Avvia-Ollama $OLLAMA | Out-Null
    $vO = Versione-Ollama $OLLAMA
    if ($vO -and $vO -lt $OLLAMA_MINIMO) {
        Avviso "Ollama $vO è troppo vecchio per i modelli con visione e agente (serve $OLLAMA_MINIMO o più recente)."
        if (Chiedi-SiNo 'Lo aggiorno? I modelli già scaricati restano' $true) {
            Get-Process -Name 'ollama app', 'ollama' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            if (Installa-Ollama) { $RIEPILOGO.Add('Ollama aggiornato') } else { Avviso 'Aggiornamento non riuscito: continuo con la versione installata.' }
            Aggiorna-PathSessione
            $OLLAMA = Trova-Ollama
        }
    } else {
        Ok "Ollama $vO già installato: $OLLAMA (non lo reinstallo)"
    }
} else {
    Info 'Ollama non trovato: lo installo.'
    if (-not (Installa-Ollama)) {
        Errore 'Installazione di Ollama non riuscita. Installalo da https://ollama.com/download e rilancia questo programma.'
        Read-Host 'Premi Invio per chiudere'; exit 1
    }
    Aggiorna-PathSessione
    $OLLAMA = Trova-Ollama
    if (-not $OLLAMA) { Errore 'Ollama installato ma non lo trovo.'; Read-Host 'Premi Invio per chiudere'; exit 1 }
    Ok "Ollama installato: $OLLAMA"
    $RIEPILOGO.Add('Ollama installato')
}
if (Avvia-Ollama $OLLAMA) { Ok "Ollama è in funzione su $OLLAMA_API (versione $(Versione-Ollama $OLLAMA))" }
else { Errore 'Ollama non risponde. Avvialo dal menu Start e rilancia questo programma.'; Read-Host 'Premi Invio per chiudere'; exit 1 }

# ---------------------------------------------------------------- 4. modello
Titolo '4/7  Modello con agente e visione delle immagini'
$vram = 0
try {
    foreach ($k in @(Get-ChildItem 'HKLM:\SYSTEM\ControlSet001\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' -ErrorAction SilentlyContinue)) {
        $q = $k.GetValue('HardwareInformation.qwMemorySize')
        if ($q) { $vram = [math]::Max($vram, [math]::Round([double]$q / 1GB)) }
    }
} catch {}
$consigliato = if ($ramGb -ge 28) { '3' } elseif ($ramGb -ge 14) { '2' } else { '1' }
Info ("RAM rilevata: $ramGb GB" + $(if ($vram) { ", memoria della scheda video: $vram GB" } else { '' }))
Write-Host ''
foreach ($k in $PROFILI.Keys) {
    $p = $PROFILI[$k]; $m = $p.Modelli[0]
    $nota = if ($k -eq $consigliato) { '  <- consigliato per questo PC' } else { '' }
    Write-Host ("  {0} - {1,-13} {2,-16} (circa {3} GB da scaricare){4}" -f $k, $p.Titolo, $m.Nome, $m.Gb, $nota)
}
Write-Host '  0 - Non installare nessun modello adesso'
$scelta = $null
while ($scelta -notin @('0', '1', '2', '3')) {
    $scelta = (Read-Host "  Scegli 1, 2, 3 oppure 0 (Invio = $consigliato)").Trim()
    if ($scelta -eq '') { $scelta = $consigliato }
}
$modelloFinale = $null
if ($scelta -ne '0') {
    $profilo = $PROFILI[$scelta]
    if ($profilo.Ram -gt $ramGb + 1) {
        Avviso "Hai scelto il modello per $($profilo.Ram) GB, ma questo PC ne ha ${ramGb}: sarà lento o potrebbe non partire."
        if (-not (Chiedi-SiNo 'Continuo lo stesso?' $false)) { $profilo = $PROFILI[$consigliato]; Info "Uso quello consigliato: $($profilo.Modelli[0].Nome)" }
    }
    $presenti = Modelli-Installati
    $giaPresente = $profilo.Modelli | Where-Object { $presenti -contains $_.Nome } | Select-Object -First 1
    if ($giaPresente) {
        Ok "$($giaPresente.Nome) è già installato (non lo riscarico)"
        $modelloFinale = $giaPresente.Nome
    } else {
        $cartellaModelli = Cartella-Modelli
        foreach ($m in $profilo.Modelli) {
            $libero = Spazio-LiberoGb $cartellaModelli
            if ($libero -ne $null -and $libero -lt ($m.Gb + 2)) {
                Avviso "Spazio libero insufficiente per $($m.Nome): servono circa $([math]::Ceiling($m.Gb + 2)) GB, liberi $libero GB ($cartellaModelli)."
                continue
            }
            Info "Scarico $($m.Nome) (circa $($m.Gb) GB): può richiedere parecchi minuti..."
            & $OLLAMA pull $m.Nome
            if ($LASTEXITCODE -eq 0) { $modelloFinale = $m.Nome; $RIEPILOGO.Add("Modello installato: $($m.Nome)"); break }
            Avviso "$($m.Nome) non scaricato: provo il successivo."
        }
    }
    if ($modelloFinale) {
        $cap = Capacita-Modello $modelloFinale
        $vede = $cap -contains 'vision'; $agente = $cap -contains 'tools'
        if ($vede -and $agente) { Ok "$modelloFinale pronto: agente (strumenti) e visione delle immagini" }
        else {
            Avviso ("$modelloFinale pronto, ma Ollama segnala: " + ($(if ($agente) { 'agente sì' } else { 'agente NO' })) + ', ' +
                    ($(if ($vede) { 'immagini sì' } else { 'immagini NO' })) + '.')
        }
    } else {
        Errore 'Nessun modello scaricato. Controlla la connessione e lo spazio su disco, poi rilancia: le parti già fatte verranno saltate.'
    }
} else {
    Info 'Nessun modello installato adesso.'
}

# ---------------------------------------------------------------- 5. preparo lo script
Titolo "5/7  Preparo $SCRIPT_CHAT"
$percorsoScript = Join-Path $PSScriptRoot $SCRIPT_CHAT
if (Test-Path -LiteralPath $percorsoScript) {
    $utf8 = New-Object Text.UTF8Encoding($false)
    $testo = [IO.File]::ReadAllText($percorsoScript, $utf8)
    $originale = $testo
    # Ollama gira su questo PC: lo script lo raggiunge sempre su 127.0.0.1
    $testo = [regex]::Replace($testo, '(?m)^OLLAMA_URL = "[^"]*"', "OLLAMA_URL = `"$OLLAMA_API`"")
    # indirizzo per gli altri dispositivi (telefono): deve essere un indirizzo di QUESTO PC
    $mIndirizzo = [regex]::Match($testo, '(?m)^INDIRIZZO = "([^"]*)"')
    if ($mIndirizzo.Success) {
        $attuale = $mIndirizzo.Groups[1].Value
        $ipPc = Ip-DelPc
        if ($attuale -in @('127.0.0.1', 'localhost')) {
            Ok 'La pagina è impostata per questo PC soltanto (127.0.0.1): la lascio così.'
        } elseif ($ipPc -contains $attuale) {
            Ok "Indirizzo di rete ${attuale}: è di questo PC, lo lascio."
        } else {
            $ip = Ip-DiRete
            if ($ip) {
                Avviso "Lo script usa $attuale, che non è un indirizzo di questo PC. L'indirizzo di questo PC è $ip."
                if (Chiedi-SiNo "Uso $ip (serve per aprire la chat dal telefono)?" $true) {
                    $testo = [regex]::Replace($testo, '(?m)^INDIRIZZO = "[^"]*"', "INDIRIZZO = `"$ip`"")
                }
            } else {
                Avviso "Non trovo l'indirizzo di rete di questo PC: la chat funzionerà solo su questo PC."
            }
        }
    }
    if ($testo -ne $originale) {
        $copia = "$percorsoScript.prima_installazione_$(Get-Date -Format 'yyyyMMdd_HHmmss').bak"
        Copy-Item -LiteralPath $percorsoScript -Destination $copia
        [IO.File]::WriteAllText($percorsoScript, $testo, $utf8)
        Ok "Impostazioni aggiornate (copia di prima: $(Split-Path $copia -Leaf))"
        $RIEPILOGO.Add("$SCRIPT_CHAT impostato per questo PC")
    } else {
        Ok 'Impostazioni già corrette'
    }
    & $PY -m py_compile $percorsoScript
    if ($LASTEXITCODE -eq 0) { Ok 'Lo script è integro (controllo di Python superato)' } else { Errore 'Python segnala un errore nello script: scarica di nuovo il file.' }
} else {
    Avviso "Non trovo $SCRIPT_CHAT in questa cartella. Mettilo accanto a questo file e rilancia, così lo preparo e creo l'icona."
}

# ---------------------------------------------------------------- 6. firewall e icona
Titolo '6/7  Firewall e icona sul desktop'
$nomeRegola = 'Chat Ollama (pagina web)'
if (Get-NetFirewallRule -DisplayName $nomeRegola -ErrorAction SilentlyContinue) {
    Ok 'Regola del firewall già presente'
} else {
    try {
        New-NetFirewallRule -DisplayName $nomeRegola -Direction Inbound -Action Allow -Protocol TCP `
            -LocalPort "$PORTA_CHAT-$($PORTA_CHAT + 9)" -Profile Private, Domain -ErrorAction Stop | Out-Null
        Ok "Firewall: aperte le porte $PORTA_CHAT-$($PORTA_CHAT + 9) solo sulle reti private (casa)"
        $RIEPILOGO.Add('Regola del firewall creata')
    } catch { Avviso "Regola del firewall non creata: $($_.Exception.Message)" }
}
$profiloRete = Get-NetConnectionProfile -ErrorAction SilentlyContinue | Select-Object -First 1
if ($profiloRete -and $profiloRete.NetworkCategory -eq 'Public') {
    Avviso "La rete '$($profiloRete.Name)' è impostata come Pubblica: il telefono non raggiungerà la chat."
    Info   '     Se è la rete di casa: Impostazioni > Rete e Internet > (la tua rete) > Tipo di profilo: Privata.'
}

if (Test-Path -LiteralPath $percorsoScript) {
    $avvio = Join-Path $PSScriptRoot 'Avvia Chat Ollama.bat'
    $contenuto = "@echo off`r`ncd /d `"%~dp0`"`r`n`"$PY`" `"$SCRIPT_CHAT`"`r`nif errorlevel 1 pause`r`n"
    [IO.File]::WriteAllText($avvio, $contenuto, (New-Object Text.ASCIIEncoding))
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $sc = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Chat Ollama.lnk'))
        $sc.TargetPath = $avvio
        $sc.WorkingDirectory = $PSScriptRoot
        $icona = Join-Path (Split-Path $OLLAMA) 'ollama app.exe'
        if (Test-Path -LiteralPath $icona) { $sc.IconLocation = "$icona,0" }
        $sc.Description = 'Avvia la chat con Ollama'
        $sc.Save()
        Ok "Icona 'Chat Ollama' creata sul desktop"
        # seconda icona: la stessa chat, ma senza finestra nera (si spegne dalle Impostazioni della pagina)
        $pywIcona = Join-Path (Split-Path $PY) 'pythonw.exe'
        if (Test-Path -LiteralPath $pywIcona) {
            $sc2 = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'Chat Ollama (senza finestra).lnk'))
            $sc2.TargetPath = $pywIcona
            $sc2.Arguments = "`"$percorsoScript`" --senza-finestra"
            $sc2.WorkingDirectory = $PSScriptRoot
            if (Test-Path -LiteralPath $icona) { $sc2.IconLocation = "$icona,0" }
            $sc2.Description = 'Avvia la chat con Ollama senza finestra e apre la pagina'
            $sc2.Save()
            Ok "Icona 'Chat Ollama (senza finestra)' creata sul desktop"
        }
    } catch { Avviso "Icona non creata: $($_.Exception.Message)" }
    Ok "Per avviare la chat: doppio clic su 'Chat Ollama' sul desktop (o su 'Avvia Chat Ollama.bat')"
}

# ---------------------------------------------------------------- 7. avvio automatico
Titolo '7/7  Avvio automatico con Windows'
$NOME_ATTIVITA = 'Chat Ollama'
$avvioAuto = $false
$codice = $null
if (Test-Path -LiteralPath $percorsoScript) {
    $attivita = Get-ScheduledTask -TaskName $NOME_ATTIVITA -ErrorAction SilentlyContinue
    $domanda = if ($attivita) { "L'avvio automatico è già attivo. Lo lascio attivo?" }
               else { 'Vuoi che la chat parta da sola, senza finestra, quando entri in Windows?' }
    if (Chiedi-SiNo $domanda $true) {
        # senza finestra il codice casuale non si vedrebbe: serve un codice fisso, salvato accanto allo script
        $fileCodice = Join-Path $PSScriptRoot 'codice_accesso.txt'
        if (Test-Path -LiteralPath $fileCodice) { $codice = "$(Get-Content -LiteralPath $fileCodice -Raw -ErrorAction SilentlyContinue)".Trim() }
        if ($codice) {
            Ok "Codice di accesso già scelto: $codice"
            if (-not (Chiedi-SiNo 'Lo tengo?' $true)) { $codice = $null }
        }
        while (-not $codice) {
            $r = (Read-Host '  Scegli il codice di accesso per telefono e altri PC (almeno 6 caratteri; Invio = lo creo io)').Trim()
            if ($r -eq '') {
                $b = New-Object byte[] 4
                [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
                $codice = ([BitConverter]::ToUInt32($b, 0) % 1000000).ToString('D6')
            } elseif ($r.Length -ge 6 -and $r -notmatch '\s') { $codice = $r }
            else { Avviso 'Servono almeno 6 caratteri, senza spazi.' }
        }
        [IO.File]::WriteAllText($fileCodice, "$codice`r`n", (New-Object Text.UTF8Encoding($false)))
        Ok "Codice di accesso: $codice (salvato in codice_accesso.txt, accanto allo script)"
        $pyw = Join-Path (Split-Path $PY) 'pythonw.exe'
        if (-not (Test-Path -LiteralPath $pyw)) { Avviso 'pythonw.exe non trovato: uso python.exe, quindi si vedrà una finestra.'; $pyw = $PY }
        $utente = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        try {
            $azione = New-ScheduledTaskAction -Execute $pyw -Argument "`"$percorsoScript`" --sfondo" -WorkingDirectory $PSScriptRoot
            $trigger = New-ScheduledTaskTrigger -AtLogOn -User $utente
            $trigger.Delay = 'PT20S'   # lascia il tempo a Ollama e alla rete di partire
            $impost = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
                -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
            $chi = New-ScheduledTaskPrincipal -UserId $utente -LogonType Interactive -RunLevel Limited
            Register-ScheduledTask -TaskName $NOME_ATTIVITA -Action $azione -Trigger $trigger -Settings $impost -Principal $chi `
                -Description "Avvia la chat con Ollama senza finestra all'accesso a Windows" -Force -ErrorAction Stop | Out-Null
            Ok "Avvio automatico attivo: la chat parte da sola 20 secondi dopo l'accesso a Windows"
            Info "Messaggi ed errori dell'avvio automatico: chat_ollama_avvio.log, accanto allo script."
            $avvioAuto = $true
            $RIEPILOGO.Add('Avvio automatico con Windows attivato')
        } catch { Avviso "Avvio automatico non attivato: $($_.Exception.Message)" }
    } elseif ($attivita) {
        Unregister-ScheduledTask -TaskName $NOME_ATTIVITA -Confirm:$false -ErrorAction SilentlyContinue
        Ok 'Avvio automatico tolto'
        $RIEPILOGO.Add('Avvio automatico con Windows disattivato')
    } else {
        Info 'Avvio automatico non attivato: la chat parte con l''icona sul desktop.'
    }
}

# ---------------------------------------------------------------- fine
Titolo 'Fatto\'
if ($RIEPILOGO.Count) { foreach ($r in $RIEPILOGO) { Ok $r } } else { Ok 'Era già tutto installato: non ho cambiato niente.' }
if ($modelloFinale) { Info "Nella chat scegli il modello '$modelloFinale' dall'elenco in alto." }
try { Stop-Transcript | Out-Null } catch {}
Write-Host ''
$mIp = [regex]::Match([IO.File]::ReadAllText($percorsoScript), '(?m)^INDIRIZZO = "([^"]*)"')
if ($mIp.Success -and $mIp.Groups[1].Value -notin @('127.0.0.1', 'localhost')) {
    Info ("Dal telefono: https://$($mIp.Groups[1].Value):$PORTA_CHAT/" + $(if ($codice) { "  (codice: $codice)" } else { '' }))
}
if ((Test-Path -LiteralPath $percorsoScript) -and (Chiedi-SiNo 'Avvio la chat adesso?' $true)) {
    if ($avvioAuto) {
        # parte come farà ogni volta all'accesso: senza finestra
        Start-ScheduledTask -TaskName $NOME_ATTIVITA -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 6
        Start-Process -FilePath 'explorer.exe' -ArgumentList "http://localhost:$PORTA_CHAT/"
    } else {
        # la avvio come utente normale tramite Esplora risorse, non dentro questa finestra da amministratore
        Start-Process -FilePath 'explorer.exe' -ArgumentList "`"$(Join-Path $PSScriptRoot 'Avvia Chat Ollama.bat')`""
    }
} else {
    Read-Host 'Premi Invio per chiudere'
}
