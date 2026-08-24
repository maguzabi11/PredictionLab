#pragma once

#include "CoreMinimal.h"
#include "PredictedInputCmd.generated.h"

USTRUCT()
struct FPredictedInputCmd
{
	GENERATED_BODY()

	UPROPERTY()
	uint32 Sequence = 0;

	UPROPERTY()
	float ClientTimeSeconds = 0.0f;

	UPROPERTY()
	float DeltaSeconds = 0.0f;

	UPROPERTY()
	FVector2D MoveAxis = FVector2D::ZeroVector;

	UPROPERTY()
	bool bDashPressed = false;
};
