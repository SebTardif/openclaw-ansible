#!/usr/bin/env bash
# shellcheck disable=SC2016  # $ in this file is awk and playbook text, not shell.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
task="$root/roles/openclaw/tasks/firewall-linux.yml"
parser='{for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit }}'

if ! grep -Fq "$parser" "$task"; then
    echo 'firewall-linux.yml does not use the tested default-route parser.' >&2
    exit 1
fi
if grep -Fq 'print $5' "$task"; then
    echo 'firewall-linux.yml still takes field 5 as the interface.' >&2
    exit 1
fi
if ! grep -Fq '/sys/class/net/' "$task"; then
    echo 'firewall-linux.yml does not check that the interface exists.' >&2
    exit 1
fi

extract_dev() {
    awk "$parser"
}

expect() {
    local input=$1
    local want=$2
    local got
    got=$(printf '%s\n' "$input" | extract_dev)
    if [ "$got" != "$want" ]; then
        echo "expected '$want' from [$input] but got '$got'" >&2
        exit 1
    fi
}

expect 'default via 192.0.2.1 dev eth0 proto dhcp src 192.0.2.15 metric 100' eth0
expect 'default dev ppp0 scope link' ppp0
expect 'default dev venet0 scope link' venet0

got=$(printf '%s\n' \
    'default proto static metric 100' \
    'nexthop via 192.0.2.1 dev eth1 weight 1' \
    'nexthop via 198.51.100.1 dev eth2 weight 1' | extract_dev)
if [ "$got" != "eth1" ]; then
    echo "expected eth1 from a multipath default route but got '$got'" >&2
    exit 1
fi

old=$(printf '%s\n' 'default dev ppp0 scope link' | awk '{print $5}')
if [ "$old" = "ppp0" ]; then
    echo 'the field-5 fixture no longer shows the old parse.' >&2
    exit 1
fi

sysfs=$(mktemp -d)
trap 'rm -rf "$sysfs"' EXIT
mkdir -p "$sysfs/eth0" "$sysfs/ppp0" "$sysfs/venet0" "$sysfs/eth1"
for name in eth0 ppp0 venet0 eth1; do
    if [ ! -d "$sysfs/$name" ]; then
        echo "detected interface '$name' does not exist" >&2
        exit 1
    fi
done
if [ -d "$sysfs/$old" ]; then
    echo "field 5 result '$old' must not be treated as an interface" >&2
    exit 1
fi

echo 'default route interface parse: PASSED'
