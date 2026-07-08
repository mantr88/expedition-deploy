# Design Specification: Frontend Build Environment Variables

We need to supply the frontend SPA (Vue/Vite) with the required environment variables during the Docker build stage. Since the frontend is built into static assets at build time, environment variables starting with `VITE_` must be defined during `npm run build`.

We are using Option A, where build arguments are declared in `Dockerfile` and configured in `fly.toml` under `[build.args]`.

## Proposed Changes

### Dockerfile

Modify the frontend build stage (Stage 2) in `Dockerfile` to accept the following `ARG` parameters and set them as environment variables (`ENV`) so that Vite can inject them:
- `VITE_USE_MOCKS` (default: `false`)
- `VITE_API_BASE_URL` (default: `/api`)
- `VITE_REVERB_HOST` (default: `expedition-demo.fly.dev`)
- `VITE_REVERB_APP_KEY`

### fly.toml

Configure the `[build.args]` section to automatically supply these variables during the Fly.io build:
```toml
[build]
  [build.args]
    VITE_USE_MOCKS = "false"
    VITE_API_BASE_URL = "/api"
    VITE_REVERB_HOST = "expedition-demo.fly.dev"
    VITE_REVERB_APP_KEY = "<REVERB_APP_KEY>"
```

## Verification

Verify that:
1. The `Dockerfile` syntax is correct.
2. `fly.toml` contains the correct fields.
