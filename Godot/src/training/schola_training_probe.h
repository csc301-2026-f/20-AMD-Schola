#ifndef SCHOLA_TRAINING_PROBE_H
#define SCHOLA_TRAINING_PROBE_H

#include <godot_cpp/classes/node.hpp>

class ScholaTrainingProbe : public godot::Node {
	GDCLASS(ScholaTrainingProbe, godot::Node)

protected:
	static void _bind_methods();
};

#endif // SCHOLA_TRAINING_PROBE_H
