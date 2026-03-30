//=====================================================================================================
// Module: rf_secure_id_digital
// Function: Top-level digital receive pipeline for AES-protected secure ID
//           packets. The wrapper performs reset synchronization and stage-to-
//           stage wiring only.
//
// Parameters:
//   None.
//
// Ports:
//   core_clk       : Primary digital clock.
//   rst_n          : Active-low reset sampled at the top-level boundary.
//   serial_bit     : Serial packet input, one bit sampled per clock cycle.
//   classify_valid : One-cycle pulse for a terminal classification result.
//   authorized     : High when a valid packet decrypts to an authorized ID.
//   unauthorized   : High when a valid packet decrypts to an unknown ID.
//   unresponsive   : High when processing times out before lookup completes.
//
// Functions:
//   None.
//
// State Variables:
//   reg_reset_sync_stage1_f[0:0] : First stage of reset release synchronization, reset to 0.
//   reg_reset_sync_stage2_f[0:0] : Second stage of reset release synchronization, reset to 0.
//   reg_serial_bit_in_f[0:0]     : Boundary capture register for serial_bit, reset to 0.
//   rst_n_sync[0:0]              : Synchronized internal reset release derived from stage2.
//   rx_packet_valid[0:0]         : Registered packet-valid pulse from rf_secure_id_packet_rx.
//   rx_packet_data[159:0]        : Registered packet bus from rf_secure_id_packet_rx.
//   parsed_valid_int[0:0]        : Registered parser-valid pulse from rf_secure_id_packet_parser.
//   packet_type_int[7:0]         : Registered packet_type field from rf_secure_id_packet_parser.
//   ciphertext_int[127:0]        : Registered ciphertext field from rf_secure_id_packet_parser.
//   crc_rx_int[15:0]             : Registered received CRC field from rf_secure_id_packet_parser.
//   crc_valid_int[0:0]           : Registered CRC-result-valid pulse from rf_secure_id_crc16_checker.
//   crc_ok_int[0:0]              : Registered CRC match result from rf_secure_id_crc16_checker.
//   cipher_valid_int[0:0]        : Combinational AES start qualifier = crc_valid_int && crc_ok_int.
//   plaintext_valid_int[0:0]     : Registered plaintext-valid pulse from rf_secure_id_aes_decrypt.
//   plaintext_int[127:0]         : Registered plaintext block from rf_secure_id_aes_decrypt.
//   decrypt_valid_int[0:0]       : Registered validator pulse from rf_secure_id_plaintext_validator.
//   decrypt_ok_int[0:0]          : Registered plaintext-structure result from rf_secure_id_plaintext_validator.
//   id_int[15:0]                 : Registered recovered ID from rf_secure_id_plaintext_validator.
//   lookup_valid_int[0:0]        : Registered lookup-valid pulse from rf_secure_id_cam.
//   id_hit_int[0:0]              : Registered CAM hit result from rf_secure_id_cam.
//   timeout_valid_int[0:0]       : Registered timeout pulse from rf_secure_id_timeout_monitor.
//
// Sub-modules:
//   rf_secure_id_packet_rx           : Detect preamble and assemble a 160-bit packet.
//   rf_secure_id_packet_parser       : Extract packet_type, ciphertext, and CRC16.
//   rf_secure_id_crc16_checker       : Validate packet_type || ciphertext.
//   rf_secure_id_aes_decrypt         : AES-128 iterative decrypt block.
//   rf_secure_id_plaintext_validator : Enforce plaintext structure and recover ID.
//   rf_secure_id_cam                 : Parallel ID lookup block.
//   rf_secure_id_timeout_monitor     : Request timeout watchdog.
//   rf_secure_id_classifier          : Convert lookup / timeout result to final outputs.
//
// Clock / Reset:
//   core_clk : Single synchronous clock domain. Target integration frequency is 50 MHz.
//   rst_n    : Active-low reset sampled by the local 2-flop reset synchronizer.
//
// Timing:
//   STA_CRITICAL: System critical paths are expected in AES decrypt first, CAM compare second,
//                 and packet receive shift logic third.
//   Throughput : One packet classification in flight at a time.
//   Latency    : Packet classification latency is determined by packet receive,
//                CRC, AES, validation, CAM, timeout, and classifier stage depth.
//   Top Critical Paths:
//     1. rf_secure_id_aes_decrypt inverse-round datapath.
//     2. rf_secure_id_aes_decrypt round-key select plus state update.
//     3. rf_secure_id_cam parallel compare and first-hit selection.
//     4. rf_secure_id_packet_rx preamble detect and payload shift update.
//     5. rf_secure_id_crc16_checker 136-bit CRC reduction path.
//     6. rf_secure_id_plaintext_validator structure-check compare path.
//     7. rf_secure_id_timeout_monitor countdown compare and pulse generation.
//     8. rf_secure_id_classifier terminal class selection.
//     9. reset synchronizer release path into the active pipeline.
//    10. top-level crc_valid_int -> timeout/aes start qualification.
//
// Synthesis Guidance:
//   Clock Source       : Primary 50 MHz system clock with nominal 50% duty cycle.
//   Constraints        : No internal false-path or multicycle exceptions are expected in the
//                        active pipeline. Integration-level I/O timing is documented separately.
//   Interface Budget   : serial_bit is captured in the first stage and final classification
//                        outputs are registered at the top boundary.
//   Resource Expectation: AES decrypt dominates area and timing; CAM is the next largest block.
//                         No clock gating, generated clocks, or embedded memory macros are used.
//   Timing Margin      : Target >=10% post-route slack margin at the 50 MHz integration point.
//   Signoff Follow-up  : Gate-level simulation, RTL-to-netlist equivalence, and timing-focused
//                        regression remain required final signoff activities outside this repo.
//                        Back-annotated timing simulation should focus on reset release,
//                        packet framing, AES completion, and timeout classification.
//   Post-Synth Checks  : Required scenarios are reset release, authorized classification,
//                        unauthorized classification, invalid plaintext timeout, and
//                        wrong-preamble / bad-CRC rejection with X-propagation review.
//   Equivalence        : RTL-to-netlist equivalence is required with AES round-key constants,
//                        reset synchronizer flops, and SVA excluded from the compare point set.
//   X Strategy         : All architectural state is explicitly reset. Gate-level regression should
//                        confirm no X leakage reaches classification outputs after reset release.
//   Power Notes        : Highest toggle activity is expected in AES state transforms, CAM compares,
//                        and packet receive shifters. No clock gating or operand isolation is used.
//                        Future optimization candidates are AES operand isolation and CAM gating.
//   Area Notes         : AES decrypt is the dominant area block, CAM is second, and the remaining
//                        control-oriented stages are comparatively small.
//   Area Breakdown     : Expected ordering is AES decrypt >> CAM > packet receive / CRC >
//                        plaintext validator / timeout / classifier / reset synchronization.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock [get_clocks core_clk] 4.000 [get_ports {rst_n serial_bit}]
//   set_output_delay -clock [get_clocks core_clk] 4.000 [get_ports {classify_valid authorized unauthorized unresponsive}]
//   No false-path or multicycle exceptions are expected inside this top-level wrapper.
//
// LIMITATION:
//   The integrated top currently ties the runtime key-loading interface inactive
//   and therefore operates with the built-in AES key schedule.
//=====================================================================================================
module rf_secure_id_digital (
    input  logic core_clk,
    input  logic rst_n,
    input  logic serial_bit,
    output logic classify_valid,
    output logic authorized,
    output logic unauthorized,
    output logic unresponsive
);

    //========================================================================
    // Reset synchronization
    //========================================================================
    logic reg_reset_sync_stage1_f;
    logic reg_reset_sync_stage1_nxt;
    logic reg_reset_sync_stage2_f;
    logic reg_reset_sync_stage2_nxt;
    logic reg_serial_bit_in_f;
    logic reg_serial_bit_in_nxt;
    logic rst_n_sync;

    //========================================================================
    // Internal stage-to-stage signals
    //========================================================================
    logic         rx_packet_valid;
    logic [159:0] rx_packet_data;

    logic         parsed_valid_int;
    logic [7:0]   packet_type_int;
    logic [127:0] ciphertext_int;
    logic [15:0]  crc_rx_int;

    logic         crc_valid_int;
    logic         crc_ok_int;
    logic         cipher_valid_int;

    logic         plaintext_valid_int;
    logic [127:0] plaintext_int;

    logic         decrypt_valid_int;
    logic         decrypt_ok_int;
    logic [15:0]  id_int;

    logic lookup_valid_int;
    logic id_hit_int;
    logic timeout_valid_int;

    //========================================================================
    // Combinatorial next-state logic
    //========================================================================
    always_comb begin : rf_secure_id_digital_next_state_logic
        // Synchronize reset release into the local clock domain while leaving
        // all packet-processing behavior inside the registered sub-modules.
        reg_reset_sync_stage1_nxt = reg_reset_sync_stage1_f;
        reg_reset_sync_stage2_nxt = reg_reset_sync_stage2_f;
        reg_serial_bit_in_nxt     = serial_bit;

        if (!rst_n) begin
            reg_reset_sync_stage1_nxt = 1'b0;
            reg_reset_sync_stage2_nxt = 1'b0;
            reg_serial_bit_in_nxt     = 1'b0;
        end else begin
            reg_reset_sync_stage1_nxt = 1'b1;
            reg_reset_sync_stage2_nxt = reg_reset_sync_stage1_f;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : rf_secure_id_digital_register_update
        reg_reset_sync_stage1_f <= reg_reset_sync_stage1_nxt;
        reg_reset_sync_stage2_f <= reg_reset_sync_stage2_nxt;
        reg_serial_bit_in_f     <= reg_serial_bit_in_nxt;
    end

    //========================================================================
    // Continuous assignments
    //========================================================================
    assign rst_n_sync       = reg_reset_sync_stage2_f;
    assign cipher_valid_int = crc_valid_int && crc_ok_int;

    //========================================================================
    // Sub-module instantiations
    //========================================================================
    // Packet framing stage: detect the preamble and assemble the serialized packet.
    rf_secure_id_packet_rx i_rf_secure_id_packet_rx (
        .core_clk    (core_clk),
        .rst_n       (rst_n_sync),
        .serial_bit  (reg_serial_bit_in_f),
        .packet_valid(rx_packet_valid),
        .packet_data (rx_packet_data)
    );

    // Packet parser stage: slice the received packet into type, ciphertext, and CRC fields.
    rf_secure_id_packet_parser i_rf_secure_id_packet_parser (
        .core_clk    (core_clk),
        .rst_n       (rst_n_sync),
        .packet_valid(rx_packet_valid),
        .packet_data (rx_packet_data),
        .parsed_valid(parsed_valid_int),
        .packet_type (packet_type_int),
        .ciphertext  (ciphertext_int),
        .crc_rx      (crc_rx_int)
    );

    // CRC stage: validate packet_type || ciphertext before starting AES decryption.
    rf_secure_id_crc16_checker i_rf_secure_id_crc16_checker (
        .core_clk    (core_clk),
        .rst_n       (rst_n_sync),
        .parsed_valid(parsed_valid_int),
        .packet_type (packet_type_int),
        .ciphertext  (ciphertext_int),
        .crc_rx      (crc_rx_int),
        .crc_valid   (crc_valid_int),
        .crc_ok      (crc_ok_int),
        .crc_calc    () // INTENTIONAL_OPEN: debug-only CRC visibility unused at top level.
    );

    // AES stage: iteratively decrypt a single accepted ciphertext block at a time.
    rf_secure_id_aes_decrypt i_rf_secure_id_aes_decrypt (
        .core_clk       (core_clk),
        .rst_n          (rst_n_sync),
        .key_valid      (1'b0),
        .key_in         ('0),
        .cipher_valid   (cipher_valid_int),
        .ciphertext     (ciphertext_int),
        .plaintext_valid(plaintext_valid_int),
        .plaintext      (plaintext_int),
        .decrypt_busy   () // INTENTIONAL_OPEN: busy is not consumed by the current top-level wrapper.
    );

    // Plaintext validation stage: enforce the structural contract and recover the ID field.
    rf_secure_id_plaintext_validator i_rf_secure_id_plaintext_validator (
        .core_clk       (core_clk),
        .rst_n          (rst_n_sync),
        .plaintext_valid(plaintext_valid_int),
        .plaintext      (plaintext_int),
        .decrypt_valid  (decrypt_valid_int),
        .decrypt_ok     (decrypt_ok_int),
        .id             (id_int)
    );

    // Lookup stage: perform the registered parallel compare against authorized IDs.
    rf_secure_id_cam i_rf_secure_id_cam (
        .core_clk    (core_clk),
        .rst_n       (rst_n_sync),
        .decrypt_valid(decrypt_valid_int),
        .decrypt_ok  (decrypt_ok_int),
        .id          (id_int),
        .lookup_valid(lookup_valid_int),
        .id_hit      (id_hit_int),
        .match_index (), // INTENTIONAL_OPEN: CAM metadata not required by the active classifier stage.
        .multi_hit   ()  // INTENTIONAL_OPEN: CAM metadata not required by the active classifier stage.
    );

    // Timeout stage: convert missing lookup completion into a one-cycle timeout pulse.
    rf_secure_id_timeout_monitor i_rf_secure_id_timeout_monitor (
        .core_clk    (core_clk),
        .rst_n       (rst_n_sync),
        .start       (cipher_valid_int),
        .done        (lookup_valid_int),
        .timeout_valid(timeout_valid_int)
    );

    // Final classification stage: map lookup and timeout results to terminal outputs.
    rf_secure_id_classifier i_rf_secure_id_classifier (
        .core_clk      (core_clk),
        .rst_n         (rst_n_sync),
        .lookup_valid  (lookup_valid_int),
        .id_hit        (id_hit_int),
        .timeout_valid (timeout_valid_int),
        .classify_valid(classify_valid),
        .authorized    (authorized),
        .unauthorized  (unauthorized),
        .unresponsive  (unresponsive)
    );

`ifndef RF_SECURE_ID_SVA_OFF
`ifdef RF_SECURE_ID_SIMONLY

`include "sva/rf_secure_id_digital_sva.sv"

`endif // RF_SECURE_ID_SIMONLY
`endif // RF_SECURE_ID_SVA_OFF

endmodule
