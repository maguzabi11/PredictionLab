#include "PredictionLabGameMode.h"
#include "PredictionLabPawn.h"
#include "PredictionLabPlayerController.h"

APredictionLabGameMode::APredictionLabGameMode()
{
	DefaultPawnClass = APredictionLabPawn::StaticClass();
	PlayerControllerClass = APredictionLabPlayerController::StaticClass();
}
