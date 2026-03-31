property p_timeout_valid_single_cycle;
    @(posedge core_clk) disable iff (!rst_n)
        timeout_fire_q |=> !timeout_fire_q;
endproperty

property p_watchdog_clears_on_timeout;
    @(posedge core_clk) disable iff (!rst_n)
        timeout_fire_q |-> !reg_watch_open_f;
endproperty

a_timeout_valid_single_cycle:
    assert property (p_timeout_valid_single_cycle)
        else $error("timeout_monitor timeout_fire_q must be a one-cycle pulse");

a_watchdog_clears_on_timeout:
    assert property (p_watchdog_clears_on_timeout)
        else $error("timeout_monitor active flag must clear once timeout fires");
