#pragma once

#include "CoreMinimal.h"
#include "PredictedInputCmd.h"
#include "PredictedState.h"

class FPredictionHistory
{
public:
	// 입력 커맨드와, 그 커맨드를 적용한 직후 클라이언트가 예측한 상태를 함께 저장한다.
	void Add(const FPredictedInputCmd& Cmd, const FPredictedState& StateAfter);
	// Replay 결과로 기존 sequence의 전체 예측 상태를 갱신한다. 기록이 없으면 false.
	bool UpdatePredictedStateAt(uint32 InputSequence, const FPredictedState& StateAfter);
	void RemoveProcessed(uint32 LastProcessedInput);
	void Reset();

	int32 Num() const;
	TArray<FPredictedInputCmd> GetPendingAfter(uint32 LastProcessedInput) const;

	// 주어진 sequence를 처리한 직후 클라이언트가 예측했던 상태를 반환한다.
	// reconciliation 오차를 서버 ack와 "같은 시점"끼리 비교하기 위해 사용한다.
	bool TryGetPredictedStateAt(const uint32 InputSequence, FPredictedState& OutState) const;

private:
	struct FEntry
	{
		FPredictedInputCmd Cmd;
		FPredictedState StateAfter;
	};

	static constexpr int32 MaxSavedCommands = 256;

	TArray<FEntry> Entries;
};
