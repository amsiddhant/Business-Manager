#!/usr/bin/env bash
# Update packages, build the Flutter app, deploy to Firebase, and push to Git.

set -Eeuo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

on_error() {
    local exit_code=$?
    printf '\n--- Deployment failed (exit code %s) ---\n' "$exit_code" >&2
    exit "$exit_code"
}
trap on_error ERR

printf '%s\n' '--- Starting Deployment Process ---'

printf '\n[1/4] Updating packages...\n'
flutter pub get

printf '\n[2/4] Building Flutter Web app...\n'
flutter build web --release

printf '\n[3/4] Deploying to Firebase Hosting...\n'

# Prefer native Apple Silicon Homebrew Node when available, since Firebase CLI
# uses the Node executable found on PATH.
if [[ -x /opt/homebrew/bin/node ]] && /opt/homebrew/bin/node --version >/dev/null 2>&1; then
    export PATH="/opt/homebrew/bin:$PATH"
fi

if ! command -v node >/dev/null 2>&1 || ! node --version >/dev/null 2>&1; then
    printf '%s\n' "No working Node.js runtime found. On Apple Silicon, install native Node.js with 'brew install node' and retry." >&2
    exit 1
fi

firebase deploy --only hosting

printf '\n[4/4] Pushing changes to Git...\n'
git add .

if ! git diff --cached --quiet; then
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    git commit -m "Deploy: Automated deployment on $timestamp"
fi

git push origin main

printf '\n--- Deployment Completed Successfully! ---\n'
