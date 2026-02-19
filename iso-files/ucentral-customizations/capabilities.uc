#!/usr/bin/ucode
push(REQUIRE_SEARCH_PATH,
	"/usr/lib/ucode/*.so",
	"/usr/share/ucentral/*.uc");

let fs = require("fs");
let vyos_api = require("vyos.https_server_api");

// Read version files (same as AP pattern)
let version = json(fs.readfile('/etc/ucentral/version.json') || '{}');
let schema = json(fs.readfile('/etc/ucentral/schema.json') || '{}');

// Read existing capabilities for fallback (WAN/LAN interface roles)
let old_caps = json(fs.readfile('/etc/ucentral/capabilities.json') || '{}');

// Initialize capabilities with static/fallback values
let capabilities = {
	"secure-rtty": true,
	"compatible": "vyos-olg",
	"model": "VyOS OLG Gateway",
	"platform": "olg",
	"firmware": "VyOS 2025.12.13-0020-rolling",
	"hostname": "vyos",
	"version": {
		"olg": version,
		"schema": schema
	},
	"network": {
		"wan": old_caps?.network?.wan || ["eth0"],
		"lan": old_caps?.network?.lan || ["eth1"]
	},
	"macaddr": {
		"wan": "",
		"lan": ""
	},
	"label_macaddr": "",
	"interfaces": {
		"ethernet": []
	},
	"hardware_offload": {
		"gro": false,
		"gso": false,
		"sg": false,
		"tso": false
	},
	"services": {
		"https_api": false,
		"ssh": false,
		"ntp": false,
		"dns_forwarding": false,
		"dhcp_server": false
	}
};

// Try to query VyOS for dynamic data
try {
	// Read VyOS connection info
	let vyos_info = json(fs.readfile('/etc/ucentral/vyos-info.json') || '{}');

	if (vyos_info.host && vyos_info.key) {
		// Query VyOS for full configuration in JSON format
		let response = vyos_api.vyos_api_call(
			{ path: ["configuration", "json"] },
			"show",
			vyos_info.host,
			vyos_info.key
		);

		let config = json(response);

		if (config && config.success && config.data) {
			// data is a JSON string, parse it again
			let data = json(config.data);

			// Extract hostname
			if (data.system && data.system["host-name"]) {
				capabilities.hostname = data.system["host-name"];
			}

			// Extract ethernet interfaces
			if (data.interfaces && data.interfaces.ethernet) {
				capabilities.interfaces.ethernet = keys(data.interfaces.ethernet);

				// Extract MAC addresses
				let wan_if = capabilities.network.wan[0] || "eth0";
				let lan_if = capabilities.network.lan[0] || "eth1";

				if (data.interfaces.ethernet[wan_if] && data.interfaces.ethernet[wan_if]["hw-id"]) {
					capabilities.macaddr.wan = data.interfaces.ethernet[wan_if]["hw-id"];
					capabilities.label_macaddr = data.interfaces.ethernet[wan_if]["hw-id"];
				}

				if (data.interfaces.ethernet[lan_if] && data.interfaces.ethernet[lan_if]["hw-id"]) {
					capabilities.macaddr.lan = data.interfaces.ethernet[lan_if]["hw-id"];
				}

				// Extract hardware offload capabilities (from any interface that has it)
				for (let ifname in data.interfaces.ethernet) {
					let iface = data.interfaces.ethernet[ifname];
					if (iface.offload) {
						capabilities.hardware_offload.gro = ("gro" in iface.offload);
						capabilities.hardware_offload.gso = ("gso" in iface.offload);
						capabilities.hardware_offload.sg = ("sg" in iface.offload);
						capabilities.hardware_offload.tso = ("tso" in iface.offload);
						break; // Only need to check one interface
					}
				}
			}

			// Extract service capabilities
			if (data.service) {
				capabilities.services.https_api = (data.service.https && data.service.https.api) ? true : false;
				capabilities.services.ssh = (data.service.ssh) ? true : false;
				capabilities.services.ntp = (data.service.ntp) ? true : false;
				capabilities.services.dns_forwarding = (data.service.dns && data.service.dns.forwarding) ? true : false;
				capabilities.services.dhcp_server = (data.service["dhcp-server"]) ? true : false;
			}
		}
	}
} catch (e) {
	// If VyOS API fails, use fallback values (already initialized)
	warn("Failed to query VyOS API, using fallback values: " + e + "\n");
}

// Write capabilities to file
fs.writefile('/etc/ucentral/capabilities.json', capabilities);
