module packet_parser (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         packet_valid,
    input  logic [159:0] packet_data,
    output logic         parsed_valid,
    output logic [7:0]   packet_type,
    output logic [127:0] ciphertext,
    output logic [15:0]  crc_rx
);

  localparam int PACKET_TYPE_MSB = 151;
  localparam int PACKET_TYPE_LSB = 144;
  localparam int CIPHERTEXT_MSB  = 143;
  localparam int CIPHERTEXT_LSB  = 16;
  localparam int CRC_MSB         = 15;
  localparam int CRC_LSB         = 0;

  logic         parsed_valid_next;
  logic [7:0]   packet_type_next;
  logic [127:0] ciphertext_next;
  logic [15:0]  crc_rx_next;

  always_comb begin
    parsed_valid_next = 1'b0;
    packet_type_next  = packet_type;
    ciphertext_next   = ciphertext;
    crc_rx_next       = crc_rx;

    if (packet_valid) begin
      parsed_valid_next = 1'b1;
      packet_type_next  = packet_data[PACKET_TYPE_MSB:PACKET_TYPE_LSB];
      ciphertext_next   = packet_data[CIPHERTEXT_MSB:CIPHERTEXT_LSB];
      crc_rx_next       = packet_data[CRC_MSB:CRC_LSB];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      parsed_valid <= 1'b0;
      packet_type  <= '0;
      ciphertext   <= '0;
      crc_rx       <= '0;
    end else begin
      parsed_valid <= parsed_valid_next;
      packet_type  <= packet_type_next;
      ciphertext   <= ciphertext_next;
      crc_rx       <= crc_rx_next;
    end
  end

endmodule
