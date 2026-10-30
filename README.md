# new-api-railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/new-api-or-just-updated-llm-gateway-nobo?referralCode=Z1xivh&utm_medium=integration&utm_source=template&utm_campaign=generic)

**Deploy on Railway:** [New API template](https://railway.com/deploy/new-api-or-just-updated-llm-gateway-nobo?referralCode=Z1xivh&utm_medium=integration&utm_source=template&utm_campaign=generic)

Railway wrapper image for [New API](https://github.com/QuantumNous/new-api), the
open-source multi-provider LLM gateway (OpenAI-compatible endpoint in front of many
model providers, with keys, quotas, channels and usage logging).

Image: `ghcr.io/bon5co/new-api-railway:v1.0.0-rc.25`, built from
`calciumion/new-api:v1.0.0-rc.25`.

## What the wrapper adds

1. **The instance is not claimable.** Upstream's `POST /api/setup` has no
   authentication of any kind — its only guard is that no root user exists yet —
   and there is no environment variable that seeds an administrator. On a public
   URL the first stranger to call it becomes root and the deployer is locked out
   permanently. This entrypoint boots New API on an internal port the Railway edge
   does not route, seeds the administrator over loopback, and only then execs the
   real server on `$PORT`.
2. **A redeploy is an account recovery.** New API's own recovery path is an emailed
   reset link, which a fresh deploy has no SMTP for. On every later boot the
   entrypoint re-applies the administrator credential from the environment
   directly in Postgres (bcrypt, `role >= 100`).
3. **It refuses to boot with an empty administrator credential**, rather than
   coming up healthy and claimable.

## Environment

| Variable | Meaning |
| --- | --- |
| `NEW_API_ADMIN_USERNAME` | Administrator login name, 12 characters max. Defaults to `admin`. |
| `NEW_API_ADMIN_PASSWORD` | Administrator credential, 8-20 characters. Required; the container exits if it is empty. |
| `NEW_API_SELF_USE_MODE` | `true` enables New API's self-use mode at first setup. |
| `NEW_API_SETUP_PORT` | Internal port used for the seeding boot. Defaults to `13000`. |
| `SQL_DSN` | Postgres connection string, as upstream. Also used for the per-boot credential refresh. |
| `SESSION_SECRET` / `CRYPTO_SECRET` | As upstream. Set them; without them New API generates a fresh UUID per boot and every session is invalidated on every redeploy. |

Everything else is upstream's.
