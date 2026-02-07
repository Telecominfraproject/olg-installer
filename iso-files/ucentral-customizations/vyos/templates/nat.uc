{%
    let snat_rules = [];
    let has_explicit_nat = false;

    if (type(config.nat) == "object" &&
        type(config.nat.snat) == "object" &&
        type(config.nat.snat.rules) == "array") {
        snat_rules = config.nat.snat.rules;
        has_explicit_nat = (length(snat_rules) > 0);
    }

    // Auto-generate NAT rules if none are explicitly defined
    if (!has_explicit_nat && type(config.interfaces) == "array") {
        // Find upstream (WAN) interface name
        let upstream_if = null;
        for (let iface in config.interfaces) {
            if (iface?.role == "upstream") {
                // In bridge mode, use bridge name instead of physical interface
                if (deployment_mode == "bridge") {
                    upstream_if = "br0";  // Bridge mode uses br0 for WAN
                } else {
                    // Router mode uses physical interface
                    let members = ethernet.lookup_interface_by_port(iface);
                    if (length(members) > 0) {
                        upstream_if = members[0];  // Typically eth0
                    }
                }
                break;
            }
        }

        // Collect all downstream subnets
        let subnets = [];
        if (upstream_if) {
            for (let iface in config.interfaces) {
                if (iface?.role == "downstream") {
                    // Native VLAN subnet
                    if (type(iface.ipv4) == "object" && type(iface.ipv4.subnet) == "string") {
                        let netinfo = network_base(iface.ipv4.subnet);
                        if (netinfo)
                            push(subnets, netinfo[0]);  // network/prefix format
                    }
                }
                // VLAN sub-interface subnets
                else if (iface?.role == "downstream" || type(iface?.vlan) == "object") {
                    if (type(iface.ipv4) == "object" && type(iface.ipv4.subnet) == "string") {
                        let netinfo = network_base(iface.ipv4.subnet);
                        if (netinfo)
                            push(subnets, netinfo[0]);
                    }
                }
            }

            // Generate NAT rules
            let rule_id = 101;
            for (let subnet in subnets) {
                push(snat_rules, {
                    rule_id: rule_id,
                    out_interface: { name: upstream_if },
                    source: { address: subnet },
                    translation: { address: "masquerade" }
                });
                rule_id++;
            }
        }
    }
%}

nat {
    source {
        {% if (type(snat_rules) == "array" && length(snat_rules) > 0): %}
            {% for (let rule_index = 0; rule_index < length(snat_rules); rule_index++): %}
                {%
                    let snat_rule = snat_rules[rule_index] || {};

                    let rule_id = snat_rule.rule_id ?? snat_rule["rule-id"];

                    let out_if_obj =
                        (type(snat_rule.out_interface) == "object") ? snat_rule.out_interface :
                        (type(snat_rule["out-interface"]) == "object") ? snat_rule["out-interface"] :
                        null;

                    let outbound_if_name = null;
                    if (type(out_if_obj) == "object")
                        outbound_if_name = out_if_obj.name ?? out_if_obj.group;

                    let source_subnet = (type(snat_rule.source) == "object") ? snat_rule.source.address : null;

                    let translation_address = (type(snat_rule.translation) == "object")
                        ? snat_rule.translation.address : null;

                %}
        rule {{ rule_id }} {
            outbound-interface {
                name {{ outbound_if_name }}
            }
            source {
                address {{ source_subnet }}
            }
            translation {
                address {{ translation_address }}
            }
        }
            {% endfor %}
        {% endif %}
    }
}

