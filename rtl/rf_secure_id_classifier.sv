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
//   lookup_valid   : One-cycle pulse indicating a completed CAM lookup.
//   id_hit         : CAM match result for the lookup event.
//   timeout_valid  : One-cycle pulse indicating the request timed out.
//   classify_valid : One-cycle pulse indicating a terminal classification.
//   authorized     : High for authorized classification.
//   unauthorized   : High for unauthorized classification.
//   unresponsive   : High for timeout / unresponsive classification.
//
// Functions:
//   None.
//
// State Variables:
//   reg_lookup_valid_in_f[0:0]  : One-stage capture register for lookup_valid. Reset default = 1'b0.
//   reg_id_hit_in_f[0:0]        : One-stage capture register for id_hit. Reset default = 1'b0.
//   reg_timeout_valid_in_f[0:0] : One-stage capture register for timeout_valid. Reset default = 1'b0.
//   reg_classify_valid_f[0:0]   : Registered classification-valid pulse. Reset default = 1'b0.
//   reg_authorized_f[0:0]       : Registered authorized output. Reset default = 1'b0.
//   reg_unauthorized_f[0:0]     : Registered unauthorized output. Reset default = 1'b0.
//   reg_unresponsive_f[0:0]     : Registered unresponsive output. Reset default = 1'b0.
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
//   Interface Budget   : lookup_valid, id_hit, and timeout_valid are captured at the boundary;
//                        all outputs are registered.
//   Resource Expectation: Small control-only block; no memories or DSP resources.
//   Signoff Follow-up  : Gate-level simulation and RTL-to-netlist equivalence remain required
//                        final signoff activities outside this educational repo.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock core_clk <integration_defined> [get_ports {lookup_valid id_hit timeout_valid}]
//   set_output_delay -clock core_clk <integration_defined> [get_ports {classify_valid authorized unauthorized unresponsive}]
//   No false-path or multicycle exceptions are expected for this module.
//
// Assumptions:
//   lookup_valid has priority over timeout_valid if both are asserted
//   together in the same cycle.
//
// LIMITATION:
//   The classifier resolves only mutually exclusive terminal status and does
//   not retain historical event context after the output pulse cycle.
//=====================================================================================================
module rf_secure_id_classifier (
    input  logic core_clk,
    input  logic rst_n,
    input  logic lookup_valid,
    input  logic id_hit,
    input  logic timeout_valid,
    output logic classify_valid,
    output logic authorized,
    output logic unauthorized,
    output logic unresponsive
);

    //========================================================================
    // Input capture and output staging registers
    //========================================================================
    logic reg_lookup_valid_in_f;
    logic reg_lookup_valid_in_nxt;
    logic reg_id_hit_in_f;
    logic reg_id_hit_in_nxt;
    logic reg_timeout_valid_in_f;
    logic reg_timeout_valid_in_nxt;

    logic reg_classify_valid_f;
    logic reg_classify_valid_nxt;
    logic reg_authorized_f;
    logic reg_authorized_nxt;
    logic reg_unauthorized_f;
    logic reg_unauthorized_nxt;
    logic reg_unresponsive_f;
    logic reg_unresponsive_nxt;

    //========================================================================
    // Combinatorial next-state logic
    //========================================================================
    always_comb begin : classifier_next_state_logic
        // Capture terminal event inputs and compute the next registered
        // classification outputs with lookup taking priority over timeout.
        reg_lookup_valid_in_nxt  = lookup_valid;
        reg_id_hit_in_nxt        = id_hit;
        reg_timeout_valid_in_nxt = timeout_valid;

        reg_classify_valid_nxt = 1'b0;
        reg_authorized_nxt     = reg_authorized_f;
        reg_unauthorized_nxt   = reg_unauthorized_f;
        reg_unresponsive_nxt   = reg_unresponsive_f;

        if (reg_lookup_valid_in_f) begin
            reg_classify_valid_nxt = 1'b1;
            reg_authorized_nxt     = reg_id_hit_in_f;
            reg_unauthorized_nxt   = ~reg_id_hit_in_f;
            reg_unresponsive_nxt   = 1'b0;
        end else if (reg_timeout_valid_in_f) begin
            reg_classify_valid_nxt = 1'b1;
            reg_authorized_nxt     = 1'b0;
            reg_unauthorized_nxt   = 1'b0;
            reg_unresponsive_nxt   = 1'b1;
        end

        if (!rst_n) begin
            reg_lookup_valid_in_nxt  = 1'b0;
            reg_id_hit_in_nxt        = 1'b0;
            reg_timeout_valid_in_nxt = 1'b0;
            reg_classify_valid_nxt = 1'b0;
            reg_authorized_nxt     = 1'b0;
            reg_unauthorized_nxt   = 1'b0;
            reg_unresponsive_nxt   = 1'b0;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : classifier_register_update
        reg_lookup_valid_in_f  <= reg_lookup_valid_in_nxt;
        reg_id_hit_in_f        <= reg_id_hit_in_nxt;
        reg_timeout_valid_in_f <= reg_timeout_valid_in_nxt;
        reg_classify_valid_f <= reg_classify_valid_nxt;
        reg_authorized_f     <= reg_authorized_nxt;
        reg_unauthorized_f   <= reg_unauthorized_nxt;
        reg_unresponsive_f   <= reg_unresponsive_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign classify_valid = reg_classify_valid_f;
    assign authorized     = reg_authorized_f;
    assign unauthorized   = reg_unauthorized_f;
    assign unresponsive   = reg_unresponsive_f;

`ifndef RF_SECURE_ID_SVA_OFF
`ifdef RF_SECURE_ID_SIMONLY

`include "sva/rf_secure_id_classifier_sva.sv"

`endif // RF_SECURE_ID_SIMONLY
`endif // RF_SECURE_ID_SVA_OFF

endmodule
