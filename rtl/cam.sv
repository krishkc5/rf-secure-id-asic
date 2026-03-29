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
    output logic                   id_hit
);

  localparam int BUILT_IN_DEPTH = 4;
  localparam int ACTIVE_DEPTH   = (DEPTH < BUILT_IN_DEPTH) ? DEPTH : BUILT_IN_DEPTH;

  localparam logic [ENTRY_WIDTH-1:0] BUILT_IN_IDS [0:BUILT_IN_DEPTH-1] = '{
      ENTRY_WIDTH'(16'h1234),
      ENTRY_WIDTH'(16'h5678),
      ENTRY_WIDTH'(16'h9ABC),
      ENTRY_WIDTH'(16'hDEF0)
  };

  logic [ENTRY_WIDTH-1:0] cam_entries_reg [0:DEPTH-1];
  logic                   cam_valid_reg   [0:DEPTH-1];

  logic lookup_valid_next;
  logic id_hit_next;
  logic id_hit_comb;

  int compare_idx;
  int init_idx;

  always_comb begin
    id_hit_comb = 1'b0;

    for (compare_idx = 0; compare_idx < DEPTH; compare_idx++) begin
      if (cam_valid_reg[compare_idx] && (id == cam_entries_reg[compare_idx])) begin
        id_hit_comb = 1'b1;
      end
    end

    lookup_valid_next = 1'b0;
    id_hit_next       = id_hit;

    if (decrypt_valid && decrypt_ok) begin
      lookup_valid_next = 1'b1;
      id_hit_next       = id_hit_comb;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (init_idx = 0; init_idx < DEPTH; init_idx++) begin
        cam_entries_reg[init_idx] <= '0;
        cam_valid_reg[init_idx]   <= 1'b0;
      end

      for (init_idx = 0; init_idx < ACTIVE_DEPTH; init_idx++) begin
        cam_entries_reg[init_idx] <= BUILT_IN_IDS[init_idx];
        cam_valid_reg[init_idx]   <= 1'b1;
      end

      lookup_valid <= 1'b0;
      id_hit       <= 1'b0;
    end else begin
      lookup_valid <= lookup_valid_next;
      id_hit       <= id_hit_next;
    end
  end

endmodule
