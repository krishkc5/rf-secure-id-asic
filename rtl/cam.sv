module cam #(
    parameter int ENTRY_WIDTH = 16,
    parameter int DEPTH = 8
) (
    input  logic                   clk,
    input  logic                   rst_n,
    input  logic                   decrypt_valid,
    input  logic                   decrypt_ok,
    input  logic [ENTRY_WIDTH-1:0] id,
    output logic                   lookup_valid,
    output logic                   id_hit,
    output logic [((DEPTH > 1) ? $clog2(DEPTH) : 1)-1:0] match_index,
    output logic                   multi_hit
);

  localparam int BUILT_IN_DEPTH = 4;
  localparam int ACTIVE_DEPTH   = (DEPTH < BUILT_IN_DEPTH) ? DEPTH : BUILT_IN_DEPTH;
  localparam int MATCH_INDEX_WIDTH = (DEPTH > 1) ? $clog2(DEPTH) : 1;
  localparam int MATCH_COUNT_WIDTH = $clog2(DEPTH + 1);

  localparam logic [ENTRY_WIDTH-1:0] BUILT_IN_ID_0 = ENTRY_WIDTH'(16'h1234);
  localparam logic [ENTRY_WIDTH-1:0] BUILT_IN_ID_1 = ENTRY_WIDTH'(16'h5678);
  localparam logic [ENTRY_WIDTH-1:0] BUILT_IN_ID_2 = ENTRY_WIDTH'(16'h9ABC);
  localparam logic [ENTRY_WIDTH-1:0] BUILT_IN_ID_3 = ENTRY_WIDTH'(16'hDEF0);

  logic [ENTRY_WIDTH-1:0] cam_entries_reg [0:DEPTH-1];
  logic                   cam_valid_reg   [0:DEPTH-1];

  logic lookup_valid_next;
  logic id_hit_next;
  logic [MATCH_INDEX_WIDTH-1:0] match_index_next;
  logic                         multi_hit_next;

  logic [DEPTH-1:0]             match_vector_comb;
  logic                         id_hit_comb;
  logic [MATCH_INDEX_WIDTH-1:0] match_index_comb;
  logic                         multi_hit_comb;
  logic [MATCH_COUNT_WIDTH-1:0] match_count_comb;

  int compare_idx;
  int init_idx;

  function automatic logic [ENTRY_WIDTH-1:0] get_built_in_id(input integer idx);
    begin
      unique case (idx)
        0:       get_built_in_id = BUILT_IN_ID_0;
        1:       get_built_in_id = BUILT_IN_ID_1;
        2:       get_built_in_id = BUILT_IN_ID_2;
        3:       get_built_in_id = BUILT_IN_ID_3;
        default: get_built_in_id = '0;
      endcase
    end
  endfunction

  always_comb begin
    match_vector_comb = '0;
    match_index_comb  = '0;
    match_count_comb  = '0;
    id_hit_comb = 1'b0;

    for (compare_idx = 0; compare_idx < DEPTH; compare_idx++) begin
      if (cam_valid_reg[compare_idx] && (id == cam_entries_reg[compare_idx])) begin
        if (!id_hit_comb) begin
          match_index_comb = MATCH_INDEX_WIDTH'(compare_idx);
        end

        match_vector_comb[compare_idx] = 1'b1;
        match_count_comb               = match_count_comb + 1'b1;
        id_hit_comb = 1'b1;
      end
    end

    multi_hit_comb = (match_count_comb > 1);

    lookup_valid_next = 1'b0;
    id_hit_next       = id_hit;
    match_index_next  = match_index;
    multi_hit_next    = multi_hit;

    if (decrypt_valid && decrypt_ok) begin
      lookup_valid_next = 1'b1;
      id_hit_next       = id_hit_comb;
      match_index_next  = match_index_comb;
      multi_hit_next    = multi_hit_comb;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (init_idx = 0; init_idx < DEPTH; init_idx++) begin
        cam_entries_reg[init_idx] <= '0;
        cam_valid_reg[init_idx]   <= 1'b0;
      end

      for (init_idx = 0; init_idx < ACTIVE_DEPTH; init_idx++) begin
        cam_entries_reg[init_idx] <= get_built_in_id(init_idx);
        cam_valid_reg[init_idx]   <= 1'b1;
      end

      lookup_valid <= 1'b0;
      id_hit       <= 1'b0;
      match_index  <= '0;
      multi_hit    <= 1'b0;
    end else begin
      lookup_valid <= lookup_valid_next;
      id_hit       <= id_hit_next;
      match_index  <= match_index_next;
      multi_hit    <= multi_hit_next;
    end
  end

endmodule
