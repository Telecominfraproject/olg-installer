{%
	let ipv4      = iface.ipv4;
	let addr_mode = ipv4 ? ipv4.addressing : null;
	let cidr      = (ipv4 && type(ipv4.subnet) == "string") ? ipv4.subnet : null;

	// For downstream bridges, derive VLAN IDs + VLAN interfaces from config.interfaces
	let vlan_ids = [];
	let vlans    = [];

	if (role == "downstream" && type(config?.interfaces) == "array") {
		let vid_map = {};

		for (let it in config.interfaces) {
			if (it?.role != "downstream")
				continue;

			if (type(it?.vlan) != "object" || !it.vlan?.id)
				continue;

			push(vlans, it);
			vid_map["" + it.vlan.id] = true;
		}

		vlan_ids = sort(keys(vid_map));
	}
%}
	bridge {{ br_name }} {
		{% if (addr_mode == "dynamic"): %}
		address dhcp
		{% elif (addr_mode == "static" && cidr): %}
		address {{ cidr }}
		{% endif %}

		{% if (iface.name): %}
		description {{ iface.name }}
		{% endif %}

		{% if (role == "downstream"): %}
		enable-vlan
		{% endif %}

		{% if (length(members)): %}
		member {
			{% for (let m in members): %}
			interface {{ m }} {
				{% if (role == "downstream"): %}
					{% for (let vid in vlan_ids): %}
						{% if (vid == "1"): %}{% continue %}{% endif %}
				allowed-vlan {{ vid }}
					{% endfor %}
				native-vlan 1
				{% endif %}
			}
			{% endfor %}
		}
		{% endif %}

		{% if (role == "downstream"): %}
			{% for (let v in vlans): %}
				{% if (type(v.vlan) == "object" && v.vlan.id && type(v.ipv4) == "object" && type(v.ipv4.subnet) == "string"): %}
                {% if (v.vlan.id == 1): %}{% continue %}{% endif %}
		vif {{ v.vlan.id }} {
			address {{ v.ipv4.subnet }}
			{% if (v.name): %}
			description {{ v.name }}
			{% else %}
			description VLAN{{ v.vlan.id }}
			{% endif %}
		}
				{% endif %}
			{% endfor %}
		{% endif %}
	}

