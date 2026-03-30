//=====================================================================================================
// Module: rf_secure_id_timeout_monitor
// Function: Track one active decrypt request and emit a single-cycle timeout
//           pulse if lookup completion does not arrive before the configured
//           countdown expires.
//
// Parameters:
//   P_TIMEOUT_CYCLES : Number of cycles allowed between start and done.
//                      Valid range is >= 1.
//
// Local Parameters:
//   LP_TIMEOUT_COUNT_WIDTH = Counter width derived from P_TIMEOUT_CYCLES.
//
// Ports:
//   core_clk      : Primary digital clock.
//   rst_n         : Active-low reset sampled in the module clock domain.
//   start         : One-cycle pulse that arms the timeout counter.
//   done          : One-cycle pulse that cancels the active timeout window.
//   timeout_valid : One-cycle pulse generated when the counter expires.
//
// Functions:
//   None.
//
// State Variables:
//   reg_start_in_f[0:0]       : One-stage capture register for start. Reset default = 1'b0.
//   reg_done_in_f[0:0]        : One-stage capture register for done. Reset default = 1'b0.
//   reg_timeout_active_f[0:0] : Internal watchdog-active state bit. Reset default = 1'b0.
//   reg_timeout_count_f[...]  : Countdown register for timeout expiry. Reset default = '0.
//   reg_timeout_valid_f[0:0]  : Registered timeout-valid pulse. Reset default = 1'b0.
//
// Sub-modules:
//   None.
//
// Clock / Reset:
//   core_clk : Single synchronous clock domain. Target integration frequency is 50 MHz.
//   rst_n    : Active-low reset applied through next-state reset logic.
//
// Timing:
//   Throughput : One watchdog result per captured start / done transaction.
//   Latency    : timeout_valid pulses when the captured countdown expires, with
//                one registered output stage at the module boundary.
//
// Synthesis Guidance:
//   Clock Source       : Primary 50 MHz system clock with nominal 50% duty cycle.
//   Constraints        : No internal false-path or multicycle exceptions are expected.
//   Interface Budget   : start and done are captured at the boundary; timeout_valid is registered.
//   Resource Expectation: Small counter/control block only; no memories or DSP resources.
//   Signoff Follow-up  : Gate-level simulation and RTL-to-netlist equivalence remain required
//                        final signoff activities outside this educational repo.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock core_clk <integration_defined> [get_ports {start done}]
//   set_output_delay -clock core_clk <integration_defined> [get_ports {timeout_valid}]
//   No false-path or multicycle exceptions are expected for this module.
//
// Assumptions:
//   New start pulses are ignored while a timeout window is already active.
//
// LIMITATION:
//   This first-pass watchdog ignores overlapping requests and therefore
//   assumes only one decrypt / lookup transaction is active at a time.
//=====================================================================================================
module rf_secure_id_timeout_monitor #(
    parameter int P_TIMEOUT_CYCLES = 32
) (
    input  logic core_clk,
    input  logic rst_n,
    input  logic start,
    input  logic done,
    output logic timeout_valid
);

    //========================================================================
    // Input capture, internal state, and output staging registers
    //========================================================================
    logic reg_start_in_f;
    logic reg_start_in_nxt;
    logic reg_done_in_f;
    logic reg_done_in_nxt;

    logic reg_timeout_active_f;
    logic reg_timeout_active_nxt;
    logic [LP_TIMEOUT_COUNT_WIDTH-1:0] reg_timeout_count_f;
    logic [LP_TIMEOUT_COUNT_WIDTH-1:0] reg_timeout_count_nxt;
    logic reg_timeout_valid_f;
    logic reg_timeout_valid_nxt;

    //========================================================================
    // Local parameters
    //========================================================================
    localparam int LP_TIMEOUT_COUNT_WIDTH = $clog2(P_TIMEOUT_CYCLES + 1);

    //========================================================================
    // Combinatorial next-state logic
    //========================================================================
    always_comb begin : timeout_monitor_next_state_logic
        // Capture request-control inputs and compute the next watchdog state
        // for countdown tracking, cancellation, and timeout pulse generation.
        reg_start_in_nxt = start;
        reg_done_in_nxt  = done;

        reg_timeout_active_nxt = reg_timeout_active_f;
        reg_timeout_count_nxt  = reg_timeout_count_f;
        reg_timeout_valid_nxt  = 1'b0;

        if (reg_timeout_active_f) begin
            if (reg_done_in_f) begin
                reg_timeout_active_nxt = 1'b0;
                reg_timeout_count_nxt  = '0;
            end else if (reg_timeout_count_f == 1) begin
                reg_timeout_active_nxt = 1'b0;
                reg_timeout_count_nxt  = '0;
                reg_timeout_valid_nxt  = 1'b1;
            end else begin
                reg_timeout_count_nxt = reg_timeout_count_f - 1'b1;
            end
        end else if (reg_start_in_f) begin
            reg_timeout_active_nxt = 1'b1;
            reg_timeout_count_nxt  = LP_TIMEOUT_COUNT_WIDTH'(P_TIMEOUT_CYCLES);
        end

        if (!rst_n) begin
            reg_start_in_nxt       = 1'b0;
            reg_done_in_nxt        = 1'b0;
            reg_timeout_active_nxt = 1'b0;
            reg_timeout_count_nxt  = '0;
            reg_timeout_valid_nxt  = 1'b0;

        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : timeout_monitor_register_update
        reg_start_in_f       <= reg_start_in_nxt;
        reg_done_in_f        <= reg_done_in_nxt;
        reg_timeout_active_f <= reg_timeout_active_nxt;
        reg_timeout_count_f  <= reg_timeout_count_nxt;
        reg_timeout_valid_f  <= reg_timeout_valid_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign timeout_valid = reg_timeout_valid_f;

`ifndef RF_SECURE_ID_SVA_OFF
`ifdef RF_SECURE_ID_SIMONLY

`include "sva/rf_secure_id_timeout_monitor_sva.sv"

`endif // RF_SECURE_ID_SIMONLY
`endif // RF_SECURE_ID_SVA_OFF

endmodule
