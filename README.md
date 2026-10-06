# PredictionLab

> **English summary:** A UE 5.7.1 C++ portfolio project implementing client prediction, server-authoritative reconciliation, remote snapshot interpolation, and repeatable adverse-network measurements.

클라이언트가 입력에 즉시 반응하면서 서버의 확정 결과에 다시 맞추는 흐름을 작은 C++ 구현으로 보여주는 넷코드 실험 프로젝트입니다. 이동·대시·스태미나·쿨다운을 공유 시뮬레이션으로 계산하고, 입력 시퀀스와 ACK를 이용해 예측 기록을 관리합니다.

**완료 범위:** 예측·서버 권위·재조정·2-point 원격 보간 구현과 Phase 7 네트워크 테스트 실행·데이터 분석까지입니다. 추가 수치 해석, 보간 비교, BadClient hook, lag compensation은 이번 버전 범위 밖입니다.

## 구현 흐름과 의도

1. 로컬 클라이언트는 `InputCmd`를 만들고 `PredictionSimulation::Simulate`로 즉시 적용합니다. 입력과 적용 직후의 `StateAfter`를 history에 저장하고 서버에 보냅니다.
2. 서버는 처리한 시퀀스보다 새로운 입력을 같은 시뮬레이션에 적용합니다. 이동·대시 규칙을 서버 상태로 계산하고, 처리한 `LastProcessedInput`과 권위 상태를 소유 클라이언트에 반환합니다.
3. 클라이언트는 ACK 번호에 대응하는 저장된 예측 위치와 서버 위치를 비교하고, ACK 이하 입력을 history에서 제거합니다.
4. 위치 오차가 4cm를 넘으면 서버 상태로 되돌린 뒤 ACK 이후 입력만 순서대로 replay합니다. 각 replay 결과로 history의 `StateAfter`도 갱신하므로 다음 ACK를 보정된 기록과 비교할 수 있습니다.
5. 원격 플레이어는 서버 snapshot을 `COND_SkipOwner`로 받습니다. 수신 시 prev/current를 갱신하고 Tick에서 두 위치를 보간합니다.

예를 들어 로컬 입력이 105까지 진행된 상태에서 ACK 100이 오면, 입력 100 직후의 예측 상태와 서버 상태를 비교합니다. 보정이 필요하면 서버 상태에서 입력 101~105를 다시 적용합니다.

Actor/RPC 처리와 상태 계산을 분리해 prediction과 replay가 같은 함수를 사용하도록 구성했습니다. 엔진 이동 복제는 `SetReplicatingMovement(false)`로 끄며, 입력 history의 상한은 256개입니다.

| 데이터/통신 | 의미 |
| --- | --- |
| `InputCmd` | Sequence, DeltaSeconds, 이동 축, 대시 입력 |
| `PredictedState` | 위치·속도·스태미나·쿨다운·처리 시퀀스 |
| `ServerSubmitInput` | Client → Server, unreliable 입력 전송 |
| `ClientReceiveAuthoritativeState` | Server → 소유 Client, unreliable ACK·권위 상태 |
| `RemoteSnapshot` | Server → 다른 Client, timestamp·위치·속도 복제 |

## 코드 읽기 순서

- [PredictionSimulation.cpp](Source/PredictionLab/Prediction/PredictionSimulation.cpp): 공유 상태 계산
- [PredictionHistory.cpp](Source/PredictionLab/Prediction/PredictionHistory.cpp): 입력·StateAfter 저장, ACK 정리, replay 기록 갱신
- [PredictionLabPawn.cpp](Source/PredictionLab/PredictionLabPawn.cpp): 입력 생성 → 서버 처리 → ACK·재조정 → 원격 보간
- [AnalyzeNetworkRuns.ps1](Tools/AnalyzeNetworkRuns.ps1): 로그에서 지표와 완주 여부 추출

## 요구 사항과 실행

- Windows, Unreal Engine 5.7.1, Visual Studio C++/Unreal 툴체인
- `UE_ROOT`: Unreal Engine 설치 루트
- 아래 로컬 데모는 `UnrealEditor.exe -server`와 `-game`을 사용합니다. 별도 Server 타깃 빌드는 해당 타깃을 지원하는 엔진 환경이 필요합니다.

```powershell
$env:UE_ROOT = "<Unreal Engine 5.7.1 설치 루트>"
Tools\BuildEditor.bat
Tools\RunLocalPrediction.bat
```

서버 1개와 클라이언트 2개가 실행됩니다. WASD로 이동하고 Space로 대시합니다. 실제 입력 바인딩은 `Config/DefaultInput.ini`에서 확인할 수 있습니다.

네트워크 테스트 명령 확인과 반복 실행:

```powershell
Tools\RunNetworkProfile.bat Jitter --dry-run
Tools\RunNetworkProfile.bat Normal
Tools\RunNetworkProfile.bat HighLatency
Tools\RunNetworkProfile.bat Jitter
Tools\RunNetworkProfile.bat PacketLoss
```

각 프로파일은 같은 자동 입력으로 3회 실행합니다. 각 클라이언트는 60Hz 입력 3,600개를 60초 동안 재생합니다. 두 완료 로그를 최대 120초 기다리고 마지막 ACK 대기 후 해당 run이 시작한 프로세스만 종료합니다. `All`은 BadClient까지 포함해 총 15회이며, BadClient는 아직 gameplay hook이 없습니다.

| 프로파일 | 실행 인자 |
| --- | --- |
| Normal | packet simulation flag 없음 |
| HighLatency | `-PktLag=150` |
| Jitter | `-PktLag=80 -PktLagVariance=60` |
| PacketLoss | `-PktLag=80 -PktLoss=5` |

위 값은 네트워크 에뮬레이션 설정입니다. 실측 RTT로 대체해 표기하지 않습니다.

## 데이터 분석과 측정 결과

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\AnalyzeNetworkRuns.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\TestAnalyzeNetworkRuns.ps1
```

run별 로그·metadata·`summary.csv`·`summary.json`은 `Saved/PredictionLab/Runs/<RunId>/`에 생성됩니다. 프로파일 집계는 루트의 `profile_summary.csv`·`profile_summary.json`에 저장됩니다. 원본 실행 로그와 생성 파일은 저장소에 포함하지 않습니다.

`complete`는 서버 처리 로그와 두 클라이언트의 ACK 이벤트, 각 1개의 `commands=3600` 완료 로그 및 현재 parser 형식을 확인한 상태입니다. 조기 종료·누락·이전 형식의 run은 집계에서 제외합니다. 모든 unreliable 메시지의 전달 성공이나 보간 품질을 의미하지 않습니다.

2026-10-01 서버 1개·클라이언트 2개로 프로파일당 3회, 총 12회 완주했습니다.

| 프로파일 | 완주 run | 서버 처리 합계 | ACK 이벤트 | Reconcile | Pending 평균 / p95 / max | BeforeError 평균 / p95 / max (cm) | Correction p95 / max (cm) |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Normal | 3 | 21,599 | 21,599 | 1 | 0.801 / 2 / 26 | 0.015 / 0.06 / 10 | 10 / 10 |
| HighLatency | 3 | 21,600 | 21,600 | 0 | 19.893 / 21 / 32 | 0.015 / 0.06 / 0.07 | N/A / N/A |
| Jitter | 3 | 21,600 | 21,600 | 0 | 13.287 / 17 / 45 | 0.015 / 0.06 / 0.07 | N/A / N/A |
| PacketLoss | 3 | 20,570 | 19,529 | 976 | 11.888 / 13 / 30 | 0.55 / 0.14 / 60 | 19.93 / 60 |

각 행의 클라이언트 통계는 해당 프로파일의 3회·두 클라이언트 이벤트를 합친 분포입니다. p95는 nearest-rank 방식이며 회차별 p95의 평균을 사용하지 않습니다. 보정 표본이 없는 분포는 N/A입니다. 모든 프로파일에서 관찰된 no-history 이벤트는 0회입니다. 과거 실행·dry-run 13개는 제외했으며, 신규 12회는 모두 완주했습니다.

| 지표 | 표본과 의미 |
| --- | --- |
| ACK count | 일반 ACK + reconcile + no-history 이벤트 수 |
| Pending | ACK 처리 후 남은 history 개수. ACK가 없는 구간의 적체는 나타내지 않음 |
| BeforeError | ACK 번호의 저장된 예측 위치와 서버 위치 사이 거리 |
| Correction | reconcile 분기의 replay 전후 현재 위치 차이. 0도 포함 |
| Replayed | reconcile에서 다시 계산한 입력 개수 |
| Reconcile rate | reconcile / (일반 ACK + reconcile), no-history 제외 |

## 검증 범위와 한계

- 입력 전송은 unreliable 단건 방식이며 재전송·묶음 전송은 없습니다.
- 서버는 시퀀스 중복·역행을 거르고 대시 쿨다운·스태미나를 계산합니다. 클라이언트 입력 시간의 양수 상한·누적 시간 검증은 없습니다.
- 보정 여부는 위치 오차로 판단합니다. 스태미나·쿨다운 불일치를 별도 보정 조건으로 사용하지 않습니다.
- 원격 보간은 prev/current 2-point lerp입니다. 별도 interpolation delay buffer·extrapolation 정책과 Raw/Interpolated 품질 비교 측정은 없습니다.
- 프로파일 CSV의 `server_processed_count`는 미집계 값 0입니다. 실제 서버 처리 수치는 run별 summary와 위 표를 사용합니다.
- Normal의 1회 보정 원인, ACK 100/101 replay-history 개별 회귀 시나리오는 아직 검증하지 않았습니다.
- lag compensation과 BadClient gameplay hook은 구현 범위 밖입니다.

## 라이선스

별도 오픈소스 라이선스를 부여하지 않았습니다. 코드 열람 외의 사용·수정·재배포 권한은 명시적으로 허가하지 않습니다.
