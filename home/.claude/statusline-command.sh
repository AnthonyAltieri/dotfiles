#!/bin/bash

# Read JSON input
input=$(cat)

# Extract values
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name')
remaining=$(echo "$input" | jq -r '.context_window.remaining_percentage // empty')

# Git branch
git_branch=""
if git -C "$cwd" rev-parse --git-dir > /dev/null 2>&1; then
    git_branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null || echo "")
    if [ -n "$git_branch" ]; then
        git_branch=" on $git_branch"
    fi
fi

# Directory (just basename)
dir=$(basename "$cwd")

# Context percentage
context=""
if [ -n "$remaining" ]; then
    context=" [ctx: ${remaining}%]"
fi

# Build output
printf "%s%s in %s%s" "$model" "$context" "$dir" "$git_branch"
