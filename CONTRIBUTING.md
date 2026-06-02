# Contributing

Thanks for considering a contribution.

## Scope

This skill aims to be **universal across Twenty deployments**. Any change that hardcodes a specific company, domain, user, or workspace will be rejected — per-instance state lives in `~/.config/twenty-cli/`, never in the skill itself.

## Development setup

You need a Twenty workspace (Cloud or self-hosted) plus an API key to test against. Set up an isolated config dir so you don't pollute your real config:

```bash
export TW_CONFIG_DIR=/tmp/twenty-cli-test
bash skills/twenty-crm/scripts/setup.sh --non-interactive \
  --name test --url https://your-server --token-from file --token "$YOUR_TEST_KEY"
```

## What to test before opening a PR

A complete end-to-end pass:

```bash
export TW_CONFIG_DIR=/tmp/twenty-cli-test
bash skills/twenty-crm/scripts/preflight.sh                          # STATUS=ready
restish twenty-test-core find-many-people --limit 1 -f body.totalCount -r
restish twenty-test-core find-many-companies --limit 1 -f body.totalCount -r
bash skills/twenty-crm/scripts/refresh-schema.sh test                # re-fetch specs
```

If you touched `setup.sh`, also test all three `--token-from` modes (keychain on macOS, env, file). If you touched `auth-helper.sh`, confirm restish picks up the new behavior — `pkill restish` to clear any cached spec, then re-run a list call.

## Style

- **Bash 3.2+ compatible** (macOS still ships 3.2; we avoid `${array,,}`, `${array[@]/x/}`, etc.). Existing scripts use the `${arr[@]+"${arr[@]}"}` idiom to handle empty arrays under `set -u` — keep it.
- **`set -euo pipefail`** at the top of every script.
- **No comments narrating what the code does** — well-named identifiers and structure should explain it. Comments are reserved for non-obvious *why* (workarounds, surprising invariants, references to external behavior).
- **Errors to stderr, exit non-zero.** Use the `tw_die` helper from `lib.sh`.
- **Atomic file writes**: use `tw_jq_inplace` for in-place JSON updates. Avoid `>` then `mv` ad hoc.

## SKILL.md changes

- Body should stay under 500 lines / ~5,000 tokens (Agent Skills [recommendation](https://agentskills.io/specification#progressive-disclosure)).
- Detailed reference material belongs in `references/*.md` with an explicit pointer from SKILL.md telling the agent *when* to load it.
- Frontmatter `description` is hard-capped at 1024 characters; keep room for future iteration.

## Validating frontmatter

CI runs the validations from `.github/workflows/validate.yml`. Locally:

```bash
# name matches dir, description present and within limits, no forbidden keys
python3 .github/scripts/validate_skill.py skills/twenty-crm
shellcheck skills/twenty-crm/scripts/*.sh
```

## Areas open for contribution

- **Linux Keychain integration** (`libsecret` / Secret Service API) so `--token-from keychain` isn't macOS-only.
- **OAuth user-token flow** (PKCE) to address Twenty REST's inability to override `updatedBy` on PATCH requests — see the gotcha in `references/restish-usage.md`.
- **More references** — e.g. webhooks via the metadata API, batch endpoints.
- **More compatibility data** in the `compatibility` field if you find specific environments where the skill behaves differently.

## Commits & PRs

Conventional Commits are appreciated but not required. Keep PRs focused — one logical change per PR. Reference the user-facing impact in the PR description.
