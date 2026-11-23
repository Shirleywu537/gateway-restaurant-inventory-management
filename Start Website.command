#!/bin/zsh
cd -- "$(dirname -- "$0")" || exit 1
if ! command -v node >/dev/null 2>&1; then
  print "Node.js is required. Install Node.js from https://nodejs.org and reopen this file."
  read "?Press Return to close. "
  exit 1
fi
print "Gateway Inventory — connected to Supabase"
print "Keep this window open while using the website. Press Control+C to stop."
node scripts/serve.mjs --open
