# .gitignore 의 'LFS 업로드 불가로 임시 제외' 블록을 지우고 바이너리 에셋을 Git LFS로 스테이징한다.
# 사용: PowerShell에서 저장소 루트에서 실행 →  .\tools\windows\enable_lfs_assets.ps1
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..\..")

git lfs install | Out-Null
$gi = Get-Content .gitignore -Raw -Encoding UTF8
$marker = "# --- 생성물: 임시(PH_) 합성 음원은"
$idx = $gi.IndexOf($marker)
if ($idx -ge 0) {
    $gi = $gi.Substring(0, $idx).TrimEnd() + "`n"
    Set-Content .gitignore $gi -Encoding UTF8 -NoNewline
    Write-Host "임시 제외 블록 제거 완료"
} else {
    Write-Host "임시 제외 블록이 없습니다 (이미 처리됨)"
}
git add .gitignore .gitattributes
git add art game tools docs
git lfs ls-files | Measure-Object | ForEach-Object { Write-Host ("LFS로 추적되는 파일: " + $_.Count) }
Write-Host "이제 'git commit' 후 'git push origin main' 하세요."
