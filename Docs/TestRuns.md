# Test Runs

Use this file to record repeatable local server/client runs.

## Version Closure (2026-10-06)

This portfolio version is complete through Phase 7 test execution and data analysis. The latest completed matrix is the 2026-10-01 four-profile measurement below. Earlier dated entries preserve the validation history and their pending work at that time.

Additional numeric interpretation, remote interpolation comparison, BadClient behavior, and lag compensation are optional follow-up work. Existing limitations and unverified regressions remain documented; closure does not imply they have been resolved. Raw runtime logs and generated summaries stay local under `Saved/PredictionLab/Runs/`; this repository includes the measured tables and reproducible analysis tools.

| Date | Profile | Command | Expected Signal | Result |
| --- | --- | --- | --- | --- |
| 2026-06-12 | Normal | `Tools\RunLocalPrediction.bat` | Server logs input sequence and clients log ACK/pending count | Historical placeholder; rerun needed after Phase 5/6 |

### 2026-09-28: Phase 7 analyzer verification

`Tools\TestAnalyzeNetworkRuns.ps1` passes with synthetic complete and incomplete runs. It checks the three ACK paths, nearest-rank p95, combined client metrics, exclusion of incomplete runs, CSV `N/A`, and single-run mode. The analyzer was also run against the existing local logs: seven eligible run directories were marked `incomplete`, so there are currently no publishable profile measurements. The August Normal runs ended around input 3,200 without `AutoInput completed ... commands=3600`; the batch runner now waits for both completion logs (up to 120 seconds). A fresh 4-profile × 3-run measurement remains pending.

Validation: `Tools\RunNetworkProfile.bat Normal --dry-run` and `Jitter --dry-run` generated three metadata directories each without launching Unreal; `Tools\TestPublishPortfolio.ps1` passed with the new export files; `Tools\BuildEditor.bat` succeeded (target up to date); `git diff --check` passed. A live dedicated-server batch with the new completion wait has not been run yet.

## Current Verification Targets

### 2026-10-01: Four-profile completed measurements

The user ran Normal, HighLatency, Jitter, and PacketLoss three times each and ran the log analyzer. Inspection of the generated summaries and source logs confirms all 12 new runs are `complete`. Each of the 24 client logs contains exactly one `AutoInput completed ... commands=3600` marker. Server processed counts in each run summary match the raw server logs. No new build or live run was performed during this review.

Run batches: `20261001_180745_369_Normal_R01..R03`, `20261001_203435_657_HighLatency_R01..R03`, `20261001_203851_513_Jitter_R01..R03`, and `20261001_204347_143_PacketLoss_R01..R03`.

| Profile | Complete runs | Server processed total (sum of run summaries) | ACK count | Reconcile count | Pending mean / p95 / max | BeforeError mean / p95 / max (cm) | Correction p95 / max (cm) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Normal | 3 | 21,599 | 21,599 | 1 | 0.801 / 2 / 26 | 0.015 / 0.06 / 10 | 10 / 10 |
| HighLatency | 3 | 21,600 | 21,600 | 0 | 19.893 / 21 / 32 | 0.015 / 0.06 / 0.07 | N/A / N/A |
| Jitter | 3 | 21,600 | 21,600 | 0 | 13.287 / 17 / 45 | 0.015 / 0.06 / 0.07 | N/A / N/A |
| PacketLoss | 3 | 20,570 | 19,529 | 976 | 11.888 / 13 / 30 | 0.55 / 0.14 / 60 | 19.93 / 60 |

Profile statistics pool the two clients' ACK events across the three complete runs. All profiles have zero observed no-history events. PacketLoss reconcile rate is approximately 4.998% (976 / 19,529), with replayed mean / p95 / max = 11.907 / 13 / 20 and correction mean = 10.629 cm. HighLatency and Jitter have no reconcile samples, so their correction/replayed statistics are N/A.

Historical or dry-run directories excluded by the analyzer: Normal 7, HighLatency 1, Jitter 4, PacketLoss 1 (13 total). These exclusions do not describe failures in the 12 new runs. The profile CSV currently writes `server_processed_count=0` as an unaggregated placeholder; use run-level summaries for actual server counts. `complete` establishes log coverage, not successful delivery of every unreliable input/ACK or satisfactory interpolation.

Observed signals: HighLatency increases pending commands while ack-time position error stays small; Jitter has a higher pending maximum than HighLatency in this sample; PacketLoss produces missed server input samples, fewer received ACKs, and reconciliation events. Normal R03 has one reconcile event (10 cm), whose exact cause has not been traced. Raw/Interpolated remote-proxy comparison and the ACK 100/101 targeted replay-history regression remain unverified.

### 2026-09-21: Replay history update

- Added `FPredictionHistory::UpdatePredictedStateAt`; each replayed command now replaces its existing full `StateAfter` before subsequent ACK comparisons.
- `Tools\BuildEditor.bat`: `PredictionLabEditor Win64 Development` succeeded. `git diff --check` passed.
- Runtime regression still pending: correct a known mismatch at ACK 100, then receive matching ACK 101 and confirm that the refreshed history does not trigger another correction from the old prediction.
- Measurement logging is now updated: no-history uses `Log`, and reconcile includes `pending`. Metric definitions are recorded in `Phase7_NetworkProfiles.md`; runtime log capture remains pending.
- Rebuilt `PredictionLabEditor Win64 Development` after these logging changes: succeeded (2026-09-21).

Use these log signals when rerunning the local dedicated server path.

| Area | Expected Signal |
| --- | --- |
| Client prediction | Owning client moves immediately after local input, before server ack is visually required |
| Auto input | `-PredictionLabAutoInput=1` owning client log: `AutoInput started ... duration=60s ... commands=3600`, followed by `AutoInput completed ... commands=3600`; no manual input affects this sequence |
| Server authority | `Server processed pawn=... sequence=... move=(...) dash=...` |
| ACK soft accept | `Client ack pawn=... ack=... pending=... beforeError=...` |
| Reconciliation | `Client reconcile pawn=... ack=... beforeError=... replayed=... correction=... pending=...` |
| Missing history guard | `Client ack(no-history) pawn=... ack=... pending=...` at Log level; indicates missing comparison history, without distinguishing the cause |
| Remote interpolation | Simulated proxy receives `RemoteSnapshot` via `COND_SkipOwner`; `OnRep_RemoteSnapshot` buffers snapshots and Tick lerps actor location |
| Camera/input alignment | W/S movement appears as screen up/down, and A/D movement appears as screen left/right |

## Phase 7 Run Matrix

`Tools\RunNetworkProfile.bat` now runs each selected profile three times, starts both clients with `-PredictionLabAutoInput=1`, and writes per-run metadata/log paths under `Saved/PredictionLab/Runs/<RunId>/`.
It waits for both client completion logs (up to 120 seconds), then stops only the Unreal process PIDs that it launched.
See `Docs\Phase7_NetworkProfiles.md` for the batch and analyzer procedure.
새 측정에서 완주한 대표 run의 profile parameters와 observed metrics를 이 문서에 기록한다.

| Profile | Purpose | Metrics To Capture |
| --- | --- | --- |
| Normal | Baseline responsiveness and correction rate | ACK count, reconcile count, beforeError p50/p95, correction p50/p95 |
| HighLatency | In-flight pending input pressure | pending count, replayed count, correction size |
| Jitter | Snapshot cadence instability | remote proxy visual smoothness, snapshot interval spread |
| PacketLoss | Dropped unreliable input behavior | skipped sequences, no-history ack count, correction frequency |
| BadClient | Server validation/correction demonstration | forced mismatch count, correction size, recovery behavior; currently needs a gameplay hook for `-PredictionLabBadClient=1` |
