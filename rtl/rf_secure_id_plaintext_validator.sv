//=====================================================================================================
// Module: rf_secure_id_plaintext_validator
// Function: Validate decrypted plaintext structure and recover the ID field.
//
// Parameters:
//   None.
//
// Local Parameters:
//   LP_PLAIN_MAGIC  = 16'hC35A required plaintext signature.
//   LP_MAGIC_*      = Bit positions for plain_magic extraction.
//   LP_ID_*         = Bit positions for ID extraction.
//   LP_RESERVED_*   = Bit positions for reserved-field structure checking.
//
// Ports:
//   core_clk       : Primary digital clock.
//   rst_n          : Active-low reset sampled in the module clock domain.
//   text_evt_i     : One-cycle pulse indicating plaintext is available.
//   text_block_i   : 128-bit plaintext bus from rf_secure_id_aes_decrypt.
//   decrypt_valid_q: One-cycle pulse indicating validator outputs are valid.
//   decrypt_ok_q   : High when plaintext structure matches expectations.
//   tag_word_q     : ID field recovered from plaintext.
//
// Functions:
//   None.
//
// Included Files:
//   None.
//
// State Variables:
//   reg_text_evt_f[0:0]           : One-stage capture register for text_evt_i. Reset default = 1'b0.
//   reg_text_lane_f[127:0]        : One-stage capture register for text_block_i. Reset default = '0.
//   flag_magic_ok[0:0]            : Combinatorial structure check for plain_magic. Not retained across cycles.
//   flag_reserved_ok[0:0]         : Combinatorial structure check for reserved bits. Not retained across cycles.
//   reg_fire_evt_f[0:0]           : Registered decrypt-valid pulse. Reset default = 1'b0.
//   reg_pass_flag_f[0:0]          : Registered plaintext-structure result. Reset default = 1'b0.
//   reg_tag_lane_f[15:0]          : Registered ID field output. Reset default = '0.
//
// Reset Behavior:
//   Active-low reset clears the captured plaintext block, recovered tag, and
//   validator outputs so no stale decrypt result survives reset release.
//
// Reset Rationale:
//   Input capture registers reset to 0 so stale text_block_i data does not trigger a validator result.
//   Output registers reset to 0 so no false decrypt_valid_q pulse, decrypt_ok_q flag, or ID escapes
//   reset before a new plaintext block is checked.
//
// Sub-modules:
//   None.
//
// Clock / Reset:
//   core_clk : Single synchronous clock domain. Target integration frequency is 50 MHz.
//   rst_n    : Active-low reset applied through next-state reset logic.
//
// Timing:
//   Throughput : One validator result per captured text_evt_i event.
//   Latency    : One cycle from captured text_block_i to registered validator outputs.
//
// Synthesis Guidance:
//   Clock Source       : Primary 50 MHz system clock with nominal 50% duty cycle.
//   Constraints        : No internal false-path or multicycle exceptions are expected.
//   Interface Budget   : text_block_i is captured at the boundary; all outputs are registered.
//   Resource Expectation: Small compare-and-extract control logic only; no memories or DSP resources.
//   Resource Estimate   : ~147 state bits, 9 Yosys sanity cells, 0 RAMs, 0 DSPs,
//                         and ~0.6% of the 1466-cell top-level baseline.
//   Signoff Follow-up  : Gate-level simulation and RTL-to-netlist equivalence remain required
//                        final signoff activities outside this educational repo.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock core_clk <integration_defined> [get_ports {text_evt_i text_block_i[*]}]
//   set_output_delay -clock core_clk <integration_defined> [get_ports {decrypt_valid_q decrypt_ok_q tag_word_q[*]}]
//   No false-path or multicycle exceptions are expected for this module.
//
// Specification Reference:
//   Plaintext layout, tag position, and validity rules are documented in
//   docs/digital_pipeline_aes.md.
//
// Byte Ordering:
//   text_block_i follows the published AES plaintext map:
//   [127:112] plain_magic, [111:96] id, [95:0] reserved.
//
// ASCII Timing Sketch:
//   core_clk       : |0|1|2|
//   text_evt_i     :  1 0 0
//   decrypt_valid_q:  0 1 0
//   tag_word_q     :  X valid on decrypt_valid_q pulse
//
// Algorithm Summary:
//   Capture the plaintext block, compare plain_magic and reserved fields
//   against fixed constants, then emit the recovered tag field.
//
// Assumptions:
//   text_block_i is the direct AES plaintext output in the published bit order.
//
// CRITICAL:
//   The validator is the only structural guard before CAM lookup. Relaxing
//   the magic or reserved-field checks changes system acceptance criteria.
//
// LIMITATION:
//   Plaintext validity is limited to structure checks on plain_magic and
//   reserved bits; no authenticated-encryption guarantee is provided.
//
// Interface Reference:
//   Plaintext format, magic word, and validator output semantics are
//   documented in docs/digital_pipeline_aes.md.
//=====================================================================================================
module rf_secure_id_plaintext_validator (
    input  logic         core_clk,
    input  logic         rst_n,
    input  logic         text_evt_i,
    input  logic [127:0] text_block_i,
    output logic         decrypt_valid_q,
    output logic         decrypt_ok_q,
    output logic [15:0]  tag_word_q
);

    //========================================================================
    // Input capture, internal logic, and output staging registers
    //========================================================================
    logic         reg_text_evt_f, reg_text_evt_nxt;
    logic [127:0] reg_text_lane_f, reg_text_lane_nxt;

    logic flag_magic_ok;
    logic flag_reserved_ok;
    logic reg_fire_evt_f, reg_fire_evt_nxt;
    logic reg_pass_flag_f, reg_pass_flag_nxt;
    logic [15:0] reg_tag_lane_f, reg_tag_lane_nxt;

    //========================================================================
    // Local parameters
    //========================================================================
    localparam logic [15:0] LP_PLAIN_MAGIC = 16'hC35A;
    localparam int LP_MAGIC_MSB            = 127;
    localparam int LP_MAGIC_LSB            = 112;
    localparam int LP_TAG_MSB              = 111;
    localparam int LP_TAG_LSB              = 96;
    localparam int LP_RESERVED_MSB         = 95;
    localparam int LP_RESERVED_LSB         = 0;

    //========================================================================
    // Combinatorial next-state logic
    //========================================================================
    always_comb begin : structural_check_next_state_logic
        // Capture the decrypt output bus and compute the next registered
        // structure-validation result that feeds the CAM stage.
        reg_text_evt_nxt  = text_evt_i;
        reg_text_lane_nxt = text_block_i;

        flag_magic_ok    = (reg_text_lane_f[LP_MAGIC_MSB:LP_MAGIC_LSB] == LP_PLAIN_MAGIC);
        flag_reserved_ok = (reg_text_lane_f[LP_RESERVED_MSB:LP_RESERVED_LSB] == 96'h0);

        reg_fire_evt_nxt  = 1'b0;
        reg_pass_flag_nxt = reg_pass_flag_f;
        reg_tag_lane_nxt  = reg_tag_lane_f;

        if (reg_text_evt_f) begin
            reg_fire_evt_nxt  = 1'b1;
            reg_pass_flag_nxt = flag_magic_ok && flag_reserved_ok;
            reg_tag_lane_nxt  = reg_text_lane_f[LP_TAG_MSB:LP_TAG_LSB];
        end

        if (!rst_n) begin
            reg_text_evt_nxt  = 1'b0;
            reg_text_lane_nxt = '0;
            reg_fire_evt_nxt  = 1'b0;
            reg_pass_flag_nxt = 1'b0;
            reg_tag_lane_nxt  = '0;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : structural_check_register_update
        reg_text_evt_f  <= reg_text_evt_nxt;
        reg_text_lane_f <= reg_text_lane_nxt;
        reg_fire_evt_f  <= reg_fire_evt_nxt;
        reg_pass_flag_f <= reg_pass_flag_nxt;
        reg_tag_lane_f  <= reg_tag_lane_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign decrypt_valid_q = reg_fire_evt_f;
    assign decrypt_ok_q    = reg_pass_flag_f;
    assign tag_word_q      = reg_tag_lane_f;

endmodule
