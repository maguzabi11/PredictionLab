#include "PredictionSimulation.h"

void FPredictionSimulation::Simulate(FPredictedState& State, const FPredictedInputCmd& Cmd, const FPredictionSimulationSettings& Settings)
{
	const float DeltaSeconds = FMath::Max(0.0f, Cmd.DeltaSeconds);

	FVector2D MoveAxis = Cmd.MoveAxis;
	if (MoveAxis.SizeSquared() > 1.0f)
	{
		MoveAxis.Normalize();
	}

	const FVector MoveDirection(MoveAxis.X, MoveAxis.Y, 0.0f);
	FVector Velocity = MoveDirection * Settings.MaxMoveSpeed;

	State.DashCooldownRemaining = FMath::Max(0.0f, State.DashCooldownRemaining - DeltaSeconds);
	State.Stamina = FMath::Min(Settings.MaxStamina, State.Stamina + Settings.StaminaRegenPerSecond * DeltaSeconds);

	// 대시를 사용할 수 있는 상태
	if (Cmd.bDashPressed && State.DashCooldownRemaining <= 0.0f && State.Stamina >= Settings.DashStaminaCost)
	{
		const FVector DashDirection = MoveDirection.IsNearlyZero() ? FVector::ForwardVector : MoveDirection.GetSafeNormal();
		Velocity += DashDirection * Settings.DashSpeed;
		State.DashCooldownRemaining = Settings.DashCooldownSeconds;
		State.Stamina -= Settings.DashStaminaCost;
	}

	State.Location = FVector(State.Location) + Velocity * DeltaSeconds;
	State.Velocity = Velocity;
	State.LastProcessedInput = Cmd.Sequence;
}
