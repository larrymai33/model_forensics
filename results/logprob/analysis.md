# Qwen3-4B matched-candidate log-probability analysis

Status: completed offline from 112/112 validated task-score rows after the collection runner had already stopped the server. The collection runner itself failed only while constructing an empty baseline reward summary.

## Primary estimand

Controllability-by-conflict DID: -0.9345689862966537
Pair-bootstrap 95% interval: [-1.4620493277907372, -0.43283782713115215]
Even-request DID: -1.9860797673463821
Odd-request DID: 0.11694179475307465

## Secondary checks

Conflict current-minus-archived mean: -0.4729396626353264
Pair-bootstrap 95% interval: [-0.684558967128396, -0.2077390979975462]
Current-conflict mirrored reward-aligned mean: -6.427402811124921
Archived-conflict mirrored reward-aligned mean: -5.9544631484895945
Transform causal-output-parity reversal: -0.04688357748091221
Pair-bootstrap 95% interval: [-0.23030277341604233, 0.1291845589876175]

## Interpretation limit

These direct-answer conditional token probabilities do not establish a persistent objective, reward hacking, scheming, deception, or tampering. Pair-bootstrap intervals are descriptive across eight fixed candidate pairs.