#!/bin/vbash
# VyOS System Statistics - Operational Mode Wrapper
#
# This script makes the Python helper callable via VyOS REST API.
# Place this file at: /opt/vyatta/bin/vyos-system-stats
#
# Callable via: /show with path ["system", "stats"]
# or from VyOS CLI: show system stats

/config/scripts/vyos-system-stats.py
