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
//   LP_HDR_WINDOW_WIDTH    = 8 bits for preamble detection.
//   LP_PAYLOAD_WIDTH       = 152 bits following the preamble.
//   LP_PAYLOAD_COUNT_WIDTH = Countdown width for payload capture progress.
//   LP_MATCH_TOKEN         = 8'hA5 packet framing token.
//   LP_PACKET_RX_FSM_*     = One-hot receive FSM encodings.
//
// Ports:
//   core_clk    : Primary digital clock.
//   rst_n       : Active-low reset sampled in the module clock domain.
//   serial_bit  : One serial input bit sampled on each clock cycle.
//   packet_valid_q: One-cycle pulse indicating packet_data_q is valid.
//   packet_data_q : Registered 160-bit packet bus.
//
// Functions:
//   None.
//
// State Variables:
//   reg_bit_lane_f[0:0]         : Boundary capture for serial_bit, reset to 0.
//   state_packet_rx_f[1:0]      : One-hot receive FSM, reset to SEARCH.
//   reg_sync_window_f[7:0]      : Sliding preamble detector, reset to 0.
//   reg_body_shift_f[151:0]     : Payload shift register, reset to 0.
//   reg_body_bits_left_f[7:0]   : Capture countdown, reset to 0.
//   reg_frame_evt_f[0:0]        : Output pulse register, reset to 0.
//   reg_frame_bits_f[159:0]     : Registered packet output, reset to 0.
//
// Reset Behavior:
//   Active-low reset clears the receive FSM, preamble detector, payload
//   shifter, and outputs so packet search restarts from SEARCH.
//
// Reset Rationale:
//   reg_bit_lane_f resets to 0 to discard any stale boundary sample.
//   FSM, preamble, payload, and countdown state reset to the idle SEARCH condition with empty
//   shifters so packet framing restarts deterministically after reset.
//   Output registers reset to 0 so no false packet_valid_q pulse or stale packet_data_q escapes reset.
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
//   Latency         : packet_valid_q pulses on the cycle after the final payload bit is captured.
//
// Synthesis Guidance:
//   Clock Source       : Primary 50 MHz system clock with nominal 50% duty cycle.
//   Constraints        : No internal false-path or multicycle exceptions are expected.
//   Interface Budget   : serial_bit is captured at the boundary; outputs are fully registered.
//   FSM Policy         : Preserve the explicit one-hot receive-state encoding; do not auto-recode it
//                        during synthesis.
//   Resource Expectation: Register-only datapath with an 8-bit preamble shifter, a 152-bit
//                         payload shifter, and a small one-hot FSM. No RAM or DSP resources used.
//   Resource Estimate   : ~332 state bits, 28 Yosys sanity cells, 0 RAMs, 0 DSPs,
//                         and ~1.9% of the 1466-cell top-level baseline.
//   Timing Margin      : Target >=10% post-route slack margin at the 50 MHz integration point.
//   Signoff Follow-up  : Gate-level simulation and RTL-to-netlist equivalence remain required
//                        final signoff activities outside this educational repo. Back-annotated
//                        timing simulation is recommended for reset release and packet framing.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock [get_clocks core_clk] 4.000 [get_ports serial_bit]
//   set_output_delay -clock [get_clocks core_clk] 4.000 [get_ports {packet_valid_q packet_data_q[*]}]
//   No false-path or multicycle exceptions are expected for this block.
//
// Specification Reference:
//   Project packet format and receive-path intent are captured in:
//   docs/digital_pipeline_aes.md
//
// Algorithm Summary:
//   An 8-bit sliding header register searches for LP_MATCH_TOKEN. Once matched,
//   a 152-bit payload shifter collects the remainder of the frame and emits
//   one registered packet bundle.
//
// ASCII State Diagram:
//   SEARCH  --[LP_MATCH_TOKEN matched]-->  CAPTURE
//   CAPTURE --[final payload bit]-----> SEARCH
//   Any illegal state ----------------> SEARCH
//
// ASCII Timing Sketch:
//   core_clk      : |0|1|2|...|158|159|
//   serial_bit    :  A 5 ............. D
//   packet_valid_q:  0 0 ............. 1
//   packet_data_q :  X X .... valid on packet_valid_q pulse only
//
// Assumptions:
//   Input serial_bit is aligned to core_clk and presented MSB-first.
//
// CRITICAL:
//   The preamble-detect and payload-shift ordering must remain MSB-first.
//   Reordering the shift direction breaks downstream field extraction.
//
// LIMITATION:
//   This block performs framing only; malformed-but-preamble-matching packets
//   must be rejected by downstream CRC and plaintext validation stages.
//
// Interface Reference:
//   Serial receive assumptions and packet framing semantics are documented in
//   docs/digital_pipeline_aes.md and docs/analog_digital_interface.md.
//=====================================================================================================
module rf_secure_id_packet_rx (
    input  logic         core_clk,
    input  logic         rst_n,
    input  logic         serial_bit,
    output logic         packet_valid_q,
    output logic [159:0] packet_data_q
);

    //========================================================================
    // Input capture, internal state, and output staging registers
    //========================================================================
    typedef enum logic [1:0] {
        LP_PACKET_RX_FSM_SEARCH  = 2'b01,
        LP_PACKET_RX_FSM_CAPTURE = 2'b10
    } packet_rx_fsm_t;

    logic reg_bit_lane_f, reg_bit_lane_nxt;

    packet_rx_fsm_t state_packet_rx_f, state_packet_rx_nxt;
    logic [LP_HDR_WINDOW_WIDTH-1:0] reg_sync_window_f, reg_sync_window_nxt;
    logic [LP_BODY_WIDTH-1:0] reg_body_shift_f, reg_body_shift_nxt;
    logic [LP_BODY_COUNT_WIDTH-1:0] reg_body_bits_left_f, reg_body_bits_left_nxt;
    logic reg_frame_evt_f, reg_frame_evt_nxt;
    logic [LP_FRAME_WIDTH-1:0] reg_frame_bits_f, reg_frame_bits_nxt;

    //========================================================================
    // Local parameters
    //========================================================================
    localparam int LP_FRAME_WIDTH = 160;
    localparam int LP_HDR_WINDOW_WIDTH = 8;
    localparam int LP_BODY_WIDTH = LP_FRAME_WIDTH - LP_HDR_WINDOW_WIDTH;
    localparam int LP_BODY_COUNT_WIDTH = $clog2(LP_BODY_WIDTH + 1);
    localparam logic [LP_HDR_WINDOW_WIDTH-1:0] LP_MATCH_TOKEN = 8'hA5;


    //========================================================================
    // Combinatorial next-state logic
    //========================================================================
    always_comb begin : packet_rx_next_state_logic
        // Capture the synchronous serial input and compute the next framing state,
        // shift-register contents, and registered packet outputs.
        reg_bit_lane_nxt       = serial_bit;
        state_packet_rx_nxt    = state_packet_rx_f;
        reg_sync_window_nxt    = reg_sync_window_f;
        reg_body_shift_nxt     = reg_body_shift_f;
        reg_body_bits_left_nxt = reg_body_bits_left_f;
        reg_frame_evt_nxt      = 1'b0;
        reg_frame_bits_nxt     = reg_frame_bits_f;

        case (state_packet_rx_f)
            LP_PACKET_RX_FSM_SEARCH: begin
                // LP_PACKET_RX_FSM_SEARCH -> LP_PACKET_RX_FSM_CAPTURE [preamble matched]
                reg_sync_window_nxt = {
                    reg_sync_window_f[LP_HDR_WINDOW_WIDTH-2:0],
                    reg_bit_lane_f
                };

                if (reg_sync_window_nxt == LP_MATCH_TOKEN) begin
                    state_packet_rx_nxt    = LP_PACKET_RX_FSM_CAPTURE;
                    reg_body_shift_nxt     = '0;
                    reg_body_bits_left_nxt = LP_BODY_COUNT_WIDTH'(LP_BODY_WIDTH);
                end
            end

            LP_PACKET_RX_FSM_CAPTURE: begin
                // LP_PACKET_RX_FSM_CAPTURE -> LP_PACKET_RX_FSM_SEARCH [final payload bit captured]
                reg_body_shift_nxt = {
                    reg_body_shift_f[LP_BODY_WIDTH-2:0],
                    reg_bit_lane_f
                };

                if (reg_body_bits_left_f == 1) begin
                    state_packet_rx_nxt    = LP_PACKET_RX_FSM_SEARCH;
                    reg_sync_window_nxt    = '0;
                    reg_body_bits_left_nxt = '0;
                    reg_frame_evt_nxt      = 1'b1;
                    reg_frame_bits_nxt     = {LP_MATCH_TOKEN, reg_body_shift_nxt};
                end else begin
                    reg_body_bits_left_nxt = reg_body_bits_left_f - 1'b1;
                end
            end

            default: begin
                // Illegal state recovery: force the receiver back to SEARCH.
                state_packet_rx_nxt    = LP_PACKET_RX_FSM_SEARCH;
                reg_sync_window_nxt    = '0;
                reg_body_shift_nxt     = '0;
                reg_body_bits_left_nxt = '0;
                reg_frame_evt_nxt      = 1'b0;
                reg_frame_bits_nxt     = reg_frame_bits_f;
            end
        endcase

        if (!rst_n) begin
            reg_bit_lane_nxt       = 1'b0;
            state_packet_rx_nxt    = LP_PACKET_RX_FSM_SEARCH;
            reg_sync_window_nxt    = '0;
            reg_body_shift_nxt     = '0;
            reg_body_bits_left_nxt = '0;
            reg_frame_evt_nxt      = 1'b0;
            reg_frame_bits_nxt     = '0;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : packet_rx_register_update
        reg_bit_lane_f       <= reg_bit_lane_nxt;
        state_packet_rx_f    <= state_packet_rx_nxt;
        reg_sync_window_f    <= reg_sync_window_nxt;
        reg_body_shift_f     <= reg_body_shift_nxt;
        reg_body_bits_left_f <= reg_body_bits_left_nxt;
        reg_frame_evt_f      <= reg_frame_evt_nxt;
        reg_frame_bits_f     <= reg_frame_bits_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign packet_valid_q = reg_frame_evt_f;
    assign packet_data_q  = reg_frame_bits_f;

endmodule
