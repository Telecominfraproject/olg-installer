#!/usr/bin/env python3
"""
VyOS System Statistics Helper Script

Gathers system metrics and outputs structured JSON for uCentral state reporting.
This script leverages Linux /proc filesystem and 'ip -json' commands to provide
structured data instead of requiring text parsing in uCentral.

Called via VyOS REST API: /show ["system", "stats"]
"""

import json
import subprocess
import sys


def get_uptime():
    """
    Read system uptime from /proc/uptime.

    Returns:
        int: Uptime in seconds
    """
    try:
        with open('/proc/uptime', 'r') as f:
            uptime_str = f.read().split()[0]  # First field is uptime in seconds
            return int(float(uptime_str))
    except Exception as e:
        sys.stderr.write(f"Error reading uptime: {e}\n")
        return 0


def get_loadavg():
    """
    Read system load average from /proc/loadavg.

    Returns:
        list: [1min, 5min, 15min] load averages as floats
    """
    try:
        with open('/proc/loadavg', 'r') as f:
            parts = f.read().split()
            return [float(parts[0]), float(parts[1]), float(parts[2])]
    except Exception as e:
        sys.stderr.write(f"Error reading load average: {e}\n")
        return [0.0, 0.0, 0.0]


def get_memory():
    """
    Read memory statistics from /proc/meminfo and convert to bytes.

    Returns:
        dict: Memory stats with keys 'total', 'free', 'cached', 'buffered'
    """
    mem = {}
    try:
        with open('/proc/meminfo', 'r') as f:
            for line in f:
                if ':' in line:
                    key, value = line.split(':', 1)
                    key = key.strip()
                    if 'kB' in value:
                        # Convert kB to bytes
                        value_kb = int(value.replace('kB', '').strip())
                        mem[key] = value_kb * 1024
    except Exception as e:
        sys.stderr.write(f"Error reading memory info: {e}\n")

    return {
        'total': mem.get('MemTotal', 0),
        'free': mem.get('MemFree', 0),
        'cached': mem.get('Cached', 0),
        'buffered': mem.get('Buffers', 0)
    }


def get_interface_stats():
    """
    Get interface statistics using 'ip -json -stats link show'.

    Returns:
        list: Interface stats as JSON array (already structured)
    """
    try:
        result = subprocess.run(
            ['ip', '-json', '-stats', 'link', 'show'],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode == 0:
            return json.loads(result.stdout)
        else:
            sys.stderr.write(f"Error running 'ip -json -stats link show': {result.stderr}\n")
            return []
    except subprocess.TimeoutExpired:
        sys.stderr.write("Timeout running 'ip -json -stats link show'\n")
        return []
    except Exception as e:
        sys.stderr.write(f"Error getting interface stats: {e}\n")
        return []


def get_interface_addresses():
    """
    Get interface IP addresses using 'ip -json addr show'.

    Returns:
        list: Interface address info as JSON array
    """
    try:
        result = subprocess.run(
            ['ip', '-json', 'addr', 'show'],
            capture_output=True,
            text=True,
            timeout=5
        )

        if result.returncode == 0:
            return json.loads(result.stdout)
        else:
            sys.stderr.write(f"Error running 'ip -json addr show': {result.stderr}\n")
            return []
    except subprocess.TimeoutExpired:
        sys.stderr.write("Timeout running 'ip -json addr show'\n")
        return []
    except Exception as e:
        sys.stderr.write(f"Error getting interface addresses: {e}\n")
        return []


def main():
    """
    Main function: gather all metrics and output as JSON.
    """
    data = {
        'uptime': get_uptime(),
        'load': get_loadavg(),
        'memory': get_memory(),
        'interfaces': get_interface_stats(),
        'addresses': get_interface_addresses()
    }

    # Output JSON to stdout
    print(json.dumps(data, indent=2))


if __name__ == '__main__':
    main()
