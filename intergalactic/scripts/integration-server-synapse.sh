#!/usr/bin/env bash
set -euo pipefail

runtime_dir="$(pwd)/integration_test/synapse/runtime"
template_path="$(pwd)/integration_test/synapse/data/homeserver.yaml"
log_config_path="$(pwd)/integration_test/synapse/data/localhost.log.config"
runtime_homeserver="$runtime_dir/homeserver.yaml"
runtime_signing_key="$runtime_dir/localhost.signing.key"

mkdir -p "$runtime_dir"

registration_secret=$(openssl rand -base64 48 | tr -d '\n')
macaroon_secret=$(openssl rand -base64 48 | tr -d '\n')
form_secret=$(openssl rand -base64 48 | tr -d '\n')
signing_key=$(openssl rand -base64 32 | tr -d '\n')

cp "$template_path" "$runtime_homeserver"

python3 - "$runtime_homeserver" "$registration_secret" "$macaroon_secret" "$form_secret" <<'PY'
from pathlib import Path
import sys

config_path = Path(sys.argv[1])
contents = config_path.read_text(encoding="utf-8")
contents = contents.replace("__REGISTRATION_SHARED_SECRET__", sys.argv[2])
contents = contents.replace("__MACAROON_SECRET_KEY__", sys.argv[3])
contents = contents.replace("__FORM_SECRET__", sys.argv[4])
config_path.write_text(contents, encoding="utf-8")
PY

printf 'ed25519 a_local %s\n' "$signing_key" > "$runtime_signing_key"

docker run -d --name synapse --tmpfs /data \
    --volume="$runtime_homeserver":/data/homeserver.yaml:rw \
    --volume="$runtime_signing_key":/data/localhost.signing.key:rw \
    --volume="$log_config_path":/data/localhost.log.config:rw \
    -p 80:80 matrixdotorg/synapse:latest
