---
name: draft-pr
description: Commit current work, push it, open a draft PR, and request a Copilot review. Manually invoked only via /draft-pr.
disable-model-invocation: true
---

# Draft PR

Manually invoked (`/draft-pr`). Take the work done so far from a feature branch to a
draft PR with a Copilot review requested.

## Steps

1. **Confirm you're on a feature branch, not the default branch.** Run `git branch --show-current`
   and check it against the repo's default branch (don't assume `main` — could be `develop`/`master`).
   If you're on the default branch, STOP and ask before continuing.
2. **Commit what's been done so far.** Stage and commit with a conventional-commits message.
   Run the repo's tests/lints/typechecks/formatters first (see the global CLAUDE.md rule).
3. **Push to origin** (`git push -u origin <branch>`).
4. **Create the draft PR** against the correct base branch (`gh pr create --draft`). See title/body guidance below.
5. **Request a Copilot review** using the exact command below.
6. **Verify the request landed** by re-querying the PR (see below). Report the PR URL to the user.

## Requesting a Copilot review — the ONE way that works

Request Copilot via the REST `requested_reviewers` endpoint with the bot's login
`copilot-pull-request-reviewer[bot]`:

```bash
gh api --method POST \
  repos/dequelabs/<repo>/pulls/<pr-number>/requested_reviewers \
  -f "reviewers[]=copilot-pull-request-reviewer[bot]"
```

Then verify it actually attached (the endpoint can accept a request without running Copilot):

```bash
gh api repos/dequelabs/<repo>/pulls/<pr-number> --jq '.requested_reviewers[].login'
```

The output must include `Copilot`. If it doesn't, the request did not land — do not report success.

DO NOT use `gh pr edit --add-reviewer @copilot`. It **silently no-ops** for the Copilot bot.

## PR title

Conventional-commits style, **unless repo-level guidance explicitly says otherwise**:
`type(scope): summary` (e.g. `fix(auth): reject expired refresh tokens`).

- **Scope in a monorepo:** a comma-separated list of the impacted package directory names
  (e.g. `feat(axe-devtools): ...` or `chore(server,client): ...`). For a repo-wide change,
  omit the scope: `chore: ...`.
- **Single-package repo:** scope is optional; use it if it adds clarity.

## PR description

Start the body with an issue reference on its own line (if repo-specific guidance says to put it at the end instead instead, do that):

- `Ref: #132` or `Ref: dequelabs/<repo>#123` — related to an issue but does **not** close it.
- `Closes: #123` — this PR **completely** closes the issue.

Then, in order:

1. **Problem** — what problem this PR solves.
2. **Impact** — what changes for users/systems as a result.
3. **Acceptance criteria** — Enumerate what QA should verify to be confident the fix solves the problem and has its intended impact. Rules:
  - If the closed/ref'd issue already lists acceptance criteria, don't repeat them — write `See #123`.
  - QA is only responsible for **user-facing** changes. If the PR isn't meant to affect anything user-facing (typical for `chore:` and most refactors), write `No user-facing changes`.
4. **Local testing** — A section noting what you already verified locally to confirm the fix works. **Omit anything CI runs anyway** — no "ran unit tests", "ran lint", "typechecked". Include only manual/external verification CI can't do (e.g. "exercised the flow against a local DB", "checked the rendered page in a browser"). If there's nothing beyond what CI covers, omit the section.
5. **Summary of changes** — *concise*. Describe the approach, not the line-by-line
   implementation (that's better understood by reading the diff). Avoid repeating details
   the code already makes clear.

## Example PR body

```
Closes: #4521

### Problem
Downgrading a plan showed an untranslated toast in non-English locales.

### Impact
Users on de/es/fr/it/ja now see the downgrade confirmation in their language.

### Acceptance Criteria
See #4521

### Summary of changes
Split the single `<Trans>` that spanned an inline conditional into two, so each
half produces a stable, translatable key.

### Local testing
Switched the app to German and confirmed the downgrade toast renders translated.
```
