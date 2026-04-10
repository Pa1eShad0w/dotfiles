# UTF-8 without BOM — must be first to avoid pipeline encoding issues in non-interactive shells
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::InputEncoding  = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding            = [System.Text.UTF8Encoding]::new($false)

$script:ProfileVerboseFile = Join-Path $env:LOCALAPPDATA "pwsh-profile-verbose.flag"
$script:ProfileVerbose = Test-Path $script:ProfileVerboseFile

function Invoke-StartupStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )
    if ($script:ProfileVerbose) {
        $start = Get-Date
        Write-Host ("[>] Loading {0}..." -f $Name) -NoNewline
        & $Action
        $ms = [math]::Round(((Get-Date) - $start).TotalMilliseconds, 0)
        Write-Host (" done ({0}ms)" -f $ms) -ForegroundColor DarkGray
    } else {
        & $Action
    }
}

# ── oh-my-posh ────────────────────────────────────────────────────────────────
$OMP_THEME = Join-Path $HOME ".config\oh-my-posh\agnosterplus.omp.json"
Invoke-StartupStep -Name "oh-my-posh" -Action {
    oh-my-posh disable notice
    oh-my-posh init pwsh --config $OMP_THEME | Invoke-Expression
}

# ── PSReadLine ────────────────────────────────────────────────────────────────
Invoke-StartupStep -Name "PSReadLine" -Action {
    Import-Module PSReadLine
}
Invoke-StartupStep -Name "posh-git" -Action {
    Import-Module posh-git
}

$isInteractive = [Environment]::UserInteractive -and
    -not [Console]::IsOutputRedirected -and
    -not [Console]::IsInputRedirected

if ($isInteractive) {
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
}
Set-PSReadLineOption -MaximumHistoryCount 1000
Set-PSReadLineKeyHandler -Key "Tab" -Function MenuComplete
Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
Set-PSReadLineOption -HistorySearchCursorMovesToEnd
Set-PSReadLineOption -HistoryNoDuplicates

# ── Terminal-Icons (eager load – avoids Ctrl+T preview glitch with PSFzf) ────
Invoke-StartupStep -Name "Terminal-Icons" -Action {
    Import-Module Terminal-Icons -ErrorAction SilentlyContinue
}

# ── zoxide ────────────────────────────────────────────────────────────────────
# _ZO_FZF_OPTS must be set BEFORE zoxide initialises so that the built-in
# interactive picker (zi) picks it up.
if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    $env:_ZO_FZF_OPTS = '--no-sort --height 40% --layout=reverse --border --preview "cmd /c dir /b {}"'
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# ── fzf + PSFzf ───────────────────────────────────────────────────────────────
if (Get-Command fzf -ErrorAction SilentlyContinue) {
    $env:FZF_DEFAULT_OPTS = '--height 40% --layout=reverse --border'

    if (Get-Module -ListAvailable -Name PSFzf) {
        Import-Module PSFzf
        Set-PsFzfOption -PSReadlineChordProvider       'Ctrl+t'
        Set-PsFzfOption -PSReadlineChordReverseHistory 'Ctrl+r'
        Set-PsFzfOption -PSReadlineChordSetLocation    'Alt+c'
    }
}

# ── zi: interactive zoxide+fzf directory jump ─────────────────────────────────
# Works whether or not PSFzf is present, as long as fzf is available.
function zi {
    if (-not (Get-Command fzf -ErrorAction SilentlyContinue)) {
        Write-Warning "fzf not found. Install it with: winget install junegunn.fzf"
        return
    }
    $dir = zoxide query -l 2>$null |
        fzf --no-sort --height 40% --layout=reverse --border `
            --preview 'cmd /c dir /b {}' --preview-window 'right:40%'
    if ($dir) {
        Set-Location $dir
        zoxide add $dir
    }
}

# ── zc: z into a directory then launch claude ────────────────────────────────
function zc {
    param(
        [Parameter(Mandatory = $true, Position = 0)][string]$Query,
        [Parameter(ValueFromRemainingArguments)][string[]]$ClaudeArgs
    )
    $dir = zoxide query -- $Query 2>$null
    if (-not $dir) {
        Write-Warning "zoxide: no match for '$Query'"
        return
    }
    zoxide add $dir
    Set-Location $dir
    & claude @ClaudeArgs
}

function pwdz {
    param(
        [Parameter(Position = 0)][string]$Query
    )

    if (-not $Query) {
        # No query provided: just echo current directory (like pwd)
        Write-Host $PWD.Path
        return
    }

    $dir = zoxide query -- $Query 2>$null
    if (-not $dir) {
        Write-Warning "zoxide: no match for '$Query'"
        return
    }

    Push-Location $dir
    try {
        Write-Host $PWD.Path
        Write-Host "Press Enter to return to previous directory..."
        [void][System.Console]::ReadLine()
    } finally {
        Pop-Location
    }
}

# ── Toggle profile verbose loading ────────────────────────────────────────────
function Toggle-ProfileVerbose {
    if (Test-Path $script:ProfileVerboseFile) {
        Remove-Item $script:ProfileVerboseFile -Force
        Write-Host "Profile verbose loading: OFF (next shell will be silent)" -ForegroundColor Yellow
    } else {
        New-Item $script:ProfileVerboseFile -ItemType File -Force | Out-Null
        Write-Host "Profile verbose loading: ON (next shell will show timings)" -ForegroundColor Green
    }
}

# ── Helpers: toggle predictive history ───────────────────────────────────────
function Enable-HistoryPrediction  { Set-PSReadLineOption -PredictionSource History }
function Disable-HistoryPrediction { Set-PSReadLineOption -PredictionSource None }

# ── Measure-ProfileLoad ───────────────────────────────────────────────────────
function Measure-ProfileLoad {
    $omp_theme_path = Join-Path $HOME ".config\oh-my-posh\agnosterplus.omp.json"
    $tests = @(
        @{ Name = "oh-my-posh init";               Action = { oh-my-posh init pwsh --config $omp_theme_path | Out-Null } },
        @{ Name = "Import PSReadLine";              Action = { Import-Module PSReadLine -Force } },
        @{ Name = "Import posh-git";                Action = { Import-Module posh-git -Force } },
        @{ Name = "Import Terminal-Icons";          Action = { Import-Module Terminal-Icons -Force } },
        @{ Name = "Set PredictionSource History";   Action = { Set-PSReadLineOption -PredictionSource History } },
        @{ Name = "Set PredictionViewStyle";        Action = { Set-PSReadLineOption -PredictionViewStyle ListView } },
        @{ Name = "Set MaximumHistoryCount";        Action = { Set-PSReadLineOption -MaximumHistoryCount 1000 } },
        @{ Name = "Set KeyHandler Tab";             Action = { Set-PSReadLineKeyHandler -Key \"Tab\" -Function MenuComplete } },
        @{ Name = "Set KeyHandler UpArrow";         Action = { Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward } },
        @{ Name = "Set KeyHandler DownArrow";       Action = { Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward } },
        @{ Name = "Set HistorySearchCursorMovesToEnd"; Action = { Set-PSReadLineOption -HistorySearchCursorMovesToEnd } },
        @{ Name = "Set HistoryNoDuplicates";        Action = { Set-PSReadLineOption -HistoryNoDuplicates } }
    )
    $results = foreach ($test in $tests) {
        $elapsed = (Measure-Command { & $test.Action }).TotalMilliseconds
        [pscustomobject]@{ Step = $test.Name; Milliseconds = [math]::Round($elapsed, 2) }
    }
    $results
    [pscustomobject]@{
        Step         = "TOTAL"
        Milliseconds = [math]::Round((($results | Measure-Object -Property Milliseconds -Sum).Sum), 2)
    }
}