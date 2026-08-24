# PredictionLab Status

이 문서는 Phase 진행 현황과 다음 작업처럼 자주 바뀌는 상태 정보를 관리한다.
구현 여부 판단이 필요한 경우 이 문서보다 소스 코드를 우선한다.

## 단계 현황

| Phase | 상태 | 내용 |
|-------|------|------|
| 0 | 완료 | 실행 골격, 입력 시퀀스, local prediction, ServerSubmitInput, ClientAck, 로그 |
| 1 | 완료 | CMC 흐름 문서화 (`Docs/`) |
| 2 | 완료 | FPredictionSimulation — deterministic simulate |
| 3 | 완료 | Local client prediction + input history (`Cmd` + `StateAfter` 저장) |
| 4 | 완료 | Server authority + ACK (LastProcessedInput) |
| 5 | 완료 | Reconciliation — ack 시점 예측 상태 비교, threshold 초과 시 rewind + pending replay |
| 6 | 완료 | Remote interpolation snapshot buffer (2-point timestamp lerp, OnRep→버퍼 밀어넣기 + Tick 보간) |
| 7 | 진행 중 | 7A 실행 자동화 완료. 7B-1 고정 자동 입력 및 7B-2 batch 실행 완료 (전 프로파일 client auto-input, 프로파일당 3회 순차 실행); 로그 분석은 미완 |
| 8 | 미완 | Lag compensation mini demo |

## 현재 구현 요약

- `APredictionLabPawn`은 `SetReplicatingMovement(false)`로 엔진 이동 복제를 끄고, 예측/보정/보간을 수동 관리한다.
- owning client는 매 Tick `FPredictedInputCmd`를 만들고 즉시 `LocalPredictedState`에 시뮬레이션한다.
- `FPredictionHistory`는 pending input뿐 아니라 각 sequence 적용 직후의 예측 상태를 저장한다.
- 서버는 `ServerSubmitInput`에서 `ServerAuthoritativeState`를 갱신하고, owning client에는 `ClientReceiveAuthoritativeState`, simulated proxy에는 `RemoteSnapshot`으로 결과를 보낸다.
- reconciliation은 최신 로컬 위치가 아니라 `AckSequence` 시점에 저장된 예측 상태와 서버 상태를 비교한다.
- simulated proxy는 `COND_SkipOwner`로 받은 `RemoteSnapshot`을 2-point buffer에 넣고 Tick에서 timestamp 기반 lerp를 적용한다.
- 카메라는 WASD 입력 방향과 화면 방향이 일치하도록 고정 yaw -90도 spring arm 뷰를 사용한다. W/S는 화면 상하, A/D는 화면 좌우 이동으로 보인다.
- `-PredictionLabAutoInput=1`을 지정한 owning client는 수동 입력 대신 60Hz 고정 `InputCmd` 3,600개를 60초 동안 재생한다. 패턴은 `Forward -> Right -> W+D dash -> Back -> Left -> S+A dash`의 9초 반복이다.

## 다음 작업 (Phase 7B Network fault metrics)

반복 가능한 입력과 batch 실행은 준비됐다. 다음 작업은 `Saved/PredictionLab/Runs/<RunId>/` 로그를 파싱해서 Phase 5/6이 네트워크 불량 상황에서 어떻게 동작하는지 프로파일별(ping/loss/jitter)로 정량 측정하는 것이다.

- `Docs/Phase7_NetworkProfiles.md`의 7B 절차를 기준으로 parser와 summary 산출물을 만든다.
- reconciliation 발생 빈도·beforeError(ack 시점 예측 오차)·correction(보정 snap 크기) 분포 (Phase 5 로그 활용)
- 원격 proxy 보간이 snap 대비 시각적/정량적 개선 확인 (Phase 6)
- 측정 결과를 문서화하여 면접 답변 근거로 사용

## 알려진 제한

- `Tools/RunNetworkProfile.bat`는 전 프로파일에서 `-PredictionLabAutoInput=1`을 client에 전달하고, 프로파일당 3회를 순차 실행한다. 각 run은 client join 3초 뒤 60초 입력을 기다린 다음, script가 시작한 PID만 강제 종료한다.
- 로그 parser, CSV/JSON summary 생성, 결과 집계는 아직 없다.
- `BadClient` 프로파일은 `-PredictionLabBadClient=1` 실행 인자만 남기며, 이를 읽는 gameplay hook은 아직 없다.
- input RPC는 unreliable 단건 전송이며, 손실된 입력 재전송/묶음 전송은 없다.
- 보정 임계값 `ReconciliationErrorThreshold = 4.0f`는 코드 상수다.
- remote interpolation은 현재 prev/current 2-point lerp이며, 별도 interpolation delay buffer나 extrapolation 정책은 없다.
- UI/CSV 기반 지표 수집은 아직 없다. 현재 검증 신호는 로그 중심이다.
- 공개 후보는 최소 실행 맵 `Content/Maps/Map1.umap`만 포함한다. `NewMap`, MCP automation plugin, 내부 계획 문서는 게시 대상이 아니며 public 전환은 자동화하지 않는다.
