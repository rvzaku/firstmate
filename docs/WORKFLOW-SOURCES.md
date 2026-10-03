# Workflow sources

This workflow is product agnostic. Product-specific knowledge belongs in private data and each product's own repository. Firstmate discovers and uses those local instructions without embedding their domain rules.
`bin/fm-lint.sh` enforces this: it fails when tracked files, or tracked symlink targets, name a project in the private `data/projects.md` registry. `tests/fm-lint.test.sh` covers the matching rules.

## Verified practices

These are short paraphrases of the dated primary sources. They describe the published practices reviewed for this alignment.

### Poteto

- Provide a reusable verification skill with a CLI, execution evidence, and a maintained feature map. [Trust workflow talk](https://x.com/poteto/status/2102050467505430555), 2026-09-21.
- Prevent repeated errors in the earliest effective layer. Prefer safe design, then static checks, then rules and skills, with style guidance last. Keep one preferred path and remove workarounds. [Trust workflow talk](https://x.com/poteto/status/2102050467505430555), 2026-09-21.
- Enforce architecture boundaries with dependency checks. Use existing event sources and tools for bounded work. [Trust workflow talk](https://x.com/poteto/status/2102050467505430555), 2026-09-21.

### Kun Chen

- Route by task after reading context. Match reasoning effort to uncertainty. Use medium for defined work and xhigh for ambiguous planning or investigation. [Task-level routing](https://x.com/kunchenguid/status/2103895901140042044), 2026-09-26; [reasoning effort](https://x.com/kunchenguid/status/2103325882752598078), 2026-09-25.
- Keep human preferences human-written. Use corroborated transcripts to propose small memory changes, then review them and check behavior against a separate evaluation set. [Your AGENTS.md is a neural net](https://blog.kunchenguid.com/p/your-agentsmd-is-a-neural-net), 2026-08-23; [backpass case study](https://x.com/kunchenguid/status/2104241432467067343), 2026-09-27.
- Prefer compact, current tool interfaces and durable isolated work with review and validation gates. [Firstmate snapshot](https://github.com/kunchenguid/firstmate/tree/87fa81b8b7f6912f84658d52d816bb9bcc2c5da6), 2026-10-02; [axi snapshot](https://github.com/kunchenguid/axi/tree/e7dd8fab88c06f6df28b3682056c6ee0f87cb68d), 2026-10-02.
- Compact at settled boundaries and consider a fresh session after long idle periods when context costs are high. [Cache and idle advice](https://x.com/kunchenguid/status/2101872626968969713), 2026-09-21.

### Matt Pocock

- Keep skills small, composable, adaptable across models, and easy to trigger. Keep human choices and approval gates explicit. [Skills for real engineers](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60), snapshot 2026-09-29.
- Clarify unclear intent, then split work into complete, independently verifiable slices with explicit blockers. [Five skills used every day](https://www.aihero.dev/5-agent-skills-i-use-every-day), updated 2026-03-16; [repository skills](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60), snapshot 2026-09-29.
- Put behavior behind small public interfaces. Test through those interfaces. Reproduce bugs with a red-capable feedback loop before causal investigation. [Codebases agents love](https://www.aihero.dev/how-to-make-codebases-ai-agents-love), updated 2026-02-26; [repository skills](https://github.com/mattpocock/skills/tree/d81f3a183412e71a5b1e84ca21bc1a35eea03a60), snapshot 2026-09-29.
- Intent is the main bottleneck as models improve. Use concise shared terms to express domain intent, ask questions that reveal missing requirements, and combine compatible skills. [Lauren Tan and Matt Pocock talk](https://x.com/0xCarnagee/status/2106080060834787463), 2026-10-02.

### Lauren Tan (Poteto)

- Put deterministic browser automation, traces, and snapshots behind a reusable skill CLI. Keep agent judgment outside the CLI, and maintain an automatically updated feature map for each product. [Lauren Tan and Matt Pocock talk](https://x.com/0xCarnagee/status/2106080060834787463), 2026-10-02.
- As models improve, remove script-level implementation detail from skills while retaining the workflow. Convert repeated failures into safer structure, static checks, or one conventional path. [Lauren Tan and Matt Pocock talk](https://x.com/0xCarnagee/status/2106080060834787463), 2026-10-02.
- Sample landed work on a schedule and queue patterns for later review. Fix environment causes when several agents repeat a shortcut, and avoid policy changes for one-off mistakes. [Lauren Tan and Matt Pocock talk](https://x.com/0xCarnagee/status/2106080060834787463), 2026-10-02.
- Connect bounded agent work to external signals, reproduce reports against the main branch with the product verification skill, and use observed data to find human bottlenecks. Batch related reports around common causes. [Lauren Tan and Matt Pocock talk](https://x.com/0xCarnagee/status/2106080060834787463), 2026-10-02.
- Mine correction moments from transcripts for reusable checks or skills. Keep skill sets adaptable, and use recall to transfer relevant earlier context. [Lauren Tan and Matt Pocock talk](https://x.com/0xCarnagee/status/2106080060834787463), 2026-10-02.
- Full autopilot with repeated real-app verification can fit verifiable domains. One-way-door changes need strong checks, and unverifiable domains have no general automation answer. Review after landing can guide reverts or lint rules. [Lauren Tan and Matt Pocock talk](https://x.com/0xCarnagee/status/2106080060834787463), 2026-10-02.

### Andrej Karpathy

- State observable success criteria and use test or browser feedback. Watch assumptions, conceptual errors, needless abstractions, and unrelated edits. [Coding-agent notes](https://x.com/karpathy/status/2015883857489522876), 2026-01-26.
- Compare changes against a measured baseline. Promote small-scale improvements only after checking them at the target scale. [Agents iterating on nanochat](https://x.com/karpathy/status/2029701092347630069), 2026-03-05; [autoresearch results](https://x.com/karpathy/status/2031135152349524125), 2026-03-09.
- For bounded experiments, fix the evaluator, limit editable scope, record each result, use equal budgets, and keep or discard by evidence. Prefer simpler changes when results tie. [autoresearch program](https://github.com/karpathy/autoresearch/blob/228791fb499afffb54b46200aca536f79142f117/program.md), snapshot 2026-03-25.

## Practice owners

An owner is the current place for the practice. A gap names the tracked backlog item from the alignment record.

| Practice | Firstmate owner or gap |
| --- | --- |
| Product-local verification skill and feature map | The product repository owns the CLI and map. `AGENTS.md` requires intake discovery and records both locations in the task note. |
| Prevent repeated mistakes by design, then static checks, rules or skills, and style text last | `.agents/skills/firstmate-coding-guidelines/SKILL.md`; existing guards and project-local checks enforce it. |
| Route work by context and reasoning needs | `config/crew-dispatch.json`, `bin/fm-dispatch-resolve.sh`, and `harness-adapters`; current preferences stay in private configuration. |
| Use medium for defined work and xhigh for ambiguity | `.agents/skills/harness-adapters/references/common/model-and-effort.md`. |
| Keep skills small, triggered, and composable | `.agents/skills/` descriptions and `.agents/skills/firstmate-coding-guidelines/SKILL.md`. |
| Define observable success and use the real feedback loop | `AGENTS.md`, `bin/fm-brief.sh`, and `bin/fm-dod-lib.sh`. |
| Clarify unclear intent and record the answer before building | `bin/fm-brief.sh` and `bin/fm-dod-lib.sh`; `bin/fm-spawn.sh` refuses a new ship brief without an `Intent check:` line. |
| Reproduce a bug before diagnosing its cause | `.agents/skills/diagnostic-reasoning/SKILL.md`. |
| Use small interfaces and test behavior through them | `.agents/skills/firstmate-coding-guidelines/SKILL.md`. |
| Keep work in complete, verifiable slices with explicit blockers | `AGENTS.md` decomposition guidance and the existing backlog dependency model. |
| Sample landed work and queue patterns for review | `bin/fm-gardener.sh` samples the newest closed-task pipeline findings into a ranked candidate-cluster report that firstmate reviews before filing any lint-rule task. |
| Mine correction transcripts for workflow updates | Gap: `fm-align-maintenance-loop`. |
| Trigger bounded triage from external signals | Existing process-event sources. |
| Fuzz per-PR verification with real-app verifier agents | The selected no-mistakes path. |
| Maintain isolated work, compact tool output, and validation gates | `AGENTS.md`, `bin/fm-spawn.sh`, and the selected delivery path. Compaction advice review gap: `fm-align-maintenance-loop`. |
| Propose memory changes from corroborated evidence and validate separately | Gap: `fm-align-maintenance-loop` and `fm-backpass-memory`. Human preferences remain protected. |
| Remove workarounds and maintain a preferred pattern | `.agents/skills/firstmate-coding-guidelines/SKILL.md` owns the correction-to-check handoff, and `bin/fm-gardener.sh` reports recurring finding clusters as candidates for a cause review. |
| Use measured baselines and bounded experiment records | The task specification and selected validation owner; apply only to authorized experiment work. |

## Trust order

When an agent repeats a mistake, fix it at the earliest effective layer:

1. Make the mistake impossible by design.
2. Add a static check when design cannot prevent it.
3. Add a rule or skill when a check cannot express the needed judgment.
4. Use style text only as the last layer.

## Differences and choice

The authors describe practices for different contexts. Poteto reports a team-wide comment ban, while Karpathy warns against deleting useful comments. Matt keeps some skill steps and test seams under human choice, while Kun and Firstmate support bounded autonomous work. Karpathy's research loop continues within an approved experiment, while production work must stop at repeated blockers. Matt's full-suite workflow differs from Firstmate's targeted local checks and broad CI. Tan reviews after landing in her full-autopilot workflow, while Firstmate keeps the selected delivery path's check at the exact head before merge.

Keep interface, license, and safety comments. Remove workaround narration by fixing its cause. Clarify genuinely ambiguous intent and honor explicit approval gates. Continue authorized bounded work, but keep production blocker escalation. Use autonomous experiments only with a defined scope, baseline, evaluator, budget, and result record. Run targeted checks locally and require broad CI coverage before delivery.

## Universal standard

This document applies [G18 Knowledge and Decisions](https://github.com/rvzaku/universal-standards/blob/main/skills/universal-standards/references/04-evaluation-and-delivery.md), [G19 Autonomous Execution](https://github.com/rvzaku/universal-standards/blob/main/skills/universal-standards/references/04-evaluation-and-delivery.md), and [G22 Low Churn Engineering](https://github.com/rvzaku/universal-standards/blob/main/skills/universal-standards/references/05-standards-and-tools.md). It records evidence with sources, points to existing owners, and adds one linked entry point without duplicating the canonical workflow rules.
