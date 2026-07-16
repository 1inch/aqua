---
name: 1inch-pr-template
description: "Format every pull request according to 1inch organization standards. Use this skill every time you create or update a pull request: fetch the latest PR template from the 1inch/.github repository for the PR body, include a link to the related Jira ticket, and write the PR title in Conventional Commits format with the Jira ticket key in parentheses in the scope."
---

# 1inch PR Template and Title Format

## When to Use

**MANDATORY:** Apply this skill every time you create or update a pull request in any 1inch repository.

## PR Body: Always Use the Org Template from `1inch/.github`

The canonical PR template lives in the `1inch/.github` repository and **can change over time — always fetch the current version, never rely on a cached or memorized copy.**

1. Fetch the latest template:

```bash
gh api repos/1inch/.github/contents/pull_request_template.md --jq '.content' | base64 -d
```

   If that file is not found, list the repo to locate it (it may move, e.g. into `.github/PULL_REQUEST_TEMPLATE/`):

```bash
gh api repos/1inch/.github/contents/ --jq '.[].path'
```

2. Fill in **every section** of the template:
   - **Change Summary** — 1–2 sentences describing what the PR changes.
   - **Related Issue/Ticket** — REQUIRED: the Jira ticket key as a markdown link to Jira, e.g. `[PT9-123](https://1inch.atlassian.net/browse/PT9-123)`. The ticket comes from the `jira-task-for-pr` skill (or from a ticket the user provided). Never leave this section empty or as a bare key without the link.
   - **Testing & Verification** — check the boxes that apply and describe how the change was tested.
   - **Risk Assessment** — check exactly one risk level and describe risks/impact honestly.
3. If the repository itself has its own PR template, the org template from `1inch/.github` still takes precedence per this policy — use the org template.

## PR Title: Conventional Commits with Ticket in Parentheses

The PR title MUST follow Conventional Commits, with the Jira ticket key in parentheses as the scope:

```
<type>(<TICKET-KEY>): <short imperative description>
```

Examples:

- `feat(PT9-123): add limit order cancellation endpoint`
- `fix(PT9-456): handle zero-amount swaps in quote calculation`
- `chore(PT9-789): bump foundry and prettier versions`

Rules:

- `type` is one of: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `build`, `ci`, `style`, `revert`.
- The scope in parentheses is the Jira ticket key (e.g. `PT9-123`), uppercase, exactly as in Jira.
- Description is lowercase, imperative mood, no trailing period.
- Use `!` before the colon for breaking changes, e.g. `feat(PT9-123)!: ...`.
