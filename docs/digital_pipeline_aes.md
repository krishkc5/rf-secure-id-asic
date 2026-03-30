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

## Module Interfaces Summary

`rf_secure_id_packet_rx`
- input: `core_clk`, `rst_n`, `serial_bit`
- output: `packet_valid`, `packet_data[159:0]`

`rf_secure_id_packet_parser`
- input: `core_clk`, `rst_n`, `packet_valid`, `packet_data[159:0]`
- output: `parsed_valid`, `packet_type[7:0]`, `ciphertext[127:0]`, `crc_rx[15:0]`

`rf_secure_id_crc16_checker`
- input: `core_clk`, `rst_n`, `parsed_valid`, `packet_type[7:0]`, `ciphertext[127:0]`, `crc_rx[15:0]`
- output: `crc_valid`, `crc_ok`, `crc_calc[15:0]`

`rf_secure_id_aes_decrypt`
- input: `core_clk`, `rst_n`, `key_valid`, `key_in[127:0]`, `cipher_valid`, `ciphertext[127:0]`
- output: `plaintext_valid`, `plaintext[127:0]`, `decrypt_busy`

`rf_secure_id_plaintext_validator`
- input: `core_clk`, `rst_n`, `plaintext_valid`, `plaintext[127:0]`
- output: `decrypt_valid`, `decrypt_ok`, `id[15:0]`

`rf_secure_id_cam`
- input: `core_clk`, `rst_n`, `decrypt_valid`, `decrypt_ok`, `id[15:0]`
- output: `lookup_valid`, `id_hit`

`rf_secure_id_timeout_monitor`
- input: `core_clk`, `rst_n`, `start`, `done`
- output: `timeout_valid`

`rf_secure_id_classifier`
- input: `core_clk`, `rst_n`, `lookup_valid`, `id_hit`, `timeout_valid`
- output: `classify_valid`, `authorized`, `unauthorized`, `unresponsive`

`rf_secure_id_digital`
- input: `core_clk`, `rst_n`, `serial_bit`
- output: `classify_valid`, `authorized`, `unauthorized`, `unresponsive`

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
- `decrypt_busy` is exposed for observability, but should not heavily drive system control in the first version.

## AES Key Handling

- Default key:
  - `128'h000102030405060708090A0B0C0D0E0F`
- `rf_secure_id_aes_decrypt` includes a synchronous key-loading interface:
  - `key_valid`
  - `key_in[127:0]`
- In the active integrated top-level, this interface is reserved for future use and is tied inactive.
- `key_reg` updates only when `decrypt_busy == 0`
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
- `rf_secure_id_timeout_monitor` cancels the countdown when `lookup_valid` is asserted before expiry
- if the countdown expires first, `timeout_valid` pulses for one cycle
- `rf_secure_id_classifier` converts `timeout_valid` into:
  - `classify_valid = 1`
  - `authorized = 0`
  - `unauthorized = 0`
  - `unresponsive = 1`
- `lookup_valid` has priority over `timeout_valid` if both ever coincide

## Clocking and Timing Intent

- Intended clock target: `50 MHz`
- Intended serial data rate: `1 bit / cycle`
- Expected dominant path: AES inverse round logic in `rf_secure_id_aes_decrypt`
- Expected AES decrypt latency: `10 cycles`
- Expected end-to-end authorized / unauthorized classification latency: approximately `16 cycles` from packet end in the current implementation
- If timing closure fails later, the first expected improvement is AES datapath pipelining

## Mixed-Signal Boundary

The detailed analog/digital contract is documented in [`analog_digital_interface.md`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/docs/analog_digital_interface.md).
