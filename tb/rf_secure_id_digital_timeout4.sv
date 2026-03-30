//=====================================================================================================
// Module: rf_secure_id_digital_timeout4
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
//   rf_secure_id_timeout_monitor     : Request timeout watchdog with 4-cycle override.
//   rf_secure_id_classifier          : Convert lookup / timeout result to final outputs.
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
//   Interface Budget   : Same registered top-level boundaries as rf_secure_id_digital.
//   Resource Expectation: Matches the production top except for the timeout parameter override.
//   Timing Margin      : Uses the same 50 MHz target margin assumptions as the production top.
//   Signoff Follow-up  : This wrapper is excluded from production signoff and exists only for
//                        directed timeout regression coverage.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock [get_clocks core_clk] 4.000 [get_ports {rst_n serial_bit}]
//   set_output_delay -clock [get_clocks core_clk] 4.000 [get_ports {classify_valid authorized unauthorized unresponsive}]
//   No false-path or multicycle exceptions are expected inside this verification wrapper.
//
// LIMITATION:
//   This wrapper is for verification only and is not part of the production RTL path.
//=====================================================================================================
module rf_secure_id_digital_timeout4 (
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
    always_comb begin : rf_secure_id_digital_timeout4_next_state_logic
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
    always_ff @(posedge core_clk) begin : rf_secure_id_digital_timeout4_register_update
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
        .crc_calc    () // INTENTIONAL_OPEN: debug-only CRC visibility unused by timeout test wrapper.
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
        .decrypt_busy   () // INTENTIONAL_OPEN: busy is not consumed by the forced-timeout wrapper.
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
        .match_index (), // INTENTIONAL_OPEN: CAM metadata not required by the timeout regression wrapper.
        .multi_hit   ()  // INTENTIONAL_OPEN: CAM metadata not required by the timeout regression wrapper.
    );

    // Timeout stage: shorten the watchdog threshold to force timeout coverage in simulation.
    rf_secure_id_timeout_monitor #(
        .P_TIMEOUT_CYCLES(4) // Default is 32; forced to 4 for timeout-focused regression coverage.
    ) i_rf_secure_id_timeout_monitor (
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

endmodule
