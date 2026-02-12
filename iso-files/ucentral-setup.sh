#!/usr/bin/env bash
set -e

ACTION="$1"

# ================= CONFIG =================
CONTAINER="ucentral-olg"
IMAGE="routerarchitect123/ucentral-client:olgV5"

BRIDGE="br-wan"

HOST_VETH="veth-${CONTAINER:0:5}-h"
CONT_VETH="veth-${CONTAINER:0:5}-c"
CONT_IF="eth0"

DOCKER_RUN_OPTS="--privileged --network none"
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
    nsenter -t "$PID" -n -m -p sh <<EOF
ip link set lo up
ip link set "$CONT_VETH" name "$CONT_IF"
ip link set "$CONT_IF" up
udhcpc -i "$CONT_IF" -b -p /var/run/udhcpc.eth0.pid -s /usr/share/udhcpc/default.script
ubusd &
EOF

    echo "[✓] Setup complete"
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
