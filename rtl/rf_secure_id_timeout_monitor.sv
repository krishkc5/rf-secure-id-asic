//=====================================================================================================
// Module: rf_secure_id_timeout_monitor
// Function: Track one active decrypt request and emit a single-cycle timeout
//           pulse if lookup completion does not arrive before the configured
//           countdown expires.
//
// Parameters:
//   P_TIMEOUT_CYCLES : Number of cycles allowed between start and watch_clear.
//                      Valid range is >= 1.
//
// Local Parameters:
//   LP_TIMEOUT_COUNT_WIDTH = Counter width derived from P_TIMEOUT_CYCLES.
//
// Ports:
//   core_clk      : Primary digital clock.
//   rst_n         : Active-low reset sampled in the module clock domain.
//   kick_evt_i    : One-cycle pulse that arms the timeout counter.
//   stop_evt_i    : One-cycle pulse that cancels the active timeout window.
//   timeout_fire_q: One-cycle pulse generated when the counter expires.
//
// Functions:
//   None.
//
// Included Files:
//   None at the top of file.
//   Raw SVA is included at the bottom of the module body to satisfy the
//   project include-style assertion policy.
//
// Defines:
//   RF_SECURE_ID_SIMONLY : When set, compile the raw SVA include.
//   RF_SECURE_ID_SVA_OFF : When set, disable the raw SVA include.
//   Default build state  : Both defines are unset outside simulation-oriented
//                          compilation, so no inline SVA is present.
//
// State Variables:
//   reg_arm_evt_f[0:0]    : One-stage capture register for kick_evt_i. Reset default = 1'b0.
//   reg_stop_evt_f[0:0]   : One-stage capture register for stop_evt_i. Reset default = 1'b0.
//   reg_watch_open_f[0:0] : Internal watchdog-active state bit. Reset default = 1'b0.
//   reg_watch_cycle_count_f[...] : Countdown register for timeout expiry. Reset default = '0.
//   reg_fire_pulse_f[0:0] : Registered timeout pulse. Reset default = 1'b0.
//
// Reset Behavior:
//   Active-low reset clears captured start/stop events, closes the watchdog
//   window, zeros the countdown, and forces timeout_fire_q low.
//
// Reset Rationale:
//   Input capture registers reset to 0 so stale kick_evt_i or stop_evt_i pulses are discarded.
//   reg_watch_open_f and reg_watch_cycle_count_f reset to 0 so no watchdog window is armed.
//   reg_fire_pulse_f resets to 0 so no false timeout pulse can escape reset.
//
// Sub-modules:
//   None.
//
// Clock / Reset:
//   core_clk : Single synchronous clock domain. Target integration frequency is 50 MHz.
//   rst_n    : Active-low reset applied through next-state reset logic.
//
// Timing:
//   Throughput : One watchdog result per captured kick_evt_i / stop_evt_i transaction.
//   Latency    : timeout_fire_q pulses when the captured countdown expires, with
//                one registered output stage at the module boundary.
//
// Synthesis Guidance:
//   Clock Source       : Primary 50 MHz system clock with nominal 50% duty cycle.
//   Constraints        : No internal false-path or multicycle exceptions are expected.
//   Interface Budget   : kick_evt_i and stop_evt_i are captured at the boundary; timeout_fire_q is registered.
//   Resource Expectation: Small counter/control block only; no memories or DSP resources.
//   Resource Estimate   : ~10 state bits at P_TIMEOUT_CYCLES=32, 20 Yosys sanity cells,
//                         0 RAMs, 0 DSPs, and ~1.4% of the 1466-cell top-level baseline.
//   Signoff Follow-up  : Gate-level simulation and RTL-to-netlist equivalence remain required
//                        final signoff activities outside this educational repo.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock core_clk <integration_defined> [get_ports {kick_evt_i stop_evt_i}]
//   set_output_delay -clock core_clk <integration_defined> [get_ports {timeout_fire_q}]
//   No false-path or multicycle exceptions are expected for this module.
//
// Specification Reference:
//   Timeout semantics are documented in docs/digital_pipeline_aes.md.
//
// ASCII Timing Sketch:
//   core_clk      : |0|1|2|...|N|N+1|
//   kick_evt_i    :  1 0 0 ... 0  0
//   stop_evt_i    :  0 0 0 ... 0  0
//   timeout_fire_q:  0 0 0 ... 0  1
//
// Algorithm Summary:
//   Capture kick and stop pulses, open a single watchdog window, count down
//   from P_TIMEOUT_CYCLES, cancel on stop, and emit one registered timeout pulse.
//
// Assumptions:
//   New kick_evt_i pulses are ignored while a timeout window is already active.
//
// CRITICAL:
//   Overlapping request support is intentionally not implemented. Changing the
//   single-request assumption affects top-level timeout classification behavior.
//
// LIMITATION:
//   This first-pass watchdog ignores overlapping requests and therefore
//   assumes only one decrypt / lookup transaction is active at a time.
//
// Interface Reference:
//   Timeout arm/stop semantics and unresponsive classification behavior are
//   documented in docs/digital_pipeline_aes.md.
//=====================================================================================================
module rf_secure_id_timeout_monitor #(
    parameter int P_TIMEOUT_CYCLES = 32
) (
    input  logic core_clk,
    input  logic rst_n,
    input  logic kick_evt_i,
    input  logic stop_evt_i,
    output logic timeout_fire_q
);

    //========================================================================
    // Input capture, internal state, and output staging registers
    //========================================================================
    logic reg_arm_evt_f, reg_arm_evt_nxt;
    logic reg_stop_evt_f, reg_stop_evt_nxt;

    logic reg_watch_open_f, reg_watch_open_nxt;
    logic [LP_TIMEOUT_COUNT_WIDTH-1:0] reg_watch_cycle_count_f, reg_watch_cycle_count_nxt;
    logic reg_fire_pulse_f, reg_fire_pulse_nxt;

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
        reg_arm_evt_nxt  = kick_evt_i;
        reg_stop_evt_nxt = stop_evt_i;

        reg_watch_open_nxt        = reg_watch_open_f;
        reg_watch_cycle_count_nxt = reg_watch_cycle_count_f;
        reg_fire_pulse_nxt        = 1'b0;

        if (reg_watch_open_f) begin
            if (reg_stop_evt_f) begin
                reg_watch_open_nxt = 1'b0;
                reg_watch_cycle_count_nxt = '0;
            end else if (reg_watch_cycle_count_f == 1) begin
                reg_watch_open_nxt = 1'b0;
                reg_watch_cycle_count_nxt = '0;
                reg_fire_pulse_nxt = 1'b1;
            end else begin
                reg_watch_cycle_count_nxt = reg_watch_cycle_count_f - 1'b1;
            end
        end else if (reg_arm_evt_f) begin
            reg_watch_open_nxt        = 1'b1;
            reg_watch_cycle_count_nxt = LP_TIMEOUT_COUNT_WIDTH'(P_TIMEOUT_CYCLES);
        end

        if (!rst_n) begin
            reg_arm_evt_nxt           = 1'b0;
            reg_stop_evt_nxt          = 1'b0;
            reg_watch_open_nxt        = 1'b0;
            reg_watch_cycle_count_nxt = '0;
            reg_fire_pulse_nxt        = 1'b0;

        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : timeout_monitor_register_update
        reg_arm_evt_f           <= reg_arm_evt_nxt;
        reg_stop_evt_f          <= reg_stop_evt_nxt;
        reg_watch_open_f        <= reg_watch_open_nxt;
        reg_watch_cycle_count_f <= reg_watch_cycle_count_nxt;
        reg_fire_pulse_f        <= reg_fire_pulse_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign timeout_fire_q = reg_fire_pulse_f;

`ifndef RF_SECURE_ID_SVA_OFF
`ifdef RF_SECURE_ID_SIMONLY

`include "sva/rf_secure_id_timeout_monitor_sva.sv"

`endif // RF_SECURE_ID_SIMONLY
`endif // RF_SECURE_ID_SVA_OFF

endmodule
