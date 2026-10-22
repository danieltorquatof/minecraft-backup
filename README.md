# 📦 Minecraft Backup

*A robust, automated Minecraft backup system powered by Docker and GitHub.*

This repository — **[danieltorquatof/minecraft-backup](https://github.com/danieltorquatof/minecraft-backup)** — provides a fully automated backup workflow for Minecraft Java Edition servers running inside Docker.
It integrates Git versioning, GitHub remote storage, periodic world saves, structured logging, and graceful shutdown procedures.

The solution is built on top of the official [`itzg/minecraft-server`](https://docker-minecraft-server.readthedocs.io/en/latest/) image (Java 25 by default) and wraps it with a custom entrypoint that restores the world at startup, backs it up periodically, and takes a final backup on shutdown.

---

## ✨ Key Features

* **Automated World Backups**
  Saves your Minecraft world at regular intervals using Git commits.

* **GitHub Integrated Storage**
  Pushes backups to a private or public GitHub repository (or any Git remote).

* **Consistent Snapshots**
  Automatic saving is paused (`save-off` / `save-all flush`) while files are staged, so a backup never captures a half-written region file.

* **Graceful Shutdown Protection**
  On `docker compose stop` / `down`, the server is stopped cleanly first, then a final backup is committed and pushed.

* **Safe Credentials**
  The GitHub token is only kept in memory: it is never written to the repository config, remote URL or logs.

* **Fully Compatible with Official Image Environment Variables**
  You can configure the server using any variables supported by the original Docker image.

---

## 📋 Requirements

* Linux, macOS or Windows (WSL 2) with **Docker Engine 23+** (BuildKit) and the **Docker Compose v2** plugin (`docker compose`).
* A GitHub account and an empty repository for the backups.
* About 4 GB of free RAM for the server (configurable with `MEMORY`).

---

## 📁 Project Structure

```bash
.
├── .github/workflows/ci.yml   # ShellCheck, Hadolint, compose validation and image build
├── docker-compose.yml
├── Dockerfile
├── entrypoint.sh              # Startup → periodic loop → graceful shutdown
├── .env.example
├── scripts
│   ├── autosave.sh            # Periodic backup (can also be run by hand)
│   ├── init.sh                # Restores/clones the world before the server starts
│   └── shutdown.sh            # Final backup after the server stops
└── utils
    ├── common.sh              # Shared configuration, git/RCON helpers
    ├── log.sh                 # Logging to stdout and ./logs
    └── saveWorld.sh           # Flush → commit → push
```

Inside the image, everything is installed under `/opt/minecraft-backup/`.

---

## 🚀 How to Run the Project

### 1. Clone the repository

```bash
git clone https://github.com/danieltorquatof/minecraft-backup.git
cd minecraft-backup
```

### 2. Create your `.env` file

```bash
cp .env.example .env
```

Then edit `.env` and fill in the required variables (see next section).

### 3. Build and start the container

```bash
docker compose up -d --build
```

The Minecraft server will start, periodic backups will be scheduled, and logs will be written to `./logs`. Follow them with:

```bash
docker compose logs -f
```

> By starting the server you accept the [Minecraft EULA](https://www.minecraft.net/eula) (`EULA=TRUE` in `docker-compose.yml`).

---

## 📝 Required Pre-Execution Steps

### ✅ 1. Create a new (empty) GitHub repository

This repository will store your automatic world backups. A **private** repository is recommended.

Official guide:
🔗 [Creating a new repository](https://docs.github.com/en/repositories/creating-and-managing-repositories/creating-a-new-repository)

Put the repository **name only** (not the full URL) in your `.env`. It is also used as the world folder name (`LEVEL`):

```Dotenv
REPO_NAME=MyMinecraftWorld
```

### ✅ 2. Create a GitHub *Personal Access Token*

This token is used for pushing commits from inside the container to your GitHub repository.

Official guide:
🔗 [Managing your personal access tokens](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens)

Recommended: a **fine-grained token** restricted to the backup repository, with the **Contents: Read and write** permission. A classic token with the `repo` scope also works.

```Dotenv
GITHUB_USER=your_github_username
GITHUB_TOKEN=your_token_here
```

### ✅ 3. Review the remaining variables

| Variable              | Default                | Description                                                                                          |
| --------------------- | ---------------------- | ---------------------------------------------------------------------------------------------------- |
| `GITHUB_USER`         | —                      | **Required.** Owner of the backup repository.                                                        |
| `GITHUB_TOKEN`        | —                      | **Required.** Token with write access to the backup repository.                                      |
| `REPO_NAME`           | —                      | **Required.** Backup repository name and world folder name.                                          |
| `PERIODIC_INTERVAL`   | `15`                   | Minutes between automatic backups.                                                                   |
| `GIT_AUTHOR_NAME`     | `Minecraft Autosave`   | Name used in backup commits.                                                                         |
| `GIT_AUTHOR_EMAIL`    | `minecraft-autosave@localhost` | E-mail used in backup commits.                                                               |
| `GIT_REMOTE_URL`      | `https://github.com/$GITHUB_USER/$REPO_NAME.git` | Use any other Git remote (GitLab, Gitea, a local bare repo…).              |
| `GIT_BRANCH`          | `main`                 | Branch used when the backup repository is created from scratch.                                      |
| `MC_IMAGE_TAG`        | `java25`               | Base image tag. Use `java21`, `java17` or `java8` for older Minecraft/modded versions.                |
| `MC_HOST_PORT`        | `25565`                | Host port players connect to.                                                                        |
| `MEMORY`              | `4G`                   | Java heap size.                                                                                      |
| `TYPE` / `VERSION`    | `VANILLA` / `LATEST`   | Server type and Minecraft version.                                                                   |
| `SEED`                | random                 | World seed (only used when the world is first created).                                              |
| `RCON_PASSWORD`       | random on each start   | RCON password. Leave it unset unless you need to connect with an external RCON client.               |

Any other [variable of the official image](https://docker-minecraft-server.readthedocs.io/en/latest/variables/) (`MOTD`, `MAX_PLAYERS`, `OPS`, `WHITELIST`, …) can be added to `.env` as usual.

---

## ▶️ How the System Works

### 🔹 On Startup (`init.sh`)

* Ownership of `/data` and the world folder is handed to the server user (UID/GID `1000` by default).
* If the remote repository has backups, it is cloned — or, if it was already cloned, updated with `git pull --ff-only`.
* If the remote repository is empty, a new local repository is prepared and the server generates a new world inside it.
* If a local world exists **without** backup history but the remote has one, the local folder is kept as `data/<REPO_NAME>.local-<timestamp>` and the remote world is restored.

### 🔹 During Gameplay (`autosave.sh`)

Every `PERIODIC_INTERVAL` minutes, while the server is online:

1. Players are notified (`📂 Backup started!`).
2. `save-off` + `save-all flush` write everything to disk and pause automatic saving.
3. Changes are staged with `git add`, then `save-on` is restored.
4. A commit is created (only when something changed) and pushed to GitHub.
5. Players are notified (`📁 Backup completed!`, or a warning if the upload failed).

### 🔹 On Shutdown (`shutdown.sh`)

1. The container receives `SIGTERM` (`docker compose stop`/`down`/`restart`).
2. The Minecraft server is stopped gracefully and saves the world.
3. A final commit is created and pushed.

`docker-compose.yml` sets `stop_grace_period: 3m` so Docker does not kill the container in the middle of this process. The same final backup runs if the server stops on its own (e.g. `/stop` in game).

---

## 🧰 Useful Commands and Directories

| Directory | Purpose                                                             |
| --------- | ------------------------------------------------------------------- |
| `data/`   | Minecraft server data. `data/<REPO_NAME>/` is the world and the Git repository. |
| `logs/`   | `entrypoint.log`, `init.log`, `autosave.log` and `shutdown.log`.    |

Run a backup right now:

```bash
docker compose exec minecraft /opt/minecraft-backup/scripts/autosave.sh
```

Open the server console (RCON):

```bash
docker compose exec minecraft rcon-cli
```

Restore an older backup: stop the server, check out the desired commit inside `data/<REPO_NAME>` and start it again — or simply delete `data/` and the latest backup will be cloned on the next start.

> RCON (port `25575`) is **not** published to the host, since backups only use it from inside the container. If you need external access, add `"127.0.0.1:25575:25575"` to `ports` and set `RCON_PASSWORD`.

---

## 🩺 Troubleshooting

* **`could not reach the backup repository`** — check `GITHUB_USER`, `REPO_NAME` and that the token has write access to that repository.
* **`local and remote histories diverged`** — the remote received commits from somewhere else. Resolve it manually inside `data/<REPO_NAME>` (e.g. `git pull --rebase` or force-push the copy you want to keep).
* **Push rejected because of file size** — GitHub rejects files over 100 MB. Region files are usually far smaller, but huge modded worlds may need [Git LFS](https://git-lfs.com/) or another remote (`GIT_REMOTE_URL`).
* **Container exits immediately** — run `docker compose logs`; configuration errors (missing variables, invalid interval) are reported there.

---

## ⬆️ Upgrading from the previous version

* The base image moved from `java21` to `java25`, required by the latest Minecraft releases. Set `MC_IMAGE_TAG=java21` to keep the old one.
* Scripts moved from `/usr/local/bin` to `/opt/minecraft-backup`.
* Remote URLs containing the token are rewritten automatically on the next start, and root-owned files left in the world folder are given back to the server user.
* RCON is no longer published on the host, and `SERVER_PORT`/`SERVER_IP` were replaced by `MC_HOST_PORT`. Compare your `.env` with `.env.example`.
* Old `logs/*.log` files may contain the token in clear text (`Adding remote origin: https://<token>@…`). Delete them and consider rotating the token.

---

## 🤝 Contributing

Contributions, issues, and pull requests are welcome.
CI runs [ShellCheck](https://www.shellcheck.net/), [Hadolint](https://github.com/hadolint/hadolint), `docker compose config` and an image build on every pull request — please make sure they pass and that changes stay compatible with the official server image.

---

## 📄 Licence

This project is available under the MIT licence.
