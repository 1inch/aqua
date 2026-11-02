// Action entry point: runs the dependency-audit fix agent through the Cursor Agent SDK.
//
// Why the SDK instead of the Cursor CLI: the SDK creates a real cloud agent, so the run is
// attributable. `cloud.metadata` tags the agent for its whole lifetime, and every usage and
// billing export carries `cloud_agent_id`. That is what lets spend be reported per repository and
// per use case instead of as one undifferentiated Cursor invoice line.
//
// The fix work is delegated to a named subagent pinned to DeepSeek Flash: the scan already says
// which package, which version and which lockfile, so the loop is mechanical and a large frontier
// model buys nothing.
//
// The scan runs on the GitHub runner while the agent runs in its own VM, so the findings arrive as
// action inputs and are forwarded as env vars, and the verdict comes back in the agent's final
// message. Nothing is shared through the filesystem.

import { appendFileSync, writeFileSync } from "node:fs";
import { mkdtemp } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join, sep } from "node:path";
import { pathToFileURL } from "node:url";
import { spawnSync } from "node:child_process";

/**
 * Title of the single fix pull request. A plain description, not a conventional commit with a
 * ticket scope: this runs on a weekday schedule, so there is no ticket to reference.
 */
const PR_TITLE = "Resolve critical and high dependency vulnerabilities";

/**
 * Pinned SDK version. The SDK ships a ~16 MB arch-specific native package alongside ~21 MB of JS,
 * so it cannot be vendored into a repository (and vendoring would pin one architecture, while the
 * org runs both amd64 and arm64 pools). It is installed at run time instead.
 */
const CURSOR_SDK_VERSION = "1.2.0";

/** Model the fix subagent runs on. Fixed here; the workflow does not let callers override it. */
const FIX_MODEL_ID = "deepseek-v4.1-flash-1017";

/**
 * Cloud env vars are encrypted and injected per session; keeping the findings payload under this
 * cap leaves room for the rest of the environment and fails loudly if a repository has an absurd
 * number of findings rather than truncating silently.
 */
const MAX_FINDINGS_BYTES = 60 * 1024;

/**
 * Installs the pinned SDK into a throwaway directory and imports it from there.
 *
 * Installing into the action's own directory would dirty the checkout, and this action is copied
 * verbatim into repositories that cannot reference a private action — so it must not depend on
 * anything outside its own file. `createRequire` resolves the real entry point, which is imported by
 * URL rather than by bare specifier, because a bare specifier would be resolved from this file's
 * directory where no `node_modules` exists.
 */
async function loadAgentSdk() {
  const dir = await mkdtemp(join(tmpdir(), "dependency-audit-sdk-"));
  writeFileSync(join(dir, "package.json"), '{"name":"dependency-audit-sdk","private":true}\n');

  const install = spawnSync(
    "npm",
    ["install", "--no-audit", "--no-fund", "--omit=dev", "--loglevel=error", `@cursor/sdk@${CURSOR_SDK_VERSION}`],
    { cwd: dir, encoding: "utf8" }
  );
  if (install.status !== 0) {
    throw new Error(`could not install @cursor/sdk@${CURSOR_SDK_VERSION}: ${install.stderr || install.stdout}`);
  }

  // `require.resolve` returns the CJS entry, whose only export is `default`. The package's `import`
  // condition points at the ESM build, which is what exposes the named exports.
  const resolved = createRequire(join(dir, "resolve.cjs")).resolve("@cursor/sdk");
  const esm = resolved.replace(`${sep}dist${sep}cjs${sep}`, `${sep}dist${sep}esm${sep}`);
  let sdk = await import(pathToFileURL(esm).href);
  if (typeof sdk.Agent?.create !== "function" && esm !== resolved) {
    // Fall back to whatever `resolve` returned, in case the layout changes.
    sdk = await import(pathToFileURL(resolved).href);
  }
  if (typeof sdk.Agent?.create !== "function") {
    throw new Error(`@cursor/sdk did not export Agent.create (resolved ${resolved})`);
  }
  return sdk.Agent;
}

/**
 * Reads an action input. Inputs arrive in `INPUT_<NAME>` with the dashes turned into underscores,
 * and GitHub does not strip surrounding whitespace.
 */
function input(name, { required = false, fallback = "" } = {}) {
  const key = `INPUT_${name.replace(/-/g, "_").toUpperCase()}`;
  const value = (process.env[key] ?? "").trim();
  if (value === "" && required) {
    throw new Error(`input ${name} is required but empty`);
  }
  return value === "" ? fallback : value;
}

/** Writes a step output through the command file, which handles multi-line values. */
function setOutput(name, value) {
  const file = process.env.GITHUB_OUTPUT;
  if (!file) {
    return;
  }
  const text = String(value);
  if (text.includes("\n")) {
    const delimiter = `EOF_${name.toUpperCase()}_${Date.now()}`;
    appendFileSync(file, `${name}<<${delimiter}\n${text}\n${delimiter}\n`);
  } else {
    appendFileSync(file, `${name}=${text}\n`);
  }
}

function setSummaryError(message) {
  if (process.env.GITHUB_STEP_SUMMARY) {
    appendFileSync(process.env.GITHUB_STEP_SUMMARY, `\n> [!WARNING]\n> ${message}\n`);
  }
}

/**
 * Tags persisted on the cloud agent. Keys are short and stable on purpose: they are joined against
 * Cursor usage and billing exports by `cloud_agent_id`, so renaming one silently orphans the
 * history already collected. Cursor caps metadata at 20 keys.
 */
function agentMetadata(cfg) {
  return {
    repository: cfg.repository,
    usecase: "dependency-update",
    workflow: "dependency-audit",
    base_branch: cfg.baseBranch,
    fix_branch: cfg.fixBranch,
    runner: cfg.runnerLabel,
    run_id: process.env.GITHUB_RUN_ID || "local",
    run_attempt: process.env.GITHUB_RUN_ATTEMPT || "1",
    server_url: process.env.GITHUB_SERVER_URL || "https://github.com"
  };
}

/** Parses a JSON-array input, keeping only strings. An unreadable value is not fatal. */
function parseArrayInput(value) {
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed.filter((entry) => typeof entry === "string") : [];
  } catch {
    return [];
  }
}

/**
 * The prompt is one string and the agent starts with no shell history, so everything it needs is
 * spelled out. Findings arrive through env vars set on the agent's session.
 */
function buildPrompt(cfg) {
  return `You fix dependency vulnerabilities in a GitHub repository. You are running as a cloud agent started by a GitHub Actions job that has already scanned the default branch.

The repository is cloned for you and your commits are attributed to the Cursor GitHub App, which can push them and open the pull request. \`gh\` in this VM is authenticated the same way. If \`git push\` is rejected, the App is missing access to this repository: say so in your final answer and stop, do not look for another credential.

# Context
- Repository: \`${cfg.repository}\`
- Default branch: \`${cfg.baseBranch}\`
- Fix branch: \`${cfg.fixBranch}\`
- CRITICAL and HIGH findings, each with a fixed version: the JSON array in \`$FINDINGS_CRITICAL_HIGH\`
- MEDIUM and LOW findings, to list only: the JSON array in \`$FINDINGS_MEDIUM_LOW\`
- Advisory ids the repository already accepts: the JSON array in \`$ACCEPTED_ADVISORIES\`
- Toolchains detected in the repository: \`$TOOLCHAINS\`

Each finding has \`target\` (the lockfile path), \`pkg\`, \`installed\`, \`fixed\`, \`id\`, \`severity\` and \`vendorIds\`. Findings whose advisory id is in \`$ACCEPTED_ADVISORIES\` are already filtered out; do not re-derive them and do not re-fix them.

# Toolchains
Install only the toolchains named in \`$TOOLCHAINS\` before regenerating any lockfile, at the version the repository pins in \`.nvmrc\`, \`.node-version\`, \`package.json#engines\`, \`packageManager\`, \`go.mod\` or \`rust-toolchain.toml\`. The private \`@1inch\` npm registry needs a token: use \`$(gh auth token)\` as \`NODE_AUTH_TOKEN\`, never a literal.

# Security exceptions
If \`SECURITY_EXCEPTIONS.md\` exists in the repository root, read it first. Skip every package it lists as an accepted risk: do not fix it and do not count it as unresolved. Mention it in the pull request body as "excepted per SECURITY_EXCEPTIONS.md".

\`.trivyignore\` is already applied by the scan that produced these findings.

# How to fix each CRITICAL or HIGH finding
Work in the directory of the lockfile named in \`target\`. Use the first option that works:
1. Bump the direct dependency in that directory's manifest (\`package.json\`, \`go.mod\` or \`Cargo.toml\`) to a version that pulls in \`fixed\`.
2. Only when no parent bump reaches \`fixed\`: add an override (\`pnpm.overrides\`, npm \`overrides\`, Yarn \`resolutions\`, \`go get <module>@<version>\`, or \`cargo update -p <crate> --precise <version>\`) and explain why in the commit message and the pull request body.

Regenerate the lockfile with the tool that owns it, in the same directory:
- \`pnpm-lock.yaml\`: \`pnpm install --no-frozen-lockfile\`
- \`package-lock.json\`: \`npm install --package-lock-only\`
- \`yarn.lock\`: \`yarn install\`
- \`go.mod\`: \`go mod tidy\`
- \`Cargo.lock\`: \`cargo update -p <crate>\`

Every lockfile is independent: never fix a nested lockfile from the root manifest.

Verify each directory you touched. Trivy is not installed on this VM and the database is not downloaded, so install it, then scan once *without* \`--skip-db-update\` so the database is fetched:
\`curl -sSfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin\`
\`trivy fs --scanners vuln --pkg-types library --severity CRITICAL,HIGH --ignore-unfixed <directory>\`
Repeat until its CRITICAL and HIGH findings are gone or cannot be fixed, dropping \`--skip-db-update\` only after the first scan has populated the database.

# Scope
- Fix only the CRITICAL and HIGH findings you were given.
- Do not fix MEDIUM or LOW findings; list them in the pull request body.
- Do not change anything unrelated to these findings, and never edit files under \`.github/workflows/\`.
- Do not run \`pnpm audit\`, \`npm audit\` or \`yarn audit\`.

# Branch
1. If \`${cfg.fixBranch}\` exists on origin (\`git ls-remote --exit-code --heads origin "${cfg.fixBranch}"\`): fetch it, check it out and rebase it onto \`origin/${cfg.baseBranch}\`. Never delete or recreate it.
2. Otherwise create it from \`origin/${cfg.baseBranch}\`.
3. Commit with the message \`fix(deps): resolve critical and high dependency vulnerabilities\` and push with \`git push --force-with-lease origin "${cfg.fixBranch}"\`. Never use \`git push --force\`. This is a scheduled job with no Jira ticket, so the commit scope is \`deps\`.

# Pull request
This run opens the pull request for you from \`${cfg.fixBranch}\` into \`${cfg.baseBranch}\`, so do not call \`gh pr create\`. What is left to you is its description:

- If \`gh pr list --head "${cfg.fixBranch}" --base "${cfg.baseBranch}" --state open --json number --jq '.[0].number'\` returns a number, update that pull request's body with \`gh pr edit <number> --body-file <file>\`.
- Otherwise report the description in your final answer and the workflow will set it on the pull request this run opens.

The body must contain:
- A table with the columns Lockfile, Package, Installed, Fixed, Advisory, Severity, Fix applied.
- Whether every CRITICAL and HIGH finding is resolved, and the reason for each one that is not.
- The MEDIUM and LOW findings in a collapsed \`<details>\` list.

Keep exactly one open pull request from \`${cfg.fixBranch}\`: never open a second one, and never recreate the branch.

If nothing needs changing because every finding is excepted, do not push and do not open a pull request.

# Delegation
Do the mechanical bump-and-regenerate work through the \`dependency-fixer\` subagent, which runs on a fast, cheap model. Keep the planning, the verification, the commit, the push and the pull request body yourself.

# Result
End your final message with a single fenced \`json\` block holding exactly these keys:
- \`unresolvedCriticalHigh\`: boolean, true when any CRITICAL or HIGH finding that is not excepted remains.
- \`pullRequestBody\`: string, the markdown body for the pull request (empty when you did not push).
- \`summary\`: string, one or two sentences naming what you changed.
Do not put this block anywhere else and do not commit it to the repository.`;
}

/**
 * The fix subagent. DeepSeek Flash is ample for this loop and far cheaper than the account
 * default, while the parent agent keeps the default model so the plan, the verification and the
 * pull request body stay coherent.
 */
function subagents() {
  return {
    "dependency-fixer": {
      description:
        "Fixes CRITICAL and HIGH dependency findings: bumps the parent dependency or adds an override, regenerates the owning lockfile, and verifies with a re-scan.",
      model: { id: FIX_MODEL_ID },
      prompt: `You fix dependency vulnerabilities in a checked-out repository. You are a subagent: the parent agent has already established the scope, the findings and the branch, and will handle the commit, the push and the pull request.

For every CRITICAL or HIGH finding you are given:
1. Work in the directory that owns the vulnerable lockfile. Every lockfile is independent, so never fix a nested lockfile from the root manifest.
2. Prefer bumping the direct dependency in that directory's manifest. Add an override (\`pnpm.overrides\`, npm \`overrides\`, Yarn \`resolutions\`, \`go get <module>@<version>\`, \`cargo update -p <crate> --precise <version>\`) only when no parent bump reaches the fixed version, and say why when you do.
3. Regenerate the lockfile with the tool that owns it: \`pnpm install --no-frozen-lockfile\`, \`npm install --package-lock-only\`, \`yarn install\`, \`go mod tidy\`, or \`cargo update -p <crate>\`.
4. Re-scan that directory and repeat until its CRITICAL and HIGH findings are gone or cannot be fixed. The database is not on the VM, so the first scan must run without \`--skip-db-update\`.

Report back, per finding, the package, the installed version, the fixed version, the advisory id and what you did. Say plainly which findings you could not fix and why. Do not run \`pnpm audit\`, \`npm audit\` or \`yarn audit\`. Do not touch anything unrelated to these findings, and never edit files under \`.github/workflows/\`.`
    }
  };
}

/** Builds the job-summary markdown. Pure, so tests can assert on it without a network call. */
function buildReport({ repository, baseBranch, fixBranch, agentId, result, usage }) {
  const lines = [
    "### Dependency audit fix agent",
    "",
    "| Field | Value |",
    "| --- | --- |",
    `| Repository | \`${repository}\` |`,
    `| Branch | \`${fixBranch}\` |`,
    `| Base | \`${baseBranch}\` |`,
    `| Cloud agent | \`${agentId}\` |`,
    `| Fix subagent model | \`${FIX_MODEL_ID}\` |`,
    `| Status | ${result.status} |`
  ];

  if (typeof result.durationMs === "number") {
    lines.push(`| Duration | ${Math.round(result.durationMs / 1000)}s |`);
  }

  if (usage) {
    lines.push(
      `| Tokens | ${usage.inputTokens} in / ${usage.outputTokens} out / ${usage.cacheReadTokens} cache read |`
    );
  }

  if (result.git?.branches?.length) {
    const branches = result.git.branches
      .map((entry) => (entry.prUrl ? `${entry.branch} (${entry.prUrl})` : entry.branch))
      .filter(Boolean)
      .join(", ");
    if (branches) {
      lines.push(`| Git | ${branches} |`);
    }
  }

  lines.push(
    "",
    `The tags on cloud agent \`${agentId}\` are what let usage and billing exports be joined to the repository and the use case.`
  );
  return lines.join("\n");
}

/**
 * Pulls the verdict out of the agent's final message: the last fenced json block, or the last JSON
 * object if the model ignored the fence.
 */
function parseVerdict(text) {
  if (typeof text !== "string" || text.trim() === "") {
    return undefined;
  }

  const blocks = [...text.matchAll(/```json\s*([\s\S]*?)```/gi)].map((match) => match[1]);
  for (const candidate of [...blocks.reverse(), text]) {
    const start = candidate.indexOf("{");
    const end = candidate.lastIndexOf("}");
    if (start === -1 || end <= start) {
      continue;
    }
    try {
      const parsed = JSON.parse(candidate.slice(start, end + 1));
      if (parsed && typeof parsed === "object" && "unresolvedCriticalHigh" in parsed) {
        return {
          unresolvedCriticalHigh: parsed.unresolvedCriticalHigh !== false,
          // Some runs report the URL explicitly; otherwise the run's git info supplies it.
          pullRequestUrl: typeof parsed.pullRequestUrl === "string" ? parsed.pullRequestUrl : "",
          pullRequestBody: typeof parsed.pullRequestBody === "string" ? parsed.pullRequestBody : "",
          summary: typeof parsed.summary === "string" ? parsed.summary : ""
        };
      }
    } catch {
      // A fenced block that is not the verdict is not fatal; try the next candidate.
    }
  }
  return undefined;
}

/**
 * Turns a finished run into an outcome. A run that did not finish, or whose message holds no
 * verdict, counts as unresolved: reporting green there would hide findings nobody judged.
 */
function collectResult({ status, error, text, git }) {
  const gitPullRequest =
    git?.branches?.find((branch) => typeof branch.prUrl === "string" && branch.prUrl !== "")?.prUrl ?? "";

  if (status !== "finished") {
    return {
      unresolvedCriticalHigh: true,
      pullRequestUrl: gitPullRequest,
      pullRequestBody: "",
      summary: `agent run ended with status ${status}${error?.message ? `: ${error.message}` : ""}`
    };
  }

  const verdict = parseVerdict(text);
  if (!verdict) {
    return {
      unresolvedCriticalHigh: true,
      pullRequestUrl: gitPullRequest,
      pullRequestBody: "",
      summary: "agent finished without a readable verdict in its final message"
    };
  }

  return { ...verdict, pullRequestUrl: verdict.pullRequestUrl || gitPullRequest };
}

/**
 * Sets the title and body on the pull request this run opened. Best effort and never fatal: the fix
 * is already pushed and the pull request already open, so a title or body that could not be set is
 * a cosmetic miss, not a failed audit.
 *
 * The body is set only on a newly opened pull request: an existing one carries the agent's
 * accumulated description.
 */
async function applyPullRequestDetails({ repository, pullRequestUrl, existedBefore, token, requestBody }) {
  if (!pullRequestUrl || !token) {
    return;
  }

  const number = pullRequestUrl.match(/\/pull\/(\d+)$/)?.[1];
  if (!number) {
    return;
  }

  const payload = { title: PR_TITLE };
  if (!existedBefore && requestBody) {
    payload.body = requestBody;
  }

  const response = await fetch(`https://api.github.com/repos/${repository}/pulls/${number}`, {
    method: "PATCH",
    headers: {
      authorization: `Bearer ${token}`,
      accept: "application/vnd.github+json",
      "content-type": "application/json",
      "user-agent": "dependency-audit"
    },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    process.stdout.write(`could not set the pull request details: HTTP ${response.status}\n`);
  }
}

async function main() {
  const cfg = {
    apiKey: input("cursor-api-key", { required: true }),
    repository: input("repository", { required: true }),
    repositoryUrl: input("repository-url", { required: true }),
    baseBranch: input("base-branch", { required: true }),
    fixBranch: input("fix-branch", { required: true }),
    toolchains: input("toolchains", { fallback: "unknown" }),
    runnerLabel: input("runner-label", { fallback: "unknown" }),
    githubToken: input("github-token"),
    prExistedBefore: input("pull-request-existed-before", { fallback: "false" }) === "true"
  };

  const findings = {
    FINDINGS_CRITICAL_HIGH: input("findings-critical-high", { required: true }),
    FINDINGS_MEDIUM_LOW: input("findings-medium-low", { required: true }),
    ACCEPTED_ADVISORIES: input("accepted-advisories", { fallback: "[]" })
  };

  for (const [key, value] of Object.entries(findings)) {
    const bytes = Buffer.byteLength(value, "utf8");
    if (bytes > MAX_FINDINGS_BYTES) {
      throw new Error(
        `${key} is ${bytes} bytes, above the ${MAX_FINDINGS_BYTES}-byte action input cap; ` +
          "split the scan per lockfile before running the agent"
      );
    }
  }

  // Fail before spending anything on a malformed findings payload.
  parseArrayInput(findings.FINDINGS_CRITICAL_HIGH);

  const Agent = await loadAgentSdk();

  const agent = await Agent.create({
    apiKey: cfg.apiKey,
    name: `${cfg.repository} dependency audit`,
    cloud: {
      repos: [{ url: cfg.repositoryUrl, startingRef: cfg.baseBranch }],
      // The Cursor GitHub App owns the clone, the push and the pull request, so nothing here needs
      // a repository-write token. Letting the SDK open the PR is what keeps it to one: `gh pr
      // create` cannot see that a PR from the branch already exists when the head is identical.
      autoCreatePR: true,
      openAsCursorGithubApp: true,
      skipReviewerRequest: true,
      metadata: agentMetadata(cfg),
      envVars: {
        TOOLCHAINS: cfg.toolchains,
        ...findings
      }
    },
    agents: subagents()
  });

  // `Agent.create()` resolves before the VM is provisioned, so surface the id immediately: a run
  // that dies during provisioning is otherwise untraceable from the job log.
  process.stdout.write(`cloud agent ${agent.agentId} created for ${cfg.repository}\n`);
  setOutput("agent-id", agent.agentId);

  try {
    const run = await agent.send(buildPrompt(cfg));
    const result = await run.wait();

    let usage = result.usage;
    if (!usage) {
      try {
        usage = (await agent.getUsage()).usage;
      } catch (usageError) {
        process.stdout.write(`agent usage unavailable: ${usageError.message}\n`);
      }
    }

    const collected = collectResult({
      status: result.status,
      error: result.error,
      text: result.result,
      git: result.git
    });

    await applyPullRequestDetails({
      repository: cfg.repository,
      pullRequestUrl: collected.pullRequestUrl,
      existedBefore: cfg.prExistedBefore,
      token: cfg.githubToken,
      requestBody: collected.pullRequestBody
    });

    setOutput("unresolved-critical-high", collected.unresolvedCriticalHigh);
    setOutput("pull-request-url", collected.pullRequestUrl);
    setOutput("agent-status", result.status);

    if (process.env.GITHUB_STEP_SUMMARY) {
      appendFileSync(
        process.env.GITHUB_STEP_SUMMARY,
        `${buildReport({
          repository: cfg.repository,
          baseBranch: cfg.baseBranch,
          fixBranch: cfg.fixBranch,
          agentId: agent.agentId,
          result,
          usage
        })}\n`
      );
    }

    if (collected.summary) {
      process.stdout.write(`${collected.summary}\n`);
    }
    if (result.status !== "finished") {
      setSummaryError(collected.summary);
    }
  } finally {
    agent.close();
  }
}

export {
  CURSOR_SDK_VERSION,
  FIX_MODEL_ID,
  MAX_FINDINGS_BYTES,
  PR_TITLE,
  agentMetadata,
  applyPullRequestDetails,
  buildPrompt,
  buildReport,
  collectResult,
  loadAgentSdk,
  parseArrayInput,
  parseVerdict,
  subagents
};

/**
 * Actions always run this file directly. The guard keeps the module importable by its own tests,
 * which is what lets the prompt, the verdict parser and the metadata tags be asserted without a
 * network call.
 */
if (process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url) {
  await main();
}
