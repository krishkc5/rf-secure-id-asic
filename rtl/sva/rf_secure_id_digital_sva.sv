property p_rf_secure_id_digital_lookup_and_timeout_do_not_overlap;
    @(posedge core_clk) disable iff (!rst_n_sync)
        !(lookup_valid_int && timeout_valid_int);
endproperty

a_rf_secure_id_digital_lookup_and_timeout_do_not_overlap:
    assert property (p_rf_secure_id_digital_lookup_and_timeout_do_not_overlap)
        else $error("rf_secure_id_digital saw lookup_valid and timeout_valid together");
