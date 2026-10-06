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
| 7 | 이번 버전 완료 | 자동 입력·batch 실행·로그 분석 도구 구현. 2026-10-01 4개 프로파일 × 3회 완주 및 ACK 지표 분석·기록 |
| 8 | 후속 선택 작업 | Lag compensation mini demo |

## 현재 구현 요약

- `APredictionLabPawn`은 `SetReplicatingMovement(false)`로 엔진 이동 복제를 끄고, 예측/보정/보간을 수동 관리한다.
- owning client는 매 Tick `FPredictedInputCmd`를 만들고 즉시 `LocalPredictedState`에 시뮬레이션한다.
- `FPredictionHistory`는 pending input뿐 아니라 각 sequence 적용 직후의 예측 상태를 저장한다.
- 서버는 `ServerSubmitInput`에서 `ServerAuthoritativeState`를 갱신하고, owning client에는 `ClientReceiveAuthoritativeState`, simulated proxy에는 `RemoteSnapshot`으로 결과를 보낸다.
- reconciliation은 최신 로컬 위치가 아니라 `AckSequence` 시점에 저장된 예측 상태와 서버 상태를 비교한다.
- 보정 시 pending 입력을 replay한 직후마다 history의 전체 `StateAfter`를 갱신한다. 이후 ACK는 이 보정된 기록과 비교한다.
- 일반 ACK·보정·no-history를 모두 `Log` 수준으로 기록하고, 세 경로 모두 ACK 처리 후 `pending` 개수를 남긴다. 지표 정의는 `Docs/Phase7_NetworkProfiles.md`를 따른다.
- simulated proxy는 `COND_SkipOwner`로 받은 `RemoteSnapshot`을 2-point buffer에 넣고 Tick에서 timestamp 기반 lerp를 적용한다.
- 카메라는 WASD 입력 방향과 화면 방향이 일치하도록 고정 yaw -90도 spring arm 뷰를 사용한다. W/S는 화면 상하, A/D는 화면 좌우 이동으로 보인다.
- `-PredictionLabAutoInput=1`을 지정한 owning client는 수동 입력 대신 60Hz 고정 `InputCmd` 3,600개를 60초 동안 재생한다. 패턴은 `Forward -> Right -> W+D dash -> Back -> Left -> S+A dash`의 9초 반복이다.

## 이번 버전 종료 기준 (2026-10-06)

2026-10-01 Normal, HighLatency, Jitter, PacketLoss를 각 3회 완주했다. 두 client의 완료 로그와 run별 서버 처리 수치를 확인했으며, ACK 지표는 `Docs/TestRuns.md`에 기록했다. 이번 버전의 개발·검증 범위는 이 테스트 실행과 데이터 분석까지로 확정한다.

- [x] 4개 프로파일 × 3회 테스트 실행 및 완주 확인
- [x] run별·프로파일별 summary 생성과 ACK/reconciliation 지표 기록
- [x] Phase 7 테스트 실행과 데이터 분석까지로 이번 버전 종료

추가 수치 해석, Phase 6 Raw Snapshot/Interpolated 비교, 화면 UI·영상, BadClient gameplay hook, Phase 8 지연 보상은 후속 선택 작업이다. Phase 6은 2-point 보간 구현 완료를 뜻하며, 별도 비교 실험으로 효과를 검증했다는 뜻은 아니다. 후속 작업은 이번 버전의 완료·업로드 조건에 포함하지 않는다.

다음 즉시 행동은 기존 코드와 테스트·분석 산출물, README를 현재 상태에 맞춰 게시하는 것이다.

## 알려진 제한

- `Tools/RunNetworkProfile.bat`는 전 프로파일에서 `-PredictionLabAutoInput=1`을 client에 전달하고, 프로파일당 3회를 순차 실행한다. 두 client의 3,600개 완료 로그를 최대 120초 기다린 다음, script가 시작한 PID만 강제 종료한다.
- 신규 12회는 모두 완주했다. 과거 실행 및 dry-run 13개는 incomplete로 프로파일 집계에서 제외됐다. `complete`는 로그 완주 조건이며 전체 입력 전달이나 원격 보간 품질을 보증하지 않는다.
- 프로파일 CSV의 `server_processed_count`는 현재 집계되지 않아 0으로 출력된다. 서버 처리 수치는 run별 summary를 사용한다.
- `BadClient` 프로파일은 `-PredictionLabBadClient=1` 실행 인자만 남기며, 이를 읽는 gameplay hook은 아직 없다.
- input RPC는 unreliable 단건 전송이며, 손실된 입력 재전송/묶음 전송은 없다.
- 보정 임계값 `ReconciliationErrorThreshold = 4.0f`는 코드 상수다.
- remote interpolation은 현재 prev/current 2-point lerp이며, 별도 interpolation delay buffer나 extrapolation 정책은 없다.
- CSV/JSON 지표는 ACK·reconciliation 로그를 집계한다. 원격 보간 품질 측정과 화면 UI는 아직 없다.
- 공개 후보는 최소 실행 맵 `Content/Maps/Map1.umap`만 포함한다. `NewMap`, MCP automation plugin, 내부 계획 문서는 게시 대상이 아니며 public 전환은 자동화하지 않는다.
