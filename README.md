# Floci Challenge — Setup Guide

This guide walks you through setting up your local AWS environment for the
AWS Architecture Challenge. Follow the steps in order. Do this **before**
event day — you don't want to spend your build time installing software.

> **Floci** is a free, local AWS emulator. It runs real AWS-compatible
> services (S3, DynamoDB, SQS, Lambda, API Gateway, Cognito) on your own
> laptop — no AWS account, no credit card, no internet dependency once set up.

---

## Step 1: Install Docker Desktop

1. Go to [https://docs.docker.com/desktop/](https://docs.docker.com/desktop/)
2. Download Docker Desktop for your operating system (Windows/Mac/Linux)
3. Run the installer
   - **Windows:** the installer will prompt you to enable WSL 2 if it isn't
     already — follow its instructions and restart if asked
4. Launch Docker Desktop from your Start Menu / Applications
5. Wait until it shows **"Engine running"** — this can take a minute on first launch

**Check it worked** — open a terminal (PowerShell on Windows, Terminal on
Mac/Linux) and run:
```bash
docker version
docker compose version
```
Both commands should print version numbers, not an error.

---
## Step 2: Clone the challenge repository

```bash
git clone https://github.com/jeffkyalo21/floci-challenge.git
cd floci-challenge
```

If you don't have `git` installed, download the repository as a ZIP from
GitHub instead (green **Code** button → **Download ZIP**), then extract it
and open a terminal in that folder.

---

## Step 3: Set up your environment file

```bash
cp .env.example .env
```

On Windows PowerShell, use:
```powershell
copy .env.example .env
```

You don't need to edit this file — it already contains working defaults.

---

## Step 4: Start the environment

```bash
docker compose up -d
```

This downloads and starts two containers: **Floci** (the AWS emulator) and
**Floci Dash** (a visual dashboard). The first run downloads images and can
take a few minutes depending on your internet speed — this is normal.

---
## Step 5: Confirm both containers are healthy

```bash
docker inspect --format='{{.State.Health.Status}}' floci
docker inspect --format='{{.State.Health.Status}}' floci-dash
```

Both should print `healthy`. If either says `starting`, wait 30 seconds and
check again. If either says `unhealthy`, see **Troubleshooting** below.

---

## Step 6: Run the verification script

**Windows PowerShell:**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/verify.ps1
```

**Mac / Linux / Git Bash / WSL:**
```bash
bash scripts/verify.sh
```

This confirms each AWS service (S3, DynamoDB, SQS, Lambda, API Gateway,
Cognito) is reachable. You should see a confirmation line for each service.

---

## Step 7: Open the dashboard

Open your browser to:

**[http://localhost:9877](http://localhost:9877)**

This is **Floci Dash** — a visual, AWS Console-style dashboard where you can
see and manage the resources you create (buckets, tables, queues, functions)
without needing the command line for everything.

---
## Step 8: (Recommended) Pre-download the Lambda runtime

If your challenge design uses Lambda, the first invocation downloads a real
runtime image (~753 MB). Avoid doing this for the first time during the
event — run this now instead:

```bash
docker pull public.ecr.aws/lambda/python:3.12
```

---

## You're ready

At this point you have:
- ✅ Docker running
- ✅ Floci and Floci Dash containers healthy
- ✅ All services verified reachable
- ✅ The dashboard open at localhost:9877

You're set up to start designing and building your architecture using the
available services below.

---

## Available Services

| Service       | Notes |
|---------------|-------|
| S3            | Storage and object management (CLI + Dashboard) |
| DynamoDB      | NoSQL database tables (CLI + Dashboard) |
| SQS           | Message queuing, standard and FIFO (CLI + Dashboard) |
| Lambda        | Serverless functions (real runtime containers) |
| API Gateway   | REST API endpoints |
| Cognito       | Identity and user pool management |

All services are reached through one endpoint: `http://localhost:4566`

---
## Troubleshooting

| Problem | Fix |
|---------|-----|
| `Cannot connect to Docker daemon` | Docker Desktop isn't running — launch it and wait for "Engine running" |
| A container says `unhealthy` | Run `docker logs floci` or `docker logs floci-dash` to see the actual error |
| Lambda invoke hangs or times out | First run pulls a ~753 MB image — wait 1-2 minutes, or pre-pull it (Step 8) |
| Port `4566` or `9877` already in use | Run `docker ps` to find what's using it, or stop the conflicting app |
| `git` command not found | Download the repo as a ZIP from GitHub instead (see Step 2) |
| Windows: install got stuck on WSL 2 | Restart your machine, then reopen Docker Desktop |
| Verification script shows a failure | Re-run Step 5 to confirm both containers are healthy first |

If none of these fix it, ask an event organizer for help before the build
phase starts — don't lose your build time debugging setup issues alone.

---

## Resetting your environment

If you want to wipe everything and start fresh:

```bash
docker compose down
rm -rf data/*
docker compose up -d
```

On Windows PowerShell, replace `rm -rf data/*` with:
```powershell
Remove-Item -Recurse -Force data\*
```

---

## Project Structure

```
floci-challenge/
├── docker-compose.yml   # Floci + Floci Dash container definitions
├── .env.example         # Template credentials (copy to .env in Step 3)
├── data/                # Your persistent state (gitignored)
└── scripts/
    ├── verify.sh        # Verification script (Mac/Linux/WSL)
    └── verify.ps1       # Verification script (Windows)
```
