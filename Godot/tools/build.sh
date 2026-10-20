#!/usr/bin/env bash
# Ensure the repo venv exists, install Godot build deps, then compile the extensions.
# Usage (from anywhere):
#   ./Godot/tools/build.sh
#   ./Godot/tools/build.sh unit_tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${GODOT_DIR}/.." && pwd)"
VENV="${REPO_ROOT}/.venv"

cd "${REPO_ROOT}"

if [[ ! -d "${GODOT_DIR}/godot-cpp/SConstruct" && ! -f "${GODOT_DIR}/godot-cpp/SConstruct" ]]; then
	echo "godot-cpp is missing. Run: git submodule update --init --recursive" >&2
	exit 1
fi

if [[ ! -d "${VENV}" ]]; then
	echo "Creating ${VENV}"
	python3 -m venv "${VENV}"
fi

# shellcheck disable=SC1091
source "${VENV}/bin/activate"

python -m pip install --quiet --require-hashes -r "${GODOT_DIR}/requirements.txt"

if command -v nproc >/dev/null 2>&1; then
	JOBS="$(nproc)"
elif command -v sysctl >/dev/null 2>&1; then
	JOBS="$(sysctl -n hw.logicalcpu)"
else
	JOBS=4
fi

exec scons -C "${GODOT_DIR}" platform=linux target=template_debug -j"${JOBS}" "$@"
