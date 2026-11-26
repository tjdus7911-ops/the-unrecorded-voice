# 자동 테스트 (시스템 39 + 레벨 43). 사용: .\tools\windows\run_tests.ps1 -GodotPath "C:\...\Godot_v4.7.2-stable_win64.exe"
param([Parameter(Mandatory = $true)][string]$GodotPath)
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$fail = 0
foreach ($t in @("run_tests", "run_phase01_tests")) {
    Write-Host "=== $t ==="
    & $GodotPath --headless --fixed-fps 60 --path "$root\game" "res://scenes/tests/$t.tscn" 2>&1 | Select-String -Pattern "PASS|FAIL|passed"
    if ($LASTEXITCODE -ne 0) { $fail++ }
}
if ($fail -eq 0) { Write-Host "모든 테스트 통과" -ForegroundColor Green } else { Write-Host "실패한 테스트 세트: $fail" -ForegroundColor Red; exit 1 }
