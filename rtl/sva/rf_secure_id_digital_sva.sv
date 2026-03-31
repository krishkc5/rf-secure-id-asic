property p_lookup_timeout_nonoverlap;
    @(posedge core_clk) disable iff (!rst_pipe_n)
        !(evt_lookup_rsp && evt_timeout_rsp);
endproperty

a_lookup_timeout_nonoverlap:
    assert property (p_lookup_timeout_nonoverlap)
        else $error("rf_secure_id_digital saw lookup and timeout pulses together");
