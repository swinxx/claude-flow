# memory-router Python CLI - Plan 14: provider status chain (`provider_status_json`)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Port the Obsidian/Vault provider STATUS chain - `provider_status_json` (Bash 1197-1292) and its helpers: `provider_manifest_json` (714-732), `provider_detection_json` (733-803), `provider_normalize_loopback_origin` (808-869), `provider_auth_json` (1000-1196), `provider_direct_search_ready_json` / `provider_direct_write_ready_json` (885-889 / 995-999). This composes the manifest + local detection + auth into the provider capability/health view consumed by `status_json`, `provider_sync_status_json`, and `vault_status_json`. **Security-sensitive:** handles the Local REST API token and probes only loopback origins.

**Architecture:** New module `hooks/memory_router/provider.py`. The live curl probes (`curl -k -sS -m T`) are ported to the stdlib `urllib` (`_http_probe`) with TLS verification disabled, loopback-only. Returns Python dicts/bools (serialized at the `contracts.dumps` boundary later). No subcommand wiring. The sync/vault helpers (1294-1397) are a separate plan.

**Tech Stack:** Python 3.9+ stdlib only (`os`, `re`, `ssl`, `urllib`, `json`); no new deps.

## Global Constraints

- **Drop-in / scope:** new `provider.py`, new `tests/test_provider.py`, spec §12 rows. No edits to `hooks/memory-router.sh`, other modules, manifests. No subcommand wiring.
- **Source of truth:** Bash provider helpers @ `kimiflow--v0.1.50`. Grounded byte-for-byte (bash normalized via `jq -c .`, isolated `env -i`, local mock Obsidian HTTP server) across ~24 scenarios - see Self-Review.
- **`manifest_json`:** parsed VAULT-PROVIDER.json when valid object, else the default manifest. A valid non-object file -> default (robust; unreachable).
- **`_normalize_loopback_origin` (SECURITY GUARD):** returns the canonical `scheme://host[:port]` only for `localhost`/`127.0.0.1`/`::1` http(s) URLs whose path is `""`/`"/"`/`"/mcp"`/`"/mcp/"`; rejects userinfo, non-loopback hosts, bad scheme, whitespace/quote/backslash/backtick, non-numeric port. The bearer token is only ever sent to a normalized loopback origin.
- **`_http_probe` no-follow (SECURITY GUARD):** ports `curl` *without* `-L`. A 3xx is terminal (returned as the code, mapped to `token_unverified`), NOT followed. urllib's default opener would follow a redirect and re-send the `Authorization` header cross-origin, leaking the token off the loopback host; `_NoRedirect` prevents that. This is the second compensating control for the disabled TLS verification.
- **`detection_json`:** probes `KIMIFLOW_OBSIDIAN_URL` (whitespace-split) or the two default loopback URLs; `detected` when the body is `status==OK` and `manifest.id` matches `obsidian-local-rest-api` OR `manifest.name` matches `/Local REST API/i`; else `missing`. Timeout `KIMIFLOW_OBSIDIAN_DETECT_TIMEOUT` (default 0.35).
- **`auth_json` (state machine):** env override (`KIMIFLOW_VAULT_AUTHENTICATED`/`KIMIFLOW_OBSIDIAN_AUTHENTICATED`) truthy/falsy -> authenticated/auth_failed (source `override`); MCP (`KIMIFLOW_VAULT_MCP_AVAILABLE`/`KIMIFLOW_OBSIDIAN_MCP_AVAILABLE`) -> source `mcp`; token from `KIMIFLOW_OBSIDIAN_API_KEY` then `OBSIDIAN_API_KEY`. With a token: `missing_url` / `non_loopback_url` (and **`url` blanked to ""**, replicating Bash's `url="$(normalize)"` capture of the failed empty output) / `multiline_token` (url already normalized) / else probe -> 2xx `authenticated`+`validated`, 401|403 `auth_failed`+`validated`, else `token_unverified`. No token -> `auth_required` when available/detected, else `not_configured`. Per-branch `setup_hint`.
- **`status_json`:** `configured = (updated_at != null) or (type != "none")`; configured -> `detection = manifest.detection // configured-default`, else `detection_json()`. `available = (.available is True) or env KIMIFLOW_VAULT_AVAILABLE truthy` (strict `is True` so JSON `1` does not match). `direct_search_ready` == `direct_write_ready` == `auth.source == "mcp"`. health.status / recommended_action ladder + capabilities + nested key orders match the Bash jq literals.
- **Truthy/falsy env spellings:** `1|true|TRUE|yes|YES` / `0|false|FALSE|no|NO` (exact).
- **Commits:** named paths only; no AI-attribution trailer. **Branch:** `feat/memory-router-py-foundation`.

## File Structure

| Path | Responsibility |
|---|---|
| `hooks/memory_router/provider.py` | NEW: `manifest_json`, `_normalize_loopback_origin`, `detection_json`, `auth_json`, `direct_search_ready`, `status_json`, `_http_probe`, helpers. |
| `hooks/memory_router/tests/test_provider.py` | NEW: Manifest/NormalizeLoopback/Detection/Auth/Status cases (network via `_http_probe` monkeypatch). |
| `docs/superpowers/specs/2026-06-28-memory-router-python-cli-design.md` | append §12 rows (curl gate, TLS, manifest/timeout fallbacks). |

---

### Task 1: provider status chain

**Step 1 (Red -> Green):** Implement `provider.py` + `test_provider.py` exactly as shipped.

**Step 2 (verify):**
- `( cd hooks && python3 -m unittest discover -s memory_router/tests -p 'test_*.py' )` -> all green (257 with this plan).
- Grounding: extract the Bash provider helpers into a standalone harness piped through `jq -c .`; drive both bash and Python under isolated `env -i` against a local mock Obsidian HTTP server (and dead ports); diff -> identical for all reachable inputs. Use only a TEST token (never the host `OBSIDIAN_API_KEY`).
- ASCII check on `provider.py` -> clean.

## Self-Review (grounding evidence)

Grounded byte-for-byte vs the real extracted Bash (normalized via `jq -c .`, isolated `env -i`, mock Obsidian server + dead ports) across ~24 scenarios: not_detected / detected_unconfigured / mcp / both env overrides / vault_available env / token probe 200->authenticated / 401->auth_failed / token_unverified / missing_url / non_loopback (url blanked) / multiline (url normalized, incl. `/mcp` + trailing-slash) / configured manifests (detection passthrough + configured-default) / configured-via-updated_at / configured-via-type / type=none / token-source precedence. All identical. Grounding caught 2 real bugs before commit: (1) non_loopback must blank `auth.url` to ""; (2) the multiline branch must use the already-normalized url (Bash assigns it in the successful `elif`). Both fixed + re-grounded.

**Review-driven fix (P1, security):** the independent review proved that urllib follows HTTP redirects and re-sends the `Authorization` header cross-origin, leaking the bearer token off the loopback host (Bash `curl` has no `-L`, so a 3xx is terminal -> `token_unverified`). Fixed with a `_NoRedirect` opener applied to both probes; verified byte-parity (302 -> `token_unverified`, identical to Bash) AND that an off-host catcher never receives the token (+1 `HttpProbeRedirectCase` regression test).
