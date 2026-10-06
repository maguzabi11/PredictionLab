# Phase 7 Network Profiles

Phase 7은 네트워크 악조건에서 Phase 5 reconciliation과 Phase 6 remote interpolation이 어떻게 보이는지 반복 실행하고 측정하는 단계다.

## 7A 완료 범위

`Tools\RunNetworkProfile.bat`가 프로파일 인자를 받아 dedicated server + 2 clients를 실행한다.

```bat
Tools\RunNetworkProfile.bat Normal
Tools\RunNetworkProfile.bat HighLatency
Tools\RunNetworkProfile.bat Jitter
Tools\RunNetworkProfile.bat PacketLoss
Tools\RunNetworkProfile.bat BadClient
```

실행마다 다음 폴더를 만든다.

```text
Saved/PredictionLab/Runs/<yyyyMMdd_HHmmss>_<Profile>/
├── metadata.txt
├── server.log
├── client1.log
├── client2.log
├── summary.csv
└── summary.json
```

프로세스를 띄우지 않고 명령과 metadata 생성만 확인하려면:

```bat
Tools\RunNetworkProfile.bat Jitter --dry-run
```

각 프로파일 명령은 3개의 run을 순차 실행한다. 모든 프로파일을 한 번에 실행하려면 다음을 사용한다.

```bat
Tools\RunNetworkProfile.bat All
```

## 7B-1 완료: 고정 자동 입력

모든 owning client는 다음 실행 옵션으로 수동 입력 대신 동일한 자동 입력을 재생할 수 있다.

```text
-PredictionLabAutoInput=1
```

- 입력은 60Hz 고정 `InputCmd` 3,600개, 즉 정확히 60초 분량이다.
- 9초 패턴은 `Forward -> Right -> W+D dash -> Back -> Left -> S+A dash`이며 반복된다.
- 자동 모드에서는 WASD/dash 수동 입력을 무시한다.
- 60초 뒤에는 새 `InputCmd` 생성을 멈춘다. 프로세스 종료와 프로파일별 3회 반복은 아래 7B-2 batch script가 담당한다.

## 7B-2 완료: batch 실행 연동

`RunNetworkProfile.bat`는 client 1/2 명령에 모두 `-PredictionLabAutoInput=1`을 추가한다. 따라서 이전처럼 script가 옵션을 전달하지 않아 자동 입력이 꺼지는 문제가 없다.

- 선택한 profile은 3회 순차 실행된다. `All`은 5개 profile, 총 15회를 순차 실행한다.
- run마다 server를 먼저 시작하고 4초 후 두 client를 시작한다.
- 두 client의 `AutoInput completed ... commands=3600` 로그를 확인한 뒤 3초 동안 마지막 ACK를 받고, script는 자신이 `Start-Process`로 시작한 PID만 종료한다. 완료 로그가 120초 안에 없거나 client가 먼저 종료되면 batch는 실패를 반환한다. 다음 run 전에는 3초 동안 port 해제를 기다린다.
- run별 `metadata.txt`에는 input 옵션, 60Hz/3,600 commands 계약, 완료 대기 제한 시간, 그리고 실제 server/client 명령이 남는다.

## 프로파일 의미

| Profile | 현재 실행 조건 | 확인 목적 |
| --- | --- | --- |
| Normal | packet simulation flag 없음 | 기준선. ACK, pending, correction의 정상 범위 확인 |
| HighLatency | `-PktLag=150` | ACK 지연으로 `PendingInput`과 replay 압력이 증가하는지 확인 |
| Jitter | `-PktLag=80 -PktLagVariance=60` | snapshot 도착 간격 흔들림에서 remote interpolation이 버티는지 확인 |
| PacketLoss | `-PktLag=80 -PktLoss=5` | unreliable input/snapshot 손실에서 correction과 no-history ack 양상 확인 |
| BadClient | `-PktLag=80 -PredictionLabBadClient=1` | 향후 bad-client 코드 hook용 실행 preset. 현재는 의도만 metadata에 남긴다 |

Unreal packet simulation flag는 프로세스 실행 인자로 전달한다. 로컬 dedicated server 실험에서는 server와 두 client에 같은 flag를 전달해 왕복 경로의 악조건을 단순하게 재현한다.

## 실행자가 관찰할 것

각 profile run은 수동 조작 없이 60초 자동 입력으로 수행한다. `AutoInput completed ... commands=3600` 로그가 client 1/2에 모두 남았는지 먼저 확인한다.

- W/S/A/D 화면 방향이 유지되는지 확인한다.
- owning client는 입력 즉시 움직이는지 확인한다.
- remote client에서 다른 pawn이 snapshot마다 순간이동하지 않고 보간되는지 확인한다.
- HighLatency에서 pending/replayed가 Normal보다 증가하는지 로그로 확인한다.
- Jitter/PacketLoss에서 `Client reconcile` 또는 `ack(no-history)`가 늘어나는지 확인한다.

## 7B-3 완료: 로그 분석 도구

PowerShell 5.1에서 동작하는 `Tools\AnalyzeNetworkRuns.ps1`이 run별 server/client 로그를 읽는다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\TestAnalyzeNetworkRuns.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\AnalyzeNetworkRuns.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File Tools\AnalyzeNetworkRuns.ps1 -RunId <RunId>
```

- 기본 실행은 Normal, HighLatency, Jitter, PacketLoss의 모든 기존 run을 검사한다. BadClient는 동작 hook이 구현되기 전까지 기본 집계에서 제외한다.
- 각 run에 `summary.json`과 `summary.csv`를 쓴다. CSV는 client1, client2, combined 세 행이다. `-RunId`는 지정한 run만 갱신하고 기존 프로파일 요약 파일은 유지한다.
- 루트 `Saved/PredictionLab/Runs/`에 `profile_summary.json`과 `profile_summary.csv`를 쓴다. 프로파일 수치는 **완주한 run의 두 client 이벤트를 합쳐 다시 계산**하며, 회차별 p95의 평균을 사용하지 않는다.
- `summary.json`의 `status=complete`는 server 처리 로그가 있고, 두 client 각각 ACK 이벤트 및 `commands=3600` 완료 로그가 정확히 한 번 있으며, 로그 형식이 현재 parser와 일치함을 뜻한다. 빠진 파일, 조기 종료, 예전 로그 형식은 `incomplete`와 `reasons`에 남고 프로파일 수치에서 제외된다.
- p95는 nearest-rank 방식이다. 값을 정렬하고 1부터 세어 `ceil(0.95 × 표본 수)`번째 값을 사용한다. JSON의 표본 없는 통계는 `null`, CSV는 `N/A`다.
- 과거 run 중 자동 입력 완료 전에 끝난 로그가 있다. parser의 실행 성공은 측정 성공을 의미하지 않으며, `complete_runs`를 확인한 뒤 결과를 해석한다.

## 이번 버전 종료 범위 (2026-10-06)

2026-10-01 Normal, HighLatency, Jitter, PacketLoss 각 3회 완주와 summary 생성을 확인했다. 실제 수치는 `TestRuns.md`에 기록했다. `complete`는 로그 완주 조건이며 모든 unreliable 메시지의 전달 성공을 뜻하지 않는다. 프로파일 CSV의 `server_processed_count`는 현재 집계되지 않아 0으로 출력되므로 서버 처리 수치는 run별 summary를 사용한다.

- [x] Normal, HighLatency, Jitter, PacketLoss 각 3회 실행 및 두 client의 완주 확인
- [x] ACK/reconcile/no-history 이벤트와 pending, beforeError, replayed, correction 지표의 데이터 분석 및 summary 생성
- [x] 측정 수치를 `TestRuns.md`에 기록

위 테스트 실행과 데이터 분석까지를 이번 버전의 종료 조건으로 확정한다. 추가 수치 해석, Phase 6 Raw Snapshot/보간 비교, BadClient gameplay hook은 후속 선택 작업으로 이관한다. 원격 보간 품질은 현재 ACK 로그만으로 계산되지 않으며, 별도 비교 효과를 검증한 것으로 설명하지 않는다.

## 측정 로그와 지표 정의

일반 ACK, reconcile, no-history는 모두 `Log` 수준으로 기록한다. 각 ACK 처리 호출은 이 세 경로 중 하나를 기록한다. client별로 먼저 집계하고, 동일 run의 두 client 결과를 합칠 때는 이벤트 수를 기준으로 비율을 계산한다.

| 지표 | 정의 |
| --- | --- |
| ACK count | 일반 ACK + reconcile + no-history 이벤트 수 |
| Reconcile count | 보정 분기에 진입한 횟수. 실제 위치가 바뀐 횟수와는 구분한다. |
| Reconcile rate | reconcile / (일반 ACK + reconcile). 분모가 0이면 N/A. no-history는 비교 불가이므로 제외한다. |
| Pending 평균/p95/max | 세 ACK 경로의 `pending`. ACK된 입력 제거 후 남은 history 개수이며 ACK 수신 시점 표본이다. ACK가 없는 구간의 적체나 256개 상한으로 버려진 입력은 나타내지 않는다. |
| BeforeError 평균/p95/max | 일반 ACK와 reconcile의 `beforeError`를 합친 분포(cm). 해당 ACK 번호의 저장된 예측 위치와 서버 위치 사이 거리. |
| Replayed 평균/p95/max | reconcile 이벤트의 `replayed` 분포(입력 개수). |
| Correction 평균/p95/max | reconcile 이벤트의 `correction` 분포(cm). replay 직전과 직후 현재 위치 사이 거리이며 0도 포함한다. |
| No-history count | 비교할 예측 기록을 찾지 못한 ACK 수. 이 로그만으로 오래된 ACK와 history 상한 초과를 구분하지 않는다. |

표본이 없는 분포는 N/A로 표시한다. 과거 로그에서 `pending` 필드나 no-history 출력 설정을 확인할 수 없으면 누락을 0으로 간주하지 않는다. 자동 입력 완료 로그(`commands=3600`)를 두 client에서 모두 확인한 run을 완주 결과로 집계한다.

## 이해하고 넘어갈 지식

- RTT가 커지면 ACK가 늦어지고, 그 사이 `PendingInput`이 쌓인다.
- reconciliation은 현재 위치가 아니라 `AckSequence` 시점의 saved predicted state와 서버 state를 비교해야 한다.
- jitter는 평균 latency보다 snapshot 도착 간격을 흔들어서 remote interpolation 품질을 떨어뜨린다.
- unreliable input은 손실될 수 있다. Reliable로 바꾸는 것은 쉬운 답이 아니며, reliable buffer 지연과 disconnect 위험을 만든다.
- 평균보다 p95/max가 중요하다. 대부분 부드러워도 가끔 큰 correction이 있으면 체감 품질이 나쁘다.
