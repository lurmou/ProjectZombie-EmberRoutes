#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Status','Reload','Capture','Inspect','Close')][string]$Action='Status',
    [ValidateSet('native','widgets','squad','settlement')][string]$Scene,
    [ValidateSet('CN','EN')][string]$Language,
    [ValidateRange(0,3840)][int]$X,
    [ValidateRange(0,2160)][int]$Y
)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$root=[IO.Path]::GetFullPath((Join-Path $repo 'build/ui-preview-native'))
$pointer=Get-Content -LiteralPath (Join-Path $root 'active.json') -Raw | ConvertFrom-Json -AsHashtable
if ($pointer.format -ne 1) { throw 'Unsupported active preview pointer' }
$output=[IO.Path]::GetFullPath($pointer.output)
if (!$output.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Active preview directory is outside the native preview workspace'
}
if (Test-Path -LiteralPath (Join-Path $output 'closed.json')) { throw 'Preview is closed; start preview-native-ui.ps1 -Live' }
$process=Get-Process -Id $pointer.pid -ErrorAction SilentlyContinue
if (!$process -or $process.ProcessName -ne 'java') { throw 'Native preview JVM is not running' }
if ($Action -eq 'Status' -and !$Scene -and !$Language) {
    Get-Content -LiteralPath (Join-Path $output 'status.json') -Raw | ConvertFrom-Json
    $selection=Join-Path $output 'selection.json'
    if (Test-Path -LiteralPath $selection) { Get-Content -LiteralPath $selection -Raw | ConvertFrom-Json }
    return
}
$file=Join-Path $output 'control.json'
$config=Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable
if ($config.format -ne 1) { throw 'Unsupported preview control format' }
if ($Scene) { $config.scene=$Scene }
if ($Language) { $config.language=$Language }
switch ($Action) {
    'Reload' { $config.reload++ }
    'Capture' { $config.capture++ }
    'Inspect' {
        $config.inspect=$true
        if ($PSBoundParameters.ContainsKey('X') -or $PSBoundParameters.ContainsKey('Y')) {
            if (!$PSBoundParameters.ContainsKey('X') -or !$PSBoundParameters.ContainsKey('Y')) { throw 'Supply both -X and -Y' }
            $config.pick++; $config.pickX=$X; $config.pickY=$Y; $config.capture++
        }
    }
    'Close' { $config.quit=$true }
}
$temporary=Join-Path $output ('control-'+[guid]::NewGuid().ToString('N')+'.tmp')
[IO.File]::WriteAllText($temporary,($config | ConvertTo-Json),[Text.UTF8Encoding]::new($false))
[IO.File]::Move($temporary,$file,$true)
Write-Output "Sent $Action to native preview: $output"
