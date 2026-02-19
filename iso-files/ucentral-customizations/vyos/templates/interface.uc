{%
let eth_used = {};
let upstream_assigned = false;
// All other bridges start from br1
let next_br_index = 1;
let router_mode_downstream_done = false; // Track if we've processed downstream in router mode
let bridge_mode_downstream_done = false;
//TODO: The ethernet interfaces should be retrieved from VyoS config, not to be set every time when a load operation is performed . Or we may need to implement logic for applying diff in the configurations instead of (retrieve + load) as it may become tedioud to manage going forward.
%}

interfaces {
	{% if (type(config.interfaces) == "array"): %}
		{% for (let iface in config.interfaces): %}
			{%
				if (iface?.role != "upstream" && iface?.role != "downstream")
					continue;

				// In router mode, only process first downstream interface (groups all VLANs)
				if (deployment_mode == "router" && iface?.role == "downstream") {
					if (router_mode_downstream_done)
						continue;
					router_mode_downstream_done = true;
				}

				// In bridge mode, skip VLAN sub-interfaces (rendered as VIFs)
                // In bridge mode, only process first downstream interface (groups all VLANs as VIFs)
                if (deployment_mode == "bridge" && iface?.role == "downstream") {
                    if (bridge_mode_downstream_done)
                        continue;
                    bridge_mode_downstream_done = true;
                }

				let role = iface.role;
				let members = ethernet.lookup_interface_by_port(iface);
				ethernet.mark_eth_used(members, eth_used);
			%}

			{% if (deployment_mode == "router"): %}
				{# Router mode: Generate direct ethernet interfaces (no bridges) #}
{{ include('interface/router.uc', { config, role, iface, members }) }}

			{% else %}
				{# Bridge mode: Generate bridge-based architecture (legacy behavior) #}
				{%
					let br_name;
					if (role == "upstream" && !upstream_assigned) {
						br_name = ethernet.upstream_bridge_name();
						upstream_assigned = true;
					}
					else {
						br_name = ethernet.calculate_next_bridge_name(next_br_index);
						next_br_index++;
					}
				%}
{{ include('interface/bridge.uc', { config, role, br_name, iface, members }) }}

			{% endif %}
		{% endfor %}
	{% endif %}

	{% if (deployment_mode == "bridge"): %}
		{# In bridge mode, generate empty ethernet interface definitions #}
		{%
			let eth_list = sort(keys(eth_used));
		%}
{{ include('interface/ethernet.uc', { eth_list }) }}
	{% endif %}

	{# Always include loopback interface #}
	loopback lo
}
