# AES-Based Digital Pipeline

This note freezes the active digital architecture baseline for `rf-secure-id-asic`.

## Packet Format

Fixed packet width: `160` bits

```text
[159:152] preamble    = 8'hA5
[151:144] packet_type
[143:16]  ciphertext   // AES-128 block
[15:0]    crc16
```

Serialization assumptions:
- bits arrive `MSB` first
- one bit per `core_clk`
- `preamble` is transmitted in the clear
- `packet_type` is transmitted in the clear

## Plaintext Layout

AES-128 decrypted block width: `128` bits

```text
[127:112] plain_magic = 16'hC35A
[111:96]  id
[95:0]    reserved    = 96'h0
```

Post-decrypt validity requires:
- `plain_magic == 16'hC35A`
- `reserved == 96'h0`

## Pipeline

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

## Pipeline Stage Map

The active integrated implementation is fully registered stage to stage:

1. top-level boundary capture and reset release synchronization
2. `rf_secure_id_packet_rx`
3. `rf_secure_id_packet_parser`
4. `rf_secure_id_crc16_checker`
5. `rf_secure_id_aes_decrypt` input capture
6. `rf_secure_id_aes_decrypt` iterative round controller
7. `rf_secure_id_plaintext_validator`
8. `rf_secure_id_cam`
9. `rf_secure_id_timeout_monitor`
10. `rf_secure_id_classifier`

Pipeline intent:
- no stalls or backpressure in the active integrated path
- one decrypt operation in flight at a time
- registered boundaries preserved to keep retiming opportunities clear
- likely retiming candidates, if ever needed, are inside the AES datapath rather than across
  module boundaries

Stage ownership and allowed optimization:
- S0 `rf_secure_id_digital`: preserve reset synchronizer and top-level boundary capture
- S1 `rf_secure_id_packet_rx`: preserve packet boundary register; optimize local shifter logic only
- S2 `rf_secure_id_packet_parser`: preserve parse result register; no cross-stage retiming
- S3 `rf_secure_id_crc16_checker`: optimize locally for speed; keep request / response flops intact
- S4/S5 `rf_secure_id_aes_decrypt`: preserve module input/output flops, optimize internally for speed
- S6 `rf_secure_id_plaintext_validator`: preserve boundary flops; area recovery allowed after timing
- S7 `rf_secure_id_cam`: keep register-based compare architecture and preserve output boundary flops
- S8 `rf_secure_id_timeout_monitor`: preserve watchdog boundary flops; area recovery allowed
- S9 `rf_secure_id_classifier`: preserve terminal output register stage; area recovery allowed

## Module Interfaces Summary

`rf_secure_id_packet_rx`
- input: `core_clk`, `rst_n`, `serial_bit`
- output: `packet_valid_q`, `packet_data_q[159:0]`

`rf_secure_id_packet_parser`
- input: `core_clk`, `rst_n`, `frame_evt_i`, `frame_bits_i[159:0]`
- output: `parsed_valid_q`, `packet_type_q[7:0]`, `ciphertext_q[127:0]`, `crc_rx_q[15:0]`

`rf_secure_id_crc16_checker`
- input: `core_clk`, `rst_n`, `parse_evt_i`, `type_lane_i[7:0]`, `cipher_lane_i[127:0]`, `rx_crc_i[15:0]`
- output: `crc_valid_q`, `crc_ok_q`, `crc_calc_q[15:0]`

`rf_secure_id_aes_decrypt`
- input: `core_clk`, `rst_n`, `key_valid`, `key_in[127:0]`, `cipher_valid`, `cipher_block_i[127:0]`
- output: `plain_fire_q`, `plain_block_q[127:0]`, `decrypt_busy_q`

`rf_secure_id_plaintext_validator`
- input: `core_clk`, `rst_n`, `text_evt_i`, `text_block_i[127:0]`
- output: `decrypt_valid_q`, `decrypt_ok_q`, `tag_word_q[15:0]`

`rf_secure_id_cam`
- input: `core_clk`, `rst_n`, `check_evt_i`, `check_pass_i`, `probe_tag_i[15:0]`
- output: `lookup_fire_q`, `lookup_hit_q`, optional metadata `lookup_slot_q`, `lookup_multi_q`

`rf_secure_id_timeout_monitor`
- input: `core_clk`, `rst_n`, `kick_evt_i`, `stop_evt_i`
- output: `timeout_fire_q`

`rf_secure_id_classifier`
- input: `core_clk`, `rst_n`, `lookup_evt_i`, `lookup_hit_i`, `timeout_evt_i`
- output: `classify_valid_q`, `class_grant_q`, `class_reject_q`, `unresponsive_q`

`rf_secure_id_digital`
- input: `core_clk`, `rst_n`, `serial_bit`
- output: `classify_valid_q`, `class_grant_q`, `class_reject_q`, `unresponsive_q`

## CRC16 Convention

CRC covers:

```text
packet_type || ciphertext
```

CRC excludes:
- `preamble`
- `crc16` field itself

CRC convention:
- polynomial: `16'h1021`
- bit order: `MSB` first
- init: `16'h0000`
- reflect in: `0`
- reflect out: `0`
- xorout: `16'h0000`

## Simplifying Assumptions

- The active integrated design is currently a fixed-key AES system.
- The active top-level currently ties `rf_secure_id_aes_decrypt.key_valid = 0` and `key_in = 0`, so the default AES key is always used in the integrated design.
- Only one AES block is decrypted per packet.
- No AES mode of operation is used.
- Only one decrypt operation is in flight at a time.
- No replay protection is implemented yet.
- No packet buffering or backpressure is implemented yet.
- `decrypt_busy_q` is exposed for observability, but should not heavily drive system control in the first version.

## AES Key Handling

- Default key:
  - `128'h000102030405060708090A0B0C0D0E0F`
- `rf_secure_id_aes_decrypt` includes a synchronous key-loading interface:
  - `key_valid`
  - `key_in[127:0]`
- In the active integrated top-level, this interface is reserved for future use and is tied inactive.
- `key_reg` updates only when `decrypt_busy_q == 0`
- Current limitation:
  - if `key_reg` matches the default key, the decrypt core uses the pre-expanded default round keys
  - if `key_reg` does not match the default key, the core still falls back to the default round keys
  - runtime key expansion is future work

## Design Constants

The following are intentionally fixed in this implementation:
- packet format
- plaintext structure
- AES round-key schedule for the default integrated key
- built-in CAM contents

These constants are fixed to keep the hardware small, deterministic, and aligned
with the current fixed-function secure ID receiver use case.

## Security Limitations

- Fixed AES-128 key stored in hardware for the active integrated design
- No replay protection
- No authentication beyond CRC16 plus plaintext structure checks
- No side-channel protections against power, EM, or timing analysis
- Not hardened for adversarial deployment environments

## Timeout Semantics

- `rf_secure_id_timeout_monitor` starts its countdown when `cipher_valid` is asserted
- `rf_secure_id_timeout_monitor` cancels the countdown when `lookup_fire_q` is asserted before expiry
- if the countdown expires first, `timeout_fire_q` pulses for one cycle
- `rf_secure_id_classifier` converts `timeout_fire_q` into:
  - `classify_valid_q = 1`
  - `class_grant_q = 0`
  - `class_reject_q = 0`
  - `unresponsive_q = 1`
- `lookup_evt_i` has priority over `timeout_evt_i` if both ever coincide

## Clocking and Timing Intent

- Intended clock target: `50 MHz`
- Intended serial data rate: `1 bit / cycle`
- Expected dominant path: AES inverse round logic in `rf_secure_id_aes_decrypt`
- Expected AES decrypt latency: `10 cycles`
- Expected end-to-end authorized / unauthorized classification latency: `24 cycles` from packet end in the current implementation
- Expected end-to-end default unresponsive classification latency: `42 cycles` from packet end
- Any path above `5` logic levels is treated as `STA_CRITICAL` for project review
- If timing closure fails later, the first expected improvement is AES datapath pipelining

Top timing attention list:
1. AES inverse-round datapath
2. AES round-key select plus state update
3. CAM parallel compare and first-hit select
4. packet receive preamble detect and payload shift
5. CRC16 reduction over `{packet_type, ciphertext}`

## Resource / Power / Optimization Notes

- Area is dominated by `rf_secure_id_aes_decrypt`, then `rf_secure_id_cam`, then the receive / CRC logic.
- Current Yosys sanity baseline:
  - total design cells: `1466`
  - `rf_secure_id_aes_decrypt`: `935`
  - `rf_secure_id_crc16_checker`: `415`
  - `rf_secure_id_cam`: `31`
  - `rf_secure_id_packet_rx`: `28`
  - `rf_secure_id_timeout_monitor`: `20`
  - `rf_secure_id_classifier`: `16`
  - `rf_secure_id_plaintext_validator`: `9`
  - `rf_secure_id_packet_parser`: `7`
  - `rf_secure_id_digital`: `5`
  - total memories: `34`
  - total memory bits: `69632`
- The CAM is intentionally register-based in this implementation so its behavior is transparent in
  RTL and simulation. A future production memory-macro migration would be an implementation
  optimization, not an architecture change.
- The current rule-checked baseline keeps that register-based CAM architecture fixed.
- Highest toggle activity is expected in:
  - AES state transforms
  - CAM compare logic
  - packet receive shifters
- These toggles are currently treated as functional rather than wasteful for the project-scale design.
- No clock gating or operand isolation is used in the current implementation.
- First optimization candidates, if timing or power require follow-up, are:
  - deeper AES pipelining
  - AES operand isolation when idle
  - CAM compare gating when `decrypt_valid && decrypt_ok` is low
- Lower-criticality area recovery candidates are timeout, classifier, and plaintext validation before
  touching the AES critical path.
- Project rule resolution for synthesis-side conflicts:
  - explicit one-hot FSM encoding in `rf_secure_id_packet_rx` and `rf_secure_id_aes_decrypt`
    is preserved and not auto-recoded
  - internal registered-state naming uses `_f/_nxt`; externally visible registered outputs use `_q`
  - plain `case` with explicit `default` is the active portability baseline

## Signoff Artifacts

The repo now includes:
- project-level timing constraint template:
  - [`constraints/rf_secure_id_digital.sdc`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/constraints/rf_secure_id_digital.sdc)
- project-level constraint notes:
  - [`constraints/README.md`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/constraints/README.md)
- reproducible digital sanity flow:
  - [`scripts/run_digital_backend_sanity.sh`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/scripts/run_digital_backend_sanity.sh)
- synthesis / verification closure notes:
  - [`digital_backend_signoff.md`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/docs/digital_backend_signoff.md)

## Mixed-Signal Boundary

The detailed analog/digital contract is documented in [`analog_digital_interface.md`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/docs/analog_digital_interface.md).
