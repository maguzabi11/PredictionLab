#include "PredictionLabPawn.h"

#include "Camera/CameraComponent.h"
#include "Components/SphereComponent.h"
#include "Components/StaticMeshComponent.h"
#include "Engine/World.h"
#include "GameFramework/SpringArmComponent.h"
#include "Misc/CommandLine.h"
#include "Misc/Parse.h"
#include "Net/UnrealNetwork.h"
#include "PredictionLab.h"
#include "UObject/ConstructorHelpers.h"

// Phase 5: reconciliation 오차 임계값(cm 단위). 서버와의 거리가 이 값보다 크면 rewind 후 pending 입력 재시뮬레이션.
static constexpr float ReconciliationErrorThreshold = 4.0f;
static constexpr float CameraTargetArmLength = 900.0f;
static const FRotator InputAlignedCameraRotation(-60.0f, -90.0f, 0.0f);

// Auto input uses fixed-size commands so a run's input sequence does not vary
// with client frame rate. 60 seconds at 60 Hz produces exactly 3,600 commands.
static constexpr float AutoInputSampleIntervalSeconds = 1.0f / 60.0f;
static constexpr int32 AutoInputDurationSeconds = 60;
static constexpr int32 AutoInputTotalCommandCount = AutoInputDurationSeconds * 60;
static constexpr int32 AutoInputSamplesPerSegment = 90; // 1.5 seconds at 60 Hz.
static constexpr int32 AutoInputSamplesPerPattern = AutoInputSamplesPerSegment * 6;
static constexpr int32 AutoInputFirstDashSample = AutoInputSamplesPerSegment * 2;
static constexpr int32 AutoInputSecondDashSample = AutoInputSamplesPerSegment * 5;

APredictionLabPawn::APredictionLabPawn()
{
	PrimaryActorTick.bCanEverTick = true;
	bReplicates = true;
	SetReplicatingMovement(false);

	CollisionComponent = CreateDefaultSubobject<USphereComponent>(TEXT("CollisionComponent"));
	CollisionComponent->InitSphereRadius(42.0f);
	CollisionComponent->SetCollisionProfileName(TEXT("Pawn"));
	RootComponent = CollisionComponent;

	MeshComponent = CreateDefaultSubobject<UStaticMeshComponent>(TEXT("MeshComponent"));
	MeshComponent->SetupAttachment(RootComponent);
	MeshComponent->SetCollisionEnabled(ECollisionEnabled::NoCollision);
	MeshComponent->SetRelativeScale3D(FVector(0.8f));

	static ConstructorHelpers::FObjectFinder<UStaticMesh> SphereMesh(TEXT("/Engine/BasicShapes/Sphere.Sphere"));
	if (SphereMesh.Succeeded())
	{
		MeshComponent->SetStaticMesh(SphereMesh.Object);
	}

	SpringArmComponent = CreateDefaultSubobject<USpringArmComponent>(TEXT("SpringArmComponent"));
	SpringArmComponent->SetupAttachment(RootComponent);
	SpringArmComponent->TargetArmLength = CameraTargetArmLength;
	SpringArmComponent->SetUsingAbsoluteRotation(true);
	SpringArmComponent->SetRelativeRotation(InputAlignedCameraRotation);
	SpringArmComponent->bUsePawnControlRotation = false;

	CameraComponent = CreateDefaultSubobject<UCameraComponent>(TEXT("CameraComponent"));
	CameraComponent->SetupAttachment(SpringArmComponent);
}

void APredictionLabPawn::BeginPlay()
{
	Super::BeginPlay();

	InitializeStateFromActor(LocalPredictedState);
	InitializeStateFromActor(ServerAuthoritativeState);

	// Accept both the convenient flag form and the documented =1 form.
	bAutoInputEnabled = FParse::Param(FCommandLine::Get(), TEXT("PredictionLabAutoInput"));
	int32 AutoInputCommandLineValue = bAutoInputEnabled ? 1 : 0;
	if (FParse::Value(FCommandLine::Get(), TEXT("PredictionLabAutoInput="), AutoInputCommandLineValue))
	{
		bAutoInputEnabled = AutoInputCommandLineValue != 0;
	}
}

void APredictionLabPawn::Tick(float DeltaSeconds)
{
	Super::Tick(DeltaSeconds);

	if (IsLocallyControlled())
	{
		if (bAutoInputEnabled)
		{
			ProduceAutoInput(DeltaSeconds);
		}
		else
		{
			ProduceLocalInput(DeltaSeconds);
		}
	}
	else if (bHasPreviousRemoteSnapshot && bHasCurrentRemoteSnapshot)
	{
		InterpolateRemoteSnapshot();
	}
}

void APredictionLabPawn::SetupPlayerInputComponent(UInputComponent* PlayerInputComponent)
{
	Super::SetupPlayerInputComponent(PlayerInputComponent);

	PlayerInputComponent->BindAxis(TEXT("MoveForward"), this, &APredictionLabPawn::MoveForward);
	PlayerInputComponent->BindAxis(TEXT("MoveRight"), this, &APredictionLabPawn::MoveRight);
	PlayerInputComponent->BindAction(TEXT("Dash"), IE_Pressed, this, &APredictionLabPawn::DashPressed);
}

void APredictionLabPawn::GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const
{
	Super::GetLifetimeReplicatedProps(OutLifetimeProps);

	DOREPLIFETIME_CONDITION(APredictionLabPawn, RemoteSnapshot, COND_SkipOwner);
}

void APredictionLabPawn::MoveForward(float Value)
{
	if (bAutoInputEnabled)
	{
		return;
	}

	// Camera yaw -90 keeps +X as screen right; screen up maps to world -Y.
	CachedMoveAxis.Y = -Value;
}

void APredictionLabPawn::MoveRight(float Value)
{
	if (bAutoInputEnabled)
	{
		return;
	}

	CachedMoveAxis.X = Value;
}

void APredictionLabPawn::DashPressed()
{
	if (bAutoInputEnabled)
	{
		return;
	}

	bDashPressedThisFrame = true;
}

void APredictionLabPawn::ProduceLocalInput(float DeltaSeconds)
{
	FPredictedInputCmd Cmd;
	Cmd.Sequence = ++NextInputSequence;
	Cmd.ClientTimeSeconds = GetWorld() ? GetWorld()->GetTimeSeconds() : 0.0f;
	Cmd.DeltaSeconds = DeltaSeconds;
	Cmd.MoveAxis = CachedMoveAxis;
	Cmd.bDashPressed = bDashPressedThisFrame;

	bDashPressedThisFrame = false;

	FPredictionSimulation::Simulate(LocalPredictedState, Cmd, SimulationSettings);
	ApplyStateToActor(LocalPredictedState);
	// 이 입력을 적용한 직후의 예측 상태를 함께 저장한다. 나중에 서버 ack가 오면
	// 같은 sequence 시점의 예측 상태와 서버 상태를 비교해 순수 예측 오차를 측정한다.
	InputHistory.Add(Cmd, LocalPredictedState);

	if (!HasAuthority())
	{
		ServerSubmitInput(Cmd);
	}
	else
	{
		ServerAuthoritativeState = LocalPredictedState;
	}
}

void APredictionLabPawn::ProduceAutoInput(float DeltaSeconds)
{
	if (!bAutoInputStarted)
	{
		bAutoInputStarted = true;
		UE_LOG(LogPredictionLab, Log, TEXT("AutoInput started pawn=%s duration=%.0fs sampleRate=60Hz commands=%d"),
			*GetName(),
			static_cast<float>(AutoInputDurationSeconds),
			AutoInputTotalCommandCount);
	}

	if (bAutoInputCompleted)
	{
		return;
	}

	AutoInputAccumulatorSeconds += FMath::Max(0.0f, DeltaSeconds);
	while (AutoInputAccumulatorSeconds >= AutoInputSampleIntervalSeconds
		&& AutoInputGeneratedCommandCount < AutoInputTotalCommandCount)
	{
		SetAutoInputSample(AutoInputGeneratedCommandCount);
		ProduceLocalInput(AutoInputSampleIntervalSeconds);
		++AutoInputGeneratedCommandCount;
		AutoInputAccumulatorSeconds -= AutoInputSampleIntervalSeconds;
	}

	if (AutoInputGeneratedCommandCount == AutoInputTotalCommandCount)
	{
		bAutoInputCompleted = true;
		AutoInputAccumulatorSeconds = 0.0f;
		CachedMoveAxis = FVector2D::ZeroVector;
		bDashPressedThisFrame = false;

		UE_LOG(LogPredictionLab, Log, TEXT("AutoInput completed pawn=%s duration=%.0fs commands=%d"),
			*GetName(),
			static_cast<float>(AutoInputDurationSeconds),
			AutoInputGeneratedCommandCount);
	}
}

void APredictionLabPawn::SetAutoInputSample(int32 SampleIndex)
{
	const int32 PatternSampleIndex = SampleIndex % AutoInputSamplesPerPattern;
	const int32 SegmentIndex = PatternSampleIndex / AutoInputSamplesPerSegment;

	// 화면 기준: Forward(W) -> Right(D) -> W+D dash -> Back(S) -> Left(A) -> S+A dash.
	// 9초 패턴의 여섯 1.5초 구간은 같은 순서로 반복된다.
	switch (SegmentIndex)
	{
	case 0:
		CachedMoveAxis = FVector2D(0.0f, -1.0f);
		break;
	case 1:
		CachedMoveAxis = FVector2D(1.0f, 0.0f);
		break;
	case 2:
		CachedMoveAxis = FVector2D(1.0f, -1.0f);
		break;
	case 3:
		CachedMoveAxis = FVector2D(0.0f, 1.0f);
		break;
	case 4:
		CachedMoveAxis = FVector2D(-1.0f, 0.0f);
		break;
	default:
		CachedMoveAxis = FVector2D(-1.0f, 1.0f);
		break;
	}

	bDashPressedThisFrame = PatternSampleIndex == AutoInputFirstDashSample
		|| PatternSampleIndex == AutoInputSecondDashSample;
}

void APredictionLabPawn::ApplyStateToActor(const FPredictedState& State)
{
	SetActorLocation(FVector(State.Location), false);
}

void APredictionLabPawn::InitializeStateFromActor(FPredictedState& State) const
{
	State.Location = GetActorLocation();
	State.Velocity = FVector::ZeroVector;
	State.Stamina = SimulationSettings.MaxStamina;
	State.DashCooldownRemaining = 0.0f;
	State.LastProcessedInput = 0;
}

void APredictionLabPawn::ServerSubmitInput_Implementation(const FPredictedInputCmd& Cmd)
{
	if (Cmd.Sequence <= ServerAuthoritativeState.LastProcessedInput)
	{
		return;
	}

	FPredictionSimulation::Simulate(ServerAuthoritativeState, Cmd, SimulationSettings);
	ServerAuthoritativeState.ServerTimeSeconds = GetWorld() ? GetWorld()->GetTimeSeconds() : 0.0f;
	ApplyStateToActor(ServerAuthoritativeState);

	RemoteSnapshot.ServerTimeSeconds = ServerAuthoritativeState.ServerTimeSeconds;
	RemoteSnapshot.Location = ServerAuthoritativeState.Location;
	RemoteSnapshot.Velocity = ServerAuthoritativeState.Velocity;

	UE_LOG(LogPredictionLab, Log, TEXT("Server processed pawn=%s sequence=%u move=(%.2f, %.2f) dash=%s"),
		*GetName(),
		Cmd.Sequence,
		Cmd.MoveAxis.X,
		Cmd.MoveAxis.Y,
		Cmd.bDashPressed ? TEXT("true") : TEXT("false"));

	ClientReceiveAuthoritativeState(ServerAuthoritativeState);
	ForceNetUpdate();
}

void APredictionLabPawn::ClientReceiveAuthoritativeState_Implementation(const FPredictedState& State)
{
	// 서버가 처리한 입력(ack) 시점에 "내가 예측했던 상태"와 "서버 권위 상태"를 비교한다.
	// 둘은 동일한 입력 sequence까지 적용한 같은 시점이므로 순수 예측 오차만 측정된다.
	// (현재 LocalPredictedState와 비교하면 아직 ack되지 않은 in-flight 입력 만큼
	//  항상 앞서 있어 오차가 과대 측정되고, 임계값 판정이 무의미해진다.)
	FPredictedState PredictedAtAck;
	const bool bHavePrediction = InputHistory.TryGetPredictedStateAt(State.LastProcessedInput, PredictedAtAck);

	InputHistory.RemoveProcessed(State.LastProcessedInput);

	if (!bHavePrediction)
	{
		// ack에 대응하는 예측 기록이 없으면(초기 상태 또는 stale/중복 패킷) 보정 여부를
		// 판단할 수 없으므로 건너뛴다. 이후 더 최신 ack가 도착하면 보정된다.
		UE_LOG(LogPredictionLab, Verbose, TEXT("Client ack(no-history) pawn=%s ack=%u pending=%d"),
			*GetName(),
			State.LastProcessedInput,
			InputHistory.Num());
		return;
	}

	const float ErrorDistance = FVector::Dist(FVector(PredictedAtAck.Location), FVector(State.Location));

	// Phase 5: Reconciliation — ack 시점 오차가 임계치를 초과하면 서버 상태로 rewind 한 뒤
	// 아직 서버가 처리하지 않은 pending 입력을 순서대로 재시뮬레이션한다.
	if (ErrorDistance > ReconciliationErrorThreshold)
	{
		const TArray<FPredictedInputCmd> PendingInputs = InputHistory.GetPendingAfter(State.LastProcessedInput);
		const FVector LocationBeforeReplay(LocalPredictedState.Location);

		LocalPredictedState = State;
		for (const FPredictedInputCmd& PendingCmd : PendingInputs)
		{
			FPredictionSimulation::Simulate(LocalPredictedState, PendingCmd, SimulationSettings);
		}
		ApplyStateToActor(LocalPredictedState);

		// 보정으로 인해 화면상 현재 위치가 실제로 얼마나 튀었는지(snap 크기)를 기록한다.
		const float AppliedCorrection = FVector::Dist(LocationBeforeReplay, FVector(LocalPredictedState.Location));
		UE_LOG(LogPredictionLab, Log, TEXT("Client reconcile pawn=%s ack=%u beforeError=%.2f replayed=%d correction=%.2f"),
			*GetName(),
			State.LastProcessedInput,
			ErrorDistance,
			PendingInputs.Num(),
			AppliedCorrection);
	}
	else
	{
		UE_LOG(LogPredictionLab, Log, TEXT("Client ack pawn=%s ack=%u pending=%d beforeError=%.2f"),
			*GetName(),
			State.LastProcessedInput,
			InputHistory.Num(),
			ErrorDistance);
	}
}

void APredictionLabPawn::OnRep_RemoteSnapshot()
{
	if (IsLocallyControlled())
	{
		return;
	}

	// Phase 6: 스냅샷을 순서대로 설정. 예전처럼 즉시 이동하지 않는다.
	// Tick의 InterpolateRemoteSnapshot()이 prev/current를 timestamp 기반으로 보간한다.
	if (bHasCurrentRemoteSnapshot)
	{
		PreviousRemoteSnapshot = CurrentRemoteSnapshot;
		bHasPreviousRemoteSnapshot = true;
	}
	CurrentRemoteSnapshot = RemoteSnapshot;
	CurrentRemoteSnapshotArrivalTimeSeconds = GetWorld() ? GetWorld()->GetTimeSeconds() : 0.0f;
	bHasCurrentRemoteSnapshot = true;
}

void APredictionLabPawn::InterpolateRemoteSnapshot()
{
	const UWorld* World = GetWorld();
	const float NowSeconds = World ? World->GetTimeSeconds() : 0.0f;
	const float ServerTimeDelta = CurrentRemoteSnapshot.ServerTimeSeconds - PreviousRemoteSnapshot.ServerTimeSeconds;

	// 현재 스냅샷을 받은 뒤 흐른 시간을 서버 스냅샷 간격과 비교해 보간 위치를 정한다.
	float Alpha = 1.0f;
	if (ServerTimeDelta > 0.0f)
	{
		const float ElapsedSeconds = NowSeconds - CurrentRemoteSnapshotArrivalTimeSeconds;
		Alpha = FMath::Clamp(ElapsedSeconds / ServerTimeDelta, 0.0f, 1.0f);
	}

	const FVector InterpolatedLocation = FMath::Lerp(
		FVector(PreviousRemoteSnapshot.Location),
		FVector(CurrentRemoteSnapshot.Location),
		Alpha);

	SetActorLocation(InterpolatedLocation, false);
}
