module rf_secure_id_digital_timeout4 (
    input  logic clk,
    input  logic rst_n,
    input  logic serial_bit,
    output logic classify_valid,
    output logic authorized,
    output logic unauthorized,
    output logic unresponsive
);

  logic rst_sync_ff1;
  logic rst_sync_ff2;
  logic rst_n_sync;

  logic         rx_packet_valid;
  logic [159:0] rx_packet_data;

  logic         parsed_valid_int;
  logic [7:0]   packet_type_int;
  logic [127:0] ciphertext_int;
  logic [15:0]  crc_rx_int;

  logic         crc_valid_int;
  logic         crc_ok_int;
  logic         cipher_valid_int;

  logic         plaintext_valid_int;
  logic [127:0] plaintext_int;

  logic        decrypt_valid_int;
  logic        decrypt_ok_int;
  logic [15:0] id_int;

  logic lookup_valid_int;
  logic id_hit_int;
  logic timeout_valid_int;

  assign rst_n_sync      = rst_sync_ff2;
  assign cipher_valid_int = crc_valid_int && crc_ok_int;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rst_sync_ff1 <= 1'b0;
      rst_sync_ff2 <= 1'b0;
    end else begin
      rst_sync_ff1 <= 1'b1;
      rst_sync_ff2 <= rst_sync_ff1;
    end
  end

  packet_rx u_packet_rx (
      .clk         (clk),
      .rst_n       (rst_n_sync),
      .serial_bit  (serial_bit),
      .packet_valid(rx_packet_valid),
      .packet_data (rx_packet_data)
  );

  packet_parser u_packet_parser (
      .clk         (clk),
      .rst_n       (rst_n_sync),
      .packet_valid(rx_packet_valid),
      .packet_data (rx_packet_data),
      .parsed_valid(parsed_valid_int),
      .packet_type (packet_type_int),
      .ciphertext  (ciphertext_int),
      .crc_rx      (crc_rx_int)
  );

  crc16_checker u_crc16_checker (
      .clk         (clk),
      .rst_n       (rst_n_sync),
      .parsed_valid(parsed_valid_int),
      .packet_type (packet_type_int),
      .ciphertext  (ciphertext_int),
      .crc_rx      (crc_rx_int),
      .crc_valid   (crc_valid_int),
      .crc_ok      (crc_ok_int),
      .crc_calc    ()
  );

  aes_decrypt u_aes_decrypt (
      .clk            (clk),
      .rst_n          (rst_n_sync),
      .key_valid      (1'b0),
      .key_in         ('0),
      .cipher_valid   (cipher_valid_int),
      .ciphertext     (ciphertext_int),
      .plaintext_valid(plaintext_valid_int),
      .plaintext      (plaintext_int),
      .decrypt_busy   ()
  );

  plaintext_validator u_plaintext_validator (
      .clk           (clk),
      .rst_n         (rst_n_sync),
      .plaintext_valid(plaintext_valid_int),
      .plaintext     (plaintext_int),
      .decrypt_valid (decrypt_valid_int),
      .decrypt_ok    (decrypt_ok_int),
      .id            (id_int)
  );

  cam u_cam (
      .clk         (clk),
      .rst_n       (rst_n_sync),
      .decrypt_valid(decrypt_valid_int),
      .decrypt_ok  (decrypt_ok_int),
      .id          (id_int),
      .lookup_valid(lookup_valid_int),
      .id_hit      (id_hit_int),
      .match_index (),
      .multi_hit   ()
  );

  timeout_monitor #(
      .TIMEOUT_CYCLES(4)
  ) u_timeout_monitor (
      .clk         (clk),
      .rst_n       (rst_n_sync),
      .start       (cipher_valid_int),
      .done        (lookup_valid_int),
      .timeout_valid(timeout_valid_int)
  );

  classifier u_classifier (
      .clk           (clk),
      .rst_n         (rst_n_sync),
      .lookup_valid  (lookup_valid_int),
      .id_hit        (id_hit_int),
      .timeout_valid (timeout_valid_int),
      .classify_valid(classify_valid),
      .authorized    (authorized),
      .unauthorized  (unauthorized),
      .unresponsive  (unresponsive)
  );

endmodule
