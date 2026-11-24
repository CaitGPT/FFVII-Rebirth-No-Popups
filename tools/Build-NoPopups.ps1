[CmdletBinding(SupportsShouldProcess)]
param(
    # Build: apply data\no-popups.json and pack NoPopups_P.
    # Install/Uninstall: copy the pak into, or out of, the game's ~mods folder. Status: show what is installed.
    [ValidateSet('Build', 'Install', 'Uninstall', 'Status')]
    [string]$Mode = 'Build',
    # Standard: built on the game's own tables. JunonCompat: built on Junon Colosseum's Action, PlannerEvent and Hub
    # (config JunonColosseumStaging: that mod's staged End\Content\DataObject\Resident folder), and named to load after
    # it. Both mods replace those whole tables, so with Junon Colosseum installed only this variant keeps both.
    [ValidateSet('Standard', 'JunonCompat')]
    [string]$Variant = 'Standard',
    # Also silence first-time tutorial tips (data\generated-tips.json). Off by default until it passes in game.
    [switch]$WithTips,
    # Give Classified Intel (the region bosses) the game's own panel back (data\classified-panel.json), for a build
    # without the UE4SS part, which otherwise starts those fights. Built into its own folder (build\<Variant>-Panel).
    [switch]$ClassifiedPanel,
    # Machine paths, JSON (default tools\build-config.local.json; see build-config.example.json).
    [string]$ConfigPath = $null
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$ModRoot = Split-Path $PSScriptRoot -Parent
if (-not $ConfigPath) { $ConfigPath = Join-Path $PSScriptRoot 'build-config.local.json' }
$Config = [ordered]@{
    GameRoot    = $null  # FF7 Rebirth install folder
    VanillaRoot = $null  # FModel raw export root containing End\Content\DataObject\Resident
    UnrealReZen = $null  # UnrealReZen.exe
    BuildRoot   = (Join-Path $ModRoot 'build')
}
if (Test-Path -LiteralPath $ConfigPath) {
    $local = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    foreach ($p in $local.PSObject.Properties) { $Config[$p.Name] = $p.Value }
}
if (-not $Config.GameRoot) { throw "Set GameRoot in $ConfigPath (see build-config.example.json)." }

# A pak named <name>_<n>_P loads after paks with a lower <n>; Junon Colosseum is JunonColosseum_999_P.
$PackageName = if ($Variant -eq 'JunonCompat') { 'NoPopups_JunonCompat_9999_P' } else { 'NoPopups_P' }
$OtherPackage = if ($Variant -eq 'JunonCompat') { 'NoPopups_P' } else { 'NoPopups_JunonCompat_9999_P' }
# data\no-popups.json is written by hand; data\generated.json comes from tools\make_spec.py.
# data\generated-tips.json comes from tools\tips_spec.py.
$SpecFiles = @((Join-Path $ModRoot 'data\no-popups.json'), (Join-Path $ModRoot 'data\generated.json'))
$Tables = @('HubConfig', 'Hub', 'Action', 'PlannerEvent')
if ($ClassifiedPanel) { $SpecFiles += (Join-Path $ModRoot 'data\classified-panel.json') }
if ($WithTips) {
    $SpecFiles += (Join-Path $ModRoot 'data\generated-tips.json')
    $Tables += 'WorldCondition'
}
$VariantRoot = Join-Path $Config.BuildRoot ($(if ($ClassifiedPanel) { "$Variant-Panel" } else { $Variant }))
$Spec = Join-Path $VariantRoot 'spec.json'
# Junon Colosseum 1.2.1 replaces Hub too (its table differs from the game's), so the compat build starts from its copy.
$JunonTables = @('Action', 'PlannerEvent', 'Hub')
$BuilderBin = Join-Path $Config.BuildRoot 'DataBuilderBin'
$Builder = Join-Path $BuilderBin 'DataBuilder.dll'
$Paks = Join-Path $Config.GameRoot 'End\Content\Paks'
$ModsDir = Join-Path $Paks '~mods'
$Package = Join-Path $VariantRoot 'Package'
# Rebirth's own containers start with these 10 bytes. They differ per game build, so each one we have built
# against is listed; an unknown header still stops the build rather than writing bytes we have not seen.
$HeaderSource = Join-Path $Paks 'pakchunk4optional-WindowsNoEditor.ucas'
$KnownHeaders = [ordered]@{
    'steam-2026-07'      = '8C-06-00-97-A6-88-97-A4-D3-00'
    'epic-1.005'         = '8C-06-00-97-7A-88-97-78-D3-00'
}

function Get-Triplet([string]$Directory) {
    '.pak', '.ucas', '.utoc' | ForEach-Object { Join-Path $Directory ($PackageName + $_) }
}
function Get-Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

function Read-Bytes([string]$Path, [int]$Count) {
    $bytes = New-Object byte[] $Count
    $stream = [IO.File]::OpenRead($Path)
    try { if ($stream.Read($bytes, 0, $Count) -ne $Count) { throw "Too short: $Path" } } finally { $stream.Dispose() }
    , $bytes
}

# UnrealReZen's .utoc lists two compressed blocks: block 0 is its 44-byte
# container header chunk at .ucas offset 0, block 1 the table. Its container
# header crashed this game at start-up when kept intact (2026-11-12: the same
# container with Rebirth's 16-byte prefix prepended and the block offsets
# shifted crashed at ff7rebirth_+0x884281). Training Dummy's step, writing
# Rebirth's 10 header bytes over the start of the .ucas, loads: it spoils only
# that header block, so check that the table's block starts after them.
function Assert-TableBlockClear([string]$Toc) {
    $t = [IO.File]::ReadAllBytes($Toc)
    $entries = [BitConverter]::ToInt32($t, 24); $blocks = [BitConverter]::ToInt32($t, 28)
    $start = 144 + $entries * 22
    for ($i = 1; $i -lt $blocks; $i++) {
        $at = $start + $i * 12
        $offset = 0L; for ($j = 0; $j -lt 5; $j++) { $offset = $offset -bor ([long]$t[$at + $j] -shl (8 * $j)) }
        if ($offset -lt 10) { throw "Block $i starts at $offset, inside the 10 bytes the header step overwrites" }
    }
    $first = 0L; for ($j = 0; $j -lt 5; $j++) { $first = $first -bor ([long]$t[$start + $j] -shl (8 * $j)) }
    $usize = $t[$start + 8] -bor ($t[$start + 9] -shl 8) -bor ($t[$start + 10] -shl 16)
    if ($first -ne 0 -or $usize -gt 64) { throw "Block 0 is not UnrealReZen's small container header (offset $first, $usize bytes)" }
}

function Invoke-Build {
    foreach ($key in 'VanillaRoot', 'UnrealReZen') {
        if (-not $Config[$key]) { throw "Set $key in $ConfigPath (see build-config.example.json)." }
    }
    $staging = Join-Path $VariantRoot 'Staging'
    $base = Join-Path $VariantRoot 'Base'
    foreach ($dir in $staging, $Package, $base) {
        if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    # The tables the spec starts from: the game's own, or for JunonCompat, Junon Colosseum's where it has them.
    $baseTables = Join-Path $base 'End\Content\DataObject\Resident'
    New-Item -ItemType Directory -Path $baseTables -Force | Out-Null
    foreach ($table in $Tables) {
        $source = Join-Path $Config.VanillaRoot "End\Content\DataObject\Resident\$table.uasset"
        if ($Variant -eq 'JunonCompat' -and $JunonTables -contains $table) {
            if (-not $Config['JunonColosseumStaging']) { throw "Set JunonColosseumStaging in $ConfigPath" }
            $source = Join-Path $Config.JunonColosseumStaging "$table.uasset"
        }
        Copy-Item -LiteralPath $source -Destination $baseTables
    }

    # One spec from all spec files (whole-line // comments allowed). DataBuilder rebuilds a table from the base for each
    # entry, so spec files that change the same table are merged into one entry; a row changed twice is refused.
    $byAsset = [ordered]@{}
    foreach ($file in $SpecFiles) {
        $json = ((Get-Content -LiteralPath $file) | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
        foreach ($table in @(($json | ConvertFrom-Json).tables)) {
            if (-not $byAsset.Contains($table.asset)) { $byAsset[$table.asset] = [System.Collections.ArrayList]@() }
            foreach ($row in @($table.rows)) { [void]$byAsset[$table.asset].Add($row) }
        }
    }
    $merged = @()
    foreach ($asset in $byAsset.Keys) {
        $names = @($byAsset[$asset] | ForEach-Object { $_.name })
        if (($names | Select-Object -Unique).Count -ne $names.Count) { throw "Two spec files change the same row of $asset" }
        $merged += [ordered]@{ asset = $asset; rows = @($byAsset[$asset]) }
    }
    [ordered]@{ tables = $merged } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $Spec -Encoding utf8

    & dotnet build (Join-Path $PSScriptRoot 'DataBuilder') -c Release -o $BuilderBin --nologo -v quiet
    if ($LASTEXITCODE -ne 0) { throw "DataBuilder build failed ($LASTEXITCODE)" }
    & dotnet $Builder build $Spec $base $staging
    if ($LASTEXITCODE -ne 0) { throw "DataBuilder failed ($LASTEXITCODE); nothing was packed" }

    # Only the rows the spec names may differ from the tables it started from.
    foreach ($table in $Tables) {
        $relative = "End\Content\DataObject\Resident\$table.uasset"
        $lines = @(& dotnet $Builder compare (Join-Path $base $relative) (Join-Path $staging $relative))
        $lines | Write-Host
    }

    # UnrealReZen must run from its own folder so it finds its Oodle DLL.
    Push-Location (Split-Path $Config.UnrealReZen -Parent)
    try {
        & $Config.UnrealReZen --content-path $staging --compression-format Zlib --engine-version GAME_UE4_26 `
            --game-dir $Paks --output-path (Join-Path $Package "$PackageName.utoc")
        if ($LASTEXITCODE -ne 0) { throw "UnrealReZen failed ($LASTEXITCODE)" }
    } finally { Pop-Location }

    Assert-TableBlockClear (Join-Path $Package "$PackageName.utoc")
    $header = Read-Bytes $HeaderSource 10
    $headerText = [BitConverter]::ToString($header)
    $headerBuild = ($KnownHeaders.GetEnumerator() | Where-Object { $_.Value -eq $headerText } | Select-Object -First 1).Key
    if (-not $headerBuild) { throw "$HeaderSource starts with $headerText, which is not a Rebirth header we have built against" }
    Write-Host "Container header: $headerBuild"
    $ucas = Join-Path $Package "$PackageName.ucas"
    $stream = [IO.File]::Open($ucas, 'Open', 'Write', 'None')
    try { $stream.Write($header, 0, 10) } finally { $stream.Dispose() }
    if ([BitConverter]::ToString((Read-Bytes $ucas 10)) -ne $headerText) { throw "Header step did not apply to $ucas" }

    $manifest = [ordered]@{
        PackageName = $PackageName
        Variant = $Variant
        Base = @($Tables | ForEach-Object { [ordered]@{ Table = $_; SHA256 = (Get-Sha (Join-Path $baseTables "$_.uasset")) } })
        BuiltAt = (Get-Date).ToString('o')
        Specs = @($SpecFiles | ForEach-Object { [ordered]@{ Path = (Split-Path $_ -Leaf); SHA256 = (Get-Sha $_) } })
        Assets = @(Get-ChildItem -LiteralPath $staging -Recurse -File | ForEach-Object {
            [ordered]@{ Path = $_.FullName.Substring($staging.Length + 1); SHA256 = (Get-Sha $_.FullName) } })
        Files = @(Get-Triplet $Package | ForEach-Object {
            [ordered]@{ Name = Split-Path $_ -Leaf; Length = (Get-Item -LiteralPath $_).Length; SHA256 = (Get-Sha $_) } })
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $Package 'manifest.json') -Encoding utf8
    Write-Host "Built $PackageName in $Package"
}

function Assert-GameClosed {
    if (Get-Process -Name 'ff7rebirth_' -ErrorAction SilentlyContinue) { throw 'Close the game first.' }
}

function Invoke-Install {
    Assert-GameClosed
    foreach ($path in '.pak', '.ucas', '.utoc' | ForEach-Object { Join-Path $ModsDir ($OtherPackage + $_) }) {
        if (Test-Path -LiteralPath $path) { throw "The other variant ($OtherPackage) is installed: uninstall it first" }
    }
    $manifest = Get-Content -LiteralPath (Join-Path $Package 'manifest.json') -Raw | ConvertFrom-Json
    New-Item -ItemType Directory -Path $ModsDir -Force | Out-Null
    foreach ($file in $manifest.Files) {
        $source = Join-Path $Package $file.Name
        if ((Get-Sha $source) -ne $file.SHA256) { throw "Built $($file.Name) does not match its manifest" }
        if ($PSCmdlet.ShouldProcess($ModsDir, "Copy $($file.Name)")) {
            Copy-Item -LiteralPath $source -Destination $ModsDir -Force
            if ((Get-Sha (Join-Path $ModsDir $file.Name)) -ne $file.SHA256) { throw "Installed $($file.Name) does not match the build" }
        }
    }
    Write-Host "Installed $PackageName"
}

function Invoke-Uninstall {
    Assert-GameClosed
    foreach ($path in Get-Triplet $ModsDir) {
        if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess($path, 'Remove')) { Remove-Item -LiteralPath $path }
    }
    Write-Host "Removed $PackageName"
}

function Show-Status {
    foreach ($path in Get-Triplet $ModsDir) {
        if (Test-Path -LiteralPath $path) { "$(Split-Path $path -Leaf) $(Get-Sha $path)" } else { "missing: $path" }
    }
}

switch ($Mode) {
    'Build' { Invoke-Build }
    'Install' { Invoke-Install }
    'Uninstall' { Invoke-Uninstall }
    'Status' { Show-Status }
}
