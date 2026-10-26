# Starts the FarmTrack backend so a phone on the SAME Wi-Fi can use it (plain http, port 8005).
#   - real crop + disease models from backend\storage\models (copied, no download), CPU, first scan loads them (~15 s)
#   - no cloud calls: mock advice composer (validated templates), no OpenAI, no Google TTS (the phone speaks)
#   - demo clock 12 May 2026 (apple season), demo farmers f001..f050, password farm1234
# Run:  powershell -ExecutionPolicy Bypass -File scripts/start_backend_for_phone.ps1      (stop with Ctrl+C)
#       -Port 8010   use another port (default 8005)
#       -Force       also stop a program that is NOT this backend if it holds the port (default: refuse and say what it is)
# Every start first stops an older copy of this backend that still listens on the port, so running the script again is a restart.
# Windows asks once whether Python may accept network connections: choose "Allow" (private networks).
[CmdletBinding()]
param(
    [int]$Port = 8005,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot      # the project folder (this script lives in scripts/)
$backend = Join-Path $root 'backend'
# A separate copy of the Python interpreter (C:\siva\tools\python313, a plain copy of the installed Python 3.13): the Windows
# firewall of this laptop has a Block rule for the installed python.exe, and rules match the program's path. The packages come
# from the backend's venv and from the torch venv (data\model_test\.venv) through PYTHONPATH.
$py = 'C:\siva\tools\python313\python.exe'
if (-not (Test-Path $py)) { $py = Join-Path $root 'data\model_test\.venv\Scripts\python.exe'; Write-Warning 'python copy not found: using the venv python (the firewall may block it)' }
$env:PYTHONPATH = (Join-Path $backend '.venv\Lib\site-packages') + ';' + (Join-Path $root 'data\model_test\.venv\Lib\site-packages')
$env:ENV = 'dev'
$env:LLM_PROVIDER = 'mock'
$env:OPENAI_API_KEY = ''
$env:TTS_PROVIDER = 'null'
$env:GOOGLE_TTS_API_KEY = ''
$env:EMBEDDINGS_PROVIDER = 'hash'
$env:VECTOR_STORE = 'memory'
$env:CROP_ID_PROVIDER = 'model'
$env:DISEASE_PROVIDER = 'model'
# DEMO ONLY (27 Oct 2026): apple answers come from the locally trained demo model alone (4 classes: scab, Marssonina, Alternaria, healthy).
# It was trained with 30 web photos of unknown licence: never ship it. Delete the next line to go back to the downloaded models.
$env:DISEASE_MODEL_DIR = Join-Path $root 'data\training\output\apple_leaf_demo'
# Owner decision 19 Oct 2026 (CLAUDE.md): medicine advice for every disease with chemical control. Without it only scab gets advice and
# Marssonina / Alternaria show "Not sure yet". Set to '' to go back to scab only. Wrong disease = wrong medicine advice: demo photos only.
$env:RULES_AUTO_ADVICE_DISEASES = '*'
$env:STORAGE_DIR = Join-Path $backend 'storage'
$env:PUSH_PROVIDER = 'log'
$env:ZOHO_PROVIDER = 'mock'
$env:IOT_PROVIDER = 'mock'
$env:WEATHER_PROVIDER = 'csv'
$env:OTP_LOGIN_ENABLED = 'false'
$env:HF_HUB_OFFLINE = '1'          # the weights are already in storage\models; never go to the internet

# Free the port. An older copy of this backend (python running "uvicorn app.main") is stopped; any other program is left alone and the
# script stops with a message, unless -Force. (Not named $pid: that is a read-only automatic variable in PowerShell.)
function Stop-PortHolder {
    param([int]$Port, [switch]$Force)
    $holders = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique | Where-Object { $_ -gt 4 })      # 0 and 4 are the system, never touch them
    foreach ($procId in $holders) {
        $info = Get-CimInstance Win32_Process -Filter "ProcessId = $procId" -ErrorAction SilentlyContinue
        $cmd = if ($info) { [string]$info.CommandLine } else { '' }
        $name = if ($info) { $info.Name } else { 'unknown' }
        $isBackend = ($cmd -match 'uvicorn') -and ($cmd -match 'app\.main')
        if (-not $isBackend -and -not $Force) {
            throw "Port $Port is used by another program (pid $procId, $name): $cmd`nI did not stop it. Close it yourself, use another port (-Port 8010) or run again with -Force."
        }
        Write-Host "Port ${Port} is in use by pid $procId ($name): stopping it." -ForegroundColor Yellow
        try { Stop-Process -Id $procId -Force } catch { throw "Could not stop pid $procId ($name): $($_.Exception.Message). Close it yourself (an administrator window may be needed)." }
    }
    for ($i = 0; $i -lt 20; $i++) {                                                          # wait up to 10 s until the port is really free
        if (-not (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Where-Object { $_.OwningProcess -gt 4 })) { return }
        Start-Sleep -Milliseconds 500
    }
    throw "Port $Port is still in use after stopping the old process. Wait a few seconds and run the script again."
}
Stop-PortHolder -Port $Port -Force:$Force

$ips = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -ExpandProperty IPAddress
Write-Host ''
Write-Host 'In the app, on the login screen, tap "Server" and type one of these (phone and PC on the same Wi-Fi):' -ForegroundColor Green
foreach ($ip in $ips) { Write-Host "    http://${ip}:$Port" -ForegroundColor Green }
Write-Host 'Login: user name f001, password farm1234' -ForegroundColor Green
Write-Host ''
Set-Location $backend
& $py -m uvicorn app.main:app --host 0.0.0.0 --port $Port
