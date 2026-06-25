#!/usr/bin/env bash
# kimiflow - terminal opener tests for the Obsidian MCP setup wizard.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FAILS=0

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); }

contains() {
  local text="$1" needle="$2" name="$3"
  if printf '%s\n' "$text" | grep -Fq -- "$needle"; then pass "$name"; else fail "$name"; fi
}

not_contains() {
  local text="$1" needle="$2" name="$3"
  if printf '%s\n' "$text" | grep -Fq -- "$needle"; then fail "$name"; else pass "$name"; fi
}

out="$(OBSIDIAN_API_KEY=fixture-token "$ROOT/hooks/vault-mcp-open-terminal.sh" --host codex --url https://LOCALHOST:27124/mcp/ --dry-run 2>&1)"
contains "$out" "vault-mcp-setup.sh" "open_terminal_calls_setup_helper"
contains "$out" "--host 'codex'" "open_terminal_passes_host"
contains "$out" "--url 'https://localhost:27124'" "open_terminal_normalizes_loopback_url"
contains "$out" "--interactive" "open_terminal_uses_interactive_setup"
not_contains "$out" "fixture-token" "open_terminal_does_not_echo_env_token"

out="$(KIMIFLOW_HOST=claude "$ROOT/hooks/vault-mcp-open-terminal.sh" --url https://127.0.0.1:27124 --dry-run 2>&1)"
contains "$out" "--host 'claude'" "open_terminal_defaults_to_kimiflow_host"

if "$ROOT/hooks/vault-mcp-open-terminal.sh" --host codex --url https://evil.example --dry-run >/dev/null 2>&1; then
  fail "open_terminal_rejects_non_loopback_url"
else
  pass "open_terminal_rejects_non_loopback_url"
fi

bad_url="$(printf 'https://127.0.0.1:27124/evil"\n[mcp_servers.injected]\nurl = "http://example.invalid"')"
if "$ROOT/hooks/vault-mcp-open-terminal.sh" --host codex --url "$bad_url" --dry-run >/dev/null 2>&1; then
  fail "open_terminal_rejects_snippet_injection_url"
else
  pass "open_terminal_rejects_snippet_injection_url"
fi

if [ "$FAILS" -eq 0 ]; then
  echo "ALL GREEN"
  exit 0
fi
echo "$FAILS failure(s)"
exit 1
