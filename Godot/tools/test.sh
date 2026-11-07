#!/usr/bin/env bash
# Build and run Godot Schola tests.
# Usage (from anywhere):
#   ./Godot/tools/test.sh              # unit (default)
#   ./Godot/tools/test.sh unit
#   ./Godot/tools/test.sh inference
#   ./Godot/tools/test.sh transport
#   ./Godot/tools/test.sh integration
#   ./Godot/tools/test.sh all
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${GODOT_DIR}/.." && pwd)"
SUITE="${1:-unit}"

run_catch() {
	local target="$1"
	local binary="$2"
	"${SCRIPT_DIR}/build.sh" "${target}"
	"${REPO_ROOT}/Godot/build/tests/${binary}"
}

run_integration() {
	"${SCRIPT_DIR}/build.sh" schola schola_training integration_tests=yes
	python "${GODOT_DIR}/tools/setup_test_dependencies.py"
	godot --headless --path "${GODOT_DIR}" --import || true
	godot --headless --path "${GODOT_DIR}" \
		-s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
		--ignoreHeadlessMode -a res://tests/integration
}

case "${SUITE}" in
unit)
	run_catch unit_tests schola_core_tests
	;;
inference)
	run_catch inference_tests schola_inference_tests
	;;
transport)
	run_catch transport_tests schola_transport_tests
	;;
integration)
	run_integration
	;;
all)
	run_catch unit_tests schola_core_tests
	run_catch inference_tests schola_inference_tests
	run_catch transport_tests schola_transport_tests
	run_integration
	;;
*)
	echo "Unknown suite: ${SUITE}" >&2
	echo "Usage: $0 [unit|inference|transport|integration|all]" >&2
	exit 1
	;;
esac
