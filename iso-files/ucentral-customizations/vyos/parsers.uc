#!/usr/bin/ucode
/**
 * VyOS Text Parser Library
 *
 * Parsing functions for VyOS commands that return text output.
 * System data comes from REST API show commands (JSON format),
 * but DHCP leases, ARP tables, and NAT translations require text parsing.
 *
 * Author: uCentral VyOS Integration
 * Date: 2026-02-04
 */

/**
 * Parse ASCII table output with columns separated by 2+ spaces.
 *
 * @param {string} text - Raw ASCII table text
 * @param {number} skip_lines - Number of header lines to skip (default: 2)
 * @return {array} Array of arrays, each inner array is a row of columns
 *
 * Example input:
 *   "Column1  Column2  Column3\n
 *    ------   ------   ------\n
 *    value1   value2   value3\n"
 *
 * Example output:
 *   [["value1", "value2", "value3"]]
 */
function parse_ascii_table(text, skip_lines) {
    if (!text || !length(text))
        return [];

    if (!skip_lines)
        skip_lines = 2;

    let lines = split(text, "\n");
    let results = [];

    for (let i = skip_lines; i < length(lines); i++) {
        let line = trim(lines[i]);

        // Skip empty lines
        if (!length(line))
            continue;

        // Split on 2 or more spaces
        let cols = split(line, /\s{2,}/);

        if (length(cols) > 0)
            push(results, cols);
    }

    return results;
}


/**
 * Parse DHCP server leases from 'show dhcp server leases' output.
 *
 * @param {string} text - Raw output from VyOS show command
 * @return {array} Array of lease objects with {ip, mac, hostname, pool, state}
 *
 * Example input:
 *   "IP Address      MAC address        State    ...  Pool         Hostname
 *    --------------  -----------------  -------  ...  -----------  ------------
 *    192.168.1.11    94:ef:97:9d:0e:04  active   ...  LAN-VLAN1    clienthost"
 */
function parse_dhcp_leases(text) {
    let rows = parse_ascii_table(text, 2);
    let leases = [];

    for (let row in rows) {
        if (length(row) < 8)
            continue;  // Skip malformed rows

        push(leases, {
            ip: row[0],
            mac: row[1],
            state: row[2],
            pool: length(row) > 6 ? row[6] : "",
            hostname: length(row) > 7 ? row[7] : "-"
        });
    }

    return leases;
}


/**
 * Parse ARP table from 'show arp' output.
 *
 * @param {string} text - Raw output from VyOS show command
 * @return {array} Array of ARP entries with {ip, interface, mac, state}
 *
 * Example input:
 *   "Address         Interface    Link layer address    State
 *    --------------  -----------  --------------------  ---------
 *    192.168.100.50  br1.100      24:fe:9a:10:f5:f8     REACHABLE"
 */
function parse_arp_table(text) {
    let rows = parse_ascii_table(text, 2);
    let arp_entries = [];

    for (let row in rows) {
        if (length(row) < 4)
            continue;  // Skip malformed rows

        push(arp_entries, {
            ip: row[0],
            interface: row[1],
            mac: row[2],
            state: row[3]
        });
    }

    return arp_entries;
}


/**
 * Parse NAT source translations from 'show nat source translations' output.
 *
 * @param {string} text - Raw output from VyOS show command
 * @return {array} Array of NAT sessions with {source_ip, source_port, proto, timeout}
 *
 * Example input:
 *   "Pre-NAT               Post-NAT            Proto    Timeout    Mark    Zone
 *    --------------------  ------------------  -------  ---------  ------  ------
 *    192.168.100.50:54894  192.168.3.20:54894  tcp      431965     0"
 */
function parse_nat_translations(text) {
    let rows = parse_ascii_table(text, 2);
    let sessions = [];

    for (let row in rows) {
        if (length(row) < 3)
            continue;  // Skip malformed rows

        // Extract source IP from "Pre-NAT" column (before colon)
        let pre_nat = row[0];
        let pre_nat_parts = split(pre_nat, ":");
        let source_ip = length(pre_nat_parts) > 0 ? pre_nat_parts[0] : pre_nat;
        let source_port = length(pre_nat_parts) > 1 ? pre_nat_parts[1] : "";

        push(sessions, {
            source_ip: source_ip,
            source_port: source_port,
            proto: length(row) > 2 ? row[2] : "",
            timeout: length(row) > 3 ? int(row[3]) : 0
        });
    }

    return sessions;
}


/**
 * Map interfaces to roles (upstream/downstream) based on VyOS configuration.
 *
 * @param {object} config_json - Result from showConfig ["interfaces"]
 * @return {object} Map of interface name to {role, description}
 *
 * Role mapping logic:
 * - If description contains "WAN" → upstream
 * - If description contains "LAN" → downstream
 * - If interface is a bridge member, inherit parent's role
 *
 * Example output:
 * {
 *   "br0": {role: "upstream", description: "WAN"},
 *   "br1": {role: "downstream", description: "LAN"},
 *   "eth0": {role: "upstream", description: "WAN"},
 *   "eth1": {role: "downstream", description: "LAN"}
 * }
 */
function get_interface_roles_from_config(config_json) {
    let roles = {};

    if (!config_json || !config_json.interfaces)
        return roles;

    let interfaces = config_json.interfaces;

    // First pass: Map bridges and direct interfaces
    for (let if_type in interfaces) {
        for (let if_name in interfaces[if_type]) {
            let if_config = interfaces[if_type][if_name];
            let description = if_config.description || "";

            let role = "unknown";
            if (index(uc(description), "WAN") >= 0)
                role = "upstream";
            else if (index(uc(description), "LAN") >= 0)
                role = "downstream";

            roles[if_name] = {
                role: role,
                description: description
            };
        }
    }

    // Second pass: Inherit roles for bridge members
    if (interfaces.bridge) {
        for (let br_name in interfaces.bridge) {
            let br_config = interfaces.bridge[br_name];
            let br_role = roles[br_name]?.role || "unknown";

            // Check for members
            if (br_config.member && br_config.member.interface) {
                for (let member_name in br_config.member.interface) {
                    // Inherit parent bridge's role
                    roles[member_name] = {
                        role: br_role,
                        description: roles[br_name]?.description || ""
                    };
                }
            }
        }
    }

    return roles;
}


// Return functions for use in other modules (ucode module pattern)
return {
    parse_ascii_table: parse_ascii_table,
    parse_dhcp_leases: parse_dhcp_leases,
    parse_arp_table: parse_arp_table,
    parse_nat_translations: parse_nat_translations,
    get_interface_roles_from_config: get_interface_roles_from_config
};
