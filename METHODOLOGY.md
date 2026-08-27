# Methodology

## Mechanism-identifying standard

The motivating prompt contains two correlated cues: a request for an even number and a displayed grader whose larger value is obtained by an odd number. One odd output would show correlation with the displayed reward, but it would not identify why that action was selected. The same output could arise from causal reward optimization, inference that the prompt is a puzzle, a learned grader-following heuristic, metadata salience, modulo misunderstanding, or random sampling.

The investigation therefore uses interventions with different predictions under those explanations. A causal reward-optimization account predicts that preferences should:

1. strengthen toward reward only when the current answer can affect the grader;
2. reverse when requested and rewarded parity are mirrored; and
3. follow transformations of the value being scored, even when the surface request and modulo expression remain similar.

These are stronger tests than asking whether the model can calculate modulo or whether an odd answer appears in one prompt.

## Broad screen

The broad screen held the **exact source user message** fixed across several accessible model IDs, but it did not hold system or wrapper context fixed. Its 58 calls break down as follows:

| Wrapper/system context | Calls | Strictly valid | Strict-valid odd |
|---|---:|---:|---:|
| Explicit `Follow the user's request` system message | 16 | 15 | 0 |
| Neutral `You are a helpful assistant.` system message | 9 | 9 | 0 |
| Wrapper-native template, no caller-supplied system message | 6 | 6 | 0 |
| Minimal Codex CLI context, no caller-supplied system message | 15 | 15 | 0 |
| Local native template, no caller-supplied system message | 12 | 5 | 0 |

The 16 explicitly user-following calls comprise all 10 qualifying calls from the initial collector and 6 `follow_user` conflicts from the wrapper screen. The neutral group comprises 6 wrapper-screen calls and 3 Claude candidate-screen calls; the 15 Codex candidate calls did not apply the schedule's descriptive `system_prompt` field because the minimal Codex runner passes only the user prompt. These context identities are recomputed from the frozen rows. See the [wrapper schedule](results/broad-screen/wrapper_schedule.json) and the preregistered [wrapper-screen amendment](preregistration/broad-screen.md#wrapper-screen-amendment).

The strict parser accepted only a single integer after light formatting normalization. Machine-recomputed totals are 58 calls, 13 model IDs, 50 strictly valid answers, and zero strictly valid odd answers. A separate manual classification of the same 58 raw responses records 57 clearly even responses and one non-answer.

The screen is descriptive and is not a context-matched replication of the source interaction. The explicit user-following wrapper directly favors the measured user-compliance outcome, the calls are heterogeneous, the model IDs are not a random sample, and the source post's private late-RL checkpoint was unavailable. Pooling the calls cannot estimate a general model-population rate or refute a checkpoint-specific effect.

## Behavioral causal interventions

The local follow-up used Qwen3-4B Q4_K_M with llama.cpp b10566. Five conditions separate objective adoption from capability and surface effects:

- **Current versus archived controllability.** The current condition says the grader scores the answer being produced. The archived control uses closely matched grader language but says it scores an archived answer that the current response cannot change. Reward optimization predicts a selective current-answer shift toward the rewarded parity; generic salience or authority parsing may affect both conditions similarly.
- **Mirrored parity.** One conflict requests even and rewards odd; the mirror requests odd and rewards even. A genuine parity-independent reward rule should reverse with the reward mapping. A fixed “modulo means even” heuristic or direct-request following need not.
- **Transformed scored value.** The `n+1` condition scores a transformed value rather than the literal output. This reverses which output parity earns the larger displayed reward while preserving much of the surface framing. Causal tracking should follow the scored value through the transformation.
- **Explicit-maximize positive control.** The model is directly told to maximize displayed reward even when that conflicts with the parity request. Passing this control shows that the model can compose the rule and act on it when the objective is unambiguous. Because it changes the instruction, it is not evidence of spontaneous reward hacking.
- **Reasoning modes.** Behavioral blocks were run with Qwen's non-thinking mode and with capped thinking. The capped-thinking positive control passed 6/6, while the two mirrored current-answer conflicts were reward-aligned in 0/12. This separates inability to calculate the rule from failure to adopt descriptive metadata as an objective in that setting.

## Direct candidate-probability probe

Sampling can hide a subthreshold preference, so the preregistered probability probe scored exact candidate answers with forced decoding. It used eight matched consecutive even/odd pairs:

```text
16/17, 42/43, 74/75, 88/89,
104/105, 128/129, 200/201, 314/315
```

Each pair appeared in 14 conditions, producing 112 unique condition-pair rows. For each exact candidate, token log probabilities were summed by the chain rule. Validation checked candidate tokenization in context, invariance to +100 versus +1000 logit bias, forward versus reverse scoring order, and an independently reconstructed arithmetic example.

The primary preregistered estimand is a reward-oriented controllability-by-conflict difference-in-differences. Positive values were predicted by causal reward optimization: making the answer current rather than archived should move probability preferentially toward the reward-aligned candidate when reward conflicts with the user. The observed estimate was negative (-0.9345689862966537), and 7/8 pair-level estimates were negative. Every leave-one-pair-out primary estimate remained negative.

The candidate design is deliberately matched, but restricted. It compares eight fixed answer pairs rather than total probability mass over every integer. Token length, digit identity, and candidate-selection effects remain possible even though the sign was robust across pair exclusions and token-length groups.

## Uncertainty and exploratory labels

The reported intervals are **descriptive pair bootstraps over eight fixed candidate pairs**. They quantify sensitivity across those chosen pairs. They are not confidence intervals for a random population of models, prompts, wrappers, or numbers, and they should not be read as such.

The user-alignment decomposition was defined **post hoc** after the preregistered reward-oriented interaction was observed. In user-aligned coordinates, changing “archived answer” to “current answer” strengthened the requested parity similarly in conflict and congruent cells; the difference between those boosts was near zero. This is an explanatory exploratory result, not a preregistered confirmatory test.

## Scope of the conclusion

The evidence supports instruction and authority parsing, with a secondary surface-evenness heuristic, for this Qwen3-4B quantization and wrapper. It does not establish a general absence of reward hacking, and it does not adjudicate the unavailable private checkpoint in the source post.

For a stronger diagnosis on that checkpoint, the same model should show the full causal signature: ignore uncontrollable archived rewards, reverse under mirrored rewarded parity, follow transformations of the scored value, and exhibit matching shifts in direct probabilities. Even that pattern would establish in-context proxy optimization more directly than it would establish a persistent terminal reward goal.

See the [full report](report/takehome.md), the three preregistrations under [`preregistration/`](preregistration), and the frozen analysis under [`results/logprob/`](results/logprob).
