#ifndef SCHOLA_RUNTIME_PROBE_H
#define SCHOLA_RUNTIME_PROBE_H

#include <godot_cpp/classes/node.hpp>

class ScholaRuntimeProbe : public godot::Node {
	GDCLASS(ScholaRuntimeProbe, godot::Node)

protected:
	static void _bind_methods();
};

#endif // SCHOLA_RUNTIME_PROBE_H
