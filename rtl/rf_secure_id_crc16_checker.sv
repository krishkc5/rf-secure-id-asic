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
//   parse_evt_i : One-cycle pulse indicating parser outputs are valid.
//   type_lane_i : Packet type field included in the CRC calculation.
//   cipher_lane_i : 128-bit ciphertext field included in the CRC calculation.
//   rx_crc_i    : Received CRC16 field from the packet.
//   crc_valid_q : One-cycle pulse indicating CRC outputs are valid.
//   crc_ok_q    : High when computed CRC matches rx_crc_i.
//   crc_calc_q  : Registered computed CRC value.
//
// Functions:
//   function_calc_crc16 : MSB-first CRC16 engine for packet_type || ciphertext.
//
// Included Files:
//   None.
//
// State Variables:
//   reg_parse_evt_f[0:0]       : One-stage capture register for parse_evt_i. Reset default = 1'b0.
//   reg_type_lane_f[7:0]       : One-stage capture register for type_lane_i. Reset default = '0.
//   reg_cipher_lane_f[127:0]   : One-stage capture register for cipher_lane_i. Reset default = '0.
//   reg_crc_lane_f[15:0]       : One-stage capture register for rx_crc_i. Reset default = '0.
//   reg_fire_evt_f[0:0]        : Registered CRC-valid pulse. Reset default = 1'b0.
//   reg_match_flag_f[0:0]      : Registered CRC comparison result. Reset default = 1'b0.
//   reg_crc_word_f[15:0]       : Registered computed CRC value. Reset default = '0.
//
// Reset Behavior:
//   Active-low reset clears captured parser fields and registered CRC outputs
//   so the next valid parse event starts a fresh CRC transaction.
//
// Reset Rationale:
//   Input capture registers reset to 0 so stale parser outputs do not seed a CRC transaction.
//   Output registers reset to 0 so no false CRC-valid pulse or stale compare result is observed.
//
// Sub-modules:
//   None.
//
// Clock / Reset:
//   core_clk : Single synchronous clock domain. Target integration frequency is 50 MHz.
//   rst_n    : Active-low reset applied through next-state reset logic.
//
// Timing:
//   TIMING_CRITICAL: The CRC reduction network is one of the top project
//                    critical paths and must preserve MSB-first behavior.
//   STA_CRITICAL   : 136-bit XOR/shift reduction for {type_lane_i,cipher_lane_i}.
//   Throughput : One CRC result per captured parser event.
//   Latency    : One cycle from captured parser inputs to registered CRC outputs.
//
// Synthesis Guidance:
//   Clock Source       : Primary 50 MHz system clock with nominal 50% duty cycle.
//   Constraints        : No internal false-path or multicycle exceptions are expected.
//   Interface Budget   : Inputs are captured at the boundary and CRC outputs are registered.
//   Resource Expectation: Register-only datapath plus combinational XOR/shift CRC network.
//                         No RAM, ROM, or DSP resources are used. Current Yosys
//                         sanity baseline is 415 local cells.
//   Resource Estimate   : ~171 state bits, 415 Yosys sanity cells, 0 RAMs, 0 DSPs,
//                         and ~28.3% of the 1466-cell top-level baseline.
//   Signoff Follow-up  : Gate-level simulation and RTL-to-netlist equivalence remain required
//                        final signoff activities outside this educational repo.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock core_clk <integration_defined>
//                    [get_ports {parse_evt_i type_lane_i[*] cipher_lane_i[*] rx_crc_i[*]}]
//   set_output_delay -clock core_clk <integration_defined> [get_ports {crc_valid_q crc_ok_q crc_calc_q[*]}]
//   No false-path or multicycle exceptions are expected for this module.
//
// Specification Reference:
//   CRC coverage, polynomial, and bit ordering are documented in
//   docs/digital_pipeline_aes.md.
//
// Byte Ordering:
//   The CRC engine consumes {type_lane_i, cipher_lane_i} in MSB-first order.
//
// ASCII Timing Sketch:
//   core_clk   : |0|1|2|
//   parse_evt_i:  1 0 0
//   crc_valid_q:  0 1 0
//   crc_ok_q   :  X valid on crc_valid_q pulse
//
// Algorithm Summary:
//   function_calc_crc16 walks the 136-bit payload MSB-first, applying the
//   16'h1021 generator polynomial with shift/XOR feedback each cycle of the loop.
//
// Assumptions:
//   Upstream parser already extracted packet_type and ciphertext from a
//   correctly framed 160-bit packet.
//
// CRITICAL:
//   The CRC engine is defined for MSB-first traversal and polynomial 16'h1021.
//   Changing either silently breaks packet interoperability.
//
// LIMITATION:
//   The checker validates transmission integrity only; packets with valid CRC
//   can still be rejected by later decrypt and plaintext-validation stages.
//
// Interface Reference:
//   CRC coverage, polynomial, and checker I/O semantics are documented in
//   docs/digital_pipeline_aes.md.
//=====================================================================================================
module rf_secure_id_crc16_checker (
    input  logic         core_clk,
    input  logic         rst_n,
    input  logic         parse_evt_i,
    input  logic [7:0]   type_lane_i,
    input  logic [127:0] cipher_lane_i,
    input  logic [15:0]  rx_crc_i,
    output logic         crc_valid_q,
    output logic         crc_ok_q,
    output logic [15:0]  crc_calc_q
);

    //========================================================================
    // Input capture, internal logic, and output staging registers
    //========================================================================
    logic         reg_parse_evt_f, reg_parse_evt_nxt;
    logic [7:0]   reg_type_lane_f, reg_type_lane_nxt;
    logic [127:0] reg_cipher_lane_f, reg_cipher_lane_nxt;
    logic [15:0]  reg_crc_lane_f, reg_crc_lane_nxt;

    logic [15:0] bus_crc_word;
    logic         reg_fire_evt_f, reg_fire_evt_nxt;
    logic         reg_match_flag_f, reg_match_flag_nxt;
    logic [15:0] reg_crc_word_f, reg_crc_word_nxt;

    //========================================================================
    // Function definitions
    //========================================================================
    // function_calc_crc16
    //   Purpose         : Calculate the packet CRC over packet_type || ciphertext.
    //   Interoperability: Consumed by crc16_checker_next_state_logic when a
    //                     captured parser event is present.
    //   Inputs          : data_in[135:0] in MSB-first transmission order.
    //   Return          : Computed CRC16 value using polynomial 16'h1021.
    //   Usage           : function_calc_crc16({reg_type_lane_f, reg_cipher_lane_f})
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
        reg_parse_evt_nxt   = parse_evt_i;
        reg_type_lane_nxt   = type_lane_i;
        reg_cipher_lane_nxt = cipher_lane_i;
        reg_crc_lane_nxt    = rx_crc_i;

        bus_crc_word       = function_calc_crc16({reg_type_lane_f, reg_cipher_lane_f});
        reg_fire_evt_nxt   = 1'b0;
        reg_match_flag_nxt = reg_match_flag_f;
        reg_crc_word_nxt   = reg_crc_word_f;

        if (reg_parse_evt_f) begin
            reg_fire_evt_nxt   = 1'b1;
            reg_match_flag_nxt = (bus_crc_word == reg_crc_lane_f);
            reg_crc_word_nxt   = bus_crc_word;
        end

        if (!rst_n) begin
            reg_parse_evt_nxt   = 1'b0;
            reg_type_lane_nxt   = '0;
            reg_cipher_lane_nxt = '0;
            reg_crc_lane_nxt    = '0;
            reg_fire_evt_nxt    = 1'b0;
            reg_match_flag_nxt  = 1'b0;
            reg_crc_word_nxt    = '0;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : crc16_checker_register_update
        reg_parse_evt_f   <= reg_parse_evt_nxt;
        reg_type_lane_f   <= reg_type_lane_nxt;
        reg_cipher_lane_f <= reg_cipher_lane_nxt;
        reg_crc_lane_f    <= reg_crc_lane_nxt;
        reg_fire_evt_f    <= reg_fire_evt_nxt;
        reg_match_flag_f  <= reg_match_flag_nxt;
        reg_crc_word_f    <= reg_crc_word_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign crc_valid_q = reg_fire_evt_f;
    assign crc_ok_q    = reg_match_flag_f;
    assign crc_calc_q  = reg_crc_word_f;

endmodule
