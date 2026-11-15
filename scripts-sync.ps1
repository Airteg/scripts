<#
.SYNOPSIS
  Синхронізація теки скриптів з GitHub: забрати свіже, відправити своє.

.DESCRIPTION
  Запуск з будь-якої теки:  scripts-sync
  Працює і в PowerShell 7, і у вбудованому Windows PowerShell 5.1 (файл збережено з BOM).

  1. Якщо в теці є локальні зміни — показує їх і комітить
     (опис: -Message або автоматичний «Оновлення з <комп'ютер>, <дата>»).
  2. Забирає зміни з GitHub і ставить ваші коміти поверх них.
  3. Відправляє ваші коміти на GitHub.

  Якщо той самий фрагмент файлу змінено і тут, і на іншому комп'ютері,
  скрипт зупиняється, нічого не втрачає і пише, що робити.

.PARAMETER Message
  Опис змін для коміту.

.EXAMPLE
  scripts-sync
.EXAMPLE
  scripts-sync -Message "code-dump: новий ключ -Docs"
#>
[CmdletBinding()]
param([string]$Message)

$repo = $PSScriptRoot
function G { & git -C $repo -c core.quotepath=false @args }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host 'git не встановлено.' -ForegroundColor Red; exit 1
}

$oldEnc = [Console]::OutputEncoding
[Console]::OutputEncoding = [Text.Encoding]::UTF8
try {
    $null = G rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "$repo — не git-репозиторій." -ForegroundColor Red; exit 1 }
    $null = G rev-parse --abbrev-ref '@{u}' 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host 'Тека не пов''язана з GitHub (немає upstream).' -ForegroundColor Red; exit 1 }

    # 1. Локальні зміни
    $changes = @(G status --porcelain)
    if ($changes) {
        Write-Host 'Локальні зміни:' -ForegroundColor Cyan
        $changes | ForEach-Object { Write-Host "  $_" }
        if (-not $Message) { $Message = "Оновлення з $env:COMPUTERNAME, $(Get-Date -Format 'yyyy-MM-dd HH:mm')" }
        G add -A
        G commit -q -m $Message
        if ($LASTEXITCODE -ne 0) { Write-Host 'Не вдалося зробити коміт.' -ForegroundColor Red; exit 1 }
    }

    # 2. Забрати з GitHub
    G fetch -q
    if ($LASTEXITCODE -ne 0) { Write-Host 'Не вдалося зв''язатися з GitHub.' -ForegroundColor Red; exit 1 }
    $behind = [int](G rev-list --count 'HEAD..@{u}')
    if ($behind -gt 0) {
        Write-Host 'Прийшло з GitHub:' -ForegroundColor Cyan
        G diff --stat 'HEAD...@{u}'
        G rebase -q '@{u}'
        if ($LASTEXITCODE -ne 0) {
            Write-Host ''
            Write-Host 'Конфлікт: той самий фрагмент змінено і тут, і на іншому комп''ютері.' -ForegroundColor Red
            Write-Host 'Нічого не втрачено. Повернути все як було до синхронізації:'
            Write-Host "  git -C $repo rebase --abort"
            Write-Host 'Подивитися, у яких файлах конфлікт:'
            Write-Host "  git -C $repo status"
            exit 1
        }
    }

    # 3. Відправити своє
    $ahead = [int](G rev-list --count '@{u}..HEAD')
    if ($ahead -gt 0) {
        G push -q
        if ($LASTEXITCODE -ne 0) { Write-Host 'Не вдалося відправити зміни на GitHub.' -ForegroundColor Red; exit 1 }
        Write-Host "Відправлено комітів: $ahead" -ForegroundColor Cyan
    }

    if (-not $changes -and $behind -eq 0 -and $ahead -eq 0) {
        Write-Host 'Усе вже актуальне.' -ForegroundColor Green
    } else {
        Write-Host ("Синхронізовано: {0}" -f (G log -1 --format='%h %s')) -ForegroundColor Green
    }
} finally {
    [Console]::OutputEncoding = $oldEnc
}
