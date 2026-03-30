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
//   packet_valid : One-cycle pulse for a newly assembled packet.
//   packet_data  : 160-bit packet bus from rf_secure_id_packet_rx.
//   parsed_valid : One-cycle pulse indicating parsed field outputs are valid.
//   packet_type  : Packet type field extracted from packet_data.
//   ciphertext   : AES ciphertext field extracted from packet_data.
//   crc_rx       : Received CRC16 field extracted from packet_data.
//
// Functions:
//   None.
//
// State Variables:
//   reg_packet_valid_in_f[0:0]  : One-stage capture register for packet_valid. Reset default = 1'b0.
//   reg_packet_data_in_f[159:0] : One-stage capture register for packet_data. Reset default = '0.
//   reg_parsed_valid_f[0:0]     : Registered parsed-valid pulse. Reset default = 1'b0.
//   reg_packet_type_f[7:0]      : Registered packet_type output field. Reset default = '0.
//   reg_ciphertext_f[127:0]     : Registered ciphertext output field. Reset default = '0.
//   reg_crc_rx_f[15:0]          : Registered crc_rx output field. Reset default = '0.
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
//   Interface Budget   : packet_data is captured at the boundary; all outputs are registered.
//   Resource Expectation: Low-area field extraction logic only; no memories or arithmetic macros.
//   Signoff Follow-up  : Gate-level simulation and RTL-to-netlist equivalence remain required
//                        final signoff activities outside this educational repo.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock core_clk <integration_defined> [get_ports {packet_valid packet_data[*]}]
//   set_output_delay -clock core_clk <integration_defined> [get_ports {parsed_valid packet_type[*] ciphertext[*] crc_rx[*]}]
//   No false-path or multicycle exceptions are expected for this module.
//
// LIMITATION:
//   This block assumes packet framing is already complete and does not validate
//   packet semantic correctness beyond fixed field extraction.
//=====================================================================================================
module rf_secure_id_packet_parser (
    input  logic         core_clk,
    input  logic         rst_n,
    input  logic         packet_valid,
    input  logic [159:0] packet_data,
    output logic         parsed_valid,
    output logic [7:0]   packet_type,
    output logic [127:0] ciphertext,
    output logic [15:0]  crc_rx
);

    //========================================================================
    // Input capture and output staging registers
    //========================================================================
    logic reg_packet_valid_in_f;
    logic reg_packet_valid_in_nxt;
    logic [159:0] reg_packet_data_in_f;
    logic [159:0] reg_packet_data_in_nxt;

    logic reg_parsed_valid_f;
    logic reg_parsed_valid_nxt;
    logic [7:0] reg_packet_type_f;
    logic [7:0] reg_packet_type_nxt;
    logic [127:0] reg_ciphertext_f;
    logic [127:0] reg_ciphertext_nxt;
    logic [15:0] reg_crc_rx_f;
    logic [15:0] reg_crc_rx_nxt;

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
        reg_packet_valid_in_nxt = packet_valid;
        reg_packet_data_in_nxt  = packet_data;

        reg_parsed_valid_nxt = 1'b0;
        reg_packet_type_nxt  = reg_packet_type_f;
        reg_ciphertext_nxt   = reg_ciphertext_f;
        reg_crc_rx_nxt       = reg_crc_rx_f;

        if (reg_packet_valid_in_f) begin
            reg_parsed_valid_nxt = 1'b1;
            reg_packet_type_nxt  = reg_packet_data_in_f[LP_PACKET_TYPE_MSB:LP_PACKET_TYPE_LSB];
            reg_ciphertext_nxt   = reg_packet_data_in_f[LP_CIPHERTEXT_MSB:LP_CIPHERTEXT_LSB];
            reg_crc_rx_nxt       = reg_packet_data_in_f[LP_CRC_MSB:LP_CRC_LSB];
        end

        if (!rst_n) begin
            reg_packet_valid_in_nxt = 1'b0;
            reg_packet_data_in_nxt  = '0;
            reg_parsed_valid_nxt = 1'b0;
            reg_packet_type_nxt  = '0;
            reg_ciphertext_nxt   = '0;
            reg_crc_rx_nxt       = '0;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : packet_parser_register_update
        reg_packet_valid_in_f <= reg_packet_valid_in_nxt;
        reg_packet_data_in_f  <= reg_packet_data_in_nxt;
        reg_parsed_valid_f <= reg_parsed_valid_nxt;
        reg_packet_type_f  <= reg_packet_type_nxt;
        reg_ciphertext_f   <= reg_ciphertext_nxt;
        reg_crc_rx_f       <= reg_crc_rx_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign parsed_valid = reg_parsed_valid_f;
    assign packet_type  = reg_packet_type_f;
    assign ciphertext   = reg_ciphertext_f;
    assign crc_rx       = reg_crc_rx_f;

endmodule
