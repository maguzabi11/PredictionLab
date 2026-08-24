#pragma once

#include "CoreMinimal.h"
#include "PredictedInputCmd.h"
#include "PredictedState.h"

struct FPredictionSimulationSettings
{
	float MaxMoveSpeed = 600.0f;
	float DashSpeed = 1800.0f;
	float DashCooldownSeconds = 0.75f;
	float DashStaminaCost = 25.0f;
	float StaminaRegenPerSecond = 18.0f;
	float MaxStamina = 100.0f;
};

class FPredictionSimulation
{
public:
	static void Simulate(FPredictedState& State, const FPredictedInputCmd& Cmd, const FPredictionSimulationSettings& Settings);
};
