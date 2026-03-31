//=====================================================================================================
// Module: rf_secure_id_timeout4_top
// Function: Test-only top-level wrapper matching rf_secure_id_digital while
//           overriding the timeout monitor threshold to 4 cycles for the
//           forced-timeout cocotb scenario.
//
// Parameters:
//   None.
//
// Ports:
//   core_clk       : Primary digital clock.
//   rst_n          : Active-low reset sampled at the top-level boundary.
//   serial_bit     : Serial packet input, one bit sampled per clock cycle.
//   classify_valid_q : One-cycle pulse for a terminal classification result.
//   class_grant_q    : High when a valid packet decrypts to an authorized ID.
//   class_reject_q   : High when a valid packet decrypts to an unknown ID.
//   unresponsive_q   : High when processing times out before lookup completes.
//
// Functions:
//   None.
//
// Included Files:
//   None.
//
// State Variables:
//   reg_reset_sync_stage1_f[0:0] : First stage of reset release synchronization, reset to 0.
//   reg_reset_sync_stage2_f[0:0] : Second stage of reset release synchronization, reset to 0.
//   reg_bit_lane_f[0:0]          : Boundary capture register for serial_bit, reset to 0.
//   rst_pipe_n[0:0]              : Synchronized internal reset release derived from stage2.
//   evt_rx_frame[0:0]            : Registered packet-valid pulse from rf_secure_id_packet_rx.
//   bus_rx_frame[159:0]          : Registered packet bus from rf_secure_id_packet_rx.
//   evt_parse_bus[0:0]           : Registered parser-valid pulse from rf_secure_id_packet_parser.
//   bus_type_lane[7:0]           : Registered packet_type field from rf_secure_id_packet_parser.
//   bus_cipher_lane[127:0]       : Registered ciphertext field from rf_secure_id_packet_parser.
//   bus_crc_lane[15:0]           : Registered received CRC field from rf_secure_id_packet_parser.
//   evt_crc_fire[0:0]            : Registered CRC-result-valid pulse from rf_secure_id_crc16_checker.
//   flag_crc_pass[0:0]           : Registered CRC match result from rf_secure_id_crc16_checker.
//   evt_aes_kick[0:0]            : Combinational AES start qualifier = evt_crc_fire && flag_crc_pass.
//   evt_plain_rsp[0:0]           : Registered plaintext-valid pulse from rf_secure_id_aes_decrypt.
//   bus_plain_lane[127:0]        : Registered plaintext block from rf_secure_id_aes_decrypt.
//   evt_check_fire[0:0]          : Registered validator pulse from rf_secure_id_plaintext_validator.
//   flag_check_pass[0:0]         : Registered plaintext-structure result from rf_secure_id_plaintext_validator.
//   bus_tag_lane[15:0]           : Registered recovered tag from rf_secure_id_plaintext_validator.
//   evt_lookup_rsp[0:0]          : Registered lookup-valid pulse from rf_secure_id_cam.
//   flag_lookup_hit[0:0]         : Registered CAM hit result from rf_secure_id_cam.
//   evt_timeout_rsp[0:0]         : Registered timeout pulse from rf_secure_id_timeout_monitor.
//
// Reset Behavior:
//   Active-low reset holds the verification wrapper in reset until the local
//   2-flop synchronizer releases rst_pipe_n on clean core_clk edges.
//
// Reset Rationale:
//   reg_reset_sync_stage*_f reset to 0 so rst_pipe_n stays asserted until two clean core_clk edges.
//   reg_bit_lane_f resets to 0 to discard any stale boundary sample during reset release.
//   All downstream stage outputs are reset inside their owning modules so the timeout-focused
//   wrapper still comes out of reset without false packets or classifications.
//
// Sub-modules:
//   rf_secure_id_packet_rx           : Detect preamble and assemble a 160-bit packet.
//   rf_secure_id_packet_parser       : Extract packet_type, ciphertext, and CRC16.
//   rf_secure_id_crc16_checker       : Validate packet_type || ciphertext.
//   rf_secure_id_aes_decrypt         : AES-128 iterative decrypt block.
//   rf_secure_id_plaintext_validator : Enforce plaintext structure and recover ID.
//   rf_secure_id_cam                 : Parallel ID lookup block.
//   rf_secure_id_timeout_monitor     : Request timeout watchdog with 4-cycle override.
//   rf_secure_id_classifier          : Convert lookup / timeout result to final outputs.
//   Parameter Policy                 : rf_secure_id_cam keeps the production defaults
//                                      P_ENTRY_WIDTH=16 and P_DEPTH=8 so only timeout
//                                      behavior changes in this wrapper. rf_secure_id_timeout_monitor
//                                      fixes P_TIMEOUT_CYCLES=4 solely to accelerate the
//                                      forced-timeout regression without altering other behavior.
//
// Clock / Reset:
//   core_clk : Single synchronous clock domain. Target integration frequency is 50 MHz.
//   rst_n    : Active-low reset sampled by the local 2-flop reset synchronizer.
//
// Timing:
//   STA_CRITICAL: Verification wrapper inherits the production critical paths
//                 while reducing timeout latency for forced-timeout coverage.
//   Throughput : Same as rf_secure_id_digital for normal traffic.
//   Latency    : Timeout-focused regression uses a 4-cycle timeout threshold
//                instead of the default 32-cycle threshold.
//
// Synthesis Guidance:
//   Clock Source       : Primary 50 MHz system clock with nominal 50% duty cycle.
//   Constraints        : Verification-only wrapper; no production timing exceptions intended.
//   CDC Strategy       : Matches rf_secure_id_digital: rst_n enters through a 2-flop
//                        ASYNC_REG synchronizer and serial_bit is captured at the wrapper
//                        boundary before the production packet receive stage.
//   CDC Placement      : Keep the reset synchronizer flops adjacent and exclude them from
//                        retiming so the verification wrapper matches production reset release.
//   Interface Budget   : Same registered top-level boundaries as rf_secure_id_digital.
//   Resource Expectation: Matches the production top except for the timeout parameter override.
//   Resource Estimate   : ~3 wrapper state bits, 5 local wrapper cells, 0 RAMs, 0 DSPs,
//                         plus the same downstream hierarchy as rf_secure_id_digital.
//   Timing Margin      : Uses the same 50 MHz target margin assumptions as the production top.
//   Signoff Follow-up  : This wrapper is excluded from production signoff and exists only for
//                        directed timeout regression coverage.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock [get_clocks core_clk] 4.000 [get_ports {rst_n serial_bit}]
//   set_output_delay -clock [get_clocks core_clk] 4.000
//                    [get_ports {classify_valid_q class_grant_q class_reject_q unresponsive_q}]
//   No false-path or multicycle exceptions are expected inside this verification wrapper.
//
// Specification Reference:
//   Functional behavior matches docs/digital_pipeline_aes.md except for the
//   reduced timeout threshold used only for cocotb coverage.
//
// ASCII Timing Sketch:
//   core_clk        : |0|1|2|...|
//   serial_bit      :  b0 b1 b2 ...
//   evt_aes_kick    :  0  0  1  ...
//   evt_timeout_rsp :  0  0  0  ... pulse after 4-cycle watchdog expiry
//   unresponsive_q  :  0  0  0  ... pulse after classifier stage
//
// Algorithm Summary:
//   Mirror the production top-level wiring exactly, but override only the
//   timeout watchdog threshold to accelerate the forced-timeout regression.
//
// Assumptions:
//   This wrapper is compiled only in verification flows and never replaces
//   the production top in implementation.
//
// CRITICAL:
//   The timeout override is required for the forced-timeout regression and
//   must not leak into the production top-level configuration.
//
// TOOL_DEPENDENCY:
//   The reset synchronizer uses ASYNC_REG and DONT_TOUCH attributes.
//
// LIMITATION:
//   This wrapper is for verification only and is not part of the production RTL path.
//
// Interface Reference:
//   Production top-level semantics are documented in docs/digital_pipeline_aes.md;
//   this wrapper changes only the timeout threshold for verification.
//=====================================================================================================
module rf_secure_id_timeout4_top (
    input  logic core_clk,
    input  logic rst_n,
    input  logic serial_bit,
    output logic classify_valid_q,
    output logic class_grant_q,
    output logic class_reject_q,
    output logic unresponsive_q
);

    //========================================================================
    // Reset synchronization
    //========================================================================
    (* ASYNC_REG = "TRUE", DONT_TOUCH = "TRUE" *) logic reg_reset_sync_stage1_f;
    logic reg_reset_sync_stage1_nxt;
    (* ASYNC_REG = "TRUE", DONT_TOUCH = "TRUE" *) logic reg_reset_sync_stage2_f;
    logic reg_reset_sync_stage2_nxt;
    logic reg_bit_lane_f, reg_bit_lane_nxt;
    logic rst_pipe_n;

    //========================================================================
    // Internal stage-to-stage signals
    //========================================================================
    logic         evt_rx_frame;
    logic [159:0] bus_rx_frame;

    logic         evt_parse_bus;
    logic [7:0]   bus_type_lane;
    logic [127:0] bus_cipher_lane;
    logic [15:0]  bus_crc_lane;

    logic         evt_crc_fire;
    logic         flag_crc_pass;
    logic         evt_aes_kick;

    logic         evt_plain_rsp;
    logic [127:0] bus_plain_lane;

    logic         evt_check_fire;
    logic         flag_check_pass;
    logic [15:0]  bus_tag_lane;

    logic evt_lookup_rsp;
    logic flag_lookup_hit;
    logic evt_timeout_rsp;

    //========================================================================
    // Combinatorial next-state logic
    //========================================================================
    always_comb begin : timeout4_top_next_state_logic
        // Synchronize reset release into the local clock domain while leaving
        // all packet-processing behavior inside the registered sub-modules.
        reg_reset_sync_stage1_nxt = reg_reset_sync_stage1_f;
        reg_reset_sync_stage2_nxt = reg_reset_sync_stage2_f;
        reg_bit_lane_nxt          = serial_bit;

        if (!rst_n) begin
            reg_reset_sync_stage1_nxt = 1'b0;
            reg_reset_sync_stage2_nxt = 1'b0;
            reg_bit_lane_nxt          = 1'b0;
        end else begin
            reg_reset_sync_stage1_nxt = 1'b1;
            reg_reset_sync_stage2_nxt = reg_reset_sync_stage1_f;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : timeout4_top_register_update
        reg_reset_sync_stage1_f <= reg_reset_sync_stage1_nxt;
        reg_reset_sync_stage2_f <= reg_reset_sync_stage2_nxt;
        reg_bit_lane_f          <= reg_bit_lane_nxt;
    end

    //========================================================================
    // Continuous assignments
    //========================================================================
    assign rst_pipe_n   = reg_reset_sync_stage2_f;
    assign evt_aes_kick = evt_crc_fire && flag_crc_pass;

    //========================================================================
    // Sub-module instantiations
    //========================================================================
    // Packet framing stage: detect the preamble and assemble the serialized packet.
    rf_secure_id_packet_rx i_rf_secure_id_packet_rx (
        .core_clk    (core_clk),
        .rst_n       (rst_pipe_n),
        .serial_bit  (reg_bit_lane_f),
        .packet_valid_q(evt_rx_frame),
        .packet_data_q (bus_rx_frame)
    );

    // Packet parser stage: slice the received packet into type, ciphertext, and CRC fields.
    rf_secure_id_packet_parser i_rf_secure_id_packet_parser (
        .core_clk    (core_clk),
        .rst_n       (rst_pipe_n),
        .frame_evt_i  (evt_rx_frame),
        .frame_bits_i (bus_rx_frame),
        .parsed_valid_q(evt_parse_bus),
        .packet_type_q (bus_type_lane),
        .ciphertext_q  (bus_cipher_lane),
        .crc_rx_q      (bus_crc_lane)
    );

    // CRC stage: validate packet_type || ciphertext before starting AES decryption.
    rf_secure_id_crc16_checker i_rf_secure_id_crc16_checker (
        .core_clk    (core_clk),
        .rst_n       (rst_pipe_n),
        .parse_evt_i   (evt_parse_bus),
        .type_lane_i   (bus_type_lane),
        .cipher_lane_i (bus_cipher_lane),
        .rx_crc_i      (bus_crc_lane),
        .crc_valid_q (evt_crc_fire),
        .crc_ok_q    (flag_crc_pass),
        .crc_calc_q  () // INTENTIONAL_OPEN: debug-only CRC visibility unused by timeout test wrapper.
    );

    // AES stage: iteratively decrypt a single accepted ciphertext block at a time.
    rf_secure_id_aes_decrypt i_rf_secure_id_aes_decrypt (
        .core_clk       (core_clk),
        .rst_n          (rst_pipe_n),
        .key_valid      (1'b0),
        .key_in         ('0),
        .cipher_valid   (evt_aes_kick),
        .cipher_block_i (bus_cipher_lane),
        .plain_fire_q   (evt_plain_rsp),
        .plain_block_q  (bus_plain_lane),
        .decrypt_busy_q () // INTENTIONAL_OPEN: busy is not consumed by the forced-timeout wrapper.
    );

    // Plaintext validation stage: enforce the structural contract and recover the ID field.
    rf_secure_id_plaintext_validator i_rf_secure_id_plaintext_validator (
        .core_clk       (core_clk),
        .rst_n          (rst_pipe_n),
        .text_evt_i     (evt_plain_rsp),
        .text_block_i   (bus_plain_lane),
        .decrypt_valid_q(evt_check_fire),
        .decrypt_ok_q   (flag_check_pass),
        .tag_word_q     (bus_tag_lane)
    );

    // Lookup stage: perform the registered parallel compare against authorized IDs.
    rf_secure_id_cam i_rf_secure_id_cam (
        .core_clk    (core_clk),
        .rst_n       (rst_pipe_n),
        .check_evt_i   (evt_check_fire),
        .check_pass_i  (flag_check_pass),
        .probe_tag_i   (bus_tag_lane),
        .lookup_fire_q (evt_lookup_rsp),
        .lookup_hit_q  (flag_lookup_hit),
        .lookup_slot_q (), // INTENTIONAL_OPEN: CAM metadata not required by the timeout regression wrapper.
        .lookup_multi_q()  // INTENTIONAL_OPEN: CAM metadata not required by the timeout regression wrapper.
    );

    // Timeout stage: shorten the watchdog threshold to force timeout coverage in simulation.
    rf_secure_id_timeout_monitor #(
        .P_TIMEOUT_CYCLES(4) // Default is 32; forced to 4 for timeout-focused regression coverage.
    ) i_rf_secure_id_timeout_monitor (
        .core_clk    (core_clk),
        .rst_n       (rst_pipe_n),
        .kick_evt_i    (evt_aes_kick),
        .stop_evt_i    (evt_lookup_rsp),
        .timeout_fire_q(evt_timeout_rsp)
    );

    // Final classification stage: map lookup and timeout results to terminal outputs.
    rf_secure_id_classifier i_rf_secure_id_classifier (
        .core_clk      (core_clk),
        .rst_n         (rst_pipe_n),
        .lookup_evt_i    (evt_lookup_rsp),
        .lookup_hit_i    (flag_lookup_hit),
        .timeout_evt_i   (evt_timeout_rsp),
        .classify_valid_q(classify_valid_q),
        .class_grant_q   (class_grant_q),
        .class_reject_q  (class_reject_q),
        .unresponsive_q  (unresponsive_q)
    );

endmodule
