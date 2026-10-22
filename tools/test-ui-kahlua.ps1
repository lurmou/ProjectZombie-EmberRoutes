param([switch]$Legacy,[switch]$SettlementTabs,[switch]$Preview,[ValidateSet('CN','EN')][string]$Language='CN')
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gameRoot='D:/Software/GameApp/steam/steamapps/common/ProjectZomboid'
$translationPath=Join-Path $projectRoot "Contents/mods/EmberRoutesProbe/42/media/lua/shared/Translate/$Language/IG_UI.json"
$translations=Get-Content -LiteralPath $translationPath -Raw | ConvertFrom-Json -AsHashtable
$native=Get-Content -LiteralPath "$gameRoot/media/lua/shared/Translate/$Language/UI.json" -Raw | ConvertFrom-Json -AsHashtable
foreach ($key in @('UI_btn_apply','UI_btn_cancel','UI_btn_close')) { $translations[$key]=$native[$key] }
$nativeIG=Get-Content -LiteralPath "$gameRoot/media/lua/shared/Translate/$Language/IG_UI.json" -Raw | ConvertFrom-Json -AsHashtable
$translations['IGUI_Name']=$nativeIG['IGUI_Name']
$itemNames=Get-Content -LiteralPath "$gameRoot/media/lua/shared/Translate/$Language/ItemName.json" -Raw | ConvertFrom-Json -AsHashtable
foreach ($id in @('Base.Hammer','Base.Nails','Base.TinnedBeans','Base.CordlessPhone','Base.WoodenFork','Base.WoodenSpoon')) {
    if ($itemNames.ContainsKey($id)) { $translations["TEST_ItemName_$id"]=$itemNames[$id] }
}
$rows=foreach ($key in $translations.Keys) {
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($translations[$key]))
    "$key`t$encoded"
}
$fixture=Join-Path $projectRoot "build/ui-$Language.tsv"
[IO.File]::WriteAllLines($fixture,[string[]]$rows,[Text.UTF8Encoding]::new($false))
$javaArgs=@('--class-path',"$gameRoot/*",(Join-Path $projectRoot 'tests/java/KahluaUiTextTest.java'),$fixture,"--language=$Language")
if ($SettlementTabs) {
    $javaArgs=@('--class-path',"$gameRoot/*",(Join-Path $projectRoot 'tests/java/KahluaLaborTest.java'),"--translations=$fixture",'settlement-tabs-test.lua','logistics-page-test.lua')
}
if ($Legacy) { $javaArgs+='--legacy' }
if ($Preview -and $SettlementTabs) { $javaArgs+='--preview' }
Push-Location $projectRoot
try { & java @javaArgs; if ($LASTEXITCODE -ne 0) { throw 'Kahlua UI regression failed' } }
finally { Pop-Location }
