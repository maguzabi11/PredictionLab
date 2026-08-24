@echo off
setlocal

set "PROJECT=%~dp0..\PredictionLab.uproject"
set "BUILD_BAT="
set "GIT_CONFIG_COUNT=1"
set "GIT_CONFIG_KEY_0=core.quotePath"
set "GIT_CONFIG_VALUE_0=false"

if defined UE_ROOT set "BUILD_BAT=%UE_ROOT%\Engine\Build\BatchFiles\Build.bat"

if not exist "%BUILD_BAT%" (
    echo Build.bat was not found. Set UE_ROOT to your Unreal Engine install directory.
    exit /b 1
)

call "%BUILD_BAT%" PredictionLabEditor Win64 Development -Project="%PROJECT%" -WaitMutex -NoHotReload
exit /b %ERRORLEVEL%
