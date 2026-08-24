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
└── client2.log
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
- client join 여유 3초와 60초 입력 구간이 지나면, script는 자신이 `Start-Process`로 시작한 PID만 종료한다. 다음 run 전에는 3초 동안 port 해제를 기다린다.
- run별 `metadata.txt`에는 input 옵션, 60Hz/3,600 commands 계약, 실행 시간, 그리고 실제 server/client 명령이 남는다.

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

## 7B 다음 작업

다음 세션에서는 분석 측정 자동화를 구현한다.

1. `Saved/PredictionLab/Runs/<RunId>/` 아래 `server.log`, `client1.log`, `client2.log`를 읽는 parser를 만든다.
2. 다음 로그 패턴을 추출한다.
   - `Client ack pawn=... ack=... pending=... beforeError=...`
   - `Client reconcile pawn=... ack=... beforeError=... replayed=... correction=...`
   - `Client ack(no-history) pawn=... ack=... pending=...`
   - `Server processed pawn=... sequence=... move=(...) dash=...`
3. run별 metric을 계산한다.
   - ACK count
   - reconcile count
   - reconcile rate
   - pending 평균/p95/max
   - beforeError 평균/p95/max
   - replayed 평균/p95/max
   - correction 평균/p95/max
   - no-history ack count
4. 결과를 `Saved/PredictionLab/Runs/<RunId>/summary.csv` 또는 `summary.json`으로 저장한다.
5. 대표 실행 결과를 `Docs\TestRuns.md`에 기록한다.
6. BadClient 프로파일을 실제로 의미 있게 만들려면 `-PredictionLabBadClient=1` 인자를 읽어 클라이언트 예측만 의도적으로 speed/dash 규칙에서 벗어나게 하는 hook을 추가한다.

## 이해하고 넘어갈 지식

- RTT가 커지면 ACK가 늦어지고, 그 사이 `PendingInput`이 쌓인다.
- reconciliation은 현재 위치가 아니라 `AckSequence` 시점의 saved predicted state와 서버 state를 비교해야 한다.
- jitter는 평균 latency보다 snapshot 도착 간격을 흔들어서 remote interpolation 품질을 떨어뜨린다.
- unreliable input은 손실될 수 있다. Reliable로 바꾸는 것은 쉬운 답이 아니며, reliable buffer 지연과 disconnect 위험을 만든다.
- 평균보다 p95/max가 중요하다. 대부분 부드러워도 가끔 큰 correction이 있으면 체감 품질이 나쁘다.
