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

## Key Loading and Assertions Update

- Added a synchronous key-loading interface to [`aes_decrypt.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/aes_decrypt.sv):
  - new inputs: `key_valid`, `key_in[127:0]`
  - new internal register: `key_reg`
  - `key_reg` resets to the existing default AES-128 key
  - `key_reg` only updates when `decrypt_busy == 0`
- Preserved existing decrypt behavior for the active design by tying the new key input off at the current tops:
  - [`rf_secure_id_digital.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/rf_secure_id_digital.sv)
  - [`rf_secure_id_digital_timeout4.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/tb/rf_secure_id_digital_timeout4.sv)
- Kept the key schedule fixed for now:
  - if `key_reg` matches the default key, the decrypt core uses the existing pre-expanded default round keys
  - if `key_reg` does not match the default key, the core still falls back to the default round keys
  - runtime key expansion is still future work

- Added guarded SystemVerilog assertions in:
  - [`classifier.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/classifier.sv) to enforce mutually exclusive outputs and ensure `classify_valid` maps to exactly one class
  - [`timeout_monitor.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/timeout_monitor.sv) to check `timeout_valid` pulse width and active-state clearing after timeout
  - [`aes_decrypt.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/aes_decrypt.sv) to ensure a new decrypt is not accepted while busy
  - [`rf_secure_id_digital.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/rf_secure_id_digital.sv) to check `lookup_valid` and `timeout_valid` do not overlap
- Assertions are guarded out of synthesis-oriented Yosys parsing with `ifndef SYNTHESIS` and `ifndef YOSYS`.

- Cocotb regression still passes after the update.
- Command used:
  - `uv run --python .venv/bin/python -m pytest -s tb/test_rf_secure_id_runner.py`
- Result:
  - `2 passed`

- Yosys still passes after the update.
- Commands used:
  - `yosys -p "read_verilog -sv rtl/*.sv; hierarchy -top rf_secure_id_digital; proc; opt; check"`
  - `yosys -p "read_verilog -sv rtl/*.sv; hierarchy -top rf_secure_id_digital; proc; opt; stat"`
- Results:
  - `check`: `Found and reported 0 problems.`
  - `stat`: completed successfully

- Updated post-change Yosys metrics:
  - total cells: `1435`
  - `aes_decrypt` cells: `926`
  - `cam` cells: `28`
  - total memories: `34`
  - total memory bits: `69632`

- Interpretation:
  - the AES block remains the dominant source of area and complexity
  - the key-loading interface added a small amount of register/control overhead
  - the design remains verification-clean and synthesis-friendly while leaving dynamic key scheduling as a future enhancement

## Reset Synchronization and Verification Depth Update

- Added a 2-flop reset synchronizer in the active integrated tops:
  - [`rf_secure_id_digital.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/rf_secure_id_digital.sv)
  - [`rf_secure_id_digital_timeout4.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/tb/rf_secure_id_digital_timeout4.sv)
- Internal pipeline modules now use synchronized reset release through `rst_n_sync`.
- Updated the cocotb reset helper to wait through synchronized reset release before applying stimulus.
- Expanded the randomized cocotb stress test from a short smoke check to `128` packets with deterministic seed `0xC35A1234`.

- Cocotb regression still passes after the reset-sync and stress-test updates.
- Command used:
  - `uv run --python .venv/bin/python -m pytest -s tb/test_rf_secure_id_runner.py`
- Result:
  - `2 passed`

- Yosys still passes after the reset-sync update.
- Commands used:
  - `yosys -p "read_verilog -sv rtl/*.sv; hierarchy -top rf_secure_id_digital; proc; opt; check"`
  - `yosys -p "read_verilog -sv rtl/*.sv; hierarchy -top rf_secure_id_digital; proc; opt; stat"`
- Results:
  - `check`: `Found and reported 0 problems.`
  - `stat`: completed successfully

### Updated Metrics

- total cells: `1437`
- `aes_decrypt` cells: `926`
- `cam` cells: `28`
- `rf_secure_id_digital` local cells: `3`
- total memories: `34`
- total memory bits: `69632`

### Yosys Warnings Reviewed and Classified

Yosys warnings reviewed and classified:
- [`aes_decrypt.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/aes_decrypt.sv):
  - 8 warnings about local helper arrays (`byte_lane`, `subbed_lane`, `mixed_lane`) being lowered from memories into registers during frontend import
  - classification: benign for synthesis in the current Yosys flow
  - reason: these are fixed-size local function temporaries, not stateful design memories
- [`cam.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/cam.sv):
  - 2 warnings about `cam_entries_reg` and `cam_valid_reg` being lowered into registers
  - classification: benign for synthesis in the current Yosys flow
  - reason: the current CAM is intentionally a register-based RTL model, not a memory macro

All current Yosys warnings are therefore reviewed and treated as benign frontend lowering behavior, not functional or synthesis blockers.

### Interpretation

- The reset synchronizer adds only a very small amount of top-level logic.
- Area and logic complexity are still dominated by [`aes_decrypt.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/aes_decrypt.sv).
- The stronger randomized regression improves confidence in packet sequencing, negative cases, and output exclusivity without changing RTL behavior.

## Verification Closure Update

- Directed cocotb coverage now explicitly includes:
  - authorized classification
  - unauthorized classification
  - unresponsive classification
  - bad CRC rejection
  - wrong preamble rejection
  - invalid plaintext rejection
  - reset during packet reception
  - back-to-back valid packets
- The randomized cocotb campaign now runs `512` packets with deterministic seed `0xC35A1234`.
- The randomized stream mixes:
  - valid authorized packets
  - valid unauthorized packets
  - bad CRC packets
  - invalid plaintext packets
  - wrong-preamble / malformed traffic
- The randomized test uses a Python-side expected-outcome model and checks the observed classification against that expected result for every packet.
- An always-on cocotb protocol monitor now checks throughout regression:
  - `authorized`, `unauthorized`, and `unresponsive` stay mutually exclusive
  - `classify_valid` is a one-cycle pulse
  - classification events are not duplicated within a single expected response window
  - invalid scenarios do not emit unexpected classifications in their observation windows
- The regression also includes an explicit coverage-closure test that requires these flags:
  - `authorized_classification_observed`
  - `unauthorized_classification_observed`
  - `unresponsive_classification_observed`
  - `bad_crc_case_exercised`
  - `wrong_preamble_case_exercised`
  - `invalid_plaintext_case_exercised`
  - `reset_mid_packet_case_exercised`
  - `back_to_back_packet_case_exercised`

- Active regression command:
  - `uv run --python .venv/bin/python -m pytest -s tb/test_rf_secure_id_runner.py`
- Regression status:
  - passed

- Why this is considered sufficient verification depth for this project:
  - the full active RTL pipeline is exercised end to end
  - all major positive and negative behaviors are covered directly
  - randomized traffic extends confidence beyond the small directed set
  - protocol-level monitor checks guard against common control bugs without adding heavyweight infrastructure
