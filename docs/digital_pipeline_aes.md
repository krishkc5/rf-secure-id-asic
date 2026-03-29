# AES-Based Digital Pipeline

This note freezes the next digital architecture baseline for `rf-secure-id-asic`.

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
- one bit per `clk`
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
-> packet_rx
-> packet_parser
-> crc16_checker
-> aes_decrypt
-> plaintext_validator
-> cam
-> classifier
```

## Module Interfaces Summary

`packet_rx`
- input: `clk`, `rst_n`, `serial_bit`
- output: `packet_valid`, `packet_data[159:0]`

`packet_parser`
- input: `clk`, `rst_n`, `packet_valid`, `packet_data[159:0]`
- output: `parsed_valid`, `packet_type[7:0]`, `ciphertext[127:0]`, `crc_rx[15:0]`

`crc16_checker`
- input: `clk`, `rst_n`, `parsed_valid`, `packet_type[7:0]`, `ciphertext[127:0]`, `crc_rx[15:0]`
- output: `crc_valid`, `crc_ok`, `crc_calc[15:0]`

`aes_decrypt`
- input: `clk`, `rst_n`, `cipher_valid`, `ciphertext[127:0]`
- output: `plaintext_valid`, `plaintext[127:0]`, `decrypt_busy`

`plaintext_validator`
- input: `clk`, `rst_n`, `plaintext_valid`, `plaintext[127:0]`
- output: `decrypt_valid`, `decrypt_ok`, `id[15:0]`

`cam`
- input: `clk`, `rst_n`, `decrypt_valid`, `decrypt_ok`, `id[15:0]`
- output: `lookup_valid`, `id_hit`

`classifier`
- input: `clk`, `rst_n`, `lookup_valid`, `id_hit`
- output: `classify_valid`, `authorized`, `unauthorized`

`rf_secure_id_digital`
- input: `clk`, `rst_n`, `serial_bit`
- output: `classify_valid`, `authorized`, `unauthorized`

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

- AES key is fixed in hardware.
- Only one AES block is decrypted per packet.
- No AES mode of operation is used.
- Only one decrypt operation is in flight at a time.
- No replay protection is implemented yet.
- No packet buffering or backpressure is implemented yet.
- `decrypt_busy` is exposed for observability, but should not heavily drive system control in the first version.
