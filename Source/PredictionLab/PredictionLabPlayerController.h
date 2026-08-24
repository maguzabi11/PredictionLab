#pragma once

#include "CoreMinimal.h"
#include "GameFramework/PlayerController.h"
#include "PredictionLabPlayerController.generated.h"

UCLASS()
class PREDICTIONLAB_API APredictionLabPlayerController : public APlayerController
{
	GENERATED_BODY()

protected:
	virtual void BeginPlay() override;
};
