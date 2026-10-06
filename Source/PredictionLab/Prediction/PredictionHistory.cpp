#include "PredictionHistory.h"

void FPredictionHistory::Add(const FPredictedInputCmd& Cmd, const FPredictedState& StateAfter)
{
	FEntry& Entry = Entries.AddDefaulted_GetRef();
	Entry.Cmd = Cmd;
	Entry.StateAfter = StateAfter;

	if (Entries.Num() > MaxSavedCommands)
	{
		Entries.RemoveAt(0, Entries.Num() - MaxSavedCommands, EAllowShrinking::No);
	}
}

bool FPredictionHistory::UpdatePredictedStateAt(uint32 InputSequence, const FPredictedState& StateAfter)
{
	for (FEntry& Entry : Entries)
	{
		if (Entry.Cmd.Sequence == InputSequence)
		{
			Entry.StateAfter = StateAfter;
			return true;
		}
	}

	return false;
}

void FPredictionHistory::RemoveProcessed(uint32 LastProcessedInput)
{
	Entries.RemoveAllSwap(
		[LastProcessedInput](const FEntry& Entry)
		{
			return Entry.Cmd.Sequence <= LastProcessedInput;
		},
		EAllowShrinking::No);

	Entries.Sort(
		[](const FEntry& Left, const FEntry& Right)
		{
			return Left.Cmd.Sequence < Right.Cmd.Sequence;
		});
}

void FPredictionHistory::Reset()
{
	Entries.Reset();
}

int32 FPredictionHistory::Num() const
{
	return Entries.Num();
}

TArray<FPredictedInputCmd> FPredictionHistory::GetPendingAfter(uint32 LastProcessedInput) const
{
	TArray<FPredictedInputCmd> Pending;
	for (const FEntry& Entry : Entries)
	{
		if (Entry.Cmd.Sequence > LastProcessedInput)
		{
			Pending.Add(Entry.Cmd);
		}
	}

	return Pending;
}

bool FPredictionHistory::TryGetPredictedStateAt(const uint32 InputSequence, FPredictedState& OutState) const
{
	for (const auto& [Cmd, StateAfter] : Entries)
	{
		if (Cmd.Sequence == InputSequence)
		{
			OutState = StateAfter;
			return true;
		}
	}

	return false;
}
