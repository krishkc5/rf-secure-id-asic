module classifier (
    input  logic clk,
    input  logic rst_n,
    input  logic lookup_valid,
    input  logic id_hit,
    input  logic timeout_valid,
    output logic classify_valid,
    output logic authorized,
    output logic unauthorized,
    output logic unresponsive
);

  logic classify_valid_next;
  logic authorized_next;
  logic unauthorized_next;
  logic unresponsive_next;

  always_comb begin
    classify_valid_next = 1'b0;
    authorized_next     = authorized;
    unauthorized_next   = unauthorized;
    unresponsive_next   = unresponsive;

    if (lookup_valid) begin
      classify_valid_next = 1'b1;
      authorized_next     = id_hit;
      unauthorized_next   = ~id_hit;
      unresponsive_next   = 1'b0;
    end else if (timeout_valid) begin
      classify_valid_next = 1'b1;
      authorized_next     = 1'b0;
      unauthorized_next   = 1'b0;
      unresponsive_next   = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      classify_valid <= 1'b0;
      authorized     <= 1'b0;
      unauthorized   <= 1'b0;
      unresponsive   <= 1'b0;
    end else begin
      classify_valid <= classify_valid_next;
      authorized     <= authorized_next;
      unauthorized   <= unauthorized_next;
      unresponsive   <= unresponsive_next;
    end
  end

endmodule
