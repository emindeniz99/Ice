# Supply-chain security review

This document records a hardening pass against the Ice repository performed on
branch `claude/fix-macos26-compatibility-Ar8K6`. The work follows the playbook
laid out in Astral's *Open-source security at Astral* post and was motivated by
the recent "Mini Shai-Hulud" npm worm coverage. The scope of this pass was the
CI/CD surface and supply-chain posture; no application source files were
changed.

## Why this pass — context and references

Recent worm activity in the open-source ecosystem (the "Shai-Hulud" family
of self-propagating npm compromises) has made it clear that publish tokens,
unconstrained workflow permissions, and floating action references are now
the soft underbelly of most maintainer-run repositories. The "Mini Shai-Hulud"
variant in particular has shown that an attacker who gets *any* workflow
write context can pivot into stealing publish credentials and trojanizing
downstream releases.

Even though Ice is a pure Swift macOS project with no npm footprint, the
same patterns apply: a compromised GitHub Action, a misconfigured
`pull_request_target` job, or a leaked release token would be enough to ship
a tampered binary to users. This pass closes those gaps.

References:

- Astral's open-source security guide:
  <https://astral.sh/blog/open-source-security-at-astral>
- Mini Shai-Hulud worm coverage (The Hacker News, 2026-05):
  <https://thehackernews.com/2026/05/mini-shai-hulud-worm-compromises.html>

## Threat model assumptions

The assumed adversary model for this review:

- A third-party GitHub Action gets compromised at the tag level (a maintainer's
  token is stolen, the tag gets force-moved to a malicious commit) — covered by
  pinning every action to a 40-char commit SHA.
- A pull request from a fork attempts to exfiltrate repository secrets or write
  to the default branch — covered by default-deny `permissions: {}`, by the
  absence of `pull_request_target` / `workflow_run` triggers, and by
  `persist-credentials: false` on the zizmor checkout.
- A transitive Swift Package or GitHub Action ships a malicious update —
  covered by Dependabot raising PRs (which are reviewable before merge) and by
  zizmor flagging workflow-side regressions.
- A maintainer account is phished and used to push directly to a release
  branch — partially covered; full coverage requires the repo-admin items in
  Phase 3.

Out of scope: the application's runtime threat model (sandboxing,
accessibility-API misuse, etc.) and the macOS code-signing / notarization
pipeline (Phase 3 lists the controls relevant to that path).

## Phase 1 — Indicator-of-compromise scan

A targeted scan for known worm/compromise indicators returned **clean**:

- No `router_init.js`, no Session/webhook exfiltration endpoints, and no
  references to known C2 hosts anywhere in the tree or in git history.
- No suspicious git authors. Only two unique author identities appear in the
  history: **Jordan Baird** (project owner) and the **Claude co-author**
  identity used on the macOS 26 compatibility branch. Both are expected.
- No JavaScript / Python / Node footprint. The repo is a pure Swift
  Xcode project: no `node_modules`, no `package.json`, no `requirements.txt`,
  no postinstall hook surface area for an npm-style worm.
- No committed secrets in history (no `.env`, no API tokens, no signing
  keys committed, no high-entropy strings matching common credential
  formats).
- No risky publish-side actions present (no `npm publish`, no PyPI release
  step, no `actions/create-release` with a static token).
- No `pull_request_target` or `workflow_run` triggers in any workflow — these
  are the two triggers most often abused for secret exfiltration from fork
  PRs.
- No obvious expression-injection sinks in workflow `run:` blocks (no raw
  `${{ github.event.* }}` user-controlled strings flowing into shell).

Conclusion: the repository does not currently show signs of an active
compromise. The remaining phases focus on preventing one.

## Phase 2 — Workflow hardening

All workflows under `.github/workflows/` now follow the same baseline:

- **Top-level `permissions: {}`** (default-deny). Each job opts back in to
  the *minimum* scope it actually needs.
- **Every third-party action pinned to a 40-char commit SHA** with the
  human-readable version preserved as a trailing comment so Dependabot can
  still bump it.
- **`defaults.run.shell: bash -euo pipefail {0}`** so shell steps fail fast on
  unset variables and broken pipes.
- **No `pull_request_target`, no `workflow_run`.** Fork PRs run with the
  `pull_request` trigger and therefore cannot read repository secrets.
- **Header comment** in every workflow file pointing at the Astral guide so
  future contributors understand the constraints.

### `build.yml`

| Item | Value / SHA |
|---|---|
| `actions/checkout` | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` (v6.0.2) |
| `actions/upload-artifact` | `043fb46d1a93c77aae656e7c1c64a875d1fc6a0a` (v7.0.1) |
| Top-level permissions | `permissions: {}` |
| Shell defaults | `bash -euo pipefail {0}` |
| Artifact upload | `if-no-files-found: warn` (does not silently succeed on missing logs) |

### `lint.yml`

| Item | Value / SHA |
|---|---|
| `actions/checkout` | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` (v6.0.2) |
| `norio-nomura/action-swiftlint` | `9f4dcd7fd46b4e75d7935cf2f4df406d5cae3684` (3.2.1) |
| Top-level permissions | `permissions: {}` |
| Job-level scope | `swiftlint` job opts back in to `checks: write` only |
| Shell defaults | `bash -euo pipefail {0}` |

### `zizmor.yml` (new)

| Item | Value / SHA |
|---|---|
| `actions/checkout` | `de0fac2e4500dabe0009e67214ff5f5447ce83dd` (v6.0.2) |
| `astral-sh/setup-uv` | `08807647e7069bb48b6ef5acd8ec9567f424441b` (v8.1.0) |
| `github/codeql-action/upload-sarif` | `bc0b696b4103f5fe60f15749af68a046868d511a` (codeql-bundle-v2.25.4) |
| Top-level permissions | `permissions: {}` |
| Job-level scope | `security-events: write` + `contents: read` (SARIF upload only) |
| Checkout hardening | `persist-credentials: false` |
| Findings sink | SARIF uploaded to GitHub Code Scanning |
| Rollout posture | `continue-on-error: true` so initial findings surface without breaking the build |

## Phase 3 — Repo-level controls (admin required)

These controls cannot be applied from code — they require GitHub repository
admin access. They are listed in priority order; items 1, 2, and 3 are the
highest-impact.

1. **Branch protection on `macos-26`** (and any other release-track branches
   such as `main`): require a PR with at least one approving review, require
   the `Build (macos-26)`, `Build (macos-15)`, `Swift parse (Linux)`,
   `swiftlint`, and `zizmor audit` checks to pass, disallow force-push, and
   disallow branch deletion.
2. **Tag protection ruleset on `v*`** so that release tags can only be
   created or moved by a workflow running in a protected GitHub Environment
   (with required reviewers). This is the single biggest mitigation against a
   worm-style compromise: even a stolen maintainer token cannot cut a
   release without environment approval.
3. **Secret scanning + push protection** enabled at the repository level so
   that a stray API key or Apple notarization credential cannot be pushed.
4. **Code scanning enabled for Swift.** The `zizmor.yml` workflow already
   uploads SARIF for workflow findings; CodeQL Swift can be enabled in
   parallel as a second source for application-code findings.
5. **Require signed commits** on protected branches. This is particularly
   important if releases will be signed and notarized for the Mac App Store
   path, because it ties every commit in the release history to a verified
   identity.

## Phase 4 — Dependabot

`.github/dependabot.yml` now configures two ecosystems on a weekly cadence:

- **`github-actions`** — directory `/`, weekly (Monday 06:00 UTC), grouped
  into a single PR (`groups.actions.patterns: ["*"]`), `open-pull-requests-limit: 5`,
  labels `dependencies` / `github-actions`, commit prefix `ci`. Updates
  preserve the `SHA  # vX.Y.Z` pinning pattern.
- **`swift`** — directory `/`, same weekly cadence, `open-pull-requests-limit: 5`,
  labels `dependencies` / `swift`, commit prefix `deps`. This ecosystem
  follows the six `XCRemoteSwiftPackageReference` entries already declared in
  `Ice.xcodeproj`:
  - Sparkle
  - LaunchAtLogin-Modern
  - AXSwift
  - CompactSlider
  - Ifrit
  - Semaphore

Grouping plus the PR limit keeps the noise bounded; the maintainer sees at
most one Actions PR and a small number of Swift PRs per week, each of which
is reviewable before merge.

## Phase 5 — Static analysis (zizmor)

[zizmor](https://github.com/woodruffw/zizmor) is a static analyzer for
GitHub Actions workflows. It catches expression injection, dangerous
triggers (`pull_request_target` patterns, `workflow_run` chains),
over-broad permissions, unpinned actions, persisted credentials, and other
supply-chain-relevant misconfigurations.

The new `zizmor.yml` workflow runs on every push and PR that touches
`.github/workflows/**` (plus on `workflow_dispatch`), executes
`uvx --from zizmor zizmor --persona=auditor --format sarif` against the
workflows directory, and uploads the SARIF to GitHub Code Scanning. During
the initial rollout it is marked `continue-on-error: true` so the existing
backlog of findings surfaces in the Security tab without blocking unrelated
work; that flag should be removed once the backlog has been triaged
(tracked in *Remaining risk* below).

## What was deliberately skipped, and why

- **gitleaks** — the IoC scan in Phase 1 found zero committed secrets and
  the project has no historical pattern of credentials living in the tree.
  Phase 3's push-protection / secret scanning provides comparable forward
  coverage with less workflow noise. Easy to add later if posture changes.
- **OSV-Scanner** — Swift Package Manager support in OSV-Scanner is still
  limited (the OSV database has thin Swift coverage compared to npm, PyPI,
  or crates.io). The `swift` Dependabot ecosystem already raises PRs for
  upstream package updates, which is the actionable surface; an OSV report
  on the same packages would mostly be redundant today.
- **pinact** — this pass *manually* pinned every third-party action to a
  40-char SHA and Dependabot will keep those pins fresh. pinact is more
  useful as an ongoing-maintenance tool for repos that have not yet been
  hand-pinned; revisit if the workflow set grows substantially.

## Remaining risk

- **Issue #946 (macOS 26.5 hidden→always-hidden regression).** This is a
  functional regression, not a security issue, but it lives on the same
  branch and is worth tracking as a follow-up so the security and
  functional hardening land together.
- **`continue-on-error: true` on the zizmor job.** Initial findings will
  *not* fail builds. Once the existing backlog has been triaged, flip the
  flag off so future regressions block merge.
- **Phase 3 items require repo-admin access.** Branch protection, tag
  protection rulesets, secret-scanning push protection, code scanning, and
  signed-commit requirements cannot be enforced from code. Until the
  maintainer enables them in GitHub Settings, the highest-impact controls
  (specifically tag protection on `v*`) remain off and a compromised
  maintainer token could still cut a release.

## Verification steps for the maintainer

After merging this branch:

1. Open the **Actions** tab and confirm the `Zizmor audit` workflow ran
   green on its first push.
2. Open the **Security → Code scanning** tab and confirm zizmor findings
   appear under the `zizmor` category.
3. Open the **Insights → Dependency graph → Dependabot** tab and confirm
   both the `github-actions` and `swift` ecosystems are listed as
   monitored.
4. Open **Settings → Branches** and apply the Phase 3 branch protection
   rule to `macos-26` (and any other release-track branches).
5. Open **Settings → Rules → Rulesets** and create the tag-protection
   ruleset for `v*`.
6. Open **Settings → Code security and analysis** and enable secret
   scanning + push protection, then enable CodeQL for Swift.
7. Once any zizmor findings have been triaged, edit
   `.github/workflows/zizmor.yml` and remove the `continue-on-error: true`
   line from the `Run zizmor` step.

## Commit map

The commits delivered by this pass, in the order they landed:

| SHA | Subject |
|---|---|
| `c3f02f5` | CI: harden workflows per Astral's open-source security guide — SHA pinning, default-deny permissions, strict bash defaults, header comments. |
| `6abfa1a` | Add Dependabot config for GitHub Actions + Swift Package Manager — weekly cadence, grouped, 5-PR limit per ecosystem. |
| `23ec544` | CI: add zizmor static analysis for workflows — SARIF upload to GitHub Code Scanning, `continue-on-error` during rollout. |
| `dda0bd4` | CodeSignInfo: document the file's purpose — Swift comment touch to re-trigger CI after the workflow changes. |
