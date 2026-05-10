#!/usr/bin/env bash
set -euo pipefail

BOARD_IP="${1:-192.168.2.1}"

echo "== Network =="
ip -br addr
echo

echo "== Ping ${BOARD_IP} =="
ping -c 4 "${BOARD_IP}"
echo

echo "== IIO explicit IP context =="
iio_info -u "ip:${BOARD_IP}" | sed -n '1,220p'
echo

echo "== HTTP probe =="
curl --max-time 5 --silent --show-error "http://${BOARD_IP}/" | sed -n '1,40p'
