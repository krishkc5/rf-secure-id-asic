property p_classifier_no_auth_and_unauth;
    @(posedge core_clk) disable iff (!rst_n)
        !(authorized && unauthorized);
endproperty

property p_classifier_no_auth_and_unresponsive;
    @(posedge core_clk) disable iff (!rst_n)
        !(authorized && unresponsive);
endproperty

property p_classifier_no_unauth_and_unresponsive;
    @(posedge core_clk) disable iff (!rst_n)
        !(unauthorized && unresponsive);
endproperty

property p_classifier_valid_maps_to_one_class;
    @(posedge core_clk) disable iff (!rst_n)
        classify_valid |-> ((authorized || unauthorized || unresponsive) &&
                            !(authorized && unauthorized) &&
                            !(authorized && unresponsive) &&
                            !(unauthorized && unresponsive));
endproperty

a_classifier_no_auth_and_unauth:
    assert property (p_classifier_no_auth_and_unauth)
        else $error("classifier drove authorized and unauthorized together");

a_classifier_no_auth_and_unresponsive:
    assert property (p_classifier_no_auth_and_unresponsive)
        else $error("classifier drove authorized and unresponsive together");

a_classifier_no_unauth_and_unresponsive:
    assert property (p_classifier_no_unauth_and_unresponsive)
        else $error("classifier drove unauthorized and unresponsive together");

a_classifier_valid_maps_to_one_class:
    assert property (p_classifier_valid_maps_to_one_class)
        else $error("classifier classify_valid did not map to exactly one class");
