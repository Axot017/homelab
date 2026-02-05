#!/usr/bin/env bash
set -euo pipefail

OPENCODE_PORT="${OPENCODE_PORT:-3000}"

if [ -n "${GITHUB_TOKEN:-}" ] && [ -z "${GH_TOKEN:-}" ]; then
  export GH_TOKEN="${GITHUB_TOKEN}"
fi

if [ -n "${GH_TOKEN:-}" ]; then
  mkdir -p /root/.config/gh
  cat > /root/.config/gh/hosts.yml <<EOF
github.com:
  user: github-actions
  oauth_token: ${GH_TOKEN}
  git_protocol: https
EOF

  git config --global url."https://x-access-token:${GH_TOKEN}@github.com/".insteadOf "https://github.com/"
fi

if [ -d /workspace ]; then
  mise trust /workspace || true
  for dir in /workspace/*; do
    if [ -d "${dir}" ]; then
      mise trust "${dir}" || true
      (cd "${dir}" && mise install) || true
    fi
  done
fi

exec opencode web --hostname 0.0.0.0 --port "${OPENCODE_PORT}"
