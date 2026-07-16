# Default Skills for Cursor Cloud Agents

Three user-level skills that apply to all repositories (not repo-specific):

| Skill | Purpose |
| --- | --- |
| `jira-task-for-pr` | Create a Jira task for every PR (PT9 for backend by default), link related epics, assign to you, In Progress → In Review |
| `1inch-pr-template` | Always use the latest PR template from `1inch/.github`, link the Jira ticket, conventional-commits PR title with ticket in `()` |
| `conventional-commits` | All commit messages follow the Conventional Commits spec |

## Installation as default skills

Cursor discovers user-level skills from `~/.cursor/skills/<skill-name>/SKILL.md` (see [cursor.com/docs/skills](https://cursor.com/docs/skills)). Cloud Agents run on fresh VMs, so the skills must be provisioned into the VM's home directory via your **personal (or team) saved cloud-agent environment** — that's what makes them apply by default across all repos.

Add this to your cloud-agent environment install/start script (or Dockerfile), replacing the copy source with wherever you host these files (e.g. a small git repo or gist):

```bash
mkdir -p ~/.cursor/skills
cp -r /path/to/cloud-agent-skills/jira-task-for-pr ~/.cursor/skills/
cp -r /path/to/cloud-agent-skills/1inch-pr-template ~/.cursor/skills/
cp -r /path/to/cloud-agent-skills/conventional-commits ~/.cursor/skills/
```

For local Cursor (IDE/CLI), simply copy the three folders into `~/.cursor/skills/` on your machine.

Notes:

- The `jira-task-for-pr` skill requires the Atlassian MCP server to be available to the agent (it already is in this environment).
- The `1inch-pr-template` skill requires `gh` CLI read access to `1inch/.github` (available to Cloud Agents by default).
