# The Unrecorded Voice — Windows 개발 환경 점검·설정
# 사용: 저장소(또는 ZIP 보관본) 루트에서  powershell -ExecutionPolicy Bypass -File .\tools\windows\setup.ps1 [-GodotPath "C:\...\Godot_v4.7.2-stable_win64.exe"]
param([string]$GodotPath = "")
$ErrorActionPreference = "Continue"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $root

function Check($name, $cmd) {
    $p = Get-Command $cmd -ErrorAction SilentlyContinue
    if ($p) { Write-Host ("[OK]   {0,-10} {1}" -f $name, $p.Source) ; return $p.Source }
    Write-Host ("[없음] {0,-10} — docs\tech\windows_setup.md 참고" -f $name) -ForegroundColor Yellow
    return $null
}

Write-Host "=== 필수 ==="
Check "git" "git" | Out-Null
Check "git-lfs" "git-lfs" | Out-Null
if ($GodotPath -eq "") {
    $cand = Get-ChildItem -Path "$env:USERPROFILE\Desktop","$env:USERPROFILE\Downloads","C:\Godot" -Filter "Godot_v4.7.2-stable_win64*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cand) { $GodotPath = $cand.FullName }
}
if ($GodotPath -and (Test-Path $GodotPath)) { Write-Host "[OK]   godot      $GodotPath" } else { Write-Host "[없음] godot      — https://godotengine.org/download 에서 4.7.2 (표준판) 설치 후 -GodotPath 지정" -ForegroundColor Yellow }

Write-Host "`n=== 에셋 재생성용 (선택) ==="
$py = Check "python" "python"
Check "ffmpeg" "ffmpeg" | Out-Null
$blender = Get-ChildItem "C:\Program Files\Blender Foundation" -Filter blender.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($blender) { Write-Host "[OK]   blender    $($blender.FullName)" } else { Write-Host "[없음] blender    — .blend 원본을 열려면 Blender 5.3 설치" -ForegroundColor Yellow }
if ($py) {
    & $py -c "import bpy, numpy, PIL, scipy; print('[OK]   python 패키지 bpy', bpy.app.version_string)" 2>$null
    if ($LASTEXITCODE -ne 0) { Write-Host "[없음] python 패키지 — pip install bpy==5.3.0 numpy pillow scipy matplotlib fonttools" -ForegroundColor Yellow }
}

Write-Host "`n=== Git LFS ==="
git lfs install 2>$null | Out-Null
Write-Host "git lfs install 완료"

if ($GodotPath -and (Test-Path $GodotPath)) {
    Write-Host "`n=== Godot 프로젝트 임포트 (처음 1회, 몇 분 걸림) ==="
    & $GodotPath --headless --import --path "$root\game" | Out-Null
    & python "$root\tools\ci\fix_texture_imports.py" 2>$null
    & $GodotPath --headless --import --path "$root\game" | Out-Null
    Write-Host "임포트 완료. 자동 테스트:  .\tools\windows\run_tests.ps1 -GodotPath `"$GodotPath`""
    Write-Host "에디터 열기:              & `"$GodotPath`" -e --path `"$root\game`""
    Write-Host "게임 실행:                & `"$GodotPath`" --path `"$root\game`""
}
