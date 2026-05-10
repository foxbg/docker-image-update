# Docker Image Update Utility

A portable, dependency-free Bash script to check for and apply updates to running Docker containers.

## 🚀 Features

- **No-Pull Update Detection**: Uses `docker manifest inspect` to check for updates on remote registries without downloading the images first.
- **Docker Compose Integration**: Automatically detects Compose-managed containers and uses `docker compose pull && docker compose up -d` to preserve networks, volumes, and configurations.
- **Standalone Support**: Detects and pulls updates for standalone containers.
- **Automated Cleanup**: Reclaims disk space by pruning dangling/old images after a successful update.
- **CI/CD Ready**: Provides specific exit codes for easy integration with automation tools and notifications (e.g., cron, email).
- **Architecture Aware**: Automatically detects and checks the correct manifest for your system's architecture (amd64, arm64, etc.).
- **Zero Dependencies**: Requires only the Docker CLI and standard Linux coreutils.

## 📦 Installation

Simply download the script to your machine and make it executable:

```bash
curl -O https://raw.githubusercontent.com/foxbg/docker-image-update/main/docker-update.sh
chmod +x docker-update.sh
```

## 🛠 Usage

### Modes

| Mode | Description |
| :--- | :--- |
| `check` | Scans all running containers and identifies those with updates available (Default). |
| `apply` | Pulls new images and restarts Compose services or pulls images for standalone containers. |

### Options

| Option | Description |
| :--- | :--- |
| `--dry-run` | Simulates the `apply` mode without making any changes. |
| `-v, --version` | Displays version information. |
| `-h, --help` | Displays the help menu. |

### Examples

**Check for updates:**
```bash
./docker-update.sh
```

**Apply updates to all running containers:**
```bash
./docker-update.sh apply
```

**Preview updates without applying them:**
```bash
./docker-update.sh apply --dry-run
```

## 🤖 Automation (Cron)

This utility is designed to work seamlessly with `cron`. Use the exit codes to trigger notifications.

### Exit Codes

| Code | Meaning |
| :--- | :--- |
| `0` | Success / All containers are up to date. |
| `2` | Updates are available (only in `check` mode). |
| `1` | Error occurred. |

### Example Cron Job

Check for updates daily at 3:00 AM and log the output:
```cron
0 3 * * * /path/to/docker-update.sh check >> /var/log/docker-update.log 2>&1
```

Trigger an email notification if updates are found:
```bash
./docker-update.sh check || if [ $? -eq 2 ]; then send_update_email; fi
```

## 📜 License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**. 

The AGPL-3.0 ensures that any modifications to this software must be shared with the community, even if the software is used to provide a service over a network (SaaS). See the [LICENSE](LICENSE) file for the full text.
