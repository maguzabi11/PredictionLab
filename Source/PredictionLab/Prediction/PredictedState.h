#pragma once

#include "CoreMinimal.h"
#include "PredictedState.generated.h"

USTRUCT()
struct FPredictedState
{
	GENERATED_BODY()

	UPROPERTY()
	uint32 LastProcessedInput = 0;

	UPROPERTY()
	float ServerTimeSeconds = 0.0f;

	UPROPERTY()
	FVector_NetQuantize10 Location = FVector::ZeroVector;

	UPROPERTY()
	FVector_NetQuantize10 Velocity = FVector::ZeroVector;

	UPROPERTY()
	float DashCooldownRemaining = 0.0f;

	UPROPERTY()
	float Stamina = 100.0f;
};

USTRUCT()
struct FRemoteSnapshot
{
	GENERATED_BODY()

	UPROPERTY()
	float ServerTimeSeconds = 0.0f;

	UPROPERTY()
	FVector_NetQuantize10 Location = FVector::ZeroVector;

	UPROPERTY()
	FVector_NetQuantize10 Velocity = FVector::ZeroVector;
};
