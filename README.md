# RF Secure ID ASIC

## Active Digital Backend

The active digital receive/classify path is:

```text
serial_bit
-> rf_secure_id_packet_rx
-> rf_secure_id_packet_parser
-> rf_secure_id_crc16_checker
-> rf_secure_id_aes_decrypt
-> rf_secure_id_plaintext_validator
-> rf_secure_id_cam
-> rf_secure_id_timeout_monitor
-> rf_secure_id_classifier
```

Top-level RTL:
- [`rf_secure_id_digital.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/rf_secure_id_digital.sv)

## Repo-Root Verification

Run the active cocotb regression:

```bash
uv run --python .venv/bin/python -m pytest -s tb/test_rf_secure_id_runner.py
```

## Repo-Root Synthesis Sanity

Run the checked-in digital sanity flow:

```bash
bash scripts/run_digital_backend_sanity.sh
```

Or run Yosys directly:

```bash
yosys -p "read_verilog -sv rtl/*.sv; hierarchy -top rf_secure_id_digital; proc; opt; check"
yosys -p "read_verilog -sv rtl/*.sv; hierarchy -top rf_secure_id_digital; proc; opt; stat"
yosys -p "read_verilog -sv rtl/*.sv; hierarchy -top rf_secure_id_digital; proc; opt; write_verilog synth.v"
```

## Key Docs

- Architecture baseline:
  - [`digital_pipeline_aes.md`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/docs/digital_pipeline_aes.md)
- Analog / digital boundary:
  - [`analog_digital_interface.md`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/docs/analog_digital_interface.md)
- Metrics and verification closure:
  - [`rtl_post_cam_metrics.md`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/docs/rtl_post_cam_metrics.md)
- Signoff intent and constraint artifacts:
  - [`digital_backend_signoff.md`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/docs/digital_backend_signoff.md)
  - [`constraints/rf_secure_id_digital.sdc`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/constraints/rf_secure_id_digital.sdc)
