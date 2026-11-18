// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
shader_type spatial;
render_mode unshaded, fog_disabled;
// Use as material_override on geometry in a dedicated depth-capture viewport.
// Camera-forward distance in Godot units, clamped to [0,1].
uniform float depth_range : hint_range(0.001, 10000.0) = 100.0;
void fragment() {
	float depth = clamp(-VERTEX.z / depth_range, 0.0, 1.0);
	// Vulkan's LDR pipeline encodes linear ALBEDO to sRGB; Compatibility
	// writes sRGB values directly. Cancel that encoding for numeric depth.
	float linear_value = depth <= 0.04045 ? depth / 12.92 : pow((depth + 0.055) / 1.055, 2.4);
	ALBEDO = vec3(OUTPUT_IS_SRGB ? depth : linear_value);
}
