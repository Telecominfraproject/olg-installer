// This file is to generatre full VyOS style configuration from uCentral config

let fs = require("fs");
let vyos_api = require("vyos.https_server_api");
function load_capabilities() {
	let capabfile = fs.open("/etc/ucentral/capabilities.json", "r");
	if (!capabfile)
		return null;

	let data = capabfile.read("all");
	capabfile.close();

	return json(data);
}
function split_ip_prefix(ip_prefix){
    if (type(ip_prefix)!="string") return null;
    let p = split(ip_prefix, "/"); if (length(p)!=2) return null; return p;
}
function ip_to_tuple(ip){
    let parts = split(ip, "."); if (length(parts)!=4) return null;
    let t=[]; for (let i=0;i<4;i++){ let n=int(parts[i]); if (n<0||n>255) return null; push(t,n); }
    return t;
}
function tuple_to_ip(t){ return sprintf("%d.%d.%d.%d", t[0],t[1],t[2],t[3]); }
function tuple_to_int(t){ return ((t[0]&255)<<24)|((t[1]&255)<<16)|((t[2]&255)<<8)|(t[3]&255); }
function int_to_tuple(n){ n = n & 0xFFFFFFFF; return [ (n>>24)&255, (n>>16)&255, (n>>8)&255, n&255 ]; }
function prefix_to_mask(p){ p=int(p); if(p<0)p=0; if(p>32)p=32; return p==0?0:((0xFFFFFFFF<<(32-p))&0xFFFFFFFF); }
function add_host(ip, add){
    let t=ip_to_tuple(ip); if(!t) return null;
    let n=tuple_to_int(t); n=(n+add)&0xFFFFFFFF;
    return tuple_to_ip(int_to_tuple(n));
}
function network_base(ip_prefix){
    let parts=split_ip_prefix(ip_prefix); if(!parts) return null;
    let ipt=ip_to_tuple(parts[0]); if(!ipt) return null;
    let p=int(parts[1]); let mask=prefix_to_mask(p);
    let ipn=tuple_to_int(ipt); let netn=ipn&mask; let nett=int_to_tuple(netn);
    return [ tuple_to_ip(nett)+"/"+p, parts[1], tuple_to_ip(nett), netn, p ];
}
function convert_lease_time_to_seconds(s, def){
    if (type(s)=="number") return int(s);
    if (type(s)!="string") return def;
    let m = match(s, /^([0-9]+)\s*([smhd])$/);
    if (!m){ let n=int(s); return n>0?n:def; }
    let n=int(m[1]), u=m[2];
    if(u=="s") return n;
    if(u=="m") return n*60;
    if(u=="h") return n*3600;
    if(u=="d") return n*86400;
    return def;
}
function vyos_retrieve_info(op_arg, op)
{
	let args_path = "/etc/ucentral/vyos-info.json";
	let args = {};
	if (fs.stat(args_path)) {
		let f = fs.open(args_path, "r");
		args = json(f.read("all"));
		f.close();
	}

	let host = args.host;
	let key  = args.key;
	let resp = vyos_api.vyos_api_call(op_arg, op, host, key);
	//TODO:Check Return Value and handle response from here
	let jsn = json(resp);
	return jsn;
}

let ethernet = {
	ports: {},

	// Discover logical ports (WAN, LAN, LAN1, LAN2...) -> { netdev, index }
	discover_ports: function() {
		let capab = load_capabilities();
		if (!capab || type(capab.network) != "object")
			return {};

		let roles = {};
		let ret_val = {};

		for (let role, spec in capab.network) {
			if (type(spec) != "array")
				continue;

			for (let i, ifname in spec) {
				role = uc(role);
				let netdev = split(ifname, ':');  // eth0 or eth0:5 (ignore suffix)
				let port = { netdev: netdev[0], index: i };
				push(roles[role] = roles[role] || [], port);
			}
		}

		for (let role, ports in roles) {
			map(sort(ports, (a, b) => (a.index - b.index)), (port, i) => {
					ret_val[role + (i + 1)] = port;
				});
		}

		return ret_val;
	},

	init: function() {
		this.ports = this.discover_ports();
		return this;
	},

	// Match select-ports globs against ethernet.ports
	lookup: function(globs) {
		let matched = {};

		for (let glob, _ in globs) {
			for (let name, spec in this.ports) {
				if (wildcard(name, glob) && spec?.netdev)
					matched[spec.netdev] = true;
			}
		}

		return matched;
	},

	lookup_interface_by_port: function(interface) {
		let globs = {};

		if (type(interface?.ethernet) != "array")
			return [];

		map(interface.ethernet, eth => {
			if (type(eth?.select_ports) == "array")
				map(eth.select_ports, glob => globs[glob] = true);
		});

		return sort(keys(this.lookup(globs)));
	},

	mark_eth_used: function(list, used_map) {
		if (type(used_map) != "object" || type(list) != "array")
			return;

		for (let m in list) {
			if (type(m) == "string" && length(m))
				used_map[m] = true;
		}
	},

	upstream_bridge_name: function() {
		return "br0";
	},

	calculate_next_bridge_name: function(next_br_index) {
		return "br" + next_br_index;
	}
};


return {
	vyos_render: function(config) {
		ethernet.init();
		let op_arg = { };
		let op = "showConfig";
		op_arg.path = ["pki"];

		let rc = vyos_retrieve_info(op_arg, op);
		let pki = render('templates/pki.uc', {rc});

		let interfaces = render('templates/interface.uc', {
			config,
			ethernet
		});

		op_arg.path = ["system", "login"];
		let systeminfo = vyos_retrieve_info(op_arg, op);
		op_arg.path = ["system", "console"];
		let consoleinfo = vyos_retrieve_info(op_arg, op);
		let system = render('templates/system.uc',{systeminfo, consoleinfo});

		let nat = render('templates/nat.uc', {
			config,
			ethernet,
			network_base
		});

		op_arg.path = ["service", "https"];
		let https = vyos_retrieve_info(op_arg, op);
		let services = render('templates/service.uc', {
			config,
			https,
			split_ip_prefix,
			network_base,
			add_host,
			ip_to_tuple,
			prefix_to_mask,
			tuple_to_int,
			tuple_to_ip,
			int_to_tuple,
			convert_lease_time_to_seconds
		});
		//TODO: Need to understand Firmware Upgrade and Migration Logic of VyOS then modify this
		let vyos_version = render('templates/version.uc');

		return interfaces + "\n" + nat + "\n" + services + "\n" + pki + "\n" + system + "\n" + vyos_version + "\n";
	}
};
