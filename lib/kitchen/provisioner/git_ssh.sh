#!/bin/sh
# Workaround: GIT_SSH_COMMAND is not supported by Git < 2.3
exec "${GIT_SSH_COMMAND:-ssh}" "$@"
