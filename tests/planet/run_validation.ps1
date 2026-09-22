param(
    [string]$Godot = 'D:\Aldean junio\Criaçao_de_Jogos\Usando_Godot\Godot\Godot-4.6\Godot_v4.6.1-stable_win64.exe',
    [string]$Only = '',
    [string]$Extra = ''
)
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$outputRoot = Join-Path ([IO.Path]::GetTempPath()) ('planet-validation-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outputRoot | Out-Null
$cases = [ordered]@{
    import = '--import'
    main = '--quit-after 120'
    cameras = '--script res://tests/cameras/camera_manager_test.gd'
    foundation = '--script res://tests/planet/planet_foundation_test.gd'
    quadtree = '--script res://tests/planet/planet_quadtree_test.gd'
    terrain = '--script res://tests/planet/planet_terrain_test.gd'
    determinism_a = '--script res://tests/planet/planet_terrain_test.gd -- --determinism-only'
    determinism_b = '--script res://tests/planet/planet_terrain_test.gd -- --determinism-only'
}
$failed = $false
$fingerprints = @()
foreach ($name in $cases.Keys) {
    if ($Only -and $name -ne $Only) { continue }
    $stdout = Join-Path $outputRoot ($name + '.out.log')
    $stderr = Join-Path $outputRoot ($name + '.err.log')
    $arguments = '--headless --path "' + $projectRoot + '" --log-file "' + (Join-Path $outputRoot ($name + '.engine.log')) + '" ' + $cases[$name] + ' ' + $Extra
    $process = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if (-not $process.WaitForExit(180000)) {
        $process.Kill()
        $process.WaitForExit()
        $failed = $true
        Write-Output "$name TIMEOUT"
    }
    $process.Refresh()
    Write-Output "$name exit=$($process.ExitCode)"
    Get-Content -LiteralPath $stdout
    Get-Content -LiteralPath $stderr
    if ($name -like 'determinism_*') {
        $capture = Select-String -LiteralPath $stdout -Pattern '"fingerprint":"([0-9a-f]+)"'
        if ($capture) { $fingerprints += $capture.Matches[0].Groups[1].Value } else { $failed = $true }
    }
    if ($process.ExitCode -ne 0 -or (Select-String -LiteralPath $stderr -Pattern 'SCRIPT ERROR|Parse Error|TEST_FAILED' -Quiet)) { $failed = $true }
}
if (-not $Only) {
    if ($fingerprints.Count -eq 2 -and $fingerprints[0] -eq $fingerprints[1]) {
        Write-Output "TERRAIN_CROSS_PROCESS_DETERMINISM_OK $($fingerprints[0])"
    } else { $failed = $true; Write-Output 'TERRAIN_CROSS_PROCESS_DETERMINISM_FAILED' }
}
Write-Output "Logs: $outputRoot"
if ($failed) { exit 1 }
