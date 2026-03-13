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
  pull             Pull OPENCLAW_IMAGE
  up               Start gateway stack
  down             Stop stack
  restart          Restart gateway container
  logs             Follow gateway logs
  health           Health check via openclaw-cli
  dashboard        Print dashboard URL (tokenized)
  pairing-recover  Approve latest pending device pairing
EOF
}

ensure_env() {
  if [[ ! -f "$ENV_FILE" ]]; then
    cp "$ENV_EXAMPLE" "$ENV_FILE"
    echo "Created $ENV_FILE"
  fi
}

compose() {
  ensure_env
  docker compose --env-file "$ENV_FILE" -f "$ROOT_DIR/docker-compose.yml" "$@"
}

cmd_init() {
  ensure_env
  echo "Edit $ENV_FILE with your tokens"
}

cmd_pull() {
  ensure_env
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
  if [[ -z "${OPENCLAW_IMAGE:-}" ]]; then
    echo "OPENCLAW_IMAGE is empty in $ENV_FILE" >&2
    exit 1
  fi
  docker pull "$OPENCLAW_IMAGE"
}

cmd_up() {
  cmd_pull
  compose up -d openclaw-gateway
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

main() {
  case "${1:-}" in
    init) cmd_init ;;
    pull) cmd_pull ;;
    up) cmd_up ;;
    down) cmd_down ;;
    restart) cmd_restart ;;
    logs) cmd_logs ;;
    health) cmd_health ;;
    dashboard) cmd_dashboard ;;
    pairing-recover) cmd_pairing_recover ;;
    ""|-h|--help|help) usage ;;
    *)
      usage
      echo "Unknown command: $1" >&2
      exit 1
      ;;
  esac
}

main "$@"
