#!/bin/sh
# Costruisce l'immagine base php74-patched (PHP 7.4 + backport CVE-2026-109618/109619).
set -eu
cd "$(dirname "$0")"
SHA=$(grep -E '^ENV PHP_PATCH_SHA' Dockerfile | awk '{print $3}')
TAG="php74-patched:${SHA%"${SHA#????????}"}"
docker build ${MAKE_JOBS:+--build-arg MAKE_JOBS=$MAKE_JOBS} -t "$TAG" -t php74-patched:latest .
echo "Immagine: $TAG"
docker run --rm "$TAG" php -v
