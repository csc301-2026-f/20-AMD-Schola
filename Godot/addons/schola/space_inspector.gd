# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
extends EditorInspectorPlugin

const AGENT_HELP: Dictionary = {
	"agent_id": "Leave empty to use this node's name. Set an explicit ID to keep it stable after renaming. IDs must be unique within an environment.",
	"agent_type": "Optional policy-sharing label. Empty uses the resolved agent ID without changing the saved value.",
	"observation_space": "Shape and type returned by _observe(). Required when neither _define_observation_space() nor descendant components supply this side. Otherwise the corresponding callback overrides this Inspector assignment; invalid results never fall back to these fields. Callback results are validated at runtime startup, never by Inspector warnings, and are not copied into saved Inspector fields, which may remain empty. Resources may be shared; use Make Unique to edit an independent copy.",
	"action_space": "Shape and type accepted by _act(). Required when neither _define_action_space() nor descendant components supply this side. Otherwise the corresponding callback overrides this Inspector assignment; invalid results never fall back to these fields. Callback results are validated at runtime startup, never by Inspector warnings, and are not copied into saved Inspector fields, which may remain empty. Resources may be shared; use Make Unique to edit an independent copy.",
}

const SPACE_HELP: Dictionary = {
	"ScholaBoxSpace": {
		"low": "Lower bounds in row-major order. Empty means unbounded below; one value applies to all elements.",
		"high": "Upper bounds in row-major order. Empty means unbounded above; one value applies to all elements.",
		"shape": "Positive dimensions in row-major order. Empty infers a single dimension from the larger bound array. Configure a shape or bounds before use.",
		"dtype": "Element data type. Defaults to float32.",
	},
	"ScholaDiscreteSpace": {
		"n": "Number of choices, with values from 0 through N - 1. Set a positive size; the initial value 0 requires configuration.",
	},
	"ScholaMultiBinarySpace": {
		"n": "Number of independent binary values (0 or 1). Set a positive size; the initial value 0 requires configuration.",
	},
	"ScholaMultiDiscreteSpace": {
		"nvec": "One positive choice count per dimension. Each value is in [0, N). Starts empty and requires configuration.",
	},
	"ScholaDictSpace": {
		"spaces": "Named subspaces. Use unique string keys and assign a ScholaSpace to every entry. Entries are processed in sorted key order. Resources can be reused; a Dict must not contain itself.",
	},
}


func _can_handle(object: Object) -> bool:
	return object.is_class("ScholaAgent") or object.is_class("ScholaSpace")


func _parse_begin(object: Object) -> void:
	if not object.is_class("ScholaAgent") or not object.has_code_defined_spaces():
		return
	var notice := VBoxContainer.new()
	var title := Label.new()
	title.text = "Spaces defined in code"
	title.add_theme_font_size_override("font_size", 16)
	notice.add_child(title)
	var description := Label.new()
	var hooks: Array[String] = []
	if object.has_code_defined_observation_space():
		hooks.append("_define_observation_space()")
	if object.has_code_defined_action_space():
		hooks.append("_define_action_space()")
	description.text = "This agent uses %s. Each hook overrides its corresponding field below; these fields show only saved Inspector assignments." % " and ".join(hooks)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	notice.add_child(description)
	add_custom_control(notice)


func _parse_property(
	object: Object, _type: Variant.Type, name: String, _hint_type: PropertyHint,
	_hint_string: String, _usage_flags: int, _wide: bool
) -> bool:
	var description: String = ""
	if object.is_class("ScholaAgent"):
		description = AGENT_HELP.get(name, "")
	else:
		for native_class: String in SPACE_HELP:
			if object.is_class(native_class):
				description = SPACE_HELP[native_class].get(name, "")
				break
	if not description.is_empty():
		var help := Label.new()
		help.text = description
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		help.modulate = Color(1, 1, 1, 0.7)
		add_custom_control(help)
	# Keep Godot's standard resource editors, save controls, and Make Unique menu.
	return false
