---
name: conventional-commits
description: "Write all git commit messages using the Conventional Commits specification. Use this skill every time you create a git commit, in any repository: choose the right type (feat, fix, chore, refactor, etc.), an optional scope, and a concise imperative subject line."
---

# Conventional Commits

## When to Use

**MANDATORY:** Apply this skill for every `git commit` you create.

## Format

```
<type>(<optional scope>): <description>

[optional body]

[optional footer(s)]
```

## Types

| Type | Use for |
| --- | --- |
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation-only changes |
| `style` | Formatting, whitespace, missing semicolons (no code behavior change) |
| `refactor` | Code change that neither fixes a bug nor adds a feature |
| `perf` | Performance improvement |
| `test` | Adding or correcting tests |
| `build` | Build system or external dependency changes |
| `ci` | CI configuration and scripts |
| `chore` | Other maintenance that doesn't modify src or test files |
| `revert` | Reverting a previous commit |

## Rules

- Subject line: imperative mood ("add", not "added"/"adds"), lowercase after the colon, no trailing period, ideally ≤ 72 characters.
- Scope is optional; use it for the affected module/area (e.g. `feat(orders): ...`). If a Jira ticket is associated with the work, the ticket key may be used as the scope, consistent with the PR title convention.
- Breaking changes: append `!` after the type/scope (`feat(api)!: ...`) and/or add a `BREAKING CHANGE:` footer describing the break.
- Body (optional): explain the what and why, not the how. Separate from the subject with a blank line.
- One logical change per commit; each commit message must accurately describe its own change.

## Examples

```
feat(orders): add partial fill support for limit orders

fix(quotes): prevent division by zero when reserves are empty

chore: update yarn lockfile after dependency bump

refactor(PT9-321)!: replace legacy resolver interface

BREAKING CHANGE: IResolver.resolve() now returns a struct instead of a tuple.
```
