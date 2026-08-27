# Odd Number Model Forensics Repository Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build, verify, and privately publish a compact GitHub repository that makes the completed Odd Number investigation auditable without committing models, runtimes, caches, credentials, or private provider identifiers.

**Architecture:** Curate publication copies into the fresh E:-staged repository using explicit source-to-destination mappings. Preserve exact, safe as-run artifacts separately from parameterized portable copies; run repo-relative statistical, privacy, and size gates without starting a model; then create a private GitHub remote in the authenticated browser and verify a fresh clone over SSH.

**Tech Stack:** Git 2.49+, PowerShell 7, Python 3 standard library/unittest, JSON/JSONL, Markdown, GitHub SSH and authenticated Chrome.

**Spec:** `docs/superpowers/specs/2026-08-23-odd-number-model-forensics-repository-design.md`

## Global Constraints

- Work only in `E:\Temp\spar-odd-number-20260823\publication\odd-number-model-forensics` until the private remote is verified.
- Do not start llama.cpp, Ollama, a model server, or any experiment runner.
- Preserve original E: experiment artifacts byte-for-byte; sanitize only publication copies.
- No tracked file may exceed 10 MiB.
- Exclude GGUF files, runtime/download archives, caches, logs, Python bytecode, `.serena`, environment files, credentials, tokens, incomplete 32B experiments, and local model manifests.
- Remove every provider thread ID from publication data and reject Windows user-profile paths, email addresses, private-key blocks, bearer-auth material, or credential-like assignments at the privacy gate.
- Keep the original collection summary's post-collection failure status and explain that `offline_finalization.json` is authoritative after 112/112 score rows.
- Treat pair-bootstrap intervals as descriptive over eight fixed pairs and the user-alignment decomposition as post hoc.
- Publish as a private repository named `odd-number-model-forensics`; do not add an open-source license without separate approval.
- Do not delete `E:\Temp\spar-odd-number-20260823` until the GitHub remote, Google Doc, email handoff, and retained deliverables are all verified.

---

### Task 1: Repository safety scaffold

**Files:**
- Create: `.gitignore`
- Create: `LICENSE-NOTICE.md`
- Create: `scripts/privacy_helpers.ps1`
- Create: `scripts/privacy-check.ps1`
- Create: `scripts/tests/test_privacy_helpers.ps1`

**Interfaces:**
- Consumes: repository root from `$PSScriptRoot` and `git ls-files -z`.
- Produces: `Get-TrackedPublicationFiles -RepoRoot <string>`, `Test-ForbiddenPublicationPath -RelativePath <string>`, `Test-SensitivePublicationText -Text <string>`, and a zero/nonzero `privacy-check.ps1` process exit code.

- [ ] **Step 1: Write failing safety-helper tests**

Create `scripts/tests/test_privacy_helpers.ps1` with a small custom test harness and cases equivalent to:

```powershell
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'privacy_helpers.ps1')

Assert-True (Test-ForbiddenPublicationPath 'models/model.gguf') 'GGUF must be rejected'
Assert-True (Test-ForbiddenPublicationPath 'results/logs/server.stdout.txt') 'logs must be rejected'
Assert-True (-not (Test-ForbiddenPublicationPath 'results/logprob/analysis.json')) 'analysis must be allowed'
Assert-True (Test-SensitivePublicationText $runtimeBuiltProviderThreadFixture) 'thread IDs must be rejected'
Assert-True (Test-SensitivePublicationText $runtimeBuiltWindowsUserPath) 'user profile paths must be rejected'
Assert-True (-not (Test-SensitivePublicationText 'E:\Temp\spar-odd-number-20260823')) 'as-run E path is allowed'
```

- [ ] **Step 2: Run the safety-helper tests and confirm the red state**

Run:

```powershell
pwsh -NoProfile -File scripts/tests/test_privacy_helpers.ps1
```

Expected: nonzero exit because `privacy_helpers.ps1` does not exist.

- [ ] **Step 3: Implement the minimal privacy helpers and gate**

Implement exact case-insensitive path rejection for:

```powershell
@('*.gguf', 'runtime/', 'downloads/', 'process-cache/', 'logs/', '__pycache__/', '*.pyc', '.serena/', '.env')
```

Implement text rejection for provider thread IDs, Windows user-profile paths, private-key blocks, bearer-auth material, common API-key assignments, and email-address patterns. `privacy-check.ps1` must enumerate only tracked files, reject files larger than `10MB`, skip binary content scanning only for `.png` and `.docx`, and emit a counted summary.

Create `.gitignore` containing the same excluded path families plus `*.zip`, `*.7z`, `*.dll`, `*.exe`, model directories, cache directories, and temporary clone directories. Create `LICENSE-NOTICE.md` stating that the private repository is shared for take-home review, contains no general reuse grant, and preserves upstream licenses for Qwen3 and llama.cpp.

- [ ] **Step 4: Run the helper tests and a clean empty-index gate**

Run:

```powershell
pwsh -NoProfile -File scripts/tests/test_privacy_helpers.ps1
pwsh -NoProfile -File scripts/privacy-check.ps1
```

Expected: all helper cases pass; the privacy gate reports zero violations.

- [ ] **Step 5: Commit the safety scaffold**

```powershell
git add .gitignore LICENSE-NOTICE.md scripts/privacy_helpers.ps1 scripts/privacy-check.ps1 scripts/tests/test_privacy_helpers.ps1
git commit -m "chore: add publication safety gates"
```

### Task 2: Package and sanitize the broad-screen evidence

**Files:**
- Create: `experiments/broad-screen/src/experiment.py`
- Create: `experiments/broad-screen/src/collect.py`
- Create: `experiments/broad-screen/src/wrapper_screen.py`
- Create: `experiments/broad-screen/src/candidate_screen.py`
- Create: `experiments/broad-screen/src/local_screen.py`
- Create: `experiments/broad-screen/tests/test_experiment.py`
- Create: `experiments/broad-screen/tests/test_local_screen.py`
- Create: `results/broad-screen/results.jsonl`
- Create: `results/broad-screen/wrapper_screen.jsonl`
- Create: `results/broad-screen/candidate_screen.sanitized.jsonl`
- Create: `results/broad-screen/local_screen.jsonl`
- Create: `results/broad-screen/schedule.json`
- Create: `results/broad-screen/wrapper_schedule.json`
- Create: `results/broad-screen/candidate_schedule.json`
- Create: `results/broad-screen/local_screen_schedule.json`
- Create: `results/broad-screen/summary.json`
- Create: `scripts/sanitize_candidate_screen.ps1`
- Create: `scripts/tests/test_sanitize_candidate_screen.ps1`

**Interfaces:**
- Consumes: publication copies made from the C: workspace's broad-screen source and data.
- Produces: portable Python modules, thread-ID-free JSONL, and `results/broad-screen/summary.json` with exact totals `{calls:58, model_ids:13, strict_valid:50, strict_valid_odd:0, manually_clear_even:57, nonanswers:1}`.

- [ ] **Step 1: Write the sanitizer regression test**

The test creates a temporary JSONL fixture containing nested provider metadata and asserts that the sanitizer preserves all fields except the provider thread ID:

```powershell
$input = $runtimeBuiltSanitizerFixture
# Run sanitizer to a separate temp output.
# Assert output has response=42, usage.tokens=2, and no recursive provider thread-ID property.
```

- [ ] **Step 2: Run the sanitizer test and confirm the red state**

Run `pwsh -NoProfile -File scripts/tests/test_sanitize_candidate_screen.ps1`.

Expected: nonzero exit because the sanitizer is absent.

- [ ] **Step 3: Copy the explicit broad-screen files and make the runner portable**

Copy only the files listed above. In the publication copy of `experiment.py`, replace the hard-coded Codex executable with this resolution order:

```python
def resolve_codex_executable(explicit: str | None = None) -> str:
    candidate = explicit or os.environ.get("CODEX_EXECUTABLE") or shutil.which("codex")
    if not candidate:
        raise RuntimeError("Provide --codex-executable, set CODEX_EXECUTABLE, or put codex on PATH")
    return candidate
```

Update callers and tests to inject a fake executable path. Do not retain any Windows user-profile path.

- [ ] **Step 4: Implement recursive thread-ID removal and write the frozen summary**

`sanitize_candidate_screen.ps1` must parse each nonempty line, recursively remove provider thread-ID properties, serialize compact JSON, and preserve line order. Run it from the original candidate file into the publication copy. Write `summary.json` with the exact frozen totals and a note that the 57-clear-even/1-nonanswer split is a manual raw-response classification.

- [ ] **Step 5: Run broad-screen tests and privacy checks**

Run:

```powershell
python -m unittest discover -s experiments/broad-screen/tests -v
pwsh -NoProfile -File scripts/tests/test_sanitize_candidate_screen.ps1
git add experiments/broad-screen results/broad-screen scripts/sanitize_candidate_screen.ps1 scripts/tests/test_sanitize_candidate_screen.ps1
pwsh -NoProfile -File scripts/privacy-check.ps1
```

Expected: Python and PowerShell tests pass; privacy gate finds zero thread IDs or user-profile paths.

- [ ] **Step 6: Commit the sanitized broad screen**

```powershell
git commit -m "data: add sanitized broad model screen"
```

### Task 3: Package Qwen behavioral and probability provenance

**Files:**
- Create: `preregistration/broad-screen.md`
- Create: `preregistration/mechanism-followup.md`
- Create: `preregistration/logprob-followup.md`
- Create: `experiments/qwen3-4b/prompts/*.txt`
- Create: `experiments/qwen3-4b/as-run/*.ps1`
- Create: `experiments/qwen3-4b/portable/screen_helpers.ps1`
- Create: `experiments/qwen3-4b/portable/logprob_helpers.ps1`
- Create: `experiments/qwen3-4b/tests/test_screen_helpers.ps1`
- Create: `experiments/qwen3-4b/tests/test_mechanism_helpers.ps1`
- Create: `experiments/qwen3-4b/tests/test_logprob_helpers.ps1`
- Create: `results/behavioral/<condition>/{schedule.json,results.jsonl,summary.json}`
- Create: `results/logprob/{schedule.json,validation.json,condition_pair_scores.jsonl,raw_responses.jsonl,analysis.json,analysis.md,offline_finalization.json,exploratory_user_alignment_decomposition.json}`
- Create: `results/audit/failed-pre-http/{v1-summary.json,v2-summary.json}`
- Create: `provenance/collection-summary.original.json`
- Create: `provenance/offline-finalization.original.json`

**Interfaces:**
- Consumes: explicit safe files from `E:\Temp\spar-odd-number-20260823\local-gpu`.
- Produces: exact as-run scripts, portable helper code, three preregistrations, four behavioral blocks, complete 112-row log-probability evidence, and two pre-HTTP failure summaries.

- [ ] **Step 1: Copy only the allowlisted Qwen files**

Use literal source and destination paths. Exclude every `logs/`, `process-cache/`, model, runtime, download, and failed-attempt artifact other than the two small summaries. Preserve source hashes in a temporary audit record before copying.

- [ ] **Step 2: Create portable copies without altering as-run provenance**

Retain the exact E:-specific scripts under `as-run/`. In `portable/`, keep prompt/condition/statistical helpers repo-relative and parameterize roots as:

```powershell
param(
    [string] $ModelPath,
    [string] $LlamaServerPath,
    [string] $OutputRoot = (Join-Path $PSScriptRoot '..\..\..\results')
)
```

Portable runner documentation must state that these parameters are required and that the repository verifier never invokes a model runner.

- [ ] **Step 3: Run the retained helper tests**

Run:

```powershell
pwsh -NoProfile -File experiments/qwen3-4b/tests/test_screen_helpers.ps1
pwsh -NoProfile -File experiments/qwen3-4b/tests/test_mechanism_helpers.ps1
pwsh -NoProfile -File experiments/qwen3-4b/tests/test_logprob_helpers.ps1
```

Expected: all screen/mechanism tests and all 15 log-probability tests pass without a listener or model process.

- [ ] **Step 4: Verify copied provenance hashes before staging**

Assert these SHA-256 values:

```text
schedule.json                a59dd875427a356b83f98db436feae1c93e12b247dea2040f0cc84f875360fdc
validation.json              6458582d03ea0d88e172c49472060c986cd6649502a870daed622bdd8419d3ff
condition_pair_scores.jsonl  d4f33ed28557807be471a8d358f9181bbbd1dbb184f63b14a1058088f8fb5a3f
raw_responses.jsonl          6f38950a9e1a2195226557793102778d36e377ccb3e92bdc8311ae1da8aee660
collection summary           e4b6c5994acbf41fa68231ac4439968d4086ad949695a0772cf9493fca4b989a
analysis.json                6f7f05e80b00a6d3934916fae5f791525ef8a4b674dcf57aba8da9bd00d82c6f
analysis.md                  c2b077b2b31ce862b4f699708d744986c61cd23683f85f653e410c79ad3d1220
```

- [ ] **Step 5: Stage, run privacy/size gates, and commit**

```powershell
git add preregistration experiments/qwen3-4b results/behavioral results/logprob results/audit provenance
pwsh -NoProfile -File scripts/privacy-check.ps1
git commit -m "data: add Qwen mechanism and probability evidence"
```

### Task 4: Implement the one-command statistical verifier

**Files:**
- Create: `scripts/verify_helpers.ps1`
- Create: `scripts/verify.ps1`
- Create: `scripts/tests/test_verify_helpers.ps1`
- Create: `results/derived/verification-reference.json`

**Interfaces:**
- Consumes: portable `logprob_helpers.ps1`, immutable result files, behavioral result blocks, and broad-screen summary.
- Produces: `Invoke-RepositoryVerification -RepoRoot <string>` and a stable JSON-like console summary; never writes result artifacts or starts a model.

- [ ] **Step 1: Write failing verifier tests**

Cover the following exact cases:

```powershell
Assert-Throws { Assert-ExactHash -Path $fixture -Expected ('0' * 64) -Label fixture } 'tamper must fail'
Assert-Throws { Assert-CompleteSchedule -ScheduleIds @('a','b') -ScoreIds @('a') } 'missing ID must fail'
Assert-Throws { Assert-ValidLogprob -Value 0.1 -Label positive } 'positive logprob must fail'
Assert-Close (Get-Mean @(-1.0, 1.0)) 0.0 1e-12 'mean mismatch'
```

Add a fixture with one even-request row and one odd-request row and assert requested/reward sign identities.

- [ ] **Step 2: Run verifier tests and confirm the red state**

Run `pwsh -NoProfile -File scripts/tests/test_verify_helpers.ps1`.

Expected: nonzero exit because helpers are absent.

- [ ] **Step 3: Implement read-only verification helpers**

Implement:

```powershell
Assert-ExactHash
Read-JsonLines
Assert-CompleteSchedule
Assert-ValidLogprob
Assert-ScoreIdentities
Assert-Close
Invoke-RepositoryVerification
```

Reuse the portable frozen estimand and seeded bootstrap functions rather than reimplementing their formulas. Verify 112 unique rows, 14 x 8 coverage, finite nonpositive candidate log probabilities, raw odds, requested signs, reward signs, all seven immutable hashes, and all saved validation checks.

- [ ] **Step 4: Assert exact recomputed statistics and behavioral counts**

Require:

```text
primary DID                         -0.9345689862966537
primary descriptive interval       [-1.4620493277907372, -0.43283782713115215]
conflict current-minus-archived     -0.4729396626353264
transform reversal                  -0.0468835774809122
negative primary candidate pairs    7 of 8
post hoc overall user boost         0.4672844931483269
broad exact calls/valid/odd          58 / 50 / 0
```

Read the behavioral JSONL blocks and assert each frozen cell count used in the report, including 6/6 explicit-maximize reward alignment with capped thinking and 0/12 reward alignment across the mirrored capped-thinking conflicts.

- [ ] **Step 5: Run the full verifier from a clean process**

```powershell
pwsh -NoProfile -File scripts/tests/test_verify_helpers.ps1
pwsh -NoProfile -File scripts/verify.ps1
```

Expected: helper tests pass; verifier reports all hashes, 112/112 rows, exact statistics, behavioral counts, and privacy gate success with exit code 0.

- [ ] **Step 6: Commit the verifier**

```powershell
git add scripts/verify_helpers.ps1 scripts/verify.ps1 scripts/tests/test_verify_helpers.ps1 results/derived/verification-reference.json
git commit -m "test: add one-command evidence verifier"
```

### Task 5: Add the report and reader-facing documentation

**Files:**
- Create: `README.md`
- Create: `METHODOLOGY.md`
- Create: `ARTIFACTS.md`
- Create: `report/takehome.md`
- Create: `report/odd-number-model-forensics-takehome.docx`
- Create: `report/figures/behavioral-results.png`
- Create: `report/figures/logprob-results.png`
- Create: `report/build_report.py`

**Interfaces:**
- Consumes: verified findings, source Markdown/DOCX/figures under E: writeup assets, Qwen model/runtime hashes, and source URLs.
- Produces: a self-contained landing page, methodological explanation, excluded-artifact manifest, report sources, sanitized binary report, and repo-relative report builder.

- [ ] **Step 1: Copy the report artifacts and make the builder repository-relative**

Copy the final Markdown, sanitized DOCX, and two inspected PNG figures. Change `build_report.py` so `ROOT` is `Path(__file__).resolve().parent`, assets are under `report/figures`, output defaults to `report/odd-number-model-forensics-takehome.docx`, and font loading falls back from Windows Arial to bundled/common sans-serif choices without a C: or E: literal.

- [ ] **Step 2: Write README, methodology, and artifact manifest**

`README.md` must lead with the narrow conclusion, show the exact source prompt, summarize the three evidence layers, link to the report and source post, and provide the one-command verifier. `METHODOLOGY.md` must explain causal predictions and caveats. `ARTIFACTS.md` must record:

```text
Qwen3-4B Q4_K_M GGUF  7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5
llama.cpp archive      6805bde00c16006cdcc757a132f7ba95d82b5f1e6ddba7e1d91f80c4e6930dcb
CUDA archive           8c79a9b226de4b3cacfd1f83d24f962d0773be79f1e7b75c6af4ded7e32ae1d6
```

Explain that these binaries are excluded and give their official source URLs.

- [ ] **Step 3: Run report and documentation checks**

```powershell
python -m py_compile report/build_report.py
rg -n "TBD|TODO|Windows user-profile path|provider thread ID|codex-file-citation|turn[0-9]+" README.md METHODOLOGY.md ARTIFACTS.md report
pwsh -NoProfile -File scripts/privacy-check.ps1
pwsh -NoProfile -File scripts/verify.ps1
```

Expected: compile succeeds; `rg` finds no forbidden placeholder/private citation tokens; privacy and evidence verification pass.

- [ ] **Step 4: Commit reader-facing material**

```powershell
git add README.md METHODOLOGY.md ARTIFACTS.md report
git commit -m "docs: publish model forensics report"
```

### Task 6: Final review, private publication, and fresh-clone proof

**Files:**
- Modify: none unless a review finding requires a focused corrective commit.
- Create outside repo: `E:\Temp\spar-odd-number-20260823\publication\clone-check\odd-number-model-forensics`.

**Interfaces:**
- Consumes: clean verified `main` branch and authenticated GitHub/SSH sessions.
- Produces: private GitHub repository URL, verified `origin/main`, and a fresh-clone verification result.

- [ ] **Step 1: Run the complete local release gate**

```powershell
pwsh -NoProfile -File scripts/verify.ps1
pwsh -NoProfile -File scripts/privacy-check.ps1
git status --short
git ls-files
git count-objects -vH
git log --oneline --decorate --reverse
```

Expected: both gates exit 0; status is clean; no tracked file exceeds 10 MiB; history contains the design, safety, data, verifier, and documentation commits.

- [ ] **Step 2: Review the complete publication diff**

```powershell
git diff --stat 16320d3..HEAD
git diff --check 16320d3..HEAD
```

Expected: only the specified publication files; no whitespace errors. Inspect the complete tracked-file list and randomly sample source/provenance/report files before external publication.

- [ ] **Step 3: Create the private GitHub repository in authenticated Chrome**

Create an empty private repository named `odd-number-model-forensics` under the SSH-authenticated account. Do not initialize it with a README, `.gitignore`, or license. Record the exact SSH URL returned by GitHub.

- [ ] **Step 4: Add the SSH remote and push main**

```powershell
git remote add origin <authenticated-ssh-remote-url>
git push -u origin main
git ls-remote --heads origin main
```

Expected: push succeeds and `ls-remote` reports `refs/heads/main` at local `HEAD`.

- [ ] **Step 5: Verify the rendered private repository**

Open the repository page and confirm README headings, source prompt, figures, internal links, report link, and verification command render correctly. Confirm repository visibility is Private.

- [ ] **Step 6: Clone and verify independently on E:**

```powershell
git clone --filter=blob:none <authenticated-ssh-remote-url> E:\Temp\spar-odd-number-20260823\publication\clone-check\odd-number-model-forensics
pwsh -NoProfile -File E:\Temp\spar-odd-number-20260823\publication\clone-check\odd-number-model-forensics\scripts\verify.ps1
```

Expected: clone succeeds and the verifier exits 0 without accessing the original experiment tree or starting a model process.

- [ ] **Step 7: Report the URL and retain E: pending final handoff**

Report the private GitHub URL and verification evidence. Do not delete the original E: tree until the Google Doc and email are also complete and the user has the retained links.
