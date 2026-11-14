#Requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('Launch','Run','Status','Cancel','Quit')][string]$Action='Launch',
    [ValidateSet('smoke','actions')][string]$Case='smoke',
    [string]$RunDirectory,
    [string]$GameRoot='D:/Software/GameApp/steam/steamapps/common/ProjectZomboid',
    [string]$BuddyMod='D:/Software/GameApp/steam/steamapps/workshop/content/108600/3619862853/mods/ZombieBuddy',
    [ValidateRange(1,900)][int]$TimeoutSeconds=240,
    [switch]$MenuOnly,
    [switch]$NoWait
)
$ErrorActionPreference='Stop'
$project=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$qaBase=[IO.Path]::GetFullPath((Join-Path $project 'build/native-qa'))
if(-not $RunDirectory){
    if($Action -ne 'Launch'){throw 'RunDirectory is required for an existing QA session'}
    $RunDirectory=Join-Path $qaBase ((Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8))
}
$runRoot=[IO.Path]::GetFullPath($RunDirectory)
if(-not $runRoot.StartsWith($qaBase+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'QA runs must be children of this workspace build/native-qa directory'
}
function Write-QaJson([string]$Name,$Value){
    $target=Join-Path $runRoot $Name
    $temporary=$target+'.tmp'
    [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temporary,$target,$true)
}
function Read-QaJson([string]$Name){
    $file=Join-Path $runRoot $Name
    if(Test-Path -LiteralPath $file){return Get-Content -LiteralPath $file -Raw|ConvertFrom-Json}
    return $null
}
function Send-QaCommand([string]$Operation,[string]$CaseId){
    $old=Read-QaJson 'command.json'
    $current=Read-QaJson 'status.json'
    $next=[Math]::Max([long]$old.seq,[long]$current.seq)+1
    Write-QaJson 'command.json' @{format=1;runId=$session.runId;seq=$next;op=$Operation;caseId=$CaseId}
    return $next
}
New-Item -ItemType Directory -Force -Path $runRoot|Out-Null
if($Action -eq 'Launch'){
    $processRecord=Read-QaJson 'process.json'
    if($processRecord){
        $existing=Get-Process -Id $processRecord.pid -ErrorAction SilentlyContinue
        if($existing -and $existing.StartTime.ToUniversalTime().ToString('o') -eq $processRecord.startedUtc){
            throw 'This QA process is still running; use Run/Status/Cancel/Quit'
        }
    }
    $report=Get-Content -LiteralPath (Join-Path $project 'build/probe-build.json') -Raw|ConvertFrom-Json
    $version=(Get-Content -LiteralPath (Join-Path $project 'version.txt') -Raw).Trim()
    if($report.version -ne $version){throw 'Build the current version before launching QA'}
    $jar=Join-Path $project 'Contents/mods/EmberRoutesProbe/42/media/java/EmberRoutesProbe.jar'
    $jarHash=(Get-FileHash -LiteralPath $jar -Algorithm SHA256).Hash
    if($jarHash -ne $report.jarSha256){throw 'QA JAR differs from the build report'}
    foreach($dependency in $report.dependencies){
        if((Get-FileHash -LiteralPath $dependency.path -Algorithm SHA256).Hash -ne $dependency.sha256){throw 'Installed QA dependency changed'}
    }
    $latestJava=Get-ChildItem -LiteralPath (Join-Path $project 'java/src/main/java') -Recurse -Filter '*.java'|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
    $builtUtc=([DateTimeOffset]$report.builtAtUtc).UtcDateTime
    if($latestJava.LastWriteTimeUtc -gt $builtUtc){throw 'Java sources changed after the build'}
    $fingerprintLines=foreach($folder in @('Contents/mods/EmberRoutesProbe','tests/pz/native-qa','java/src/main/java')){
        foreach($file in Get-ChildItem -LiteralPath (Join-Path $project $folder) -File -Recurse|Sort-Object FullName){
            $relative=[IO.Path]::GetRelativePath($project,$file.FullName).Replace('\','/')
            $relative+'|'+(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
    }
    $overrideJar=Join-Path $GameRoot 'pzopt/aot/pzopt.jar'
    $fingerprintLines+=('installed/pzopt.jar|'+(Get-FileHash -LiteralPath $overrideJar -Algorithm SHA256).Hash)
    $sourceHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes(($fingerprintLines -join "`n"))))
    $cache=Join-Path $runRoot 'cache'
    $deployment=Read-QaJson 'deployment.json'
    if($deployment){
        if($deployment.sourceHash -ne $sourceHash -or $deployment.jarSha256 -ne $jarHash){throw 'QA baseline changed; launch into a new RunDirectory'}
    }else{
        if(Test-Path -LiteralPath $cache){throw 'Unidentified QA cache exists; use a new RunDirectory'}
        $mods=Join-Path $cache 'mods'
        New-Item -ItemType Directory -Force -Path $mods|Out-Null
        Copy-Item -LiteralPath (Join-Path $project 'Contents/mods/EmberRoutesProbe') -Destination (Join-Path $mods 'EmberRoutesProbe') -Recurse
        Copy-Item -LiteralPath (Join-Path $project 'tests/pz/native-qa') -Destination (Join-Path $mods 'EmberRoutesNativeQA') -Recurse
        Copy-Item -LiteralPath $BuddyMod -Destination (Join-Path $mods 'ZombieBuddy') -Recurse
        [IO.File]::WriteAllText((Join-Path $cache 'options.ini'),"version=8`nwidth=1280`nheight=720`nfullScreen=false`nborderless=false`nframeRate=60`nfocusloss=false`nlanguage=EN`n",[Text.UTF8Encoding]::new($false))
        Write-QaJson 'deployment.json' @{sourceHash=$sourceHash;jarSha256=$jarHash;version=$version;files=$fingerprintLines}
    }
    # Current pinned B42 initializes this sentinel before honoring the chosen mod list.
    # The normal user's profile is never read or modified.
    $mods=Join-Path $cache 'mods'
    [IO.File]::WriteAllText((Join-Path $mods 'reset-mods-42_00.txt'),"If this file does not exist, default.txt will be reset to empty (no mods active).`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $mods 'default.txt'),"VERSION = 1,`nmods`n{`n mod = ZombieBuddy,`n mod = EmberRoutesProbe,`n mod = EmberRoutesNativeQA,`n}`nmaps`n{`n}`n",[Text.UTF8Encoding]::new($false))
    $session=@{format=1;runId=[Guid]::NewGuid().ToString();version=$version;jarSha256=$jarHash;sourceHash=$sourceHash;saveName='ERQA_House';autoStart=(-not $MenuOnly)}
    Write-QaJson 'session.json' $session
    # Clear the mailbox by replacing it with the new run's first request, never replay an old run.
    Write-QaJson 'command.json' @{format=1;runId=$session.runId;seq=1;op='run';caseId=$Case}
    $requestedSequence=1
    function Quote-QaArgument([string]$Text){return '"'+[regex]::Replace($Text,'(\*)"','$1$1\"').TrimEnd('\')+'"'}
    $libraryPath=(Join-Path $GameRoot 'win64')+';'+$GameRoot+';'+(Join-Path $GameRoot 'jre64/bin')
    $qaJvmArgs=@('-Xmx4096m','--enable-native-access=ALL-UNNAMED','--add-exports=java.base/jdk.internal.misc=ALL-UNNAMED',
        '-Djava.awt.headless=true',('-Djava.library.path='+$libraryPath),'-agentlib:zbNative=policy=allow-all',
        ('-Demberroutes.qa.root='+$runRoot),'-Dzomboid.steam=0','-cp',($overrideJar+';'+(Join-Path $GameRoot 'projectzomboid.jar')),
        'zombie.gameStates.MainScreenState',('-cachedir='+$cache),'-modfolders','mods','-nosteam','-debug')
    $commandLine=($qaJvmArgs|ForEach-Object {Quote-QaArgument $_}) -join ' '
    $process=Start-Process -FilePath (Join-Path $GameRoot 'jre64/bin/java.exe') -ArgumentList $commandLine -WorkingDirectory $GameRoot -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput (Join-Path $runRoot ('stdout-'+$session.runId+'.txt')) -RedirectStandardError (Join-Path $runRoot ('stderr-'+$session.runId+'.txt'))
    Write-QaJson 'process.json' @{pid=$process.Id;startedUtc=$process.StartTime.ToUniversalTime().ToString('o');runId=$session.runId}
    Write-Output "QA_STARTED pid=$($process.Id) run=$($session.runId) directory=$runRoot"
    if($MenuOnly -or $NoWait){return}
}else{
    $session=Read-QaJson 'session.json'
    if(-not $session){throw 'QA session.json is missing'}
    $requestedSequence=Send-QaCommand $Action.ToLowerInvariant() $Case
    if($Action -eq 'Status'){Read-QaJson 'status.json'|ConvertTo-Json -Depth 12;return}
    if($NoWait){Write-Output "QA_SENT seq=$requestedSequence action=$Action directory=$runRoot";return}
}
$until=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
$previous=''
while([DateTime]::UtcNow -lt $until){
    $status=Read-QaJson 'status.json'
    if($status -and $status.runId -eq $session.runId){
        $summary="$($status.state) $($status.phase) seq=$($status.seq)"
        if($summary -ne $previous){Write-Output $summary;$previous=$summary}
        if($status.commandError){throw "QA command rejected: $($status.commandError)"}
    }
    $result=Read-QaJson 'result.json'
    if($Action -ne 'Quit' -and $result -and $result.runId -eq $session.runId -and ($result.seq -eq $requestedSequence -or ($result.state -eq 'CANCELLED' -and $result.evidence.requestSequence -eq $requestedSequence))){
        $result|ConvertTo-Json -Depth 12
        if($result.state -ne 'PASS' -and -not ($Action -eq 'Cancel' -and $result.state -eq 'CANCELLED')){throw "QA terminal state: $($result.state)"}
        return
    }
    $record=Read-QaJson 'process.json'
    $running=$record -and (Get-Process -Id $record.pid -ErrorAction SilentlyContinue)
    if(-not $running){
        if($Action -eq 'Quit'){Write-Output 'QA_EXITED';return}
        throw "QA process exited without the requested result; inspect $runRoot"
    }
    Start-Sleep -Milliseconds 1000
}
throw "QA_TIMEOUT: result unverified; process and world retained at $runRoot"
