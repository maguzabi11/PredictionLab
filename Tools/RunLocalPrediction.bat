@echo off
setlocal

set "PROJECT=%~dp0..\PredictionLab.uproject"
set "EDITOR_EXE="

if defined UE_ROOT set "EDITOR_EXE=%UE_ROOT%\Engine\Binaries\Win64\UnrealEditor.exe"

if not exist "%EDITOR_EXE%" (
    echo UnrealEditor.exe was not found. Set UE_ROOT to your Unreal Engine install directory.
    exit /b 1
)

start "PredictionLab Server" "%EDITOR_EXE%" "%PROJECT%" /Game/Maps/Map1 -server -log -port=7777 -nosteam
timeout /t 4 /nobreak >nul
start "PredictionLab Client 1" "%EDITOR_EXE%" "%PROJECT%" 127.0.0.1:7777 -game -log -windowed -ResX=960 -ResY=540 -WinX=50 -WinY=50 -nosteam
start "PredictionLab Client 2" "%EDITOR_EXE%" "%PROJECT%" 127.0.0.1:7777 -game -log -windowed -ResX=960 -ResY=540 -WinX=1050 -WinY=50 -nosteam
