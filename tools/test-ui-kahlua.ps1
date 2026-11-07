param([switch]$Legacy,[switch]$SettlementTabs,[switch]$Preview,[ValidateSet('CN','EN')][string]$Language='CN')
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gameRoot='D:/Software/GameApp/steam/steamapps/common/ProjectZomboid'
$translationPath=Join-Path $projectRoot "Contents/mods/EmberRoutesProbe/42/media/lua/shared/Translate/$Language/IG_UI.json"

function ConvertTo-Dict($path) {
    $dict = New-Object 'System.Collections.Generic.Dictionary[string,string]'
    if (Test-Path $path) {
        $lines = & python -c "import json, sys; sys.stdout.reconfigure(encoding='utf-8'); d=json.load(open(sys.argv[1], encoding='utf-8')); [print(f'{k}\t{v}') for k, v in d.items()]" $path
        foreach ($line in $lines) {
            $parts = $line.Split("`t", 2)
            if ($parts.Length -eq 2) {
                $dict[$parts[0]] = $parts[1]
            }
        }
    }
    return $dict
}

$translations=ConvertTo-Dict $translationPath
$native=ConvertTo-Dict "$gameRoot/media/lua/shared/Translate/$Language/UI.json"
foreach ($key in @('UI_btn_apply','UI_btn_cancel','UI_btn_close')) { if ($native.ContainsKey($key)) { $translations[$key]=$native[$key] } }
$nativeIG=ConvertTo-Dict "$gameRoot/media/lua/shared/Translate/$Language/IG_UI.json"
if ($nativeIG.ContainsKey('IGUI_Name')) { $translations['IGUI_Name']=$nativeIG['IGUI_Name'] }
$itemNames=ConvertTo-Dict "$gameRoot/media/lua/shared/Translate/$Language/ItemName.json"
foreach ($id in @('Base.Hammer','Base.Nails','Base.TinnedBeans','Base.CordlessPhone','Base.WoodenFork','Base.WoodenSpoon')) {
    if ($itemNames.ContainsKey($id)) { $translations["TEST_ItemName_$id"]=$itemNames[$id] }
}
$rows=foreach ($key in $translations.Keys) {
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($translations[$key]))
    "$key`t$encoded"
}
$fixture=Join-Path $projectRoot "build/ui-$Language.tsv"
[IO.File]::WriteAllLines($fixture,[string[]]$rows,[Text.UTF8Encoding]::new($false))
$javaArgs=@('-Dfile.encoding=UTF-8','--class-path',"$gameRoot/*",(Join-Path $projectRoot 'tests/java/KahluaUiTextTest.java'),$fixture,"--language=$Language")
if ($SettlementTabs) {
    $javaArgs=@('-Dfile.encoding=UTF-8','--class-path',"$gameRoot/*",(Join-Path $projectRoot 'tests/java/KahluaLaborTest.java'),"--translations=$fixture",'settlement-tabs-test.lua')
}
if ($Legacy) { $javaArgs+='--legacy' }
if ($Preview -and $SettlementTabs) { $javaArgs+='--preview' }
Push-Location $projectRoot
try { & java @javaArgs; if ($LASTEXITCODE -ne 0) { throw 'Kahlua UI regression failed' } }
finally { Pop-Location }
