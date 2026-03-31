//=====================================================================================================
// Module: rf_secure_id_classifier
// Function: Convert lookup and timeout events into one registered terminal
//           classification result.
//
// Parameters:
//   None.
//
// Ports:
//   core_clk       : Primary digital clock.
//   rst_n          : Active-low reset sampled in the module clock domain.
//   lookup_evt_i     : One-cycle pulse indicating a completed CAM lookup.
//   lookup_hit_i     : CAM match result for the lookup event.
//   timeout_evt_i    : One-cycle pulse indicating the request timed out.
//   classify_valid_q : One-cycle pulse indicating a terminal classification.
//   class_grant_q    : High for authorized classification.
//   class_reject_q   : High for unauthorized classification.
//   unresponsive_q   : High for timeout / unresponsive classification.
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
//   reg_cam_evt_f[0:0]   : One-stage capture register for lookup_evt_i. Reset default = 1'b0.
//   reg_match_evt_f[0:0] : One-stage capture register for lookup_hit_i. Reset default = 1'b0.
//   reg_watch_evt_f[0:0] : One-stage capture register for timeout_evt_i. Reset default = 1'b0.
//   reg_term_evt_f[0:0]  : Registered classify_valid_q pulse. Reset default = 1'b0.
//   reg_allow_f[0:0]     : Registered class_grant_q output. Reset default = 1'b0.
//   reg_reject_f[0:0]    : Registered class_reject_q output. Reset default = 1'b0.
//   reg_noresp_f[0:0]    : Registered unresponsive_q output. Reset default = 1'b0.
//
// Reset Behavior:
//   Active-low reset clears captured terminal events and forces all
//   classification outputs low on the next registered cycle.
//
// Reset Rationale:
//   Input capture registers reset to 0 so stale lookup or timeout events are discarded.
//   Terminal outputs reset to 0 so no classification is emitted during or immediately after reset.
//
// Sub-modules:
//   None.
//
// Clock / Reset:
//   core_clk : Single synchronous clock domain. Target integration frequency is 50 MHz.
//   rst_n    : Active-low reset applied through next-state reset logic.
//
// Timing:
//   Throughput : One classification result per captured terminal event.
//   Latency    : One cycle from captured lookup / timeout inputs to registered outputs.
//
// Synthesis Guidance:
//   Clock Source       : Primary 50 MHz system clock with nominal 50% duty cycle.
//   Constraints        : No internal false-path or multicycle exceptions are expected.
//   Interface Budget   : lookup_evt_i, lookup_hit_i, and timeout_evt_i are captured at the boundary;
//                        all outputs are registered.
//   Resource Expectation: Small control-only block; no memories or DSP resources.
//   Resource Estimate   : ~7 state bits, 16 Yosys sanity cells, 0 RAMs, 0 DSPs,
//                         and ~1.1% of the 1466-cell top-level baseline.
//   Signoff Follow-up  : Gate-level simulation and RTL-to-netlist equivalence remain required
//                        final signoff activities outside this educational repo.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock core_clk <integration_defined>
//                    [get_ports {lookup_evt_i lookup_hit_i timeout_evt_i}]
//   set_output_delay -clock core_clk <integration_defined>
//                    [get_ports {classify_valid_q class_grant_q class_reject_q unresponsive_q}]
//   No false-path or multicycle exceptions are expected for this module.
//
// Specification Reference:
//   Final classification semantics and timeout priority rules are documented in
//   docs/digital_pipeline_aes.md.
//
// ASCII Timing Sketch:
//   core_clk        : |0|1|2|
//   lookup_evt_i    :  1 0 0
//   timeout_evt_i   :  0 0 0
//   classify_valid_q:  0 1 0
//   class_grant_q   :  X valid on classify_valid_q pulse
//
// Algorithm Summary:
//   Capture terminal events, give lookup precedence over timeout for the same
//   cycle, and emit exactly one registered classification output pulse.
//
// Assumptions:
//   lookup_evt_i has priority over timeout_evt_i if both are asserted
//   together in the same cycle.
//
// CRITICAL:
//   The three terminal class outputs must remain mutually exclusive. Any
//   change to the lookup-vs-timeout priority changes architectural behavior.
//
// LIMITATION:
//   The classifier resolves only mutually exclusive terminal status and does
//   not retain historical event context after the output pulse cycle.
//
// Interface Reference:
//   Classification output semantics are documented in
//   docs/digital_pipeline_aes.md.
//=====================================================================================================
module rf_secure_id_classifier (
    input  logic core_clk,
    input  logic rst_n,
    input  logic lookup_evt_i,
    input  logic lookup_hit_i,
    input  logic timeout_evt_i,
    output logic classify_valid_q,
    output logic class_grant_q,
    output logic class_reject_q,
    output logic unresponsive_q
);

    //========================================================================
    // Input capture and output staging registers
    //========================================================================
    logic reg_cam_evt_f, reg_cam_evt_nxt;
    logic reg_match_evt_f, reg_match_evt_nxt;
    logic reg_watch_evt_f, reg_watch_evt_nxt;

    logic reg_term_evt_f, reg_term_evt_nxt;
    logic reg_allow_f, reg_allow_nxt;
    logic reg_reject_f, reg_reject_nxt;
    logic reg_noresp_f, reg_noresp_nxt;

    //========================================================================
    // Combinatorial next-state logic
    //========================================================================
    always_comb begin : classifier_next_state_logic
        // Capture terminal event inputs and compute the next registered
        // classification outputs with lookup taking priority over timeout.
        reg_cam_evt_nxt   = lookup_evt_i;
        reg_match_evt_nxt = lookup_hit_i;
        reg_watch_evt_nxt = timeout_evt_i;

        reg_term_evt_nxt = 1'b0;
        reg_allow_nxt    = reg_allow_f;
        reg_reject_nxt   = reg_reject_f;
        reg_noresp_nxt   = reg_noresp_f;

        if (reg_cam_evt_f) begin
            reg_term_evt_nxt = 1'b1;
            reg_allow_nxt    = reg_match_evt_f;
            reg_reject_nxt   = ~reg_match_evt_f;
            reg_noresp_nxt   = 1'b0;
        end else if (reg_watch_evt_f) begin
            reg_term_evt_nxt = 1'b1;
            reg_allow_nxt    = 1'b0;
            reg_reject_nxt   = 1'b0;
            reg_noresp_nxt   = 1'b1;
        end

        if (!rst_n) begin
            reg_cam_evt_nxt   = 1'b0;
            reg_match_evt_nxt = 1'b0;
            reg_watch_evt_nxt = 1'b0;
            reg_term_evt_nxt  = 1'b0;
            reg_allow_nxt     = 1'b0;
            reg_reject_nxt    = 1'b0;
            reg_noresp_nxt    = 1'b0;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : classifier_register_update
        reg_cam_evt_f   <= reg_cam_evt_nxt;
        reg_match_evt_f <= reg_match_evt_nxt;
        reg_watch_evt_f <= reg_watch_evt_nxt;
        reg_term_evt_f  <= reg_term_evt_nxt;
        reg_allow_f     <= reg_allow_nxt;
        reg_reject_f    <= reg_reject_nxt;
        reg_noresp_f    <= reg_noresp_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign classify_valid_q = reg_term_evt_f;
    assign class_grant_q    = reg_allow_f;
    assign class_reject_q   = reg_reject_f;
    assign unresponsive_q   = reg_noresp_f;

`ifndef RF_SECURE_ID_SVA_OFF
`ifdef RF_SECURE_ID_SIMONLY

`include "sva/rf_secure_id_classifier_sva.sv"

`endif // RF_SECURE_ID_SIMONLY
`endif // RF_SECURE_ID_SVA_OFF

endmodule
