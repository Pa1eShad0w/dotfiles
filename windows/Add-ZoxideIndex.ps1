<#
.SYNOPSIS
    Bulk-add directories into the zoxide database without having to cd into each one.

.DESCRIPTION
    Scans one or more parent directories up to a specified depth and registers every
    subdirectory with 'zoxide add' immediately as it is found (streaming traversal).
    Progress is displayed in real time; there is no silent pre-collection phase.

.PARAMETER Path
    One or more root directories to scan.  Defaults to the current directory.
    Accepts pipeline input and wildcards.

.PARAMETER Depth
    How many directory levels below each Path to include.  Default: 3.
    (1 = immediate children only)

.PARAMETER Exclude
    Directory names to skip entirely (directory + all descendants).
    Matched against the directory name only.
    Default: .git, node_modules, .venv, __pycache__, vendor, .cache, bin, obj

.PARAMETER ExcludeSubtree
    Directory names whose CHILDREN are skipped, but the directory itself is
    still indexed.  Use this for container folders whose contents are noise.
    Default: Library  (Unity intermediate folder)

.PARAMETER WhatIf
    Show what would be added without actually calling zoxide add.

.EXAMPLE
    Add-ZoxideIndex -Path F:\Projects -Depth 3

.EXAMPLE
    Add-ZoxideIndex -Path C:\UnityProjects -Depth 4 -ExcludeSubtree Library,Temp,Logs
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('FullName')]
    [string[]]$Path = @($PWD.Path),

    [ValidateRange(1, 10)]
    [int]$Depth = 3,

    [string[]]$Exclude = @('.git','node_modules','.venv','__pycache__','vendor','.cache','bin','obj'),

    [string[]]$ExcludeSubtree = @('Library')
)

begin {
    if (-not (Get-Command zoxide -ErrorAction SilentlyContinue)) {
        throw 'zoxide not found in PATH.  Install it with: winget install ajeetdsouza.zoxide'
    }

    $script:added   = 0
    $script:skipped = 0
    $script:count   = 0
    $roots = [System.Collections.Generic.List[string]]::new()

    # Recursive traversal with early pruning.
    # Registers each directory with zoxide immediately as it is discovered
    # instead of collecting everything first, so progress is always live.
    function Invoke-IndexDir {
        param(
            [string]$DirPath,
            [int]$CurrentDepth,
            [int]$MaxDepth,
            [string[]]$HardExclude,
            [string[]]$SubtreeExclude
        )

        # Register this directory immediately
        $script:count++
        Write-Progress `
            -Activity  'Add-ZoxideIndex' `
            -Status    "[$script:count added]  $DirPath" `
            -PercentComplete -1    # indeterminate – we don't know total upfront

        if ($PSCmdlet.ShouldProcess($DirPath, 'zoxide add')) {
            zoxide add $DirPath
            $script:added++
        } else {
            $script:skipped++
        }

        # Stop descending when depth limit reached
        if ($CurrentDepth -ge $MaxDepth) { return }

        $children = Get-ChildItem -LiteralPath $DirPath -Directory -ErrorAction SilentlyContinue
        foreach ($child in $children) {
            $name = $child.Name

            # Hard exclude: skip directory and all its descendants
            if ($HardExclude -contains $name) { continue }

            # Subtree exclude: register this directory but do NOT recurse into it
            if ($SubtreeExclude -contains $name) {
                $script:count++
                Write-Progress `
                    -Activity  'Add-ZoxideIndex' `
                    -Status    "[$script:count added]  $($child.FullName)" `
                    -PercentComplete -1
                if ($PSCmdlet.ShouldProcess($child.FullName, 'zoxide add')) {
                    zoxide add $child.FullName
                    $script:added++
                } else {
                    $script:skipped++
                }
                continue
            }

            Invoke-IndexDir `
                -DirPath        $child.FullName `
                -CurrentDepth   ($CurrentDepth + 1) `
                -MaxDepth       $MaxDepth `
                -HardExclude    $HardExclude `
                -SubtreeExclude $SubtreeExclude
        }
    }
}

process {
    foreach ($p in $Path) {
        $resolved = Resolve-Path -LiteralPath $p -ErrorAction SilentlyContinue
        if (-not $resolved) {
            Write-Warning "Path not found, skipping: $p"
            continue
        }
        $roots.Add($resolved.Path)
    }
}

end {
    foreach ($root in $roots) {
        Write-Host "`nScanning " -NoNewline
        Write-Host $root -ForegroundColor Cyan -NoNewline
        Write-Host "  (depth $Depth)..."

        $countBefore = $script:added

        Invoke-IndexDir `
            -DirPath        $root `
            -CurrentDepth   0 `
            -MaxDepth       $Depth `
            -HardExclude    $Exclude `
            -SubtreeExclude $ExcludeSubtree

        Write-Progress -Activity 'Add-ZoxideIndex' -Completed

        $countThis = $script:added - $countBefore
        Write-Host "  Indexed " -NoNewline
        Write-Host $countThis -ForegroundColor Yellow -NoNewline
        Write-Host " directories under $root"
    }

    Write-Host ''
    $action = if ($WhatIfPreference) { 'Would add' } else { 'Added' }
    Write-Host "$action " -NoNewline
    Write-Host $script:added -ForegroundColor Green -NoNewline
    Write-Host " director$(if ($script:added -ne 1) {'ies'} else {'y'}) to zoxide index."
    if ($script:skipped -gt 0) {
        Write-Host "Skipped $script:skipped (WhatIf)." -ForegroundColor DarkGray
    }
}