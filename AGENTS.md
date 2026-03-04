# Lean 4 Theorem Proving

Use this guidance whenever editing Lean 4 proofs or debugging Lean builds. It prioritizes LSP-based inspection and mathlib search, with scripted primitives for sorry analysis, axiom checking, and error parsing.

## Core Principles

**Search before prove.** Many mathematical facts already exist in mathlib. Search exhaustively before writing tactics.

**Build incrementally.** Lean's type checker is your test suite—if it compiles with no sorries and standard axioms only, the proof is sound.

**Respect scope.** Follow the user's preference: fill one sorry, its transitive dependencies, all sorries in a file, or everything. Ask if unclear.

**Never change statements or add axioms without explicit permission.** Theorem/lemma statements, type signatures, and docstrings are off-limits unless the user requests changes. Inline comments may be adjusted; docstrings may not (they're part of the API). Custom axioms require explicit approval—if a proof seems to need one, stop and discuss.

## Typical Workflow

```
1. Inspect goals and errors    (LSP tools: lean_goal, lean_diagnostic_messages)
2. Search for existing lemmas   (lean_local_search, lean_leandex, lean_loogle, lean_leanfinder)
3. Attempt tactics              (lean_multi_attempt, direct file edits)
4. Verify                       (lean_diagnostic_messages per-edit → lake build)
5. Optimize (optional)          (golf proofs for brevity)
6. Checkpoint                   (build + axiom check + commit)
```

## LSP Tools (Preferred)

Sub-second feedback and search tools via Lean LSP MCP:

```
lean_goal(file, line)                           # See exact goal
lean_hover_info(file, line, col)                # Understand types
lean_local_search("keyword")                    # Fast local + mathlib (unlimited)
lean_leanfinder("goal or query")                # Semantic, goal-aware (10/30s)
lean_leandex("natural language")                # Semantic search (3/30s)
lean_loogle("?a → ?b → _")                      # Type-pattern (unlimited if local mode)
lean_hammer_premise(file, line, col)            # Premise suggestions for simp/aesop/grind (3/30s)
lean_state_search(file, line, col)              # Goal-conditioned lemma search (3/30s)
lean_multi_attempt(file, line, snippets=[...])  # Test multiple tactics
```

## Core Scripts

| Script | Purpose | Output |
|--------|---------|--------|
| `sorry_analyzer.py` | Find sorries with context | text (default), json, markdown, summary |
| `check_axioms_inline.sh` | Check for non-standard axioms | text |
| `smart_search.sh` | Multi-source mathlib search | text |
| `find_golfable.py` | Detect optimization patterns | JSON |
| `find_usages.sh` | Find declaration usages | text |

**Invocation contract:** Never run bare script names. Always use:
- Python: `python3 "lean4-skills/plugins/lean4/lib/scripts/script.py" ...`
- Shell: `bash "lean4-skills/plugins/lean4/lib/scripts/script.sh" ...`
- Report-only calls: add `--report-only` to `sorry_analyzer.py`, `check_axioms_inline.sh`, `unused_declarations.sh` — suppresses exit 1 on findings; real errors still exit 1.
- Keep stderr visible for Lean scripts (no `/dev/null` redirection), so real errors are not hidden.

## Automation Tactics

Try in order (stop on first success):
`rfl` → `simp` → `ring` → `linarith` → `nlinarith` → `omega` → `exact?` → `apply?` → `grind` → `aesop`

Note: `exact?`/`apply?` query mathlib (slow). `grind` and `aesop` are powerful but may timeout.

## Type Class Patterns

```lean
-- Local instance for this proof block
haveI : MeasurableSpace Ω := inferInstance
letI : Fintype α := ⟨...⟩

-- Scoped instances (affects current section)
open scoped Topology MeasureTheory
```

Order matters: provide outer structures before inner ones.

## Common Fixes

See [compilation-errors](lean4-skills/plugins/lean4/skills/lean4/references/compilation-errors.md) for error-by-error guidance (type mismatch, unknown identifier, failed to synthesize, timeout, etc.).

## Quality Gate

A proof is complete when:
- `lake build` passes
- Zero sorries in agreed scope
- Only standard axioms (`propext`, `Classical.choice`, `Quot.sound`)
- No statement changes without permission

Verification ladder: `lean_diagnostic_messages(file)` per-edit → `lake env lean <path/to/File.lean>` file gate (run from project root) → `lake build` project gate only. See [cycle-engine: Build Target Policy](lean4-skills/plugins/lean4/skills/lean4/references/cycle-engine.md#build-target-policy).

## References

All reference docs live under `lean4-skills/plugins/lean4/skills/lean4/references/`.

**Cycle Engine:** [cycle-engine](lean4-skills/plugins/lean4/skills/lean4/references/cycle-engine.md) — shared prove/autoprove logic (stuck, deep mode, falsification, safety)

**LSP Tools:** [lean-lsp-server](lean4-skills/plugins/lean4/skills/lean4/references/lean-lsp-server.md) (quick start), [lean-lsp-tools-api](lean4-skills/plugins/lean4/skills/lean4/references/lean-lsp-tools-api.md) (full API — grep `^##` for tool names)

**Search:** [mathlib-guide](lean4-skills/plugins/lean4/skills/lean4/references/mathlib-guide.md) (read when searching for existing lemmas), [lean-phrasebook](lean4-skills/plugins/lean4/skills/lean4/references/lean-phrasebook.md) (math→Lean translations)

**Errors:** [compilation-errors](lean4-skills/plugins/lean4/skills/lean4/references/compilation-errors.md) (read first for any build error), [instance-pollution](lean4-skills/plugins/lean4/skills/lean4/references/instance-pollution.md) (typeclass conflicts — grep `## Sub-` for patterns), [compiler-guided-repair](lean4-skills/plugins/lean4/skills/lean4/references/compiler-guided-repair.md) (escalation-only repair — not first-pass)

**Tactics:** [tactics-reference](lean4-skills/plugins/lean4/skills/lean4/references/tactics-reference.md) (tactic lookup — grep `^### TacticName`), [grind-tactic](lean4-skills/plugins/lean4/skills/lean4/references/grind-tactic.md) (SMT-style automation — when simp can't close), [simproc-patterns](lean4-skills/plugins/lean4/skills/lean4/references/simproc-patterns.md) (custom deterministic rewrites for simp), [tactic-patterns](lean4-skills/plugins/lean4/skills/lean4/references/tactic-patterns.md), [calc-patterns](lean4-skills/plugins/lean4/skills/lean4/references/calc-patterns.md), [simp-hygiene](lean4-skills/plugins/lean4/skills/lean4/references/simp-hygiene.md)

**Proof Development:** [proof-templates](lean4-skills/plugins/lean4/skills/lean4/references/proof-templates.md), [proof-refactoring](lean4-skills/plugins/lean4/skills/lean4/references/proof-refactoring.md) (28K — grep by topic), [sorry-filling](lean4-skills/plugins/lean4/skills/lean4/references/sorry-filling.md)

**Optimization:** [proof-golfing](lean4-skills/plugins/lean4/skills/lean4/references/proof-golfing.md) (includes bounded LSP lemma replacement; bulk rewrites are context-filtered and regression-reverting; escalates to axiom-eliminator), [proof-golfing-patterns](lean4-skills/plugins/lean4/skills/lean4/references/proof-golfing-patterns.md), [proof-golfing-safety](lean4-skills/plugins/lean4/skills/lean4/references/proof-golfing-safety.md), [performance-optimization](lean4-skills/plugins/lean4/skills/lean4/references/performance-optimization.md) (grep by symptom), [profiling-workflows](lean4-skills/plugins/lean4/skills/lean4/references/profiling-workflows.md) (diagnose slow builds/proofs)

**Domain:** [domain-patterns](lean4-skills/plugins/lean4/skills/lean4/references/domain-patterns.md) (25K — grep `## Area`), [measure-theory](lean4-skills/plugins/lean4/skills/lean4/references/measure-theory.md) (28K), [axiom-elimination](lean4-skills/plugins/lean4/skills/lean4/references/axiom-elimination.md)

**Style:** [mathlib-style](lean4-skills/plugins/lean4/skills/lean4/references/mathlib-style.md), [verso-docs](lean4-skills/plugins/lean4/skills/lean4/references/verso-docs.md) (Verso doc comment roles and fixups)

**Custom Syntax:** [lean4-custom-syntax](lean4-skills/plugins/lean4/skills/lean4/references/lean4-custom-syntax.md) (read when building notations, macros, elaborators, or DSLs), [metaprogramming-patterns](lean4-skills/plugins/lean4/skills/lean4/references/metaprogramming-patterns.md) (MetaM/TacticM API — composable blocks, elaborators), [scaffold-dsl](lean4-skills/plugins/lean4/skills/lean4/references/scaffold-dsl.md) (copy-paste DSL template)

**Quality:** [linter-authoring](lean4-skills/plugins/lean4/skills/lean4/references/linter-authoring.md) (project-specific linter rules), [ffi-patterns](lean4-skills/plugins/lean4/skills/lean4/references/ffi-patterns.md) (C/ObjC bindings via Lake)

**Workflows:** [agent-workflows](lean4-skills/plugins/lean4/skills/lean4/references/agent-workflows.md), [subagent-workflows](lean4-skills/plugins/lean4/skills/lean4/references/subagent-workflows.md), [command-examples](lean4-skills/plugins/lean4/skills/lean4/references/command-examples.md), [learn-pathways](lean4-skills/plugins/lean4/skills/lean4/references/learn-pathways.md) (intent taxonomy, game tracks, source handling)
