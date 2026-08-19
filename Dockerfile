# Railway wrapper for New API (QuantumNous/new-api).
#
# Adds three things a stock deploy cannot do on Railway:
#   1. seeds the root administrator before the public port is ever served, so the
#      instance is not claimable by the first stranger who opens the URL,
#   2. re-applies that credential on every boot, making a redeploy a working
#      account recovery (upstream exposes no recovery path without SMTP),
#   3. refuses to boot when the administrator credential is empty.
FROM calciumion/new-api:v1.0.0-rc.25

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         curl postgresql-client python3 python3-bcrypt \
    && rm -rf /var/lib/apt/lists/*

# Literals baked here rather than published as template variables: a literal
# defaultValue is dropped at generate time and would publish as a blank required
# field on the deploy form.
ENV TZ=UTC \
    ERROR_LOG_ENABLED=true \
    BATCH_UPDATE_ENABLED=true \
    NEW_API_ADMIN_USERNAME=admin

COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod +x /usr/local/bin/railway-entrypoint.sh

WORKDIR /data
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
