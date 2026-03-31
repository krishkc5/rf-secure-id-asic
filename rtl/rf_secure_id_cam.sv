//=====================================================================================================
// Module: rf_secure_id_cam
// Function: Parallel-compare content-addressable memory used for recovered ID
//           lookup after plaintext validation.
//
// Parameters:
//   P_ENTRY_WIDTH : Width of each stored CAM entry. Valid range is >= 1.
//   P_DEPTH       : Number of CAM entries. Valid range is >= 1.
//
// Local Parameters:
//   LP_BOOT_DEPTH = Number of built-in tags available at reset.
//   LP_ACTIVE_DEPTH = Number of built-in tags actually used for current P_DEPTH.
//   LP_SLOT_WIDTH = Width of the first-match index output.
//   LP_TALLY_WIDTH = Width of the internal match counter.
//   LP_BOOT_TAG_* = Reset-loaded authorized tag constants.
//
// Ports:
//   core_clk     : Primary digital clock.
//   rst_n        : Active-low reset sampled in the module clock domain.
//   check_evt_i   : One-cycle pulse indicating ID input is valid.
//   check_pass_i  : Plaintext structure check result.
//   probe_tag_i   : Recovered ID presented to the CAM.
//   lookup_fire_q : One-cycle pulse indicating CAM result outputs are valid.
//   lookup_hit_q  : High when any valid CAM entry matches probe_tag_i.
//   lookup_slot_q : Index of the first matching CAM entry.
//   lookup_multi_q: High when more than one valid entry matches probe_tag_i.
//
// Functions:
//   function_get_boot_tag : Return the built-in tag value for a reset-loaded entry slot.
//
// Included Files:
//   None.
//
// State Variables:
//   reg_req_fire_f[0:0]              : Captured check_evt_i pulse, reset to 0.
//   reg_req_pass_f[0:0]              : Captured check_pass_i flag, reset to 0.
//   reg_probe_tag_f[P_ENTRY_WIDTH-1:0] : Captured probe_tag_i input, reset to 0.
//   reg_store_tag_f[P_DEPTH][P_ENTRY_WIDTH]: Register-based CAM storage, reset to built-in tags plus 0-fill.
//   reg_store_vld_f[P_DEPTH-1:0]     : Valid bitmap for CAM entries, reset to built-in valid map.
//   reg_rsp_fire_f[0:0]              : Registered lookup-valid pulse, reset to 0.
//   reg_rsp_match_f[0:0]             : Registered match flag, reset to 0.
//   reg_rsp_slot_f[LP_SLOT_WIDTH]    : Registered first-hit index, reset to 0.
//   reg_rsp_multi_f[0:0]             : Registered multi-hit flag, reset to 0.
//
// Reset Behavior:
//   Active-low reset reloads the built-in authorization set and clears any
//   captured request or response metadata before lookup resumes.
//
// Reset Rationale:
//   Input capture registers reset to 0 so stale validator events and IDs are discarded.
//   CAM storage and valid bits reset to the built-in authorization set so lookup behavior is
//   deterministic immediately after reset.
//   Output registers reset to 0 so no false lookup_fire_q pulse or stale hit metadata escapes reset.
//
// Sub-modules:
//   None.
//
// Clock / Reset:
//   core_clk : Single synchronous clock domain. Target integration frequency is 50 MHz.
//   rst_n    : Active-low reset applied through next-state reset logic.
//
// Timing:
//   TIMING_CRITICAL: Parallel compare across all P_DEPTH entries.
//   STA_CRITICAL   : ID compare tree and first-hit selection across the full CAM depth.
//   Throughput      : One lookup result per captured validator event.
//   Latency         : One cycle from captured validator inputs to registered lookup outputs.
//
// Synthesis Guidance:
//   Clock Source       : Primary 50 MHz system clock with nominal 50% duty cycle.
//   Constraints        : No internal false-path or multicycle exceptions are expected.
//   Interface Budget   : Inputs are captured at the boundary; result outputs are fully registered.
//   Resource Expectation: Register-based storage and parallel compare logic. Area scales with
//                         P_DEPTH * P_ENTRY_WIDTH and this block is the dominant non-AES lookup resource.
//                         Current Yosys sanity baseline at P_DEPTH=8 and P_ENTRY_WIDTH=16 is 31 local
//                         cells. This register-CAM architecture is the approved baseline for the active
//                         project configuration and should not be remapped to RAM/ROM.
//   Resource Estimate   : ~160 state bits at P_DEPTH=8 and P_ENTRY_WIDTH=16, 31 Yosys sanity
//                         cells, 0 RAMs, 0 DSPs, and ~2.1% of the 1466-cell top-level baseline.
//   Timing Margin      : Target >=10% post-route slack margin at the 50 MHz integration point.
//   Signoff Follow-up  : Gate-level simulation and RTL-to-netlist equivalence remain required
//                        final signoff activities outside this educational repo. Power and area
//                        review should focus on compare-tree switching and entry storage scaling.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock [get_clocks core_clk] 4.000 [get_ports {check_evt_i check_pass_i probe_tag_i[*]}]
//   set_output_delay -clock [get_clocks core_clk] 4.000
//                    [get_ports {lookup_fire_q lookup_hit_q lookup_slot_q[*] lookup_multi_q}]
//   No false-path or multicycle exceptions are expected for this block.
//
// Specification Reference:
//   CAM integration role and fixed built-in authorization-set behavior are
//   documented in docs/digital_pipeline_aes.md.
//
// ASCII Timing Sketch:
//   core_clk      : |0|1|2|
//   check_evt_i   :  1 0 0
//   lookup_fire_q :  0 1 0
//   lookup_hit_q  :  X valid on lookup_fire_q pulse
//
// Algorithm Summary:
//   Capture the recovered tag, compare it in parallel against the valid
//   reset-loaded entries, count matches, and return first-hit plus multi-hit metadata.
//
// Assumptions:
//   The active project baseline uses reset-loaded entries only and does not
//   perform runtime CAM updates.
//
// CRITICAL:
//   The current project baseline depends on a transparent register-based CAM.
//   Remapping to memory changes the ruled implementation model.
//
// LIMITATION:
//   CAM contents are reset-loaded only in this implementation; there is no
//   runtime update interface.
//
// Interface Reference:
//   Lookup semantics and built-in authorization-set behavior are documented in
//   docs/digital_pipeline_aes.md.
//=====================================================================================================
module rf_secure_id_cam #(
    parameter int P_ENTRY_WIDTH = 16,
    parameter int P_DEPTH = 8
) (
    input  logic                     core_clk,
    input  logic                     rst_n,
    input  logic                     check_evt_i,
    input  logic                     check_pass_i,
    input  logic [P_ENTRY_WIDTH-1:0] probe_tag_i,
    output logic                     lookup_fire_q,
    output logic                     lookup_hit_q,
    output logic [((P_DEPTH > 1) ? $clog2(P_DEPTH) : 1)-1:0] lookup_slot_q,
    output logic                     lookup_multi_q
);

    //========================================================================
    // Input capture, internal state, and output staging registers
    //========================================================================
    logic                     reg_req_fire_f, reg_req_fire_nxt;
    logic                     reg_req_pass_f, reg_req_pass_nxt;
    logic [P_ENTRY_WIDTH-1:0] reg_probe_tag_f, reg_probe_tag_nxt;

    logic [P_DEPTH-1:0][P_ENTRY_WIDTH-1:0] reg_store_tag_f, reg_store_tag_nxt;
    logic [P_DEPTH-1:0] reg_store_vld_f, reg_store_vld_nxt;

    logic reg_rsp_fire_f, reg_rsp_fire_nxt;
    logic reg_rsp_match_f, reg_rsp_match_nxt;
    logic [LP_SLOT_WIDTH-1:0] reg_rsp_slot_f, reg_rsp_slot_nxt;
    logic reg_rsp_multi_f, reg_rsp_multi_nxt;

    logic flag_any_match;
    logic [LP_SLOT_WIDTH-1:0] flag_first_slot;
    logic flag_multi_match;
    logic [LP_TALLY_WIDTH-1:0] ctr_match_tally;

    integer slot_iter;

    //========================================================================
    // Function definitions
    //========================================================================
    // function_get_boot_tag
    //   Purpose         : Map a reset-load slot index to a built-in CAM tag constant.
    //   Interoperability: Used only by reset initialization in cam_next_state_logic.
    //   Inputs          : slot_sel in the range [0, LP_BOOT_DEPTH - 1].
    //   Return          : Built-in tag value for the requested slot, or zero for default.
    //   Usage           : function_get_boot_tag(2)
    function automatic logic [P_ENTRY_WIDTH-1:0] function_get_boot_tag(input integer slot_sel);
        begin
            case (slot_sel)
                0:       function_get_boot_tag = LP_BOOT_TAG_0;
                1:       function_get_boot_tag = LP_BOOT_TAG_1;
                2:       function_get_boot_tag = LP_BOOT_TAG_2;
                3:       function_get_boot_tag = LP_BOOT_TAG_3;
                default: function_get_boot_tag = '0;
            endcase
        end
    endfunction

    //========================================================================
    // Local parameters
    //========================================================================
    localparam int LP_BOOT_DEPTH = 4;
    localparam int LP_ACTIVE_DEPTH = (P_DEPTH < LP_BOOT_DEPTH) ? P_DEPTH : LP_BOOT_DEPTH;
    localparam int LP_SLOT_WIDTH = (P_DEPTH > 1) ? $clog2(P_DEPTH) : 1;
    localparam int LP_TALLY_WIDTH = $clog2(P_DEPTH + 1);

    localparam logic [P_ENTRY_WIDTH-1:0] LP_BOOT_TAG_0 = P_ENTRY_WIDTH'(16'h1234);
    localparam logic [P_ENTRY_WIDTH-1:0] LP_BOOT_TAG_1 = P_ENTRY_WIDTH'(16'h5678);
    localparam logic [P_ENTRY_WIDTH-1:0] LP_BOOT_TAG_2 = P_ENTRY_WIDTH'(16'h9ABC);
    localparam logic [P_ENTRY_WIDTH-1:0] LP_BOOT_TAG_3 = P_ENTRY_WIDTH'(16'hDEF0);

    //========================================================================
    // Combinatorial next-state logic
    //========================================================================
    always_comb begin : cam_next_state_logic
        // Capture the validator outputs, preserve reset-loaded CAM contents,
        // and compute the next registered lookup result from the parallel compare.
        reg_req_fire_nxt  = check_evt_i;
        reg_req_pass_nxt  = check_pass_i;
        reg_probe_tag_nxt = probe_tag_i;

        reg_store_tag_nxt = reg_store_tag_f;
        reg_store_vld_nxt = reg_store_vld_f;

        flag_any_match = 1'b0;
        flag_first_slot = '0;
        ctr_match_tally = '0;

        for (slot_iter = 0; slot_iter < P_DEPTH; slot_iter = slot_iter + 1) begin
            if (reg_store_vld_f[slot_iter] && (reg_probe_tag_f == reg_store_tag_f[slot_iter])) begin
                if (!flag_any_match) begin
                    flag_first_slot = LP_SLOT_WIDTH'(slot_iter);
                end

                ctr_match_tally = ctr_match_tally + 1'b1;
                flag_any_match  = 1'b1;
            end
        end

        flag_multi_match = (ctr_match_tally > 1);

        reg_rsp_fire_nxt  = 1'b0;
        reg_rsp_match_nxt = reg_rsp_match_f;
        reg_rsp_slot_nxt  = reg_rsp_slot_f;
        reg_rsp_multi_nxt = reg_rsp_multi_f;

        if (reg_req_fire_f && reg_req_pass_f) begin
            reg_rsp_fire_nxt  = 1'b1;
            reg_rsp_match_nxt = flag_any_match;
            reg_rsp_slot_nxt  = flag_first_slot;
            reg_rsp_multi_nxt = flag_multi_match;
        end

        if (!rst_n) begin
            reg_req_fire_nxt  = 1'b0;
            reg_req_pass_nxt  = 1'b0;
            reg_probe_tag_nxt = '0;
            reg_store_tag_nxt = '0;
            reg_store_vld_nxt = '0;

            if (LP_ACTIVE_DEPTH > 0) begin
                reg_store_tag_nxt[0] = LP_BOOT_TAG_0;
                reg_store_vld_nxt[0] = 1'b1;
            end

            if (LP_ACTIVE_DEPTH > 1) begin
                reg_store_tag_nxt[1] = LP_BOOT_TAG_1;
                reg_store_vld_nxt[1] = 1'b1;
            end

            if (LP_ACTIVE_DEPTH > 2) begin
                reg_store_tag_nxt[2] = LP_BOOT_TAG_2;
                reg_store_vld_nxt[2] = 1'b1;
            end

            if (LP_ACTIVE_DEPTH > 3) begin
                reg_store_tag_nxt[3] = LP_BOOT_TAG_3;
                reg_store_vld_nxt[3] = 1'b1;
            end

            reg_rsp_fire_nxt  = 1'b0;
            reg_rsp_match_nxt = 1'b0;
            reg_rsp_slot_nxt  = '0;
            reg_rsp_multi_nxt = 1'b0;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : cam_register_update
        reg_req_fire_f  <= reg_req_fire_nxt;
        reg_req_pass_f  <= reg_req_pass_nxt;
        reg_probe_tag_f <= reg_probe_tag_nxt;
        reg_store_tag_f <= reg_store_tag_nxt;
        reg_store_vld_f <= reg_store_vld_nxt;
        reg_rsp_fire_f  <= reg_rsp_fire_nxt;
        reg_rsp_match_f <= reg_rsp_match_nxt;
        reg_rsp_slot_f  <= reg_rsp_slot_nxt;
        reg_rsp_multi_f <= reg_rsp_multi_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign lookup_fire_q  = reg_rsp_fire_f;
    assign lookup_hit_q   = reg_rsp_match_f;
    assign lookup_slot_q  = reg_rsp_slot_f;
    assign lookup_multi_q = reg_rsp_multi_f;

endmodule
