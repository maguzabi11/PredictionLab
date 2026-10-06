[CmdletBinding()]
param(
    [string] $RunsRoot,
    [string[]] $Profiles = @('Normal', 'HighLatency', 'Jitter', 'PacketLoss'),
    [string] $RunId
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$culture = [System.Globalization.CultureInfo]::InvariantCulture
$utf8 = New-Object System.Text.UTF8Encoding($false)
$clientPattern = 'LogPredictionLab:\s+Client (?:ack(?:\(no-history\))?|reconcile)(?=\s)'
$ackPattern = 'LogPredictionLab:\s+Client ack pawn=\S+ ack=(?<ack>\d+) pending=(?<pending>\d+) beforeError=(?<error>\d+(?:\.\d+)?)\s*$'
$reconcilePattern = 'LogPredictionLab:\s+Client reconcile pawn=\S+ ack=(?<ack>\d+) beforeError=(?<error>\d+(?:\.\d+)?) replayed=(?<replayed>\d+) correction=(?<correction>\d+(?:\.\d+)?) pending=(?<pending>\d+)\s*$'
$noHistoryPattern = 'LogPredictionLab:\s+Client ack\(no-history\) pawn=\S+ ack=(?<ack>\d+) pending=(?<pending>\d+)\s*$'
$completedPattern = 'LogPredictionLab:\s+AutoInput completed pawn=\S+ duration=\d+(?:\.\d+)?s commands=(?<commands>\d+)\s*$'

function Read-Metadata {
    param([string] $Path)
    $values = @{}
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ($line -match '^([^=]+)=(.*)$') {
            $values[$Matches[1].Trim()] = $Matches[2].Trim()
        }
    }
    return $values
}

function Read-ClientLog {
    param([string] $Path)
    $events = New-Object 'System.Collections.Generic.List[object]'
    $result = [pscustomobject]@{
        Events = $events
        Started = 0
        Completed = 0
        CompletedCommands = 0
        Malformed = 0
    }
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ($line -match 'LogPredictionLab:\s+AutoInput started\b') { $result.Started++ }
        if ($line -match $completedPattern) {
            $result.Completed++
            $result.CompletedCommands = [int]$Matches['commands']
        }
        if ($line -notmatch $clientPattern) { continue }

        if ($line -match $ackPattern) {
            $events.Add([pscustomobject]@{
                Type = 'ack'; Pending = [int]$Matches['pending']
                BeforeError = [double]::Parse($Matches['error'], $culture)
                Replayed = $null; Correction = $null
            })
        }
        elseif ($line -match $reconcilePattern) {
            $events.Add([pscustomobject]@{
                Type = 'reconcile'; Pending = [int]$Matches['pending']
                BeforeError = [double]::Parse($Matches['error'], $culture)
                Replayed = [int]$Matches['replayed']
                Correction = [double]::Parse($Matches['correction'], $culture)
            })
        }
        elseif ($line -match $noHistoryPattern) {
            $events.Add([pscustomobject]@{
                Type = 'no_history'; Pending = [int]$Matches['pending']
                BeforeError = $null; Replayed = $null; Correction = $null
            })
        }
        else { $result.Malformed++ }
    }
    return $result
}

function Get-Distribution {
    param([object[]] $Events, [string] $Field)
    $values = New-Object 'System.Collections.Generic.List[double]'
    foreach ($event in $Events) {
        if ($null -ne $event.$Field) { $values.Add([double]$event.$Field) }
    }
    if ($values.Count -eq 0) {
        return [ordered]@{ count = 0; mean = $null; p95 = $null; max = $null }
    }
    $sorted = $values.ToArray()
    [array]::Sort($sorted)
    $sum = 0.0
    foreach ($value in $sorted) { $sum += $value }
    # Nearest-rank p95: the value at ceil(0.95 * N) in one-based indexing.
    $index = [Math]::Ceiling(0.95 * $sorted.Length) - 1
    return [ordered]@{
        count = $sorted.Length
        mean = [Math]::Round($sum / $sorted.Length, 3)
        p95 = $sorted[$index]
        max = $sorted[$sorted.Length - 1]
    }
}

function Get-Metrics {
    param([object[]] $Events)
    $accepted = 0
    $reconciled = 0
    $noHistory = 0
    foreach ($event in $Events) {
        switch ($event.Type) {
            'ack' { $accepted++ }
            'reconcile' { $reconciled++ }
            'no_history' { $noHistory++ }
        }
    }
    $comparable = $accepted + $reconciled
    $rate = $null
    if ($comparable -gt 0) { $rate = [Math]::Round($reconciled / $comparable, 6) }
    return [ordered]@{
        ack_count = $Events.Count
        accepted_count = $accepted
        reconcile_count = $reconciled
        no_history_count = $noHistory
        reconcile_rate = $rate
        pending = Get-Distribution $Events 'Pending'
        before_error_cm = Get-Distribution $Events 'BeforeError'
        replayed = Get-Distribution $Events 'Replayed'
        correction_cm = Get-Distribution $Events 'Correction'
    }
}

function New-FlatRow {
    param([string] $Profile, [string] $Run, [string] $Scope, [string] $Status,
          [string] $Reason, [int] $ServerCount, [int] $CompleteRuns, [object] $Metrics)
    $row = [ordered]@{
        profile = $Profile; run_id = $Run; scope = $Scope; status = $Status
        reason = $Reason; complete_runs = $CompleteRuns
        server_processed_count = $ServerCount
        ack_count = $Metrics.ack_count; accepted_count = $Metrics.accepted_count
        reconcile_count = $Metrics.reconcile_count; no_history_count = $Metrics.no_history_count
        reconcile_rate = $(if ($null -eq $Metrics.reconcile_rate) { 'N/A' } else { $Metrics.reconcile_rate })
    }
    foreach ($field in @('pending', 'before_error_cm', 'replayed', 'correction_cm')) {
        foreach ($stat in @('count', 'mean', 'p95', 'max')) {
            $value = $Metrics[$field][$stat]
            $row["${field}_${stat}"] = $(if ($null -eq $value) { 'N/A' } else { $value })
        }
    }
    return [pscustomobject]$row
}

function Write-Json {
    param([string] $Path, [object] $Value)
    [System.IO.File]::WriteAllText($Path, (ConvertTo-Json -InputObject $Value -Depth 10) + "`n", $utf8)
}

if (-not $RunsRoot) { $RunsRoot = Join-Path $PSScriptRoot '..\Saved\PredictionLab\Runs' }
$root = [System.IO.Path]::GetFullPath($RunsRoot)
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
    throw "Runs directory does not exist: $root"
}
$profileSet = @{}
foreach ($profile in $Profiles) { $profileSet[$profile] = $true }
$runs = New-Object 'System.Collections.Generic.List[object]'
$profileEvents = @{}
$profileComplete = @{}
$profileSkipped = @{}
foreach ($profile in $Profiles) {
    $profileEvents[$profile] = New-Object 'System.Collections.Generic.List[object]'
    $profileComplete[$profile] = 0
    $profileSkipped[$profile] = 0
}

foreach ($directory in (Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name)) {
    if ($RunId -and $directory.Name -ne $RunId) { continue }
    $metadataPath = Join-Path $directory.FullName 'metadata.txt'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { continue }
    $metadata = Read-Metadata $metadataPath
    $profile = $metadata['Profile']
    if (-not $profileSet.ContainsKey($profile)) { continue }

    $reasons = New-Object 'System.Collections.Generic.List[string]'
    if ($metadata['RunId'] -ne $directory.Name) { $reasons.Add('metadata RunId mismatch') }
    $expectedCommands = 0
    if (-not [int]::TryParse($metadata['AutoInputCommandCount'], [ref]$expectedCommands) -or $expectedCommands -le 0) {
        $reasons.Add('invalid AutoInputCommandCount')
    }

    $serverPath = Join-Path $directory.FullName 'server.log'
    $serverCount = 0
    if (-not (Test-Path -LiteralPath $serverPath -PathType Leaf)) {
        $reasons.Add('missing server.log')
    }
    else {
        foreach ($line in [System.IO.File]::ReadLines($serverPath)) {
            if ($line -match 'LogPredictionLab:\s+Server processed pawn=\S+ sequence=\d+ move=\([^)]*\) dash=(?:true|false)\s*$') {
                $serverCount++
            }
        }
        if ($serverCount -eq 0) { $reasons.Add('no server processed events') }
    }

    $clientResults = @{}
    $allEvents = New-Object 'System.Collections.Generic.List[object]'
    foreach ($client in @('client1', 'client2')) {
        $path = Join-Path $directory.FullName "$client.log"
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $reasons.Add("missing $client.log")
            $clientResults[$client] = [pscustomobject]@{
                Events = (New-Object 'System.Collections.Generic.List[object]')
                Started = 0; Completed = 0; CompletedCommands = 0; Malformed = 0
            }
            continue
        }
        $parsed = Read-ClientLog $path
        $clientResults[$client] = $parsed
        foreach ($event in $parsed.Events) { $allEvents.Add($event) }
        if ($parsed.Completed -ne 1 -or $parsed.CompletedCommands -ne $expectedCommands) {
            $reasons.Add("$client completion missing or command count mismatch")
        }
        if ($parsed.Events.Count -eq 0) { $reasons.Add("$client has no ACK events") }
        if ($parsed.Malformed -gt 0) { $reasons.Add("$client has $($parsed.Malformed) malformed ACK events") }
    }

    $status = 'complete'
    if ($reasons.Count -gt 0) { $status = 'incomplete' }
    $reason = $reasons -join '; '
    $clientMetrics = [ordered]@{
        client1 = Get-Metrics @($clientResults['client1'].Events.ToArray())
        client2 = Get-Metrics @($clientResults['client2'].Events.ToArray())
    }
    $combinedMetrics = Get-Metrics @($allEvents.ToArray())
    $summary = [ordered]@{
        schema_version = 1
        run_id = $directory.Name
        profile = $profile
        packet_args = $metadata['PacketArgs']
        status = $status
        reasons = @($reasons.ToArray())
        expected_commands_per_client = $expectedCommands
        client_completion_commands = [ordered]@{
            client1 = $clientResults['client1'].CompletedCommands
            client2 = $clientResults['client2'].CompletedCommands
        }
        server_processed_count = $serverCount
        clients = $clientMetrics
        combined = $combinedMetrics
    }
    Write-Json (Join-Path $directory.FullName 'summary.json') $summary
    $rows = @(
        (New-FlatRow $profile $directory.Name 'client1' $status $reason $serverCount 0 $clientMetrics.client1),
        (New-FlatRow $profile $directory.Name 'client2' $status $reason $serverCount 0 $clientMetrics.client2),
        (New-FlatRow $profile $directory.Name 'combined' $status $reason $serverCount 0 $combinedMetrics)
    )
    $rows | Export-Csv -LiteralPath (Join-Path $directory.FullName 'summary.csv') -NoTypeInformation -Encoding UTF8
    $runs.Add([pscustomobject]@{ profile = $profile; run_id = $directory.Name; status = $status; reason = $reason })
    if ($status -eq 'complete') {
        $profileComplete[$profile]++
        foreach ($event in $allEvents) { $profileEvents[$profile].Add($event) }
    }
    else { $profileSkipped[$profile]++ }
    Write-Host "$($directory.Name): $status$(if ($reason) { " ($reason)" })"
}

if ($RunId -and $runs.Count -eq 0) { throw "No matching run found: $RunId" }
if ($RunId) {
    Write-Host "Analyzed $($runs.Count) run(s); profile summaries were not changed."
    return
}
if ($runs.Count -eq 0) { throw "No runs matched the selected profiles in $root" }
$profileRows = New-Object 'System.Collections.Generic.List[object]'
$profileSummary = [ordered]@{}
foreach ($profile in $Profiles) {
    $metrics = Get-Metrics @($profileEvents[$profile].ToArray())
    $profileSummary[$profile] = [ordered]@{
        complete_runs = $profileComplete[$profile]
        skipped_runs = $profileSkipped[$profile]
        combined = $metrics
    }
    $profileRows.Add((New-FlatRow $profile '' 'profile' 'complete-only' '' 0 $profileComplete[$profile] $metrics))
}
$profileRows | Export-Csv -LiteralPath (Join-Path $root 'profile_summary.csv') -NoTypeInformation -Encoding UTF8
Write-Json (Join-Path $root 'profile_summary.json') ([ordered]@{
    schema_version = 1
    percentile_method = 'nearest-rank'
    runs = @($runs.ToArray())
    profiles = $profileSummary
})
Write-Host "Analyzed $($runs.Count) run(s); profile summaries: $root"
