<#
 post-install-check.ps1 — перевірка системи після встановлення програми.

 НАВІЩО
   Створено 2026-11-20 після інциденту: інсталятор Viber непомітно поставив
   Bright VPN (proxyware від Bright Data / Luminati SDK). Скрипт шукає, чи не
   лишила програма-інсталятор чогось зайвого: нових програм, служб, задач,
   автозапуску, змін мережі (проксі, DNS, hosts), підозрілих сертифікатів,
   мостів у браузери, залишків файлів. Нічого НЕ змінює — лише читає.

 ЯК ЗАПУСКАТИ
   PowerShell 7 від імені адміністратора:
     post-install-check            # за останні 24 години
     post-install-check -Hours 72  # за останні 3 дні

 ЩО ВВАЖАТИ НОРМОЮ
   (нічого) у секціях — добре. Будь-який рядок — переглянути разом з Claude.
#>
param([int]$Hours = 24)

$since = (Get-Date).AddHours(-$Hours)
$p = 'bright|luminati|lum_sdk|net_updater|brightdata'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Section($t) { "`n=== $t" }
function Show($x) { if ($x) { ($x | Format-Table -AutoSize -Wrap | Out-String -Width 220).TrimEnd() } else { '  (нічого)' } }

"Перевірка за останні $Hours год. (з $($since.ToString('yyyy-MM-dd HH:mm'))). Адміністратор: $isAdmin"

Section '1. Нові встановлені програми'
$sinceStr = $since.ToString('yyyyMMdd')
Show (Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -EA SilentlyContinue |
    Where-Object { $_.DisplayName -and $_.InstallDate -and $_.InstallDate -ge $sinceStr } |
    Select-Object DisplayName, DisplayVersion, Publisher, InstallDate)

Section '2. Нові служби (журнал System, подія 7045)'
Show (Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 7045; StartTime = $since } -EA SilentlyContinue |
    ForEach-Object { [pscustomobject]@{ Час = $_.TimeCreated; Служба = $_.Properties[0].Value; Файл = $_.Properties[1].Value } })

Section '3. Задачі планувальника не від Microsoft'
Show (Get-ScheduledTask -EA SilentlyContinue | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } |
    Select-Object TaskPath, TaskName, State, @{ n = 'Запуск'; e = { ($_.Actions | ForEach-Object { $_.Execute }) -join '; ' } })

Section '4. Автозапуск (Run-ключі та папки Startup)'
$runKeys = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
$run = foreach ($k in $runKeys) {
    $i = Get-ItemProperty $k -EA SilentlyContinue
    if ($i) {
        $i.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' } | ForEach-Object {
            [pscustomobject]@{ Де = ($k -replace 'Software\\(WOW6432Node\\)?Microsoft\\Windows\\CurrentVersion\\', ''); Назва = $_.Name; Команда = $_.Value }
        }
    }
}
$st = Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup" -EA SilentlyContinue |
    Where-Object { $_.Name -ne 'desktop.ini' } |
    ForEach-Object { [pscustomobject]@{ Де = 'Startup'; Назва = $_.Name; Команда = $_.FullName } }
Show (@($run) + @($st))

Section '5. Мережа: проксі та DNS'
$is = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -EA SilentlyContinue
"  Проксі користувача: ProxyEnable=$($is.ProxyEnable)  ProxyServer=$($is.ProxyServer)  AutoConfigURL=$($is.AutoConfigURL)"
"  WinHTTP: " + (((netsh winhttp show proxy) -join ' ') -replace '\s+', ' ').Trim()
Show (Get-DnsClientServerAddress -AddressFamily IPv4 -EA SilentlyContinue | Where-Object { $_.ServerAddresses } |
    Select-Object InterfaceAlias, @{ n = 'DNS'; e = { $_.ServerAddresses -join ', ' } })

Section '6. Файл hosts (активні рядки)'
$h = Get-Content "$env:windir\System32\drivers\etc\hosts" -EA SilentlyContinue | Where-Object { $_ -match '^\s*[^#\s]' }
if ($h) { $h | ForEach-Object { "  $_" } } else { '  (нічого)' }

Section '7. Кореневі сертифікати, створені за період'
Show (Get-ChildItem Cert:\LocalMachine\Root, Cert:\CurrentUser\Root -EA SilentlyContinue | Where-Object { $_.NotBefore -ge $since } |
    Select-Object @{ n = 'Сховище'; e = { $_.PSParentPath -replace '.*::', '' } }, Subject, NotBefore)

Section '8. Native messaging hosts у браузерах (усі)'
$nm = 'HKCU:\Software\Google\Chrome\NativeMessagingHosts', 'HKLM:\Software\Google\Chrome\NativeMessagingHosts',
'HKLM:\Software\WOW6432Node\Google\Chrome\NativeMessagingHosts', 'HKCU:\Software\Microsoft\Edge\NativeMessagingHosts',
'HKLM:\Software\Microsoft\Edge\NativeMessagingHosts', 'HKLM:\Software\WOW6432Node\Microsoft\Edge\NativeMessagingHosts',
'HKCU:\Software\Mozilla\NativeMessagingHosts', 'HKLM:\Software\Mozilla\NativeMessagingHosts'
Show ($nm | ForEach-Object { Get-ChildItem $_ -EA SilentlyContinue } |
    ForEach-Object { [pscustomobject]@{ Де = ($_.PSParentPath -replace '.*::', ''); Назва = $_.PSChildName } })

Section '9. Правила брандмауера з ознаками Bright/Luminati'
Show (Get-NetFirewallApplicationFilter -EA SilentlyContinue | Where-Object { $_.Program -match $p } | Select-Object Program)

Section '10. Залишки файлів Bright/Luminati'
$roots = $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, $env:LOCALAPPDATA, $env:APPDATA, $env:TEMP
Show ($roots | ForEach-Object { Get-ChildItem $_ -Depth 2 -Force -EA SilentlyContinue } | Where-Object { $_.Name -match $p } |
    Select-Object FullName, LastWriteTime)

Section '11. Microsoft Defender'
$mp = Get-MpComputerStatus -EA SilentlyContinue
if ($mp) { "  Захист у реальному часі: $($mp.RealTimeProtectionEnabled); бази від: $($mp.AntivirusSignatureLastUpdated); остання швидка перевірка: $($mp.QuickScanEndTime)" }
else { '  (статус недоступний)' }
"  Виявлені загрози за період:"
Show (Get-MpThreatDetection -EA SilentlyContinue | Where-Object { $_.InitialDetectionTime -ge $since } |
    Select-Object InitialDetectionTime, ThreatID, @{ n = 'Ресурси'; e = { $_.Resources -join '; ' } })

Section '12. Інсталятори в Завантаженнях за період: підпис і звідки завантажено'
Show (Get-ChildItem "$env:USERPROFILE\Downloads" -File -Include *.exe, *.msi -Recurse -Depth 0 -EA SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $since } | ForEach-Object {
        $z = Get-Content $_.FullName -Stream Zone.Identifier -EA SilentlyContinue
        $s = Get-AuthenticodeSignature $_.FullName
        [pscustomobject]@{
            Файл              = $_.Name
            Підпис            = $s.Status
            Видавець          = ($s.SignerCertificate.Subject -replace ',.*', '')
            ЗвідкиЗавантажено = (($z | Where-Object { $_ -like 'HostUrl=*' }) -replace 'HostUrl=', '')
        }
    })

"`n=== Готово"
