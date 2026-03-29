module packet_rx (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         serial_bit,
    output logic         packet_valid,
    output logic [159:0] packet_data
);

  localparam int PACKET_WIDTH   = 160;
  localparam int PREAMBLE_WIDTH = 8;
  localparam int PAYLOAD_WIDTH  = PACKET_WIDTH - PREAMBLE_WIDTH;
  localparam int COUNT_WIDTH    = $clog2(PAYLOAD_WIDTH + 1);

  localparam logic [PREAMBLE_WIDTH-1:0] PREAMBLE = 8'hA5;

  typedef enum logic {
    STATE_SEARCH,
    STATE_CAPTURE
  } state_t;

  state_t state_reg;
  state_t state_next;

  logic [PREAMBLE_WIDTH-1:0] preamble_shift_reg;
  logic [PREAMBLE_WIDTH-1:0] preamble_shift_next;
  logic [PAYLOAD_WIDTH-1:0]  payload_shift_reg;
  logic [PAYLOAD_WIDTH-1:0]  payload_shift_next;
  logic [COUNT_WIDTH-1:0]    bits_remaining_reg;
  logic [COUNT_WIDTH-1:0]    bits_remaining_next;
  logic                      packet_valid_next;
  logic [PACKET_WIDTH-1:0]   packet_data_next;

  always_comb begin
    state_next          = state_reg;
    preamble_shift_next = preamble_shift_reg;
    payload_shift_next  = payload_shift_reg;
    bits_remaining_next = bits_remaining_reg;
    packet_valid_next   = 1'b0;
    packet_data_next    = packet_data;

    unique case (state_reg)
      STATE_SEARCH: begin
        preamble_shift_next = {preamble_shift_reg[PREAMBLE_WIDTH-2:0], serial_bit};

        if (preamble_shift_next == PREAMBLE) begin
          state_next          = STATE_CAPTURE;
          payload_shift_next  = '0;
          bits_remaining_next = COUNT_WIDTH'(PAYLOAD_WIDTH);
        end
      end

      STATE_CAPTURE: begin
        payload_shift_next = {payload_shift_reg[PAYLOAD_WIDTH-2:0], serial_bit};

        if (bits_remaining_reg == 1) begin
          state_next          = STATE_SEARCH;
          preamble_shift_next = '0;
          bits_remaining_next = '0;
          packet_valid_next   = 1'b1;
          packet_data_next    = {PREAMBLE, payload_shift_next};
        end else begin
          bits_remaining_next = bits_remaining_reg - 1'b1;
        end
      end

      default: begin
        state_next          = STATE_SEARCH;
        preamble_shift_next = '0;
        payload_shift_next  = '0;
        bits_remaining_next = '0;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_reg          <= STATE_SEARCH;
      preamble_shift_reg <= '0;
      payload_shift_reg  <= '0;
      bits_remaining_reg <= '0;
      packet_valid       <= 1'b0;
      packet_data        <= '0;
    end else begin
      state_reg          <= state_next;
      preamble_shift_reg <= preamble_shift_next;
      payload_shift_reg  <= payload_shift_next;
      bits_remaining_reg <= bits_remaining_next;
      packet_valid       <= packet_valid_next;
      packet_data        <= packet_data_next;
    end
  end

endmodule
