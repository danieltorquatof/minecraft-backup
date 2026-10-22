# syntax=docker/dockerfile:1

# java25 runs the latest Minecraft releases; see README for other tags.
ARG MC_IMAGE_TAG=java25

FROM itzg/minecraft-server:${MC_IMAGE_TAG}

LABEL org.opencontainers.image.title="minecraft-backup" \
      org.opencontainers.image.description="itzg/minecraft-server with automatic Git/GitHub world backups" \
      org.opencontainers.image.source="https://github.com/danieltorquatof/minecraft-backup" \
      org.opencontainers.image.licenses="MIT"

COPY --chmod=755 entrypoint.sh /opt/minecraft-backup/
COPY --chmod=755 utils/ /opt/minecraft-backup/utils/
COPY --chmod=755 scripts/ /opt/minecraft-backup/scripts/

ENTRYPOINT ["/opt/minecraft-backup/entrypoint.sh"]
