#!/bin/bash
# run_lab.sh - Build (once) and run a lab script inside Docker
# Usage: ./run_lab.sh <lab_script>
# Example: ./run_lab.sh lab5_1.sh

set -e

SCRIPT="$1"
IMAGE="awscli-labs"

if [ -z "$SCRIPT" ]; then
  echo "Usage: $0 <lab_script>"
  echo "Available labs:"
  ls lab*.sh
  exit 1
fi

if [ ! -f "$SCRIPT" ]; then
  echo "ERROR: '$SCRIPT' not found."
  exit 1
fi

if [ ! -f ".env" ]; then
  echo "ERROR: .env file not found. Copy .env.example and fill in your credentials."
  exit 1
fi

# Build the image if it doesn't exist yet (or pass --build to force rebuild)
if [[ "$*" == *--build* ]] || ! docker image inspect "$IMAGE" &>/dev/null; then
  echo "==> Building Docker image '$IMAGE'..."
  docker build -t "$IMAGE" .
fi

echo "==> Running $SCRIPT inside Docker..."

# Git Bash on Windows returns /c/Users/... paths which Docker can't use for bind mounts.
# pwd -W returns the Windows-style C:/Users/... path that Docker Desktop expects.
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
  HOST_PWD=$(pwd -W)
else
  HOST_PWD=$(pwd)
fi

docker run --rm -it \
  --env-file .env \
  -v "$HOST_PWD:/lab" \
  "$IMAGE" \
  bash "$SCRIPT"
