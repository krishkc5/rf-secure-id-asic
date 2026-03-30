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
//   LP_BUILT_IN_DEPTH    = Number of built-in IDs available at reset.
//   LP_ACTIVE_DEPTH      = Number of built-in IDs actually used for current P_DEPTH.
//   LP_MATCH_INDEX_WIDTH = Width of the first-match index output.
//   LP_MATCH_COUNT_WIDTH = Width of the internal match counter.
//   LP_BUILT_IN_ID_*     = Reset-loaded authorized ID constants.
//
// Ports:
//   core_clk     : Primary digital clock.
//   rst_n        : Active-low reset sampled in the module clock domain.
//   decrypt_valid: One-cycle pulse indicating ID input is valid.
//   decrypt_ok   : Plaintext structure check result.
//   id           : Recovered ID presented to the CAM.
//   lookup_valid : One-cycle pulse indicating CAM result outputs are valid.
//   id_hit       : High when any valid CAM entry matches id.
//   match_index  : Index of the first matching CAM entry.
//   multi_hit    : High when more than one CAM entry matches id.
//
// Functions:
//   function_get_built_in_id : Return the built-in ID value for a reset-loaded entry slot.
//
// State Variables:
//   reg_decrypt_valid_in_f[0:0]              : Captured decrypt_valid pulse, reset to 0.
//   reg_decrypt_ok_in_f[0:0]                 : Captured decrypt_ok flag, reset to 0.
//   reg_id_in_f[P_ENTRY_WIDTH-1:0]           : Captured ID input, reset to 0.
//   reg_cam_entries_f[P_DEPTH][P_ENTRY_WIDTH]: Register-based CAM storage, reset to built-in IDs plus 0-fill.
//   reg_cam_valid_f[P_DEPTH-1:0]             : Valid bitmap for CAM entries, reset to built-in valid map.
//   reg_lookup_valid_f[0:0]                  : Registered lookup-valid pulse, reset to 0.
//   reg_id_hit_f[0:0]                        : Registered match flag, reset to 0.
//   reg_match_index_f[LP_MATCH_INDEX_WIDTH]  : Registered first-hit index, reset to 0.
//   reg_multi_hit_f[0:0]                     : Registered multi-hit flag, reset to 0.
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
//                         No external memory macro is instantiated in this educational implementation.
//   Timing Margin      : Target >=10% post-route slack margin at the 50 MHz integration point.
//   Signoff Follow-up  : Gate-level simulation and RTL-to-netlist equivalence remain required
//                        final signoff activities outside this educational repo. Power and area
//                        review should focus on compare-tree switching and entry storage scaling.
//
// Constraint Template:
//   create_clock -name core_clk -period 20.000 [get_ports core_clk]
//   set_input_delay  -clock [get_clocks core_clk] 4.000 [get_ports {decrypt_valid decrypt_ok id[*]}]
//   set_output_delay -clock [get_clocks core_clk] 4.000 [get_ports {lookup_valid id_hit match_index[*] multi_hit}]
//   No false-path or multicycle exceptions are expected for this block.
//
// LIMITATION:
//   CAM contents are reset-loaded only in this implementation; there is no
//   runtime update interface.
//=====================================================================================================
module rf_secure_id_cam #(
    parameter int P_ENTRY_WIDTH = 16,
    parameter int P_DEPTH = 8
) (
    input  logic                     core_clk,
    input  logic                     rst_n,
    input  logic                     decrypt_valid,
    input  logic                     decrypt_ok,
    input  logic [P_ENTRY_WIDTH-1:0] id,
    output logic                     lookup_valid,
    output logic                     id_hit,
    output logic [((P_DEPTH > 1) ? $clog2(P_DEPTH) : 1)-1:0] match_index,
    output logic                     multi_hit
);

    //========================================================================
    // Input capture, internal state, and output staging registers
    //========================================================================
    logic reg_decrypt_valid_in_f;
    logic reg_decrypt_valid_in_nxt;
    logic reg_decrypt_ok_in_f;
    logic reg_decrypt_ok_in_nxt;
    logic [P_ENTRY_WIDTH-1:0] reg_id_in_f;
    logic [P_ENTRY_WIDTH-1:0] reg_id_in_nxt;

    logic [P_DEPTH-1:0][P_ENTRY_WIDTH-1:0] reg_cam_entries_f;
    logic [P_DEPTH-1:0][P_ENTRY_WIDTH-1:0] reg_cam_entries_nxt;
    logic [P_DEPTH-1:0] reg_cam_valid_f;
    logic [P_DEPTH-1:0] reg_cam_valid_nxt;

    logic reg_lookup_valid_f;
    logic reg_lookup_valid_nxt;
    logic reg_id_hit_f;
    logic reg_id_hit_nxt;
    logic [LP_MATCH_INDEX_WIDTH-1:0] reg_match_index_f;
    logic [LP_MATCH_INDEX_WIDTH-1:0] reg_match_index_nxt;
    logic reg_multi_hit_f;
    logic reg_multi_hit_nxt;

    logic id_hit_comb;
    logic [LP_MATCH_INDEX_WIDTH-1:0] match_index_comb;
    logic multi_hit_comb;
    logic [LP_MATCH_COUNT_WIDTH-1:0] match_count_comb;

    integer compare_idx;

    //========================================================================
    // Function definitions
    //========================================================================
    // function_get_built_in_id
    //   Purpose         : Map a reset-load slot index to a built-in CAM ID constant.
    //   Interoperability: Used only by reset initialization in cam_next_state_logic.
    //   Inputs          : idx in the range [0, LP_BUILT_IN_DEPTH - 1].
    //   Return          : Built-in ID value for the requested slot, or zero for default.
    //   Usage           : function_get_built_in_id(2)
    function automatic logic [P_ENTRY_WIDTH-1:0] function_get_built_in_id(input integer idx);
        begin
            case (idx)
                0:       function_get_built_in_id = LP_BUILT_IN_ID_0;
                1:       function_get_built_in_id = LP_BUILT_IN_ID_1;
                2:       function_get_built_in_id = LP_BUILT_IN_ID_2;
                3:       function_get_built_in_id = LP_BUILT_IN_ID_3;
                default: function_get_built_in_id = '0;
            endcase
        end
    endfunction

    //========================================================================
    // Local parameters
    //========================================================================
    localparam int LP_BUILT_IN_DEPTH    = 4;
    localparam int LP_ACTIVE_DEPTH      = (P_DEPTH < LP_BUILT_IN_DEPTH) ? P_DEPTH : LP_BUILT_IN_DEPTH;
    localparam int LP_MATCH_INDEX_WIDTH = (P_DEPTH > 1) ? $clog2(P_DEPTH) : 1;
    localparam int LP_MATCH_COUNT_WIDTH = $clog2(P_DEPTH + 1);

    localparam logic [P_ENTRY_WIDTH-1:0] LP_BUILT_IN_ID_0 = P_ENTRY_WIDTH'(16'h1234);
    localparam logic [P_ENTRY_WIDTH-1:0] LP_BUILT_IN_ID_1 = P_ENTRY_WIDTH'(16'h5678);
    localparam logic [P_ENTRY_WIDTH-1:0] LP_BUILT_IN_ID_2 = P_ENTRY_WIDTH'(16'h9ABC);
    localparam logic [P_ENTRY_WIDTH-1:0] LP_BUILT_IN_ID_3 = P_ENTRY_WIDTH'(16'hDEF0);

    //========================================================================
    // Combinatorial next-state logic
    //========================================================================
    always_comb begin : cam_next_state_logic
        // Capture the validator outputs, preserve reset-loaded CAM contents,
        // and compute the next registered lookup result from the parallel compare.
        reg_decrypt_valid_in_nxt = decrypt_valid;
        reg_decrypt_ok_in_nxt    = decrypt_ok;
        reg_id_in_nxt            = id;

        reg_cam_entries_nxt = reg_cam_entries_f;
        reg_cam_valid_nxt   = reg_cam_valid_f;

        id_hit_comb      = 1'b0;
        match_index_comb = '0;
        match_count_comb = '0;

        for (compare_idx = 0; compare_idx < P_DEPTH; compare_idx = compare_idx + 1) begin
            if (reg_cam_valid_f[compare_idx] && (reg_id_in_f == reg_cam_entries_f[compare_idx])) begin
                if (!id_hit_comb) begin
                    match_index_comb = LP_MATCH_INDEX_WIDTH'(compare_idx);
                end

                match_count_comb = match_count_comb + 1'b1;
                id_hit_comb      = 1'b1;
            end
        end

        multi_hit_comb = (match_count_comb > 1);

        reg_lookup_valid_nxt = 1'b0;
        reg_id_hit_nxt       = reg_id_hit_f;
        reg_match_index_nxt  = reg_match_index_f;
        reg_multi_hit_nxt    = reg_multi_hit_f;

        if (reg_decrypt_valid_in_f && reg_decrypt_ok_in_f) begin
            reg_lookup_valid_nxt = 1'b1;
            reg_id_hit_nxt       = id_hit_comb;
            reg_match_index_nxt  = match_index_comb;
            reg_multi_hit_nxt    = multi_hit_comb;
        end

        if (!rst_n) begin
            reg_decrypt_valid_in_nxt = 1'b0;
            reg_decrypt_ok_in_nxt    = 1'b0;
            reg_id_in_nxt            = '0;
            reg_cam_entries_nxt = '0;
            reg_cam_valid_nxt   = '0;

            if (LP_ACTIVE_DEPTH > 0) begin
                reg_cam_entries_nxt[0] = LP_BUILT_IN_ID_0;
                reg_cam_valid_nxt[0]   = 1'b1;
            end

            if (LP_ACTIVE_DEPTH > 1) begin
                reg_cam_entries_nxt[1] = LP_BUILT_IN_ID_1;
                reg_cam_valid_nxt[1]   = 1'b1;
            end

            if (LP_ACTIVE_DEPTH > 2) begin
                reg_cam_entries_nxt[2] = LP_BUILT_IN_ID_2;
                reg_cam_valid_nxt[2]   = 1'b1;
            end

            if (LP_ACTIVE_DEPTH > 3) begin
                reg_cam_entries_nxt[3] = LP_BUILT_IN_ID_3;
                reg_cam_valid_nxt[3]   = 1'b1;
            end

            reg_lookup_valid_nxt = 1'b0;
            reg_id_hit_nxt       = 1'b0;
            reg_match_index_nxt  = '0;
            reg_multi_hit_nxt    = 1'b0;
        end
    end

    //========================================================================
    // Sequential register update
    //========================================================================
    always_ff @(posedge core_clk) begin : cam_register_update
        reg_decrypt_valid_in_f <= reg_decrypt_valid_in_nxt;
        reg_decrypt_ok_in_f    <= reg_decrypt_ok_in_nxt;
        reg_id_in_f            <= reg_id_in_nxt;
        reg_cam_entries_f  <= reg_cam_entries_nxt;
        reg_cam_valid_f    <= reg_cam_valid_nxt;
        reg_lookup_valid_f <= reg_lookup_valid_nxt;
        reg_id_hit_f       <= reg_id_hit_nxt;
        reg_match_index_f  <= reg_match_index_nxt;
        reg_multi_hit_f    <= reg_multi_hit_nxt;
    end

    //========================================================================
    // Registered outputs
    //========================================================================
    assign lookup_valid = reg_lookup_valid_f;
    assign id_hit       = reg_id_hit_f;
    assign match_index  = reg_match_index_f;
    assign multi_hit    = reg_multi_hit_f;

endmodule
