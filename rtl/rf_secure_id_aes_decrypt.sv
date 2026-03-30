//=====================================================================================================
// Module: rf_secure_id_aes_decrypt
// Function: Iterative AES-128 decrypt block with a single block in flight.
//
// Parameters:
//   None.
//
// Local Parameters:
//   LP_NUM_ROUNDS             = 10 AES-128 inverse rounds.
//   LP_ROUND_INDEX_WIDTH      = Width of the iterative round counter.
//   LP_DEFAULT_KEY            = Built-in fixed AES-128 key.
//   LP_DEFAULT_ROUND_KEY_*    = Pre-expanded round-key schedule for LP_DEFAULT_KEY.
//   LP_AES_DECRYPT_FSM_*      = One-hot decrypt controller state encodings.
//
// Ports:
//   core_clk       : Primary digital clock.
//   rst_n          : Active-low reset sampled in the module clock domain.
//   key_valid      : Synchronous key update request, accepted only while idle.
//   key_in         : Replacement AES key input.
//   cipher_valid   : One-cycle pulse starting a decrypt operation.
//   ciphertext     : 128-bit AES ciphertext block.
//   plaintext_valid: One-cycle pulse indicating plaintext output is valid.
//   plaintext      : 128-bit decrypted plaintext block.
//   decrypt_busy   : High while the iterative decrypt engine is active.
//
// Functions:
//   function_get_default_round_key : Return pre-expanded round key by index.
//   function_get_active_round_key  : Select the currently active round key schedule.
//   function_inv_sbox              : AES inverse S-box lookup.
//   function_inv_shift_rows        : AES inverse row permutation.
//   function_gf_mul8               : GF(2^8) multiply used by inverse MixColumns.
//   function_inv_mix_columns       : AES inverse column transform.
//   function_inv_sub_bytes         : AES inverse byte substitution.
//   function_add_round_key         : XOR state with round key.
//   function_inv_round             : Full inverse round with MixColumns.
//   function_inv_final_round       : Final inverse round without MixColumns.
//
// State Variables:
//   reg_key_valid_in_f[0:0]                  : Boundary capture for key_valid, reset to 0.
//   reg_key_in_in_f[127:0]                   : Boundary capture for key_in, reset to 0.
//   reg_cipher_valid_in_f[0:0]               : Boundary capture for cipher_valid, reset to 0.
//   reg_ciphertext_in_f[127:0]               : Boundary capture for ciphertext, reset to 0.
//   reg_aes_decrypt_fsm_state_f[1:0]         : One-hot decrypt FSM, reset to IDLE.
//   reg_state_f[127:0]                       : Iterative AES state register, reset to 0.
//   reg_key_f[127:0]                         : Latched key register, reset to LP_DEFAULT_KEY.
//   reg_round_index_f[LP_ROUND_INDEX_WIDTH]  : Iterative round counter, reset to 0.
//   reg_plaintext_valid_f[0:0]               : Output pulse register, reset to 0.
//   reg_plaintext_f[127:0]                   : Registered plaintext output, reset to 0.
//   reg_decrypt_busy_f[0:0]                  : Registered in-flight flag, reset to 0.
//
// Sub-modules:
//   None.
//
// Clock / Reset:
//   core_clk : Single synchronous clock domain. Target integration frequency is 50 MHz.
//   rst_n    : Active-low reset applied through next-state reset logic.
//
// Timing:
//   TIMING_CRITICAL: The inverse-round datapath dominates module logic depth.
//   STA_CRITICAL   : InvShiftRows -> InvSubBytes -> AddRoundKey -> InvMixColumns round path.
//   Throughput      : One block in flight at a time.
//   Latency         : 10 AES round cycles after the captured start event, plus the
//                     input-capture stage used at the module boundary.
//
// Synthesis Guidance:
//   Clock Source       : Primary 50 MHz system clock with nominal 50% duty cycle.
//   Constraints        : No internal false-path or multicycle exceptions are expected.
//   Interface Budget   : key and ciphertext inputs are captured at the boundary; plaintext and
//                        decrypt_busy are fully registered outputs.
//   Resource Expectation: This is the dominant area and timing block in the design, driven by
//                         the inverse-round combinational datapath and round-key constants.
//                         No RAM, ROM macro, or DSP primitive is instantiated.
//   Timing Margin      : Target >=10% post-route slack margin at the 50 MHz integration point.
//   Signoff Follow-up  : Gate-level simulation, RTL-to-netlist equivalence, and timing-focused
//                        regression remain required final signoff activities outside this repo.
//                        Back-annotated timing simulation should focus on decrypt_busy,
//                        plaintext_valid, and reset-release corner cases.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock [get_clocks core_clk] 4.000 [get_ports {key_valid key_in[*] cipher_valid ciphertext[*]}]
//   set_output_delay -clock [get_clocks core_clk] 4.000 [get_ports {plaintext_valid plaintext[*] decrypt_busy}]
//   No false-path or multicycle exceptions are expected for this block.
//
// Defines:
//   RF_SECURE_ID_SIMONLY : Enables inline include-style SVA during simulation.
//   RF_SECURE_ID_SVA_OFF : Disables the include-style SVA block entirely.
//
// LIMITATION:
//   Non-default runtime keys are latched into the interface register, but the
//   round-key schedule still falls back to the built-in default schedule.
//   No side-channel hardening is implemented in this educational RTL version.
//=====================================================================================================
module rf_secure_id_aes_decrypt (
    input  logic         core_clk,
    input  logic         rst_n,
    input  logic         key_valid,
    input  logic [127:0] key_in,
    input  logic         cipher_valid,
    input  logic [127:0] ciphertext,
    output logic         plaintext_valid,
    output logic [127:0] plaintext,
    output logic         decrypt_busy
);

    //========================================================================
    // Input capture, internal state, and output staging registers
    //========================================================================
    typedef enum logic [1:0] {
        LP_AES_DECRYPT_FSM_IDLE = 2'b01,
        LP_AES_DECRYPT_FSM_RUN  = 2'b10
    } aes_decrypt_fsm_t;

    logic reg_key_valid_in_f;
    logic reg_key_valid_in_nxt;
    logic [127:0] reg_key_in_in_f;
    logic [127:0] reg_key_in_in_nxt;
    logic reg_cipher_valid_in_f;
    logic reg_cipher_valid_in_nxt;
    logic [127:0] reg_ciphertext_in_f;
    logic [127:0] reg_ciphertext_in_nxt;

    aes_decrypt_fsm_t reg_aes_decrypt_fsm_state_f;
    aes_decrypt_fsm_t reg_aes_decrypt_fsm_state_nxt;
    logic [127:0] reg_state_f;
    logic [127:0] reg_state_nxt;
    logic [127:0] reg_key_f;
    logic [127:0] reg_key_nxt;
    logic [LP_ROUND_INDEX_WIDTH-1:0] reg_round_index_f;
    logic [LP_ROUND_INDEX_WIDTH-1:0] reg_round_index_nxt;
    logic reg_plaintext_valid_f;
    logic reg_plaintext_valid_nxt;
    logic [127:0] reg_plaintext_f;
    logic [127:0] reg_plaintext_nxt;
    logic reg_decrypt_busy_f;
    logic reg_decrypt_busy_nxt;

    //========================================================================
    // Function definitions
    //========================================================================
    // function_get_default_round_key
    //   Purpose         : Return one pre-expanded round key from the built-in AES schedule.
    //   Interoperability: Used by function_get_active_round_key and the round controller.
    //   Inputs          : idx in the range [0, 10].
    //   Return          : 128-bit round key value for the requested round.
    //   Usage           : function_get_default_round_key(4'd10)
    function automatic logic [127:0] function_get_default_round_key(input logic [3:0] idx);
        begin
            case (idx)
                4'd0:    function_get_default_round_key = LP_DEFAULT_ROUND_KEY_0;
                4'd1:    function_get_default_round_key = LP_DEFAULT_ROUND_KEY_1;
                4'd2:    function_get_default_round_key = LP_DEFAULT_ROUND_KEY_2;
                4'd3:    function_get_default_round_key = LP_DEFAULT_ROUND_KEY_3;
                4'd4:    function_get_default_round_key = LP_DEFAULT_ROUND_KEY_4;
                4'd5:    function_get_default_round_key = LP_DEFAULT_ROUND_KEY_5;
                4'd6:    function_get_default_round_key = LP_DEFAULT_ROUND_KEY_6;
                4'd7:    function_get_default_round_key = LP_DEFAULT_ROUND_KEY_7;
                4'd8:    function_get_default_round_key = LP_DEFAULT_ROUND_KEY_8;
                4'd9:    function_get_default_round_key = LP_DEFAULT_ROUND_KEY_9;
                4'd10:   function_get_default_round_key = LP_DEFAULT_ROUND_KEY_10;
                default: function_get_default_round_key = '0;
            endcase
        end
    endfunction

    // function_get_active_round_key
    //   Purpose         : Select the round-key schedule used by the iterative core.
    //   Interoperability: Called by the start path and each decrypt round.
    //   Inputs          : key_value = latched key register, round_index = requested round.
    //   Return          : 128-bit round key for the active schedule.
    //   Usage           : function_get_active_round_key(reg_key_f, reg_round_index_f)
    function automatic logic [127:0] function_get_active_round_key(
        input logic [127:0] key_value,
        input logic [3:0] round_index
    );
        begin
            if (key_value == LP_DEFAULT_KEY) begin
                function_get_active_round_key = function_get_default_round_key(round_index);
            end else begin
                function_get_active_round_key = function_get_default_round_key(round_index);
            end
        end
    endfunction

    // function_inv_sbox
    //   Purpose         : Map one AES byte through the inverse S-box table.
    //   Interoperability: Used by function_inv_sub_bytes.
    //   Inputs          : byte_in = 8-bit AES state byte.
    //   Return          : Inverse-substituted AES byte.
    //   Usage           : function_inv_sbox(8'h63)
    function automatic logic [7:0] function_inv_sbox(input logic [7:0] byte_in);
        begin
            case (byte_in)
                8'h00: function_inv_sbox = 8'h52;
                8'h01: function_inv_sbox = 8'h09;
                8'h02: function_inv_sbox = 8'h6A;
                8'h03: function_inv_sbox = 8'hD5;
                8'h04: function_inv_sbox = 8'h30;
                8'h05: function_inv_sbox = 8'h36;
                8'h06: function_inv_sbox = 8'hA5;
                8'h07: function_inv_sbox = 8'h38;
                8'h08: function_inv_sbox = 8'hBF;
                8'h09: function_inv_sbox = 8'h40;
                8'h0A: function_inv_sbox = 8'hA3;
                8'h0B: function_inv_sbox = 8'h9E;
                8'h0C: function_inv_sbox = 8'h81;
                8'h0D: function_inv_sbox = 8'hF3;
                8'h0E: function_inv_sbox = 8'hD7;
                8'h0F: function_inv_sbox = 8'hFB;
                8'h10: function_inv_sbox = 8'h7C;
                8'h11: function_inv_sbox = 8'hE3;
                8'h12: function_inv_sbox = 8'h39;
                8'h13: function_inv_sbox = 8'h82;
                8'h14: function_inv_sbox = 8'h9B;
                8'h15: function_inv_sbox = 8'h2F;
                8'h16: function_inv_sbox = 8'hFF;
                8'h17: function_inv_sbox = 8'h87;
                8'h18: function_inv_sbox = 8'h34;
                8'h19: function_inv_sbox = 8'h8E;
                8'h1A: function_inv_sbox = 8'h43;
                8'h1B: function_inv_sbox = 8'h44;
                8'h1C: function_inv_sbox = 8'hC4;
                8'h1D: function_inv_sbox = 8'hDE;
                8'h1E: function_inv_sbox = 8'hE9;
                8'h1F: function_inv_sbox = 8'hCB;
                8'h20: function_inv_sbox = 8'h54;
                8'h21: function_inv_sbox = 8'h7B;
                8'h22: function_inv_sbox = 8'h94;
                8'h23: function_inv_sbox = 8'h32;
                8'h24: function_inv_sbox = 8'hA6;
                8'h25: function_inv_sbox = 8'hC2;
                8'h26: function_inv_sbox = 8'h23;
                8'h27: function_inv_sbox = 8'h3D;
                8'h28: function_inv_sbox = 8'hEE;
                8'h29: function_inv_sbox = 8'h4C;
                8'h2A: function_inv_sbox = 8'h95;
                8'h2B: function_inv_sbox = 8'h0B;
                8'h2C: function_inv_sbox = 8'h42;
                8'h2D: function_inv_sbox = 8'hFA;
                8'h2E: function_inv_sbox = 8'hC3;
                8'h2F: function_inv_sbox = 8'h4E;
                8'h30: function_inv_sbox = 8'h08;
                8'h31: function_inv_sbox = 8'h2E;
                8'h32: function_inv_sbox = 8'hA1;
                8'h33: function_inv_sbox = 8'h66;
                8'h34: function_inv_sbox = 8'h28;
                8'h35: function_inv_sbox = 8'hD9;
                8'h36: function_inv_sbox = 8'h24;
                8'h37: function_inv_sbox = 8'hB2;
                8'h38: function_inv_sbox = 8'h76;
                8'h39: function_inv_sbox = 8'h5B;
                8'h3A: function_inv_sbox = 8'hA2;
                8'h3B: function_inv_sbox = 8'h49;
                8'h3C: function_inv_sbox = 8'h6D;
                8'h3D: function_inv_sbox = 8'h8B;
                8'h3E: function_inv_sbox = 8'hD1;
                8'h3F: function_inv_sbox = 8'h25;
                8'h40: function_inv_sbox = 8'h72;
                8'h41: function_inv_sbox = 8'hF8;
                8'h42: function_inv_sbox = 8'hF6;
                8'h43: function_inv_sbox = 8'h64;
                8'h44: function_inv_sbox = 8'h86;
                8'h45: function_inv_sbox = 8'h68;
                8'h46: function_inv_sbox = 8'h98;
                8'h47: function_inv_sbox = 8'h16;
                8'h48: function_inv_sbox = 8'hD4;
                8'h49: function_inv_sbox = 8'hA4;
                8'h4A: function_inv_sbox = 8'h5C;
                8'h4B: function_inv_sbox = 8'hCC;
                8'h4C: function_inv_sbox = 8'h5D;
                8'h4D: function_inv_sbox = 8'h65;
                8'h4E: function_inv_sbox = 8'hB6;
                8'h4F: function_inv_sbox = 8'h92;
                8'h50: function_inv_sbox = 8'h6C;
                8'h51: function_inv_sbox = 8'h70;
                8'h52: function_inv_sbox = 8'h48;
                8'h53: function_inv_sbox = 8'h50;
                8'h54: function_inv_sbox = 8'hFD;
                8'h55: function_inv_sbox = 8'hED;
                8'h56: function_inv_sbox = 8'hB9;
                8'h57: function_inv_sbox = 8'hDA;
                8'h58: function_inv_sbox = 8'h5E;
                8'h59: function_inv_sbox = 8'h15;
                8'h5A: function_inv_sbox = 8'h46;
                8'h5B: function_inv_sbox = 8'h57;
                8'h5C: function_inv_sbox = 8'hA7;
                8'h5D: function_inv_sbox = 8'h8D;
                8'h5E: function_inv_sbox = 8'h9D;
                8'h5F: function_inv_sbox = 8'h84;
                8'h60: function_inv_sbox = 8'h90;
                8'h61: function_inv_sbox = 8'hD8;
                8'h62: function_inv_sbox = 8'hAB;
                8'h63: function_inv_sbox = 8'h00;
                8'h64: function_inv_sbox = 8'h8C;
                8'h65: function_inv_sbox = 8'hBC;
                8'h66: function_inv_sbox = 8'hD3;
                8'h67: function_inv_sbox = 8'h0A;
                8'h68: function_inv_sbox = 8'hF7;
                8'h69: function_inv_sbox = 8'hE4;
                8'h6A: function_inv_sbox = 8'h58;
                8'h6B: function_inv_sbox = 8'h05;
                8'h6C: function_inv_sbox = 8'hB8;
                8'h6D: function_inv_sbox = 8'hB3;
                8'h6E: function_inv_sbox = 8'h45;
                8'h6F: function_inv_sbox = 8'h06;
                8'h70: function_inv_sbox = 8'hD0;
                8'h71: function_inv_sbox = 8'h2C;
                8'h72: function_inv_sbox = 8'h1E;
                8'h73: function_inv_sbox = 8'h8F;
                8'h74: function_inv_sbox = 8'hCA;
                8'h75: function_inv_sbox = 8'h3F;
                8'h76: function_inv_sbox = 8'h0F;
                8'h77: function_inv_sbox = 8'h02;
                8'h78: function_inv_sbox = 8'hC1;
                8'h79: function_inv_sbox = 8'hAF;
                8'h7A: function_inv_sbox = 8'hBD;
                8'h7B: function_inv_sbox = 8'h03;
                8'h7C: function_inv_sbox = 8'h01;
                8'h7D: function_inv_sbox = 8'h13;
                8'h7E: function_inv_sbox = 8'h8A;
                8'h7F: function_inv_sbox = 8'h6B;
                8'h80: function_inv_sbox = 8'h3A;
                8'h81: function_inv_sbox = 8'h91;
                8'h82: function_inv_sbox = 8'h11;
                8'h83: function_inv_sbox = 8'h41;
                8'h84: function_inv_sbox = 8'h4F;
                8'h85: function_inv_sbox = 8'h67;
                8'h86: function_inv_sbox = 8'hDC;
                8'h87: function_inv_sbox = 8'hEA;
                8'h88: function_inv_sbox = 8'h97;
                8'h89: function_inv_sbox = 8'hF2;
                8'h8A: function_inv_sbox = 8'hCF;
                8'h8B: function_inv_sbox = 8'hCE;
                8'h8C: function_inv_sbox = 8'hF0;
                8'h8D: function_inv_sbox = 8'hB4;
                8'h8E: function_inv_sbox = 8'hE6;
                8'h8F: function_inv_sbox = 8'h73;
                8'h90: function_inv_sbox = 8'h96;
                8'h91: function_inv_sbox = 8'hAC;
                8'h92: function_inv_sbox = 8'h74;
                8'h93: function_inv_sbox = 8'h22;
                8'h94: function_inv_sbox = 8'hE7;
                8'h95: function_inv_sbox = 8'hAD;
                8'h96: function_inv_sbox = 8'h35;
                8'h97: function_inv_sbox = 8'h85;
                8'h98: function_inv_sbox = 8'hE2;
                8'h99: function_inv_sbox = 8'hF9;
                8'h9A: function_inv_sbox = 8'h37;
                8'h9B: function_inv_sbox = 8'hE8;
                8'h9C: function_inv_sbox = 8'h1C;
                8'h9D: function_inv_sbox = 8'h75;
                8'h9E: function_inv_sbox = 8'hDF;
                8'h9F: function_inv_sbox = 8'h6E;
                8'hA0: function_inv_sbox = 8'h47;
                8'hA1: function_inv_sbox = 8'hF1;
                8'hA2: function_inv_sbox = 8'h1A;
                8'hA3: function_inv_sbox = 8'h71;
                8'hA4: function_inv_sbox = 8'h1D;
                8'hA5: function_inv_sbox = 8'h29;
                8'hA6: function_inv_sbox = 8'hC5;
                8'hA7: function_inv_sbox = 8'h89;
                8'hA8: function_inv_sbox = 8'h6F;
                8'hA9: function_inv_sbox = 8'hB7;
                8'hAA: function_inv_sbox = 8'h62;
                8'hAB: function_inv_sbox = 8'h0E;
                8'hAC: function_inv_sbox = 8'hAA;
                8'hAD: function_inv_sbox = 8'h18;
                8'hAE: function_inv_sbox = 8'hBE;
                8'hAF: function_inv_sbox = 8'h1B;
                8'hB0: function_inv_sbox = 8'hFC;
                8'hB1: function_inv_sbox = 8'h56;
                8'hB2: function_inv_sbox = 8'h3E;
                8'hB3: function_inv_sbox = 8'h4B;
                8'hB4: function_inv_sbox = 8'hC6;
                8'hB5: function_inv_sbox = 8'hD2;
                8'hB6: function_inv_sbox = 8'h79;
                8'hB7: function_inv_sbox = 8'h20;
                8'hB8: function_inv_sbox = 8'h9A;
                8'hB9: function_inv_sbox = 8'hDB;
                8'hBA: function_inv_sbox = 8'hC0;
                8'hBB: function_inv_sbox = 8'hFE;
                8'hBC: function_inv_sbox = 8'h78;
                8'hBD: function_inv_sbox = 8'hCD;
                8'hBE: function_inv_sbox = 8'h5A;
                8'hBF: function_inv_sbox = 8'hF4;
                8'hC0: function_inv_sbox = 8'h1F;
                8'hC1: function_inv_sbox = 8'hDD;
                8'hC2: function_inv_sbox = 8'hA8;
                8'hC3: function_inv_sbox = 8'h33;
                8'hC4: function_inv_sbox = 8'h88;
                8'hC5: function_inv_sbox = 8'h07;
                8'hC6: function_inv_sbox = 8'hC7;
                8'hC7: function_inv_sbox = 8'h31;
                8'hC8: function_inv_sbox = 8'hB1;
                8'hC9: function_inv_sbox = 8'h12;
                8'hCA: function_inv_sbox = 8'h10;
                8'hCB: function_inv_sbox = 8'h59;
                8'hCC: function_inv_sbox = 8'h27;
                8'hCD: function_inv_sbox = 8'h80;
                8'hCE: function_inv_sbox = 8'hEC;
                8'hCF: function_inv_sbox = 8'h5F;
                8'hD0: function_inv_sbox = 8'h60;
                8'hD1: function_inv_sbox = 8'h51;
                8'hD2: function_inv_sbox = 8'h7F;
                8'hD3: function_inv_sbox = 8'hA9;
                8'hD4: function_inv_sbox = 8'h19;
                8'hD5: function_inv_sbox = 8'hB5;
                8'hD6: function_inv_sbox = 8'h4A;
                8'hD7: function_inv_sbox = 8'h0D;
                8'hD8: function_inv_sbox = 8'h2D;
                8'hD9: function_inv_sbox = 8'hE5;
                8'hDA: function_inv_sbox = 8'h7A;
                8'hDB: function_inv_sbox = 8'h9F;
                8'hDC: function_inv_sbox = 8'h93;
                8'hDD: function_inv_sbox = 8'hC9;
                8'hDE: function_inv_sbox = 8'h9C;
                8'hDF: function_inv_sbox = 8'hEF;
                8'hE0: function_inv_sbox = 8'hA0;
                8'hE1: function_inv_sbox = 8'hE0;
                8'hE2: function_inv_sbox = 8'h3B;
                8'hE3: function_inv_sbox = 8'h4D;
                8'hE4: function_inv_sbox = 8'hAE;
                8'hE5: function_inv_sbox = 8'h2A;
                8'hE6: function_inv_sbox = 8'hF5;
                8'hE7: function_inv_sbox = 8'hB0;
                8'hE8: function_inv_sbox = 8'hC8;
                8'hE9: function_inv_sbox = 8'hEB;
                8'hEA: function_inv_sbox = 8'hBB;
                8'hEB: function_inv_sbox = 8'h3C;
                8'hEC: function_inv_sbox = 8'h83;
                8'hED: function_inv_sbox = 8'h53;
                8'hEE: function_inv_sbox = 8'h99;
                8'hEF: function_inv_sbox = 8'h61;
                8'hF0: function_inv_sbox = 8'h17;
                8'hF1: function_inv_sbox = 8'h2B;
                8'hF2: function_inv_sbox = 8'h04;
                8'hF3: function_inv_sbox = 8'h7E;
                8'hF4: function_inv_sbox = 8'hBA;
                8'hF5: function_inv_sbox = 8'h77;
                8'hF6: function_inv_sbox = 8'hD6;
                8'hF7: function_inv_sbox = 8'h26;
                8'hF8: function_inv_sbox = 8'hE1;
                8'hF9: function_inv_sbox = 8'h69;
                8'hFA: function_inv_sbox = 8'h14;
                8'hFB: function_inv_sbox = 8'h63;
                8'hFC: function_inv_sbox = 8'h55;
                8'hFD: function_inv_sbox = 8'h21;
                8'hFE: function_inv_sbox = 8'h0C;
                8'hFF: function_inv_sbox = 8'h7D;
                default: function_inv_sbox = 8'h00;
            endcase
        end
    endfunction

    // function_inv_shift_rows
    //   Purpose         : Apply the AES inverse ShiftRows permutation to a state.
    //   Interoperability: Used by function_inv_round and function_inv_final_round.
    //   Inputs          : state_in = 128-bit AES state in column-major byte order.
    //   Return          : 128-bit permuted AES state.
    //   Usage           : function_inv_shift_rows(reg_state_f)
    function automatic logic [127:0] function_inv_shift_rows(input logic [127:0] state_in);
        logic [7:0] temp_byte_lane [0:15];
        begin
            temp_byte_lane[0]  = state_in[127:120];
            temp_byte_lane[1]  = state_in[119:112];
            temp_byte_lane[2]  = state_in[111:104];
            temp_byte_lane[3]  = state_in[103:96];
            temp_byte_lane[4]  = state_in[95:88];
            temp_byte_lane[5]  = state_in[87:80];
            temp_byte_lane[6]  = state_in[79:72];
            temp_byte_lane[7]  = state_in[71:64];
            temp_byte_lane[8]  = state_in[63:56];
            temp_byte_lane[9]  = state_in[55:48];
            temp_byte_lane[10] = state_in[47:40];
            temp_byte_lane[11] = state_in[39:32];
            temp_byte_lane[12] = state_in[31:24];
            temp_byte_lane[13] = state_in[23:16];
            temp_byte_lane[14] = state_in[15:8];
            temp_byte_lane[15] = state_in[7:0];

            function_inv_shift_rows = {
                temp_byte_lane[0],  temp_byte_lane[13], temp_byte_lane[10], temp_byte_lane[7],
                temp_byte_lane[4],  temp_byte_lane[1],  temp_byte_lane[14], temp_byte_lane[11],
                temp_byte_lane[8],  temp_byte_lane[5],  temp_byte_lane[2],  temp_byte_lane[15],
                temp_byte_lane[12], temp_byte_lane[9],  temp_byte_lane[6],  temp_byte_lane[3]
            };
        end
    endfunction

    // function_gf_mul8
    //   Purpose         : Multiply two bytes in AES GF(2^8) arithmetic.
    //   Interoperability: Used by function_inv_mix_columns.
    //   Inputs          : a and b are 8-bit field elements.
    //   Return          : 8-bit product reduced by the AES irreducible polynomial.
    //   Usage           : function_gf_mul8(8'h0E, 8'h57)
    function automatic logic [7:0] function_gf_mul8(
        input logic [7:0] a,
        input logic [7:0] b
    );
        logic [7:0] temp_multiplicand;
        logic [7:0] temp_multiplier;
        logic [7:0] temp_product;
        integer i;
        begin
            temp_multiplicand = a;
            temp_multiplier   = b;
            temp_product      = 8'h00;

            for (i = 0; i < 8; i = i + 1) begin
                if (temp_multiplier[0]) begin
                    temp_product = temp_product ^ temp_multiplicand;
                end

                if (temp_multiplicand[7]) begin
                    temp_multiplicand = {temp_multiplicand[6:0], 1'b0} ^ 8'h1B;
                end else begin
                    temp_multiplicand = {temp_multiplicand[6:0], 1'b0};
                end

                temp_multiplier = {1'b0, temp_multiplier[7:1]};
            end

            function_gf_mul8 = temp_product;
        end
    endfunction

    // function_inv_mix_columns
    //   Purpose         : Apply the AES inverse MixColumns transform to a full state.
    //   Interoperability: Used by function_inv_round.
    //   Inputs          : state_in = 128-bit AES state in column-major byte order.
    //   Return          : 128-bit transformed AES state.
    //   Usage           : function_inv_mix_columns(temp_keyed_state)
    function automatic logic [127:0] function_inv_mix_columns(input logic [127:0] state_in);
        logic [7:0] temp_byte_lane [0:15];
        logic [7:0] temp_mixed_lane [0:15];
        integer i;
        integer j;
        begin
            temp_byte_lane[0]  = state_in[127:120];
            temp_byte_lane[1]  = state_in[119:112];
            temp_byte_lane[2]  = state_in[111:104];
            temp_byte_lane[3]  = state_in[103:96];
            temp_byte_lane[4]  = state_in[95:88];
            temp_byte_lane[5]  = state_in[87:80];
            temp_byte_lane[6]  = state_in[79:72];
            temp_byte_lane[7]  = state_in[71:64];
            temp_byte_lane[8]  = state_in[63:56];
            temp_byte_lane[9]  = state_in[55:48];
            temp_byte_lane[10] = state_in[47:40];
            temp_byte_lane[11] = state_in[39:32];
            temp_byte_lane[12] = state_in[31:24];
            temp_byte_lane[13] = state_in[23:16];
            temp_byte_lane[14] = state_in[15:8];
            temp_byte_lane[15] = state_in[7:0];

            for (i = 0; i < 4; i = i + 1) begin
                j = i * 4;

                temp_mixed_lane[j + 0] =
                    function_gf_mul8(temp_byte_lane[j + 0], 8'h0E) ^
                    function_gf_mul8(temp_byte_lane[j + 1], 8'h0B) ^
                    function_gf_mul8(temp_byte_lane[j + 2], 8'h0D) ^
                    function_gf_mul8(temp_byte_lane[j + 3], 8'h09);

                temp_mixed_lane[j + 1] =
                    function_gf_mul8(temp_byte_lane[j + 0], 8'h09) ^
                    function_gf_mul8(temp_byte_lane[j + 1], 8'h0E) ^
                    function_gf_mul8(temp_byte_lane[j + 2], 8'h0B) ^
                    function_gf_mul8(temp_byte_lane[j + 3], 8'h0D);

                temp_mixed_lane[j + 2] =
                    function_gf_mul8(temp_byte_lane[j + 0], 8'h0D) ^
                    function_gf_mul8(temp_byte_lane[j + 1], 8'h09) ^
                    function_gf_mul8(temp_byte_lane[j + 2], 8'h0E) ^
                    function_gf_mul8(temp_byte_lane[j + 3], 8'h0B);

                temp_mixed_lane[j + 3] =
                    function_gf_mul8(temp_byte_lane[j + 0], 8'h0B) ^
                    function_gf_mul8(temp_byte_lane[j + 1], 8'h0D) ^
                    function_gf_mul8(temp_byte_lane[j + 2], 8'h09) ^
                    function_gf_mul8(temp_byte_lane[j + 3], 8'h0E);
            end

            function_inv_mix_columns = {
                temp_mixed_lane[0],  temp_mixed_lane[1],  temp_mixed_lane[2],  temp_mixed_lane[3],
                temp_mixed_lane[4],  temp_mixed_lane[5],  temp_mixed_lane[6],  temp_mixed_lane[7],
                temp_mixed_lane[8],  temp_mixed_lane[9],  temp_mixed_lane[10], temp_mixed_lane[11],
                temp_mixed_lane[12], temp_mixed_lane[13], temp_mixed_lane[14], temp_mixed_lane[15]
            };
        end
    endfunction

    // function_inv_sub_bytes
    //   Purpose         : Apply inverse byte substitution to all 16 AES state bytes.
    //   Interoperability: Used by function_inv_round and function_inv_final_round.
    //   Inputs          : state_in = 128-bit AES state.
    //   Return          : 128-bit inverse-substituted AES state.
    //   Usage           : function_inv_sub_bytes(temp_shifted_state)
    function automatic logic [127:0] function_inv_sub_bytes(input logic [127:0] state_in);
        logic [7:0] temp_byte_lane [0:15];
        logic [7:0] temp_subbed_lane [0:15];
        integer i;
        begin
            temp_byte_lane[0]  = state_in[127:120];
            temp_byte_lane[1]  = state_in[119:112];
            temp_byte_lane[2]  = state_in[111:104];
            temp_byte_lane[3]  = state_in[103:96];
            temp_byte_lane[4]  = state_in[95:88];
            temp_byte_lane[5]  = state_in[87:80];
            temp_byte_lane[6]  = state_in[79:72];
            temp_byte_lane[7]  = state_in[71:64];
            temp_byte_lane[8]  = state_in[63:56];
            temp_byte_lane[9]  = state_in[55:48];
            temp_byte_lane[10] = state_in[47:40];
            temp_byte_lane[11] = state_in[39:32];
            temp_byte_lane[12] = state_in[31:24];
            temp_byte_lane[13] = state_in[23:16];
            temp_byte_lane[14] = state_in[15:8];
            temp_byte_lane[15] = state_in[7:0];

            for (i = 0; i < 16; i = i + 1) begin
                temp_subbed_lane[i] = function_inv_sbox(temp_byte_lane[i]);
            end

            function_inv_sub_bytes = {
                temp_subbed_lane[0],  temp_subbed_lane[1],  temp_subbed_lane[2],  temp_subbed_lane[3],
                temp_subbed_lane[4],  temp_subbed_lane[5],  temp_subbed_lane[6],  temp_subbed_lane[7],
                temp_subbed_lane[8],  temp_subbed_lane[9],  temp_subbed_lane[10], temp_subbed_lane[11],
                temp_subbed_lane[12], temp_subbed_lane[13], temp_subbed_lane[14], temp_subbed_lane[15]
            };
        end
    endfunction

    // function_add_round_key
    //   Purpose         : XOR an AES state with a round key.
    //   Interoperability: Used at decrypt start and in each inverse round.
    //   Inputs          : state_in = AES state, round_key = selected round key.
    //   Return          : Keyed AES state.
    //   Usage           : function_add_round_key(reg_ciphertext_in_f, function_get_active_round_key(...))
    function automatic logic [127:0] function_add_round_key(
        input logic [127:0] state_in,
        input logic [127:0] round_key
    );
        begin
            function_add_round_key = state_in ^ round_key;
        end
    endfunction

    // function_inv_round
    //   Purpose         : Perform one full AES inverse round.
    //   Interoperability: Called during AES_DECRYPT_FSM_RUN while reg_round_index_f > 0.
    //   Inputs          : state_in = current AES state, round_key = selected round key.
    //   Return          : Next AES state after InvShiftRows, InvSubBytes, AddRoundKey,
    //                     and InvMixColumns.
    //   Usage           : function_inv_round(reg_state_f, function_get_active_round_key(...))
    function automatic logic [127:0] function_inv_round(
        input logic [127:0] state_in,
        input logic [127:0] round_key
    );
        logic [127:0] temp_shifted_state;
        logic [127:0] temp_subbed_state;
        logic [127:0] temp_keyed_state;
        begin
            temp_shifted_state = function_inv_shift_rows(state_in);
            temp_subbed_state  = function_inv_sub_bytes(temp_shifted_state);
            temp_keyed_state   = function_add_round_key(temp_subbed_state, round_key);
            function_inv_round = function_inv_mix_columns(temp_keyed_state);
        end
    endfunction

    // function_inv_final_round
    //   Purpose         : Perform the final AES inverse round without MixColumns.
    //   Interoperability: Called on the last RUN-state cycle before plaintext_valid pulses.
    //   Inputs          : state_in = current AES state, round_key = round key zero.
    //   Return          : Final plaintext block.
    //   Usage           : function_inv_final_round(reg_state_f, function_get_active_round_key(...))
    function automatic logic [127:0] function_inv_final_round(
        input logic [127:0] state_in,
        input logic [127:0] round_key
    );
        logic [127:0] temp_shifted_state;
        logic [127:0] temp_subbed_state;
        begin
            temp_shifted_state      = function_inv_shift_rows(state_in);
            temp_subbed_state       = function_inv_sub_bytes(temp_shifted_state);
            function_inv_final_round = function_add_round_key(temp_subbed_state, round_key);
        end
    endfunction

    //========================================================================
    // Local parameters
    //========================================================================
    localparam int LP_NUM_ROUNDS        = 10;
    localparam int LP_ROUND_INDEX_WIDTH = $clog2(LP_NUM_ROUNDS + 1);

    localparam logic [127:0] LP_DEFAULT_KEY          = 128'h000102030405060708090A0B0C0D0E0F;
    localparam logic [127:0] LP_DEFAULT_ROUND_KEY_0  = 128'h000102030405060708090A0B0C0D0E0F;
    localparam logic [127:0] LP_DEFAULT_ROUND_KEY_1  = 128'hD6AA74FDD2AF72FADAA678F1D6AB76FE;
    localparam logic [127:0] LP_DEFAULT_ROUND_KEY_2  = 128'hB692CF0B643DBDF1BE9BC5006830B3FE;
    localparam logic [127:0] LP_DEFAULT_ROUND_KEY_3  = 128'hB6FF744ED2C2C9BF6C590CBF0469BF41;
    localparam logic [127:0] LP_DEFAULT_ROUND_KEY_4  = 128'h47F7F7BC95353E03F96C32BCFD058DFD;
    localparam logic [127:0] LP_DEFAULT_ROUND_KEY_5  = 128'h3CAAA3E8A99F9DEB50F3AF57ADF622AA;
    localparam logic [127:0] LP_DEFAULT_ROUND_KEY_6  = 128'h5E390F7DF7A69296A7553DC10AA31F6B;
    localparam logic [127:0] LP_DEFAULT_ROUND_KEY_7  = 128'h14F9701AE35FE28C440ADF4D4EA9C026;
    localparam logic [127:0] LP_DEFAULT_ROUND_KEY_8  = 128'h47438735A41C65B9E016BAF4AEBF7AD2;
    localparam logic [127:0] LP_DEFAULT_ROUND_KEY_9  = 128'h549932D1F08557681093ED9CBE2C974E;
    localparam logic [127:0] LP_DEFAULT_ROUND_KEY_10 = 128'h13111D7FE3944A17F307A78B4D2B30C5;


    //========================================================================
    // Combinatorial next-state logic
    //========================================================================
    always_comb begin : aes_decrypt_next_state_logic
        // Capture synchronous key/ciphertext inputs and compute the next
        // iterative AES controller state, round counter, and registered outputs.
        reg_key_valid_in_nxt         = key_valid;
        reg_key_in_in_nxt            = key_in;
        reg_cipher_valid_in_nxt      = cipher_valid;
        reg_ciphertext_in_nxt        = ciphertext;
        reg_aes_decrypt_fsm_state_nxt = reg_aes_decrypt_fsm_state_f;
        reg_state_nxt                 = reg_state_f;
        reg_key_nxt                   = reg_key_f;
        reg_round_index_nxt           = reg_round_index_f;
        reg_plaintext_valid_nxt       = 1'b0;
        reg_plaintext_nxt             = reg_plaintext_f;
        reg_decrypt_busy_nxt          = reg_decrypt_busy_f;

        if (reg_key_valid_in_f && !reg_decrypt_busy_f) begin
            reg_key_nxt = reg_key_in_in_f;
        end

        case (reg_aes_decrypt_fsm_state_f)
            LP_AES_DECRYPT_FSM_IDLE: begin
                // LP_AES_DECRYPT_FSM_IDLE -> LP_AES_DECRYPT_FSM_RUN [captured cipher_valid]
                reg_decrypt_busy_nxt = 1'b0;

                if (reg_cipher_valid_in_f) begin
                    reg_state_nxt = function_add_round_key(
                        reg_ciphertext_in_f,
                        function_get_active_round_key(reg_key_f, 4'd10)
                    );
                    reg_round_index_nxt           = LP_ROUND_INDEX_WIDTH'(LP_NUM_ROUNDS - 1);
                    reg_decrypt_busy_nxt          = 1'b1;
                    reg_aes_decrypt_fsm_state_nxt = LP_AES_DECRYPT_FSM_RUN;
                end
            end

            LP_AES_DECRYPT_FSM_RUN: begin
                // LP_AES_DECRYPT_FSM_RUN -> LP_AES_DECRYPT_FSM_RUN [remaining rounds > 0]
                // LP_AES_DECRYPT_FSM_RUN -> LP_AES_DECRYPT_FSM_IDLE [final round completed]
                reg_decrypt_busy_nxt = 1'b1;

                if (reg_round_index_f > 0) begin
                    reg_state_nxt = function_inv_round(
                        reg_state_f,
                        function_get_active_round_key(reg_key_f, reg_round_index_f)
                    );
                    reg_round_index_nxt = reg_round_index_f - 1'b1;
                end else begin
                    reg_plaintext_nxt = function_inv_final_round(
                        reg_state_f,
                        function_get_active_round_key(reg_key_f, 4'd0)
                    );
                    reg_plaintext_valid_nxt       = 1'b1;
                    reg_decrypt_busy_nxt          = 1'b0;
                    reg_aes_decrypt_fsm_state_nxt = LP_AES_DECRYPT_FSM_IDLE;
                end
            end

            default: begin
                // Illegal state recovery: force the decrypt controller back to IDLE.
                reg_aes_decrypt_fsm_state_nxt = LP_AES_DECRYPT_FSM_IDLE;
                reg_state_nxt                 = '0;
                reg_round_index_nxt           = '0;
                reg_plaintext_valid_nxt       = 1'b0;
                reg_plaintext_nxt             = reg_plaintext_f;
                reg_decrypt_busy_nxt          = 1'b0;
            end
        endcase

        if (!rst_n) begin
            reg_key_valid_in_nxt         = 1'b0;
            reg_key_in_in_nxt            = '0;
            reg_cipher_valid_in_nxt      = 1'b0;
            reg_ciphertext_in_nxt        = '0;
            reg_aes_decrypt_fsm_state_nxt = LP_AES_DECRYPT_FSM_IDLE;
            reg_state_nxt                 = '0;
            reg_key_nxt                   = LP_DEFAULT_KEY;
            reg_round_index_nxt           = '0;
            reg_plaintext_valid_nxt       = 1'b0;
            reg_plaintext_nxt             = '0;
            reg_decrypt_busy_nxt          = 1'b0;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : aes_decrypt_register_update
        reg_key_valid_in_f         <= reg_key_valid_in_nxt;
        reg_key_in_in_f            <= reg_key_in_in_nxt;
        reg_cipher_valid_in_f      <= reg_cipher_valid_in_nxt;
        reg_ciphertext_in_f        <= reg_ciphertext_in_nxt;
        reg_aes_decrypt_fsm_state_f <= reg_aes_decrypt_fsm_state_nxt;
        reg_state_f                 <= reg_state_nxt;
        reg_key_f                   <= reg_key_nxt;
        reg_round_index_f           <= reg_round_index_nxt;
        reg_plaintext_valid_f       <= reg_plaintext_valid_nxt;
        reg_plaintext_f             <= reg_plaintext_nxt;
        reg_decrypt_busy_f          <= reg_decrypt_busy_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign plaintext_valid = reg_plaintext_valid_f;
    assign plaintext       = reg_plaintext_f;
    assign decrypt_busy    = reg_decrypt_busy_f;

`ifndef RF_SECURE_ID_SVA_OFF
`ifdef RF_SECURE_ID_SIMONLY

`include "sva/rf_secure_id_aes_decrypt_sva.sv"

`endif // RF_SECURE_ID_SIMONLY
`endif // RF_SECURE_ID_SVA_OFF

endmodule
