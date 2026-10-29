param(
    [string]$GameRoot = 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid'
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$probeVersion = (Get-Content -LiteralPath (Join-Path $projectRoot 'version.txt') -Raw).Trim()
if ($probeVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'version.txt must contain a semantic version' }
$prefix = "[EmberRoutes v$probeVersion]"
$gameJar = Join-Path $GameRoot 'projectzomboid.jar'
$buddyJar = Join-Path $GameRoot 'ZombieBuddy.jar'
$expected = @{
    'projectzomboid.jar' = 'E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33'
    'ZombieBuddy.jar' = 'EB79B9876332010733A8E0D7CE4FE0377846059A9E28859029E2A0FB449F6CF2'
}
$dependencies = foreach ($dependencyJar in @($gameJar, $buddyJar)) {
    $hash = Get-FileHash -LiteralPath $dependencyJar -Algorithm SHA256
    if ($hash.Hash -ne $expected[[IO.Path]::GetFileName($dependencyJar)]) {
        throw "$prefix Dependency changed: $dependencyJar. Re-review before updating the baseline."
    }
    [ordered]@{ path=$dependencyJar; sha256=$hash.Hash }
}
$javaCommand = (Get-Command java -ErrorAction Stop).Source
$javacCommand = (Get-Command javac -ErrorAction Stop).Source
$jarCommand = (Get-Command jar -ErrorAction Stop).Source
$buildRoot = Join-Path $projectRoot 'build'
$logsRoot = Join-Path $buildRoot 'logs'
$staging = Join-Path $buildRoot ('compile-' + [Guid]::NewGuid().ToString('N'))
$classes = Join-Path $staging 'classes'
$tests = Join-Path $staging 'tests'
$generated = Join-Path $staging 'generated/emberroutes/probe'
foreach ($directory in @($logsRoot, $classes, $tests, $generated)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}
$buildInfo = @"
package emberroutes.probe;
public final class BuildInfo {
    public static final String VERSION = "$probeVersion";
    public static final String PREFIX = "[EmberRoutes v" + VERSION + "]";
    public static final String GAME_SHA256 = "$($dependencies[0].sha256)";
    private BuildInfo() {}
}
"@
[IO.File]::WriteAllText((Join-Path $generated 'BuildInfo.java'), $buildInfo, [Text.UTF8Encoding]::new($false))
$sources = @(Get-ChildItem (Join-Path $projectRoot 'java/src/main/java') -Recurse -Filter '*.java' | ForEach-Object FullName)
$sources += Join-Path $generated 'BuildInfo.java'
$classpath = "$gameJar;$buddyJar"
Write-Output "$prefix Compiling against pinned local game dependencies"
& $javacCommand '-J-Duser.language=en' '--release' '17' '-encoding' 'UTF-8' '-cp' $classpath '-d' $classes @sources 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'javac.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Java build failed" }
$testSources = @(Get-ChildItem (Join-Path $projectRoot 'java/src/test/java') -Recurse -Filter '*.java' | ForEach-Object FullName)
& $javacCommand '-J-Duser.language=en' '--release' '17' '-encoding' 'UTF-8' '-cp' $classes '-d' $tests @testSources 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'test-compile.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Test compilation failed" }
& $javaCommand '-ea' '-cp' "$classes;$tests" 'emberroutes.probe.ProbeLogicTest' 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'logic-tests.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Logic tests failed" }
& $javaCommand '-ea' '-cp' "$classes;$tests" 'emberroutes.probe.ProbeCheckpointTest' 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'checkpoint-tests.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Checkpoint tests failed" }
& $javaCommand '-ea' '-cp' "$classes;$tests" 'emberroutes.probe.WorkerRosterTest' 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'worker-tests.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Worker tests failed" }
& $javaCommand '-ea' '-cp' "$classes;$tests" 'emberroutes.probe.BodyAuthorityTest' 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'body-authority-tests.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Body authority tests failed" }
& $javaCommand '-ea' '-cp' "$classes;$tests" 'emberroutes.probe.ProbeBaselineTest' $GameRoot $expected['projectzomboid.jar'] 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'baseline-tests.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Installed-file baseline regression failed" }
$overrideJar = Join-Path $GameRoot 'pzopt/aot/pzopt.jar'
if (Test-Path -LiteralPath $overrideJar -PathType Leaf) {
    # Resolve actual class metadata only; do not initialize IsoPlayer or start the engine.
    $originClasspath = "$classes;$tests;$overrideJar;$gameJar;$GameRoot/*"
    & $javaCommand '-ea' '-cp' $originClasspath 'emberroutes.probe.ProbeBaselineTest' $GameRoot $expected['projectzomboid.jar'] '--class-origin' 2>&1 |
        Tee-Object -FilePath (Join-Path $logsRoot 'class-origin-smoke.txt')
    if ($LASTEXITCODE -ne 0) { throw "$prefix Override class-origin regression failed" }
}
$manifest = "Manifest-Version: 1.0`nImplementation-Title: EmberRoutes Carrier Probe`nImplementation-Version: $probeVersion`n`n"
& $javacCommand '-J-Duser.language=en' '--release' '17' '-cp' "$classes;$GameRoot/*" '-d' $tests (Join-Path $projectRoot 'tests/java/emberroutes/probe/ProbeStoreTableTest.java') 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'store-table-compile.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Checkpoint table test compilation failed" }
& $javaCommand '--enable-native-access=ALL-UNNAMED' '-Duser.language=en' '-ea' '-cp' "$classes;$tests;$GameRoot/*" 'emberroutes.probe.ProbeStoreTableTest' 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'store-table-tests.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Checkpoint table migration tests failed" }
& $javacCommand '-J-Duser.language=en' '--release' '17' '-cp' "$classes;$GameRoot/*" '-d' $tests (Join-Path $projectRoot 'tests/java/emberroutes/probe/ProbeSaveReceiptTest.java') 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'save-receipt-compile.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Save receipt test compilation failed" }
& $javaCommand '--enable-native-access=ALL-UNNAMED' '-Duser.language=en' '-ea' '-cp' "$classes;$tests;$GameRoot/*" 'emberroutes.probe.ProbeSaveReceiptTest' 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'save-receipt-tests.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Save receipt tests failed" }
& $javacCommand '-J-Duser.language=en' '--release' '17' '-cp' "$classes;$GameRoot/*" '-d' $tests (Join-Path $projectRoot 'tests/java/emberroutes/probe/RecipeMetadataTest.java') 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'recipe-metadata-compile.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Recipe metadata test compilation failed" }
& $javaCommand '--enable-native-access=ALL-UNNAMED' '-Duser.language=en' '-ea' '-cp' "$classes;$tests;$GameRoot/*" 'emberroutes.probe.RecipeMetadataTest' 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'recipe-metadata-tests.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Recipe metadata test failed" }
& $javacCommand '-J-Duser.language=en' '--release' '17' '-cp' "$classes;$GameRoot/*" '-d' $tests (Join-Path $projectRoot 'tests/java/emberroutes/probe/InventoryReadsTest.java') 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'inventory-reads-compile.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Native inventory-read test compilation failed" }
& $javaCommand '--enable-native-access=ALL-UNNAMED' '-Duser.language=en' '-ea' '-cp' "$classes;$tests;$GameRoot/*" 'emberroutes.probe.InventoryReadsTest' 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'inventory-reads-tests.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix Native inventory-read tests failed" }
& $javacCommand '-J-Duser.language=en' '--release' '17' '-cp' "$classes;$GameRoot/*" '-d' $tests (Join-Path $projectRoot 'tests/java/emberroutes/probe/WarehouseFastIndexTest.java') 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'warehouse-fast-index-compile.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix WarehouseFastIndex test compilation failed" }
& $javaCommand '--enable-native-access=ALL-UNNAMED' '-Duser.language=en' '-ea' '-cp' "$classes;$tests;$GameRoot/*" 'emberroutes.probe.WarehouseFastIndexTest' 2>&1 |
    Tee-Object -FilePath (Join-Path $logsRoot 'warehouse-fast-index-tests.txt')
if ($LASTEXITCODE -ne 0) { throw "$prefix WarehouseFastIndex tests failed" }
$manifestPath = Join-Path $staging 'MANIFEST.MF'
[IO.File]::WriteAllText($manifestPath, $manifest, [Text.UTF8Encoding]::new($false))
$builtJar = Join-Path $staging 'EmberRoutesProbe.jar'
& $jarCommand "-J-Djava.io.tmpdir=$staging" '--create' '--file' $builtJar '--manifest' $manifestPath '-C' $classes '.'
if ($LASTEXITCODE -ne 0) { throw "$prefix JAR packaging failed" }
$entries = @(& $jarCommand 'tf' $builtJar)
if ($LASTEXITCODE -ne 0) { throw "$prefix JAR inspection failed" }
foreach ($entry in $entries) {
    if ($entry -notmatch '^(META-INF/|emberroutes/)') { throw "$prefix Unexpected JAR entry: $entry" }
}
$modRoot = Join-Path $projectRoot 'Contents/mods/EmberRoutesProbe'
$versionRoot = Join-Path $modRoot '42'
$javaOutput = Join-Path $versionRoot 'media/java'
$luaGenerated = Join-Path $versionRoot 'media/lua/shared/EmberRoutesProbe'
foreach ($directory in @($javaOutput, $luaGenerated)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}
$template = Get-Content (Join-Path $projectRoot 'packaging/probe-mod.info.in') -Raw
[IO.File]::WriteAllText((Join-Path $versionRoot 'mod.info'), $template.Replace('@VERSION@', $probeVersion), [Text.UTF8Encoding]::new($false))
$luaBuild = "return { version = '$probeVersion', prefix = '$prefix' }`n"
[IO.File]::WriteAllText((Join-Path $luaGenerated 'Build.lua'), $luaBuild, [Text.UTF8Encoding]::new($false))
[IO.File]::Copy($builtJar, (Join-Path $javaOutput 'EmberRoutesProbe.jar'), $true)
$translationRoot = Join-Path $versionRoot 'media/lua/shared/Translate'
foreach ($filename in @('IG_UI.json', 'Sandbox.json')) {
    $en = Get-Content (Join-Path $translationRoot "EN/$filename") -Raw | ConvertFrom-Json -AsHashtable
    $cn = Get-Content (Join-Path $translationRoot "CN/$filename") -Raw | ConvertFrom-Json -AsHashtable
    if (@(Compare-Object @($en.Keys | Sort-Object) @($cn.Keys | Sort-Object)).Count -ne 0) {
        throw "$prefix CN/EN translation mismatch: $filename"
    }
}
$packageRoot = Join-Path $buildRoot 'packages'
New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null
$zipPath = Join-Path $packageRoot "EmberRoutesProbe-$probeVersion.zip"
Compress-Archive -LiteralPath $modRoot -DestinationPath $zipPath -Force
$buildReport = [ordered]@{
    version=$probeVersion; builtAtUtc=[DateTime]::UtcNow.ToString('o');
    dependencies=@($dependencies); java=$javaCommand; javac=$javacCommand;
    jarSha256=(Get-FileHash (Join-Path $javaOutput 'EmberRoutesProbe.jar') -Algorithm SHA256).Hash;
    zipSha256=(Get-FileHash $zipPath -Algorithm SHA256).Hash;
    jarEntries=$entries; runtimeTestsRun=$false
}
$buildReport | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 (Join-Path $buildRoot 'probe-build.json')
Write-Output "$prefix BUILD_OK $zipPath; runtime tests NOT RUN"
