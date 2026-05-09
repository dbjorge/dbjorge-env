#!/bin/bash

# Creates a read-only GitHub fine-grained PAT for use by Claude Code,
# and stores it in the macOS Keychain.
#
# Usage:
# > ./create-claude-ro-gh-token.sh
#
# The token is stored under the keychain account name "claude-ro-gh-token".
# To use it in Claude Code, create ~/.claude/setup-env.sh:
#
#   #!/bin/bash
#   if [ -z "$CLAUDE_ENV_FILE" ]; then
#     echo "WARNING: CLAUDE_ENV_FILE not set, cannot apply GH_TOKEN" >&2
#     exit 1
#   fi
#   if ! security find-generic-password -ga 'claude-ro-gh-token' -w &>/dev/null; then
#     echo "WARNING: claude-ro-gh-token not found in keychain, cannot apply GH_TOKEN" >&2
#     exit 1
#   fi
#   echo "export GH_TOKEN=\$(security find-generic-password -ga 'claude-ro-gh-token' -w 2>/dev/null)" >> "$CLAUDE_ENV_FILE"
#   exit 0
#
# Then add a SessionStart hook to ~/.claude/settings.json:
#
#   {
#     "hooks": {
#       "SessionStart": [{
#         "hooks": [{
#           "type": "command",
#           "command": "bash ~/.claude/setup-env.sh"
#         }]
#       }]
#     }
#   }

set -eo pipefail

KEYCHAIN_ACCOUNT="claude-ro-gh-token"

echo "This script will:"
echo "  1. Open GitHub to create a read-only fine-grained PAT"
echo "  2. Store the token in your macOS Keychain as \"$KEYCHAIN_ACCOUNT\""
echo ""
echo "On the GitHub page, configure the token as follows:"
echo ""
echo "  Token name:        claude-code-ro"
echo "  Expiration:        your preference (90 days is a reasonable default)"
echo "  Repository access:  All repositories"
echo ""
echo "  Repository permissions (all Read-only):"
echo "    - Actions"
echo "    - Actions variables"
echo "    - Artifact metadata"
echo "    - Commit statuses"
echo "    - Contents"
echo "    - Issues"
echo "    - Metadata  (automatically Read-only)"
echo "    - Pull requests"
echo "    - Workflows"
echo ""
echo "  Account permissions: none needed"
echo ""
read -rp "Press Enter to open GitHub..."

open "https://github.com/settings/personal-access-tokens/new"

echo ""
read -rsp "Paste the token here (input hidden): " token
echo ""

if [[ -z "$token" ]]; then
  echo "Error: no token provided."
  exit 1
fi

if [[ ! "$token" =~ ^github_pat_ ]]; then
  echo "Warning: token doesn't start with github_pat_ — are you sure this is a fine-grained PAT?"
  read -rp "Continue anyway? [y/N] " confirm
  if [[ "$confirm" != [yY] ]]; then
    echo "Aborted."
    exit 1
  fi
fi

# Verify the token works and is read-only by checking scopes
echo ""
echo "Verifying token..."
http_code=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $token" \
  "https://api.github.com/user")

if [[ "$http_code" != "200" ]]; then
  echo "Error: GitHub API returned HTTP $http_code. Token may be invalid."
  exit 1
fi

echo "Token is valid."

# Store in keychain (delete existing entry first if present)
if security find-generic-password -a "$KEYCHAIN_ACCOUNT" &>/dev/null; then
  echo "Replacing existing keychain entry for \"$KEYCHAIN_ACCOUNT\"..."
  security delete-generic-password -a "$KEYCHAIN_ACCOUNT" &>/dev/null
fi

security add-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_ACCOUNT" -w "$token"
echo "Token stored in keychain as \"$KEYCHAIN_ACCOUNT\"."
