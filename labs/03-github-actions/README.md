# Lab 03: GitHub Actions

Day 2 of the [CI/CD for Ignition Masterclass](../../README.md).

> Build a CI safety net around a real Ignition project: run linters that catch problems before they ship, write a GitHub Actions workflow yourself, make it a required check on `main`, and see when to reach for a self-hosted runner.

The subject is the same **Ignition project** you worked on in
[Lab 02](../02-branching-and-prs/): a Perspective HMI screen (the Oatmakers Site 04
oat-line overview) and a couple of Python script libraries, running on a local gateway you
spin up yourself. Lab 02 had you run the checks **by hand**; this lab makes them
**automatic**: a required status check no one can merge past.

The repo tracks only the **project files**; the gateway generates its own config on boot
into a Docker volume we never commit. How those project files are structured, and how to
deploy them, is [Lab 04](../04-ignition-file-based-deploy/).

## Slides

The decks open in your browser; click **Open document** on the first page.

| Deck | Online | Offline copy |
|---|---|---|
| Teaching | [open in your browser](https://share.mustrysolutions.com/79b83f03-daca-4e27-bcc5-e1c8fbba2b3b) | [`slides/teaching.html`](./slides/teaching.html) |
| Assignment | [open in your browser](https://share.mustrysolutions.com/9cbacc0c-958d-4b10-88cd-af223211166e) | [`slides/assignment.html`](./slides/assignment.html) |

The offline copy is the same deck: open it from your clone if the link doesn't load.

## Prerequisites

- Completed [Lab 02](../02-branching-and-prs/)
- Passed the [preflight](../../preflight/)
- Docker (with the Compose V2 plugin); about 1.5 GB RAM for the single gateway
- [`uv`](https://docs.astral.sh/uv/) to create the linters' Python 3.12 venv (the same version CI uses; uv downloads it if needed)
- The [GitHub CLI](https://cli.github.com/) (`gh`), authenticated (`gh auth status`)

> **WSL2 (Windows): keep the clone in your Linux home (`~/…`), never `/mnt/c/…`.**
> `scripts/setup.sh` refuses to run from there, and never needs `sudo`.
> See [`docs/wsl-setup.md`](./docs/wsl-setup.md).

## Quick start

From this lab's folder in your clone:

```bash
cd ~/mustry-academy/cicd-for-ignition/labs/03-github-actions
(cd ../02-branching-and-prs && scripts/teardown.sh)   # Lab 02's gateway holds port 8088
cp .env.example .env
scripts/setup.sh        # boots one Ignition gateway, waits for RUNNING, prints the URL + login
# open http://localhost:8088  → log in with the .env credentials
```

Port 8088 taken by something else? Set `GATEWAY_PORT` in `.env` (for example
`GATEWAY_PORT=8090`) and re-run `scripts/setup.sh`; it prints the matching URL.

Install the linters and run the checks CI runs: see Setup and Part 1 in
[`exercises/lab.md`](./exercises/lab.md).

Stop the gateway when you're done:

```bash
scripts/teardown.sh             # stop (keeps the gateway's data volume)
scripts/teardown.sh --volumes   # stop and wipe gateway state for a fresh start
```

## Lab structure

The whole lab is one continuous workshop in [`exercises/lab.md`](./exercises/lab.md):

| Part | Topic |
|---|---|
| 1 | Linters as your safety net (yamllint, shellcheck, actionlint, **ign-lint**, `validate.sh`) |
| 2 | GitHub Actions: build `lab03-ci.yml`, path filters, a ruleset that requires it |
| 3 | Self-hosted runners: a discussion and an optional hands-on |

Part 1 starts from a deliberately broken state seeded by [`scripts/seed.sh`](./scripts/seed.sh).

## Repo layout

```
labs/03-github-actions/
├── README.md
├── docker-compose.yml                 ← one Ignition gateway (named volume + bind-mounted projects/)
├── third-party-modules/               ← Project Scan Endpoint .modl the gateway installs at boot (for Flint)
├── .env.example                       ← copy to .env before running
├── .gitattributes                     ← LF normalization so Ignition's JSON resources stay clean
├── .yamllint.yml                      ← yamllint config (its documented mute is read in Part 1)
├── .pre-commit-config.yaml            ← the linters as pre-commit hooks (Stretch 1)
├── rule_config.json                   ← ign-lint rule configuration
├── .config/
│   └── .ignition-pylintrc             ← pylint config ign-lint uses for scripts inside views
├── .github/
│   └── actionlint.yaml                ← declares the self-hosted runner label
├── scripts/
│   ├── setup.sh                       ← boot the gateway and wait for RUNNING
│   ├── scan.sh                        ← push project-file edits to the running gateway
│   ├── teardown.sh                    ← stop the gateway (--volumes to wipe state)
│   ├── seed.sh                        ← plant Part 1's deliberately broken state
│   ├── prepare-part2.sh               ← set the reference workflow aside, scaffold your own
│   └── validate.sh                    ← every project file: valid JSON, parseable Python
├── projects/                          ← the Ignition project (bind-mounted into the gateway)
│   └── lab-project/
│       ├── project.json
│       ├── com.inductiveautomation.perspective/   ← the Perspective HMI dashboard + page config
│       └── ignition/script-python/lab/            ← Python scripts (display + util helpers)
├── exercises/
│   └── lab.md                         ← the workshop (Parts 1-3)
└── docs/                              ← reference reading
```

This lab's workflows live at the **repo root**, the only place GitHub reads them:

```
.github/workflows/
├── lab03-ci.yml                       ← the workflow you rebuild in Part 2
└── lab03-runner-demo.yml              ← Part 3's self-hosted runner demo
```

## The Compose stack

A single Ignition 8.3 gateway:

- **The gateway's own config and runtime state live in a named volume** (`ignition-data`)
  that the gateway generates on first boot. It never lands in the repo.
- **`./projects` is bind-mounted** from the repo into the gateway, so the project files you
  and CI check are the files the gateway runs. (`./third-party-modules` is mounted too, read
  at boot: it holds the Project Scan Endpoint module that the Flint extension calls, as in
  Lab 02.)

```yaml
services:
  ignition:
    image: inductiveautomation/ignition:8.3.8
    ports: ["${GATEWAY_PORT:-8088}:8088"]                  # host port from .env
    volumes:
      - ignition-data:/usr/local/bin/ignition/data        # gateway-owned, self-generated, not in git
      - ./projects:/usr/local/bin/ignition/data/projects   # the one thing you edit
      - ./third-party-modules:/third-party-modules         # add-on .modl files, installed at boot

volumes:
  ignition-data:
```

> The gateway writes a `.resources/` blob store and other operational files inside
> `projects/` as it runs. They are gitignored; if you see them in `git status`, your ignore
> rules are off.

## Licence

Apache 2.0, see [`LICENSE`](./LICENSE).
