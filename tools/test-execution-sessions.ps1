param([string]$GameRoot = 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid')
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$logRoot = Join-Path $projectRoot 'build/logs'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
Push-Location $projectRoot
try {
    & java '--class-path' "$GameRoot/*" (Join-Path $projectRoot 'tests/java/KahluaLaborTest.java') 'execution-sessions-test.lua' 2>&1 |
        Tee-Object -FilePath (Join-Path $logRoot 'execution-sessions-kahlua.txt')
    if ($LASTEXITCODE -ne 0) { throw 'Execution session contract regression failed' }
}
finally { Pop-Location }
