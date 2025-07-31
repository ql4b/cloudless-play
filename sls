#!/bin/bash

ROOT_PATH=$(realpath $(dirname "$0"))
APP_PATH="$ROOT_PATH/app"
ENV_FILENAME="$ROOT_PATH/.env"

set -a
. $ENV_FILENAME
set +a

SERVERLESS='./node_modules/serverless/run.js'

cd $APP_PATH && "$SERVERLESS" \
  "$@"
