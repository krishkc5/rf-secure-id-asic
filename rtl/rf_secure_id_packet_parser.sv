//=====================================================================================================
// Module: rf_secure_id_packet_parser
// Function: Register the parsed fields from a completed 160-bit packet.
//
// Parameters:
//   None.
//
// Local Parameters:
//   LP_PACKET_TYPE_* = Bit positions for packet_type extraction.
//   LP_CIPHERTEXT_*  = Bit positions for ciphertext extraction.
//   LP_CRC_*         = Bit positions for received CRC16 extraction.
//
// Ports:
//   core_clk     : Primary digital clock.
//   rst_n        : Active-low reset sampled in the module clock domain.
//   frame_evt_i    : One-cycle pulse for a newly assembled packet.
//   frame_bits_i   : 160-bit packet bus from rf_secure_id_packet_rx.
//   parsed_valid_q : One-cycle pulse indicating parsed field outputs are valid.
//   packet_type_q  : Packet type field extracted from frame_bits_i.
//   ciphertext_q   : AES ciphertext field extracted from frame_bits_i.
//   crc_rx_q       : Received CRC16 field extracted from frame_bits_i.
//
// Functions:
//   None.
//
// Included Files:
//   None.
//
// State Variables:
//   reg_frame_evt_f[0:0]        : One-stage capture register for frame_evt_i. Reset default = 1'b0.
//   reg_frame_bits_f[159:0]     : One-stage capture register for frame_bits_i. Reset default = '0.
//   reg_parse_evt_f[0:0]        : Registered parsed-valid pulse. Reset default = 1'b0.
//   reg_type_lane_f[7:0]        : Registered packet_type_q output field. Reset default = '0.
//   reg_cipher_lane_f[127:0]    : Registered ciphertext_q output field. Reset default = '0.
//   reg_crc_lane_f[15:0]        : Registered crc_rx_q output field. Reset default = '0.
//
// Reset Behavior:
//   Active-low reset clears the captured packet bus and all parsed outputs so
//   field extraction restarts from an empty frame after reset release.
//
// Reset Rationale:
//   Input capture registers reset to 0 so partial or stale packets are discarded on reset.
//   Output field registers reset to 0 so no parser-valid pulse or stale fields escape reset.
//
// Sub-modules:
//   None.
//
// Clock / Reset:
//   core_clk : Single synchronous clock domain. Target integration frequency is 50 MHz.
//   rst_n    : Active-low reset applied through next-state reset logic.
//
// Timing:
//   Throughput : One parsed field bundle per captured packet event.
//   Latency    : One cycle from the captured packet bus to registered parser outputs.
//
// Synthesis Guidance:
//   Clock Source       : Primary 50 MHz system clock with nominal 50% duty cycle.
//   Constraints        : No internal false-path or multicycle exceptions are expected.
//   Interface Budget   : frame_bits_i is captured at the boundary; all outputs are registered.
//   Resource Expectation: Low-area field extraction logic only; no memories or arithmetic macros.
//   Resource Estimate   : ~314 state bits, 7 Yosys sanity cells, 0 RAMs, 0 DSPs,
//                         and ~0.5% of the 1466-cell top-level baseline.
//   Signoff Follow-up  : Gate-level simulation and RTL-to-netlist equivalence remain required
//                        final signoff activities outside this educational repo.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock core_clk <integration_defined>
//                    [get_ports {frame_evt_i frame_bits_i[*]}]
//   set_output_delay -clock core_clk <integration_defined>
//                    [get_ports {parsed_valid_q packet_type_q[*] ciphertext_q[*] crc_rx_q[*]}]
//   No false-path or multicycle exceptions are expected for this module.
//
// Specification Reference:
//   Packet layout and field ordering are documented in docs/digital_pipeline_aes.md.
//
// Byte Ordering:
//   frame_bits_i is interpreted MSB-first using the published packet bit map:
//   [159:152] preamble, [151:144] type, [143:16] ciphertext, [15:0] crc16.
//
// ASCII Timing Sketch:
//   core_clk      : |0|1|2|
//   frame_evt_i   :  1 0 0
//   parsed_valid_q:  0 1 0
//   packet_type_q :  X valid on parsed_valid_q pulse
//
// Algorithm Summary:
//   Capture the full frame bus, then slice the registered packet into fixed
//   fields for downstream CRC checking.
//
// Assumptions:
//   frame_bits_i already matches the published packet bit ordering and width.
//
// CRITICAL:
//   The fixed bit slices for packet_type, ciphertext, and crc16 must remain
//   aligned with the published packet map and downstream CRC coverage.
//
// LIMITATION:
//   This block assumes packet framing is already complete and does not validate
//   packet semantic correctness beyond fixed field extraction.
//
// Interface Reference:
//   Packet field map and parser output semantics are documented in
//   docs/digital_pipeline_aes.md.
//=====================================================================================================
module rf_secure_id_packet_parser (
    input  logic         core_clk,
    input  logic         rst_n,
    input  logic         frame_evt_i,
    input  logic [159:0] frame_bits_i,
    output logic         parsed_valid_q,
    output logic [7:0]   packet_type_q,
    output logic [127:0] ciphertext_q,
    output logic [15:0]  crc_rx_q
);

    //========================================================================
    // Input capture and output staging registers
    //========================================================================
    logic         reg_frame_evt_f, reg_frame_evt_nxt;
    logic [159:0] reg_frame_bits_f, reg_frame_bits_nxt;

    logic         reg_parse_evt_f, reg_parse_evt_nxt;
    logic [7:0]   reg_type_lane_f, reg_type_lane_nxt;
    logic [127:0] reg_cipher_lane_f, reg_cipher_lane_nxt;
    logic [15:0]  reg_crc_lane_f, reg_crc_lane_nxt;

    //========================================================================
    // Local parameters
    //========================================================================
    localparam int LP_PACKET_TYPE_MSB = 151;
    localparam int LP_PACKET_TYPE_LSB = 144;
    localparam int LP_CIPHERTEXT_MSB  = 143;
    localparam int LP_CIPHERTEXT_LSB  = 16;
    localparam int LP_CRC_MSB         = 15;
    localparam int LP_CRC_LSB         = 0;

    //========================================================================
    // Combinatorial next-state logic
    //========================================================================
    always_comb begin : packet_parser_next_state_logic
        // Capture the synchronous packet interface and compute the next
        // registered field bundle that feeds the CRC stage.
        reg_frame_evt_nxt  = frame_evt_i;
        reg_frame_bits_nxt = frame_bits_i;

        reg_parse_evt_nxt   = 1'b0;
        reg_type_lane_nxt   = reg_type_lane_f;
        reg_cipher_lane_nxt = reg_cipher_lane_f;
        reg_crc_lane_nxt    = reg_crc_lane_f;

        if (reg_frame_evt_f) begin
            reg_parse_evt_nxt   = 1'b1;
            reg_type_lane_nxt   = reg_frame_bits_f[LP_PACKET_TYPE_MSB:LP_PACKET_TYPE_LSB];
            reg_cipher_lane_nxt = reg_frame_bits_f[LP_CIPHERTEXT_MSB:LP_CIPHERTEXT_LSB];
            reg_crc_lane_nxt    = reg_frame_bits_f[LP_CRC_MSB:LP_CRC_LSB];
        end

        if (!rst_n) begin
            reg_frame_evt_nxt  = 1'b0;
            reg_frame_bits_nxt = '0;
            reg_parse_evt_nxt   = 1'b0;
            reg_type_lane_nxt   = '0;
            reg_cipher_lane_nxt = '0;
            reg_crc_lane_nxt    = '0;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : packet_parser_register_update
        reg_frame_evt_f   <= reg_frame_evt_nxt;
        reg_frame_bits_f  <= reg_frame_bits_nxt;
        reg_parse_evt_f   <= reg_parse_evt_nxt;
        reg_type_lane_f   <= reg_type_lane_nxt;
        reg_cipher_lane_f <= reg_cipher_lane_nxt;
        reg_crc_lane_f    <= reg_crc_lane_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign parsed_valid_q = reg_parse_evt_f;
    assign packet_type_q  = reg_type_lane_f;
    assign ciphertext_q   = reg_cipher_lane_f;
    assign crc_rx_q       = reg_crc_lane_f;

endmodule
