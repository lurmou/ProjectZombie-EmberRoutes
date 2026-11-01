param([string]$OutputRoot)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$commit=(& git -C $project rev-parse HEAD).Trim()
if($LASTEXITCODE -ne 0){throw 'Git baseline unavailable'}
$short=$commit.Substring(0,7)
if(-not $OutputRoot){$OutputRoot=Join-Path $project ('build/qa/B5-'+$short+'-'+[Guid]::NewGuid().ToString('N'))}
$destination=[IO.Path]::GetFullPath($OutputRoot)
if(Test-Path -LiteralPath $destination){throw 'Output must be a new directory; existing data will not be overwritten'}
$report=Get-Content -LiteralPath (Join-Path $project 'build/probe-build.json') -Raw | ConvertFrom-Json
$version=(& git -C $project show "$($commit):version.txt").Trim()
if($version -ne $report.version){throw 'Native build version does not match the selected Git baseline'}
$jar=Join-Path $project 'Contents/mods/EmberRoutesProbe/42/media/java/EmberRoutesProbe.jar'
$jarHash=(Get-FileHash -LiteralPath $jar -Algorithm SHA256).Hash
if($jarHash -ne $report.jarSha256){throw 'Native JAR differs from the existing build report'}
$dirtyJava=& git -C $project diff HEAD --name-only -- java/src/main/java
if($dirtyJava){throw 'Uncommitted Java runtime sources require a separate reviewed build'}
$laterJava=& git -C $project log "--since=$($report.builtAtUtc)" --format=%H -- java/src/main/java
if($laterJava){throw 'Java sources changed after the native build report'}
foreach($dependency in $report.dependencies){
    if((Get-FileHash -LiteralPath $dependency.path -Algorithm SHA256).Hash -ne $dependency.sha256){throw 'Installed dependency differs from the native build report'}
}
New-Item -ItemType Directory -Path $destination | Out-Null
$sourceZip=Join-Path $destination 'source.zip'
& git -c core.autocrlf=false -c core.eol=lf -C $project archive --format=zip "--output=$sourceZip" $commit -- Contents/mods/EmberRoutesProbe tests/pz/B5Acceptance.lua tests/pz/ZZB5AcceptanceMenu.lua
if($LASTEXITCODE -ne 0){throw 'Git archive failed'}
$archive=Join-Path $destination 'source'
Expand-Archive -LiteralPath $sourceZip -DestinationPath $archive
$mod=Join-Path $archive 'Contents/mods/EmberRoutesProbe'
$javaDir=Join-Path $mod '42/media/java'
New-Item -ItemType Directory -Force -Path $javaDir | Out-Null
Copy-Item -LiteralPath $jar -Destination (Join-Path $javaDir 'EmberRoutesProbe.jar')
$lua=Join-Path $mod '42/media/lua/client/EmberRoutesProbe'
foreach($name in @('B5Acceptance.lua','ZZB5AcceptanceMenu.lua')){
    Copy-Item -LiteralPath (Join-Path $archive "tests/pz/$name") -Destination (Join-Path $lua $name)
}
$texts=@{
    EN=@{IGUI_EmberRoutesProbe_B5QA='B.5 QA (disposable world only)';IGUI_EmberRoutesProbe_B5QA_prepare='Prepare persistence fixtures';IGUI_EmberRoutesProbe_B5QA_verify='Verify after full quit and reload'}
    CN=@{IGUI_EmberRoutesProbe_B5QA='B.5 验收（仅一次性世界）';IGUI_EmberRoutesProbe_B5QA_prepare='准备持久化样本';IGUI_EmberRoutesProbe_B5QA_verify='完整退出重进后检查'}
}
foreach($language in @('EN','CN')){
    $path=Join-Path $mod "42/media/lua/shared/Translate/$language/IG_UI.json"
    $json=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    foreach($key in $texts[$language].Keys){$json[$key]=$texts[$language][$key]}
    [IO.File]::WriteAllText($path,($json | ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
}
$files=@(Get-ChildItem -LiteralPath $mod -Recurse -File | ForEach-Object {
    [ordered]@{path=[IO.Path]::GetRelativePath($mod,$_.FullName).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
})
$zip=Join-Path $destination ('EmberRoutesProbe-B5-QA-'+$short+'.zip')
Compress-Archive -LiteralPath $mod -DestinationPath $zip
$manifest=[ordered]@{sourceCommit=$commit;version=$version;qaOnly=$true;nativeRebuilt=$false;
    nativeBuildUtc=$report.builtAtUtc;nativeJarSha256=$jarHash;dependencies=$report.dependencies;
    zipSha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash;files=$files;
    gameRun=$false;diskPersistenceVerified=$false;stageCStarted=$false}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $destination 'manifest.json') -Encoding utf8
Write-Output "QA_PACKAGE $zip"
Write-Output "QA_MOD $mod"
Write-Output 'Game/disk NOT RUN; no installation or publication performed'
