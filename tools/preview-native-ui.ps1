#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GameRoot = 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid',
    [switch]$Smoke,
    [ValidateSet('native','widgets','squad','settlement','layout')][string]$Scene = 'native',
    [ValidateSet('CN','EN')][string]$Language = 'CN',
    [ValidateRange(640,3840)][int]$Width = 960,
    [ValidateRange(480,2160)][int]$Height = 600,
    [ValidateRange(1,1800)][int]$Seconds = 120,
    [switch]$InjectFailure,
    [switch]$Live,
    [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'
if ($Live -and ($Smoke -or $SelfTest -or $InjectFailure)) { throw '-Live cannot be combined with bounded test modes' }
if ($SelfTest) { $Scene='widgets'; $Language='EN'; $Seconds=90 }
$repo = Split-Path $PSScriptRoot -Parent
$GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path
$jar = Join-Path $GameRoot 'projectzomboid.jar'
$java = Join-Path $GameRoot 'jre64/bin/java.exe'
$nativeRoot = Join-Path $GameRoot '.lwjgl/3.4.1-snapshot/x64'
foreach ($required in @($jar, $java, (Join-Path $nativeRoot 'glfw.dll'))) {
    if (!(Test-Path -LiteralPath $required)) { throw "Missing installed game dependency: $required" }
}
$buildRoot = Join-Path $repo 'build/ui-preview-native'
$classes = Join-Path $buildRoot 'classes'
$output = Join-Path $buildRoot (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
New-Item -ItemType Directory -Force $classes, $output | Out-Null
$sources = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'ui-preview') -Filter '*.java' | Select-Object -ExpandProperty FullName)
& javac -encoding UTF-8 -cp $jar -d $classes @sources
if ($LASTEXITCODE -ne 0) { throw 'Native preview compilation failed' }
$sceneFile = Join-Path $PSScriptRoot "ui-preview/$Scene-scene.lua"
if ($Scene -eq 'layout') {
    if ($Live) { throw 'Layout preview currently supports bounded snapshots only' }
    $arrow = Join-Path $output 'cache/ArrowDown.png'
    & python (Join-Path $PSScriptRoot 'ui-preview/extract-ui-arrow.py') (Join-Path $GameRoot 'media/texturepacks/UI2.pack') $arrow
    if ($LASTEXITCODE -ne 0) { throw 'Installed UI2 preview asset extraction failed' }
    $assetPath = $arrow.Replace('\','/')
    $assetModule = Join-Path $PSScriptRoot 'ui-preview/layout-assets.lua'
    if (Test-Path -LiteralPath $assetModule) { throw 'Layout asset module already exists; another preview may own it' }
    "return getTexture([[$assetPath]])" | Set-Content -LiteralPath $assetModule -Encoding utf8
}
$start = [System.Diagnostics.ProcessStartInfo]::new()
$start.FileName = $java
$start.WorkingDirectory = $GameRoot
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
foreach ($argument in @('--enable-native-access=ALL-UNNAMED',
    "-Djava.library.path=$GameRoot;$nativeRoot", "-Dorg.lwjgl.librarypath=$nativeRoot",
    '-cp', "$classes;$jar", 'NativeUiPreview', $output,
    $sceneFile,
    ($Smoke -or $SelfTest).ToString().ToLowerInvariant(), "$Seconds", $InjectFailure.IsPresent.ToString().ToLowerInvariant(), $repo, $Language, "$Width", "$Height",
    $Live.IsPresent.ToString().ToLowerInvariant(), $SelfTest.IsPresent.ToString().ToLowerInvariant())) {
    $start.ArgumentList.Add($argument)
}
$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $start
$started = $false
try {
    [void]$process.Start()
    $started = $true
    Write-Output "Native UI window: $output"
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $limit = if ($Smoke -or $InjectFailure -or $SelfTest) { 120000 } else { ($Seconds + 90) * 1000 }
    if ($Live) { while (!$process.WaitForExit(500)) {} ; $timedOut = $false }
    else { $timedOut = !$process.WaitForExit($limit) }
    if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    $stdout | Set-Content -LiteralPath (Join-Path $output 'stdout.log') -Encoding utf8
    $stderr | Set-Content -LiteralPath (Join-Path $output 'stderr.log') -Encoding utf8
    @{
        jarSha256 = (Get-FileHash -LiteralPath $jar -Algorithm SHA256).Hash
        gameRoot = $GameRoot; scene = $Scene; language = $Language; width = $Width; height = $Height
        smoke = $Smoke.IsPresent; injectFailure = $InjectFailure.IsPresent; live = $Live.IsPresent; selfTest = $SelfTest.IsPresent
        exitCode = $process.ExitCode; timedOut = $timedOut
        scope = 'Native game rendering; repository UI; fixture data; silent audio; host input routing'
    } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $output 'run.json') -Encoding utf8
    Write-Output $stdout.TrimEnd()
    if ($stderr) { Write-Output $stderr.TrimEnd() }
    Write-Output "Evidence: $output"
    if ($timedOut) { throw 'Native preview timed out; owned child JVM terminated' }
    if ($process.ExitCode -ne 0) { throw "Native preview exited with code $($process.ExitCode); see logs" }
} finally {
    if ($started -and !$process.HasExited) { $process.Kill($true); $process.WaitForExit() }
    $process.Dispose()
    if ($assetModule) { Remove-Item -LiteralPath $assetModule -ErrorAction SilentlyContinue }
}
