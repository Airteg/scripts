<#
  battery-watch.ps1 — поточне споживання від батареї (Вт) і прогноз роботи.
    battery-watch            — замір кожні 5 с, доки не натиснеш Ctrl+C
    battery-watch 10 12      — кожні 10 с, 12 замірів (2 хв), у кінці — середнє
  Права адміністратора не потрібні. Дані — з драйвера батареї (root\wmi),
  контролер оновлює їх раз на кілька секунд, тому сусідні рядки можуть збігатися.
#>
param([int]$Seconds = 5, [int]$Count = 0)

# powercfg пише в DOS-кодуванні без «і», тому відомі схеми називаємо за GUID
$KnownPlans = @{
    '5f1a3c2e-7b4d-4e8a-9c61-2d0b7e9a4f11' = 'Nitro — Максимум'
    '9d2e6b4a-1c3f-4a7e-8b52-6e0f3d1c7a22' = 'Nitro — Економія'
    '381b4222-f694-41f0-9685-ff5bb260df2e' = 'Збалансований'
}
function Get-ActivePlanName {
    $a = (powercfg.exe /getactivescheme) -join ' '
    if ($a -match '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})' -and $KnownPlans.ContainsKey($Matches[1])) {
        return $KnownPlans[$Matches[1]]
    }
    if ($a -match '\((.+)\)') { $Matches[1] } else { '?' }
}

# Стан живлення NVIDIA з диспетчера пристроїв (D0 = працює, D3 = спить).
# Читання властивості не будить відеокарту, на відміну від nvidia-smi.
$nvDev = Get-PnpDevice -Class Display -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object FriendlyName -like '*NVIDIA*' | Select-Object -First 1
function Get-NvidiaState {
    if (-not $nvDev) { return '—' }
    $p = Get-PnpDeviceProperty -InstanceId $nvDev.InstanceId -KeyName DEVPKEY_Device_PowerData -ErrorAction SilentlyContinue
    if (-not $p -or -not $p.Data -or $p.Data.Length -lt 8) { return '?' }
    $s = [BitConverter]::ToInt32([byte[]]$p.Data, 4)   # PD_MostRecentPowerState: 1 = D0 … 4 = D3
    if ($s -ge 1) { 'D' + ($s - 1) } else { '?' }
}

$fullInfo = Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction SilentlyContinue |
    Select-Object -First 1
$fullWh = if ($fullInfo) { [math]::Round($fullInfo.FullChargedCapacity / 1000, 1) } else { 0 }

Write-Host "Повна ємність батареї: $fullWh Вт·год   Інтервал: $Seconds с" -ForegroundColor Cyan
Write-Host ('{0,-8} {1,-18} {2,-8} {3,10} {4,14} {5,5} {6,9} {7,7}' -f 'Час', 'Схема', 'Живлення', 'Спож., Вт', 'Залиш., Вт·год', '%', 'Прогноз', 'NVIDIA')

$rates = [System.Collections.Generic.List[double]]::new()
$i = 0
try {
    while ($Count -eq 0 -or $i -lt $Count) {
        $b = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -ErrorAction Stop | Select-Object -First 1
        $remWh  = [math]::Round($b.RemainingCapacity / 1000, 1)
        $pct    = if ($fullWh -gt 0) { [math]::Round(100 * $remWh / $fullWh) } else { '?' }
        $source = if ($b.PowerOnline) { 'мережа' } else { 'батарея' }
        $rateW  = [math]::Round($b.DischargeRate / 1000, 1)
        $eta    = '—'
        if (-not $b.PowerOnline -and $b.DischargeRate -gt 0) {
            $rates.Add($rateW)
            $t   = [timespan]::FromHours($b.RemainingCapacity / $b.DischargeRate)
            $eta = '{0}:{1:00}' -f [int][math]::Floor($t.TotalHours), $t.Minutes
        }
        Write-Host ('{0,-8} {1,-18} {2,-8} {3,10} {4,14} {5,5} {6,9} {7,7}' -f (Get-Date -Format 'HH:mm:ss'), (Get-ActivePlanName), $source, $rateW, $remWh, $pct, $eta, (Get-NvidiaState))
        $i++
        if ($Count -eq 0 -or $i -lt $Count) { Start-Sleep -Seconds $Seconds }
    }
}
finally {
    if ($rates.Count -gt 0) {
        # Медіана — сталий рівень: поодинокі сплески (запуск команди, перемикання) її не зсувають
        $sorted = $rates | Sort-Object
        $n = $sorted.Count
        $median = if ($n % 2) { $sorted[[int][math]::Floor($n / 2)] } else { ($sorted[$n / 2 - 1] + $sorted[$n / 2]) / 2 }
        $avg = ($rates | Measure-Object -Average).Average
        $t   = [timespan]::FromHours($fullWh / $median)
        Write-Host ("`nСталий рівень (медіана): {0:N1} Вт; середнє: {1:N1} Вт ({2} замірів). Повної батареї вистачило б на ≈{3}:{4:00}" -f `
            $median, $avg, $n, [int][math]::Floor($t.TotalHours), $t.Minutes) -ForegroundColor Green
    } elseif ($i -gt 0) {
        Write-Host "`nЗамірів від батареї немає — ноутбук на мережі. Відключи зарядку і запусти ще раз." -ForegroundColor Yellow
    }
}
