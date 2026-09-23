param([string]$Godot = 'D:\Aldean junio\Criaçao_de_Jogos\Usando_Godot\Godot\Godot-4.6\Godot_v4.6.1-stable_win64.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$outputRoot = Join-Path ([IO.Path]::GetTempPath()) ('planet-stage6-' + [guid]::NewGuid().ToString('N'))
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
Write-Output "Logs: $outputRoot"
if ($failed) { exit 1 }
