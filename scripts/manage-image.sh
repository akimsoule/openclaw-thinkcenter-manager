#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${OPENCLAW_MANAGER_ENV_FILE:-$ROOT_DIR/.env}"
ENV_EXAMPLE="$ROOT_DIR/.env.example"

usage() {
  cat <<'EOF'
Usage: ./scripts/manage-image.sh <command>

Commands:
  init             Create .env from .env.example
  prepare          Create state dirs and fix ownership for container UID
  pull             Pull OPENCLAW_IMAGE
  bootstrap        Write minimal required OpenClaw config (gateway.mode/bind)
  apply-model      Configure PRIMARY_MODEL as primary model
  apply-telegram   Apply Telegram dm/group policy from .env
  allow-origin     Configure Control UI allowedOrigins (arg IP or env)
  disable-device-identity Disable Control UI device identity checks (dangerous)
  enable-device-identity  Re-enable Control UI device identity checks
  up               Pull + start + bootstrap + restart gateway
  first-start      Full first-run flow: prepare + up + health + dashboard
  repair           Repair config and restart (bootstrap + model + telegram + health)
  down             Stop stack
  restart          Restart gateway container
  logs             Follow gateway logs
  health           Health check via openclaw-cli
  dashboard        Print dashboard URL (tokenized)
  pairing-recover  Approve latest pending device pairing
  diagnose         Show gateway logs and run doctor
  reset-state      Backup state dir, recreate fresh state, fix ownership
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

warn() {
  echo "WARN: $*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing dependency: $1"
}

ensure_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    echo "Created $ENV_FILE"
  fi
}

load_env() {
  ensure_env
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  : "${OPENCLAW_CONFIG_DIR:=${HOME}/.openclaw-thinkcenter}"
  : "${OPENCLAW_WORKSPACE_DIR:=${OPENCLAW_CONFIG_DIR}/workspace}"
  : "${OPENCLAW_GATEWAY_BIND:=lan}"
  : "${OPENCLAW_IMAGE:=akimsoule/openclaw-thinkcenter:latest}"
  : "${OPENCLAW_CONTAINER_UID:=1000}"
  : "${CONTROL_UI_SERVER_IP:=}"
  : "${CONTROL_UI_ALLOWED_ORIGINS_JSON:=}"
  : "${CONTROL_UI_DISABLE_DEVICE_IDENTITY:=false}"
  : "${PRIMARY_MODEL:=moonshot/kimi-k2.5}"
  : "${PRIMARY_MODEL_CONTEXT_WINDOW:=131072}"
  : "${PRIMARY_MODEL_MAX_TOKENS:=16384}"
  : "${TELEGRAM_DM_POLICY:=open}"
  : "${TELEGRAM_GROUP_POLICY:=open}"
  : "${TELEGRAM_GROUP_ALLOW_FROM:=}"

  export OPENCLAW_CONFIG_DIR
  export OPENCLAW_WORKSPACE_DIR
  export OPENCLAW_GATEWAY_BIND
  export OPENCLAW_IMAGE
  export OPENCLAW_CONTAINER_UID
  export CONTROL_UI_SERVER_IP
  export CONTROL_UI_ALLOWED_ORIGINS_JSON
  export CONTROL_UI_DISABLE_DEVICE_IDENTITY
  export PRIMARY_MODEL
  export PRIMARY_MODEL_CONTEXT_WINDOW
  export PRIMARY_MODEL_MAX_TOKENS
  export TELEGRAM_DM_POLICY
  export TELEGRAM_GROUP_POLICY
  export TELEGRAM_GROUP_ALLOW_FROM
}

compose() {
  ensure_env
  docker compose --env-file "$ENV_FILE" -f "$ROOT_DIR/docker-compose.yml" "$@"
}

ensure_state_dirs() {
  load_env
  mkdir -p "$OPENCLAW_CONFIG_DIR" "$OPENCLAW_WORKSPACE_DIR"
}

fix_state_ownership() {
  load_env

  local current_uid
  current_uid="$(stat -c '%u' "$OPENCLAW_CONFIG_DIR" 2>/dev/null || echo "")"
  if [[ "$current_uid" == "$OPENCLAW_CONTAINER_UID" ]]; then
    return 0
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    chown -R "$OPENCLAW_CONTAINER_UID":"$OPENCLAW_CONTAINER_UID" "$OPENCLAW_CONFIG_DIR"
    return 0
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo chown -R "$OPENCLAW_CONTAINER_UID":"$OPENCLAW_CONTAINER_UID" "$OPENCLAW_CONFIG_DIR" || {
      warn "Could not chown $OPENCLAW_CONFIG_DIR automatically."
      warn "Run: sudo chown -R $OPENCLAW_CONTAINER_UID:$OPENCLAW_CONTAINER_UID \"$OPENCLAW_CONFIG_DIR\""
    }
  else
    warn "sudo is not available to fix ownership for $OPENCLAW_CONFIG_DIR"
    warn "Run as root: chown -R $OPENCLAW_CONTAINER_UID:$OPENCLAW_CONTAINER_UID \"$OPENCLAW_CONFIG_DIR\""
  fi
}

cmd_init() {
  ensure_env
  echo "Edit $ENV_FILE with your tokens"
}

cmd_prepare() {
  require_cmd docker
  ensure_state_dirs
  fix_state_ownership
  echo "Prepared state directories:"
  echo "- $OPENCLAW_CONFIG_DIR"
  echo "- $OPENCLAW_WORKSPACE_DIR"
}

cmd_pull() {
  require_cmd docker
  load_env
  if [[ -z "${OPENCLAW_IMAGE:-}" ]]; then
    fail "OPENCLAW_IMAGE is empty in $ENV_FILE"
  fi
  docker pull "$OPENCLAW_IMAGE"
}

cmd_bootstrap() {
  require_cmd docker
  load_env
  local disable_identity

  compose run --rm openclaw-cli config set gateway.mode local
  compose run --rm openclaw-cli config set gateway.bind "$OPENCLAW_GATEWAY_BIND"
  cmd_apply_model
  cmd_apply_telegram
  cmd_allow_origin --auto || true

  disable_identity="$(printf '%s' "${CONTROL_UI_DISABLE_DEVICE_IDENTITY}" | tr '[:upper:]' '[:lower:]')"
  if [[ "$disable_identity" == "true" ]]; then
    cmd_disable_device_identity --auto
  fi
}

cmd_apply_model() {
  require_cmd docker
  load_env

  local primary_model
  primary_model="${PRIMARY_MODEL:-moonshot/kimi-k2.5}"
  if [[ "$primary_model" == moonshotai/* ]]; then
    primary_model="moonshot/${primary_model#moonshotai/}"
  fi
  local primary_provider
  local primary_id
  primary_provider="${primary_model%%/*}"
  primary_id="${primary_model#*/}"

  if [[ "$primary_provider" == "nvidia" ]]; then
    compose run --rm openclaw-cli \
      config set models.providers.nvidia.baseUrl "https://integrate.api.nvidia.com/v1"
    compose run --rm openclaw-cli \
      config set models.providers.nvidia.api "openai-completions"
    compose run --rm openclaw-cli \
      config set models.providers.nvidia.models "[{\"id\":\"${primary_id}\",\"name\":\"${primary_id}\",\"reasoning\":true,\"input\":[\"text\"],\"cost\":{\"input\":0,\"output\":0,\"cacheRead\":0,\"cacheWrite\":0},\"contextWindow\":${PRIMARY_MODEL_CONTEXT_WINDOW},\"maxTokens\":${PRIMARY_MODEL_MAX_TOKENS}}]" --strict-json
  fi

  compose run --rm openclaw-cli \
    config set agents.defaults.model.primary "${primary_model}"
  compose run --rm openclaw-cli \
    config set agents.defaults.model.fallbacks '[]' --strict-json || true

  echo "Applied primary model: ${primary_model}"
}

csv_to_json_array() {
  local raw="${1:-}"
  python3 - "$raw" <<'PY'
import json
import sys

raw = sys.argv[1] if len(sys.argv) > 1 else ""
items = [x.strip() for x in raw.split(",") if x.strip()]
print(json.dumps(items))
PY
}

cmd_apply_telegram() {
  require_cmd docker
  load_env

  if [[ -z "${TELEGRAM_BOT_TOKEN:-}" ]]; then
    warn "TELEGRAM_BOT_TOKEN is empty; skipping Telegram policy apply."
    return 0
  fi

  local effective_group_policy
  effective_group_policy="$TELEGRAM_GROUP_POLICY"
  if [[ "$TELEGRAM_GROUP_POLICY" == "allowlist" && -z "${TELEGRAM_GROUP_ALLOW_FROM:-}" ]]; then
    warn "TELEGRAM_GROUP_POLICY=allowlist but TELEGRAM_GROUP_ALLOW_FROM is empty; switching group policy to open."
    effective_group_policy="open"
  fi

  compose run --rm openclaw-cli config set channels.telegram.enabled true
  compose run --rm openclaw-cli config set channels.telegram.botToken "$TELEGRAM_BOT_TOKEN"

  if [[ "$TELEGRAM_DM_POLICY" == "open" ]]; then
    compose run --rm openclaw-cli \
      config set channels.telegram.allowFrom '["*"]' --strict-json
  fi

  compose run --rm openclaw-cli config set channels.telegram.dmPolicy "$TELEGRAM_DM_POLICY"
  compose run --rm openclaw-cli config set channels.telegram.groupPolicy "$effective_group_policy"

  if [[ "$effective_group_policy" == "open" ]]; then
    compose run --rm openclaw-cli \
      config set channels.telegram.groups '{"*":{"requireMention":false}}' --strict-json || true
  elif [[ "$effective_group_policy" == "allowlist" ]]; then
    local group_allow_json
    group_allow_json="$(csv_to_json_array "$TELEGRAM_GROUP_ALLOW_FROM")"
    if [[ "$group_allow_json" != "[]" ]]; then
      compose run --rm openclaw-cli \
        config set channels.telegram.groupAllowFrom "$group_allow_json" --strict-json
    else
      warn "TELEGRAM_GROUP_POLICY=allowlist but TELEGRAM_GROUP_ALLOW_FROM is empty."
    fi
  fi

  echo "Applied Telegram policy: dm=${TELEGRAM_DM_POLICY}, group=${effective_group_policy}"
}

normalize_origins_json() {
  local raw="${1:-}"
  python3 - "$raw" <<'PY'
import json
import re
import sys

raw = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
if not raw:
    print("")
    raise SystemExit(1)

# Preferred path: already-valid JSON array of strings
try:
    parsed = json.loads(raw)
    if isinstance(parsed, list) and all(isinstance(x, str) and x for x in parsed):
        print(json.dumps(parsed))
        raise SystemExit(0)
except Exception:
    pass

# Compatibility path: [http://a:18789,http://b:18789]
compact = re.sub(r"\s+", "", raw)
if compact.startswith("[") and compact.endswith("]"):
    body = compact[1:-1]
    if body:
        parts = [p for p in body.split(",") if p]
        if parts and all(re.match(r"^https?://[^\]\"']+$", p) for p in parts):
            print(json.dumps(parts))
            raise SystemExit(0)

print("")
raise SystemExit(1)
PY
}

resolve_allowed_origins_json() {
  load_env

  local ip_arg="${1:-}"
  if [[ -n "$ip_arg" ]]; then
    echo "[\"http://${ip_arg}:${OPENCLAW_GATEWAY_PORT:-18789}\",\"http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}\"]"
    return 0
  fi

  if [[ -n "${CONTROL_UI_ALLOWED_ORIGINS_JSON:-}" ]]; then
    normalize_origins_json "$CONTROL_UI_ALLOWED_ORIGINS_JSON"
    return 0
  fi

  if [[ -n "${CONTROL_UI_SERVER_IP:-}" ]]; then
    echo "[\"http://${CONTROL_UI_SERVER_IP}:${OPENCLAW_GATEWAY_PORT:-18789}\",\"http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}\"]"
    return 0
  fi

  return 1
}

cmd_allow_origin() {
  require_cmd docker

  local mode="${1:-}"
  local ip_arg=""
  if [[ "$mode" == "--auto" ]]; then
    ip_arg=""
  else
    ip_arg="$mode"
  fi

  local origins_json
  if ! origins_json="$(resolve_allowed_origins_json "$ip_arg")"; then
    if [[ "$mode" == "--auto" ]]; then
      warn "Skipping allowedOrigins auto-config (set CONTROL_UI_SERVER_IP or CONTROL_UI_ALLOWED_ORIGINS_JSON in .env)."
      return 0
    fi
    fail "No origin provided. Use: allow-origin <server-ip> or set CONTROL_UI_SERVER_IP / CONTROL_UI_ALLOWED_ORIGINS_JSON in .env"
  fi

  compose run --rm openclaw-cli \
    config set gateway.controlUi.allowedOrigins "$origins_json" --strict-json

  echo "Applied gateway.controlUi.allowedOrigins: $origins_json"
}

cmd_disable_device_identity() {
  require_cmd docker
  compose run --rm openclaw-cli \
    config set gateway.controlUi.dangerouslyDisableDeviceAuth true

  if [[ "${1:-}" != "--auto" ]]; then
    compose restart openclaw-gateway
  fi
  echo "Applied gateway.controlUi.dangerouslyDisableDeviceAuth=true"
}

cmd_enable_device_identity() {
  require_cmd docker
  compose run --rm openclaw-cli \
    config set gateway.controlUi.dangerouslyDisableDeviceAuth false
  compose restart openclaw-gateway
  echo "Applied gateway.controlUi.dangerouslyDisableDeviceAuth=false"
}

cmd_up() {
  cmd_prepare
  cmd_pull
  compose up -d openclaw-gateway
  cmd_bootstrap
  compose restart openclaw-gateway
}

cmd_first_start() {
  cmd_up
  cmd_health
  cmd_dashboard
}

cmd_repair() {
  cmd_prepare
  cmd_bootstrap
  compose restart openclaw-gateway
  cmd_health
}

cmd_down() {
  compose down
}

cmd_restart() {
  compose restart openclaw-gateway
}

cmd_logs() {
  compose logs -f openclaw-gateway
}

cmd_health() {
  compose run --rm openclaw-cli health
}

cmd_dashboard() {
  compose run --rm openclaw-cli dashboard --no-open
}

cmd_pairing_recover() {
  compose run --rm openclaw-cli devices approve --latest || true
  cmd_dashboard
}

cmd_diagnose() {
  compose logs --tail=120 openclaw-gateway
  compose run --rm openclaw-cli doctor || true
}

cmd_reset_state() {
  load_env
  local backup_path
  backup_path="${OPENCLAW_CONFIG_DIR}.bak.$(date +%Y%m%d-%H%M%S)"

  compose down --remove-orphans || true
  if [[ -d "$OPENCLAW_CONFIG_DIR" ]]; then
    mv "$OPENCLAW_CONFIG_DIR" "$backup_path"
    echo "State backup: $backup_path"
  fi
  ensure_state_dirs
  fix_state_ownership
  echo "Fresh state prepared in $OPENCLAW_CONFIG_DIR"
}

main() {
  case "${1:-}" in
    init) cmd_init ;;
    prepare) cmd_prepare ;;
    pull) cmd_pull ;;
    bootstrap) cmd_bootstrap ;;
    apply-model) cmd_apply_model ;;
    apply-telegram) cmd_apply_telegram ;;
    allow-origin) cmd_allow_origin "${2:-}" ;;
    disable-device-identity) cmd_disable_device_identity ;;
    enable-device-identity) cmd_enable_device_identity ;;
    up) cmd_up ;;
    first-start) cmd_first_start ;;
    repair) cmd_repair ;;
    down) cmd_down ;;
    restart) cmd_restart ;;
    logs) cmd_logs ;;
    health) cmd_health ;;
    dashboard) cmd_dashboard ;;
    pairing-recover) cmd_pairing_recover ;;
    diagnose) cmd_diagnose ;;
    reset-state) cmd_reset_state ;;
    ""|-h|--help|help) usage ;;
    *)
      usage
      echo "Unknown command: $1" >&2
      exit 1
      ;;
  esac
}

main "$@"
