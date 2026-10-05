#pragma once

#include <godot_cpp/classes/node.hpp>

class ScholaRuntimeProbe : public godot::Node {
	GDCLASS(ScholaRuntimeProbe, godot::Node)

protected:
	static void _bind_methods();
};
