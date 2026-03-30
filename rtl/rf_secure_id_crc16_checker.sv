//=====================================================================================================
// Module: rf_secure_id_crc16_checker
// Function: Compute and compare CRC16 for packet_type || ciphertext.
//
// Parameters:
//   None.
//
// Local Parameters:
//   LP_CRC_DATA_WIDTH = 136 bits for packet_type || ciphertext CRC coverage.
//   LP_CRC_POLY       = 16'h1021 CRC16 generator polynomial.
//
// Ports:
//   core_clk    : Primary digital clock.
//   rst_n       : Active-low reset sampled in the module clock domain.
//   parsed_valid: One-cycle pulse indicating parser outputs are valid.
//   packet_type : Packet type field included in the CRC calculation.
//   ciphertext  : 128-bit ciphertext field included in the CRC calculation.
//   crc_rx      : Received CRC16 field from the packet.
//   crc_valid   : One-cycle pulse indicating CRC outputs are valid.
//   crc_ok      : High when computed CRC matches crc_rx.
//   crc_calc    : Registered computed CRC value.
//
// Functions:
//   function_calc_crc16 : MSB-first CRC16 engine for packet_type || ciphertext.
//
// State Variables:
//   reg_parsed_valid_in_f[0:0] : One-stage capture register for parsed_valid. Reset default = 1'b0.
//   reg_packet_type_in_f[7:0]  : One-stage capture register for packet_type. Reset default = '0.
//   reg_ciphertext_in_f[127:0] : One-stage capture register for ciphertext. Reset default = '0.
//   reg_crc_rx_in_f[15:0]      : One-stage capture register for crc_rx. Reset default = '0.
//   reg_crc_valid_f[0:0]       : Registered CRC-valid pulse. Reset default = 1'b0.
//   reg_crc_ok_f[0:0]          : Registered CRC comparison result. Reset default = 1'b0.
//   reg_crc_calc_f[15:0]       : Registered computed CRC value. Reset default = '0.
//
// Sub-modules:
//   None.
//
// Clock / Reset:
//   core_clk : Single synchronous clock domain. Target integration frequency is 50 MHz.
//   rst_n    : Active-low reset applied through next-state reset logic.
//
// Timing:
//   Throughput : One CRC result per captured parser event.
//   Latency    : One cycle from captured parser inputs to registered CRC outputs.
//
// Synthesis Guidance:
//   Clock Source       : Primary 50 MHz system clock with nominal 50% duty cycle.
//   Constraints        : No internal false-path or multicycle exceptions are expected.
//   Interface Budget   : Inputs are captured at the boundary and CRC outputs are registered.
//   Resource Expectation: Register-only datapath plus combinational XOR/shift CRC network.
//                         No RAM, ROM, or DSP resources are used.
//   Signoff Follow-up  : Gate-level simulation and RTL-to-netlist equivalence remain required
//                        final signoff activities outside this educational repo.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock core_clk <integration_defined> [get_ports {parsed_valid packet_type[*] ciphertext[*] crc_rx[*]}]
//   set_output_delay -clock core_clk <integration_defined> [get_ports {crc_valid crc_ok crc_calc[*]}]
//   No false-path or multicycle exceptions are expected for this module.
//
// LIMITATION:
//   The checker validates transmission integrity only; packets with valid CRC
//   can still be rejected by later decrypt and plaintext-validation stages.
//=====================================================================================================
module rf_secure_id_crc16_checker (
    input  logic         core_clk,
    input  logic         rst_n,
    input  logic         parsed_valid,
    input  logic [7:0]   packet_type,
    input  logic [127:0] ciphertext,
    input  logic [15:0]  crc_rx,
    output logic         crc_valid,
    output logic         crc_ok,
    output logic [15:0]  crc_calc
);

    //========================================================================
    // Input capture, internal logic, and output staging registers
    //========================================================================
    logic reg_parsed_valid_in_f;
    logic reg_parsed_valid_in_nxt;
    logic [7:0] reg_packet_type_in_f;
    logic [7:0] reg_packet_type_in_nxt;
    logic [127:0] reg_ciphertext_in_f;
    logic [127:0] reg_ciphertext_in_nxt;
    logic [15:0] reg_crc_rx_in_f;
    logic [15:0] reg_crc_rx_in_nxt;

    logic [15:0] calc_crc_comb;
    logic reg_crc_valid_f;
    logic reg_crc_valid_nxt;
    logic reg_crc_ok_f;
    logic reg_crc_ok_nxt;
    logic [15:0] reg_crc_calc_f;
    logic [15:0] reg_crc_calc_nxt;

    //========================================================================
    // Function definitions
    //========================================================================
    // function_calc_crc16
    //   Purpose         : Calculate the packet CRC over packet_type || ciphertext.
    //   Interoperability: Consumed by crc16_checker_next_state_logic when a
    //                     captured parser event is present.
    //   Inputs          : data_in[135:0] in MSB-first transmission order.
    //   Return          : Computed CRC16 value using polynomial 16'h1021.
    //   Usage           : function_calc_crc16({reg_packet_type_in_f, reg_ciphertext_in_f})
    function automatic logic [15:0] function_calc_crc16(
        input logic [LP_CRC_DATA_WIDTH-1:0] data_in
    );
        logic [15:0] temp_crc;
        logic temp_feedback;
        integer bit_idx;
        begin
            temp_crc = 16'h0000;

            for (bit_idx = LP_CRC_DATA_WIDTH - 1; bit_idx >= 0; bit_idx = bit_idx - 1) begin
                temp_feedback = temp_crc[15] ^ data_in[bit_idx];
                temp_crc      = {temp_crc[14:0], 1'b0};

                if (temp_feedback) begin
                    temp_crc = temp_crc ^ LP_CRC_POLY;
                end
            end

            function_calc_crc16 = temp_crc;
        end
    endfunction

    //========================================================================
    // Local parameters
    //========================================================================
    localparam int LP_CRC_DATA_WIDTH  = 136;
    localparam logic [15:0] LP_CRC_POLY = 16'h1021;

    //========================================================================
    // Combinatorial next-state logic
    //========================================================================
    always_comb begin : crc16_checker_next_state_logic
        // Capture parser outputs and compute the next registered CRC result
        // that qualifies packets for entry into the decrypt stage.
        reg_parsed_valid_in_nxt = parsed_valid;
        reg_packet_type_in_nxt  = packet_type;
        reg_ciphertext_in_nxt   = ciphertext;
        reg_crc_rx_in_nxt       = crc_rx;

        calc_crc_comb     = function_calc_crc16({reg_packet_type_in_f, reg_ciphertext_in_f});
        reg_crc_valid_nxt = 1'b0;
        reg_crc_ok_nxt    = reg_crc_ok_f;
        reg_crc_calc_nxt  = reg_crc_calc_f;

        if (reg_parsed_valid_in_f) begin
            reg_crc_valid_nxt = 1'b1;
            reg_crc_ok_nxt    = (calc_crc_comb == reg_crc_rx_in_f);
            reg_crc_calc_nxt  = calc_crc_comb;
        end

        if (!rst_n) begin
            reg_parsed_valid_in_nxt = 1'b0;
            reg_packet_type_in_nxt  = '0;
            reg_ciphertext_in_nxt   = '0;
            reg_crc_rx_in_nxt       = '0;
            reg_crc_valid_nxt = 1'b0;
            reg_crc_ok_nxt    = 1'b0;
            reg_crc_calc_nxt  = '0;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : crc16_checker_register_update
        reg_parsed_valid_in_f <= reg_parsed_valid_in_nxt;
        reg_packet_type_in_f  <= reg_packet_type_in_nxt;
        reg_ciphertext_in_f   <= reg_ciphertext_in_nxt;
        reg_crc_rx_in_f       <= reg_crc_rx_in_nxt;
        reg_crc_valid_f <= reg_crc_valid_nxt;
        reg_crc_ok_f    <= reg_crc_ok_nxt;
        reg_crc_calc_f  <= reg_crc_calc_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign crc_valid = reg_crc_valid_f;
    assign crc_ok    = reg_crc_ok_f;
    assign crc_calc  = reg_crc_calc_f;

endmodule
