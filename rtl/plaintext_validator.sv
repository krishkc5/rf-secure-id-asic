module plaintext_validator (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         plaintext_valid,
    input  logic [127:0] plaintext,
    output logic         decrypt_valid,
    output logic         decrypt_ok,
    output logic [15:0]  id
);

  localparam logic [15:0] PLAIN_MAGIC = 16'hC35A;

  localparam int MAGIC_MSB    = 127;
  localparam int MAGIC_LSB    = 112;
  localparam int ID_MSB       = 111;
  localparam int ID_LSB       = 96;
  localparam int RESERVED_MSB = 95;
  localparam int RESERVED_LSB = 0;

  logic        decrypt_valid_next;
  logic        decrypt_ok_next;
  logic [15:0] id_next;
  logic        magic_ok;
  logic        reserved_ok;

  always_comb begin
    magic_ok    = (plaintext[MAGIC_MSB:MAGIC_LSB] == PLAIN_MAGIC);
    reserved_ok = (plaintext[RESERVED_MSB:RESERVED_LSB] == 96'h0);

    decrypt_valid_next = 1'b0;
    decrypt_ok_next    = decrypt_ok;
    id_next            = id;

    if (plaintext_valid) begin
      decrypt_valid_next = 1'b1;
      decrypt_ok_next    = magic_ok && reserved_ok;
      id_next            = plaintext[ID_MSB:ID_LSB];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      decrypt_valid <= 1'b0;
      decrypt_ok    <= 1'b0;
      id            <= '0;
    end else begin
      decrypt_valid <= decrypt_valid_next;
      decrypt_ok    <= decrypt_ok_next;
      id            <= id_next;
    end
  end

endmodule
