#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "[1/4] Running cocotb regression (RTL plus synthesized-netlist smoke)"
uv run --python .venv/bin/python -m pytest -s tb/test_rf_secure_id_runner.py

echo "[2/4] Running Yosys check"
yosys -p "read_verilog -sv rtl/*.sv; hierarchy -top rf_secure_id_digital; proc; opt; check"

echo "[3/4] Running Yosys stat"
yosys -p "read_verilog -sv rtl/*.sv; hierarchy -top rf_secure_id_digital; proc; opt; stat"

echo "[4/4] Exporting synthesized Verilog"
yosys -p "read_verilog -sv rtl/*.sv; hierarchy -top rf_secure_id_digital; proc; opt; write_verilog synth.v"
