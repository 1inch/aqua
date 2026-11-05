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
// action inputs and are inlined in the prompt. A session env value is capped at 4096 bytes, which
// a weekday findings list exceeds. The verdict comes back in the agent's final message. Nothing
// is shared through the filesystem.

import { appendFileSync, copyFileSync } from "node:fs";
import { mkdtemp } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { dirname, join, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
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

/**
 * Model the fix subagent runs on. Fixed here; the workflow does not let callers override it.
 *
 * This is the id `GET /v1/models` returns for DeepSeek V4.1 Flash 1017. The IDE picker label
 * (`deepseek-v4.1-flash-1017`) and the docs slug (`deepseek-v4-1-flash-1017`) are both rejected
 * by POST /v1/agents.
 */
const FIX_MODEL_ID = "deepseek-v41-flash-1017";

/**
 * Action-input cap for one findings list. GitHub collapses a step output near this size, and a
 * prompt that embeds more than this is no longer a reviewable fix. Fail instead of truncating.
 */
const MAX_FINDINGS_BYTES = 60 * 1024;
// POST /v1/agents rejects an env var value above this. A weekday medium/low list is larger, so
// findings travel in the prompt and only short values (the token, the toolchain names, the
// lifecycle guard) go in the session env.
const ENV_VAR_VALUE_MAX_BYTES = 4096;

/**
 * Session-level switch that stops every package manager running lifecycle scripts.
 *
 * The prompts pass `--ignore-scripts` to every install, but a prompt is not a control: a model that
 * forgets the flag, or follows an injected instruction to drop it, executes a third-party
 * `postinstall` in the VM that holds the App's push identity and the forwarded package token.
 * These variables are set on the session before any model-controlled shell runs, and cover npm,
 * pnpm and Yarn (both classic and Berry). Verified: a `postinstall` that runs by default does not
 * run once `npm_config_ignore_scripts=true` is set.
 */
const LIFECYCLE_SCRIPT_GUARD = {
  // Measured against a package whose postinstall writes a file, on the versions this org's images
  // carry (npm 10, pnpm 10.12.1, yarn 1.22.22):
  //
  //   npm    runs by default, blocked by npm_config_ignore_scripts
  //   pnpm   runs by default, blocked by npm_config_ignore_scripts — and *not* by
  //          pnpm_config_ignore_scripts, which pnpm 10.12.1 resolves to undefined
  //   yarn 1 runs by default, blocked by YARN_IGNORE_SCRIPTS; YARN_ENABLE_SCRIPTS is Berry-only
  //
  // Both pnpm names and both Yarn names are set anyway: they cost nothing, and a pnpm release that
  // changes precedence would otherwise leave the gap open.
  npm_config_ignore_scripts: "true",
  pnpm_config_ignore_scripts: "true",
  YARN_IGNORE_SCRIPTS: "true",
  YARN_ENABLE_SCRIPTS: "false"
};

/**
 * Installs the pinned SDK graph and imports it.
 *
 * Two properties matter here, both from a security review of the first version:
 *
 * 1. **Pinned by lockfile.** `sdk/package-lock.json` records integrity hashes for `@cursor/sdk`,
 *    every `@cursor/sdk-<platform>` package and the transitive `@connectrpc/*` / `zod` graph. A
 *    plain `npm install` only pinned the SDK's own version, so a new release inside
 *    `@connectrpc/connect@^1.6` could have run its install scripts. `npm ci` installs exactly that
 *    graph, and `--ignore-scripts` means nothing in it runs at install time.
 * 2. **No secrets in the child.** `spawnSync` inherits this process's environment by default, which
 *    here holds `CURSOR_API_KEY`, `GITHUB_TOKEN` and `NPM_TOKEN`. npm does not need any of them, so
 *    the child gets a minimal environment instead.
 *
 * Installing into the action's own directory would dirty the checkout, so it goes to a temp dir.
 * `createRequire` resolves the real entry point, imported by URL: a bare specifier would be
 * resolved from this file's directory, where no `node_modules` exists.
 */
async function loadAgentSdk() {
  const dir = await mkdtemp(join(tmpdir(), "dependency-audit-sdk-"));
  const sdkDir = join(dirname(fileURLToPath(import.meta.url)), "sdk");
  copyFileSync(join(sdkDir, "package.json"), join(dir, "package.json"));
  copyFileSync(join(sdkDir, "package-lock.json"), join(dir, "package-lock.json"));

  const install = spawnSync("npm", ["ci", "--ignore-scripts", "--no-audit", "--no-fund", "--loglevel=error"], {
    cwd: dir,
    encoding: "utf8",
    env: {
      PATH: process.env.PATH ?? "",
      HOME: process.env.HOME ?? dir,
      // Keep npm from reading a repository .npmrc or writing anything into the home cache layout.
      npm_config_userconfig: join(dir, ".npmrc"),
      npm_config_cache: join(dir, ".npm-cache")
    }
  });
  if (install.status !== 0) {
    throw new Error(`could not install the pinned @cursor/sdk graph: ${install.stderr || install.stdout}`);
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
 * Reads an action input. GitHub sets `INPUT_<NAME>` in uppercase and turns spaces into
 * underscores. Hyphens stay hyphens: `repository-url` is `INPUT_REPOSITORY-URL`, and looking it
 * up as `INPUT_REPOSITORY_URL` reads empty even though the workflow log shows the value.
 * GitHub does not strip surrounding whitespace.
 */
function input(name, { required = false, fallback = "" } = {}) {
  const key = `INPUT_${name.replace(/ /g, "_").toUpperCase()}`;
  const value = (process.env[key] ?? "").trim();
  if (value === "" && required) {
    throw new Error(`input ${name} is required but empty`);
  }
  return value === "" ? fallback : value;
}

/**
 * Reads a credential. A node24 action does not receive a secret passed through `with:` — the
 * workflow log still prints it as `***`, and `INPUT_*` is empty. The jobs that already use the
 * org `CURSOR_API_KEY` pass it with `env:`, which is the channel this process actually receives.
 * The input remains as a fallback for a runner that still copies inputs into the environment.
 */
function secretInput(envName, inputName) {
  const fromEnv = (process.env[envName] ?? "").trim();
  if (fromEnv !== "") {
    return fromEnv;
  }
  return input(inputName);
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
 * Session env for the cloud VM. Findings are deliberately absent: each value has to be non-empty
 * and at most {@link ENV_VAR_VALUE_MAX_BYTES} bytes or the create call returns 400, and the
 * medium/low list does not fit.
 */
function sessionEnvVars({ toolchains, npmToken }) {
  const envVars = {
    TOOLCHAINS: toolchains && toolchains.trim() !== "" ? toolchains : "unknown",
    ...LIFECYCLE_SCRIPT_GUARD,
    ...(npmToken ? { NPM_TOKEN: npmToken } : {})
  };

  for (const [key, value] of Object.entries(envVars)) {
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key) || key.startsWith("CURSOR_") || /cursor_sandbox/i.test(key)) {
      throw new Error(`env var name ${key} is rejected by the Cloud Agents API`);
    }
    const bytes = Buffer.byteLength(value, "utf8");
    if (value === "" || bytes > ENV_VAR_VALUE_MAX_BYTES) {
      throw new Error(
        `env var ${key} is ${bytes} bytes; the Cloud Agents API allows a non-empty value of at most ${ENV_VAR_VALUE_MAX_BYTES} bytes`
      );
    }
  }
  return envVars;
}

/** One log line. A thrown SDK error's stack is the whole minified bundle, and Actions drops it. */
function formatAgentError(error) {
  const message = error instanceof Error ? error.message : String(error);
  const status = error && typeof error === "object" && "status" in error ? error.status : "";
  const code = error && typeof error === "object" && "code" in error ? error.code : "";
  return `cloud agent send failed status=${status} code=${code} ${message.replace(/\s+/g, " ").slice(0, 1500)}`;
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
/**
 * Verified install instructions, shared by the parent prompt and the `dependency-fixer` subagent.
 *
 * A subagent starts from a clean context and does not inherit `buildPrompt`, so a rule that lives
 * only in the parent message never reaches the one agent that is told to re-scan and to run the
 * package managers — leaving it to reach for an unverified installer in the VM that holds the
 * App push identity. Both prompts therefore interpolate these same two strings.
 */
const TOOLCHAIN_RULE = `Install only the toolchains named in \`$TOOLCHAINS\` before regenerating any lockfile, at the version the repository pins in \`.nvmrc\`, \`.node-version\`, \`package.json#engines\`, \`packageManager\`, \`go.mod\` or \`rust-toolchain.toml\`.

**Verify every downloaded toolchain before running it.** Do not use \`nvm\`, \`asdf\`, \`rustup\`'s unverified path, or a vendor install script: those execute whatever the network returns in a VM that holds the App's push identity. Fetch the versioned archive and check it against the project's own published digest, failing closed:

\`\`\`bash
set -euo pipefail
# Node: the versioned archive plus its published manifest
V=22.23.4; ARCH=$(uname -m); [ "$ARCH" = x86_64 ] && A=x64 || A=arm64
curl -sSfO "https://nodejs.org/dist/v$V/node-v$V-linux-$A.tar.xz"
curl -sSfO "https://nodejs.org/dist/v$V/SHASUMS256.txt"
grep " node-v$V-linux-$A.tar.xz$" SHASUMS256.txt | sha256sum -c - || { echo "node checksum mismatch" >&2; exit 1; }

# Go: the versioned archive plus the official download manifest
GV=1.27.3; GA=$([ "$ARCH" = x86_64 ] && echo amd64 || echo arm64)
curl -sSfLO "https://go.dev/dl/go$GV.linux-$GA.tar.gz"   # -L: go.dev redirects to dl.google.com
curl -sSf -o go.json "https://go.dev/dl/?mode=json&include=all"
jq -r --arg f "go$GV.linux-$GA.tar.gz" '. | map(.files[]) | map(select(.filename == $f)) | .[0].sha256' go.json \
  | awk '{print $1"  go'"$GV"'.linux-'"$GA"'.tar.gz"}' | sha256sum -c - || { echo "go checksum mismatch" >&2; exit 1; }

# Rust: the versioned archive plus its own .sha256 sibling
RV=1.83.0; RA=$([ "$ARCH" = x86_64 ] && echo x86_64 || echo aarch64)
curl -sSfLO "https://static.rust-lang.org/dist/rust-$RV-$RA-unknown-linux-gnu.tar.xz"
curl -sSfLO "https://static.rust-lang.org/dist/rust-$RV-$RA-unknown-linux-gnu.tar.xz.sha256"
sha256sum -c "rust-$RV-$RA-unknown-linux-gnu.tar.xz.sha256" || { echo "rust checksum mismatch" >&2; exit 1; }
\`\`\`

Extract and put the resulting binaries on \`PATH\` only after the check passes. If a repository pins a version you cannot find a published digest for, say so in your final answer and stop rather than running an unverified installer. The private \`@1inch\` npm registry needs a token, and the Cursor GitHub App installation token cannot read GitHub Packages, so a package-read token is forwarded in the \`NPM_TOKEN\` environment variable.

**The token must never be written into the repository.** Everything in this clone is committed and pushed, and on a public repository that would publish a live credential.

Set this up once, and re-run the export in every shell you use — a bare \`bash -c '…'\` starts fresh and loses it:

\`\`\`bash
export NODE_AUTH_TOKEN="$NPM_TOKEN"
cat > "$HOME/.npmrc" <<'NPMRC'
//npm.pkg.github.com/:_authToken=\${NODE_AUTH_TOKEN}
@1inch:registry=https://npm.pkg.github.com
NPMRC
export npm_config_userconfig="$HOME/.npmrc"
\`\`\`

That file is outside the clone and is never committed. It holds an indirection, so it is safe to leave on disk: npm resolves the value from \`NODE_AUTH_TOKEN\` at install time. Do not create or edit a \`.npmrc\` inside the repository, and never expand \`$NPM_TOKEN\` into a file under the clone.

The token can only read packages. Always pass \`--ignore-scripts\` to every install, as listed below: a third-party lifecycle script must never get the chance to read it.

A lockfile for a private \`@1inch\` package legitimately contains \`npm.pkg.github.com\` in its \`resolved\` URLs, so that host on its own is expected and must not be removed. Before committing, check for a credential rather than for the host:
\`git diff --cached -U0 | grep -E '_authToken=[^$]|(ghp_|ghs_|github_pat_|crsr_)'\` and unstage anything it finds.

# Security exceptions
If \`SECURITY_EXCEPTIONS.md\` exists in the repository root, read it first. Skip every package it lists as an accepted risk: do not fix it and do not count it as unresolved. Mention it in the pull request body as "excepted per SECURITY_EXCEPTIONS.md".

\`.trivyignore\` is already applied by the scan that produced these findings.

# How to fix each CRITICAL or HIGH finding
Work in the directory of the lockfile named in \`target\`. Use the first option that works:
1. Bump the direct dependency in that directory's manifest (\`package.json\`, \`go.mod\` or \`Cargo.toml\`) to a version that pulls in \`fixed\`.
2. Only when no parent bump reaches \`fixed\`: add an override (\`pnpm.overrides\`, npm \`overrides\`, Yarn \`resolutions\`, \`go get <module>@<version>\`, or \`cargo update -p <crate> --precise <version>\`) and explain why in the commit message and the pull request body.

Regenerate the lockfile with the tool that owns it, in the same directory:
- \`pnpm-lock.yaml\`: \`pnpm install --no-frozen-lockfile --ignore-scripts\`
- \`package-lock.json\`: \`npm install --package-lock-only --ignore-scripts\`
- \`yarn.lock\`: \`yarn install --ignore-scripts\`
- \`go.mod\`: \`go mod tidy\`
- \`Cargo.lock\`: \`cargo update -p <crate>\`

Every lockfile is independent: never fix a nested lockfile from the root manifest.`;

const VERIFIED_TRIVY_INSTALL = `Verify each directory you touched. Trivy is not installed on this VM, so install the exact release the scan used — do not use the upstream install script, which is fetched from a moving branch:

\`\`\`bash
set -euo pipefail
case "$(uname -m)" in
  x86_64) ASSET="trivy_0.76.0_Linux-64bit.tar.gz"; SHA=e24b1c51293c1b15e4ba8d45bbc7891ba053f90278ec2698f3562c993e145fe7 ;;
  aarch64|arm64) ASSET="trivy_0.76.0_Linux-ARM64.tar.gz"; SHA=aab21e677a7b7071fc79f1711480840754c18a1b9d9cefa7ccd06af63a0e8f4c ;;
  *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
curl -sSfLo /tmp/trivy.tgz "https://github.com/aquasecurity/trivy/releases/download/v0.76.0/$ASSET"
echo "$SHA  /tmp/trivy.tgz" | sha256sum -c - || { echo "trivy checksum mismatch" >&2; exit 1; }
tar -xzf /tmp/trivy.tgz -C /usr/local/bin trivy
trivy --version
\`\`\`

The block fails closed on purpose: without \`set -euo pipefail\` and the explicit \`|| exit 1\`, a digest mismatch would fall through to \`tar\` and install whatever was downloaded, and the script's status would be \`trivy --version\`. Do not run Trivy from any other source.`;

function buildPrompt(cfg) {
  return `You fix dependency vulnerabilities in a GitHub repository. You are running as a cloud agent started by a GitHub Actions job that has already scanned the default branch.

The repository is cloned for you and your commits are attributed to the Cursor GitHub App, which can push them and open the pull request. \`gh\` in this VM is authenticated the same way. If \`git push\` is rejected, the App is missing access to this repository: say so in your final answer and stop, do not look for another credential.

# Context
- Repository: \`${cfg.repository}\`
- Default branch: \`${cfg.baseBranch}\`
- Fix branch: \`${cfg.fixBranch}\`
- Toolchains detected in the repository: \`$TOOLCHAINS\`

The findings are in this prompt, not in environment variables. A session env value is capped at 4096 bytes, and the medium/low list from a weekday scan is larger than that, so the create call is rejected when they are passed as env.

# Findings
CRITICAL and HIGH, each with a fixed version. Fix these:

\`\`\`json
${cfg.findingsCriticalHigh ?? "[]"}
\`\`\`

MEDIUM and LOW. List these in the pull request body and do not fix them:

\`\`\`json
${cfg.findingsMediumLow ?? "[]"}
\`\`\`

Advisory ids the repository already accepts:

\`\`\`json
${cfg.acceptedAdvisories ?? "[]"}
\`\`\`

Each finding has \`target\` (the lockfile path), \`pkg\`, \`installed\`, \`fixed\`, \`id\`, \`severity\` and \`vendorIds\`. Findings whose advisory id is in the accepted list are already filtered out; do not re-derive them and do not re-fix them.

# Toolchains
${TOOLCHAIN_RULE}

${VERIFIED_TRIVY_INSTALL}

Then scan once *without* \`--skip-db-update\` so the database is fetched:
\`trivy fs --scanners vuln --pkg-types library --severity CRITICAL,HIGH --ignore-unfixed <directory>\`
Repeat until its CRITICAL and HIGH findings are gone or cannot be fixed, dropping \`--skip-db-update\` only after the first scan has populated the database.

# Scope
- Fix only the CRITICAL and HIGH findings you were given.
- Do not fix MEDIUM or LOW findings; list them in the pull request body.
- Do not change anything unrelated to these findings, and never edit files under \`.github/\`.
- Do not run \`pnpm audit\`, \`npm audit\` or \`yarn audit\`.

# Branch
1. If \`${cfg.fixBranch}\` exists on origin (\`git ls-remote --exit-code --heads origin "${cfg.fixBranch}"\`): fetch it, check it out and rebase it onto \`origin/${cfg.baseBranch}\`. Never delete or recreate it.
2. Otherwise create it from \`origin/${cfg.baseBranch}\`.
3. Commit with the message \`fix(deps): resolve critical and high dependency vulnerabilities\` and push with \`git push --force-with-lease origin "${cfg.fixBranch}"\`. Never use \`git push --force\`. This is a scheduled job with no Jira ticket, so the commit scope is \`deps\`.

# Pull request
This run opens the pull request for you from \`${cfg.fixBranch}\` into \`${cfg.baseBranch}\`, so do not call \`gh pr create\`. What is left to you is its description:

- Write the description yourself and return it as \`pullRequestBody\` in the result block below. This run is attached to the pull request, so the workflow sets the body from that value; do not write it to a file, because a file in this VM is not readable from the runner.

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
3. Regenerate the lockfile with the tool that owns it: \`pnpm install --no-frozen-lockfile --ignore-scripts\`, \`npm install --package-lock-only --ignore-scripts\`, \`yarn install --ignore-scripts\`, \`go mod tidy\`, or \`cargo update -p <crate>\`. Always pass \`--ignore-scripts\`: a dependency's lifecycle script would otherwise run with your credentials.
4. Re-scan that directory and repeat until its CRITICAL and HIGH findings are gone or cannot be fixed. The database is not on the VM, so the first scan must run without \`--skip-db-update\`.

Before installing anything, follow these exactly — they are the only verified way to get these tools:

${TOOLCHAIN_RULE}

${VERIFIED_TRIVY_INSTALL}

Report back, per finding, the package, the installed version, the fixed version, the advisory id and what you did. Say plainly which findings you could not fix and why. Do not run \`pnpm audit\`, \`npm audit\` or \`yarn audit\`. Do not touch anything unrelated to these findings, and never edit files under \`.github/\`.`
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
 * The body is written on every run, because the agent rewrites the description to describe the
 * current state of the branch — which is what someone reading the pull request wants.
 */
/**
 * Removes anything credential-shaped from text the runner is about to publish.
 *
 * The agent's description is written into a pull request body, which on a public repository is
 * world-readable. The prompt forbids putting a token in the clone and the re-scan greps the pushed
 * worktree, but neither covers text the runner itself writes out of the agent's final message — so
 * the publication path needs its own gate.
 *
 * Returns `{ body, redacted }` so the caller can say whether it had to intervene.
 */
function redactCredentials(text) {
  if (typeof text !== "string" || text === "") {
    return { body: "", redacted: false };
  }

  let body = text;
  const substitutions = [
    // GitHub tokens: classic, app installation, OAuth, fine-grained.
    [/\bgh[pousr]_[A-Za-z0-9]{16,}/g, "[REDACTED]"],
    [/\bgithub_pat_[A-Za-z0-9_]{20,}/g, "[REDACTED]"],
    // Cursor API keys.
    [/\bcrsr_[A-Za-z0-9_-]{16,}/g, "[REDACTED]"],
    // A literal registry token on an npmrc line; the ${NODE_AUTH_TOKEN} placeholder is kept.
    [/:_authToken=\S*?(gh[pousr]_|github_pat_)[A-Za-z0-9_]+/g, ":_authToken=[REDACTED]"],
    // A bare bearer credential.
    [/\bBearer\s+[A-Za-z0-9._-]{20,}/gi, "Bearer [REDACTED]"]
  ];

  for (const [pattern, replacement] of substitutions) {
    body = body.replace(pattern, replacement);
  }
  return { body, redacted: body !== text };
}

async function applyPullRequestDetails({ repository, pullRequestUrl, token, requestBody }) {
  if (!pullRequestUrl || !token) {
    return;
  }

  const number = pullRequestUrl.match(/\/pull\/(\d+)$/)?.[1];
  if (!number) {
    return;
  }

  // The body comes from the verdict, which the agent returns in its final message. It cannot be a
  // file: the agent writes it in its own VM, so nothing on this runner could read it.
  const payload = { title: PR_TITLE };
  if (requestBody) {
    const { body, redacted } = redactCredentials(requestBody);
    payload.body = body;
    if (redacted) {
      // Loud on purpose: a description that needed redacting is worth looking at, not silently
      // cleaning up.
      process.stdout.write(
        "::warning::The agent's pull request body contained something credential-shaped and was redacted before publishing.\n"
      );
    }
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
  const apiKey = secretInput("CURSOR_API_KEY", "cursor-api-key");
  if (apiKey === "") {
    throw new Error(
      "CURSOR_API_KEY is not set. Pass the org secret on this step's env; a with: input is empty inside a node24 action."
    );
  }

  const cfg = {
    apiKey,
    repository: input("repository", { required: true }),
    repositoryUrl: input("repository-url", { required: true }),
    baseBranch: input("base-branch", { required: true }),
    fixBranch: input("fix-branch", { required: true }),
    toolchains: input("toolchains", { fallback: "unknown" }),
    runnerLabel: input("runner-label", { fallback: "unknown" }),
    githubToken: secretInput("GITHUB_TOKEN", "github-token"),
    npmToken: secretInput("NPM_TOKEN", "npm-token"),
    existingPullRequestUrl: input("existing-pull-request-url")
  };

  cfg.findingsCriticalHigh = input("findings-critical-high", { required: true });
  cfg.findingsMediumLow = input("findings-medium-low", { required: true });
  cfg.acceptedAdvisories = input("accepted-advisories", { fallback: "[]" });

  const findings = {
    FINDINGS_CRITICAL_HIGH: cfg.findingsCriticalHigh,
    FINDINGS_MEDIUM_LOW: cfg.findingsMediumLow,
    ACCEPTED_ADVISORIES: cfg.acceptedAdvisories
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

  // One pull request per repository, forever. The SDK defaults to pushing a fresh `cursor/`
  // branch and opening a new pull request each run, which would make the long-lived `fixBranch`
  // rebase flow pointless and leave a new PR every weekday. Attaching to the existing PR keeps the
  // SDK on the branch that already backs it.
  //
  // With no PR yet, `startingRef` must stay on the base branch: the API verifies the ref exists on
  // the remote when the agent is created, and the fix branch does not exist until the first push,
  // so pointing at it would fail before any work started. `autoCreatePR` then opens exactly one.
  const repoEntry = cfg.existingPullRequestUrl
    ? { url: cfg.repositoryUrl, prUrl: cfg.existingPullRequestUrl }
    : { url: cfg.repositoryUrl, startingRef: cfg.baseBranch };

  const agent = await Agent.create({
    apiKey: cfg.apiKey,
    name: `${cfg.repository} dependency audit`,
    cloud: {
      repos: [repoEntry],
      // True only when a pull request already exists. The API then pushes to that PR's head, which
      // is the long-lived fix branch. True with no PR would push straight to `startingRef`, and
      // that ref is the default branch.
      workOnCurrentBranch: Boolean(cfg.existingPullRequestUrl),
      // The Cursor GitHub App owns the clone, the push and the pull request, so nothing here needs
      // a repository-write token.
      autoCreatePR: true,
      openAsCursorGithubApp: true,
      skipReviewerRequest: true,
      metadata: agentMetadata(cfg),
      envVars: sessionEnvVars({ toolchains: cfg.toolchains, npmToken: cfg.npmToken })
    },
    agents: subagents()
  });

  // `Agent.create()` resolves before the VM is provisioned, so surface the id immediately: a run
  // that dies during provisioning is otherwise untraceable from the job log.
  process.stdout.write(`cloud agent ${agent.agentId} created for ${cfg.repository}\n`);
  setOutput("agent-id", agent.agentId);

  try {
    let run;
    try {
      run = await agent.send(buildPrompt(cfg));
    } catch (error) {
      // The SDK throws from a one-line bundle. Actions keeps that line and drops the message.
      process.stdout.write(`${formatAgentError(error)}\n`);
      throw error;
    }
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
  ENV_VAR_VALUE_MAX_BYTES,
  FIX_MODEL_ID,
  LIFECYCLE_SCRIPT_GUARD,
  MAX_FINDINGS_BYTES,
  PR_TITLE,
  agentMetadata,
  formatAgentError,
  sessionEnvVars,
  applyPullRequestDetails,
  buildPrompt,
  buildReport,
  collectResult,
  loadAgentSdk,
  input,
  parseArrayInput,
  parseVerdict,
  redactCredentials,
  secretInput,
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
