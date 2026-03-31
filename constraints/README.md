# Constraint Notes

This directory holds project-level timing-constraint templates for the active digital backend.

## Active Constraint File

- [`rf_secure_id_digital.sdc`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/constraints/rf_secure_id_digital.sdc)
- [`rf_secure_id_backend_impl.tcl`](/Users/krishnachemudupati/Projects/rf-secure-id-asic/constraints/rf_secure_id_backend_impl.tcl)

## Scope

The active constraint template captures:
- top-level `core_clk`
- top-level input timing for `rst_n` and `serial_bit`
- top-level output timing for `classify_valid_q`, `class_grant_q`, `class_reject_q`, and `unresponsive_q`
- the project intent that no false-path or multicycle exception is required inside the active
  digital pipeline

## CDC Note

The only intended asynchronous control sampled by the production top is `rst_n`.
The reset synchronizer flops are marked `ASYNC_REG` in RTL.

Implementation guidance:
- honor the RTL `ASYNC_REG` and `DONT_TOUCH` attributes on the synchronizer flops
- keep the two synchronizer flops adjacent
- exclude the synchronizer chain from retiming, replication, and logic absorption
- review reset-release timing and placement in the final backend flow
- preserve the stage order `reg_reset_sync_stage1_f -> reg_reset_sync_stage2_f -> rst_pipe_n`
- do not merge the synchronizer stages into surrounding logic during optimization

## Implementation Companion

`rf_secure_id_backend_impl.tcl` records the concrete backend-preservation intent used by this project:
- explicit reset synchronizer cell list
- explicit registered stage-boundary instance list
- speed-first timing-critical instance list
- area / power recovery instance list
- fixed-encoding FSM instance list
- resource-locked instance list for the register-based CAM baseline

## Stage-Boundary Policy

- Preserve the registered request / response boundaries of the active modules.
- Do not retime logic across top-level stage boundaries in the ruled baseline.
- Allow local logic optimization inside the AES, CRC16, and CAM instances.
- Favor speed-first optimization inside AES before changing any other stage.
- Keep the active CAM implementation register-based in the ruled baseline; do not remap it to RAM.
