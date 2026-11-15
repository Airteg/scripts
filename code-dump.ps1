<#
.SYNOPSIS
  Дамп коду проєкту в один txt-файл — для ШІ, у яких немає доступу до робочого простору.

.DESCRIPTION
  Запуск у теці проєкту:   code-dump
  Працює і в PowerShell 7, і у вбудованому Windows PowerShell 5.1 (файл збережено з BOM).
  Результат:               <тека>_code-dump.txt у корені проєкту.

  Що в файлі:
    1. Шапка  — стек (з package.json), статистика за типами, що пропущено як завелике.
    2. Дерево — лише включені файли.
    3. Вміст  — кожен файл під своїм абсолютним шляхом.

  Звідки список файлів: якщо проєкт у git — з git (тобто .gitignore уже враховано),
  інакше — обхід теки. Поверх цього завжди діють власні фільтри:
    - теки, що починаються з крапки, і службові теки (node_modules, build, dist, Pods …);
    - лише код (ts/tsx/js/jsx/vue/svelte/css/scss/html/py …) і конфіги за назвою
      (package.json, tsconfig*.json, app.json, *.config.json, pnpm-workspace.yaml …);
    - решта JSON вважається даними і пропускається;
    - *.txt, *.md, lock-файли, .env*, *.min.*, *.map — ніколи (md — лише з -Docs);
    - файли більші за -MaxKB (ймовірно згенеровані) — пропускаються і перелічуються в шапці.

.PARAMETER Native
  Додати нативний код: kt kts java swift m mm h hpp c cpp gradle xml plist,
  а також Podfile і CMakeLists.txt.
.PARAMETER Docs
  Додати документацію *.md / *.mdx.
.PARAMETER NoTests
  Не включати тести (*.test.*, *.spec.*, *.selftest.*, теки __tests__, test, tests, e2e …).
.PARAMETER Add
  Додаткові розширення:  -Add ps1,sh
.PARAMETER MaxKB
  Поріг розміру файлу в КБ (за замовчуванням 300).
.PARAMETER NoGit
  Не використовувати git, обходити теку.
.PARAMETER Path
  Тека проєкту (за замовчуванням — поточна).

.EXAMPLE
  code-dump
.EXAMPLE
  code-dump -Native -Add ps1
.EXAMPLE
  code-dump -NoTests -Docs
#>
[CmdletBinding()]
param(
    [switch]$Native,
    [switch]$Docs,
    [switch]$NoTests,
    [string[]]$Add = @(),
    [int]$MaxKB = 300,
    [switch]$NoGit,
    [string]$Path = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$root    = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
$name    = Split-Path $root -Leaf
$outFile = Join-Path $root "${name}_code-dump.txt"

# ---------------- Правила ----------------
$skipDirs = @(
    'node_modules','bower_components','jspm_packages',
    'build','dist','out','target','coverage','Pods','DerivedData',
    '__pycache__','venv','site-packages','tmp','temp','logs'
)

$exts = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
'ts','tsx','mts','cts','js','jsx','mjs','cjs','vue','svelte','astro',
'css','scss','sass','less','html','htm','py' | ForEach-Object { [void]$exts.Add($_) }
if ($Native) { 'kt','kts','java','swift','m','mm','h','hpp','c','cpp','gradle','xml','plist' | ForEach-Object { [void]$exts.Add($_) } }
if ($Docs)   { 'md','mdx' | ForEach-Object { [void]$exts.Add($_) } }
foreach ($a in ($Add -join ',' -split ',')) { $e = $a.Trim().TrimStart('.'); if ($e) { [void]$exts.Add($e) } }

# Конфіги, які потрібні завжди (за назвою файлу)
$configNames = @('package.json','app.json','eas.json','composer.json','pnpm-workspace.yaml',
                 'requirements.txt','pyproject.toml','Dockerfile')
$nativeNames = @('Podfile','CMakeLists.txt')

function Test-IsConfig([string]$f) {
    return ($configNames -contains $f) -or
           ($f -like 'tsconfig*.json') -or ($f -like 'jsconfig*.json') -or
           ($f -like '*.config.json')  -or ($f -like 'docker-compose*.y*ml') -or
           ($Native -and ($nativeNames -contains $f))
}

function Test-IsTest([string]$rel) {
    return ($rel -match '\.(test|spec|selftest)\.[^./]+$') -or
           ($rel -match '(^|/)(__tests__|__mocks__|tests?|spec|e2e|androidTest)/')
}

# Повертає $null, якщо файл включається, або причину пропуску
function Get-SkipReason([string]$rel) {
    $parts = $rel -split '/'
    $file  = $parts[-1]
    for ($i = 0; $i -lt $parts.Count - 1; $i++) {
        $d = $parts[$i]
        if ($d.StartsWith('.') -or ($skipDirs -contains $d)) { return 'dir' }
    }
    if ($file -like '.env*' -or $file -like '*_code-dump.txt') { return 'never' }
    if ($file -match '\.min\.(js|css)$|\.map$|\.bundle\.js$')   { return 'never' }
    $isConfig = Test-IsConfig $file
    if (-not $isConfig) {
        $ext = if ($file.Contains('.')) { $file.Substring($file.LastIndexOf('.') + 1) } else { '' }
        if (-not $exts.Contains($ext)) { return 'type' }
        if ($NoTests -and (Test-IsTest $rel)) { return 'test' }
    }
    return $null
}

# ---------------- Збір списку ----------------
$source = 'обхід теки'
$rels = $null
if (-not $NoGit -and (Get-Command git -ErrorAction SilentlyContinue)) {
    $inside = & git -C $root rev-parse --is-inside-work-tree 2>$null
    if ($inside -eq 'true') {
        $oldEnc = [Console]::OutputEncoding
        [Console]::OutputEncoding = [Text.Encoding]::UTF8
        try {
            $rels = & git -c core.quotepath=false -C $root ls-files --cached --others --exclude-standard
        } finally { [Console]::OutputEncoding = $oldEnc }
        $rels = $rels | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf) }
        $source = 'git (.gitignore враховано)'
    }
}
if ($null -eq $rels) {
    $list = [System.Collections.Generic.List[string]]::new()
    function Walk([string]$dir, [string]$prefix) {
        foreach ($it in Get-ChildItem -LiteralPath $dir -Force) {
            if ($it.PSIsContainer) {
                if ($it.Name.StartsWith('.') -or ($skipDirs -contains $it.Name)) { continue }
                if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
                Walk $it.FullName "$prefix$($it.Name)/"
            } else { $list.Add("$prefix$($it.Name)") }
        }
    }
    Walk $root ''
    $rels = $list
}

$files = [System.Collections.Generic.List[object]]::new()
$big   = [System.Collections.Generic.List[string]]::new()
foreach ($rel in $rels) {
    $rel = $rel -replace '\\','/'
    if (Get-SkipReason $rel) { continue }
    $full = Join-Path $root ($rel -replace '/','\')
    $len  = (Get-Item -LiteralPath $full).Length
    if ($len -gt $MaxKB * 1KB) { $big.Add(('{0}  ({1:N0} КБ)' -f $rel, ($len / 1KB))); continue }
    $files.Add([pscustomobject]@{ Rel = $rel; Full = $full; Len = $len })
}
$files = @($files | Sort-Object Rel)

if (-not $files) { Write-Warning "Жодного файлу не підпадає під фільтри у $root"; return }

# ---------------- Стек ----------------
$stack = @()
$pkgPath = Join-Path $root 'package.json'
if (Test-Path -LiteralPath $pkgPath) {
    try {
        $pkg  = [IO.File]::ReadAllText($pkgPath) | ConvertFrom-Json
        $deps = @{}
        foreach ($k in 'dependencies','devDependencies') {
            if ($pkg.$k) { foreach ($pr in $pkg.$k.PSObject.Properties) { $deps[$pr.Name] = $pr.Value } }
        }
        $known = [ordered]@{
            'expo'='Expo'; 'react-native'='React Native'; 'react'='React'; 'next'='Next.js'; 'vue'='Vue';
            'nuxt'='Nuxt'; 'svelte'='Svelte'; '@angular/core'='Angular'; 'electron'='Electron';
            'express'='Express'; 'vite'='Vite'; 'typescript'='TypeScript'; 'tailwindcss'='Tailwind CSS';
            'expo-sqlite'='expo-sqlite'; 'zustand'='Zustand'; '@reduxjs/toolkit'='Redux Toolkit'
        }
        foreach ($k in $known.Keys) { if ($deps.ContainsKey($k)) { $stack += "$($known[$k]) $($deps[$k])" } }
        if ($pkg.packageManager) { $stack += "менеджер: $($pkg.packageManager)" }
    } catch { $stack += '(package.json не вдалося розібрати)' }
}
if (Test-Path (Join-Path $root 'android')) { $stack += 'нативна тека android/' }
if (Test-Path (Join-Path $root 'ios'))     { $stack += 'нативна тека ios/' }
if ((Test-Path (Join-Path $root 'pyproject.toml')) -or (Test-Path (Join-Path $root 'requirements.txt'))) { $stack += 'Python' }

# ---------------- Запис ----------------
$mode = @('база')
if ($Native)  { $mode += '+native' }
if ($Docs)    { $mode += '+docs' }
if ($NoTests) { $mode += 'без тестів' }
if ($Add)     { $mode += "+$($Add -join ',')" }

$totalKB = ($files | Measure-Object Len -Sum).Sum / 1KB
$byType  = $files | Group-Object { if ($_.Rel.Contains('.')) { $_.Rel.Substring($_.Rel.LastIndexOf('.') + 1).ToLower() } else { '(без розширення)' } } |
           Sort-Object Count -Descending | ForEach-Object { "$($_.Name) $($_.Count)" }

$sep = '=' * 80
$w = [IO.StreamWriter]::new($outFile, $false, [Text.UTF8Encoding]::new($false))
try {
    $w.WriteLine("# CODE DUMP: $name")
    $w.WriteLine("# Шлях:    $root")
    $w.WriteLine("# Створено: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    $w.WriteLine("# Джерело списку: $source")
    $w.WriteLine("# Режим:   $($mode -join ' ')")
    $w.WriteLine("# Стек:    $(if ($stack) { $stack -join '; ' } else { 'не визначено' })")
    $w.WriteLine(('# Файлів:  {0}, обсяг {1:N0} КБ' -f $files.Count, $totalKB))
    $w.WriteLine("# Типи:    $($byType -join ', ')")
    if ($big.Count) {
        $w.WriteLine("# Пропущено як завеликі (> $MaxKB КБ):")
        foreach ($b in $big) { $w.WriteLine("#   $b") }
    }
    $w.WriteLine('')

    # Дерево
    $w.WriteLine($sep); $w.WriteLine('СТРУКТУРА (лише включені файли)'); $w.WriteLine($sep)
    $prev = @()
    foreach ($f in $files) {
        $parts = $f.Rel -split '/'
        $dirs  = @(if ($parts.Count -gt 1) { $parts[0..($parts.Count - 2)] })
        $same  = 0
        while ($same -lt $dirs.Count -and $same -lt $prev.Count -and $dirs[$same] -eq $prev[$same]) { $same++ }
        for ($i = $same; $i -lt $dirs.Count; $i++) { $w.WriteLine(('  ' * $i) + $dirs[$i] + '/') }
        $w.WriteLine(('{0}{1}  ({2:N1} КБ)' -f ('  ' * $dirs.Count), $parts[-1], ($f.Len / 1KB)))
        $prev = $dirs
    }
    $w.WriteLine('')

    # Вміст
    foreach ($f in $files) {
        $w.WriteLine($sep); $w.WriteLine("FILE: $($f.Full)"); $w.WriteLine($sep)
        $text = [IO.File]::ReadAllText($f.Full)
        $w.WriteLine($text.TrimEnd())
        $w.WriteLine('')
    }
} finally { $w.Dispose() }

Write-Host ('Готово: {0}' -f $outFile) -ForegroundColor Green
Write-Host ('Файлів: {0}, обсяг {1:N0} КБ, джерело: {2}, режим: {3}' -f $files.Count, $totalKB, $source, ($mode -join ' '))
if ($big.Count) { Write-Host "Пропущено як завеликі: $($big.Count) (список у шапці файлу)" -ForegroundColor Yellow }
