#!/bin/sh
set -eu

state_dir=/var/lib/nginx-mtc-acme
private_dir="${state_dir}/private"
cert_dir="${state_dir}/certs"
lego_dir="${state_dir}/lego"
wellknown_dir="${state_dir}/wellknown"

leaf_key="${private_dir}/leaf.key"
leaf_csr="${cert_dir}/leaf.csr"
leaf_cert="${cert_dir}/leaf.crt"

: "${ACME_DIRECTORY_URL:=https://ca.mtc-demo.test:14000/directory}"
: "${ACME_EMAIL:=demo@example.invalid}"
: "${CERT_CN:=nginx-mtc-acme.mtc-demo.test}"
: "${CERT_DNS_NAMES:=nginx-mtc-acme.mtc-demo.test,localhost}"

mkdir -p "${private_dir}" "${cert_dir}" "${lego_dir}/certificates" "${wellknown_dir}"

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

rm -f "${lego_dir}/certificates"/*.crt "${lego_dir}/certificates"/*.issuer.crt 2>/dev/null || true

lego \
  --server "${ACME_DIRECTORY_URL}" \
  --path "${lego_dir}" \
  --email "${ACME_EMAIL}" \
  --accept-tos \
  --csr "${leaf_csr}" \
  --http \
  --http.webroot "${wellknown_dir}" \
  run \
  --no-bundle

issued_cert="$(find "${lego_dir}/certificates" -maxdepth 1 -type f -name '*.crt' ! -name '*.issuer.crt' | sort | head -n 1)"
if [ -z "${issued_cert}" ]; then
  echo "lego did not write an issued certificate" >&2
  exit 1
fi
cp "${issued_cert}" "${leaf_cert}"

nginx -t
exec nginx -g "daemon off;"
