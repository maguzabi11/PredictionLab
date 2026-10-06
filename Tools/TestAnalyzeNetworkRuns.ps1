[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('PredictionLabAnalyzeTest-' + [guid]::NewGuid().ToString('N'))
$analyzer = Join-Path $PSScriptRoot 'AnalyzeNetworkRuns.ps1'
$waiter = Join-Path $PSScriptRoot 'WaitForAutoInput.ps1'

function Assert-Equal {
    param($Expected, $Actual, [string] $Description)
    if ($Expected -ne $Actual) { throw "$Description`: expected '$Expected', got '$Actual'" }
}

function Write-Text {
    param([string] $Path, [string[]] $Lines)
    [System.IO.File]::WriteAllText($Path, ($Lines -join "`r`n") + "`r`n", $utf8)
}

function New-Run {
    param([string] $Name, [string] $Profile, [string[]] $Client1, [string[]] $Client2)
    $directory = Join-Path $testRoot $Name
    $null = New-Item -ItemType Directory -Path $directory
    Write-Text (Join-Path $directory 'metadata.txt') @(
        "RunId=$Name", "Profile=$Profile", 'AutoInputCommandCount=3600', 'PacketArgs='
    )
    Write-Text (Join-Path $directory 'server.log') @(
        '[2026.09.28-12.00.00:000][  1]LogPredictionLab: Server processed pawn=PredictionLabPawn_0 sequence=1 move=(1.00, 0.00) dash=false'
    )
    Write-Text (Join-Path $directory 'client1.log') $Client1
    Write-Text (Join-Path $directory 'client2.log') $Client2
}

try {
    $null = New-Item -ItemType Directory -Path $testRoot
    $prefix = '[2026.09.28-12.00.00:000][  1]LogPredictionLab: '
    $completion = $prefix + 'AutoInput completed pawn=PredictionLabPawn_0 duration=60s commands=3600'
    $client1 = New-Object 'System.Collections.Generic.List[string]'
    foreach ($number in 1..18) {
        $client1.Add($prefix + "Client ack pawn=PredictionLabPawn_0 ack=$number pending=$number beforeError=0.00")
    }
    $client1.Add($prefix + 'Client reconcile pawn=PredictionLabPawn_0 ack=19 beforeError=10.00 replayed=2 correction=5.00 pending=19')
    $client1.Add($prefix + 'Client ack(no-history) pawn=PredictionLabPawn_0 ack=20 pending=20')
    $client1.Add($completion)
    $client2 = @(($prefix + 'Client ack pawn=PredictionLabPawn_0 ack=1 pending=0 beforeError=0.00'), $completion)
    New-Run 'run_normal_01' 'Normal' $client1.ToArray() $client2
    New-Run 'run_normal_02' 'Normal' $client1.ToArray() $client2
    New-Run 'run_normal_incomplete' 'Normal' @($prefix + 'Client ack pawn=PredictionLabPawn_0 ack=1 pending=99 beforeError=99.00') $client2
    New-Run 'run_normal_old_schema' 'Normal' @(
        ($prefix + 'Client reconcile pawn=PredictionLabPawn_0 ack=1 beforeError=8.00 replayed=1 correction=8.00'),
        $completion
    ) $client2

    & powershell -NoProfile -ExecutionPolicy Bypass -File $analyzer -RunsRoot $testRoot -Profiles Normal | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Analyzer returned exit code $LASTEXITCODE" }

    $one = Get-Content (Join-Path $testRoot 'run_normal_01\summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal 'complete' $one.status "complete run status ($($one.reasons -join '; '))"
    Assert-Equal 21 $one.combined.ack_count 'ACK count includes no-history'
    Assert-Equal 1 $one.combined.reconcile_count 'reconcile count'
    Assert-Equal 1 $one.combined.no_history_count 'no-history count'
    Assert-Equal 0.05 $one.combined.reconcile_rate 'comparable ACK denominator'
    Assert-Equal 19 $one.combined.pending.p95 'nearest-rank p95'
    Assert-Equal 0 $one.combined.before_error_cm.p95 'before-error nearest-rank p95'
    Assert-Equal 10 $one.combined.before_error_cm.max 'before-error maximum'
    Assert-Equal 5 $one.combined.correction_cm.p95 'correction p95'
    Assert-Equal 2 $one.combined.replayed.p95 'replayed p95'

    $bad = Get-Content (Join-Path $testRoot 'run_normal_incomplete\summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal 'incomplete' $bad.status 'incomplete run status'
    $profile = Get-Content (Join-Path $testRoot 'profile_summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal 2 $profile.profiles.Normal.complete_runs 'complete run count'
    Assert-Equal 2 $profile.profiles.Normal.skipped_runs 'skipped run count'
    Assert-Equal 42 $profile.profiles.Normal.combined.ack_count 'pooled ACK count excludes incomplete run'
    Assert-Equal 19 $profile.profiles.Normal.combined.pending.p95 'pooled p95'

    $csv = Import-Csv (Join-Path $testRoot 'run_normal_01\summary.csv')
    Assert-Equal 3 $csv.Count 'one row per client plus combined'
    Assert-Equal 'N/A' $csv[1].correction_cm_p95 'CSV empty distribution'

    & powershell -NoProfile -ExecutionPolicy Bypass -File $analyzer -RunsRoot $testRoot -Profiles Normal -RunId run_normal_01 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Single-run analyzer returned exit code $LASTEXITCODE" }
    $profileAgain = Get-Content (Join-Path $testRoot 'profile_summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal 2 $profileAgain.profiles.Normal.complete_runs 'single-run mode preserves profile summary'

    $oldSchema = Get-Content (Join-Path $testRoot 'run_normal_old_schema\summary.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Equal 'incomplete' $oldSchema.status 'old schema is excluded'
    if (($oldSchema.reasons -join '; ') -notmatch 'malformed ACK') { throw 'Old schema reason was not recorded.' }

    $log1 = Join-Path $testRoot 'run_normal_01\client1.log'
    $log2 = Join-Path $testRoot 'run_normal_01\client2.log'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $waiter -Client1Log $log1 -Client2Log $log2 -Client1Pid $PID -Client2Pid $PID -TimeoutSeconds 1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Completion waiter rejected two completed logs.' }
    Write-Host 'AnalyzeNetworkRuns tests passed.'
}
finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
