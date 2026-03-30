property p_aes_decrypt_busy_blocks_new_start;
    @(posedge core_clk) disable iff (!rst_n)
        decrypt_busy |-> !cipher_valid;
endproperty

a_aes_decrypt_busy_blocks_new_start:
    assert property (p_aes_decrypt_busy_blocks_new_start)
        else $error("aes_decrypt received cipher_valid while decrypt_busy was high");
