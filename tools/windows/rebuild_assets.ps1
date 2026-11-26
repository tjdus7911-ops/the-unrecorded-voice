# 바이너리 에셋 전체 재생성 (텍스처 → 소품 → 작업실 → 복도 → 평면도 → 효과음·음성)
# 준비: Python 3.13 +  pip install bpy==5.3.0 numpy pillow scipy matplotlib fonttools  + ffmpeg(PATH)
#       음성 샘플은 선택: pip install "sherpa-onnx<2"  + 모델(vits-mimic3-ko_KO-kss_low)을 C:\tts\ 에 풀고 -TtsModel 지정
# 사용: .\tools\windows\rebuild_assets.ps1 [-Render] [-TtsModel C:\tts\vits-mimic3-ko_KO-kss_low]
param([switch]$Render, [string]$TtsModel = "")
$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $root
$steps = @(
    @("텍스처(PBR·데칼)", "tools\textures\gen_pbr.py"),
    @("작업실 텍스처", "tools\blender\gen_studio_textures.py"),
    @("소품 텍스처", "tools\textures\gen_prop_textures.py"),
    @("효과 텍스처", "tools\textures\gen_fx_textures.py"),
    @("주요 오브젝트", "tools\blender\build_props.py"),
    @("작업실", "tools\blender\build_studio.py"),
    @("외부 복도", "tools\blender\build_corridor.py"),
    @("임시 호흡·심장 음원", "tools\audio\make_placeholders.py"),
    @("환경음·효과음", "tools\audio\make_sfx.py")
)
foreach ($s in $steps) {
    Write-Host "== $($s[0]) =="
    $args = @($s[1])
    if ($Render -and ($s[1] -like "*build_*")) { $args += "--render" }
    & python @args
    if ($LASTEXITCODE -ne 0) { throw "실패: $($s[1])" }
}
& python tools\blender\draw_plan.py art\blender\environments\studio\stu_studio.blend art\renders\studio\stu_floorplan.png
if ($TtsModel -ne "") {
    $env:TUV_TTS_MODEL = $TtsModel
    & python tools\audio\make_voice_samples.py
}
Write-Host "완료. Godot에서 다시 임포트하세요:  godot --headless --import --path game" -ForegroundColor Green
