{%
	let lans = [];
	if (type(config.interfaces) == "array") {
		for (let iface in config.interfaces) {
			if (iface.role != "downstream")
				continue;
			//TODO: Modify this code for multiple downstream and make a common
			// func for repetitive code
			// ----- Base LAN IPv4 -----
			if (type(iface.ipv4) == "object" &&
			    iface.ipv4.addressing == "static" &&
			    type(iface.ipv4.subnet) == "string") {

				let parts = split_ip_prefix(iface.ipv4.subnet);
				if (parts) {
					let lan_ip = parts[0];

					let nb = network_base(iface.ipv4.subnet);
					if (nb) {
						let net_ip_prefix = nb[0]; // 192.168.50.0/24
						let net_ip   = nb[2]; // 192.168.50.0

						let lease_secs  = 21600; // default 6h
						let range_start = null;
						let range_stop  = null;

						let dhcp = iface.ipv4.dhcp || {};

						let lt = (dhcp["lease-time"] != null) ? dhcp["lease-time"] : dhcp["lease_time"];
						if (lt)
							lease_secs = convert_lease_time_to_seconds(lt, lease_secs);

						let lf = (dhcp["lease-first"] != null) ? dhcp["lease-first"] : dhcp["lease_first"];
						let first = lf ? int(lf) : 10;
						if (first < 1)
							first = 1;

						range_start = add_host(net_ip, first);

						let lc = (dhcp["lease-count"] != null) ? dhcp["lease-count"] : dhcp["lease_count"];
						let count = lc ? int(lc) : 100;
						if (count < 1)
							count = 1;

						if (range_start)
							range_stop = add_host(range_start, count - 1);
				
						let subnet_id = (type(iface.vlan) == "object" && iface.vlan.id) ? int(iface.vlan.id) : (4051 + int(iface.index));
			
						if (range_start && range_stop) {
							push(lans, {
								name: iface.name || "LAN",
								lan_ip,
								net_ip_prefix,
								lease_secs,
								range_start,
								range_stop,
								subnet_id: subnet_id
							});
						}
					}
				}
			}

		}
	}

	// SSH port
	let ssh_port = 22;
	if (type(config.services) == "object" &&
	    type(config.services.ssh) == "object" &&
	    config.services.ssh.port)
		ssh_port = int(config.services.ssh.port);

	let https_enabled     = false;
	let https_allow_from  = [];
	let https_keys        = [];
	let https_ca_cert     = null;
	let https_cert        = null;
	let https_port        = 443;

	if (type(https) == "object" &&
	    https.success === true &&
	    type(https.data) == "object") {

		let h = https.data;

		// ----- allow-client -----
		if (type(h["allow-client"]) == "object") {
			let ac = h["allow-client"];

			if (type(ac.address) == "string") {
				push(https_allow_from, ac.address);
			} else if (type(ac.address) == "array") {
				for (let addr in ac.address) {
					if (type(addr) == "string")
						push(https_allow_from, addr);
				}
			}
		}

		// ----- api keys -----
		if (type(h.api) == "object" &&
		    type(h.api.keys) == "object" &&
		    type(h.api.keys.id) == "object") {

			for (let kid in keys(h.api.keys.id)) {
				let kobj = h.api.keys.id[kid];
				if (type(kobj) == "object" && kobj.key) {
					push(https_keys, { id: kid, key: kobj.key });
				}
			}
		}

		// ----- certificates -----
		if (type(h.certificates) == "object") {
			if (type(h.certificates["ca-certificate"]) == "string")
				https_ca_cert = h.certificates["ca-certificate"];

			if (type(h.certificates.certificate) == "string")
				https_cert = h.certificates.certificate;
		}

		// ----- port -----
		if (h.port)
			https_port = int(h.port);

		https_enabled = true;
	}
%}
service {
    {% include('services/dhcp-server.uc', {lans}); %}
    {% include('services/dns-forwarding.uc', {lans}); %}
    {% include('services/ssh.uc', {ssh_port}); %}
    {% include('services/https.uc', {https_enabled, https_allow_from, https_keys, https_ca_cert, https_cert, https_port}); %}
}
