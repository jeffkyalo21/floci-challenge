# Floci Challenge — Local AWS Emulator Environment

> **Floci** is a free, open-source local AWS emulator that runs 90+ AWS services on a single port (4566).

## Run in GitHub Codespaces (Zero Install / In-Browser)

Students and participants can launch and use this entire environment directly in their web browser without installing Docker locally:

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/jeffkyalo21/floci-challenge)

1. Open the repository on GitHub: [https://github.com/jeffkyalo21/floci-challenge](https://github.com/jeffkyalo21/floci-challenge)
2. Click **Code** > **Codespaces** > **Create codespace on main**
3. Codespaces automatically builds the environment, starts Floci and Floci Dash, and forwards the ports.
4. The **Floci Dash Web UI** (port 9877) will automatically open in a browser preview tab.

---

## Local Prerequisites

| Tool           | Version Tested | Required |
|----------------|---------------|----------|
| Docker Desktop | 4.88+         | ✅       |
| AWS CLI v2     | 2.36+         | ✅       |
| PowerShell 5+  | 5.1+          | ✅ (Windows) |

## Web UI — Floci Dash

The environment includes **Floci Dash**, an AWS Console-style web management dashboard built with AWS Cloudscape Design System.

- **URL:** [http://localhost:9877](http://localhost:9877)
- **Container Port:** `3000` (mapped to `9877` on host)
- **Image:** `ghcr.io/ofsazib/floci-dash:latest`

### UI Capabilities & Known Caveats
- **S3:** Full support via UI — browse buckets, inspect contents, upload files, create/delete buckets.
- **SQS:** Full support via UI — browse queues, view attributes, send messages, inspect messages, and purge queues.
- **DynamoDB:** Table listing and table creation work via UI. **Caveat:** Navigating to individual table detail views (`/#/services/dynamodb/<table-name>`) currently triggers a minified React error #310 in floci-dash ("Rendered more hooks than previous render"), rendering table item management unavailable in the UI. Manage DynamoDB items via AWS CLI or SDK instead.

## Quick Start

```bash
# 1. Copy environment file
cp .env.example .env

# 2. Start Floci and Floci Dash
docker compose up -d

# 3. Wait for containers to be healthy
docker inspect --format='{{.State.Health.Status}}' floci
docker inspect --format='{{.State.Health.Status}}' floci-dash

# 4. Open the Web UI in your browser:
#    http://localhost:9877

# 5. Verify everything works via automated test suite:
#    Windows PowerShell:
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1

#    Bash (WSL / Git Bash / macOS / Linux):
bash scripts/verify.sh
```

## Verified Services

| Service       | Status | Notes |
|---------------|--------|-------|
| S3            | ✅ Full | Buckets, objects, multipart (CLI + Web UI) |
| DynamoDB      | ✅ Full | Conditional writes (`ConditionalCheckFailedException`), tables in UI; use CLI for items |
| SQS           | ✅ Full | Standard + FIFO queues, send/receive (CLI + Web UI) |
| Lambda        | ✅ Full | Real runtime containers (python3.12 tested). First invoke pulls ~753 MB runtime image. |
| API Gateway   | ✅ Full | REST API with Lambda proxy integration |
| Cognito       | ✅ Full | User pools, user creation, `USER_PASSWORD_AUTH` with JWT tokens |
| Floci Dash    | ✅ Full | Web UI on port 9877 connecting to Floci emulator |

## Important Notes

### Lambda Runtime Images
The first Lambda invocation pulls a real runtime container image from ECR public:
- `public.ecr.aws/lambda/python:3.12` (~753 MB)

**Pre-cache this on your machine** before event day:
```bash
docker pull public.ecr.aws/lambda/python:3.12
```

### Docker Socket
The `docker-compose.yml` mounts `/var/run/docker.sock` into the container. This is required for services that spin up real containers (Lambda, RDS, ECS, etc.).

### Persistence
Data is stored in `./data/` via a bind mount. To reset all state:
```bash
docker compose down
rm -rf data/*
docker compose up -d
```

### Credentials
Any non-empty credentials work. The `.env` uses `test`/`test`.

## Disk Space

| Component | Size |
|-----------|------|
| Floci image | ~565 MB |
| Floci Dash image | ~280 MB |
| Python 3.12 Lambda runtime | ~753 MB |
| **Total minimum** | **~1.6 GB** |

Ensure at least **5 GB free** for comfortable headroom (container layers, Lambda staging, etc.).

## Project Structure

```
floci-challenge/
├── docker-compose.yml   # Floci + Floci Dash container definitions
├── .env.example         # Template credentials & UI URL (copy to .env)
├── .env                 # Your local credentials (gitignored)
├── data/                # Persistent Floci state (gitignored)
│   └── .gitkeep
└── scripts/
    ├── verify.sh        # Bash verification script (includes UI check)
    └── verify.ps1       # PowerShell verification script (includes UI check)
```

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `Cannot connect to Docker daemon` | Start Docker Desktop |
| Lambda invoke hangs | First run pulls ~753 MB image — wait 1-2 min |
| Port 4566 or 9877 in use | `docker ps` to find conflict, or change port in compose |
| Health check fails | `docker logs floci` or `docker logs floci-dash` for startup errors |

