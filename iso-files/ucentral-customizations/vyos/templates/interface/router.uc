{%
	// Router mode template: generates direct ethernet interfaces (no bridges)
	// Used for simple router/gateway deployments like OLG

	let ipv4      = iface.ipv4;
	let addr_mode = ipv4 ? ipv4.addressing : null;
	let cidr      = (ipv4 && type(ipv4.subnet) == "string") ? ipv4.subnet : null;

	// For downstream interfaces, derive VLAN IDs + VLAN interfaces from config.interfaces
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

	// Get the actual ethernet interface name (eth0, eth1, etc.)
	let eth_if = (length(members) > 0) ? members[0] : null;
%}
	{% if (eth_if): %}
	ethernet {{ eth_if }} {
		{% if (role == "upstream"): %}
			{# Upstream (WAN) configuration - typically DHCP #}
			{% if (addr_mode == "dynamic"): %}
		address dhcp
			{% elif (addr_mode == "static" && cidr): %}
		address {{ cidr }}
			{% endif %}
		{% else %}
			{# Downstream (LAN) configuration - static IP for native VLAN #}
			{% if (addr_mode == "static" && cidr): %}
		address {{ cidr }}
			{% endif %}
		{% endif %}

		{% if (iface.name): %}
		description {{ iface.name }}
		{% elif (role == "upstream"): %}
		description WAN
		{% elif (role == "downstream"): %}
		description Native VLAN 1
		{% endif %}

		{% if (role == "downstream"): %}
			{# Generate VLAN sub-interfaces (vif) on ethernet interface #}
			{% for (let v in vlans): %}
				{% if (type(v.vlan) == "object" && v.vlan.id && type(v.ipv4) == "object" && type(v.ipv4.subnet) == "string"): %}
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
	{% endif %}

