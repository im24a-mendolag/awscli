#!/bin/bash
# common.sh - Shared setup for all lab scripts

# --- Load .env ---
if [ ! -f .env ]; then
  echo "ERROR: .env file not found. Create one with your AWS credentials."
  exit 1
fi
# Strip Windows carriage returns (\r) so the file works whether edited on
# Windows or Mac/Linux. Without this, values get a \r appended and AWS CLI
# rejects the credentials even though they look correct.
_ENV_CLEAN=$(mktemp)
tr -d '\r' < .env > "$_ENV_CLEAN"
set -a
source "$_ENV_CLEAN"
set +a
rm -f "$_ENV_CLEAN"
# -----------------

# --- Credential check ---
echo "==> Checking AWS credentials..."

if ! command -v aws &>/dev/null; then
  echo "ERROR: 'aws' command not found. Install the AWS CLI and make sure it is on your PATH."
  exit 1
fi

# Detect quotes left in from the template (e.g. aws_access_key_id='ASIA...')
# Docker --env-file does not strip quotes, so they end up in the value.
for _VAR in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN; do
  _VAL="${!_VAR}"
  if [[ "$_VAL" == \'* ]] || [[ "$_VAL" == \"* ]]; then
    echo "ERROR: $_VAR starts with a quote character."
    echo "       Remove the surrounding quotes from the value in your .env file."
    exit 1
  fi
done

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_SESSION_TOKEN" ]; then
  echo "ERROR: One or more credentials are missing from .env."
  echo "       Fill in AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN."
  exit 1
fi

IDENTITY=$(aws sts get-caller-identity --output text 2>&1)
if [ $? -ne 0 ]; then
  echo "ERROR: AWS credentials are expired or invalid."
  echo "       Update your .env file with fresh credentials from the lab and re-run."
  echo "       AWS response: $IDENTITY"
  exit 1
fi
ACCOUNT_ID=$(echo "$IDENTITY" | awk '{print $1}')
echo "    Credentials OK."
echo "    Account ID: $ACCOUNT_ID"
echo "    If this account ID doesn't match your lab, update your .env and re-run."
# ------------------------
