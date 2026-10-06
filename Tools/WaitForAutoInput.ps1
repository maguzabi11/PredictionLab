[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string] $Client1Log,
    [Parameter(Mandatory = $true)][string] $Client2Log,
    [Parameter(Mandatory = $true)][int] $Client1Pid,
    [Parameter(Mandatory = $true)][int] $Client2Pid,
    [int] $ExpectedCommands = 3600,
    [int] $TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
if ($ExpectedCommands -le 0 -or $TimeoutSeconds -le 0) { throw 'ExpectedCommands and TimeoutSeconds must be positive.' }
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
$completePattern = 'LogPredictionLab:\s+AutoInput completed pawn=\S+ duration=\d+(?:\.\d+)?s commands=' + $ExpectedCommands + '\s*$'

while ((Get-Date) -lt $deadline) {
    $done1 = (Test-Path -LiteralPath $Client1Log -PathType Leaf) -and
        [bool](Select-String -LiteralPath $Client1Log -Pattern $completePattern -Quiet)
    $done2 = (Test-Path -LiteralPath $Client2Log -PathType Leaf) -and
        [bool](Select-String -LiteralPath $Client2Log -Pattern $completePattern -Quiet)
    if ($done1 -and $done2) {
        Write-Host "Both clients completed $ExpectedCommands input commands."
        exit 0
    }
    if (-not (Get-Process -Id $Client1Pid -ErrorAction SilentlyContinue) -or
        -not (Get-Process -Id $Client2Pid -ErrorAction SilentlyContinue)) {
        Write-Error 'A client exited before both AutoInput completed logs appeared.'
        exit 1
    }
    Start-Sleep -Seconds 1
}

Write-Error "Timed out after $TimeoutSeconds seconds waiting for both AutoInput completed logs."
exit 1
