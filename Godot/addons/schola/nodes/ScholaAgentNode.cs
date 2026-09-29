using Godot;
using System;

namespace Schola.Godot;

[GlobalClass]
public partial class ScholaAgentNode : Node
{
	[Export] public NodePath EnvironmentPath { get; set; }

	public ScholaEnvironmentNode Environment { get; private set; }

	// Called when the node enters the scene tree for the first time.
	public override void _Ready()
	{
		
	}

	// Called every frame. 'delta' is the elapsed time since the previous frame.
	public override void _Process(double delta)
	{
		if (Environment = EnvironmentPath.IsEmpty)
		{
			// fallback
			Environment = GetTree().GetFirstNodeInGroup("schola_environment") as ScholaEnvironmentNode;
		} else
		{
			Environment = GetNodeOrNull<ScholaEnvironmentNode>(EnvironmentPath);
		}
	}

	public void AddReward(float amount, string reason = "")
	{
		
	}

    public void CompleteEpisode()
    {

    }

    public void FailEpisode(string reason = "Failed")
    {

    }
}
