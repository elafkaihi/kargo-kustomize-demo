#!/bin/sh
# Starts the real podinfo, then switches on fault injection once it listens.
/home/app/podinfo-bin "$@" &
pid=$!
trap 'kill -TERM "$pid"' TERM INT
until wget -q -O /dev/null --post-data='' http://127.0.0.1:9898/fault_injection/enable; do
  kill -0 "$pid" 2>/dev/null || exit 1
  sleep 1
done
wait "$pid"
