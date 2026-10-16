#!/bin/bash
# validate.sh: the checks .github/workflows/lab05-ci.yml (repo root) runs.
#
# Run this before opening a PR to catch the cheap stuff the CI workflow checks,
# without waiting for a runner:
#   1. Every *.json under projects/ and services/ parses.
#   2. .dockerignore excludes the lab/secret paths it should.
#   3. hadolint passes on the Dockerfile.
#   4. security-properties doesn't name a throwaway temp_N identity.
#   5. actionlint passes on this lab's workflows, .github/workflows/lab05-*.yml
#      at the repo root.
#   6. yamllint, shellcheck and ign-lint pass, and `docker compose config`
#      accepts the compose file.
# Linters that aren't installed are skipped with a note (CI always runs them
# all), so a green run here means "everything you have installed passed".
#
# Exits non-zero if any check fails. No Ignition needed. The image build smoke
# test is scripts/build-image.sh (CI always does it; see lab05-ci.yml).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"
cd "$PROJECT_ROOT" || exit 1

rc=0

# 1. JSON validity sweep -------------------------------------------------------
echo "→ JSON validity sweep (projects/, services/)"
json_fail=0
while IFS= read -r f; do
  if ! python3 -m json.tool "$f" > /dev/null 2>&1; then
    echo -e "  ${RED}invalid JSON:${NC} $f"
    json_fail=1
  fi
done < <(find projects services -type f -name '*.json' 2>/dev/null)
if [ "$json_fail" -eq 0 ]; then
  echo -e "  ${GREEN}ok${NC} — all JSON parses"
else
  rc=1
fi

# 2. .dockerignore sanity ------------------------------------------------------
# The build context must not carry secrets or lab tooling into the image. We
# don't reimplement Docker's matcher — we just confirm the must-exclude paths
# are present as patterns.
echo "→ .dockerignore excludes secrets + lab tooling"
if [ -f .dockerignore ]; then
  di_fail=0
  for must in ".env" ".git/" "scripts/" "docs/" "exercises/"; do
    if ! grep -qxF "$must" .dockerignore; then
      echo -e "  ${RED}missing pattern:${NC} $must"
      di_fail=1
    fi
  done
  if [ "$di_fail" -eq 0 ]; then
    echo -e "  ${GREEN}ok${NC} — required exclusions present"
  else
    rc=1
  fi
else
  echo -e "  ${RED}no .dockerignore${NC} — the build context would carry everything"
  rc=1
fi

# 3. hadolint on the Dockerfile (optional) -------------------------------------
echo "→ hadolint (Dockerfile)"
if command -v hadolint > /dev/null 2>&1; then
  if hadolint Dockerfile; then
    echo -e "  ${GREEN}ok${NC}"
  else
    rc=1
  fi
else
  echo -e "  ${YELLOW}skipped${NC} — hadolint not installed (CI runs it; see https://github.com/hadolint/hadolint)"
fi

# 4. identity policy -----------------------------------------------------------
# security-properties is tracked, so whatever it names has to exist on every
# gateway that reads it. Commissioning rewrites it to a throwaway `temp_N`
# profile when it runs with identity files that outlived their data volume
# (scripts/setup.sh heals that) — and a temp profile exists on exactly one
# gateway. Cheap check, because the failure mode is a locked-out gateway.
echo "→ identity policy (security-properties names a deployable profile)"
secprops="services/config/resources/core/ignition/security-properties/config.json"
if [ -f "$secprops" ]; then
  bad_profile="$(python3 -c 'import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit(0)
print(" ".join(sorted({v for k,v in d.items()
                       if k in ("systemAuthProfile","systemIdentityProvider")
                       and str(v).startswith("temp")})))' "$secprops" 2>/dev/null || true)"
  if [ -n "$bad_profile" ]; then
    echo -e "  ${RED}security-properties points at a throwaway identity:${NC} $bad_profile"
    echo "  A commissioning run rewrote it. Restore it and drop the temp identity:"
    echo "    git checkout -- $secprops"
    echo "    rm -rf services/config/resources/core/ignition/{user-source,identity-provider}/temp*"
    echo "  (or just re-run scripts/setup.sh, which now repairs this)"
    rc=1
  else
    echo -e "  ${GREEN}ok${NC} — no throwaway identity in the deploy payload"
  fi
else
  echo -e "  ${YELLOW}skipped${NC} — $secprops not found"
fi

# 5. actionlint (optional) -----------------------------------------------------
echo "→ actionlint (.github/workflows/lab05-*.yml)"
if command -v actionlint > /dev/null 2>&1; then
  if actionlint -color "$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel)"/.github/workflows/lab05-*.yml; then
    echo -e "  ${GREEN}ok${NC}"
  else
    rc=1
  fi
else
  echo -e "  ${YELLOW}skipped${NC} — actionlint not installed (CI runs it; install from https://github.com/rhysd/actionlint to check locally)"
fi

# 6. yamllint, shellcheck, ign-lint, compose config (each optional) -----------
# Same invocations as lab05-ci.yml's lint job.
run_optional() {
  local label="$1" tool="$2" hint="$3"; shift 3
  echo "→ $label"
  if command -v "$tool" > /dev/null 2>&1; then
    if "$@"; then
      echo -e "  ${GREEN}ok${NC}"
    else
      rc=1
    fi
  else
    echo -e "  ${YELLOW}skipped${NC}: $tool not installed (CI runs it; $hint)"
  fi
}

repo_root="$(git -C "$PROJECT_ROOT" rev-parse --show-toplevel 2>/dev/null || echo "$PROJECT_ROOT/../..")"
run_optional "yamllint" yamllint "uv pip install yamllint" \
  yamllint -c .yamllint.yml . "$repo_root"/.github/workflows/lab05-*.yml
run_optional "shellcheck (scripts/*.sh)" shellcheck "install shellcheck from your package manager" \
  shellcheck -x scripts/*.sh
# ign-lint runs from the repo root, like CI: rule_config.json names its pylint
# config with a repo-root-relative path.
lab_rel="${PROJECT_ROOT#"$repo_root"/}"
# shellcheck disable=SC2329,SC2317  # invoked through run_optional
ign_lint_views() {
  (cd "$repo_root" && ign-lint --config "$lab_rel/rule_config.json" --files "$lab_rel/projects/**/view.json")
}
run_optional "ign-lint (Perspective views)" ign-lint "uv pip install ign-lint==0.6.1" \
  ign_lint_views
run_optional "docker compose config" docker "install Docker with Compose v2" \
  docker compose config -q

echo ""
if [ "$rc" -eq 0 ]; then
  echo -e "${GREEN}validate.sh: all checks passed${NC}"
else
  echo -e "${RED}validate.sh: one or more checks failed${NC}"
fi
exit "$rc"
