#!/usr/bin/env bash
set -euo pipefail
HOST="100.83.83.58"
SESSION="notch-acp"
MSG="${*:-}"
if [ -z "$MSG" ]; then
  echo "usage: notch-acp-relay.sh \"your message\""
  exit 1
fi

# send message + newline
ssh "$HOST" "tmux send-keys -t $SESSION $(printf %q "$MSG") C-m"

# poll pane until next prompt appears
for i in {1..60}; do
  OUT="$(ssh "$HOST" "tmux capture-pane -pt $SESSION | tail -120")"
  # heuristic: once assistant text appears after the sent message, break when prompt returns
  if echo "$OUT" | tail -5 | grep -q '^> '; then
    echo "$OUT"
    exit 0
  fi
  sleep 1
done

echo "$OUT"
exit 0
