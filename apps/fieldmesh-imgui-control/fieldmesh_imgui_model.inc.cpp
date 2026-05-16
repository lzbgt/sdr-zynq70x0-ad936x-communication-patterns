struct GuiBoard {
    std::string device_eui;
    std::string hostname;
    std::string device_type;
    std::string daemon_host;
    unsigned daemon_port;
    bool selected;
    bool ap_capable;
    bool camera_stream_capable;
    bool route_metrics_capable;
    bool tun_gateway_capable;
    bool rf_packet_engine_capable;
    bool mutual_auth_required;
    bool rtls_position_capable;
};

struct GuiPeer {
    std::string device_eui;
    std::string hostname;
    std::string device_type;
    bool direct_reachable;
    bool relay_available;
    int rssi_dbm;
    int snr_db;
    int per_mille;
    int x_cm;
    int y_cm;
    unsigned error_radius_cm;
    unsigned range_update_count;
    unsigned metrics_age_ms;
    std::string range_source;
};

struct GuiCamera {
    bool publish_enabled;
    bool preview_enabled;
    bool invite_pending;
    bool incoming_invite;
    bool session_active;
    bool local_camera_enabled;
    bool local_mic_enabled;
    bool local_screen_enabled;
    bool remote_camera_enabled;
    bool remote_mic_enabled;
    std::string source_name;
    std::string preview_name;
    std::string session_kind;
    std::string dst_device_eui;
    std::string subscribed_device_eui;
    std::string pending_peer_eui;
    unsigned target_fps;
    unsigned target_bitrate_kbps;
    unsigned frames_tx;
    unsigned frames_rx;
    unsigned queued_to_rf_engine;
};

struct GuiRadioConfig {
    unsigned frequency_mhz;
    unsigned channel_index;
    unsigned bandwidth_khz;
    unsigned sample_rate_ksps;
    std::string profile_name;
    std::string modulation;
    std::string fec;
    std::string access_mode;
    std::string timing_mode;
    bool adaptive_mcs;
    bool direct_p2p_preferred;
    bool ap_relay_fallback;
    bool apply_pending;
    bool daemon_config_supported;
    bool daemon_config_sent;
    bool daemon_config_ok;
    bool daemon_config_writes_hardware;
    unsigned daemon_config_events;
    std::string daemon_config_status;
};

struct GuiPythonAutomation {
    std::string script;
    std::string last_output;
    std::string execution_log;
    unsigned runs;
    bool page_open;
    bool last_ok;
};

struct GuiProvisioning {
    bool page_open;
    bool persist;
    bool reboot_after_apply;
    bool dry_run;
    bool require_unique_seen_eui;
    bool last_ok;
    std::string new_eui;
    std::string last_message;
};

struct GuiConversation {
    std::string peer_eui;
    std::string display_name;
    unsigned unread_count;
    bool selected;
};

struct GuiMessage {
    std::string peer_eui;
    std::string direction;
    std::string text;
    std::string status;
};

struct GuiSecurity {
    std::string command_ca;
    std::string command_ca_fingerprint;
    std::string device_cert;
    std::string peer_cert;
    std::string mutual_auth_state;
    std::string authorization_scope;
    std::string app_security_layer;
    std::string device_private_key_source;
    std::string provisioning_model;
    bool derived_certificates;
    bool mutual_auth_required;
    bool authorization_required;
    bool app_security_optional;
    bool bundled_trust_bundle;
    bool bundled_demo_profile;
    bool command_ca_private_key_bundled;
    bool user_runs_shell_scripts;
    bool resources_embedded_in_app;
    unsigned embedded_resource_count;
    unsigned trust_bundle_bytes;
    unsigned profile_schema_bytes;
    unsigned auth_policy_bytes;
    unsigned codec_preset_bytes;
};

struct GuiState {
    std::vector<GuiBoard> boards;
    std::vector<GuiPeer> peers;
    std::vector<GuiConversation> conversations;
    std::vector<GuiMessage> messages;
    GuiSecurity security;
    GuiCamera camera;
    GuiRadioConfig radio;
    GuiPythonAutomation python;
    GuiProvisioning provisioning;
    bool topology_page_open;
    std::string selected_conversation_eui;
    std::string draft_message;
    unsigned messages_sent;
    unsigned messages_received;
    std::string selected_board_eui;
    std::string selected_ap_eui;
    std::string operation_status;
    std::string profile_source;
    std::string discovery_candidates;
    size_t message_bus_read_offset;
    unsigned daemon_message_cursor;
    float topology_zoom;
    int topology_center_x_cm;
    int topology_center_y_cm;
    bool event_worker_enabled;
    unsigned event_dispatch_count;
    unsigned topology_update_count;
    bool topology_metrics_live;
    bool connected_to_board;
    bool auto_election_enabled;
    bool radio_topology_only;
    bool uses_inter_board_ip_routing;
    bool starts_rf_tx;
    bool writes_hardware;
};
