#!/usr/bin/env ucode
// Test script for deployment mode detection

// Minimal ethernet object for testing
let ethernet = {
	detect_deployment_mode: function(config) {
		// Check for explicit deployment mode setting
		if (type(config.deployment_mode) == "string") {
			let mode = lc(config.deployment_mode);
			if (mode == "bridge")
				return "bridge";
			if (mode == "router")
				return "router";
		}

		// Check if any interface explicitly requests bridge mode
		if (type(config.interfaces) == "array") {
			for (let iface in config.interfaces) {
				// Look for bridge=true or bridge_mode=true flags
				if (iface.bridge === true || iface.bridge_mode === true)
					return "bridge";
			}
		}

		// Default to router mode (OLG gateway use case)
		return "router";
	}
};

// Test cases
let tests = [
	{
		name: "Test 1: Empty config (should default to router)",
		config: {},
		expected: "router"
	},
	{
		name: "Test 2: Config with no interfaces (should default to router)",
		config: { interfaces: [] },
		expected: "router"
	},
	{
		name: "Test 3: Explicit router mode",
		config: { deployment_mode: "router" },
		expected: "router"
	},
	{
		name: "Test 4: Explicit bridge mode",
		config: { deployment_mode: "bridge" },
		expected: "bridge"
	},
	{
		name: "Test 5: Interface with bridge flag",
		config: {
			interfaces: [
				{ role: "downstream", bridge: true }
			]
		},
		expected: "bridge"
	},
	{
		name: "Test 6: Interface with bridge_mode flag",
		config: {
			interfaces: [
				{ role: "downstream", bridge_mode: true }
			]
		},
		expected: "bridge"
	},
	{
		name: "Test 7: OLG typical config (no bridge flags)",
		config: {
			interfaces: [
				{ role: "upstream", ethernet: [{ select_ports: ["WAN*"] }] },
				{ role: "downstream", ethernet: [{ select_ports: ["LAN*"] }] }
			]
		},
		expected: "router"
	},
	{
		name: "Test 8: Mixed mode - explicit deployment overrides interface flags",
		config: {
			deployment_mode: "router",
			interfaces: [
				{ role: "downstream", bridge: true }
			]
		},
		expected: "router"
	}
];

// Run tests
let passed = 0;
let failed = 0;

for (let test in tests) {
	let result = ethernet.detect_deployment_mode(test.config);
	let status = (result == test.expected) ? "✓ PASS" : "✗ FAIL";

	if (result == test.expected) {
		passed++;
	} else {
		failed++;
	}

	printf("%s: %s\n", status, test.name);
	if (result != test.expected) {
		printf("  Expected: %s, Got: %s\n", test.expected, result);
	}
}

printf("\n===========================================\n");
printf("Test Results: %d passed, %d failed\n", passed, failed);
printf("===========================================\n");

// Exit with appropriate code
exit(failed > 0 ? 1 : 0);
