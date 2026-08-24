# PredictionLab

> **English summary:** PredictionLab is a UE 5.7.1 C++ networking portfolio project that implements a compact deterministic client-prediction loop, server-authoritative reconciliation, remote interpolation, and repeatable adverse-network experiments without rebuilding CharacterMovementComponent.

UE 5.7.1 C++로 Client Prediction, Server Authority, Reconciliation, Remote Interpolation을 직접 구현하고 네트워크 악조건에서 측정하는 실험형 포트폴리오입니다. 완성 게임보다 입력 명령, ACK, rewind/replay, snapshot interpolation의 원리를 작은 코드와 반복 가능한 실험으로 보여주는 데 초점을 둡니다.

## 현재 구현

- `InputCmd` 기반 로컬 즉시 예측
- 서버 권위 상태와 `AckSequence` 반환
- ACK 시점 상태 비교 후 rewind + `PendingInput` replay
- simulated proxy용 timestamp 기반 2-point snapshot interpolation
- Dedicated Server + 2 clients 로컬 실행
- 고정 60Hz 자동 입력과 latency/jitter/loss 프로파일 반복 실행

현재 단계와 알려진 제한은 [Docs/Status.md](Docs/Status.md), 보정 알고리즘은 [Docs/Reconciliation_Design.md](Docs/Reconciliation_Design.md), 네트워크 실험 절차는 [Docs/Phase7_NetworkProfiles.md](Docs/Phase7_NetworkProfiles.md)를 참고하세요.

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

전체 프로파일 반복 실행:

```powershell
Tools\RunNetworkProfile.bat All
```

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

엔진 이동 복제는 끄고(`SetReplicateMovement(false)`), simulation과 Actor/RPC 코드를 분리합니다. 입력 RPC는 의도적으로 unreliable이며 history 상한은 256개입니다.

## 프로젝트 상태

이 저장소는 진행 중인 포트폴리오 실험실입니다. 현재 테스트 기록은 [Docs/TestRuns.md](Docs/TestRuns.md)에 정리되어 있으며, 로그 parser와 최종 지표 시각화, lag compensation mini demo는 아직 완료되지 않았습니다.

## 라이선스

이 저장소에는 별도 오픈소스 라이선스가 부여되지 않았습니다. 코드 열람 외의 사용·수정·재배포 권한은 명시적으로 허가되지 않습니다.
