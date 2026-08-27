# Portable Qwen helpers

`screen_helpers.ps1` and `logprob_helpers.ps1` are path-independent helper libraries retained for offline testing and analysis. The repository does not include or invoke a portable model runner.

Any runner built around these helpers must require machine-specific model and server paths and may default only the publication output root:

```powershell
param(
    [string] $ModelPath,
    [string] $LlamaServerPath,
    [string] $OutputRoot = (Join-Path $PSScriptRoot '..\..\..\results')
)
```

`ModelPath` and `LlamaServerPath` are required inputs. Repository verification never starts a model, listener, server, runner, HTTP scoring request, or live-process check.

The scripts in `../as-run/` are immutable, machine-specific provenance and are not portable runners.
