param(
    [string]$Godot = 'D:\Aldean junio\Criaçao_de_Jogos\Usando_Godot\Godot\Godot-4.6\Godot_v4.6.1-stable_win64.exe',
    [string]$Label = 'profile',
    [switch]$DebugOff,
    [switch]$Graphics,
    [switch]$Sphere,
    [switch]$MacroRoute,
    [switch]$SettledRoute,
    [switch]$NoGeology
)
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = Join-Path ([IO.Path]::GetTempPath()) ('planet-profile-' + $Label + '-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $output | Out-Null
$mode = if ($Graphics) { '--windowed --resolution 1100x760' } else { '--headless --resolution 1100x760' }
$extra = if ($DebugOff) { ' --debug-off' } else { '' }
if ($Sphere) { $extra += ' --sphere' }
if ($MacroRoute) { $extra += ' --macro-route' }
if ($SettledRoute) { $extra += ' --settled-route' }
if ($NoGeology) { $extra += ' --no-geology' }
$arguments = $mode + ' --path "' + $projectRoot + '" --script res://tests/planet/planet_profile_route.gd --log-file "' + (Join-Path $output 'engine.log') + '" -- "' + (Join-Path $output 'profile.json') + '"' + $extra
Write-Output "PROFILE_DIR=$output"
$p = Start-Process -FilePath $Godot -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $output 'out.log') -RedirectStandardError (Join-Path $output 'err.log')
if (-not $p.WaitForExit(900000)) { $p.Kill(); $p.WaitForExit(); throw 'Profile timeout' }
$p.Refresh()
Get-Content -LiteralPath (Join-Path $output 'out.log')
Get-Content -LiteralPath (Join-Path $output 'err.log')
if ($p.ExitCode -ne 0 -or (Select-String -LiteralPath (Join-Path $output 'err.log') -Pattern 'SCRIPT ERROR|Parse Error' -Quiet)) { exit 1 }
