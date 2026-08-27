# Artifact provenance

## Excluded model and runtime binaries

The model and runtime archives used for the local run are not committed. Each exceeds the repository's publication scope, and the model alone is far above the 10 MiB tracked-file limit. Exact identities are retained so an auditor can obtain the official releases independently:

| Excluded artifact | Size (bytes) | SHA-256 |
|---|---:|---|
| `Qwen3-4B-Q4_K_M.gguf` | 2,497,280,256 | `7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5` |
| `llama-b10566-bin-win-cuda-12.4-x64.zip` | 250,963,000 | `6805bde00c16006cdcc757a132f7ba95d82b5f1e6ddba7e1d91f80c4e6930dcb` |
| `cudart-llama-bin-win-cuda-12.4-x64.zip` | 391,443,627 | `8c79a9b226de4b3cacfd1f83d24f962d0773be79f1e7b75c6af4ded7e32ae1d6` |

Official sources and release records:

- [Qwen3-4B GGUF repository](https://huggingface.co/Qwen/Qwen3-4B-GGUF)
- [Qwen3-4B architecture/model card](https://huggingface.co/Qwen/Qwen3-4B)
- [llama.cpp b10566 release](https://github.com/ggml-org/llama.cpp/releases/tag/b10566)
- [GitHub artifact attestation for the llama.cpp release](https://github.com/ggml-org/llama.cpp/attestations/42207505)

Upstream licenses remain with Qwen and llama.cpp. The repository contains no model weights, runtime binaries, CUDA archive, caches, server logs, or download directory.

## Publication-copy preservation

The Qwen evidence package was built from an explicit allowlist. The source-to-index audit found **47/47 exact destinations** byte-for-byte identical to both their source artifacts and staged Git blobs. These exact copies include prompts, as-run scripts, schedules, results, summaries, probability payloads, analyses, and compact failed-attempt summaries.

Three retained test files were intentionally adapted only at their helper import line so they resolve the repository's portable helper location. Their test logic was unchanged. Portable helper files are publication variants kept separately from immutable machine-specific as-run provenance. Everything outside the allowlist—including models, runtimes, downloads, caches, logs, and incomplete experiments—was excluded.

## Failed pre-HTTP attempts

The two files in [`results/audit/failed-pre-http/`](results/audit/failed-pre-http) preserve compact summaries of setup attempts that failed before any scoring request was sent:

- `v1-summary.json`: the loader log did not verify 37/37 GPU-layer offload within the shared 120-second startup window; no HTTP request was sent and zero condition-pair scores were collected.
- `v2-summary.json`: the same startup verification gate stopped the attempt before HTTP, even though its retained resource summary later recorded full 37/37 offload; zero condition-pair scores were collected.

These are runner/setup failures, not model-behavior observations, and they are excluded from the 112-row analysis.

## Complete collection and authoritative finalization

The successful collection run passed its validation checks, verified 37/37 GPU-layer offload, and collected all **112/112 planned condition-pair scores**. After collection and server cleanup, the collection runner failed while constructing an empty baseline-reward summary, producing:

```text
Cannot bind argument to parameter 'Values' because it is null.
```

The original failure record is preserved as [`provenance/collection-summary.original.json`](provenance/collection-summary.original.json). It attests that all 112 planned rows had already been collected, so its top-level `failed` status must not be read as an incomplete experiment.

[`results/logprob/offline_finalization.json`](results/logprob/offline_finalization.json) is the authoritative completion record. It was produced offline from the complete validated inputs after the server was stopped, verifies 112 unique schedule IDs, freezes input and output hashes, and records status `completed_offline_from_complete_validated_scores`. A byte-identical provenance copy is retained at [`provenance/offline-finalization.original.json`](provenance/offline-finalization.original.json).

The one-command verifier checks the collection failure exactly, confirms that it occurred after 112/112 score collection, and requires the authoritative offline finalization and its frozen hashes.
