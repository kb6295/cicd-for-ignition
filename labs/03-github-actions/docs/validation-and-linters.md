# Validation and linters: cheat sheet

Reference reading for Part 1 (linters): which tool catches which class of bug, built
around the files this lab tracks: YAML, workflows, shell scripts and Perspective
`view.json` resources.

## The tools we install

| Tool | What it catches | Speed | Where it runs |
|---|---|---|---|
| **yamllint** | YAML syntax and style issues (`docker-compose.yml`, workflows, `.yamllint.yml`) | ms | local + CI |
| **actionlint** | GitHub Actions workflow correctness (syntax, expression typing) | ms | local + CI |
| **shellcheck** | Bash scripting bugs in `scripts/*.sh` | ms | local + CI |
| **ign-lint** | Ignition-native static analysis of Perspective `view.json` files and embedded scripts | seconds | local + CI |

Plus two validators that aren't really linters:

| Tool | What it catches |
|---|---|
| **`scripts/validate.sh`** | Every `*.json` under `projects/` is valid JSON, every `code.py` parses as Python 3. Exits 0 (green) or 1 (red). |
| **`docker compose config -q`** | Compose schema: "service not defined", port-string typos, malformed environment maps. |

## Three kinds of finding

**1. Syntax.** Does the file parse? `yamllint`, `docker compose config`, `actionlint` and
`scripts/validate.sh`. Cheap, fast, hard to argue with.

**2. Likely bug.** It parses, but the pattern is risky: `shellcheck` flagging an unquoted
`$VAR`, or `ign-lint` flagging a component reached via brittle `.getParent().getChild(...)`
traversal. It works today and breaks the moment someone renames or reorders something.

**3. Style.** Is it consistent? Some `yamllint` rules (line length) and `ign-lint`'s naming
conventions (PascalCase components, camelCase properties). Tune or disable rules *as long
as the team agrees*, and check the config in so the agreement is enforced.

## ign-lint: the Ignition-native linter

`ign-lint` statically analyzes Perspective `view.json` files, and the Python scripts
embedded inside them, **without a running gateway**.

- **PyPI package:** `ign-lint` (v0.6.1, pinned)
- **Install:** `uv pip install ign-lint==0.6.1` in the Python 3.12 venv (the lab and CI run it on Python 3.12)
- **Run (from the repo root):** `ign-lint --config labs/03-github-actions/rule_config.json --files "labs/03-github-actions/projects/**/view.json"`
- **Repo:** <https://github.com/bw-design-group/ignition-lint>
- **Docs:** <https://bw-design-group.github.io/ignition-lint>

It's configured by the lab's `rule_config.json`, tuned so the clean `lab-project` passes
with zero findings. Every later lab uses the same rules and the same pylint config.

- **NamePatternRule:** naming conventions per node type: components `PascalCase`,
  properties `camelCase`, message handlers `kebab-case`, custom methods `snake_case`. In
  this lab, component and custom-method violations are `error`; property and
  message-handler violations are `warning`.
- **PollingIntervalRule:** flags `now()` / expression polling faster than a minimum,
  **1000 ms** in this lab.
- **PylintScriptRule:** runs pylint over the Python scripts embedded in views, with the
  lab's `.config/.ignition-pylintrc` (ign-lint's bundled config with
  `import-outside-toplevel` switched off). `rule_config.json` names that file
  repo-root-relative, so CI, the pre-commit hook and your own runs all start ign-lint from
  the repo root.
- **BadComponentReferenceRule:** brittle traversal like `.getSibling()`, `.getParent()` and
  other relative walking that breaks when the component tree is edited.
- **ComponentReferenceValidationRule:** relative references that don't resolve to a real
  component (expressions, property bindings and scripts).
- **UnusedCustomPropertiesRule:** custom properties that nothing reads.
- **ExcessiveContextDataRule:** oversized context data (large arrays, deep nesting, too
  many data points).

## scripts/validate.sh: the gateway-free project validator

It walks `projects/` and checks two things:

1. every `*.json` resource is valid JSON, and
2. every `code.py` parses as Python 3.

It needs nothing but `python3`, runs in about a second, and exits `0` when everything is
valid, `1` otherwise. The gateway runs Jython 2.7, so this is a Python-3 parse check, not a
Jython validator.

## Common findings and what they mean

### yamllint

- `line too long`: often a false positive for Compose env strings; this lab disables
  `line-length` in `.yamllint.yml`, with the reason in a comment.
- `trailing spaces`: strip the whitespace.
- `truthy value should be true/false`: YAML's `yes`/`no`/`on`/`off` boolean shorthand.

### shellcheck

- `SC2086: Double quote to prevent globbing and word splitting`: `$VAR` should almost
  always be `"$VAR"`.
- `SC2148: Missing shebang`: add `#!/usr/bin/env bash` at the top.
- `SC2034: VAR appears unused`.
- `SC2155: Declare and assign separately`: `local x=$(cmd)` masks `cmd`'s exit status.
  Split into two lines.

### actionlint

- `unknown action`: typo in the action name, or no version pinned.
- `expression type mismatch`: `${{ steps.foo.outputs.value }}` referenced before `foo`
  runs, or the wrong type in arithmetic.
- `the runner of "actions/checkout@v2" action is too old`: bump the action to a current
  release.

### ign-lint

- **Non-PascalCase component name:** `myButton` or `temp_gauge` instead of
  `TemperatureGauge`. `NamePatternRule`, severity `error`.
- **Sub-minimum polling interval:** a binding polling faster than 1000 ms.
  `PollingIntervalRule`. Bump the interval, or use a tag change-driven binding.
- **Brittle component reference:** a binding or script reaching another component by
  relative path. `BadComponentReferenceRule` / `ComponentReferenceValidationRule`. Bind to
  a real data source, a custom property or a message handler instead.

## Further reading

- [yamllint docs](https://yamllint.readthedocs.io/): full rule reference
- [shellcheck wiki](https://www.shellcheck.net/wiki/): every error code explained
- [actionlint docs](https://github.com/rhysd/actionlint/blob/main/docs/checks.md): what it checks
- [ign-lint docs](https://bw-design-group.github.io/ignition-lint): rule reference and configuration
