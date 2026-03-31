# Digital Backend Signoff Intent

This note collects the non-style signoff artifacts and implementation intent for the active
digital backend.

## Active Scope

Production digital path:

```text
rf_secure_id_digital
  -> rf_secure_id_packet_rx
  -> rf_secure_id_packet_parser
  -> rf_secure_id_crc16_checker
  -> rf_secure_id_aes_decrypt
  -> rf_secure_id_plaintext_validator
  -> rf_secure_id_cam
  -> rf_secure_id_timeout_monitor
  -> rf_secure_id_classifier
```

Verification-only wrapper:
- [`rf_secure_id_timeout4_top.sv`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/tb/rf_secure_id_timeout4_top.sv)

## CDC and Reset Strategy

- The active datapath is single-clock in `core_clk`.
- The only intentional asynchronous control sampled by the top-level is external `rst_n`.
- Reset release is synchronized with a 2-flop chain in the two top-level wrappers.
- The synchronizer flops are marked `ASYNC_REG` in RTL and should be kept adjacent in backend
  implementation.
- No multi-bit CDC path exists in the active integrated digital pipeline.

MTBF assumptions:
- destination clock: `50 MHz`
- reset release is infrequent relative to continuous data traffic
- the 2-flop synchronizer is considered sufficient for this project-level backend
- if process-specific MTBF signoff is required later, it must be computed with real library
  metastability parameters and actual reset event assumptions

CDC implementation notes:
- the synchronizer chain is single-bit only; no multi-bit CDC is present in the active datapath
- the synchronizer must not be retimed, duplicated, or absorbed into surrounding logic
- backend constraints should preserve the two-flop chain as a dedicated reset-release structure
- placement review should confirm short routing between synchronizer stages and no logic between them

Concrete CDC artifacts in the repo:
- timing template:
  - [`rf_secure_id_digital.sdc`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/constraints/rf_secure_id_digital.sdc)
- implementation companion:
  - [`rf_secure_id_backend_impl.tcl`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/constraints/rf_secure_id_backend_impl.tcl)
- interface / MTBF assumptions:
  - [`analog_digital_interface.md`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/docs/analog_digital_interface.md)

CDC closure rule for this project:
- keep `reg_reset_sync_stage1_f` and `reg_reset_sync_stage2_f` marked `ASYNC_REG` and `DONT_TOUCH`
- apply the tool's `dont_retime` / `dont_replicate` equivalent to the reset synchronizer pair
- keep the two synchronizer flops adjacent during placement
- preserve the stage order `stage1 -> stage2 -> rst_pipe_n`
- perform the MTBF worksheet below if a library-specific signoff package is required

MTBF worksheet target:
- assumed destination clock: `50 MHz`
- assumed reset release rate: <= `1 event / second`
- required criterion: MTBF comfortably above project lifetime once foundry `tau` and `T0`
  parameters are applied
- evaluation formula:
  - `MTBF = exp(Tresolve / tau) / (fclk * fevent * T0)`

## Timing and Pipelining

Target clock:
- `50 MHz`

Stage-by-stage timing intent:
1. top-level boundary capture and reset synchronization
2. packet receive shift / preamble detect
3. packet parse
4. CRC16 check
5. AES input capture
6. AES iterative round datapath
7. plaintext validation
8. CAM compare
9. timeout watchdog
10. final classifier

Stage ownership and retiming policy:
- S0 `rf_secure_id_digital`: preserve wrapper boundary capture and reset synchronizer; no retiming
  across the top-level shell
- S1 `rf_secure_id_packet_rx`: preserve request / response boundary; local shifter optimization only
- S2 `rf_secure_id_packet_parser`: preserve parser output register stage
- S3 `rf_secure_id_crc16_checker`: allow local Boolean optimization for speed, but do not retime
  across the module boundary
- S4 / S5 `rf_secure_id_aes_decrypt`: preserve module boundary flops, optimize internally for speed
- S6 `rf_secure_id_plaintext_validator`: preserve boundary flops; allow balanced area cleanup
- S7 `rf_secure_id_cam`: preserve boundary flops and keep the register-based compare architecture
- S8 `rf_secure_id_timeout_monitor`: preserve watchdog boundary flops; allow area-first cleanup
- S9 `rf_secure_id_classifier`: preserve final registered outputs; allow area-first cleanup

Current latency targets:
- authorized / unauthorized: `24 cycles` from end of packet
- default unresponsive: `42 cycles` from end of packet
- AES decrypt core: `10 cycles` from accepted `cipher_valid` to `plain_fire_q`

Critical-path threshold policy:
- any path exceeding `5` logic levels is treated as `STA_CRITICAL` for project review
- the active RTL already tags the dominant path families in top headers and project docs

Interface timing budgets:
- `serial_bit` and `rst_n` are budgeted with `4.0 ns` input delay in the checked-in template
- `classify_valid_q`, `class_grant_q`, `class_reject_q`, and `unresponsive_q` are budgeted with `4.0 ns`
  output delay in the checked-in template
- no internal multicycle or false-path exception is intended in the active pipeline

Hold / min-delay policy:
- hold closure is expected to be handled with standard backend buffering rather than RTL changes
- if min-delay violations cluster around the reset synchronizer, fix them in backend while preserving
  the two-flop adjacency requirement
- if hold issues appear across stage boundaries, preserve the registered architecture and repair them
  with placement / buffering before considering RTL restructuring

Top timing-critical paths:
1. AES inverse-round transform
2. AES round-key select plus state update
3. CAM compare and first-hit logic
4. packet receive preamble and payload shift
5. CRC16 reduction path
6. plaintext structure compare
7. timeout expiration compare
8. classifier terminal output selection
9. reset synchronizer release into the first active stage
10. CRC-to-start qualification into AES / timeout

Approximate logic-depth intent by stage:
- S0 top boundary capture / reset release: `1-2` logic levels
- S1 packet receive: `4-5` logic levels
- S2 packet parse: `1-2` logic levels
- S3 CRC16 check: `5` logic levels and XOR reduction depth
- S4 AES input capture: `1` logic level
- S5 AES inverse round: `>5` logic levels and treated as dominant critical stage
- S6 plaintext validation: `2-3` logic levels
- S7 CAM compare / first-hit select: `4-5` logic levels
- S8 timeout watchdog: `2-3` logic levels
- S9 classifier: `1-2` logic levels

Retiming / optimization policy:
- preserve registered stage boundaries
- prefer optimization inside AES before adding new architectural stages elsewhere
- no false-path or multicycle exception is intended in the active pipeline
- boundary outputs are registered to keep interface timing simple
- do not re-encode the explicit one-hot FSMs in `rf_secure_id_packet_rx` or
  `rf_secure_id_aes_decrypt`
- do not remap the register-based CAM to RAM / ROM in the ruled baseline

Compile strategy:
- front-end synthesis sanity flow: `read_verilog -sv; hierarchy; proc; opt; check/stat`
- implementation-oriented synthesis intent: medium-to-high effort on timing for AES and CAM,
  moderate area recovery on CRC / control blocks
- suggested partition / compile order:
  1. packet receive and parser
  2. CRC16 checker
  3. AES decrypt
  4. plaintext validator and CAM
  5. timeout monitor and classifier
  6. top-level wrapper
- preserve hierarchy at the top level and around the reset synchronizer
- do not ungroup the reset synchronizer; allow internal optimization inside AES round logic if needed
- prefer speed-first optimization on AES, then balanced optimization elsewhere

Project synthesis rule-resolution policy:
- explicit one-hot FSM encoding takes precedence over tool-chosen FSM recoding in this project
- internal registered state uses `_f/_nxt`; externally visible registered outputs use `_q`
- plain `case` with explicit `default` is the active portability baseline
- these choices are fixed for the ruled project baseline and are not treated as open style options

## Resource and Power Intent

Area-critical blocks:
1. `rf_secure_id_aes_decrypt`
2. `rf_secure_id_cam`
3. `rf_secure_id_packet_rx`
4. `rf_secure_id_crc16_checker`

Resource strategy:
- AES is iterative and fixed-key in the integrated path
- CAM is intentionally register-based for transparent RTL behavior
- no external memory macros are instantiated in the current implementation
- no inferred RAM, ROM, or FIFO macros are intentionally used in the active path
- no DSP-specific or technology-specific primitives are required
- if a future implementation swaps CAM storage to a memory macro, that should remain behind the
  same registered interface boundary

Measured Yosys baseline (2026-03-30):
- total design cells: `1466`
- `rf_secure_id_aes_decrypt`: `935` cells (`63.8%` of total)
- `rf_secure_id_crc16_checker`: `415` cells (`28.3%`)
- `rf_secure_id_cam`: `31` cells (`2.1%`)
- `rf_secure_id_packet_rx`: `28` cells (`1.9%`)
- `rf_secure_id_timeout_monitor`: `20` cells (`1.4%`)
- `rf_secure_id_classifier`: `16` cells (`1.1%`)
- `rf_secure_id_plaintext_validator`: `9` cells (`0.6%`)
- `rf_secure_id_packet_parser`: `7` cells (`0.5%`)
- `rf_secure_id_digital`: `5` cells (`0.3%`)
- total frontend helper memories: `34`
- total helper memory bits: `69632`

Resource closure note:
- the reported Yosys memories are frontend helper structures inside `rf_secure_id_aes_decrypt`
  function lowering, not required technology RAMs
- the CAM resource model is intentionally register-based and is treated as an approved project choice

Power strategy:
- high-toggle blocks are AES state logic, CAM compare logic, and packet receive shifting
- those toggles are functional in the current design; no known wasteful free-running datapath exists
  outside packet search / receive activity and AES active rounds
- qualitative toggle ranking:
  1. AES state / inverse round logic
  2. CAM compare fanout
  3. packet receive shift path
  4. CRC16 XOR reduction
  5. timeout / classifier control
- no clock gating is implemented
- no operand isolation is implemented
- first follow-up opportunities are AES operand isolation and CAM compare gating
- low-criticality candidates for area/power recovery are timeout, classifier, and plaintext validation
  before touching the AES critical path

Relative dynamic-power proxy:
- proxy formula = `local cell count * qualitative activity weight`
- activity weights used in this project:
  - AES decrypt = `5`
  - CAM = `4`
  - packet_rx = `4`
  - CRC16 = `3`
  - remaining control = `1`
- resulting proxy breakdown:
  - AES decrypt: `4675` score (`75.2%`)
  - CRC16 checker: `1245` score (`20.0%`)
  - CAM: `124` score (`2.0%`)
  - packet_rx: `112` score (`1.8%`)
  - remaining control: `57` score (`0.9%`)
- this proxy is the quantified project-level power evidence for the current ruled baseline;
  library-based power signoff remains an external implementation step

Relative static-power proxy:
- proxy formula = `local cell count` with no RAM macro or analog leakage contribution included
- rationale:
  - the current ruled baseline uses standard-cell style RTL only
  - no embedded memory macros, DSP macros, or explicit power domains are present
  - leakage is therefore approximated by cell count share until a real library is chosen
- resulting proxy breakdown:
  - AES decrypt: `935` units (`63.8%`)
  - CRC16 checker: `415` units (`28.3%`)
  - CAM: `31` units (`2.1%`)
  - packet_rx: `28` units (`1.9%`)
  - remaining control: `57` units (`3.9%`)
- this is the project-level static-power estimate for the current portable RTL baseline;
  library-specific leakage signoff remains an external implementation step

Optimization closure rule:
- speed-first optimization priority:
  1. `rf_secure_id_aes_decrypt`
  2. `rf_secure_id_crc16_checker`
  3. `rf_secure_id_cam`
- balanced cleanup after timing closure:
  1. `rf_secure_id_packet_rx`
  2. `rf_secure_id_packet_parser`
  3. `rf_secure_id_plaintext_validator`
- area / power recovery after timing closure:
  1. `rf_secure_id_timeout_monitor`
  2. `rf_secure_id_classifier`
- preserve top-level hierarchy, reset synchronizer structure, and all inter-stage registered boundaries

Resource notes:
- current implementation intentionally uses a register-based CAM rather than a memory macro so that
  lookup behavior remains transparent in portable RTL and Yosys sanity flow
- this is treated as an explicit project choice, not an accidental inferred-memory style
- a future memory-macro migration should preserve the same registered request/response interface

## Verification and Signoff Flow

Primary repo-root regression:

```bash
uv run --python .venv/bin/python -m pytest -s tb/test_rf_secure_id_runner.py
```

Primary repo-root synthesis sanity flow:

```bash
bash scripts/run_digital_backend_sanity.sh
```

Required signoff-oriented checks captured in repo intent:
- RTL simulation of the active pipeline
- synthesized-netlist smoke simulation using Yosys-exported `synth.v`
- Yosys syntax / synthesis sanity
- Yosys hierarchy / cell statistics
- synthesized Verilog export
- protocol monitor checks in cocotb
- coverage closure across directed and randomized traffic

Still external to this repo:
- formal RTL-to-netlist equivalence
- back-annotated SDF timing simulation
- implementation-specific library power analysis
- process/library-specific MTBF calculation for reset release synchronizer

## Constraints and Artifacts

- Timing constraint template:
  - [`constraints/rf_secure_id_digital.sdc`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/constraints/rf_secure_id_digital.sdc)
- Constraint notes:
  - [`constraints/README.md`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/constraints/README.md)
- Metrics and warning review:
  - [`rtl_post_cam_metrics.md`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/docs/rtl_post_cam_metrics.md)
