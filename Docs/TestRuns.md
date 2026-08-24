# Test Runs

Use this file to record repeatable local server/client runs.

| Date | Profile | Command | Expected Signal | Result |
| --- | --- | --- | --- | --- |
| 2026-06-12 | Normal | `Tools\RunLocalPrediction.bat` | Server logs input sequence and clients log ACK/pending count | Historical placeholder; rerun needed after Phase 5/6 |

## Current Verification Targets

Use these log signals when rerunning the local dedicated server path.

| Area | Expected Signal |
| --- | --- |
| Client prediction | Owning client moves immediately after local input, before server ack is visually required |
| Auto input | `-PredictionLabAutoInput=1` owning client log: `AutoInput started ... duration=60s ... commands=3600`, followed by `AutoInput completed ... commands=3600`; no manual input affects this sequence |
| Server authority | `Server processed pawn=... sequence=... move=(...) dash=...` |
| ACK soft accept | `Client ack pawn=... ack=... pending=... beforeError=...` |
| Reconciliation | `Client reconcile pawn=... ack=... beforeError=... replayed=... correction=...` |
| Missing history guard | `Client ack(no-history) pawn=... ack=... pending=...` only for stale/evicted ack cases |
| Remote interpolation | Simulated proxy receives `RemoteSnapshot` via `COND_SkipOwner`; `OnRep_RemoteSnapshot` buffers snapshots and Tick lerps actor location |
| Camera/input alignment | W/S movement appears as screen up/down, and A/D movement appears as screen left/right |

## Phase 7 Run Matrix

`Tools\RunNetworkProfile.bat` now runs each selected profile three times, starts both clients with `-PredictionLabAutoInput=1`, and writes per-run metadata/log paths under `Saved/PredictionLab/Runs/<RunId>/`.
It waits for the 60-second input window plus a 3-second client-join grace, then stops only the Unreal process PIDs that it launched.
See `Docs\Phase7_NetworkProfiles.md` for the 7B batch procedure and parser/summary TODO.
로그 parser가 구현되면 대표 run의 profile parameters와 observed metrics를 이 문서에 기록한다.

| Profile | Purpose | Metrics To Capture |
| --- | --- | --- |
| Normal | Baseline responsiveness and correction rate | ACK count, reconcile count, beforeError p50/p95, correction p50/p95 |
| HighLatency | In-flight pending input pressure | pending count, replayed count, correction size |
| Jitter | Snapshot cadence instability | remote proxy visual smoothness, snapshot interval spread |
| PacketLoss | Dropped unreliable input behavior | skipped sequences, no-history ack count, correction frequency |
| BadClient | Server validation/correction demonstration | forced mismatch count, correction size, recovery behavior; currently needs a gameplay hook for `-PredictionLabBadClient=1` |
