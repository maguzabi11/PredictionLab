#include "PredictionLabPlayerController.h"

void APredictionLabPlayerController::BeginPlay()
{
	Super::BeginPlay();

	bShowMouseCursor = false;
	SetInputMode(FInputModeGameOnly());
}
