module aes_decrypt (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         cipher_valid,
    input  logic [127:0] ciphertext,
    output logic         plaintext_valid,
    output logic [127:0] plaintext,
    output logic         decrypt_busy
);

  localparam int NUM_ROUNDS      = 10;
  localparam int ROUND_IDX_WIDTH = $clog2(NUM_ROUNDS + 1);

  localparam logic [127:0] ROUND_KEY_0  = 128'h000102030405060708090A0B0C0D0E0F;
  localparam logic [127:0] ROUND_KEY_1  = 128'hD6AA74FDD2AF72FADAA678F1D6AB76FE;
  localparam logic [127:0] ROUND_KEY_2  = 128'hB692CF0B643DBDF1BE9BC5006830B3FE;
  localparam logic [127:0] ROUND_KEY_3  = 128'hB6FF744ED2C2C9BF6C590CBF0469BF41;
  localparam logic [127:0] ROUND_KEY_4  = 128'h47F7F7BC95353E03F96C32BCFD058DFD;
  localparam logic [127:0] ROUND_KEY_5  = 128'h3CAAA3E8A99F9DEB50F3AF57ADF622AA;
  localparam logic [127:0] ROUND_KEY_6  = 128'h5E390F7DF7A69296A7553DC10AA31F6B;
  localparam logic [127:0] ROUND_KEY_7  = 128'h14F9701AE35FE28C440ADF4D4EA9C026;
  localparam logic [127:0] ROUND_KEY_8  = 128'h47438735A41C65B9E016BAF4AEBF7AD2;
  localparam logic [127:0] ROUND_KEY_9  = 128'h549932D1F08557681093ED9CBE2C974E;
  localparam logic [127:0] ROUND_KEY_10 = 128'h13111D7FE3944A17F307A78B4D2B30C5;

  typedef enum logic {
    STATE_IDLE,
    STATE_RUN
  } controller_state_t;

  controller_state_t        controller_state_reg;
  controller_state_t        controller_state_next;
  logic [127:0]             state_reg;
  logic [127:0]             state_next;
  logic [ROUND_IDX_WIDTH-1:0] round_idx_reg;
  logic [ROUND_IDX_WIDTH-1:0] round_idx_next;
  logic                     plaintext_valid_next;
  logic [127:0]             plaintext_next;
  logic                     decrypt_busy_next;

  function automatic logic [127:0] get_round_key(input logic [3:0] idx);
    begin
      unique case (idx)
        4'd0:    get_round_key = ROUND_KEY_0;
        4'd1:    get_round_key = ROUND_KEY_1;
        4'd2:    get_round_key = ROUND_KEY_2;
        4'd3:    get_round_key = ROUND_KEY_3;
        4'd4:    get_round_key = ROUND_KEY_4;
        4'd5:    get_round_key = ROUND_KEY_5;
        4'd6:    get_round_key = ROUND_KEY_6;
        4'd7:    get_round_key = ROUND_KEY_7;
        4'd8:    get_round_key = ROUND_KEY_8;
        4'd9:    get_round_key = ROUND_KEY_9;
        4'd10:   get_round_key = ROUND_KEY_10;
        default: get_round_key = '0;
      endcase
    end
  endfunction

  function automatic logic [7:0] inv_sbox(input logic [7:0] byte_in);
    begin
      unique case (byte_in)
        8'h00: inv_sbox = 8'h52;
        8'h01: inv_sbox = 8'h09;
        8'h02: inv_sbox = 8'h6A;
        8'h03: inv_sbox = 8'hD5;
        8'h04: inv_sbox = 8'h30;
        8'h05: inv_sbox = 8'h36;
        8'h06: inv_sbox = 8'hA5;
        8'h07: inv_sbox = 8'h38;
        8'h08: inv_sbox = 8'hBF;
        8'h09: inv_sbox = 8'h40;
        8'h0A: inv_sbox = 8'hA3;
        8'h0B: inv_sbox = 8'h9E;
        8'h0C: inv_sbox = 8'h81;
        8'h0D: inv_sbox = 8'hF3;
        8'h0E: inv_sbox = 8'hD7;
        8'h0F: inv_sbox = 8'hFB;
        8'h10: inv_sbox = 8'h7C;
        8'h11: inv_sbox = 8'hE3;
        8'h12: inv_sbox = 8'h39;
        8'h13: inv_sbox = 8'h82;
        8'h14: inv_sbox = 8'h9B;
        8'h15: inv_sbox = 8'h2F;
        8'h16: inv_sbox = 8'hFF;
        8'h17: inv_sbox = 8'h87;
        8'h18: inv_sbox = 8'h34;
        8'h19: inv_sbox = 8'h8E;
        8'h1A: inv_sbox = 8'h43;
        8'h1B: inv_sbox = 8'h44;
        8'h1C: inv_sbox = 8'hC4;
        8'h1D: inv_sbox = 8'hDE;
        8'h1E: inv_sbox = 8'hE9;
        8'h1F: inv_sbox = 8'hCB;
        8'h20: inv_sbox = 8'h54;
        8'h21: inv_sbox = 8'h7B;
        8'h22: inv_sbox = 8'h94;
        8'h23: inv_sbox = 8'h32;
        8'h24: inv_sbox = 8'hA6;
        8'h25: inv_sbox = 8'hC2;
        8'h26: inv_sbox = 8'h23;
        8'h27: inv_sbox = 8'h3D;
        8'h28: inv_sbox = 8'hEE;
        8'h29: inv_sbox = 8'h4C;
        8'h2A: inv_sbox = 8'h95;
        8'h2B: inv_sbox = 8'h0B;
        8'h2C: inv_sbox = 8'h42;
        8'h2D: inv_sbox = 8'hFA;
        8'h2E: inv_sbox = 8'hC3;
        8'h2F: inv_sbox = 8'h4E;
        8'h30: inv_sbox = 8'h08;
        8'h31: inv_sbox = 8'h2E;
        8'h32: inv_sbox = 8'hA1;
        8'h33: inv_sbox = 8'h66;
        8'h34: inv_sbox = 8'h28;
        8'h35: inv_sbox = 8'hD9;
        8'h36: inv_sbox = 8'h24;
        8'h37: inv_sbox = 8'hB2;
        8'h38: inv_sbox = 8'h76;
        8'h39: inv_sbox = 8'h5B;
        8'h3A: inv_sbox = 8'hA2;
        8'h3B: inv_sbox = 8'h49;
        8'h3C: inv_sbox = 8'h6D;
        8'h3D: inv_sbox = 8'h8B;
        8'h3E: inv_sbox = 8'hD1;
        8'h3F: inv_sbox = 8'h25;
        8'h40: inv_sbox = 8'h72;
        8'h41: inv_sbox = 8'hF8;
        8'h42: inv_sbox = 8'hF6;
        8'h43: inv_sbox = 8'h64;
        8'h44: inv_sbox = 8'h86;
        8'h45: inv_sbox = 8'h68;
        8'h46: inv_sbox = 8'h98;
        8'h47: inv_sbox = 8'h16;
        8'h48: inv_sbox = 8'hD4;
        8'h49: inv_sbox = 8'hA4;
        8'h4A: inv_sbox = 8'h5C;
        8'h4B: inv_sbox = 8'hCC;
        8'h4C: inv_sbox = 8'h5D;
        8'h4D: inv_sbox = 8'h65;
        8'h4E: inv_sbox = 8'hB6;
        8'h4F: inv_sbox = 8'h92;
        8'h50: inv_sbox = 8'h6C;
        8'h51: inv_sbox = 8'h70;
        8'h52: inv_sbox = 8'h48;
        8'h53: inv_sbox = 8'h50;
        8'h54: inv_sbox = 8'hFD;
        8'h55: inv_sbox = 8'hED;
        8'h56: inv_sbox = 8'hB9;
        8'h57: inv_sbox = 8'hDA;
        8'h58: inv_sbox = 8'h5E;
        8'h59: inv_sbox = 8'h15;
        8'h5A: inv_sbox = 8'h46;
        8'h5B: inv_sbox = 8'h57;
        8'h5C: inv_sbox = 8'hA7;
        8'h5D: inv_sbox = 8'h8D;
        8'h5E: inv_sbox = 8'h9D;
        8'h5F: inv_sbox = 8'h84;
        8'h60: inv_sbox = 8'h90;
        8'h61: inv_sbox = 8'hD8;
        8'h62: inv_sbox = 8'hAB;
        8'h63: inv_sbox = 8'h00;
        8'h64: inv_sbox = 8'h8C;
        8'h65: inv_sbox = 8'hBC;
        8'h66: inv_sbox = 8'hD3;
        8'h67: inv_sbox = 8'h0A;
        8'h68: inv_sbox = 8'hF7;
        8'h69: inv_sbox = 8'hE4;
        8'h6A: inv_sbox = 8'h58;
        8'h6B: inv_sbox = 8'h05;
        8'h6C: inv_sbox = 8'hB8;
        8'h6D: inv_sbox = 8'hB3;
        8'h6E: inv_sbox = 8'h45;
        8'h6F: inv_sbox = 8'h06;
        8'h70: inv_sbox = 8'hD0;
        8'h71: inv_sbox = 8'h2C;
        8'h72: inv_sbox = 8'h1E;
        8'h73: inv_sbox = 8'h8F;
        8'h74: inv_sbox = 8'hCA;
        8'h75: inv_sbox = 8'h3F;
        8'h76: inv_sbox = 8'h0F;
        8'h77: inv_sbox = 8'h02;
        8'h78: inv_sbox = 8'hC1;
        8'h79: inv_sbox = 8'hAF;
        8'h7A: inv_sbox = 8'hBD;
        8'h7B: inv_sbox = 8'h03;
        8'h7C: inv_sbox = 8'h01;
        8'h7D: inv_sbox = 8'h13;
        8'h7E: inv_sbox = 8'h8A;
        8'h7F: inv_sbox = 8'h6B;
        8'h80: inv_sbox = 8'h3A;
        8'h81: inv_sbox = 8'h91;
        8'h82: inv_sbox = 8'h11;
        8'h83: inv_sbox = 8'h41;
        8'h84: inv_sbox = 8'h4F;
        8'h85: inv_sbox = 8'h67;
        8'h86: inv_sbox = 8'hDC;
        8'h87: inv_sbox = 8'hEA;
        8'h88: inv_sbox = 8'h97;
        8'h89: inv_sbox = 8'hF2;
        8'h8A: inv_sbox = 8'hCF;
        8'h8B: inv_sbox = 8'hCE;
        8'h8C: inv_sbox = 8'hF0;
        8'h8D: inv_sbox = 8'hB4;
        8'h8E: inv_sbox = 8'hE6;
        8'h8F: inv_sbox = 8'h73;
        8'h90: inv_sbox = 8'h96;
        8'h91: inv_sbox = 8'hAC;
        8'h92: inv_sbox = 8'h74;
        8'h93: inv_sbox = 8'h22;
        8'h94: inv_sbox = 8'hE7;
        8'h95: inv_sbox = 8'hAD;
        8'h96: inv_sbox = 8'h35;
        8'h97: inv_sbox = 8'h85;
        8'h98: inv_sbox = 8'hE2;
        8'h99: inv_sbox = 8'hF9;
        8'h9A: inv_sbox = 8'h37;
        8'h9B: inv_sbox = 8'hE8;
        8'h9C: inv_sbox = 8'h1C;
        8'h9D: inv_sbox = 8'h75;
        8'h9E: inv_sbox = 8'hDF;
        8'h9F: inv_sbox = 8'h6E;
        8'hA0: inv_sbox = 8'h47;
        8'hA1: inv_sbox = 8'hF1;
        8'hA2: inv_sbox = 8'h1A;
        8'hA3: inv_sbox = 8'h71;
        8'hA4: inv_sbox = 8'h1D;
        8'hA5: inv_sbox = 8'h29;
        8'hA6: inv_sbox = 8'hC5;
        8'hA7: inv_sbox = 8'h89;
        8'hA8: inv_sbox = 8'h6F;
        8'hA9: inv_sbox = 8'hB7;
        8'hAA: inv_sbox = 8'h62;
        8'hAB: inv_sbox = 8'h0E;
        8'hAC: inv_sbox = 8'hAA;
        8'hAD: inv_sbox = 8'h18;
        8'hAE: inv_sbox = 8'hBE;
        8'hAF: inv_sbox = 8'h1B;
        8'hB0: inv_sbox = 8'hFC;
        8'hB1: inv_sbox = 8'h56;
        8'hB2: inv_sbox = 8'h3E;
        8'hB3: inv_sbox = 8'h4B;
        8'hB4: inv_sbox = 8'hC6;
        8'hB5: inv_sbox = 8'hD2;
        8'hB6: inv_sbox = 8'h79;
        8'hB7: inv_sbox = 8'h20;
        8'hB8: inv_sbox = 8'h9A;
        8'hB9: inv_sbox = 8'hDB;
        8'hBA: inv_sbox = 8'hC0;
        8'hBB: inv_sbox = 8'hFE;
        8'hBC: inv_sbox = 8'h78;
        8'hBD: inv_sbox = 8'hCD;
        8'hBE: inv_sbox = 8'h5A;
        8'hBF: inv_sbox = 8'hF4;
        8'hC0: inv_sbox = 8'h1F;
        8'hC1: inv_sbox = 8'hDD;
        8'hC2: inv_sbox = 8'hA8;
        8'hC3: inv_sbox = 8'h33;
        8'hC4: inv_sbox = 8'h88;
        8'hC5: inv_sbox = 8'h07;
        8'hC6: inv_sbox = 8'hC7;
        8'hC7: inv_sbox = 8'h31;
        8'hC8: inv_sbox = 8'hB1;
        8'hC9: inv_sbox = 8'h12;
        8'hCA: inv_sbox = 8'h10;
        8'hCB: inv_sbox = 8'h59;
        8'hCC: inv_sbox = 8'h27;
        8'hCD: inv_sbox = 8'h80;
        8'hCE: inv_sbox = 8'hEC;
        8'hCF: inv_sbox = 8'h5F;
        8'hD0: inv_sbox = 8'h60;
        8'hD1: inv_sbox = 8'h51;
        8'hD2: inv_sbox = 8'h7F;
        8'hD3: inv_sbox = 8'hA9;
        8'hD4: inv_sbox = 8'h19;
        8'hD5: inv_sbox = 8'hB5;
        8'hD6: inv_sbox = 8'h4A;
        8'hD7: inv_sbox = 8'h0D;
        8'hD8: inv_sbox = 8'h2D;
        8'hD9: inv_sbox = 8'hE5;
        8'hDA: inv_sbox = 8'h7A;
        8'hDB: inv_sbox = 8'h9F;
        8'hDC: inv_sbox = 8'h93;
        8'hDD: inv_sbox = 8'hC9;
        8'hDE: inv_sbox = 8'h9C;
        8'hDF: inv_sbox = 8'hEF;
        8'hE0: inv_sbox = 8'hA0;
        8'hE1: inv_sbox = 8'hE0;
        8'hE2: inv_sbox = 8'h3B;
        8'hE3: inv_sbox = 8'h4D;
        8'hE4: inv_sbox = 8'hAE;
        8'hE5: inv_sbox = 8'h2A;
        8'hE6: inv_sbox = 8'hF5;
        8'hE7: inv_sbox = 8'hB0;
        8'hE8: inv_sbox = 8'hC8;
        8'hE9: inv_sbox = 8'hEB;
        8'hEA: inv_sbox = 8'hBB;
        8'hEB: inv_sbox = 8'h3C;
        8'hEC: inv_sbox = 8'h83;
        8'hED: inv_sbox = 8'h53;
        8'hEE: inv_sbox = 8'h99;
        8'hEF: inv_sbox = 8'h61;
        8'hF0: inv_sbox = 8'h17;
        8'hF1: inv_sbox = 8'h2B;
        8'hF2: inv_sbox = 8'h04;
        8'hF3: inv_sbox = 8'h7E;
        8'hF4: inv_sbox = 8'hBA;
        8'hF5: inv_sbox = 8'h77;
        8'hF6: inv_sbox = 8'hD6;
        8'hF7: inv_sbox = 8'h26;
        8'hF8: inv_sbox = 8'hE1;
        8'hF9: inv_sbox = 8'h69;
        8'hFA: inv_sbox = 8'h14;
        8'hFB: inv_sbox = 8'h63;
        8'hFC: inv_sbox = 8'h55;
        8'hFD: inv_sbox = 8'h21;
        8'hFE: inv_sbox = 8'h0C;
        8'hFF: inv_sbox = 8'h7D;
        default: inv_sbox = 8'h00;
      endcase
    end
  endfunction

  function automatic logic [127:0] inv_shift_rows(input logic [127:0] state_in);
    logic [7:0] byte_lane [0:15];
    begin
      byte_lane[0]  = state_in[127:120];
      byte_lane[1]  = state_in[119:112];
      byte_lane[2]  = state_in[111:104];
      byte_lane[3]  = state_in[103:96];
      byte_lane[4]  = state_in[95:88];
      byte_lane[5]  = state_in[87:80];
      byte_lane[6]  = state_in[79:72];
      byte_lane[7]  = state_in[71:64];
      byte_lane[8]  = state_in[63:56];
      byte_lane[9]  = state_in[55:48];
      byte_lane[10] = state_in[47:40];
      byte_lane[11] = state_in[39:32];
      byte_lane[12] = state_in[31:24];
      byte_lane[13] = state_in[23:16];
      byte_lane[14] = state_in[15:8];
      byte_lane[15] = state_in[7:0];

      inv_shift_rows = {
          byte_lane[0],  byte_lane[13], byte_lane[10], byte_lane[7],
          byte_lane[4],  byte_lane[1],  byte_lane[14], byte_lane[11],
          byte_lane[8],  byte_lane[5],  byte_lane[2],  byte_lane[15],
          byte_lane[12], byte_lane[9],  byte_lane[6],  byte_lane[3]
      };
    end
  endfunction

  function automatic logic [7:0] gf_mul8(
      input logic [7:0] a,
      input logic [7:0] b
  );
    logic [7:0] multiplicand;
    logic [7:0] multiplier;
    logic [7:0] product;
    int         bit_idx;
    begin
      multiplicand = a;
      multiplier   = b;
      product      = 8'h00;

      for (bit_idx = 0; bit_idx < 8; bit_idx++) begin
        if (multiplier[0]) begin
          product ^= multiplicand;
        end

        if (multiplicand[7]) begin
          multiplicand = {multiplicand[6:0], 1'b0} ^ 8'h1B;
        end else begin
          multiplicand = {multiplicand[6:0], 1'b0};
        end

        multiplier = {1'b0, multiplier[7:1]};
      end

      gf_mul8 = product;
    end
  endfunction

  function automatic logic [127:0] inv_mix_columns(input logic [127:0] state_in);
    logic [7:0] byte_lane [0:15];
    logic [7:0] mixed_lane [0:15];
    int         col_idx;
    int         base_idx;
    begin
      byte_lane[0]  = state_in[127:120];
      byte_lane[1]  = state_in[119:112];
      byte_lane[2]  = state_in[111:104];
      byte_lane[3]  = state_in[103:96];
      byte_lane[4]  = state_in[95:88];
      byte_lane[5]  = state_in[87:80];
      byte_lane[6]  = state_in[79:72];
      byte_lane[7]  = state_in[71:64];
      byte_lane[8]  = state_in[63:56];
      byte_lane[9]  = state_in[55:48];
      byte_lane[10] = state_in[47:40];
      byte_lane[11] = state_in[39:32];
      byte_lane[12] = state_in[31:24];
      byte_lane[13] = state_in[23:16];
      byte_lane[14] = state_in[15:8];
      byte_lane[15] = state_in[7:0];

      for (col_idx = 0; col_idx < 4; col_idx++) begin
        base_idx = col_idx * 4;

        mixed_lane[base_idx + 0] =
            gf_mul8(byte_lane[base_idx + 0], 8'h0E) ^
            gf_mul8(byte_lane[base_idx + 1], 8'h0B) ^
            gf_mul8(byte_lane[base_idx + 2], 8'h0D) ^
            gf_mul8(byte_lane[base_idx + 3], 8'h09);

        mixed_lane[base_idx + 1] =
            gf_mul8(byte_lane[base_idx + 0], 8'h09) ^
            gf_mul8(byte_lane[base_idx + 1], 8'h0E) ^
            gf_mul8(byte_lane[base_idx + 2], 8'h0B) ^
            gf_mul8(byte_lane[base_idx + 3], 8'h0D);

        mixed_lane[base_idx + 2] =
            gf_mul8(byte_lane[base_idx + 0], 8'h0D) ^
            gf_mul8(byte_lane[base_idx + 1], 8'h09) ^
            gf_mul8(byte_lane[base_idx + 2], 8'h0E) ^
            gf_mul8(byte_lane[base_idx + 3], 8'h0B);

        mixed_lane[base_idx + 3] =
            gf_mul8(byte_lane[base_idx + 0], 8'h0B) ^
            gf_mul8(byte_lane[base_idx + 1], 8'h0D) ^
            gf_mul8(byte_lane[base_idx + 2], 8'h09) ^
            gf_mul8(byte_lane[base_idx + 3], 8'h0E);
      end

      inv_mix_columns = {
          mixed_lane[0],  mixed_lane[1],  mixed_lane[2],  mixed_lane[3],
          mixed_lane[4],  mixed_lane[5],  mixed_lane[6],  mixed_lane[7],
          mixed_lane[8],  mixed_lane[9],  mixed_lane[10], mixed_lane[11],
          mixed_lane[12], mixed_lane[13], mixed_lane[14], mixed_lane[15]
      };
    end
  endfunction

  function automatic logic [127:0] inv_sub_bytes(input logic [127:0] state_in);
    logic [7:0] byte_lane [0:15];
    logic [7:0] subbed_lane [0:15];
    int         byte_idx;
    begin
      byte_lane[0]  = state_in[127:120];
      byte_lane[1]  = state_in[119:112];
      byte_lane[2]  = state_in[111:104];
      byte_lane[3]  = state_in[103:96];
      byte_lane[4]  = state_in[95:88];
      byte_lane[5]  = state_in[87:80];
      byte_lane[6]  = state_in[79:72];
      byte_lane[7]  = state_in[71:64];
      byte_lane[8]  = state_in[63:56];
      byte_lane[9]  = state_in[55:48];
      byte_lane[10] = state_in[47:40];
      byte_lane[11] = state_in[39:32];
      byte_lane[12] = state_in[31:24];
      byte_lane[13] = state_in[23:16];
      byte_lane[14] = state_in[15:8];
      byte_lane[15] = state_in[7:0];

      for (byte_idx = 0; byte_idx < 16; byte_idx++) begin
        subbed_lane[byte_idx] = inv_sbox(byte_lane[byte_idx]);
      end

      inv_sub_bytes = {
          subbed_lane[0],  subbed_lane[1],  subbed_lane[2],  subbed_lane[3],
          subbed_lane[4],  subbed_lane[5],  subbed_lane[6],  subbed_lane[7],
          subbed_lane[8],  subbed_lane[9],  subbed_lane[10], subbed_lane[11],
          subbed_lane[12], subbed_lane[13], subbed_lane[14], subbed_lane[15]
      };
    end
  endfunction

  function automatic logic [127:0] add_round_key(
      input logic [127:0] state_in,
      input logic [127:0] round_key
  );
    begin
      add_round_key = state_in ^ round_key;
    end
  endfunction

  function automatic logic [127:0] inv_round(
      input logic [127:0] state_in,
      input logic [127:0] round_key
  );
    logic [127:0] shifted_state;
    logic [127:0] subbed_state;
    logic [127:0] keyed_state;
    begin
      shifted_state = inv_shift_rows(state_in);
      subbed_state  = inv_sub_bytes(shifted_state);
      keyed_state   = add_round_key(subbed_state, round_key);
      inv_round     = inv_mix_columns(keyed_state);
    end
  endfunction

  function automatic logic [127:0] inv_final_round(
      input logic [127:0] state_in,
      input logic [127:0] round_key
  );
    logic [127:0] shifted_state;
    logic [127:0] subbed_state;
    begin
      shifted_state   = inv_shift_rows(state_in);
      subbed_state    = inv_sub_bytes(shifted_state);
      inv_final_round = add_round_key(subbed_state, round_key);
    end
  endfunction

  always_comb begin
    controller_state_next = controller_state_reg;
    state_next            = state_reg;
    round_idx_next        = round_idx_reg;
    plaintext_valid_next  = 1'b0;
    plaintext_next        = plaintext;
    decrypt_busy_next     = decrypt_busy;

    unique case (controller_state_reg)
      STATE_IDLE: begin
        decrypt_busy_next = 1'b0;

        if (cipher_valid) begin
          state_next            = add_round_key(ciphertext, get_round_key(4'd10));
          round_idx_next        = ROUND_IDX_WIDTH'(NUM_ROUNDS - 1);
          decrypt_busy_next     = 1'b1;
          controller_state_next = STATE_RUN;
        end
      end

      STATE_RUN: begin
        decrypt_busy_next = 1'b1;

        if (round_idx_reg > 0) begin
          state_next     = inv_round(state_reg, get_round_key(round_idx_reg));
          round_idx_next = round_idx_reg - 1'b1;
        end else begin
          plaintext_next        = inv_final_round(state_reg, get_round_key(4'd0));
          plaintext_valid_next  = 1'b1;
          decrypt_busy_next     = 1'b0;
          controller_state_next = STATE_IDLE;
        end
      end

      default: begin
        controller_state_next = STATE_IDLE;
        state_next            = '0;
        round_idx_next        = '0;
        plaintext_valid_next  = 1'b0;
        plaintext_next        = plaintext;
        decrypt_busy_next     = 1'b0;
      end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      controller_state_reg <= STATE_IDLE;
      state_reg            <= '0;
      round_idx_reg        <= '0;
      plaintext_valid      <= 1'b0;
      plaintext            <= '0;
      decrypt_busy         <= 1'b0;
    end else begin
      controller_state_reg <= controller_state_next;
      state_reg            <= state_next;
      round_idx_reg        <= round_idx_next;
      plaintext_valid      <= plaintext_valid_next;
      plaintext            <= plaintext_next;
      decrypt_busy         <= decrypt_busy_next;
    end
  end

endmodule
