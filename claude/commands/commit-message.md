---
description: Write a concise Conventional Commits message for the current changes (never commits)
allowed-tools: Bash(git status:*), Bash(git diff:*)
---

## Changes

- Status: !`git status --short`
- Staged diff: !`git diff --cached`
- All uncommitted changes: !`git diff HEAD`
- Extra summary from the user (may be empty): $ARGUMENTS

If the staged diff is non-empty, describe only the staged changes; otherwise describe all uncommitted changes.

## Task

Act as an expert Git Commit Generator. Analyze the provided git diff or summary of changes and output a super concise commit message following the Conventional Commits specification.

Rules:
1. Output ONLY the raw commit text. Do not include markdown code blocks, intro text (e.g., "Here is your commit"), or explanations.
2. Title format: <type>(<scope>): <short description in imperative mood, max 50 chars, lowercase, no period>.
3. Body format (optional): Separate from title by a blank line. Use short bullet points (max 72 chars per line) only if the change is complex. Omit body for simple changes.
4. Allowed Types: feat, fix, docs, style, refactor, test, chore.
5. I will manually commit it. Never run git commit, git add or any other git command that changes the repository.
