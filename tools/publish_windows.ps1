# Builds the Windows version and uploads it to itch.io (channel "windows").
#   .\tools\publish_windows.ps1 0.25.0
# Needs: Godot 4.7.2 (path below), Windows export templates, and butler logged
# in (butler.exe login, once). Stops if any unit test fails.
param([Parameter(Mandatory = $true)][string]$Version)

$ErrorActionPreference = "Stop"
$godot = "G:\2026 Downloads\GODOT\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$butler = Join-Path $env:LOCALAPPDATA "butler\butler.exe"
$project = Split-Path $PSScriptRoot -Parent
$target = "figtreegames/fish-breeder-job-simulator:windows"

Push-Location $project
try {
	& $godot --headless --path . -s res://tests/run_tests.gd
	if ($LASTEXITCODE -ne 0) { throw "Unit tests failed; not publishing." }

	if (Test-Path "build/windows") { Remove-Item -Recurse -Force "build/windows" }
	New-Item -ItemType Directory -Force "build/windows" | Out-Null
	& $godot --headless --path . --export-release "Windows Desktop" build/windows/FishBreeder.exe
	if ($LASTEXITCODE -ne 0) { throw "Windows export failed." }

	& $butler push build/windows $target --userversion $Version
	if ($LASTEXITCODE -ne 0) { throw "butler push failed." }
	& $butler status $target
}
finally {
	Pop-Location
}
