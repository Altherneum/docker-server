# =============================================================================
# code-server officiel (Coder).
# Docs : https://coder.com/docs/code-server
# =============================================================================
FROM codercom/code-server

USER root
RUN install -d -o coder -g coder /home/coder/workspace \
    && install -d /home/coder/.local/share/code-server/extensions \
    && chown -R coder:coder /home/coder/.local/share

# Extensions par défaut : elles sont listées dans stacks/code-server/extensions.txt.
# Ce fichier est copié dans l'image puis relu au démarrage pour compléter un
# volume code-server-data existant.
COPY extensions.txt /usr/local/share/code-server/extensions.txt

# Extensions préinstallées : Docker les recopie dans un volume code-server-data
# neuf. Un volume déjà existant est complété par entrypoint.sh.
# Cette étape reste avant la copie de l'entrypoint pour profiter du cache.
USER coder
RUN while read -r extension; do \
        case "$extension" in \
            ""|\#*) continue ;; \
        esac; \
        code-server --install-extension "$extension" || exit 1; \
    done < /usr/local/share/code-server/extensions.txt

USER root
COPY entrypoint.sh /usr/local/bin/code-server-entrypoint
COPY clone-github-org.sh /usr/local/bin/clone-github-org
RUN chmod +x /usr/local/bin/code-server-entrypoint /usr/local/bin/clone-github-org

USER coder

WORKDIR /home/coder/workspace

ENTRYPOINT ["/usr/local/bin/code-server-entrypoint"]
