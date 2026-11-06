# =============================================================================
# Forgejo Actions Runner (image officielle + curl/jq pour l'enregistrement
# automatique auprès de Forgejo).
# Docs : https://forgejo.org/docs/latest/admin/actions/
# =============================================================================
ARG FORGEJO_RUNNER_VERSION=13.2.1
FROM data.forgejo.org/forgejo/runner:${FORGEJO_RUNNER_VERSION}

LABEL org.opencontainers.image.title="Forgejo Actions Runner"

USER root
RUN apk add --no-cache curl jq
COPY entrypoint.sh /usr/local/bin/forgejo-runner-entrypoint
RUN chmod 755 /usr/local/bin/forgejo-runner-entrypoint

USER 1000:1000
WORKDIR /data
ENTRYPOINT ["/usr/local/bin/forgejo-runner-entrypoint"]
