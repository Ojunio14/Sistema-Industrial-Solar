param([string]$Godot = 'D:\Aldean junio\Criaçao_de_Jogos\Usando_Godot\Godot\Godot-4.6\Godot_v4.6.1-stable_win64.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$outputRoot = Join-Path ([IO.Path]::GetTempPath()) ('planet-stage10-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$cases = [ordered]@{
    import = '--editor --import --quit'
    main = '--quit-after 180'
    cameras = '--script res://tests/cameras/camera_manager_test.gd'
    foundation = '--script res://tests/planet/planet_foundation_test.gd'
    terrain = '--script res://tests/planet/planet_terrain_test.gd'
    contracts_a = '--script res://tests/planet/surface_contract_test.gd'
    contracts_b = '--script res://tests/planet/surface_contract_test.gd'
    lod = '--script res://tests/planet/planet_lod_test.gd'
    geology_a = '--script res://tests/planet/geology_test.gd'
    geology_b = '--script res://tests/planet/geology_test.gd'
    climate_a = '--script res://tests/planet/climate_test.gd'
    climate_b = '--script res://tests/planet/climate_test.gd'
    biome_a = '--script res://tests/planet/biome_test.gd'
    biome_b = '--script res://tests/planet/biome_test.gd'
    relief_a = '--script res://tests/planet/relief_test.gd'
    relief_b = '--script res://tests/planet/relief_test.gd'
}
$failed = $false
foreach ($name in $cases.Keys) {
    $stdout = Join-Path $outputRoot ($name + '.out.log')
    $stderr = Join-Path $outputRoot ($name + '.err.log')
    $arguments = '--headless --path "' + $projectRoot + '" --log-file "' + (Join-Path $outputRoot ($name + '.engine.log')) + '" ' + $cases[$name]
    $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $process.WaitForExit(180000)) { $process.Kill(); $process.WaitForExit(); $failed = $true }
    $process.Refresh()
    Write-Output "$name exit=$($process.ExitCode)"
    Get-Content -LiteralPath $stdout -Tail 5
    Get-Content -LiteralPath $stderr
    if ($process.ExitCode -ne 0 -or (Select-String -LiteralPath @($stdout,$stderr) -Pattern 'SCRIPT ERROR|Parse Error|TEST_FAILED|SHADER ERROR|^ERROR:' -Quiet)) { $failed = $true }
}
$surfacePrints = @()
foreach ($case in @('contracts_a','contracts_b')) {
    $match = Select-String -LiteralPath (Join-Path $outputRoot ($case + '.out.log')) -Pattern 'SURFACE_CONTRACT ([0-9a-f]{64})'
    if ($match) { $surfacePrints += $match.Matches[0].Groups[1].Value }
}
if ($surfacePrints.Count -ne 2 -or $surfacePrints[0] -ne $surfacePrints[1]) {
    Write-Output 'Natural surface fingerprint differs between processes.'
    $failed = $true
}
$fingerprints = @()
foreach ($case in @('geology_a', 'geology_b')) {
    $log = Join-Path $outputRoot ($case + '.out.log')
    $match = Select-String -LiteralPath $log -Pattern 'GEOLOGY fingerprint=([0-9a-f]{64})'
    if ($match) { $fingerprints += $match.Matches[0].Groups[1].Value }
}
if ($fingerprints.Count -ne 2 -or $fingerprints[0] -ne $fingerprints[1]) {
    Write-Output 'Geology fingerprint differs between processes.'
    $failed = $true
}
$climateFingerprints = @()
foreach ($case in @('climate_a', 'climate_b')) {
    $log = Join-Path $outputRoot ($case + '.out.log')
    $match = Select-String -LiteralPath $log -Pattern 'CLIMATE fingerprint=([0-9a-f]{64})'
    if ($match) { $climateFingerprints += $match.Matches[0].Groups[1].Value }
}
if ($climateFingerprints.Count -ne 2 -or $climateFingerprints[0] -ne $climateFingerprints[1]) {
    Write-Output 'Climate fingerprint differs between processes.'
    $failed = $true
}
$biomeFingerprints = @()
foreach ($case in @('biome_a', 'biome_b')) {
    $log = Join-Path $outputRoot ($case + '.out.log')
    $match = Select-String -LiteralPath $log -Pattern 'BIOME fingerprint=([0-9a-f]{64})'
    if ($match) { $biomeFingerprints += $match.Matches[0].Groups[1].Value }
}
if ($biomeFingerprints.Count -ne 2 -or $biomeFingerprints[0] -ne $biomeFingerprints[1]) {
    Write-Output 'Biome fingerprint differs between processes.'
    $failed = $true
}
$reliefFingerprints = @()
foreach ($case in @('relief_a', 'relief_b')) {
    $log = Join-Path $outputRoot ($case + '.out.log')
    $match = Select-String -LiteralPath $log -Pattern 'RELIEF fingerprint=([0-9a-f]{64})'
    if ($match) { $reliefFingerprints += $match.Matches[0].Groups[1].Value }
}
if ($reliefFingerprints.Count -ne 2 -or $reliefFingerprints[0] -ne $reliefFingerprints[1]) {
    Write-Output 'Relief fingerprint differs between processes.'
    $failed = $true
}
Write-Output "Logs: $outputRoot"
if ($failed) { exit 1 }
