//=====================================================================================================
// Module: rf_secure_id_packet_rx
// Function: Detect the packet preamble and assemble the remaining packet bits
//           into a registered 160-bit packet bus.
//
// Parameters:
//   None.
//
// Local Parameters:
//   LP_PACKET_WIDTH        = 160 bits for the complete received packet.
//   LP_PREAMBLE_WIDTH      = 8 bits for preamble detection.
//   LP_PAYLOAD_WIDTH       = 152 bits following the preamble.
//   LP_PAYLOAD_COUNT_WIDTH = Countdown width for payload capture progress.
//   LP_PREAMBLE            = 8'hA5 packet framing token.
//   LP_PACKET_RX_FSM_*     = One-hot receive FSM encodings.
//
// Ports:
//   core_clk    : Primary digital clock.
//   rst_n       : Active-low reset sampled in the module clock domain.
//   serial_bit  : One serial input bit sampled on each clock cycle.
//   packet_valid: One-cycle pulse indicating packet_data is valid.
//   packet_data : Registered 160-bit packet bus.
//
// Functions:
//   None.
//
// State Variables:
//   reg_serial_bit_in_f[0:0]                  : Boundary capture for serial_bit, reset to 0.
//   reg_packet_rx_fsm_state_f[1:0]            : One-hot receive FSM, reset to SEARCH.
//   reg_preamble_shift_f[7:0]                 : Sliding preamble detector, reset to 0.
//   reg_payload_shift_f[151:0]                : Payload shift register, reset to 0.
//   reg_payload_bits_remaining_f[7:0]         : Capture countdown, reset to 0.
//   reg_packet_valid_f[0:0]                   : Output pulse register, reset to 0.
//   reg_packet_data_f[159:0]                  : Registered packet output, reset to 0.
//
// Sub-modules:
//   None.
//
// Clock / Reset:
//   core_clk : Single synchronous clock domain. Target integration frequency is 50 MHz.
//   rst_n    : Active-low reset applied through next-state reset logic.
//
// Timing:
//   TIMING_CRITICAL: The serial receive path shifts one sampled bit per cycle.
//   STA_CRITICAL   : serial_bit -> preamble/payload shift path at 1 bit per cycle.
//   Throughput      : One serial input bit consumed per core_clk cycle.
//   Latency         : packet_valid pulses on the cycle after the final payload bit is captured.
//
// Synthesis Guidance:
//   Clock Source       : Primary 50 MHz system clock with nominal 50% duty cycle.
//   Constraints        : No internal false-path or multicycle exceptions are expected.
//   Interface Budget   : serial_bit is captured at the boundary; outputs are fully registered.
//   Resource Expectation: Register-only datapath with an 8-bit preamble shifter, a 152-bit
//                         payload shifter, and a small one-hot FSM. No RAM or DSP resources used.
//   Timing Margin      : Target >=10% post-route slack margin at the 50 MHz integration point.
//   Signoff Follow-up  : Gate-level simulation and RTL-to-netlist equivalence remain required
//                        final signoff activities outside this educational repo. Back-annotated
//                        timing simulation is recommended for reset release and packet framing.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock [get_clocks core_clk] 4.000 [get_ports serial_bit]
//   set_output_delay -clock [get_clocks core_clk] 4.000 [get_ports {packet_valid packet_data[*]}]
//   No false-path or multicycle exceptions are expected for this block.
//
// Assumptions:
//   Input serial_bit is aligned to core_clk and presented MSB-first.
//
// LIMITATION:
//   This block performs framing only; malformed-but-preamble-matching packets
//   must be rejected by downstream CRC and plaintext validation stages.
//=====================================================================================================
module rf_secure_id_packet_rx (
    input  logic         core_clk,
    input  logic         rst_n,
    input  logic         serial_bit,
    output logic         packet_valid,
    output logic [159:0] packet_data
);

    //========================================================================
    // Input capture, internal state, and output staging registers
    //========================================================================
    typedef enum logic [1:0] {
        LP_PACKET_RX_FSM_SEARCH  = 2'b01,
        LP_PACKET_RX_FSM_CAPTURE = 2'b10
    } packet_rx_fsm_t;

    logic reg_serial_bit_in_f;
    logic reg_serial_bit_in_nxt;

    packet_rx_fsm_t reg_packet_rx_fsm_state_f;
    packet_rx_fsm_t reg_packet_rx_fsm_state_nxt;
    logic [LP_PREAMBLE_WIDTH-1:0] reg_preamble_shift_f;
    logic [LP_PREAMBLE_WIDTH-1:0] reg_preamble_shift_nxt;
    logic [LP_PAYLOAD_WIDTH-1:0] reg_payload_shift_f;
    logic [LP_PAYLOAD_WIDTH-1:0] reg_payload_shift_nxt;
    logic [LP_PAYLOAD_COUNT_WIDTH-1:0] reg_payload_bits_remaining_f;
    logic [LP_PAYLOAD_COUNT_WIDTH-1:0] reg_payload_bits_remaining_nxt;
    logic reg_packet_valid_f;
    logic reg_packet_valid_nxt;
    logic [LP_PACKET_WIDTH-1:0] reg_packet_data_f;
    logic [LP_PACKET_WIDTH-1:0] reg_packet_data_nxt;

    //========================================================================
    // Local parameters
    //========================================================================
    localparam int LP_PACKET_WIDTH         = 160;
    localparam int LP_PREAMBLE_WIDTH       = 8;
    localparam int LP_PAYLOAD_WIDTH        = LP_PACKET_WIDTH - LP_PREAMBLE_WIDTH;
    localparam int LP_PAYLOAD_COUNT_WIDTH  = $clog2(LP_PAYLOAD_WIDTH + 1);
    localparam logic [LP_PREAMBLE_WIDTH-1:0] LP_PREAMBLE = 8'hA5;


    //========================================================================
    // Combinatorial next-state logic
    //========================================================================
    always_comb begin : packet_rx_next_state_logic
        // Capture the synchronous serial input and compute the next framing state,
        // shift-register contents, and registered packet outputs.
        reg_serial_bit_in_nxt         = serial_bit;
        reg_packet_rx_fsm_state_nxt   = reg_packet_rx_fsm_state_f;
        reg_preamble_shift_nxt        = reg_preamble_shift_f;
        reg_payload_shift_nxt         = reg_payload_shift_f;
        reg_payload_bits_remaining_nxt = reg_payload_bits_remaining_f;
        reg_packet_valid_nxt          = 1'b0;
        reg_packet_data_nxt           = reg_packet_data_f;

        case (reg_packet_rx_fsm_state_f)
            LP_PACKET_RX_FSM_SEARCH: begin
                // LP_PACKET_RX_FSM_SEARCH -> LP_PACKET_RX_FSM_CAPTURE [preamble matched]
                reg_preamble_shift_nxt = {
                    reg_preamble_shift_f[LP_PREAMBLE_WIDTH-2:0],
                    reg_serial_bit_in_f
                };

                if (reg_preamble_shift_nxt == LP_PREAMBLE) begin
                    reg_packet_rx_fsm_state_nxt    = LP_PACKET_RX_FSM_CAPTURE;
                    reg_payload_shift_nxt          = '0;
                    reg_payload_bits_remaining_nxt = LP_PAYLOAD_COUNT_WIDTH'(LP_PAYLOAD_WIDTH);
                end
            end

            LP_PACKET_RX_FSM_CAPTURE: begin
                // LP_PACKET_RX_FSM_CAPTURE -> LP_PACKET_RX_FSM_SEARCH [final payload bit captured]
                reg_payload_shift_nxt = {
                    reg_payload_shift_f[LP_PAYLOAD_WIDTH-2:0],
                    reg_serial_bit_in_f
                };

                if (reg_payload_bits_remaining_f == 1) begin
                    reg_packet_rx_fsm_state_nxt    = LP_PACKET_RX_FSM_SEARCH;
                    reg_preamble_shift_nxt         = '0;
                    reg_payload_bits_remaining_nxt = '0;
                    reg_packet_valid_nxt           = 1'b1;
                    reg_packet_data_nxt            = {LP_PREAMBLE, reg_payload_shift_nxt};
                end else begin
                    reg_payload_bits_remaining_nxt = reg_payload_bits_remaining_f - 1'b1;
                end
            end

            default: begin
                // Illegal state recovery: force the receiver back to SEARCH.
                reg_packet_rx_fsm_state_nxt    = LP_PACKET_RX_FSM_SEARCH;
                reg_preamble_shift_nxt         = '0;
                reg_payload_shift_nxt          = '0;
                reg_payload_bits_remaining_nxt = '0;
                reg_packet_valid_nxt           = 1'b0;
                reg_packet_data_nxt            = reg_packet_data_f;
            end
        endcase

        if (!rst_n) begin
            reg_serial_bit_in_nxt         = 1'b0;
            reg_packet_rx_fsm_state_nxt    = LP_PACKET_RX_FSM_SEARCH;
            reg_preamble_shift_nxt         = '0;
            reg_payload_shift_nxt          = '0;
            reg_payload_bits_remaining_nxt = '0;
            reg_packet_valid_nxt           = 1'b0;
            reg_packet_data_nxt            = '0;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : packet_rx_register_update
        reg_serial_bit_in_f         <= reg_serial_bit_in_nxt;
        reg_packet_rx_fsm_state_f    <= reg_packet_rx_fsm_state_nxt;
        reg_preamble_shift_f         <= reg_preamble_shift_nxt;
        reg_payload_shift_f          <= reg_payload_shift_nxt;
        reg_payload_bits_remaining_f <= reg_payload_bits_remaining_nxt;
        reg_packet_valid_f           <= reg_packet_valid_nxt;
        reg_packet_data_f            <= reg_packet_data_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign packet_valid = reg_packet_valid_f;
    assign packet_data  = reg_packet_data_f;

endmodule
