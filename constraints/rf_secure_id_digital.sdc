#=====================================================================================================
# Constraint file: rf_secure_id_digital.sdc
# Purpose       : Project-level timing template for the active RF Secure ID digital backend.
#=====================================================================================================

create_clock -name core_clk -period 20.000 [get_ports core_clk]
set_clock_uncertainty 0.500 [get_clocks core_clk]

set_input_delay  -clock [get_clocks core_clk] 4.000 [get_ports {rst_n serial_bit}]
set_output_delay -clock [get_clocks core_clk] 4.000 [get_ports {classify_valid_q class_grant_q class_reject_q unresponsive_q}]

# No false-path or multicycle exception is intended inside the active digital pipeline.
# The only asynchronous control sampled at the top boundary is rst_n.
# Reset-release synchronizer flops are marked ASYNC_REG in RTL and should be kept adjacent.
# Backend implementation should avoid retiming across the reset synchronizer chain.
# Additional implementation-preservation intent is captured in:
#   constraints/rf_secure_id_backend_impl.tcl
