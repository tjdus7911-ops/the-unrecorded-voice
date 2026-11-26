@echo off
REM Windows: Godot 경로를 인자로 주거나 PATH에 godot 이 있어야 합니다.
set GODOT=%1
if "%GODOT%"=="" set GODOT=godot
if not exist "%~dp0\..\..\game\assets\audio\breathing\PH_breath_calm_01.wav" python "%~dp0\..\audio\make_placeholders.py"
cd /d "%~dp0\..\..\game"
%GODOT% --headless --import --path . >nul 2>&1
%GODOT% --headless --fixed-fps 60 --path . res://scenes/tests/run_tests.tscn
%GODOT% --headless --fixed-fps 60 --path . res://scenes/tests/run_studio_tests.tscn
