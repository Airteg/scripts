<#
.SYNOPSIS
  Який Android-пристрій підключено до комп'ютера і чи він готовий до роботи.
  Окремо — чи не зайнятий порт Metro 8081.

.DESCRIPTION
  Запуск:  device-check
  Працює і в PowerShell 7, і у вбудованому Windows PowerShell 5.1 (файл збережено з BOM).

  Очікується рівно один пристрій. Якщо пристрою немає, він не авторизований,
  offline, заблокований або з вимкненим екраном, підключено кілька пристроїв —
  скрипт пише, що зробити, і чекає: Enter — перевірити ще раз, Q — вийти.

  Порт 8081 перевіряється завжди і показується окремим блоком у кінці:
  хто його тримає (PID, програма, команда запуску) і як звільнити.

  adb шукається в PATH, потім у ANDROID_HOME, ANDROID_SDK_ROOT
  і %LOCALAPPDATA%\Android\Sdk\platform-tools.

  Код виходу: 0 — пристрій готовий, 1 — ні.
#>
[CmdletBinding()]
param()

$Port = 8081

# ---------------- Порт Metro ----------------
function Show-Port {
    Write-Host ''
    Write-Host "---- Порт $Port (Metro) ----"
    $pids = @()
    try {
        $pids = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop |
                  Select-Object -ExpandProperty OwningProcess -Unique)
    } catch {
        # Немає слухача (або недоступний модуль) — запасний шлях через netstat
        $pids = @(netstat -ano | Select-String "^\s*TCP\s+\S+:$Port\s+(0\.0\.0\.0|\[::\]):0\s+\S+\s+(\d+)\s*$" |
                  ForEach-Object { [int]$_.Matches[0].Groups[2].Value } | Select-Object -Unique)
    }
    if (-not $pids) { Write-Host "Вільний." -ForegroundColor Green; return }

    foreach ($id in $pids) {
        $p   = Get-Process -Id $id -ErrorAction SilentlyContinue
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
        $cmd = if ($cim -and $cim.CommandLine) { $cim.CommandLine } else { '(команда недоступна)' }
        if ($cmd.Length -gt 160) { $cmd = $cmd.Substring(0, 160) + '…' }
        $isMetro = $cmd -match 'expo|metro|react-native'

        Write-Host "ЗАЙНЯТИЙ" -ForegroundColor Red
        Write-Host ("  Процес:  {0}  PID {1}" -f $(if ($p) { $p.ProcessName } else { '?' }), $id)
        try { if ($p -and $p.StartTime) { Write-Host ("  Запущено: {0:dd.MM HH:mm}" -f $p.StartTime) } } catch { }
        Write-Host  "  Команда: $cmd"
        if ($isMetro) {
            Write-Host "  Схоже, це Metro від обірваного сеансу." -ForegroundColor Yellow
        } else {
            Write-Host "  Це не схоже на Metro — перевірте, що це за програма, перш ніж зупиняти." -ForegroundColor Yellow
        }
        Write-Host "  Звільнити:  Stop-Process -Id $id"
    }
}

# ---------------- adb ----------------
$adb = $null
$cmdAdb = Get-Command adb -ErrorAction SilentlyContinue
if ($cmdAdb) { $adb = $cmdAdb.Source }
else {
    foreach ($sdk in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk'))) {
        if ($sdk) {
            $c = Join-Path $sdk 'platform-tools\adb.exe'
            if (Test-Path -LiteralPath $c) { $adb = $c; break }
        }
    }
}
if (-not $adb) {
    Write-Host "adb не знайдено (ні в PATH, ні в Android SDK)." -ForegroundColor Red
    Show-Port
    exit 1
}

function Get-Devices {
    & $adb start-server 2>$null | Out-Null
    $out = & $adb devices -l 2>$null
    foreach ($l in $out) {
        if ($l -match '^\s*\*' -or $l -match '^List of devices' -or -not $l.Trim()) { continue }
        if ($l -match '^(\S+)\s+(.+?)(\s+(usb:|product:|model:|device:|transport_id:).*)?$') {
            $serial = $Matches[1]; $state = $Matches[2].Trim(); $rest = "$($Matches[3])"
            $model  = if ($rest -match 'model:(\S+)') { $Matches[1] -replace '_',' ' } else { '' }
            [pscustomobject]@{ Serial = $serial; State = $state; Model = $model }
        }
    }
}

# $true — заблоковано / екран вимкнений, $false — розблоковано, $null — не вдалося визначити
function Test-Locked([string]$s) {
    $wake = $null
    $pw = & $adb -s $s shell dumpsys power 2>$null
    $m  = $pw | Select-String 'mWakefulness=(\w+)' | Select-Object -First 1
    if ($m) { $wake = $m.Matches[0].Groups[1].Value }

    $kg = $null
    $hits = & $adb -s $s shell dumpsys window 2>$null |
            Select-String '(mDreamingLockscreen|mKeyguardShowing|isKeyguardShowing|mShowingLockscreen)=(true|false)'
    if (-not $hits) {
        $hits = & $adb -s $s shell dumpsys activity activities 2>$null |
                Select-String '(mKeyguardShowing)=(true|false)'
    }
    if ($hits) { $kg = @($hits | ForEach-Object { $_.Matches[0].Groups[2].Value }) -contains 'true' }

    if ($wake -and $wake -ne 'Awake') { return $true }
    if ($null -ne $kg) { return $kg }
    if ($wake) { return $false }
    return $null
}

# ---------------- Основний цикл ----------------
$ready = $null
while ($true) {
    $devs = @(Get-Devices)
    $msg  = $null

    if ($devs.Count -eq 0) {
        $msg = "Пристрою немає. Підключіть кабель і розблокуйте телефон.`n" +
               "Якщо на телефоні з'явиться запит «Дозволити налагодження USB?» — дозвольте."
    }
    elseif ($devs.Count -gt 1) {
        $msg = "Підключено пристроїв: $($devs.Count), очікується один. Від'єднайте зайві:`n" +
               (($devs | ForEach-Object { "  $($_.Serial)  $($_.State)  $($_.Model)" }) -join "`n")
    }
    else {
        $d = $devs[0]
        switch ($d.State) {
            'device' {
                $lock = Test-Locked $d.Serial
                if ($lock -eq $true) {
                    $msg = "Пристрій $($d.Model) підключено, але екран вимкнений або заблокований.`n" +
                           "Розблокуйте телефон (палець, обличчя або PIN)."
                } else {
                    $d | Add-Member -NotePropertyName Lock -NotePropertyValue $lock
                    $ready = $d
                }
            }
            'unauthorized' {
                $msg = "Пристрій не авторизований. Розблокуйте телефон і підтвердьте`n" +
                       "запит «Дозволити налагодження USB?» (можна поставити «Завжди дозволяти з цього комп'ютера»)."
            }
            'offline' {
                $msg = "Пристрій offline. Розблокуйте телефон; якщо не допоможе — перепідключіть кабель."
            }
            default {
                $msg = "Пристрій у стані «$($d.State)». Розблокуйте телефон або перепідключіть кабель."
            }
        }
    }

    if ($ready) { break }

    Write-Host ''
    Write-Host $msg -ForegroundColor Yellow
    $k = Read-Host 'Enter — перевірити ще раз, Q — вийти'
    if ($k -match '^\s*[qQйЙ]') { break }
}

# ---------------- Результат ----------------
Write-Host ''
if ($ready) {
    $props = & $adb -s $ready.Serial shell 'getprop ro.product.manufacturer; getprop ro.product.model; getprop ro.build.version.release; getprop ro.build.version.sdk' 2>$null
    $props = @($props | ForEach-Object { "$_".Trim() })
    $conn  = if ($ready.Serial -match ':\d+$' -or $ready.Serial -match '_adb-tls-') { 'Wi-Fi' }
             elseif ($ready.Serial -like 'emulator-*') { 'емулятор' } else { 'USB' }
    $screen = if ($ready.Lock -eq $false) { 'розблоковано' } else { 'не вдалося визначити' }

    Write-Host "---- Пристрій ----"
    Write-Host ("Готовий:   {0} {1}" -f $props[0], $props[1]) -ForegroundColor Green
    Write-Host ("Android:   {0} (SDK {1})" -f $props[2], $props[3])
    Write-Host  "Серійний:  $($ready.Serial)"
    Write-Host  "Зв'язок:   $conn"
    Write-Host  "Екран:     $screen"
} else {
    Write-Host "Пристрій не готовий." -ForegroundColor Red
}

Show-Port
if ($ready) { exit 0 } else { exit 1 }
