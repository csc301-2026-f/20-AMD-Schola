# Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.
@tool
extends EditorPlugin

const Monitor = preload("res://addons/schola/ui/schola_monitor.gd")
const PREVIEW = "res://examples/ui_preview/main.tscn"
var _dock: VBoxContainer
var _capabilities: Label
var _nodes: ItemList
var _scene_nodes: Array[Node] = []


func _enter_tree() -> void:
	_dock = VBoxContainer.new()
	_dock.name = "Schola"
	_dock.custom_minimum_size.x = 260
	_dock.add_theme_constant_override("separation", 10)
	var heading := Label.new()
	heading.text = "AMD SCHOLA"
	heading.add_theme_font_size_override("font_size", 20)
	_dock.add_child(heading)
	var intro := Label.new()
	intro.text = "Reinforcement learning / Godot"
	_dock.add_child(intro)
	_capabilities = Label.new()
	_capabilities.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(_capabilities)
	_button("Open interactive UI preview", func(): get_editor_interface().open_scene_from_path(PREVIEW))
	_button("Add monitor to current scene", _add_monitor)
	var caption := Label.new()
	caption.text = "SCENE NODES · select to inspect"
	_dock.add_child(caption)
	_nodes = ItemList.new()
	_nodes.custom_minimum_size.y = 180
	_nodes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_nodes.item_selected.connect(_inspect_node)
	_dock.add_child(_nodes)
	_button("Refresh scene & capabilities", _refresh)
	var note := Label.new()
	note.text = "Configure selected nodes in the Inspector.\nThe monitor accepts telemetry from your lifecycle code. Training and inference controls become available when their native APIs are implemented."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dock.add_child(note)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	scene_changed.connect(_on_scene_changed)
	_refresh()


func _exit_tree() -> void:
	remove_control_from_docks(_dock)
	_dock.queue_free()


func _button(caption: String, action: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	_dock.add_child(button)


func _on_scene_changed(_root: Node) -> void:
	_refresh()


func _refresh() -> void:
	var lines := PackedStringArray()
	for native_class in ["ScholaRuntimeProbe", "ScholaEnvironment", "ScholaAgent", "ScholaTrainingConnector", "ScholaOnnxPolicy"]:
		lines.append("%s: %s" % [native_class, "available" if ClassDB.class_exists(native_class) else "unavailable"])
	_capabilities.text = "NATIVE CAPABILITIES\n" + "\n".join(lines)
	_nodes.clear()
	_scene_nodes.clear()
	var root := get_editor_interface().get_edited_scene_root()
	if root:
		_collect_nodes(root, root)
	if _scene_nodes.is_empty():
		_nodes.add_item("No Schola nodes in this scene")
		_nodes.set_item_disabled(0, true)


func _collect_nodes(node: Node, root: Node) -> void:
	if node is Monitor or node.get_class().begins_with("Schola"):
		_scene_nodes.append(node)
		_nodes.add_item(str(root.get_path_to(node)))
	for child in node.get_children():
		# Generated UI children have no owner; only list editable scene nodes.
		if child.owner != null:
			_collect_nodes(child, root)


func _inspect_node(index: int) -> void:
	if index >= _scene_nodes.size() or not is_instance_valid(_scene_nodes[index]):
		_refresh()
		return
	var selection := get_editor_interface().get_selection()
	selection.clear()
	selection.add_node(_scene_nodes[index])
	get_editor_interface().edit_node(_scene_nodes[index])


func _add_monitor() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		_capabilities.text = "Open or create a scene before adding a monitor."
		return
	var layer := CanvasLayer.new()
	layer.name = "ScholaHUD"
	var monitor := Monitor.new()
	monitor.name = "ScholaMonitor"
	layer.add_child(monitor)
	monitor.position = Vector2(16, 16)
	monitor.size = Vector2(420, 420)
	var undo := get_undo_redo()
	undo.create_action("Add Schola monitor")
	undo.add_do_method(root, "add_child", layer, true)
	undo.add_do_method(layer, "set_owner", root)
	undo.add_do_method(monitor, "set_owner", root)
	undo.add_do_method(self, "_refresh")
	undo.add_undo_method(root, "remove_child", layer)
	undo.add_undo_method(self, "_refresh")
	undo.add_do_reference(layer)
	undo.commit_action()
