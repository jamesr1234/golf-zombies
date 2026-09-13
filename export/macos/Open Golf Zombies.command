#!/bin/bash
cd "$(dirname "$0")"
xattr -dr com.apple.quarantine "Golf Zombies.app" 2>/dev/null || true
xattr -cr "Golf Zombies.app" 2>/dev/null || true
open "Golf Zombies.app"
