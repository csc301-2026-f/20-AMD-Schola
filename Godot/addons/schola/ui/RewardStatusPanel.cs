using Godot;
using System;

namespace Schola.Godot;

[GlobalClass]
public partial class RewardStatusPanel : PanelContainer
{
	[Export] public NodePath EnvironmentPath { get; set; }

	private Label _label;
    private ScholaEnvironmentNode _environment;

	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
	}


	private void OnRewardChanged(float totalReward, string reason)
	{
		
	}
	
	private void OnEpisodeEnded(bool succeeded)
	{
		
	}
}
