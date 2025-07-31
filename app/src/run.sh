#!/bin/bash

set -eu

b64() {
  base64 -w0 2>/dev/null || base64 | tr -d '\n'
}

data=$(curl -sS "https://httpbin.org/ip")

body=$(printf '%s' "$data" | b64)
printf '{"statusCode":200,"headers":{"Content-Type":"application/json","Access-Control-Allow-Origin":"*"},"isBase64Encoded":true,"body":"%s"}' "$body"