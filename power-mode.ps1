<#
  power-mode.ps1 — перемикання схем живлення (права адміністратора не потрібні).
    power-mode        — показати активну схему, частоту вбудованого екрана і список схем
    power-mode max    — Nitro — Максимум  + вбудований екран на максимальну частоту
    power-mode eco    — Nitro — Економія  + вбудований екран на 60 Гц
    power-mode bal    — Збалансований     + вбудований екран на максимальну частоту
  Схеми «Максимум» і «Економія» створює power-plans-setup.ps1.
  Частота змінюється штатною функцією Windows (ChangeDisplaySettingsEx) — тією самою,
  що й у «Параметрах»; лише для екрана на Intel (вбудованого), зовнішній не чіпається.
#>
param([string]$Mode = '')

$EcoHz = 60   # частота вбудованого екрана в режимі eco

$Plans = [ordered]@{
    max = @{ Guid = '5f1a3c2e-7b4d-4e8a-9c61-2d0b7e9a4f11'; Name = 'Nitro — Максимум'; Hz = 'max' }
    eco = @{ Guid = '9d2e6b4a-1c3f-4a7e-8b52-6e0f3d1c7a22'; Name = 'Nitro — Економія'; Hz = $EcoHz }
    bal = @{ Guid = '381b4222-f694-41f0-9685-ff5bb260df2e'; Name = 'Збалансований';    Hz = 'max' }
}

# ---------- Частота вбудованого екрана ----------
$displaySrc = @'
using System;
using System.Runtime.InteropServices;
public static class NitroDisplay {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields;
        public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]  public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplayDevices(string lpDevice, int iDevNum, ref DISPLAY_DEVICE dd, int flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern bool EnumDisplaySettings(string name, int mode, ref DEVMODE dm);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern int ChangeDisplaySettingsEx(string name, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr lParam);

    // Активний вихід адаптера, назва якого містить vendor (напр. "Intel"); null — немає
    public static string FindOutput(string vendor) {
        for (int i = 0; ; i++) {
            DISPLAY_DEVICE dd = new DISPLAY_DEVICE();
            dd.cb = Marshal.SizeOf(typeof(DISPLAY_DEVICE));
            if (!EnumDisplayDevices(null, i, ref dd, 0)) return null;
            bool attached = (dd.StateFlags & 1) != 0;   // DISPLAY_DEVICE_ATTACHED_TO_DESKTOP
            if (attached && dd.DeviceString != null && dd.DeviceString.IndexOf(vendor, StringComparison.OrdinalIgnoreCase) >= 0) return dd.DeviceName;
        }
    }
    static DEVMODE NewMode() { DEVMODE m = new DEVMODE(); m.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); return m; }

    public static int CurrentHz(string output) {
        DEVMODE m = NewMode();
        return EnumDisplaySettings(output, -1, ref m) ? m.dmDisplayFrequency : 0;   // -1 = ENUM_CURRENT_SETTINGS
    }
    // Найвища частота, доступна для поточної роздільності
    public static int MaxHz(string output) {
        DEVMODE cur = NewMode();
        if (!EnumDisplaySettings(output, -1, ref cur)) return 0;
        int best = 0;
        for (int i = 0; ; i++) {
            DEVMODE m = NewMode();
            if (!EnumDisplaySettings(output, i, ref m)) break;
            if (m.dmPelsWidth == cur.dmPelsWidth && m.dmPelsHeight == cur.dmPelsHeight && m.dmDisplayFrequency > best) best = m.dmDisplayFrequency;
        }
        return best;
    }
    public static bool Supports(string output, int hz) {
        DEVMODE cur = NewMode();
        if (!EnumDisplaySettings(output, -1, ref cur)) return false;
        for (int i = 0; ; i++) {
            DEVMODE m = NewMode();
            if (!EnumDisplaySettings(output, i, ref m)) return false;
            if (m.dmPelsWidth == cur.dmPelsWidth && m.dmPelsHeight == cur.dmPelsHeight && m.dmDisplayFrequency == hz) return true;
        }
    }
    // 0 = успіх; 1 = потрібне перезавантаження; інше — помилка (DISP_CHANGE_*)
    public static int SetHz(string output, int hz) {
        DEVMODE m = NewMode();
        if (!EnumDisplaySettings(output, -1, ref m)) return -100;
        m.dmDisplayFrequency = hz;
        m.dmFields = 0x400000;                       // DM_DISPLAYFREQUENCY
        return ChangeDisplaySettingsEx(output, ref m, IntPtr.Zero, 1, IntPtr.Zero);   // 1 = CDS_UPDATEREGISTRY
    }
}
'@

function Get-InternalOutput {
    if (-not ('NitroDisplay' -as [type])) { Add-Type -TypeDefinition $displaySrc -ErrorAction Stop }
    [NitroDisplay]::FindOutput('Intel')
}

function Set-InternalRefresh($Target) {
    try { $out = Get-InternalOutput } catch { Write-Warning "Частоту не змінено: $($_.Exception.Message)"; return }
    if (-not $out) { Write-Warning 'Вбудований екран (Intel) не знайдено — частоту не змінено.'; return }
    $hz  = if ("$Target" -eq 'max') { [NitroDisplay]::MaxHz($out) } else { [int]$Target }
    $cur = [NitroDisplay]::CurrentHz($out)
    if ($cur -eq $hz) { Write-Host "Екран: уже $hz Гц"; return }
    if (-not [NitroDisplay]::Supports($out, $hz)) { Write-Warning "Екран не підтримує $hz Гц — лишаю $cur Гц."; return }
    $r = [NitroDisplay]::SetHz($out, $hz)
    switch ($r) {
        0       { Write-Host "Екран: $cur → $hz Гц" -ForegroundColor Green }
        1       { Write-Warning "Екран: $hz Гц застосується після перезавантаження." }
        default { Write-Warning "Екран: не вдалося змінити частоту (код $r), лишається $cur Гц." }
    }
}

# ---------- Стан ----------
function Show-State {
    # powercfg пише в DOS-кодуванні без «і», тому відомі схеми називаємо за GUID
    $active = (powercfg.exe /getactivescheme) -join ' '
    $known  = $Plans.Values | Where-Object { $active -match $_.Guid } | Select-Object -First 1
    $name = if ($known) { $known.Name } elseif ($active -match '\((.+)\)') { $Matches[1] } else { $active }
    Write-Host "Активна: $name" -ForegroundColor Green
    try {
        $out = Get-InternalOutput
        if ($out) { Write-Host ('Вбудований екран: {0} Гц (максимум {1} Гц)' -f [NitroDisplay]::CurrentHz($out), [NitroDisplay]::MaxHz($out)) }
    } catch { }
    Write-Host ''
    powercfg.exe /list
    Write-Host "`nВикористання: power-mode max | eco | bal"
}

if (-not $Mode) { Show-State; return }

$key = $Mode.ToLower()
if (-not $Plans.Contains($key)) {
    Write-Warning "Невідомий режим '$Mode'. Доступні: $($Plans.Keys -join ', ')"
    return
}

$plan = $Plans[$key]
& powercfg.exe /setactive $plan.Guid 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Warning "Схему «$($plan.Name)» не знайдено. Спершу запусти power-plans-setup від адміністратора."
    return
}
Write-Host "Увімкнено: $($plan.Name)" -ForegroundColor Green
Set-InternalRefresh $plan.Hz
