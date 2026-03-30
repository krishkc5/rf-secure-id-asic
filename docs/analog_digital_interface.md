# Analog / Digital Interface

This note defines the current mixed-signal boundary assumptions for the digital backend.

## Scope

The active digital top is [`rf_secure_id_digital.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/rf_secure_id_digital.sv).

Top-level digital inputs at the mixed-signal boundary:
- `core_clk`
- `rst_n`
- `serial_bit`

## Signal Contract

`core_clk`
- Single digital clock for the backend
- Current timing intent: `50 MHz` target clock

`rst_n`
- Active-low reset into the digital backend
- Current RTL samples `rst_n` on `core_clk` at the top-level boundary
- Internal logic uses a local synchronized reset release (`rst_n_sync`)
- Reset behavior inside the backend is synchronous to `core_clk`

`serial_bit`
- One serial data bit presented to the digital backend per `core_clk`
- The active RTL samples `serial_bit` directly on `posedge core_clk`
- Therefore, the current backend assumes `serial_bit` is already synchronous to `core_clk`

## Upstream Requirements

The analog or mixed-signal source that drives `serial_bit` must guarantee:
- `serial_bit` meets setup and hold timing relative to `core_clk`
- one valid data bit is delivered per clock cycle
- packet preamble and payload timing are aligned to the same `core_clk` domain seen by the digital backend

If the upstream source cannot guarantee synchronous timing, the current RTL is not sufficient by itself. In that case, chip integration must add:
- a synchronizer or retiming stage before `rf_secure_id_packet_rx`
- any additional bit-alignment logic needed for asynchronous comparator output timing

## Startup / Reset Expectations

On reset:
- packet reception state clears
- decrypt state clears
- timeout state clears
- classification outputs clear

After reset release:
- the digital backend starts from an idle state
- the next valid preamble can begin a new packet immediately

## Reset Behavior

- All internal pipeline modules use `rst_n_sync`
- No internal state is retained across reset
- Partial packets are discarded on reset
- The AES decrypt controller returns to `IDLE` on reset
- The timeout monitor clears any active countdown on reset
- The system returns to an idle, deterministic state after reset release

## Timing Intent

- Target clock: `50 MHz`
- Intended packet sampling rate: `1 bit / cycle`
- Expected AES decrypt latency: `10 cycles` from accepted `cipher_valid` to `plaintext_valid`
- Expected dominant logic depth: inverse AES round datapath in [`rf_secure_id_aes_decrypt.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/rtl/rf_secure_id_aes_decrypt.sv)

If timing closure at the target clock fails in a later ASIC flow, the first expected improvement is additional AES datapath pipelining or a slower target clock.
