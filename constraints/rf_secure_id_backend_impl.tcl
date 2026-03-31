#=====================================================================================================
# Backend intent file: rf_secure_id_backend_impl.tcl
# Purpose            : Tool-adaptable implementation guidance companion for the active
#                      RF Secure ID digital backend.
#=====================================================================================================

# Reset synchronizer flops that must remain a dedicated 2-flop release chain.
set rf_secure_id_reset_sync_cells [list \
    "rf_secure_id_digital/reg_reset_sync_stage1_f" \
    "rf_secure_id_digital/reg_reset_sync_stage2_f" \
]

# Registered stage-boundary instances whose visible request/response boundaries should be preserved.
set rf_secure_id_stage_boundary_instances [list \
    "rf_secure_id_digital/i_rf_secure_id_packet_rx" \
    "rf_secure_id_digital/i_rf_secure_id_packet_parser" \
    "rf_secure_id_digital/i_rf_secure_id_crc16_checker" \
    "rf_secure_id_digital/i_rf_secure_id_aes_decrypt" \
    "rf_secure_id_digital/i_rf_secure_id_plaintext_validator" \
    "rf_secure_id_digital/i_rf_secure_id_cam" \
    "rf_secure_id_digital/i_rf_secure_id_timeout_monitor" \
    "rf_secure_id_digital/i_rf_secure_id_classifier" \
]

# Speed-first optimization focus for timing closure.
set rf_secure_id_speed_critical_instances [list \
    "rf_secure_id_digital/i_rf_secure_id_aes_decrypt" \
    "rf_secure_id_digital/i_rf_secure_id_crc16_checker" \
    "rf_secure_id_digital/i_rf_secure_id_cam" \
]

# Area / power recovery focus once timing is closed.
set rf_secure_id_area_recovery_instances [list \
    "rf_secure_id_digital/i_rf_secure_id_timeout_monitor" \
    "rf_secure_id_digital/i_rf_secure_id_classifier" \
    "rf_secure_id_digital/i_rf_secure_id_plaintext_validator" \
]

# FSM instances with fixed explicit one-hot encoding in the ruled project baseline.
set rf_secure_id_fixed_encoding_instances [list \
    "rf_secure_id_digital/i_rf_secure_id_packet_rx" \
    "rf_secure_id_digital/i_rf_secure_id_aes_decrypt" \
]

# Resource-locked implementation choices in the ruled project baseline.
set rf_secure_id_resource_locked_instances [list \
    "rf_secure_id_digital/i_rf_secure_id_cam" \
]

# Required backend actions when translating this template into a tool-specific script:
# 1. Honor ASYNC_REG and DONT_TOUCH on rf_secure_id_reset_sync_cells.
# 2. Apply the tool's dont_retime / dont_replicate equivalent to rf_secure_id_reset_sync_cells.
# 3. Keep the two reset synchronizer flops adjacent with no logic inserted between them.
# 4. Preserve registered stage order across rf_secure_id_stage_boundary_instances.
# 5. Optimize rf_secure_id_speed_critical_instances for speed before area.
# 6. Preserve explicit one-hot encoding for rf_secure_id_fixed_encoding_instances.
# 7. Keep rf_secure_id_cam as a register-based compare structure in the ruled baseline;
#    do not remap it to RAM/ROM for this project configuration.
