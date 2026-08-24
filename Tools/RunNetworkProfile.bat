@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "PROJECT=%~dp0..\PredictionLab.uproject"
set "EDITOR_EXE="
set "PROFILE=%~1"
set "DRY_RUN=0"

rem Phase 7B repeatable-run contract. Do not change these per profile: all
rem profiles replay the same 60 second, 60 Hz client input sequence three times.
set "RUN_COUNT=3"
set "AUTO_INPUT_DURATION_SECONDS=60"
set "SERVER_STARTUP_SECONDS=4"
set "CLIENT_JOIN_GRACE_SECONDS=3"
set /a RUN_ACTIVE_SECONDS=%AUTO_INPUT_DURATION_SECONDS% + %CLIENT_JOIN_GRACE_SECONDS%
set "INTER_RUN_SETTLE_SECONDS=3"
set "AUTO_INPUT_ARGS=-PredictionLabAutoInput=1"
set "BATCH_EXIT_CODE=0"

if "%PROFILE%"=="" set "PROFILE=Normal"
if /I "%PROFILE%"=="--dry-run" (
    set "PROFILE=Normal"
    set "DRY_RUN=1"
)
if /I "%~2"=="--dry-run" set "DRY_RUN=1"
if /I "%PROFILE%"=="help" goto :usage
if /I "%PROFILE%"=="--help" goto :usage
if /I "%PROFILE%"=="/?" goto :usage

rem All is deliberately explicit: it launches 15 sequential runs (five profiles x three).
if /I "%PROFILE%"=="All" goto :run_all_profiles

if defined UE_ROOT set "EDITOR_EXE=%UE_ROOT%\Engine\Binaries\Win64\UnrealEditor.exe"

if not exist "%EDITOR_EXE%" (
    echo UnrealEditor.exe was not found. Set UE_ROOT to your Unreal Engine install directory.
    exit /b 1
)

set "PROFILE_NAME="
set "PACKET_ARGS="
set "EXTRA_ARGS="
set "PROFILE_NOTES="

if /I "%PROFILE%"=="Normal" (
    set "PROFILE_NAME=Normal"
    set "PROFILE_NOTES=Baseline local dedicated server run without packet simulation flags."
) else if /I "%PROFILE%"=="HighLatency" (
    set "PROFILE_NAME=HighLatency"
    set "PACKET_ARGS=-PktLag=150"
    set "PROFILE_NOTES=Adds fixed packet lag to expose PendingInput and replay pressure."
) else if /I "%PROFILE%"=="Jitter" (
    set "PROFILE_NAME=Jitter"
    set "PACKET_ARGS=-PktLag=80 -PktLagVariance=60"
    set "PROFILE_NOTES=Adds lag variance to make snapshot arrival cadence unstable."
) else if /I "%PROFILE%"=="PacketLoss" (
    set "PROFILE_NAME=PacketLoss"
    set "PACKET_ARGS=-PktLag=80 -PktLoss=5"
    set "PROFILE_NOTES=Adds moderate packet loss to show unreliable input and snapshot behavior."
) else if /I "%PROFILE%"=="BadClient" (
    set "PROFILE_NAME=BadClient"
    set "PACKET_ARGS=-PktLag=80"
    set "EXTRA_ARGS=-PredictionLabBadClient=1"
    set "PROFILE_NOTES=Launch preset reserved for a later bad-client code hook; today it records the intended test mode."
) else (
    echo Unknown network profile "%PROFILE%".
    echo(
    goto :usage
)

for /f %%I in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss_fff"') do set "RUN_STAMP=%%I"
set "PREDICTIONLAB_EDITOR_EXE=%EDITOR_EXE%"
set "PREDICTIONLAB_PROJECT=%PROJECT%"
set "SERVER_COMMON_ARGS=-nosteam %PACKET_ARGS% %EXTRA_ARGS%"
set "CLIENT_COMMON_ARGS=-nosteam %PACKET_ARGS% %EXTRA_ARGS% %AUTO_INPUT_ARGS%"
set "PREDICTIONLAB_SERVER_COMMON_ARGS=%SERVER_COMMON_ARGS%"
set "PREDICTIONLAB_CLIENT_COMMON_ARGS=%CLIENT_COMMON_ARGS%"

echo Profile: %PROFILE_NAME%
echo Runs: %RUN_COUNT%
echo AutoInput: %AUTO_INPUT_ARGS% ^(%AUTO_INPUT_DURATION_SECONDS%s at 60 Hz^)
echo Run active window: %RUN_ACTIVE_SECONDS%s ^(%CLIENT_JOIN_GRACE_SECONDS%s client join grace included^)
echo PacketArgs: %PACKET_ARGS%
echo ExtraArgs: %EXTRA_ARGS%
echo(

for /L %%R in (1,1,%RUN_COUNT%) do (
    set "RUN_INDEX=00%%R"
    set "RUN_INDEX=!RUN_INDEX:~-2!"
    set "RUN_ID=%RUN_STAMP%_%PROFILE_NAME%_R!RUN_INDEX!"
    set "RUN_DIR=%~dp0..\Saved\PredictionLab\Runs\!RUN_ID!"
    set "SERVER_LOG=!RUN_DIR!\server.log"
    set "CLIENT1_LOG=!RUN_DIR!\client1.log"
    set "CLIENT2_LOG=!RUN_DIR!\client2.log"

    if not exist "!RUN_DIR!" mkdir "!RUN_DIR!"
    call :write_metadata

    echo [%%R/%RUN_COUNT%] RunId: !RUN_ID!
    echo          RunDir: !RUN_DIR!

    if "!DRY_RUN!"=="1" (
        echo          Dry run only. Commands were written to metadata.txt.
    ) else (
        call :launch_server
        if errorlevel 1 (
            set "BATCH_EXIT_CODE=1"
            echo          Server launch failed; this run was skipped.
        ) else (
            timeout /t %SERVER_STARTUP_SECONDS% /nobreak >nul
            call :launch_client1
            call :launch_client2

            if not defined CLIENT1_PID set "BATCH_EXIT_CODE=1"
            if not defined CLIENT2_PID set "BATCH_EXIT_CODE=1"

            if defined CLIENT1_PID if defined CLIENT2_PID (
                echo          Server PID !SERVER_PID!, clients !CLIENT1_PID! / !CLIENT2_PID!.
                echo          Waiting %RUN_ACTIVE_SECONDS%s for the 60 second automatic input run...
                timeout /t %RUN_ACTIVE_SECONDS% /nobreak >nul
            ) else (
                echo          One or more client launches failed; stopping this run.
            )

            call :stop_run_processes
            timeout /t %INTER_RUN_SETTLE_SECONDS% /nobreak >nul
        )
    )
)

if "%DRY_RUN%"=="1" goto :dry_run_complete
echo(
echo Completed %RUN_COUNT% %PROFILE_NAME% run(s). Logs are under:
echo %~dp0..\Saved\PredictionLab\Runs\%RUN_STAMP%_%PROFILE_NAME%_R##
goto :finish

:dry_run_complete
echo(
echo Dry run complete. No Unreal process was started.

:finish
exit /b %BATCH_EXIT_CODE%

:run_all_profiles
set "ALL_EXIT_CODE=0"
echo Running every network profile three times each.
call "%~f0" Normal %~2
if errorlevel 1 set "ALL_EXIT_CODE=1"
call "%~f0" HighLatency %~2
if errorlevel 1 set "ALL_EXIT_CODE=1"
call "%~f0" Jitter %~2
if errorlevel 1 set "ALL_EXIT_CODE=1"
call "%~f0" PacketLoss %~2
if errorlevel 1 set "ALL_EXIT_CODE=1"
call "%~f0" BadClient %~2
if errorlevel 1 set "ALL_EXIT_CODE=1"
exit /b %ALL_EXIT_CODE%

:write_metadata
(
    echo RunId=%RUN_ID%
    echo RunIndex=%RUN_INDEX%/%RUN_COUNT%
    echo Profile=%PROFILE_NAME%
    echo CreatedAt=%DATE% %TIME%
    echo Project=%PROJECT%
    echo Editor=%EDITOR_EXE%
    echo PacketArgs=%PACKET_ARGS%
    echo ExtraArgs=%EXTRA_ARGS%
    echo AutoInputArgs=%AUTO_INPUT_ARGS%
    echo AutoInputDurationSeconds=%AUTO_INPUT_DURATION_SECONDS%
    echo AutoInputSampleRateHz=60
    echo AutoInputCommandCount=3600
    echo ServerStartupSeconds=%SERVER_STARTUP_SECONDS%
    echo ClientJoinGraceSeconds=%CLIENT_JOIN_GRACE_SECONDS%
    echo RunActiveSeconds=%RUN_ACTIVE_SECONDS%
    echo InterRunSettleSeconds=%INTER_RUN_SETTLE_SECONDS%
    echo Notes=%PROFILE_NOTES%
    echo ServerLog=%SERVER_LOG%
    echo Client1Log=%CLIENT1_LOG%
    echo Client2Log=%CLIENT2_LOG%
    echo(
    echo ServerCommand="%EDITOR_EXE%" "%PROJECT%" /Game/Maps/Map1 -server -log -abslog="%SERVER_LOG%" -port=7777 %SERVER_COMMON_ARGS%
    echo Client1Command="%EDITOR_EXE%" "%PROJECT%" 127.0.0.1:7777 -game -log -abslog="%CLIENT1_LOG%" -windowed -ResX=960 -ResY=540 -WinX=50 -WinY=50 %CLIENT_COMMON_ARGS%
    echo Client2Command="%EDITOR_EXE%" "%PROJECT%" 127.0.0.1:7777 -game -log -abslog="%CLIENT2_LOG%" -windowed -ResX=960 -ResY=540 -WinX=1050 -WinY=50 %CLIENT_COMMON_ARGS%
) > "%RUN_DIR%\metadata.txt"
exit /b 0

:launch_server
set "SERVER_PID="
set "PREDICTIONLAB_SERVER_LOG=%SERVER_LOG%"
for /f %%P in ('powershell -NoProfile -Command "$q = [char]34; $arguments = $q + $env:PREDICTIONLAB_PROJECT + $q + ' /Game/Maps/Map1 -server -log -abslog=' + $q + $env:PREDICTIONLAB_SERVER_LOG + $q + ' -port=7777 ' + $env:PREDICTIONLAB_SERVER_COMMON_ARGS; $p = Start-Process -FilePath $env:PREDICTIONLAB_EDITOR_EXE -ArgumentList $arguments -PassThru; $p.Id"') do set "SERVER_PID=%%P"
if not defined SERVER_PID exit /b 1
exit /b 0

:launch_client1
set "CLIENT1_PID="
set "PREDICTIONLAB_CLIENT1_LOG=%CLIENT1_LOG%"
for /f %%P in ('powershell -NoProfile -Command "$q = [char]34; $arguments = $q + $env:PREDICTIONLAB_PROJECT + $q + ' 127.0.0.1:7777 -game -log -abslog=' + $q + $env:PREDICTIONLAB_CLIENT1_LOG + $q + ' -windowed -ResX=960 -ResY=540 -WinX=50 -WinY=50 ' + $env:PREDICTIONLAB_CLIENT_COMMON_ARGS; $p = Start-Process -FilePath $env:PREDICTIONLAB_EDITOR_EXE -ArgumentList $arguments -PassThru; $p.Id"') do set "CLIENT1_PID=%%P"
exit /b 0

:launch_client2
set "CLIENT2_PID="
set "PREDICTIONLAB_CLIENT2_LOG=%CLIENT2_LOG%"
for /f %%P in ('powershell -NoProfile -Command "$q = [char]34; $arguments = $q + $env:PREDICTIONLAB_PROJECT + $q + ' 127.0.0.1:7777 -game -log -abslog=' + $q + $env:PREDICTIONLAB_CLIENT2_LOG + $q + ' -windowed -ResX=960 -ResY=540 -WinX=1050 -WinY=50 ' + $env:PREDICTIONLAB_CLIENT_COMMON_ARGS; $p = Start-Process -FilePath $env:PREDICTIONLAB_EDITOR_EXE -ArgumentList $arguments -PassThru; $p.Id"') do set "CLIENT2_PID=%%P"
exit /b 0

:stop_run_processes
echo          Stopping run processes.
if defined CLIENT2_PID taskkill /PID %CLIENT2_PID% /T /F >nul 2>&1
if defined CLIENT1_PID taskkill /PID %CLIENT1_PID% /T /F >nul 2>&1
if defined SERVER_PID taskkill /PID %SERVER_PID% /T /F >nul 2>&1
set "SERVER_PID="
set "CLIENT1_PID="
set "CLIENT2_PID="
exit /b 0

:usage
echo Usage:
echo   Tools\RunNetworkProfile.bat [Normal^|HighLatency^|Jitter^|PacketLoss^|BadClient^|All] [--dry-run]
echo(
echo Each selected profile runs three sequential dedicated-server + two-client tests.
echo Both clients receive -PredictionLabAutoInput=1 and replay 3,600 commands over 60 seconds.
echo The script waits an additional 3 seconds for client join, then terminates only the PIDs it launched.
echo.
echo Examples:
echo   Tools\RunNetworkProfile.bat Normal
echo   Tools\RunNetworkProfile.bat Jitter --dry-run
echo   Tools\RunNetworkProfile.bat All
echo.
echo Use --dry-run to create per-run metadata and verify commands without starting Unreal processes.
exit /b 1
