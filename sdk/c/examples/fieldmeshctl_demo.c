#define _POSIX_C_SOURCE 200809L

#include "fieldmesh_sdk.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int require_ok(fieldmesh_status_t status, const char *operation)
{
    if (status == FIELDMESH_OK) {
        return 0;
    }
    fprintf(stderr, "%s failed: %s\n", operation, fieldmesh_status_string(status));
    return 1;
}

static void copy_arg(char *dst, size_t dst_len, const char *src)
{
    if (dst_len == 0u) {
        return;
    }
    snprintf(dst, dst_len, "%s", src ? src : "");
}

static const char *policy_name(fieldmesh_ap_policy_t policy)
{
    switch (policy) {
    case FIELDMESH_AP_POLICY_PREDEFINED:
        return "predefined";
    case FIELDMESH_AP_POLICY_AUTONOMOUS_SWARM:
        return "autonomous-swarm";
    case FIELDMESH_AP_POLICY_HYBRID:
        return "hybrid";
    default:
        return "invalid";
    }
}

static fieldmesh_ap_policy_t parse_policy(const char *text)
{
    if (!text || strcmp(text, "hybrid") == 0) {
        return FIELDMESH_AP_POLICY_HYBRID;
    }
    if (strcmp(text, "predefined") == 0) {
        return FIELDMESH_AP_POLICY_PREDEFINED;
    }
    if (strcmp(text, "autonomous-swarm") == 0) {
        return FIELDMESH_AP_POLICY_AUTONOMOUS_SWARM;
    }
    return (fieldmesh_ap_policy_t)0;
}

static uint8_t prefix_from_netmask(const char *text, uint8_t fallback)
{
    unsigned int a;
    unsigned int b;
    unsigned int c;
    unsigned int d;
    unsigned int octets[4];
    uint32_t mask = 0u;
    uint8_t prefix = 0u;
    uint8_t seen_zero = 0u;
    int i;

    if (!text || sscanf(text, "%u.%u.%u.%u", &a, &b, &c, &d) != 4) {
        return fallback;
    }
    octets[0] = a;
    octets[1] = b;
    octets[2] = c;
    octets[3] = d;
    for (i = 0; i < 4; ++i) {
        if (octets[i] > 255u) {
            return fallback;
        }
        mask = (mask << 8) | octets[i];
    }
    for (i = 31; i >= 0; --i) {
        if (mask & (1u << (unsigned int)i)) {
            if (seen_zero) {
                return fallback;
            }
            ++prefix;
        } else {
            seen_zero = 1u;
        }
    }
    return prefix > 30u ? fallback : prefix;
}

static void apply_env_value(fieldmesh_network_profile_t *profile,
                            const char *key,
                            const char *value)
{
    if (!key || !value || value[0] == '\0') {
        return;
    }
    if (strcmp(key, "hostname") == 0) {
        if (profile->node_id[0] == '\0' || strcmp(profile->node_id, "node-a") == 0) {
            copy_arg(profile->node_id, sizeof(profile->node_id), value);
        }
        copy_arg(profile->friendly_name, sizeof(profile->friendly_name), value);
    } else if (strcmp(key, "ethaddr") == 0 ||
               strcmp(key, "fieldmesh_device_eui") == 0) {
        char compact[13];
        size_t in_index;
        size_t out_index = 0u;

        for (in_index = 0u; value[in_index] != '\0' && out_index < 12u; ++in_index) {
            if (value[in_index] == ':' || value[in_index] == '-') {
                continue;
            }
            compact[out_index++] = value[in_index];
        }
        compact[out_index] = '\0';
        copy_arg(profile->device_eui, sizeof(profile->device_eui), compact);
    } else if (strcmp(key, "ipaddr") == 0) {
        copy_arg(profile->usb_device_ip, sizeof(profile->usb_device_ip), value);
    } else if (strcmp(key, "ipaddr_host") == 0) {
        copy_arg(profile->usb_host_ip, sizeof(profile->usb_host_ip), value);
    } else if (strcmp(key, "netmask") == 0) {
        profile->usb_prefix_len = prefix_from_netmask(value, profile->usb_prefix_len);
    } else if (strcmp(key, "ipaddr_eth") == 0) {
        copy_arg(profile->phy_device_ip, sizeof(profile->phy_device_ip), value);
    } else if (strcmp(key, "netmask_eth") == 0) {
        profile->phy_prefix_len = prefix_from_netmask(value, profile->phy_prefix_len);
    } else if (strcmp(key, "fieldmesh_node_id") == 0) {
        copy_arg(profile->node_id, sizeof(profile->node_id), value);
    } else if (strcmp(key, "fieldmesh_network_id") == 0) {
        copy_arg(profile->network_id, sizeof(profile->network_id), value);
    } else if (strcmp(key, "fieldmesh_preferred_ap") == 0) {
        copy_arg(profile->preferred_ap_id, sizeof(profile->preferred_ap_id), value);
    } else if (strcmp(key, "fieldmesh_ap_policy") == 0) {
        fieldmesh_ap_policy_t policy = parse_policy(value);
        if (policy != (fieldmesh_ap_policy_t)0) {
            profile->ap_policy = policy;
        }
    }
}

static void load_board_env_profile(fieldmesh_network_profile_t *profile)
{
#if !defined(_WIN32)
    FILE *pipe;
    char line[256];
    const char *identity_paths[] = {
        "/mnt/jffs2/fieldmesh/device_eui",
        "/etc/fieldmesh/device_eui",
    };
    size_t path_index;

    pipe = popen("fw_printenv hostname ethaddr ipaddr ipaddr_host netmask ipaddr_eth "
                 "netmask_eth fieldmesh_device_eui fieldmesh_node_id fieldmesh_network_id "
                 "fieldmesh_preferred_ap fieldmesh_ap_policy 2>/dev/null", "r");
    if (pipe) {
        while (fgets(line, sizeof(line), pipe)) {
            char *equals = strchr(line, '=');
            char *value;
            if (!equals) {
                continue;
            }
            *equals = '\0';
            value = equals + 1;
            value[strcspn(value, "\r\n")] = '\0';
            apply_env_value(profile, line, value);
        }
        (void)pclose(pipe);
    }
    for (path_index = 0u; path_index < sizeof(identity_paths) / sizeof(identity_paths[0]);
         ++path_index) {
        FILE *file = fopen(identity_paths[path_index], "r");
        if (file) {
            if (fgets(line, sizeof(line), file)) {
                line[strcspn(line, "\r\n\t ")] = '\0';
                apply_env_value(profile, "fieldmesh_device_eui", line);
            }
            fclose(file);
            break;
        }
    }
#else
    (void)profile;
#endif
}

static void print_profile(const char *event, const fieldmesh_network_profile_t *profile)
{
    printf("{\"event\":\"%s\",\"device_eui\":\"%s\",\"device_uuid\":\"%s\","
           "\"node_id\":\"%s\",\"network_id\":\"%s\","
           "\"friendly_name\":\"%s\",\"usb_device_ip\":\"%s\",\"usb_host_ip\":\"%s\","
           "\"usb_prefix_len\":%u,\"phy_device_ip\":\"%s\",\"phy_host_ip\":\"%s\","
           "\"phy_prefix_len\":%u,\"ap_policy\":\"%s\",\"preferred_ap_id\":\"%s\","
           "\"allow_emergency_1r1t_ap\":%u,\"radio_freq_mhz\":%u,"
           "\"radio_bandwidth_hz\":%u}\n",
           event, profile->device_eui, profile->device_eui,
           profile->node_id, profile->network_id, profile->friendly_name,
           profile->usb_device_ip, profile->usb_host_ip, profile->usb_prefix_len,
           profile->phy_device_ip, profile->phy_host_ip, profile->phy_prefix_len,
           policy_name(profile->ap_policy), profile->preferred_ap_id,
           profile->allow_emergency_1r1t_ap, profile->radio_freq_mhz,
           profile->radio_bandwidth_hz);
}

static void print_report(const char *event,
                         fieldmesh_status_t status,
                         const fieldmesh_network_profile_t *profile,
                         const fieldmesh_profile_validation_report_t *report)
{
    printf("{\"event\":\"%s\",\"status\":\"%s\",\"valid\":%u,"
           "\"requires_reboot\":%u,\"rollback_supported\":%u,"
           "\"persist_requested\":%u,\"device_eui\":\"%s\","
           "\"device_uuid\":\"%s\",\"node_id\":\"%s\",\"network_id\":\"%s\","
           "\"usb_device_ip\":\"%s\",\"usb_host_ip\":\"%s\",\"message\":\"%s\"}\n",
           event, fieldmesh_status_string(status), report ? report->valid : 0u,
           report ? report->requires_reboot : 0u,
           report ? report->rollback_supported : 0u,
           report ? report->persist_requested : 0u,
           profile ? profile->device_eui : "", profile ? profile->device_eui : "",
           profile ? profile->node_id : "", profile ? profile->network_id : "",
           profile ? profile->usb_device_ip : "", profile ? profile->usb_host_ip : "",
           report ? report->message : "");
}

static int usage(const char *argv0)
{
    fprintf(stderr,
            "usage: %s profile show|validate|apply|rollback "
            "[--device-eui 12HEX] [--node-id ID] [--network-id ID] "
            "[--friendly-name NAME] "
            "[--usb-device-ip IP] [--usb-host-ip IP] [--prefix N] "
            "[--phy-device-ip IP] [--phy-host-ip IP] [--phy-prefix N] "
            "[--ap-policy predefined|autonomous-swarm|hybrid] "
            "[--preferred-ap-id ID] [--persist]\n",
            argv0);
    return 2;
}

static int parse_profile_args(int argc,
                              char **argv,
                              int start,
                              fieldmesh_network_profile_t *profile,
                              uint32_t *flags)
{
    int i;

    for (i = start; i < argc; ++i) {
        if (strcmp(argv[i], "--persist") == 0) {
            *flags |= FIELDMESH_PROFILE_APPLY_PERSIST;
        } else if (i + 1 >= argc) {
            return -1;
        } else if (strcmp(argv[i], "--node-id") == 0) {
            copy_arg(profile->node_id, sizeof(profile->node_id), argv[++i]);
        } else if (strcmp(argv[i], "--device-eui") == 0) {
            copy_arg(profile->device_eui, sizeof(profile->device_eui), argv[++i]);
        } else if (strcmp(argv[i], "--network-id") == 0) {
            copy_arg(profile->network_id, sizeof(profile->network_id), argv[++i]);
        } else if (strcmp(argv[i], "--friendly-name") == 0) {
            copy_arg(profile->friendly_name, sizeof(profile->friendly_name), argv[++i]);
        } else if (strcmp(argv[i], "--usb-device-ip") == 0) {
            copy_arg(profile->usb_device_ip, sizeof(profile->usb_device_ip), argv[++i]);
        } else if (strcmp(argv[i], "--usb-host-ip") == 0) {
            copy_arg(profile->usb_host_ip, sizeof(profile->usb_host_ip), argv[++i]);
        } else if (strcmp(argv[i], "--prefix") == 0) {
            profile->usb_prefix_len = (uint8_t)strtoul(argv[++i], 0, 10);
        } else if (strcmp(argv[i], "--phy-device-ip") == 0) {
            copy_arg(profile->phy_device_ip, sizeof(profile->phy_device_ip), argv[++i]);
        } else if (strcmp(argv[i], "--phy-host-ip") == 0) {
            copy_arg(profile->phy_host_ip, sizeof(profile->phy_host_ip), argv[++i]);
        } else if (strcmp(argv[i], "--phy-prefix") == 0) {
            profile->phy_prefix_len = (uint8_t)strtoul(argv[++i], 0, 10);
        } else if (strcmp(argv[i], "--ap-policy") == 0) {
            profile->ap_policy = parse_policy(argv[++i]);
        } else if (strcmp(argv[i], "--preferred-ap-id") == 0) {
            copy_arg(profile->preferred_ap_id, sizeof(profile->preferred_ap_id), argv[++i]);
        } else {
            return -1;
        }
    }
    return 0;
}

int main(int argc, char **argv)
{
    fieldmesh_context_t *ctx = 0;
    fieldmesh_config_t config;
    fieldmesh_network_profile_t profile;
    fieldmesh_profile_validation_report_t report;
    fieldmesh_status_t status;
    uint32_t flags = 0;
    int rc = 0;
    const char *group = argc > 1 ? argv[1] : "profile";
    const char *command = argc > 2 ? argv[2] : "show";
    int option_start = argc > 2 ? 3 : argc;

    if (strcmp(group, "profile") != 0) {
        return usage(argv[0]);
    }
    memset(&config, 0, sizeof(config));
    config.transport = FIELDMESH_TRANSPORT_USB_ETH;
    config.control_port = 49000u;
    config.timeout_ms = 1000u;
    if (require_ok(fieldmesh_context_create(&config, &ctx), "context_create")) {
        return 1;
    }
    if (require_ok(fieldmesh_get_network_profile(ctx, &profile), "get_profile")) {
        fieldmesh_context_destroy(ctx);
        return 1;
    }
    load_board_env_profile(&profile);
    if (parse_profile_args(argc, argv, option_start, &profile, &flags) != 0) {
        fieldmesh_context_destroy(ctx);
        return usage(argv[0]);
    }

    if (strcmp(command, "show") == 0) {
        print_profile("fieldmeshctl_profile_show", &profile);
    } else if (strcmp(command, "validate") == 0) {
        status = fieldmesh_validate_network_profile(ctx, &profile, &report);
        print_report("fieldmeshctl_profile_validate", status, &profile, &report);
        rc = status == FIELDMESH_OK ? 0 : 1;
    } else if (strcmp(command, "apply") == 0) {
        status = fieldmesh_apply_network_profile(ctx, &profile, flags, &report);
        print_report("fieldmeshctl_profile_apply", status, &profile, &report);
        rc = status == FIELDMESH_OK ? 0 : 1;
    } else if (strcmp(command, "rollback") == 0) {
        (void)fieldmesh_apply_network_profile(ctx, &profile, 0u, &report);
        status = fieldmesh_rollback_network_profile(ctx);
        (void)fieldmesh_get_network_profile(ctx, &profile);
        printf("{\"event\":\"fieldmeshctl_profile_rollback\",\"status\":\"%s\","
               "\"node_id\":\"%s\",\"usb_device_ip\":\"%s\"}\n",
               fieldmesh_status_string(status), profile.node_id, profile.usb_device_ip);
        rc = status == FIELDMESH_OK ? 0 : 1;
    } else {
        rc = usage(argv[0]);
    }

    fieldmesh_context_destroy(ctx);
    return rc;
}
