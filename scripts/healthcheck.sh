#!/bin/bash
# Docker HEALTHCHECK of the Horizon image: healthy once the game is up and running.

horizon-server --dir /data status --json 2>/dev/null | grep -q '"phase":"running"'
