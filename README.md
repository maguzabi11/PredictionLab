# PredictionLab

> **English summary:** PredictionLab is a UE 5.7.1 C++ networking portfolio project that implements a compact deterministic client-prediction loop, server-authoritative reconciliation, remote interpolation, and repeatable adverse-network experiments without rebuilding CharacterMovementComponent.

UE 5.7.1 C++로 Client Prediction, Server Authority, Reconciliation, Remote Interpolation을 직접 구현하고 네트워크 악조건에서 측정하는 실험형 포트폴리오입니다. 완성 게임보다 입력 명령, ACK, rewind/replay, snapshot interpolation의 원리를 작은 코드와 반복 가능한 실험으로 보여주는 데 초점을 둡니다.

**이번 버전 완료 범위 (2026-10-06):** Phase 7 네트워크 테스트 실행과 데이터 분석까지. 추가 수치 해석과 Phase 6 보간 비교, lag compensation은 후속 선택 작업으로 둡니다.

## 현재 구현

- `InputCmd` 기반 로컬 즉시 예측
- 서버 권위 상태와 `AckSequence` 반환
- ACK 시점 상태 비교 후 rewind + `PendingInput` replay
- simulated proxy용 timestamp 기반 2-point snapshot interpolation
- Dedicated Server + 2 clients 로컬 실행
- 고정 60Hz 자동 입력과 latency/jitter/loss 프로파일 반복 실행
- 완주한 run의 ACK/reconciliation 로그를 CSV/JSON으로 집계하는 분석 도구

현재 단계와 알려진 제한은 [Docs/Status.md](Docs/Status.md), 보정 알고리즘은 [Docs/Reconciliation_Design.md](Docs/Reconciliation_Design.md), 네트워크 실험 절차는 [Docs/Phase7_NetworkProfiles.md](Docs/Phase7_NetworkProfiles.md)를 참고하세요.

## 측정 결과

2026-10-01 Normal, HighLatency, Jitter, PacketLoss를 각각 3회 실행했습니다. 각 run은 서버 1개와 클라이언트 2개로 구성되며, 각 클라이언트는 60Hz 입력 3,600개를 60초 동안 재생했습니다. 총 12회 모두 두 클라이언트의 입력 완료 로그를 확인했습니다.

| 프로파일 | 완주 run | ACK 이벤트 | Reconcile 이벤트 | Pending p95 | Correction p95 (cm) |
| --- | --- | --- | --- | --- | --- |
| Normal | 3 | 21,599 | 1 | 2 | 10 |
| HighLatency | 3 | 21,600 | 0 | 21 | N/A |
| Jitter | 3 | 21,600 | 0 | 17 | N/A |
| PacketLoss | 3 | 19,529 | 976 | 13 | 19.93 |

각 행은 해당 프로파일의 3회 실행에서 두 클라이언트의 이벤트를 합친 결과입니다. Pending은 ACK 처리 후 남은 입력 수이며, Correction은 reconcile 이벤트에서 replay 전후 현재 위치의 차이입니다. N/A는 보정 표본이 없음을 뜻합니다. 완주는 로그 수집 범위를 확인하는 조건이며 모든 unreliable 입력/ACK의 전달이나 원격 보간 품질을 보증하지 않습니다.

전체 지표·프로파일 조건·측정 제한은 [Docs/TestRuns.md](Docs/TestRuns.md)와 [Docs/Phase7_NetworkProfiles.md](Docs/Phase7_NetworkProfiles.md)에 기록했습니다. 원본 실행 로그와 생성된 summary는 로컬 `Saved/PredictionLab/Runs/`에 보관하며, 저장소에는 결과 표와 재현용 도구를 포함합니다.

## 요구 사항

- Windows
- Unreal Engine 5.7.1 C++ 툴체인
- Visual Studio의 Unreal/C++ 빌드 구성
- `UE_ROOT` 환경 변수: Unreal Engine 설치 루트

PowerShell 예시:

```powershell
$env:UE_ROOT = "<Unreal Engine 5.7.1 설치 경로>"
```

## 빌드와 실행

Editor 타깃 빌드:

```powershell
Tools\BuildEditor.bat
```

Dedicated Server와 클라이언트 2개 실행:

```powershell
Tools\RunLocalPrediction.bat
```

네트워크 프로파일 명령 확인:

```powershell
Tools\RunNetworkProfile.bat Jitter --dry-run
```

측정한 네 가지 프로파일 반복 실행 (각 3회):

```powershell
Tools\RunNetworkProfile.bat Normal
Tools\RunNetworkProfile.bat HighLatency
Tools\RunNetworkProfile.bat Jitter
Tools\RunNetworkProfile.bat PacketLoss
```

기존 실행 로그 분석:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\AnalyzeNetworkRuns.ps1
```

분석 도구의 합성 로그 검증:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\TestAnalyzeNetworkRuns.ps1
```

`All`은 위 네 프로파일과 `BadClient`를 포함해 총 15회 실행합니다. `BadClient` gameplay hook은 후속 작업이므로, 이번 버전의 측정에는 위 네 가지 명령을 사용합니다.

`All`에는 아직 gameplay hook이 없는 BadClient도 포함됩니다. 현재 측정 가능한 네트워크 조건은 Normal, HighLatency, Jitter, PacketLoss이며 각 프로파일을 개별 실행하면 3회씩 반복합니다.

로그 분석:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\AnalyzeNetworkRuns.ps1
```

분석 결과는 run별 `summary.csv`/`summary.json`과 `Saved/PredictionLab/Runs/`의 `profile_summary.csv`/`profile_summary.json`에 저장됩니다. 완주한 run만 프로파일 수치에 포함됩니다.

실험 로그는 `Saved/PredictionLab/Runs/` 아래에 생성되며 저장소에는 포함되지 않습니다.

## 핵심 구조

```text
Source/PredictionLab/
├── PredictionLabPawn.*              prediction/network loop entry point
└── Prediction/
    ├── PredictedInputCmd.h           sampled input command
    ├── PredictedState.h              deterministic state and snapshot
    ├── PredictionSimulation.*        Actor-independent simulation
    └── PredictionHistory.*           bounded pending-input history
```

엔진 이동 복제는 끄고(`SetReplicatingMovement(false)`), simulation과 Actor/RPC 코드를 분리합니다. 입력 RPC는 의도적으로 unreliable이며 history 상한은 256개입니다.

## 프로젝트 상태

이번 버전은 예측·서버 권위·재조정·2-point 원격 보간 구현과 Phase 7 반복 테스트·로그 분석까지 완료했습니다. 기존 결과의 추가 해석, Raw Snapshot/Interpolated 비교 실험, 지표 UI·영상, BadClient hook, lag compensation mini demo는 후속 선택 작업입니다.

### 알려진 제한

- 입력 RPC는 unreliable 단건 전송이며, 손실된 입력의 재전송·묶음 전송은 구현하지 않았습니다.
- 원격 보간은 prev/current 2-point lerp입니다. 별도 interpolation delay buffer·extrapolation 정책과 보간 품질의 비교 측정은 없습니다.
- 프로파일 CSV의 `server_processed_count`는 미집계 값 0으로 출력됩니다. 실제 서버 처리 수치는 run별 summary와 `TestRuns.md`를 참고하세요.
- `BadClient`는 실행 인자만 있으며 gameplay hook이 없습니다.
- Normal에서 발생한 1회 보정의 정확한 원인과 ACK 100/101 replay-history 개별 회귀 시나리오는 아직 검증하지 않았습니다.

## 라이선스

이 저장소에는 별도 오픈소스 라이선스가 부여되지 않았습니다. 코드 열람 외의 사용·수정·재배포 권한은 명시적으로 허가되지 않습니다.
