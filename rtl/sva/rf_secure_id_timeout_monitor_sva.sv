property p_timeout_monitor_timeout_valid_is_single_cycle;
    @(posedge core_clk) disable iff (!rst_n)
        timeout_valid |=> !timeout_valid;
endproperty

property p_timeout_monitor_active_clears_on_timeout;
    @(posedge core_clk) disable iff (!rst_n)
        timeout_valid |-> !reg_timeout_active_f;
endproperty

a_timeout_monitor_timeout_valid_is_single_cycle:
    assert property (p_timeout_monitor_timeout_valid_is_single_cycle)
        else $error("timeout_monitor timeout_valid must be a one-cycle pulse");

a_timeout_monitor_active_clears_on_timeout:
    assert property (p_timeout_monitor_active_clears_on_timeout)
        else $error("timeout_monitor active flag must clear once timeout fires");
