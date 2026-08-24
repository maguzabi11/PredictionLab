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
   - Apply the replayed state to the actor.
   - Log `ack`, `beforeError`, `replayed`, and `correction`.

## Current Limitations

- The history cap is still `MaxSavedCommands = 256`; if an ack arrives after its saved prediction has been evicted, correction is skipped for that ack.
- Inputs are not bundled or resent. Packet loss can still drop individual input commands.
- The reconciliation threshold is a compile-time constant in `PredictionLabPawn.cpp`, not a config value.
- There is no CSV/stat aggregation yet. Current evidence is log based.
- Remote interpolation is implemented separately with a 2-point snapshot buffer; it does not use this rewind/replay path.

## Next Step

Phase 7 should turn the current logs into repeatable network fault measurements:

1. Extend `Tools/RunNetworkProfile.bat` beyond its current placeholder behavior.
2. Run Normal, HighLatency, Jitter, PacketLoss, and BadClient profiles.
3. Capture reconciliation log metrics: `beforeError`, `replayed`, `correction`, and frequency.
4. Compare remote proxy interpolation under jitter/loss against raw snapshot snapping.
5. Record the runs in `Docs/TestRuns.md`.
