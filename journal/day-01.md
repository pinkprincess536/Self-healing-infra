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

**What happens between `docker build` and `docker run`?**
`docker build` reads the Dockerfile and produces an **image** — a read-only set of layered filesystem snapshots plus metadata (entrypoint, exposed ports, etc). Nothing is running yet at this point, it's just a packaged artifact. `docker run` (or `docker compose up`) takes that image and starts a **container**: a live process with its own writable layer on top of the image, its own network namespace, and its own lifecycle. Building happens once (or whenever the Dockerfile/context changes); running can happen many times from the same image.

**Why is an image different from a container?**
An image is like a class; a container is like an instance of it. The image is static and immutable — the same image tag always produces the same starting filesystem. A container is a running instance with mutable state (a thin writable layer, a process, logs, an IP). You can start multiple containers from one image, and deleting a container doesn't affect the image it came from.

**What does WORKDIR do?**
`WORKDIR` sets the working directory inside the image for every subsequent instruction (`COPY`, `RUN`, `CMD`, etc.) and for any process started in the container, similar to running `cd` but persisted across instructions. It also creates the directory if it doesn't exist. In our Dockerfile we set it to `/usr/share/nginx/html` mostly to make the intent explicit — NGINX's base image doesn't strictly need it since we use absolute paths in `COPY`.

**Why do Dockerfile instructions create layers?**
Each instruction that changes the filesystem (`RUN`, `COPY`, `ADD`) produces a new, cached, immutable layer stacked on top of the previous one. This is how Docker achieves build caching (unchanged layers are reused) and image sharing (multiple images can share common base layers, saving disk and transfer time). It's also why instruction order matters: put things that change rarely (like installing dependencies) before things that change often (like copying application code) to maximize cache hits.

**What does `8083:8080` mean?**
It's a port mapping in `host:container` format — traffic hitting port 8083 on the **host machine** gets forwarded to port 8080 **inside the container**. In our actual Compose file this ended up as `8083:80` (host 8083 → container's NGINX listening on 80), because port 8080 on the host was already taken by another process and NGINX inside the container listens on 80, not 8080.

**Why use Compose?**
Compose lets us declare the whole stack (services, ports, build context, networks, restart policy) as one YAML file instead of typing long `docker build`/`docker run` commands by hand. It also gives us a repeatable, versioned definition of "what should be running" — `docker compose up -d` brings the whole environment up consistently, which matters a lot once we add Prometheus, Alertmanager, and other services in later days that all need to talk to each other.

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




## What I learned / what broke / what I want to remember
docker stop -t 30 nginx
Docker gives the container 30 seconds to shut down gracefully.
If it still hasn't stopped, Docker forcibly terminates it.


A bind mount connects a folder/file on your computer to a folder inside a container.

