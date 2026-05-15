#!/bin/sh
set -eu

state_dir=/var/lib/nginx-mtc-acme
private_dir="${state_dir}/private"
cert_dir="${state_dir}/certs"
acme_dir="${state_dir}/dehydrated"
wellknown_dir="${state_dir}/wellknown"

leaf_key="${private_dir}/leaf.key"
leaf_csr="${cert_dir}/leaf.csr"
leaf_cert="${cert_dir}/leaf.crt"
dehydrated_config="${acme_dir}/config"

: "${ACME_DIRECTORY_URL:=http://ca.mtc-demo.test:14000/directory}"
: "${CERT_CN:=nginx-mtc-acme.mtc-demo.test}"
: "${CERT_DNS_NAMES:=nginx-mtc-acme.mtc-demo.test,localhost}"

mkdir -p "${private_dir}" "${cert_dir}" "${acme_dir}" "${wellknown_dir}"

if [ ! -f "${leaf_key}" ]; then
  openssl genpkey -algorithm ML-DSA-44 -out "${leaf_key}"
  chmod 600 "${leaf_key}"
fi

san=""
old_ifs="${IFS}"
IFS=","
for name in ${CERT_DNS_NAMES}; do
  name="$(printf '%s' "${name}" | sed 's/^ *//;s/ *$//')"
  [ -n "${name}" ] || continue
  if [ -n "${san}" ]; then
    san="${san},"
  fi
  san="${san}DNS:${name}"
done
IFS="${old_ifs}"

openssl req -new \
  -key "${leaf_key}" \
  -out "${leaf_csr}" \
  -subj "/CN=${CERT_CN}" \
  -addext "subjectAltName=${san}"

cat > "${dehydrated_config}" <<EOF
CA="${ACME_DIRECTORY_URL}"
CHALLENGETYPE="http-01"
WELLKNOWN="${wellknown_dir}"
EOF

dehydrated \
  --config "${dehydrated_config}" \
  --accept-terms \
  --register

tmp_cert="${leaf_cert}.tmp"
dehydrated \
  --config "${dehydrated_config}" \
  --accept-terms \
  --signcsr "${leaf_csr}" > "${tmp_cert}"
mv "${tmp_cert}" "${leaf_cert}"

nginx -t
exec nginx -g "daemon off;"
