using Godot;
using System;

namespace Schola.Godot;

[GlobalClass]
public partial class ScholaEnvironmentNode : Node3D
{

	[ExportCategory("Rewards")]
    [Export] public float ProgressReward { get; set; } = 1.0f;
    [Export] public float StepReward { get; set; } = -0.001f;
    [Export] public float GoalReward { get; set; } = 10.0f;
    [Export] public float FailurePenalty { get; set; } = -10.0f;


	public float TotalReward { get; private set; }
    public bool EpisodeFinished { get; private set; }

	// Notifies listeners when total reward changes
	[Signal]
	public delegate void RewardChangedEventHandler(float totalReward, string reason);
	// Notifies listeners when an episode ends
	[Signal]
	public delegate void EpisodeEndedEventHandler(bool succeeded);


	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
		AddToGroup("schola_environment");
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
		
	}

	// Adds a reward amount to the current episode total
	public void AddReward(float amount, string reason = "")
	{
		
	}

	// Converts progress into a scaled reward
	public void AddProgressReward(float progressAmount)
	{
		
	}

	// Finish episode successfully -> grant the goal reward
	public void CompleteEpisode()
	{
		
	}

	// Finish episode unsuccessfully -> apply the failure penalty
	public void FailEpisode(string reason = "Failed")
	{

	}

	// Clears the current reward total and starts a new episode
	public void ResetEpisode()
	{
		
	}
}
