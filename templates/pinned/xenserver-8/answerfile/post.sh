#!/bin/sh
# Runs in the installer with the freshly installed root at $1.
ROOT="$1"
mkdir -p "$ROOT/etc/dissect-smoketest"
cat > "$ROOT/etc/dissect-smoketest/provisioned" <<EOF
template=xenserver-8
lifecycle=pinned
EOF
