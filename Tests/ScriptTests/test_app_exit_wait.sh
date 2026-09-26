#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../../scripts/_package_common.sh"
# Function stubs avoid touching real processes and avoid a ten-second test delay.
ticks=0
pgrep() { return 0; }
sleep() { [ "$1" = "0.2" ]; ticks=$((ticks + 1)); }
if wait_for_app_exit 2>/dev/null; then
    echo 'FAIL: live app must abort packaging' >&2
    exit 1
fi
[ "$ticks" -eq 50 ]
ticks=0
pgrep() { [ "$ticks" -lt 7 ]; }
wait_for_app_exit
[ "$ticks" -eq 7 ]
ticks=0
pgrep() { return 1; }
wait_for_app_exit
[ "$ticks" -eq 0 ]
echo 'app exit wait: 3 passed'
