# DAY 1 — Docker + NGINX + Compose

Date:

## Daily build goals
- [ ] Create repo/project structure.
- [ ] Create simple application/NGINX endpoint.
- [ ] Write and understand Dockerfile.
- [ ] Build/run image; practice logs and exec.
- [ ] Create first Compose stack.
- [ ] Use a feature branch and clean commit.

## Topics to refer to
- Dockerfile: FROM, WORKDIR, COPY, RUN, CMD
- Image vs container
- Layers
- Docker CLI
- Compose services
- Port mapping
- Git branching

## Interview questions
- What happens between `docker build` and `docker run`?
- Why is an image different from a container?
- What does WORKDIR do?
- Why do Dockerfile instructions create layers?
- What does `8083:8080` mean?
- Why use Compose?

## Extra related topics — only if core work is stable
- Docker networking
- Bind mounts
- Docker volumes
- Container healthchecks

## Commands I actually learned / used

| # | Command | Why / what it does |
|---|---|---|
| 1 | `git checkout -b feature/day1-nginx-baseline` | Creates and switches to a new feature branch so Day 1 work stays isolated from `main` and commits are clean. |
| 2 | `Get-Command docker` | Checks whether the `docker` CLI is installed and on PATH at all, before assuming it's a daemon problem. |
| 3 | `Get-Process "*docker*"` | Lists running processes matching "docker". Used to confirm Docker Desktop's background process wasn't running yet. |
| 4 | `Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe"` | Launches Docker Desktop from PowerShell since the daemon wasn't up and `docker compose` needs it running. |
| 5 | `docker info` (polled in a loop with `Start-Sleep`) | The standard way to check if the Docker **daemon** is actually reachable and ready (not just the CLI installed). Polled every 5s until it stopped erroring, to wait out Docker Desktop's startup time. |
| 6 | `docker compose build` | Builds the image(s) defined in `docker-compose.yml` by running the Dockerfile. Needed whenever the Dockerfile or app files change. |
| 7 | `docker compose up -d` | Creates and starts containers for all services in detached (background) mode — this is what actually runs NGINX. |
| 8 | `docker compose ps` | Lists containers for this Compose project with their status and port mappings — quick way to confirm the stack is actually running, not just that the command succeeded. |
| 9 | `Get-NetTCPConnection -LocalPort 8080` | Windows equivalent of checking what's listening on a port. Used to diagnose the "port already allocated" error by finding the process already holding port 8080 on the host. |
| 10 | `curl.exe -i http://localhost:8083/` | Sends an HTTP request and shows response headers + body. Proves NGINX is reachable and serving the expected page for *that* request — not a full health guarantee. |
| 11 | `curl.exe -i http://localhost:8083/health` | Hits the dedicated `/health` endpoint — the same check recovery automation (Ansible, later) will use to decide if NGINX is truly healthy after a restart. |
| 12 | `docker logs nginx --tail 20` | Shows the last 20 lines of the container's stdout/stderr — the evidence trail for what NGINX did (startup, worker processes spawned, access log entries). |
| 13 | `docker exec nginx nginx -v` | Runs a command inside the running container without a full shell session. Confirms the exact NGINX binary/version inside the container. |
| 14 | `docker exec nginx cat /etc/nginx/conf.d/default.conf` | Reads a file from inside the running container to verify the config we `COPY`'d in the Dockerfile is the one actually active at runtime. |

## What I achieved today
_features, commands, experiments, screenshots, breakthroughs_



## What I learned / what broke / what I want to remember
docker stop -t 30 nginx
Docker gives the container 30 seconds to shut down gracefully.
If it still hasn't stopped, Docker forcibly terminates it.

