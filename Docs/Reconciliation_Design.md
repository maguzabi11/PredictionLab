# Reconciliation Design

## Current Phase

Phase 5 reconciliation is implemented in `APredictionLabPawn::ClientReceiveAuthoritativeState_Implementation`.

The current owning-client path is:

- The owning client captures movement input into `FPredictedInputCmd`.
- Each command receives a monotonically increasing `Sequence`.
- The client immediately simulates `FPredictionSimulation::Simulate`.
- The command and the state immediately after applying it are saved in `FPredictionHistory`.
- The same command is sent to the server through unreliable `ServerSubmitInput`.
- The server simulates `ServerAuthoritativeState`, updates `RemoteSnapshot`, and replies with `LastProcessedInput`.
- The client compares the server state against the saved predicted state at the same ack sequence.
- The client removes acknowledged commands from `FPredictionHistory`.
- If the ack-time error exceeds `ReconciliationErrorThreshold` (`4.0f` cm), the client rewinds to the authoritative state, replays only pending commands, applies the replayed state to the actor, and logs the correction.

This avoids comparing the server ack state against the client's latest predicted state, which would include unacknowledged in-flight inputs and overstate the error.

## Terms

- `InputCmd`: one client input sample with sequence, delta time, move axis, and dash edge.
- `PredictedState`: deterministic state shared by client and server.
- `AuthoritativeState`: the server-owned `PredictedState`.
- `AckSequence`: the latest input sequence processed by the server.
- `PendingInput`: local commands newer than `AckSequence`.
- `PredictedAtAck`: the saved local predicted state immediately after applying `AckSequence`.
- `Correction`: the actor-space snap distance after rewinding to server state and replaying pending input.

## Reconciliation Algorithm

1. Receive `FPredictedState State` from `ClientReceiveAuthoritativeState`.
2. Look up `PredictedAtAck` from `FPredictionHistory` using `State.LastProcessedInput`.
3. Remove commands with `Sequence <= State.LastProcessedInput`.
4. If no saved prediction exists for the ack, log `ack(no-history)` and skip correction.
5. Compute `beforeError = Distance(PredictedAtAck.Location, State.Location)`.
6. If `beforeError <= ReconciliationErrorThreshold`, accept the ack and keep the current local prediction.
7. If `beforeError > ReconciliationErrorThreshold`:
   - Copy the authoritative `State` into `LocalPredictedState`.
   - Fetch pending commands with `Sequence > State.LastProcessedInput`.
   - Replay pending commands through `FPredictionSimulation::Simulate`.
   - After each replayed command, update its existing history entry through `UpdatePredictedStateAt` with the full resulting state. Subsequent ACKs compare against these corrected predictions.
   - Apply the replayed state to the actor.
   - Log `ack`, `beforeError`, `replayed`, `correction`, and `pending`.

All three ACK paths (soft accept, reconcile, and no-history) log at `Log` level and include the pending history count after acknowledged inputs are removed. See `Phase7_NetworkProfiles.md` for metric denominators, sample populations, and missing-data handling.

## Current Limitations

- The history cap is still `MaxSavedCommands = 256`; if an ack arrives after its saved prediction has been evicted, correction is skipped for that ack.
- Inputs are not bundled or resent. Packet loss can still drop individual input commands.
- The reconciliation threshold is a compile-time constant in `PredictionLabPawn.cpp`, not a config value.
- `Tools/AnalyzeNetworkRuns.ps1` generates CSV/JSON ACK statistics for completed runs. The four-profile matrix completed three runs per profile on 2026-10-01; see `TestRuns.md`. Completion validates log coverage, not delivery of every unreliable input/ACK or interpolation quality.
- Remote interpolation is implemented separately with a 2-point snapshot buffer; it does not use this rewind/replay path.

## Version Scope (2026-10-06)

This portfolio version closes at Phase 7 test execution and data analysis. Normal, HighLatency, Jitter, and PacketLoss completed three runs each, and the run/profile summaries and observed metrics are recorded in `Docs/TestRuns.md`.

Further interpretation of rare events and sample populations, raw-snapshot/interpolation comparison, and a BadClient gameplay hook are optional follow-up work. They are excluded from this version's completion criteria. Interpolation is implemented, but its improvement over raw snapshot snapping has not been separately measured.
