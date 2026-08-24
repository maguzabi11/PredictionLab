#pragma once

#include "CoreMinimal.h"
#include "GameFramework/Pawn.h"
#include "Prediction/PredictedInputCmd.h"
#include "Prediction/PredictedState.h"
#include "Prediction/PredictionHistory.h"
#include "Prediction/PredictionSimulation.h"
#include "PredictionLabPawn.generated.h"

class UCameraComponent;
class USphereComponent;
class USpringArmComponent;
class UStaticMeshComponent;

UCLASS()
class PREDICTIONLAB_API APredictionLabPawn : public APawn
{
	GENERATED_BODY()

public:
	APredictionLabPawn();

	virtual void Tick(float DeltaSeconds) override;
	virtual void SetupPlayerInputComponent(UInputComponent* PlayerInputComponent) override;
	virtual void GetLifetimeReplicatedProps(TArray<FLifetimeProperty>& OutLifetimeProps) const override;

protected:
	virtual void BeginPlay() override;

private:
	UPROPERTY(VisibleAnywhere, Category = "Prediction Lab")
	TObjectPtr<USphereComponent> CollisionComponent;

	UPROPERTY(VisibleAnywhere, Category = "Prediction Lab")
	TObjectPtr<UStaticMeshComponent> MeshComponent;

	UPROPERTY(VisibleAnywhere, Category = "Prediction Lab")
	TObjectPtr<USpringArmComponent> SpringArmComponent;

	UPROPERTY(VisibleAnywhere, Category = "Prediction Lab")
	TObjectPtr<UCameraComponent> CameraComponent;

	UPROPERTY(ReplicatedUsing = OnRep_RemoteSnapshot)
	FRemoteSnapshot RemoteSnapshot;

	// Phase 6: 원격 proxy 보간용 2-point 스냅샷 버퍼. RemoteSnapshot이 수신되면
	// 여기로 밀려들어오고, Tick이 timestamp 기반으로 lerp한다.
	FRemoteSnapshot PreviousRemoteSnapshot;
	FRemoteSnapshot CurrentRemoteSnapshot;
	float CurrentRemoteSnapshotArrivalTimeSeconds = 0.0f;
	bool bHasCurrentRemoteSnapshot = false;
	bool bHasPreviousRemoteSnapshot = false;

	FPredictionSimulationSettings SimulationSettings;
	FPredictionHistory InputHistory;
	FPredictedState LocalPredictedState;
	FPredictedState ServerAuthoritativeState;

	FVector2D CachedMoveAxis = FVector2D::ZeroVector;
	uint32 NextInputSequence = 0;
	bool bDashPressedThisFrame = false;

	// Phase 7B-1: -PredictionLabAutoInput=1일 때 owning client가 재생하는
	// 60초 고정 입력 시퀀스 상태. 수동 입력 경로와 분리해 측정 재현성을 보장한다.
	bool bAutoInputEnabled = false;
	bool bAutoInputStarted = false;
	bool bAutoInputCompleted = false;
	float AutoInputAccumulatorSeconds = 0.0f;
	int32 AutoInputGeneratedCommandCount = 0;

	void MoveForward(float Value);
	void MoveRight(float Value);
	void DashPressed();
	void ProduceLocalInput(float DeltaSeconds);
	void ProduceAutoInput(float DeltaSeconds);
	void SetAutoInputSample(int32 SampleIndex);
	void ApplyStateToActor(const FPredictedState& State);
	void InitializeStateFromActor(FPredictedState& State) const;

	UFUNCTION(Server, Unreliable)
	void ServerSubmitInput(const FPredictedInputCmd& Cmd);

	UFUNCTION(Client, Unreliable)
	void ClientReceiveAuthoritativeState(const FPredictedState& State);

	UFUNCTION()
	void OnRep_RemoteSnapshot();

	void InterpolateRemoteSnapshot();
};
