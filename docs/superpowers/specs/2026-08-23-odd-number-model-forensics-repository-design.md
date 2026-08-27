# Odd Number Model Forensics Repository Design

## Status and scope

This specification packages the completed Odd Number investigation as a private, auditable GitHub repository named `odd-number-model-forensics`. The repository supports the take-home report; it does not replace the report's self-contained argument, rerun any model, or claim to reproduce the private late capabilities-RL checkpoints in the source post.

The publication unit is a fresh Git repository staged under `E:\Temp\spar-odd-number-20260823`. The existing C: workspace is an unborn, dirty Git repository containing unrelated and exploratory files, so it will not be reused as the publication root. The only intended C: deliverable remains the final DOCX.

## Approaches considered

### Selected: fresh E:-staged repository and private GitHub remote

Build a curated repository from explicit include lists, create an empty private repository through the authenticated GitHub web interface, add the SSH remote, push `main`, and verify the remote independently. This minimizes accidental inclusion, avoids installing another CLI, and preserves the user's request that experiment work remain on E:.

### Rejected: publish the existing C: workspace directly

The current workspace has no commits, no remote, and all contents are untracked. It also contains incomplete 32B experiment material, local manifests, caches, and exploratory scripts. Publishing it directly would make privacy, provenance, and scope harder to audit.

### Rejected: install GitHub CLI or use a hand-managed API token

GitHub CLI is not installed. SSH authentication already works, but SSH cannot create a repository. Creating the remote in the logged-in browser is lower risk than installing another tool or passing an API token through scripts.

## Repository architecture

```text
odd-number-model-forensics/
|-- README.md
|-- LICENSE-NOTICE.md
|-- .gitignore
|-- ARTIFACTS.md
|-- METHODOLOGY.md
|-- report/
|   |-- takehome.md
|   |-- odd-number-model-forensics-takehome.docx
|   `-- figures/
|       |-- behavioral-results.png
|       `-- logprob-results.png
|-- preregistration/
|   |-- broad-screen.md
|   |-- mechanism-followup.md
|   `-- logprob-followup.md
|-- experiments/
|   |-- broad-screen/
|   |   |-- src/
|   |   `-- tests/
|   `-- qwen3-4b/
|       |-- prompts/
|       |-- as-run/
|       |-- portable/
|       `-- tests/
|-- results/
|   |-- broad-screen/
|   |-- behavioral/
|   |-- logprob/
|   |-- derived/
|   `-- audit/failed-pre-http/
|-- provenance/
|   |-- collection-summary.original.json
|   `-- offline-finalization.original.json
|-- scripts/
|   |-- verify.ps1
|   |-- privacy-check.ps1
|   `-- history-privacy-check.ps1
`-- docs/superpowers/specs/
    `-- 2026-08-23-odd-number-model-forensics-repository-design.md
```

Each directory has one purpose. `as-run/` preserves exact E:-specific scripts needed to understand the original execution. `portable/` contains parameterized copies suitable for another machine. `provenance/` contains immutable original records whose machine-specific paths or post-collection failure status must remain unchanged for auditability. `derived/` contains readable summaries generated from those records.

## Inclusion boundary

The repository includes the report Markdown and sanitized DOCX, both final figures, all three preregistrations, compact broad-screen code and tests, exact Qwen prompt files, the successful behavioral schedules/results/summaries, the successful 112-row log-probability score set and raw payload, the final analysis, the exploratory user-alignment decomposition, and the two failed pre-HTTP summaries.

The raw log-probability payload is included because it is approximately 860 KB, contains no detected credentials or user identifiers, and permits a fuller audit of the forced-scoring extraction. The failed attempts are represented only by their small summaries and a clear explanation that neither sent a task-scoring HTTP request.

The repository excludes:

- the 2.5 GB GGUF model;
- llama.cpp and CUDA binaries or download archives;
- CUDA/Hugging Face/process caches;
- per-trial, loader, server, stdout, and stderr logs;
- `__pycache__`, `.pyc`, `.serena`, environment files, credentials, and tokens;
- aborted 32B experiment material and verbose local Ollama manifests;
- duplicate report binaries and exploratory files not used by a stated claim.

`ARTIFACTS.md` records source URLs and SHA-256 hashes for excluded model/runtime artifacts so the evidentiary chain remains checkable without committing gigabytes.

## Privacy and portability transformations

Sanitization operates only on publication copies. Original hashed artifacts remain untouched on E:.

Before commit:

1. Remove the 18 provider thread-ID values from `candidate_screen.jsonl`.
2. Replace the hard-coded Windows user-profile executable path in the portable broad-screen runner with a CLI argument, environment variable, or PATH lookup.
3. Make the portable report builder use repository-relative paths and font fallbacks instead of C:/E: constants.
4. Keep E:-specific Qwen scripts in `as-run/`; create parameterized portable copies rather than altering the exact originals.
5. Remove or omit user-profile paths, ephemeral PIDs, private provider metadata, and machine-local model manifests from derived/publication views.
6. Run a repository-wide search for credential patterns, bearer-auth material, private-key blocks, email addresses, Windows user-profile paths, provider thread IDs, and unexpected absolute paths.
7. Fail publication if any tracked file exceeds 10 MiB or matches an excluded cache/model/log pattern.

The private repository receives no open-source software license by default. `LICENSE-NOTICE.md` states that the repository is shared for take-home review and cites upstream model/runtime licenses. A public release and code license require a separate explicit decision.

## Verification contract

The single read-only verification command is:

```powershell
pwsh -NoProfile -File scripts/verify.ps1
```

It must exit nonzero on any failure and perform all of the following without starting a model server:

1. Run the existing 15 log-probability helper tests and the retained broad-screen unit tests.
2. Verify recorded SHA-256 hashes for the immutable schedule, validation, scores, raw payload, collection summary, final analyses, all four broad-screen evidence files, and report artifacts.
3. Assert 14 conditions x 8 candidate pairs = 112 unique scheduled and scored IDs with exact schedule/score coverage.
4. Require finite, nonpositive log probabilities and recompute raw, requested-aligned, and reward-aligned sign identities for every row.
5. Recompute the primary controllability-by-conflict DID, conflict current-minus-archived contrast, mirrored conflict summaries, transform reversal, and post hoc user-alignment decomposition, including the seeded descriptive pair bootstraps.
6. Reparse every frozen broad-screen response with the publication parser, derive parity without trusting stored outcome flags, and assert the behavioral cell counts and broad-screen totals: 58 calls across 13 model IDs, 50 strictly valid, and 0 valid odd.
7. Verify that the known collection-runner `summary.json` failure occurred only after 112/112 score collection and that `offline_finalization.json` is the authoritative completion record.
8. Run the privacy and maximum-file-size gates over the exact staged Git blobs and sizes in the index.

The existing offline finalizer is not used as the repository verifier because it hard-codes E: paths, checks live process state, and its `-VerifyOnly` branch refuses existing analysis outputs before reaching the switch. Its original version remains provenance; the repo-relative verifier is a new, non-mutating audit tool.

## Documentation behavior

`README.md` leads with the narrowly scoped conclusion: Qwen3-4B under this wrapper followed the user request rather than causally optimizing the displayed reward. It prominently distinguishes this from the source post's unavailable late capabilities-RL checkpoint and states that an odd output alone is not mechanism-identifying.

`METHODOLOGY.md` explains the causal logic of current versus archived controllability, mirrored requested/reward parity, transformed scored values, explicit-maximize positive controls, and matched-candidate log probabilities. It labels pair-bootstrap intervals as descriptive across eight fixed pairs and labels the user-alignment decomposition as post hoc.

`ARTIFACTS.md` records exact model/runtime hashes, versions, excluded sizes, and source locations. The audit note explains both pre-HTTP failures and the successful collection runner's later offline-summary bug without presenting them as model failures.

## Publication and remote verification

Publication uses the authenticated GitHub web interface to create a private, empty `odd-number-model-forensics` repository. Existing SSH authentication is then used to add `origin` and push `main`.

After creating a sanitized root or squashed release history, run `scripts/history-privacy-check.ps1` with the explicitly approved release author name, release email, and every ref intended for push. This separate pre-push gate checks all reachable commit identities and every reachable blob/path against the same privacy, forbidden-path, binary exemption, and size rules; it is intentionally not part of the ordinary verifier while unsafe development history remains reachable.

Before reporting success:

1. Verify the staged repository with the one-command verifier.
2. Run the all-history privacy gate over every ref intended for push and the approved sanitized release identity.
3. Inspect `git status`, the complete tracked-file list, object sizes, and secret/path scan output.
4. Review the diff from the design-only commit to the publication commit.
5. Push `main` over SSH.
6. Verify `git ls-remote origin`, open the private repository, and confirm the README, report, figures, and verification instructions render correctly.
7. Perform a fresh clone into a separate E: directory and run both the verifier and all-history privacy gate there.

The E: experiment tree is not deleted after repository publication alone. Deletion occurs only after the GitHub remote, Google Doc, email handoff, and final retained deliverables are all verified. The deletion target remains the exact named directory `E:\Temp\spar-odd-number-20260823`.

## Success criteria

The repository is complete when it is private on GitHub, cloneable over the configured authentication path, under 10 MiB per tracked file, free of detected credentials/user identifiers, reproducible with one read-only command, explicit about null and post hoc findings, and linked as supporting material rather than relied on for the report's main argument.
