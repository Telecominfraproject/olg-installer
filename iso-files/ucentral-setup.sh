#!/usr/bin/env bash
set -e

ACTION="$1"

# ================= CONFIG =================
CONTAINER="ucentral-olg"
IMAGE="mjhnetexp/ucentral-client:olgV6"

BRIDGE="br-wan"

HOST_VETH="veth-${CONTAINER:0:5}-h"
CONT_VETH="veth-${CONTAINER:0:5}-c"
CONT_IF="eth0"

# Volume mounts for runtime configuration only (code files now in image)
DOCKER_RUN_OPTS="--privileged --network none \
  -v /opt/ucentral-persistent/config:/etc/config \
  -v /opt/ucentral-persistent/config-shadow:/etc/config-shadow \
  -v /opt/ucentral-persistent/ucentral:/etc/ucentral"
# ==========================================

usage() {
    echo "Usage: $0 setup | cleanup | shell"
    exit 1
}

[ -z "$ACTION" ] && usage

container_pid() {
    docker inspect -f '{{.State.Pid}}' "$CONTAINER" 2>/dev/null
}

container_exists() {
    docker inspect "$CONTAINER" &>/dev/null
}

container_running() {
    docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null | grep -q true
}

veth_exists() {
    ip link show "$HOST_VETH" &>/dev/null
}

attached_to_bridge() {
    bridge link show | grep -q "$HOST_VETH"
}

setup() {
    echo "[+] Setup container on $BRIDGE"

    if ! container_exists; then
        echo "[+] Creating container $CONTAINER"
        docker run -dit --name "$CONTAINER" $DOCKER_RUN_OPTS "$IMAGE"
    fi

    if ! container_running; then
        echo "[+] Starting container"
        docker start "$CONTAINER"
    fi

    PID=$(container_pid)
    [ -z "$PID" ] && { echo "Failed to get container PID"; exit 1; }

    if veth_exists && attached_to_bridge; then
        echo "[!] Setup already done: container already attached to $BRIDGE"
        exit 0
    fi

    echo "[+] Creating veth pair"
    ip link add "$HOST_VETH" type veth peer name "$CONT_VETH"

    echo "[+] Attaching host veth to bridge $BRIDGE"
    ip link set "$HOST_VETH" master "$BRIDGE"
    ip link set "$HOST_VETH" up

    echo "[+] Moving container veth into netns"
    ip link set "$CONT_VETH" netns "$PID"

    echo "[+] Configuring container interface"
    nsenter -t "$PID" -n sh <<'EOF'
ip link set lo up
ip link set veth-ucent-c name eth0 2>/dev/null || true
ip link set eth0 up
EOF

    # Run DHCP client using docker exec (needs container filesystem for udhcpc script)
    docker exec "$CONTAINER" sh -c 'udhcpc -i eth0 -b -p /var/run/udhcpc.eth0.pid -s /usr/share/udhcpc/default.script'

    echo "[+] Disabling container firewall (allows VyOS API and cloud connectivity)"
    docker exec "$CONTAINER" /etc/init.d/firewall disable 2>/dev/null || true
    docker exec "$CONTAINER" /etc/init.d/firewall stop 2>/dev/null || true

    echo "[+] Fixing state.uc symlink (point to VyOS version)"
    docker exec "$CONTAINER" sh -c 'rm -f /usr/share/ucentral/state.uc && ln -s /usr/share/ucentral/vyos/state.uc /usr/share/ucentral/state.uc'

    echo "[✓] Setup complete"
    echo ""
    echo "IMPORTANT: Verify vyos-info.json exists and has correct VyOS IP:"
    echo "  sudo cat /opt/ucentral-persistent/ucentral/vyos-info.json"
    echo ""
    echo "If the file is missing or IP is incorrect, create/update it with:"
    echo "  echo '{\"host\":\"https://VYOS_WAN_IP\",\"port\":443,\"key\":\"MY-HTTPS-API-PLAINTEXT-KEY\"}' | sudo tee /opt/ucentral-persistent/ucentral/vyos-info.json"
    echo ""
}

cleanup() {
    local did_something=false

    if veth_exists; then
        echo "[+] Removing veth"
        ip link del "$HOST_VETH"
        did_something=true
    fi

    if container_exists; then
        echo "[+] Stopping container"
        docker stop "$CONTAINER" || true

        echo "[+] Removing container"
        docker rm "$CONTAINER" || true
        did_something=true
    fi

    if ! $did_something; then
        echo "[!] Nothing to cleanup"
    else
        echo "[✓] Cleanup complete"
    fi
}

shell() {
    if ! container_exists; then
        echo "Container $CONTAINER does not exist"
        exit 1
    fi

    if ! container_running; then
        echo "Container $CONTAINER is not running"
        exit 1
    fi

    echo "[+] Opening shell in $CONTAINER"
    exec docker exec -it "$CONTAINER" /bin/ash
}

case "$ACTION" in
    setup)   setup ;;
    cleanup) cleanup ;;
    shell)   shell ;;
    *) usage ;;
esac
