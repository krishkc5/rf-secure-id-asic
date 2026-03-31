property p_classifier_no_auth_and_unauth;
    @(posedge core_clk) disable iff (!rst_n)
        !(class_grant_q && class_reject_q);
endproperty

property p_classifier_no_auth_and_unresponsive;
    @(posedge core_clk) disable iff (!rst_n)
        !(class_grant_q && unresponsive_q);
endproperty

property p_classifier_no_unauth_and_unresponsive;
    @(posedge core_clk) disable iff (!rst_n)
        !(class_reject_q && unresponsive_q);
endproperty

property p_classifier_valid_maps_to_one_class;
    @(posedge core_clk) disable iff (!rst_n)
        classify_valid_q |-> ((class_grant_q || class_reject_q || unresponsive_q) &&
                              !(class_grant_q && class_reject_q) &&
                              !(class_grant_q && unresponsive_q) &&
                              !(class_reject_q && unresponsive_q));
endproperty

a_classifier_no_auth_and_unauth:
    assert property (p_classifier_no_auth_and_unauth)
        else $error("classifier drove class_grant and class_reject together");

a_classifier_no_auth_and_unresponsive:
    assert property (p_classifier_no_auth_and_unresponsive)
        else $error("classifier drove class_grant and unresponsive together");

a_classifier_no_unauth_and_unresponsive:
    assert property (p_classifier_no_unauth_and_unresponsive)
        else $error("classifier drove class_reject and unresponsive together");

a_classifier_valid_maps_to_one_class:
    assert property (p_classifier_valid_maps_to_one_class)
        else $error("classifier classify_valid did not map to exactly one class");
