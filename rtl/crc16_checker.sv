module crc16_checker (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         parsed_valid,
    input  logic [7:0]   packet_type,
    input  logic [127:0] ciphertext,
    input  logic [15:0]  crc_rx,
    output logic         crc_valid,
    output logic         crc_ok,
    output logic [15:0]  crc_calc
);

  localparam int DATA_WIDTH = 136;
  localparam logic [15:0] CRC_POLY = 16'h1021;

  logic        crc_valid_next;
  logic        crc_ok_next;
  logic [15:0] crc_calc_next;
  logic [15:0] crc_calc_comb;

  function automatic logic [15:0] calc_crc16(input logic [DATA_WIDTH-1:0] data_in);
    logic [15:0] crc;
    logic        feedback;
    int          bit_idx;
    begin
      crc = 16'h0000;

      for (bit_idx = DATA_WIDTH - 1; bit_idx >= 0; bit_idx--) begin
        feedback = crc[15] ^ data_in[bit_idx];
        crc = {crc[14:0], 1'b0};

        if (feedback) begin
          crc ^= CRC_POLY;
        end
      end

      return crc;
    end
  endfunction

  always_comb begin
    crc_calc_comb = calc_crc16({packet_type, ciphertext});

    crc_valid_next = 1'b0;
    crc_ok_next    = crc_ok;
    crc_calc_next  = crc_calc;

    if (parsed_valid) begin
      crc_valid_next = 1'b1;
      crc_ok_next    = (crc_calc_comb == crc_rx);
      crc_calc_next  = crc_calc_comb;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      crc_valid <= 1'b0;
      crc_ok    <= 1'b0;
      crc_calc  <= '0;
    end else begin
      crc_valid <= crc_valid_next;
      crc_ok    <= crc_ok_next;
      crc_calc  <= crc_calc_next;
    end
  end

endmodule
