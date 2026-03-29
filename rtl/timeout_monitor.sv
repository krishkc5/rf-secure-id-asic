module timeout_monitor #(
    parameter int TIMEOUT_CYCLES = 32
) (
    input  logic clk,
    input  logic rst_n,
    input  logic start,
    input  logic done,
    output logic timeout_valid
);

  localparam int COUNT_WIDTH = $clog2(TIMEOUT_CYCLES + 1);

  logic                    active_reg;
  logic                    active_next;
  logic [COUNT_WIDTH-1:0]  counter_reg;
  logic [COUNT_WIDTH-1:0]  counter_next;
  logic                    timeout_valid_next;

  always_comb begin
    active_next        = active_reg;
    counter_next       = counter_reg;
    timeout_valid_next = 1'b0;

    if (active_reg) begin
      if (done) begin
        active_next  = 1'b0;
        counter_next = '0;
      end else if (counter_reg == 1) begin
        active_next        = 1'b0;
        counter_next       = '0;
        timeout_valid_next = 1'b1;
      end else begin
        counter_next = counter_reg - 1'b1;
      end
    end else if (start) begin
      active_next  = 1'b1;
      counter_next = COUNT_WIDTH'(TIMEOUT_CYCLES);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active_reg     <= 1'b0;
      counter_reg    <= '0;
      timeout_valid  <= 1'b0;
    end else begin
      active_reg     <= active_next;
      counter_reg    <= counter_next;
      timeout_valid  <= timeout_valid_next;
    end
  end

endmodule
