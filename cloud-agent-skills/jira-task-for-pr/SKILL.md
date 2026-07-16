---
name: jira-task-for-pr
description: "Always create and manage a Jira task whenever a pull request is created. Use this skill every time you are about to create a PR, open a PR, push a branch that will become a PR, or finish work on a PR. Creates the Jira task in PT9 for backend work (or a user-specified project), links related epics, assigns the task to the requesting user, moves it to In Progress while working and In Review when the PR is ready."
---

# Jira Task for Every PR

## When to Use

**MANDATORY:** Apply this skill every time you create a pull request. No PR should exist without a corresponding Jira task. Also apply it at the end of the task, when the PR is finished, to transition the Jira issue.

## Jira Site

All operations use the `1inch.atlassian.net` Jira site (pass it as `cloudId` to Atlassian MCP tools; if that fails, resolve the cloudId via `getAccessibleAtlassianResources`).

## Project Selection

1. **If the user explicitly specified a Jira project or space** (in the task description, a linked issue, or conversation) — use that project. An explicit instruction always wins.
2. **If the work is backend** (services, APIs, smart-contract backends, infrastructure, databases, workers, anything server-side) — use project **PT9** ("Product Team 9 (Backend)").
3. **Otherwise** — try to infer the correct project from context (repository name, team conventions, similar recent issues found via JQL). If nothing can be inferred confidently, fall back to **PT9** and mention this in your summary so the user can correct it.

## Workflow

### Step 1: Create the Jira task (before or right after opening the PR)

1. Determine the requesting user's Jira account:
   - Call `atlassianUserInfo` to get the current user's `accountId`. This is the user the task must be assigned to.
2. Search for a related Epic to link to:
   - Run 1–3 JQL searches for open Epics in the target project matching the feature area, e.g.:
     `searchJiraIssuesUsingJql(cloudId="1inch.atlassian.net", jql='project = PT9 AND issuetype = Epic AND statusCategory != Done AND (summary ~ "<feature keywords>" OR text ~ "<feature keywords>") ORDER BY updated DESC', fields=["summary","status"], maxResults=10)`
   - Pick the Epic whose scope clearly matches the PR's work. If no Epic clearly matches, create the task without a parent and note that in your summary. Do NOT guess a wrong Epic.
3. Create the task:
   - `createJiraIssue` with:
     - `projectKey`: the project chosen above
     - `issueTypeName`: `"Task"` (use `"Bug"` if the PR is a pure bug fix)
     - `summary`: concise description of the change, matching the PR title's meaning
     - `description`: what is being changed and why, plus a link to the PR (add the PR link with `editJiraIssue` or a comment after the PR exists if you create the issue first)
     - assignee: the current user's `accountId` (via `additional_fields`: `{"assignee": {"accountId": "<accountId>"}}`)
     - Epic link/parent: the Epic found in step 2, if any
   - If assignee or Epic link cannot be set at creation time (field not on the create screen), set them right after with `editJiraIssue`.

### Step 2: Move to In Progress (default status while working)

- Get available transitions with `getTransitionsForJiraIssue`, find the transition to **In Progress** (match case-insensitively), and apply it with `transitionJiraIssue`.
- Do this immediately after creating the issue.

### Step 3: Reference the ticket everywhere

- Put the issue key in the PR title scope, e.g. `feat(PT9-123): ...` (see the `1inch-pr-template` skill).
- Include a link to the Jira issue (`https://1inch.atlassian.net/browse/<KEY>`) in the PR description.
- Add a comment or remote link on the Jira issue pointing to the PR URL.

### Step 4: Move to In Review when finished

- When the PR is pushed and ready (end of the task, PR opened/updated for review), transition the issue to **In Review** using `getTransitionsForJiraIssue` + `transitionJiraIssue`.
- If a transition named exactly "In Review" does not exist, use the closest equivalent (e.g. "Code Review", "Review"). If no review-like transition exists, leave it In Progress and mention this in your summary.

## Rules

- One Jira task per PR. If the user already provided an existing ticket for this work, do NOT create a duplicate — use the provided ticket, assign it to the user if unassigned, and follow the same status transitions.
- Always assign the task to the requesting user (from `atlassianUserInfo`), never leave it unassigned and never assign to someone else unless explicitly told to.
- Always report in your final summary: issue key with URL, project used, Epic linked (or "none found"), and final status.
