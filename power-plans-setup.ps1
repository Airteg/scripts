#Requires -RunAsAdministrator
<#
  power-plans-setup.ps1 — створює (або перестворює) дві власні схеми живлення:
    • "Nitro — Максимум"  — на основі «Максимальна продуктивність» (Ultimate Performance)
    • "Nitro — Економія"  — на основі «Енергозбереження» (Power saver)
  Схеми мають сталі GUID, тому скрипт можна запускати повторно: стара копія
  видаляється і створюється заново з актуальними налаштуваннями.
  Запуск: PowerShell від адміністратора →  power-plans-setup
  Перемикання між схемами (без адміністратора) — скрипт power-mode.
#>

$ErrorActionPreference = 'Stop'

# --- Сталі GUID (ті самі, що й у power-mode.ps1) ---
$GuidMax = '5f1a3c2e-7b4d-4e8a-9c61-2d0b7e9a4f11'
$GuidEco = '9d2e6b4a-1c3f-4a7e-8b52-6e0f3d1c7a22'

# --- Вбудовані шаблони Windows ---
$TplUltimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'   # Максимальна продуктивність
$TplHigh     = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'   # Висока продуктивність
$TplSaver    = 'a1841308-3542-4836-ad75-ed4bd1d74bdb'   # Енергозбереження
$TplBalanced = '381b4222-f694-41f0-9685-ff5bb260df2e'   # Збалансований

# --- Підгрупи / параметри без псевдонімів у powercfg ---
$SubUsb       = '2a737441-1930-4402-8d77-b2bebba308a3'
$UsbSuspend   = '48e6b7a6-50f5-4782-a5d4-53bb8f07e226'  # 0 = вимкнено, 1 = увімкнено
$SubWireless  = '19cbb8fa-5279-450e-9fac-8a3d5fedd0c1'
$WirelessMode = '12bbebe6-58d6-4636-95bb-3217ef867c1a'  # 0 = макс. продуктивність … 3 = макс. економія

# --- Ліміт процесора для «Економії» (у %). Будь-що < 100 вимикає Turbo Boost ---
$EcoCpuMax = 50

function Invoke-Powercfg {
    param([Parameter(ValueFromRemainingArguments)][string[]]$PcArgs)
    $out = & powercfg.exe @PcArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "powercfg $($PcArgs -join ' ') → $($out -join ' ')" }
    $out
}

function Test-Plan([string]$Guid) {
    [bool]((powercfg.exe /list) -match [regex]::Escape($Guid))
}

function Get-ActiveGuid {
    if (((powercfg.exe /getactivescheme) -join ' ') -match'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})') { $Matches[1] }
}

function New-PlanFrom([string[]]$Sources, [string]$NewGuid) {
    foreach ($src in $Sources) {
        & powercfg.exe /duplicatescheme $src $NewGuid *> $null
        if ($LASTEXITCODE -eq 0) { return $src }
    }
    throw "Не вдалося створити схему $NewGuid з жодного шаблону: $($Sources -join ', ')"
}

# Встановлює значення окремо для мережі (AC) і батареї (DC). Якщо параметра
# на цьому залізі немає — лише попередження, скрипт іде далі.
function Set-PlanValue([string]$Guid, [string]$Sub, [string]$Setting, [int]$Ac, [int]$Dc, [string]$Label) {
    try {
        Invoke-Powercfg /setacvalueindex $Guid $Sub $Setting $Ac | Out-Null
        Invoke-Powercfg /setdcvalueindex $Guid $Sub $Setting $Dc | Out-Null
        Write-Host ("    {0,-38} мережа: {1,-6} батарея: {2}" -f $Label, $Ac, $Dc)
    } catch {
        Write-Warning "    $Label — не встановлено: $($_.Exception.Message)"
    }
}

function Reset-Plan([string]$Guid, [string[]]$Sources, [string]$Name, [string]$Description) {
    $active = Get-ActiveGuid
    $wasActive = $active -eq $Guid
    if (Test-Plan $Guid) {
        if ($wasActive) { Invoke-Powercfg /setactive $TplBalanced | Out-Null }
        Invoke-Powercfg /delete $Guid | Out-Null
        Write-Host "  Стару копію «$Name» видалено."
    }
    $src = New-PlanFrom $Sources $Guid
    Invoke-Powercfg /changename $Guid $Name $Description | Out-Null
    Write-Host "  Створено «$Name» (шаблон $src)"
    return $wasActive
}

# ================= Nitro — Максимум =================
Write-Host "`n[1/2] Nitro — Максимум" -ForegroundColor Cyan
$maxWasActive = Reset-Plan $GuidMax @($TplUltimate, $TplHigh, $TplBalanced) 'Nitro — Максимум' `
    'Максимальна продуктивність: процесор 100 %, агресивний Turbo, без енергозбереження PCIe/USB/Wi-Fi, без сну від мережі.'

# Процесор
Set-PlanValue $GuidMax SUB_PROCESSOR PROCTHROTTLEMIN 100 100 'Мін. стан процесора, %'
Set-PlanValue $GuidMax SUB_PROCESSOR PROCTHROTTLEMAX 100 100 'Макс. стан процесора, %'
Set-PlanValue $GuidMax SUB_PROCESSOR PERFBOOSTMODE   2   2   'Turbo (2 = агресивний)'
Set-PlanValue $GuidMax SUB_PROCESSOR PERFEPP         0   0   'EPP (0 = продуктивність)'
Set-PlanValue $GuidMax SUB_PROCESSOR SYSCOOLPOL      1   1   'Охолодження (1 = активне)'
# Периферія
Set-PlanValue $GuidMax SUB_PCIEXPRESS ASPM           0   0   'PCIe ASPM (0 = вимкнено)'
Set-PlanValue $GuidMax $SubUsb $UsbSuspend           0   0   'Призупинення USB (0 = вимкнено)'
Set-PlanValue $GuidMax $SubWireless $WirelessMode    0   0   'Wi-Fi (0 = макс. продуктивність)'
Set-PlanValue $GuidMax SUB_DISK DISKIDLE             0   0   'Вимкнення диска, с (0 = ніколи)'
# Екран і сон (секунди)
Set-PlanValue $GuidMax SUB_VIDEO VIDEOIDLE         900 300   'Вимкнення екрана, с'
Set-PlanValue $GuidMax SUB_SLEEP STANDBYIDLE         0 900   'Сон, с (0 = ніколи)'

# ================= Nitro — Економія =================
Write-Host "`n[2/2] Nitro — Економія" -ForegroundColor Cyan
$ecoWasActive = Reset-Plan $GuidEco @($TplSaver, $TplBalanced) 'Nitro — Економія' `
    "Мінімальне споживання: процесор до $EcoCpuMax %, без Turbo, пасивне охолодження, енергозбереження PCIe/USB/Wi-Fi."

# Процесор
Set-PlanValue $GuidEco SUB_PROCESSOR PROCTHROTTLEMIN 5          5          'Мін. стан процесора, %'
Set-PlanValue $GuidEco SUB_PROCESSOR PROCTHROTTLEMAX $EcoCpuMax $EcoCpuMax 'Макс. стан процесора, %'
Set-PlanValue $GuidEco SUB_PROCESSOR PERFBOOSTMODE   0          0          'Turbo (0 = вимкнено)'
Set-PlanValue $GuidEco SUB_PROCESSOR PERFEPP         100        100        'EPP (100 = економія)'
Set-PlanValue $GuidEco SUB_PROCESSOR SYSCOOLPOL      0          0          'Охолодження (0 = пасивне)'
# Периферія
Set-PlanValue $GuidEco SUB_PCIEXPRESS ASPM           2   2   'PCIe ASPM (2 = макс. економія)'
Set-PlanValue $GuidEco $SubUsb $UsbSuspend           1   1   'Призупинення USB (1 = увімкнено)'
Set-PlanValue $GuidEco $SubWireless $WirelessMode    2   2   'Wi-Fi (2 = середня економія)'
Set-PlanValue $GuidEco SUB_DISK DISKIDLE           600 300   'Вимкнення диска, с'
# Екран і сон (секунди)
Set-PlanValue $GuidEco SUB_VIDEO VIDEOIDLE         600 180   'Вимкнення екрана, с'
Set-PlanValue $GuidEco SUB_SLEEP STANDBYIDLE      1800 600   'Сон, с'

# Якщо одна зі схем була активною до перестворення — повертаємо її
if ($maxWasActive) { Invoke-Powercfg /setactive $GuidMax | Out-Null }
elseif ($ecoWasActive) { Invoke-Powercfg /setactive $GuidEco | Out-Null }

Write-Host "`nГотово. Поточні схеми:" -ForegroundColor Green
powercfg.exe /list
Write-Host "`nПеремикання: power-mode max | power-mode eco | power-mode bal"
