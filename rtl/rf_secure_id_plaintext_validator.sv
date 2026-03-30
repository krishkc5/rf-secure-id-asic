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
//   plaintext_valid: One-cycle pulse indicating plaintext is available.
//   plaintext      : 128-bit plaintext bus from rf_secure_id_aes_decrypt.
//   decrypt_valid  : One-cycle pulse indicating validator outputs are valid.
//   decrypt_ok     : High when plaintext structure matches expectations.
//   id             : ID field recovered from plaintext.
//
// Functions:
//   None.
//
// State Variables:
//   reg_plaintext_valid_in_f[0:0] : One-stage capture register for plaintext_valid. Reset default = 1'b0.
//   reg_plaintext_in_f[127:0]     : One-stage capture register for plaintext. Reset default = '0.
//   flag_magic_ok[0:0]            : Combinatorial structure check for plain_magic. Not retained across cycles.
//   flag_reserved_ok[0:0]         : Combinatorial structure check for reserved bits. Not retained across cycles.
//   reg_decrypt_valid_f[0:0]      : Registered decrypt-valid pulse. Reset default = 1'b0.
//   reg_decrypt_ok_f[0:0]         : Registered plaintext-structure result. Reset default = 1'b0.
//   reg_id_f[15:0]                : Registered ID field output. Reset default = '0.
//
// Sub-modules:
//   None.
//
// Clock / Reset:
//   core_clk : Single synchronous clock domain. Target integration frequency is 50 MHz.
//   rst_n    : Active-low reset applied through next-state reset logic.
//
// Timing:
//   Throughput : One validator result per captured plaintext event.
//   Latency    : One cycle from captured plaintext to registered validator outputs.
//
// Synthesis Guidance:
//   Clock Source       : Primary 50 MHz system clock with nominal 50% duty cycle.
//   Constraints        : No internal false-path or multicycle exceptions are expected.
//   Interface Budget   : plaintext is captured at the boundary; all outputs are registered.
//   Resource Expectation: Small compare-and-extract control logic only; no memories or DSP resources.
//   Signoff Follow-up  : Gate-level simulation and RTL-to-netlist equivalence remain required
//                        final signoff activities outside this educational repo.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock core_clk <integration_defined> [get_ports {plaintext_valid plaintext[*]}]
//   set_output_delay -clock core_clk <integration_defined> [get_ports {decrypt_valid decrypt_ok id[*]}]
//   No false-path or multicycle exceptions are expected for this module.
//
// LIMITATION:
//   Plaintext validity is limited to structure checks on plain_magic and
//   reserved bits; no authenticated-encryption guarantee is provided.
//=====================================================================================================
module rf_secure_id_plaintext_validator (
    input  logic         core_clk,
    input  logic         rst_n,
    input  logic         plaintext_valid,
    input  logic [127:0] plaintext,
    output logic         decrypt_valid,
    output logic         decrypt_ok,
    output logic [15:0]  id
);

    //========================================================================
    // Input capture, internal logic, and output staging registers
    //========================================================================
    logic reg_plaintext_valid_in_f;
    logic reg_plaintext_valid_in_nxt;
    logic [127:0] reg_plaintext_in_f;
    logic [127:0] reg_plaintext_in_nxt;

    logic flag_magic_ok;
    logic flag_reserved_ok;
    logic reg_decrypt_valid_f;
    logic reg_decrypt_valid_nxt;
    logic reg_decrypt_ok_f;
    logic reg_decrypt_ok_nxt;
    logic [15:0] reg_id_f;
    logic [15:0] reg_id_nxt;

    //========================================================================
    // Local parameters
    //========================================================================
    localparam logic [15:0] LP_PLAIN_MAGIC = 16'hC35A;
    localparam int LP_MAGIC_MSB            = 127;
    localparam int LP_MAGIC_LSB            = 112;
    localparam int LP_ID_MSB               = 111;
    localparam int LP_ID_LSB               = 96;
    localparam int LP_RESERVED_MSB         = 95;
    localparam int LP_RESERVED_LSB         = 0;

    //========================================================================
    // Combinatorial next-state logic
    //========================================================================
    always_comb begin : plaintext_validator_next_state_logic
        // Capture the decrypt output bus and compute the next registered
        // structure-validation result that feeds the CAM stage.
        reg_plaintext_valid_in_nxt = plaintext_valid;
        reg_plaintext_in_nxt       = plaintext;

        flag_magic_ok    = (reg_plaintext_in_f[LP_MAGIC_MSB:LP_MAGIC_LSB] == LP_PLAIN_MAGIC);
        flag_reserved_ok = (reg_plaintext_in_f[LP_RESERVED_MSB:LP_RESERVED_LSB] == 96'h0);

        reg_decrypt_valid_nxt = 1'b0;
        reg_decrypt_ok_nxt    = reg_decrypt_ok_f;
        reg_id_nxt            = reg_id_f;

        if (reg_plaintext_valid_in_f) begin
            reg_decrypt_valid_nxt = 1'b1;
            reg_decrypt_ok_nxt    = flag_magic_ok && flag_reserved_ok;
            reg_id_nxt            = reg_plaintext_in_f[LP_ID_MSB:LP_ID_LSB];
        end

        if (!rst_n) begin
            reg_plaintext_valid_in_nxt = 1'b0;
            reg_plaintext_in_nxt       = '0;
            reg_decrypt_valid_nxt = 1'b0;
            reg_decrypt_ok_nxt    = 1'b0;
            reg_id_nxt            = '0;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : plaintext_validator_register_update
        reg_plaintext_valid_in_f <= reg_plaintext_valid_in_nxt;
        reg_plaintext_in_f       <= reg_plaintext_in_nxt;
        reg_decrypt_valid_f <= reg_decrypt_valid_nxt;
        reg_decrypt_ok_f    <= reg_decrypt_ok_nxt;
        reg_id_f            <= reg_id_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign decrypt_valid = reg_decrypt_valid_f;
    assign decrypt_ok    = reg_decrypt_ok_f;
    assign id            = reg_id_f;

endmodule
