# RTL Post-CAM Metrics

## CAM RTL Changes

- Upgraded [`cam.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/cam.sv) from a minimal hit-only lookup block into a more realistic parameterized CAM with:
  - registered parallel match evaluation
  - internal `match_vector` generation across all valid entries
  - registered `match_index` metadata for the first matching entry
  - registered `multi_hit` metadata when more than one valid entry matches
- Preserved the active pipeline behavior by keeping `lookup_valid` and `id_hit` semantics unchanged.
- Updated only the two CAM instantiations to leave the new metadata outputs unconnected:
  - [`rf_secure_id_digital.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/rf_secure_id_digital.sv)
  - [`rf_secure_id_digital_timeout4.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/tb/rf_secure_id_digital_timeout4.sv)

## Verification Status

- Cocotb regression passed after the CAM upgrade.
- Command used:
  - `uv run --python .venv/bin/python -m pytest -s tb/test_rf_secure_id_runner.py`
- Result:
  - `2 passed`

## Yosys Status

- Yosys synthesis sanity check passed.
- Command:
  - `yosys -p "read_verilog -sv rtl/*.sv; hierarchy -top rf_secure_id_digital; proc; opt; check"`
- Result:
  - `Found and reported 0 problems.`

- Yosys statistics pass completed.
- Command:
  - `yosys -p "read_verilog -sv rtl/*.sv; hierarchy -top rf_secure_id_digital; proc; opt; stat"`

- Yosys Verilog export completed.
- Command:
  - `yosys -p "read_verilog -sv rtl/*.sv; hierarchy -top rf_secure_id_digital; proc; opt; write_verilog synth.v"`
- Output:
  - [`synth.v`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/synth.v)

## Key Metrics

### Design Hierarchy Summary

- `rf_secure_id_digital`: 1422 cells including submodules
- `aes_decrypt`: 913 cells
- `crc16_checker`: 411 cells
- `cam`: 28 cells
- `packet_rx`: 27 cells
- `timeout_monitor`: 17 cells
- `classifier`: 13 cells
- `plaintext_validator`: 7 cells
- `packet_parser`: 5 cells

### Top-Level Totals

- Total cells: 1422
- Total wires: 1988
- Total wire bits: 21334
- Public wires: 646
- Public wire bits: 10591
- Total ports: 66
- Total port bits: 1110
- Total memories: 33
- Total memory bits: 67584

### Module Cell Counts

- `aes_decrypt`: 913 cells
- `cam`: 28 cells
- `crc16_checker`: 411 cells
- `packet_rx`: 27 cells
- `timeout_monitor`: 17 cells

## Warnings Worth Noting

- Yosys reported 10 unique warnings during frontend/import.
- The warnings are mainly about replacing internal memories/arrays with registers:
  - internal helper arrays inside [`aes_decrypt.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/aes_decrypt.sv)
  - CAM storage arrays inside [`cam.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/cam.sv)
- These warnings did not prevent `check`, `stat`, or `write_verilog` from succeeding.

## Interpretation

- [`aes_decrypt.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/aes_decrypt.sv) is still the dominant source of area/complexity by a large margin.
- [`crc16_checker.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/crc16_checker.sv) is the second-largest logic block because its CRC is fully combinational over a 136-bit input bundle.
- The upgraded [`cam.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/cam.sv) is now more structured and informative, but it is still small compared with AES and CRC logic.

## Overall Status

- The RTL remains synthesizable under the current Yosys sanity flow.
- The active cocotb verification flow remains clean after the CAM upgrade.
- The AES-based pipeline architecture is intact, with only a local CAM improvement and minimal wiring updates.
