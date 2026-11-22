#!/usr/bin/env bash
# One-shot (founder 2026-10-20: "pause canary for 2 days and see what happens"). Fired by launchd
# com.matsumototakeshi.viraltech-canary-resume on 2026-10-22: one canary run first (its Telegram DM
# reports the verdict and writes a fresh state), then lift the hold, re-arm the hourly canary, and
# remove this job. If the canary run fails, the hold stays and reviews keep using lane 2.
LOG="$HOME/.local/state/review-lanes/viraltech-canary-resume.log"
CFG="$HOME/.config/review-lanes"
exec >>"$LOG" 2>&1
echo "== $(date -u +%FT%TZ) resume start"
/opt/homebrew/bin/python3 "$HOME/.claude/skills/codex/scripts/viraltech-nerf-canary.py"; rc=$?
if [[ $rc -ne 0 ]]; then
  echo "canary run crashed (rc=$rc) — hold kept, hourly canary NOT re-armed"; exit 1
fi
[[ -e "$CFG/viraltech-hold" ]] && mv "$CFG/viraltech-hold" "$CFG/viraltech-hold.lifted-$(date +%Y%m%d-%H%M%S)" && echo "hold lifted"
launchctl bootstrap "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.matsumototakeshi.viraltech-nerf-canary.plist" && echo "hourly canary re-armed"
launchctl list | grep viraltech-nerf-canary
mv "$HOME/Library/LaunchAgents/com.matsumototakeshi.viraltech-canary-resume.plist" \
   "$HOME/Library/LaunchAgents/.viraltech-canary-resume.plist.done-$(date +%Y%m%d)"
echo "== $(date -u +%FT%TZ) resume done"
launchctl bootout "gui/$(id -u)/com.matsumototakeshi.viraltech-canary-resume"
