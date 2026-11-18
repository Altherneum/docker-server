# =============================================================================
# Forgejo officiel (image Codeberg ou son miroir officiel).
# Docs : https://forgejo.org/docs/latest/admin/installation-docker/
#
# FORGEJO_REGISTRY permet d'utiliser le miroir si codeberg.org est
# inaccessible (erreurs `tls: handshake failure` fréquentes sur son registre) :
#   FORGEJO_REGISTRY=codeberg.org     registre principal
#   FORGEJO_REGISTRY=data.forgejo.org miroir officiel (défaut)
#   FORGEJO_REGISTRY=code.forgejo.org autre nom du miroir
# =============================================================================
ARG FORGEJO_REGISTRY=data.forgejo.org
ARG FORGEJO_VERSION
FROM ${FORGEJO_REGISTRY}/forgejo/forgejo:${FORGEJO_VERSION}

LABEL org.opencontainers.image.title="Forgejo"
