# Frontend Build Environment Variables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Configure the Docker build stage for the frontend Vue/Vite application to accept build arguments (such as `VITE_USE_MOCKS`, `VITE_API_BASE_URL`, `VITE_REVERB_HOST`, `VITE_REVERB_APP_KEY`) and map them as environment variables during build, and configure these variables under `[build.args]` in `fly.toml`.

**Architecture:** We use Docker build-time arguments (`ARG`) and environment variables (`ENV`) inside the `frontend` build stage of the `Dockerfile` to bake these configurations into the Vue/Vite production build. The arguments are defined in `fly.toml` under `[build.args]` for Fly.io.

**Tech Stack:** Docker, Fly.io, Node.js (Vite)

## Global Constraints

- Do not modify backend runtime variables.
- Ensure the Docker build syntax is compatible with Dockerfile version 1.6.

---

### Task 1: Update Dockerfile to declare and export build arguments

**Files:**
- Modify: [Dockerfile](file:///home/apetrenko/projects/pet/expedition/expedition-deploy/Dockerfile#L22-L30)

- [ ] **Step 1: Declare ARGs and ENVs in the Stage 2 build stage**
  Modify lines 22-30 in `Dockerfile` to include the build-args declaration before `npm ci`.

  ```dockerfile
  # ---------- Stage 2: збірка фронтенду ----------
  FROM node:20-alpine AS frontend
  WORKDIR /app

  ARG VITE_USE_MOCKS=false
  ARG VITE_API_BASE_URL=/api
  ARG VITE_REVERB_HOST=expedition-demo.fly.dev
  ARG VITE_REVERB_APP_KEY

  ENV VITE_USE_MOCKS=$VITE_USE_MOCKS
  ENV VITE_API_BASE_URL=$VITE_API_BASE_URL
  ENV VITE_REVERB_HOST=$VITE_REVERB_HOST
  ENV VITE_REVERB_APP_KEY=$VITE_REVERB_APP_KEY

  COPY --from=sources /src/frontend/package.json /src/frontend/package-lock.json ./
  RUN npm ci
  COPY --from=sources /src/frontend/. .
  # .env.production фронтенду має вказувати на прод-адресу API/WS (див. розділ 8)
  RUN npm run build
  ```

- [ ] **Step 2: Commit Dockerfile changes**
  Run command:
  ```bash
  git add Dockerfile
  git commit -m "deploy: add frontend environment build args to Dockerfile"
  ```

### Task 2: Configure build arguments in fly.toml

**Files:**
- Modify: [fly.toml](file:///home/apetrenko/projects/pet/expedition/expedition-deploy/fly.toml#L9-L19)

- [ ] **Step 1: Add `[build.args]` section in `fly.toml`**
  Modify the `[build]` section to specify the default build arguments. Note: The `VITE_REVERB_APP_KEY` value should be placeholders or set to the public app key.

  ```toml
  [build]
    [build.args]
      VITE_USE_MOCKS = "false"
      VITE_API_BASE_URL = "/api"
      VITE_REVERB_HOST = "expedition-demo.fly.dev"
      VITE_REVERB_APP_KEY = "<REVERB_APP_KEY>"
  ```

- [ ] **Step 2: Commit fly.toml changes**
  Run command:
  ```bash
  git add fly.toml
  git commit -m "deploy: add frontend build arguments to fly.toml"
  ```
