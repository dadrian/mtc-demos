#!/bin/sh
set -eu

seed_dir=/var/lib/cactus/keys
seed_file="${seed_dir}/ca-cosigner.seed"
seed_source=/cactus-demo/keys/ca-cosigner.seed.b64

mkdir -p "${seed_dir}"

if [ ! -f "${seed_file}" ]; then
  base64 -d "${seed_source}" > "${seed_file}"
  chmod 600 "${seed_file}"
fi

seed_size="$(wc -c < "${seed_file}" | tr -d ' ')"
if [ "${seed_size}" != "32" ]; then
  echo "ca-cosigner seed must be 32 bytes, got ${seed_size}" >&2
  exit 1
fi

exec /usr/local/bin/cactus -config /etc/cactus/config.json
