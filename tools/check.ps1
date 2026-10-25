# tools/check.ps1
$ErrorActionPreference = "Stop"
$Godot = if ($env:GODOT) { $env:GODOT } else { "godot" }

& $Godot --headless --path . --import
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Godot --headless --path . -s res://tools/scene_smoke.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $Godot --headless --path . -s res://tools/run_tests.gd
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Output "CHECK OK"
