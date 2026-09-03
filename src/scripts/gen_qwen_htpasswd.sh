#!/bin/sh
# Generates the nginx basic-auth htpasswd entry for QwenCode Web.
# Usage: sh scripts/gen_qwen_htpasswd.sh '<password>'
set -e
mkdir -p "$(dirname "$0")/../.tmp"
printf 'qwen:%s\n' "$(openssl passwd -6 "$1")" > "$(dirname "$0")/../.tmp/qwen_htpasswd"
echo "wrote $(dirname "$0")/../.tmp/qwen_htpasswd"
