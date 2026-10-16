# Lab 03: GitHub Actions

**A hands-on workshop.** Take the Ignition project you already know and build a **CI safety
net** around it: local linters first, then a GitHub Actions workflow that makes those checks
a required gate on every PR, then a look at *where* CI runs when GitHub-hosted isn't enough.

> The subject is the same Ignition gateway and Perspective project from Lab 02 (the
> Oatmakers Site 04 oat-line "Overview" HMI plus two Jython script libraries). The repo
> tracks only the project files under `projects/`; the gateway generates its own config
> into a Docker volume we never commit. Lab 04 goes deep on that file layout and deploys
> the files to a gateway.

## What you'll do

- **Part 1: Linters as your safety net:** yamllint, shellcheck, actionlint, **ign-lint**, `scripts/validate.sh`
- **Part 2: GitHub Actions:** build `lab03-ci.yml`, path filters, a ruleset that requires it
- **Part 3: Self-hosted runners:** a discussion and an optional hands-on; the real thing comes in Labs 04 and 06

## Setup

You'll need Docker (Compose V2) and Python 3.12. From this lab's folder in your clone,
stop the Lab 02 gateway (both labs use port 8088), copy the env file and boot the gateway:

```bash
cd ~/mustry-academy/cicd-for-ignition/labs/03-github-actions
code .

(cd ../02-branching-and-prs && scripts/teardown.sh)   # Lab 02's gateway holds port 8088

cp .env.example .env
scripts/setup.sh        # boots one Ignition gateway, waits for RUNNING, prints the URL + login
# open http://localhost:8088  → log in with the .env credentials
```

> **Port 8088 taken by something else?** Set `GATEWAY_PORT=8090` (any free port) in `.env`
> and re-run `scripts/setup.sh`; it prints the matching URL.

Install the linters, pinned, in a Python 3.12 venv (the version CI uses). `uv` creates it and
downloads Python 3.12 if your machine doesn't have it (Ubuntu 26.04 ships 3.14, which ign-lint
doesn't support yet):

```bash
# macOS
brew install shellcheck actionlint uv

# Debian/Ubuntu/WSL: actionlint has no apt package, so grab the release binary
sudo apt install shellcheck
bash <(curl -sSL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash)
sudo mv actionlint /usr/local/bin/
curl -LsSf https://astral.sh/uv/install.sh | sh     # then open a new terminal

# both
uv venv --python 3.12 .venv && source .venv/bin/activate
uv pip install yamllint==1.35.1 ign-lint==0.6.1
python -V                    # Python 3.12.x, same as CI
```

> In a new terminal, re-activate with `source .venv/bin/activate`.

> **No CI on your PRs?** `course-setup.sh` enabled Actions on your fork and pointed `gh` at
> it. If your fork's **Actions** tab still shows *"I understand my workflows, go ahead and
> enable them"*, click it. In the web UI, check that a new PR's base is **your fork's** `main`.

Reference reading: [`docs/validation-and-linters.md`](../docs/validation-and-linters.md)
and [`docs/self-hosted-runners.md`](../docs/self-hosted-runners.md).

---

## Part 1: Linters as your safety net

**Goal:** run yamllint, shellcheck, actionlint, **ign-lint** and `scripts/validate.sh`
against a real Ignition project, read each tool's output, fix every finding, and read how
`.yamllint.yml` documents a rule it mutes on purpose.

### Seed the broken state

```bash
scripts/seed.sh
```

This plants seven issues into your working tree, at least one for every tool, including
three Ignition findings in the Perspective view: a **brittle, broken binding**, a **runaway
poll rate** and a **mis-named component**. Find them with the linters, not with `git diff`:
it shows every answer at once. Start over any time, from the lab folder, with:

```bash
git restore . && rm -f ../../.github/workflows/lab03-example.yml
```

### We-do

The instructor runs each tool on the seeded state, reads the output and fixes one finding.
These are five separate commands, run from the lab folder:

```bash
yamllint -c .yamllint.yml .            # YAML syntax and style
shellcheck scripts/*.sh                # shell-script bugs
actionlint -config-file .github/actionlint.yaml \
  ../../.github/workflows/lab03-*.yml  # Actions workflows (they live at the repo root)
# ign-lint runs from the repo root; the subshell keeps your terminal in the lab folder
(cd ../.. && ign-lint --config labs/03-github-actions/rule_config.json \
  --files "labs/03-github-actions/projects/**/view.json")
scripts/validate.sh                    # every *.json is valid JSON, every code.py parses
```

`scripts/validate.sh` exits 0 (green) or 1 (red). It is not a linter and runs none of the
others for you.

Spend the most time on **ign-lint**, the one tool that reads a Perspective view. Open
`rule_config.json` and walk the rules the seed trips:

- `NamePatternRule`: components PascalCase, properties camelCase, message handlers
  kebab-case, custom methods snake_case.
- `PollingIntervalRule`: a floor on binding poll rates, 1000 ms in this lab.
- `BadComponentReferenceRule`: brittle `.getSibling()` / `.getParent()` / relative-path traversal.
- `ComponentReferenceValidationRule`: relative references that don't resolve.
- `PylintScriptRule`: pylint over the Python inside views, with `.config/.ignition-pylintrc`.

The clean `lab-project` passes ign-lint with **zero** findings: every finding you see is
something `scripts/seed.sh` broke on purpose.

### You do

Hunt every planted issue and fix them all. (The step numbers match the assignment slides.)

1. Run `scripts/seed.sh` for a fresh broken state (reset first if your tree still carries
   We-do fixes: `git restore . && rm -f ../../.github/workflows/lab03-example.yml`).
2. Run all five checks and write down each finding: *what the tool flagged*, in *which file*.
3. Spend the most time on **ign-lint**'s output. It fires two rules on one binding (the
   Kiln tile), plus a poll-rate finding and a naming finding. Work out *why* each rule
   exists before fixing anything.
4. Fix every finding. For each, record *what the tool flagged*, *why your fix is correct*
   and *what class of production bug it would catch*. That includes the seeded
   `lab03-example.yml`: bump it to `actions/checkout@v7`, don't delete it.
5. Re-run every linter until each is silent and `scripts/validate.sh` exits 0.
6. Open `.yamllint.yml` and read the comment on `line-length: disable`: a finding configured
   away rather than fixed, with the reason written down. Nothing to change here.
7. Commit with `-A`: the seeded `lab03-example.yml` is a new, untracked file that
   `git commit -am` would leave behind.

   ```bash
   git add -A && git commit -m "fix: part 1 linter findings"
   ```

> **No delete-cheats.** Don't silence ign-lint by deleting the Clock, the Kiln binding or
> the Power tile: restore real data bindings and a real name. The teaching deck's
> broken-binding slide shows the Kiln binding before the edit. Check that the view still
> loads: `docker compose restart` (or `scripts/scan.sh` with an API key in `.env`), then
> reload the Overview page.

### Stretch 1 `[OPTIONAL]`: block bad commits with pre-commit

The lab ships `.pre-commit-config.yaml` with all four linters as hooks.

1. Install the tool in your venv: `uv pip install pre-commit`. There is no `pre-commit install`:
   `scripts/setup.sh` already set `core.hooksPath=scripts/git-hooks`, which runs this lab's
   config whenever a commit touches `labs/03-github-actions/`.
2. Baseline run over the whole lab, clean after Part 1:
   `pre-commit run --all-files --config .pre-commit-config.yaml`
3. Set the Clock binding to `now(250)`, try to commit, and watch the ign-lint hook refuse
   the commit.
4. Undo the bad change. If the commit went through anyway: does `pre-commit --version` work
   (venv active)? Does `git config core.hooksPath` print `scripts/git-hooks`? If not, re-run
   `scripts/setup.sh`.

### Debrief

- Which of these linters would have caught the most recent real bug your team shipped?
- When does linting *hurt* instead of help? (When it flags style as errors, when it's
  slower than the dev loop, when its config drifts from what the team agrees on.)
- Which ign-lint rules map to a mistake you've shipped in a Perspective project? Which feel
  like overreach?

---

## Part 2: GitHub Actions: workflows, jobs, required checks

**Goal:** write the workflow yourself (PR trigger, least-privilege permissions, path
filters), wire in the Part 1 linters, and make it a *required check* no one can merge past.
Start from a clean tree (Part 1 fixes committed).

```
workflow  ──contains──▶  jobs  ──contains──▶  steps  ──run──▶  actions or shell commands
   │                       │
   │                       └── runs-on, timeout-minutes
   └── on (triggers), permissions, defaults
```

Two facts about this repo shape every workflow below:

- GitHub only reads workflows from `.github/workflows/` at the **repo root**, so this lab's
  workflow is `.github/workflows/lab03-ci.yml` at the top of your fork.
- `defaults: run: working-directory: labs/03-github-actions` makes every `run:` step start
  in the lab folder. `uses:` steps and `paths:` patterns still see the repo root.

### We-do (step 0): build the workflow

The repo ships the finished workflow. `scripts/prepare-part2.sh` moves it to
`.github/ci-reference.yml` in the lab folder (your answer key for step 4) and writes a bare
two-job skeleton (`lint` and `validate`, each just `checkout` plus TODOs) to
`.github/workflows/lab03-ci.yml` at the repo root:

```bash
scripts/prepare-part2.sh
git add -A && git commit -m "chore: set aside reference workflow, scaffold lab03-ci.yml skeleton"
```

By hand instead: do the `git mv`, then type the skeleton from the assignment slide.

```bash
git mv ../../.github/workflows/lab03-ci.yml .github/ci-reference.yml
git commit -m "chore: set aside the reference workflow"
```

Fill in the TODOs yourself; don't copy the reference. Start with the `validate` job (the
`lint` job keeps its TODOs for now):

```yaml
name: Lab 03 · CI
on:
  pull_request:
    paths:
      - "labs/03-github-actions/**"
      - ".github/workflows/lab03-*.yml"
permissions:
  contents: read
defaults:
  run:
    working-directory: labs/03-github-actions
jobs:
  validate:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v7
      - run: scripts/validate.sh
```

Watch it run on a test PR: push the same commit as a branch, open the PR, watch it, and
close it **unmerged**. Merging it would put a merge commit on GitHub's `main` that your local
`main` lacks, and step 2's `git push origin main` would be rejected.

```bash
git add -A && git commit -m "ci: validate job"            # on your local main
git branch ci/first-run && git push -u origin ci/first-run   # a test branch, same commit
gh pr create --head ci/first-run --fill
sleep 15 && gh pr checks ci/first-run --watch              # checks take a few seconds to register
gh pr close ci/first-run --delete-branch                   # close it unmerged
```

Read the logs on the PR's **Checks** tab: each step is its own collapsible block. Then fill
in the `lint` job with the Part 1 linters:

```yaml
  lint:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-python@v7
        with:
          python-version: "3.12"
      - run: pip install yamllint==1.35.1 ign-lint==0.6.1
      - run: yamllint -c .yamllint.yml . ../../.github/workflows/lab03-*.yml
      - uses: raven-actions/actionlint@v2
        with:                             # a `uses:` step: paths are repo-root-relative
          files: ".github/workflows/lab03-*.yml"
          flags: "-config-file labs/03-github-actions/.github/actionlint.yaml"
      - run: sudo apt-get update && sudo apt-get install -y --no-install-recommends shellcheck
      - run: shellcheck scripts/*.sh
      - working-directory: .              # ign-lint runs from the repo root, as in Part 1
        run: >-
          ign-lint --config labs/03-github-actions/rule_config.json
          --files "labs/03-github-actions/projects/**/view.json"
```

What the We-do also shows:

- **`permissions: contents: read`**: the workflow may read the repo and nothing else.
- **Secrets vs variables**: secrets are encrypted and masked (`***`) in logs; variables are
  plain text. The instructor adds an `EXAMPLE_SECRET` and shows it masked:
  `gh secret set EXAMPLE_SECRET --body "hunter2" -R "$(gh repo set-default --view)"`.
- **Job ids are check names**: the ruleset in step 3a requires `lint` and `validate` by
  name. Rename a job, or give it a `name:`, and the required check waits forever.
- **`timeout-minutes`** on every job: a hung job otherwise runs for up to 6 hours.

### You do

Make the workflow yours. (Step 0 was the We-do above; steps 1-4 follow, with 3a-3d inside
step 3.)

**Step 1: path filters.** Narrow `paths:` from "anything in this lab" to the files the
checks actually read, so the workflow skips docs-only PRs. Add a `push` trigger on `main`,
scoped to the lab the same way. Include every config the checks read: `.yamllint.yml`,
`rule_config.json`, `.config/` and the lab's `.github/`.

```yaml
on:
  pull_request:
    paths:
      - "labs/03-github-actions/projects/**"
      - "labs/03-github-actions/scripts/**"
      - "labs/03-github-actions/docker-compose.yml"
      - ".github/workflows/lab03-*.yml"
      - "labs/03-github-actions/.yamllint.yml"
      - "labs/03-github-actions/rule_config.json"
      - "labs/03-github-actions/.config/**"
      - "labs/03-github-actions/.github/**"
  push:
    branches: [main]
    paths:
      - "labs/03-github-actions/**"
      - ".github/workflows/lab03-*.yml"
```

**Step 2: the Compose check, then a README-only PR.** Add a final step to the `lint` job:

```yaml
      - run: docker compose config -q
```

Commit and push to `main` (it isn't protected yet). The push runs `lint` and `validate`
once, so both names show up as suggestions when step 3a asks for the required checks. Then
branch off, touch **only** `labs/03-github-actions/README.md` and open a PR. The checks
panel stays **empty**, not even a *Skipped* entry: a path-filtered workflow never starts.
Close that PR afterwards.

```bash
git add -A && git commit -m "ci: lab03 workflow"
git push origin main                  # runs lint + validate
git switch -c docs/readme-only        # edit README.md only, then:
git commit -am "docs: readme tweak"
git push -u origin docs/readme-only
gh pr create --fill                   # checks panel stays empty: no workflow started
gh pr close docs/readme-only --delete-branch && git switch main
```

**Step 3: protect `main`.**

**3a: Create a ruleset.** On github.com, open your fork's **Settings → Rules → Rulesets →
New ruleset → New branch ruleset** and fill it in exactly like this:

- **Ruleset name:** `protect-main`
- **Enforcement status:** Active
- **Bypass list:** leave it **empty**, so the rules apply to you too, as admin.
- **Target branches:** Add target → **Include default branch**
- **Restrict deletions:** ticked
- **Require a pull request before merging:** ticked, with **Required approvals: 0**
  (GitHub never lets you approve your own PR).
- **Require status checks to pass:** ticked → **Add checks** → **`lint`** and **`validate`**
- **Block force pushes:** ticked
- Leave everything else unticked. **Restrict updates** blocks PR merges too.

Click **Create**.

> **Delete the ruleset when you finish Lab 03.** Every lab shares your fork's `main`: while
> the ruleset is on, PRs of other labs wait for `lint` and `validate` too. Settings → Rules
> → Rulesets → `protect-main` → Delete ruleset.

**3b: A direct push is rejected.** Commit straight to `main` and push. GitHub rejects it,
even for you as admin: `Changes must be made through a pull request.` and `2 of 2 required
status checks are expected.` Then drop the rejected commit.

```bash
git switch main
git commit --allow-empty -m "test: direct to main"
git push                              # → rejected: GH013 Repository rule violations
git reset --hard origin/main          # drop the rejected commit
```

**3c: A green PR merges.** Make a **real** change on a branch (an empty commit starts no
checks): reword the Overview's `Subtitle` text in its `view.json`. Open a PR, wait for
`lint` and `validate` to go green, and merge.

```bash
git switch -c fix/proper-route
# reword the Overview Subtitle's text in its view.json, then:
git commit -am "feat: reword overview subtitle"
git push -u origin fix/proper-route
gh pr create --fill
sleep 15 && gh pr checks --watch && gh pr merge --merge --delete-branch   # checks take a few seconds to register
git switch main && git pull
```

Then open another README-only PR: no workflow starts, so the required checks never report
and the PR waits on *Expected* forever. Stretch 2 unblocks it; close the PR for now.

**3d: A red PR is blocked.** On a branch, set the Clock's poll to `now(250)` by hand,
commit and open a PR. `lint` goes red and `gh pr merge` refuses with `the base branch policy
prohibits the merge`. Pre-commit hook installed (Stretch 1)? Commit with `--no-verify`.
Don't re-run `scripts/seed.sh` for this: it plants all seven bugs.

Then fix it with `now(1500)`, not the exact original value: a PR with no net change
against `main` matches no `paths:` filter, so the checks sit on *Expected*. (Reverted
exactly anyway? Close the now-empty PR.)

```bash
git switch -c fix/regression
# edit the Clock binding → now(250), then:
git commit -am "test: reintroduce a bug"     # pre-commit hook installed? add --no-verify
git push -u origin fix/regression
gh pr create --fill
sleep 15 && gh pr checks --watch             # → lint fails; the merge stays blocked
# edit the Clock binding → now(1500), then:
git commit -am "fix: poll the clock at 1500 ms" && git push
sleep 15 && gh pr checks --watch && gh pr merge --merge --delete-branch
git switch main && git pull
```

**Step 4: compare with the reference.** Your workflow should match
`.github/ci-reference.yml` structurally: same triggers, jobs and step order. Step `name:`
labels and comments may differ.

```bash
git diff --no-index .github/ci-reference.yml ../../.github/workflows/lab03-ci.yml
```

### Stretch 2 `[OPTIONAL]`: unblock README-only PRs with the no-op twin

Add a second workflow, `.github/workflows/lab03-ci-noop.yml` at the repo root, with the
opposite path filter and jobs named exactly `lint` and `validate` that just `echo`. A later
`!` pattern removes files an earlier pattern matched, so the twin runs only when a changed
file is in this lab *and* outside the real CI's filter:

```yaml
name: Lab 03 · CI (no-op twin)
on:
  pull_request:
    paths:
      - "labs/03-github-actions/**"                # this lab's files...
      - "!labs/03-github-actions/projects/**"      # ...minus everything lab03-ci.yml checks
      - "!labs/03-github-actions/scripts/**"
      - "!labs/03-github-actions/docker-compose.yml"
      - "!labs/03-github-actions/.yamllint.yml"
      - "!labs/03-github-actions/rule_config.json"
      - "!labs/03-github-actions/.config/**"
      - "!labs/03-github-actions/.github/**"
permissions: {}
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: echo "No lint-relevant files changed."
  validate:
    runs-on: ubuntu-latest
    steps:
      - run: echo "No validate-relevant files changed."
```

Merge it to `main` through a PR, then open a README-only PR: `lint` and `validate` report
green within seconds and the merge unlocks.

### Stretch 3 `[OPTIONAL]`: a Run button and a masked secret

- **The manual Run button.** Add `workflow_dispatch:` to your `on:` block and merge it to
  `main` through a PR. The Actions tab grows a *Run workflow* button.
- **A masked secret in your fork.**
  `gh secret set EXAMPLE_SECRET --body "hunter2" -R "$(gh repo set-default --view)"`, add a
  step that runs `echo "leak? ${{ secrets.EXAMPLE_SECRET }}"`, push, and read the log: it
  prints `leak? ***`. Delete the echo step afterwards.

### Debrief

- Where does the workflow actually run? (A fresh machine per job.)
- What happens when a step fails midway? (The rest of the job is skipped and the job fails.)
- Required checks are a contract with the *team*: who decides what's blocking, and who
  fixes CI when it flakes?

---

## Part 3: Self-hosted runners

Back together. The teaching covered what a self-hosted runner is, when you need one, and
the one rule: never attach one to a **public** repo that accepts **fork PRs**. You'll use
runners for real in Labs 04 and 06.

**Discussion (everyone).** Which of *your own* deploys would need a self-hosted runner, and
why, specifically? ("Our gateway is behind the customer's VPN; GitHub-hosted physically
can't reach it" beats "maybe.")

### Optional hands-on `[OPTIONAL]`

> Only on your own fork, with an ephemeral runner, a `workflow_dispatch` job, and a
> teardown at the end.

**1: Register an ephemeral runner.** Docker running, `gh` logged in with admin on your
fork. Mint a short-lived registration token, start the runner container, and wait for
`Listening for Jobs`. It also shows on *Settings → Actions → Runners*.

```bash
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)

RUNNER_TOKEN=$(gh api -X POST \
  "repos/$REPO/actions/runners/registration-token" --jq .token)

docker run -d --rm --name lab03-runner \
  -e REPO_URL="https://github.com/$REPO" \
  -e RUNNER_TOKEN="$RUNNER_TOKEN" \
  -e LABELS="self-hosted,local-lab03" \
  -e EPHEMERAL=true \
  myoung34/github-runner:latest

docker logs -f lab03-runner          # wait for "Listening for Jobs", then Ctrl-C (the runner keeps running)
```

**2: Route one job to it, then tear it down.** The repo ships
[`.github/workflows/lab03-runner-demo.yml`](../../../.github/workflows/lab03-runner-demo.yml):
`workflow_dispatch` only, with `runs-on: [self-hosted, local-lab03]`. Nothing to write.
Note your runner's container ID, dispatch the workflow and read its run log:

```bash
docker ps --filter name=lab03-runner --format '{{.ID}}'   # your runner's container ID
gh workflow run lab03-runner-demo.yml
sleep 5
RUN_ID=$(gh run list --workflow lab03-runner-demo.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run watch "$RUN_ID"                        # returns when the job is done
gh run view "$RUN_ID" --log | grep "ran on" | tail -1   # → ran on <that container ID>

docker rm -f lab03-runner                     # tear down: a no-op if it already exited
```

The job goes green and the run log names your container ID. After its one job the
ephemeral container exits and the runner drops off the Runners tab. Check that
*Settings → Actions → Runners* is empty, and remove a lingering "Offline" runner by hand.

---

## Wrap-up

You built a CI safety net for an Ignition project:

- **Local linters** (yamllint, shellcheck, actionlint, **ign-lint**, `scripts/validate.sh`),
  each catching a class of bug before it ships.
- **A GitHub Actions workflow** that runs them on every PR, with least-privilege
  permissions and path filters.
- **A ruleset on `main`** that turns "please run the linters" into "you cannot merge until
  they pass."
- **Self-hosted runners:** when you need one, and the rule that keeps it safe.

**Before Lab 04:** delete the `protect-main` ruleset on your fork (Part 2, step 3a), and
skim [`docs/self-hosted-runners.md`](../docs/self-hosted-runners.md).
