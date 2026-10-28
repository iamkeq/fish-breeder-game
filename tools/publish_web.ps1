# Builds the web version and uploads it to itch.io.
#   .\tools\publish_web.ps1 0.2.0
# Needs: Godot 4.7.2 (path below), web export templates, and butler logged in
# (butler.exe login, once). Stops if any unit test fails.
param([Parameter(Mandatory = $true)][string]$Version)

$ErrorActionPreference = "Stop"
$godot = "G:\2026 Downloads\GODOT\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$butler = Join-Path $env:LOCALAPPDATA "butler\butler.exe"
$project = Split-Path $PSScriptRoot -Parent
$target = "figtreegames/fish-breeder-job-simulator:html5"

Push-Location $project
try {
	& $godot --headless --path . -s res://tests/run_tests.gd
	if ($LASTEXITCODE -ne 0) { throw "Unit tests failed; not publishing." }

	New-Item -ItemType Directory -Force "build/web" | Out-Null
	& $godot --headless --path . --export-release "Web" build/web/index.html
	if ($LASTEXITCODE -ne 0) { throw "Web export failed." }

	& $butler push build/web $target --userversion $Version
	if ($LASTEXITCODE -ne 0) { throw "butler push failed." }
	& $butler status $target
}
finally {
	Pop-Location
}
