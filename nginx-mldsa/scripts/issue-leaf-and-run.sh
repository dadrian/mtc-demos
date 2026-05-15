#!/bin/sh
set -eu

cert_dir="${CERT_DIR:-/etc/nginx/certs}"
root_cert="${cert_dir}/root.crt"
root_key="${cert_dir}/root.key"
leaf_key="${cert_dir}/leaf.key"
leaf_csr="${cert_dir}/leaf.csr"
leaf_cert="${cert_dir}/leaf.crt"
dns_names="${CERT_DNS_NAMES:-nginx-mldsa.mtc-demo.test,localhost}"
leaf_subject="${CERT_SUBJECT:-/CN=nginx-mldsa.mtc-demo.test}"
leaf_days="${CERT_DAYS:-30}"

if [ ! -s "${root_cert}" ] || [ ! -s "${root_key}" ]; then
  echo "missing committed ML-DSA-44 root certificate or key in ${cert_dir}" >&2
  exit 1
fi

if [ ! -s "${leaf_key}" ] || [ ! -s "${leaf_cert}" ]; then
  tmp_ext="$(mktemp)"
  trap 'rm -f "${tmp_ext}"' EXIT

  if [ ! -s "${leaf_key}" ]; then
    openssl genpkey -algorithm ML-DSA-44 -out "${leaf_key}"
  fi

  san=""
  old_ifs="${IFS}"
  IFS=","
  for name in ${dns_names}; do
    IFS="${old_ifs}"
    name="$(printf '%s' "${name}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    if [ -n "${name}" ]; then
      if [ -n "${san}" ]; then
        san="${san},"
      fi
      san="${san}DNS:${name}"
    fi
    IFS=","
  done
  IFS="${old_ifs}"

  if [ -z "${san}" ]; then
    echo "CERT_DNS_NAMES must contain at least one DNS name" >&2
    exit 1
  fi

  cat >"${tmp_ext}" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=${san}
EOF

  openssl req -new -key "${leaf_key}" -out "${leaf_csr}" -subj "${leaf_subject}"
  openssl x509 -req \
    -in "${leaf_csr}" \
    -CA "${root_cert}" \
    -CAkey "${root_key}" \
    -out "${leaf_cert}" \
    -days "${leaf_days}" \
    -set_serial 0x$(openssl rand -hex 16) \
    -extfile "${tmp_ext}"
fi

nginx -t
exec nginx -g "daemon off;"
