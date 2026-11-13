// Copyright (c) 2026 Advanced Micro Devices, Inc. All Rights Reserved.

#include "training/bindings/register_types.h"

#include "training/bindings/schola_training_connector.h"
#include "training/schola_training_probe.h"

#include <godot_cpp/core/class_db.hpp>

#ifdef SCHOLA_INTEGRATION_TESTS
void register_schola_training_test_client();
#endif

void register_schola_training_binding_types() {
	GDREGISTER_CLASS(ScholaTrainingProbe);
	GDREGISTER_CLASS(ScholaTrainingConnector);
#ifdef SCHOLA_INTEGRATION_TESTS
	register_schola_training_test_client();
#endif
}

void unregister_schola_training_binding_types() {
}
