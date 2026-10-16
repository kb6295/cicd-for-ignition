# CI/CD for Ignition — Preflight

> Run this **at least two days before Day 1** to validate that your environment is ready.

The preflight script checks that you have all the tools required for the course installed and working, and that you can successfully pull and run an Ignition 8.3 Docker image. It lives in the `preflight/` folder of the course repo, [`cicd-for-ignition`](../README.md).

## Quick start

You need the [GitHub CLI](https://cli.github.com/) logged in (`gh auth login -s workflow`). The `workflow` scope lets you push GitHub Actions files from Lab 03 on; the preflight checks for it. Have a GitHub **classic Personal Access Token with the `repo` scope** ready too ([github.com/settings/tokens](https://github.com/settings/tokens) → *Generate new token (classic)*): `./course-setup.sh` asks for it once, and the Labs 04 and 06 runners use it to register on your fork.

```bash
mkdir -p ~/mustry-academy && cd ~/mustry-academy     # Windows: this must be your LINUX home
gh repo fork Mustry-Academy/cicd-for-ignition --clone
cd cicd-for-ignition
./course-setup.sh
```

`./course-setup.sh` runs this preflight and then does the one-time setup of your fork: it installs the shared git hooks, checks that `origin` is your fork, sets `gh`'s default repo to your fork (`gh repo set-default`), switches on Actions for it (forks start with workflows off), and prepares the `.env` files for Labs 04 and 06. To run only the checks, from the repo root:

```bash
preflight/scripts/preflight.sh
```

> **Windows:** run this inside WSL, and keep your clone in your Linux home
> (`~/…`), never on your Windows drive (`/mnt/c/…`). The script fails if the repo is on
> `/mnt/c` — see [Platform notes](#platform-notes) for why.

The script writes a report to `preflight/preflight-report.txt` (gitignored), whichever directory you start it from. **Paste the contents of that file into the Discord `#preflight-help` channel** so the TA can confirm you're ready or help debug.

### Options

```
--no-pull       Skip pulling the course images (use locally cached ones)
--skip-smoke    Skip starting the throwaway gateway container
--quiet         Only print warnings, failures and the summary
-h, --help      Show this help and exit
```

The image pulls and gateway smoke test are the slow steps; `--no-pull --skip-smoke` makes for a fast re-run while you're fixing the lighter checks. Run `preflight/scripts/preflight.sh --help` to see this list anytime.

## What it checks

Every check is one of two tiers:

- **Required** — you cannot complete Day 1 without it. A miss is a hard failure and the script exits non-zero.
- **Recommended** — things work without it, but the labs are rougher. A miss is only a warning and never changes the exit code.

<!-- Keep this table in sync with the checks in scripts/preflight.sh (top to bottom). -->

| Check | Tier |
|---|---|
| Operating system (and WSL2 on Windows) | Required |
| The course repo is on the Linux filesystem, not `/mnt/c` (WSL only) | Required |
| Not running as root / under `sudo` | Required |
| `git` installed, with a commit identity (`user.name` / `user.email`) | Required |
| `git` ≥ 2.40 | Recommended |
| `core.autocrlf` is not `true` (CRLF checkouts break every lab script) | Required |
| `curl` installed | Required |
| `jq` and `openssl` installed | Recommended |
| Clock within 5 minutes of GitHub's (WSL2 drifts after hibernate) | Required |
| `python3` ≥ 3.10 that can create a venv with pip (lab scripts) | Required |
| `uv` that can create a Python 3.12 venv (Lab 03 linters, same Python as CI) | Required |
| `docker` ≥ 24, daemon running, and `docker compose` v2 | Required |
| Memory available to Docker ≥ 8 GB (labs 04–06 run three gateways + DB + runner) | Recommended |
| CPUs available to Docker ≥ 4 | Recommended |
| Logged in to Docker Hub (anonymous pulls are rate-limited per IP — the classroom shares one) | Recommended |
| `gh` (GitHub CLI) installed and authenticated | Required |
| `gh` token has the `repo` and `workflow` scopes (Lab 03 pushes workflow files) | Required |
| `git push` can authenticate to GitHub (gh credential helper or SSH key) | Required |
| VS Code installed (`code` on PATH) | Recommended |
| Ignition Designer Launcher installed (best-effort detection) | Recommended |
| No locally installed Ignition gateway (its service squats on 8088) | Recommended |
| At least 20 GB free disk space | Recommended |
| At least 8 GB total RAM | Recommended |
| Containers can reach GitHub and GHCR over HTTPS (detects corporate TLS interception) | Required |
| Lab ports are free: 8060-8062 | Required |
| Lab ports are free: 8088-8090, 5432 (a busy one can be moved with the lab's `.env`, see [troubleshooting](./troubleshooting.md#ports-already-in-use)) | Recommended |
| Can pull every course image (`ignition:8.3.8`, `timescaledb` for Labs 04-06 and Lab 07, `github-runner`, `migrate`, `alpine`) | Required |
| Directories in the course repo accept `chmod g+s` (setgid) | Recommended |
| Gateway container (uid 2003) can write to a bind mount from the course repo | Required |
| Gateway container starts and responds over HTTP | Required |

## If something fails

1. Read the suggestion the script prints
2. Check the [`troubleshooting.md`](./troubleshooting.md) guide
3. Post your `preflight/preflight-report.txt` in the Discord `#preflight-help` channel
4. The TA will follow up within 24h on weekdays

## Platform notes

- **Windows:** you must use **WSL2 with Docker Desktop's WSL2 backend**. Run the preflight script from inside Ubuntu (or your WSL distro of choice). Native Windows / Git Bash setups are not supported. **Keep your course repo clones (`cicd-for-ignition` and, for Lab 07, your clone of `Mustry-Solutions/demo-oatmakers`) in your Linux home (`~/mustry-academy/…`), never under `/mnt/c/…`.** See [`WSL-SETUP.md`](./WSL-SETUP.md). A repo on the Windows drive is governed by Windows ACLs rather than your WSL user, so your Windows user, your WSL user and the gateway container's user are three different identities: `chown` and `chmod` do not stick, Docker bind mounts lose permission bits, and the only thing that seems to help is running WSL as a Windows administrator, which hides the problem and makes every later lab worse. The lab setup scripts refuse to run from there, and none of them ever need `sudo`. Note that the **disk space and RAM figures are measured inside WSL2, not for your whole Windows machine**: that's deliberate, since Docker images, volumes and containers live in WSL2. The RAM number is the WSL2 VM's allocation (configurable in `C:\Users\<you>\.wslconfig`).
- **macOS:** Apple Silicon is fully supported. Ignition publishes `linux/arm64` images.
- **Linux:** Docker Engine + Docker Compose v2. The smoothest experience.

## Licence

Apache 2.0. See [`LICENSE`](./LICENSE).
