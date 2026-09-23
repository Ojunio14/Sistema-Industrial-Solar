param(
    [string]$Godot = 'D:\Aldean junio\Criaçao_de_Jogos\Usando_Godot\Godot\Godot-4.6\Godot_v4.6.1-stable_win64.exe',
    [switch]$DebugOnly,
    [switch]$Geology,
    [switch]$Climate,
    [switch]$Materials
)
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = Join-Path ([IO.Path]::GetTempPath()) ('planet-terrain-visual-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output | Out-Null
Write-Output "VISUAL_DIR=$output"
$arguments = '--windowed --resolution 1100x760 --path "' + $projectRoot + '" --script res://tests/planet/planet_terrain_visual.gd --log-file "' + (Join-Path $output 'engine.log') + '" -- "' + $output + '"'
if ($DebugOnly) { $arguments += ' --debug-only' }
if ($Geology) { $arguments += ' --geology' }
if ($Climate) { $arguments += ' --climate' }
if ($Materials) { $arguments += ' --materials' }
$p = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'out.log') -RedirectStandardError (Join-Path $output 'err.log')
if (-not $p.WaitForExit(900000)) { $p.Kill(); $p.WaitForExit(); throw 'Visual timeout' }
$p.Refresh()
Get-Content -LiteralPath (Join-Path $output 'out.log')
Get-Content -LiteralPath (Join-Path $output 'err.log')
if ($p.ExitCode -ne 0 -or (Select-String -LiteralPath (Join-Path $output 'err.log') -Pattern 'SCRIPT ERROR|Parse Error|VISUAL_FAILED|SHADER ERROR|Shader compilation failed' -Quiet)) { exit 1 }
