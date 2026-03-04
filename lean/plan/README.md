# Plan: `--lean` Backend for SpecTec (Lean 4 + CSLib)

Add a `--lean` flag to the `spectec` binary that emits Lean 4 files containing
WebAssembly syntax, auxiliary functions, typing relations, and reduction rules —
with a CSLib `LTS` instance for multi-step reduction, reachability, and
bisimulation reasoning.

The Rocq backend (`src/backend-rocq/`) is the direct template. ~70% transfers
with syntax substitutions; ~30% is replaced by Lean 4 idioms.

| Item | Detail |
|---|---|
| New source files | `src/backend-lean/disamb.ml`, `print.ml`, `dune` |
| Changed files | `src/exe-spectec/main.ml` (4 edits), `src/dune` (1 line) |
| Template | ~70% of `backend-rocq/print.ml` adapted with syntax substitutions |
| Key savings vs Rocq | `deriving` replaces ~45 lines of boilerplate per type; native record update; shorter preamble |
| Key addition vs Rocq | CSLib `LTS` block (~15 hardcoded lines) wired to the `Step` relation |
| Output | `wasm3.lean` — single Lean 4 file, `namespace Wasm`, CSLib import |
| Estimated effort | 5–7 developer-days for a working first version |

---

## Phases

### Phase 1 — Scaffolding  *(~2 hours)*

- [ ] Add `| Lean` to `target` in `main.ml`
- [ ] Register `--lean` CLI flag
- [ ] Copy `| Rocq ->` pass block; change label to `| Lean`
- [ ] Copy `| Rocq ->` output dispatch; call `Backend_lean.Print.string_of_script`
- [ ] Create `src/backend-lean/` with stub `dune` and stubs for `disamb.ml` / `print.ml`
- [ ] Add `(re_export backend_lean)` to `src/dune`
- [ ] `dune build` passes with no errors

**Checkpoint**: `./spectec --lean spec/*.spectec` produces `-- TODO`

→ Details: [phase1-scaffolding.md](phase1-scaffolding.md)

---

### Phase 2 — Disambiguator  *(~1 day)*

- [ ] Copy `backend-rocq/disamb.ml` → `backend-lean/disamb.ml`
- [ ] Replace `reserved_ids` with the Lean 4 set
- [ ] Replace `render_id` collision strategy (`res_` → `wasm_`)
- [ ] Add `to_pascal` and `to_camel` helpers
- [ ] Apply case conventions to type/constructor vs term-level atoms
- [ ] Unit-test on `0.1-aux.vars.spectec`: output ids are well-formed Lean 4 identifiers

**Checkpoint**: `./spectec --lean spec/0.1*.spectec spec/1.1*.spectec` prints disambiguated ids in Lean 4 case format

→ Details: [phase2-disambiguator.md](phase2-disambiguator.md)

---

### Phase 3 — Preamble + Type Rendering  *(~1 day)*

- [ ] Implement `preamble` string constant
- [ ] Implement `render_type` (IL types → Lean 4 types)
- [ ] Implement `render_typealias` → `abbrev Name := T`
- [ ] Implement `render_variant_typ` → `inductive ... deriving DecidableEq, Inhabited, Repr`
- [ ] Implement `render_record` → `structure ... where mk :: ...`
- [ ] Implement `render_extra_info` → `none` (no Rocq eq_dec proofs needed)

**Checkpoint**: `./spectec --lean spec/1.2*.spectec` produces well-formed Lean 4 type definitions

→ Details: [phase3-types.md](phase3-types.md)

---

### Phase 4 — Expression and Function Rendering  *(~2 days)*

- [ ] Implement `render_exp` (all operator mappings, expression nodes)
- [ ] Implement `render_function_def` → `partial def id (params) : T := match ...`
- [ ] Implement `render_axiom` → `axiom id : T`
- [ ] Implement `render_global_declaration` → `def id : T := exp`
- [ ] Implement projection coercion emission → `instance : Coe A B := ⟨id⟩`
- [ ] Implement mutual function blocks → `mutual ... end`
- [ ] Implement `string_of_script` entry point

**Checkpoint**: `./spectec --lean spec/0.*.spectec` produces well-formed auxiliary function definitions

→ Details: [phase4-expressions.md](phase4-expressions.md)

---

### Phase 5 — Relation Rendering  *(~1 day)*

- [ ] Implement `render_relation` → `inductive Name : T → Prop where | ...`
- [ ] Implement premise rendering (`IfPr`, `IterPr`, `RulePr`)
- [ ] Implement mutual inductive blocks
- [ ] Implement mixed `RecD` (def + inductive) mutual blocks

**Checkpoint**: `./spectec --lean spec/2.*.spectec` produces well-formed validation/typing `inductive Prop` definitions

→ Details: [phase5-relations.md](phase5-relations.md)

---

### Phase 6 — CSLib LTS Wiring  *(~half a day)*

- [ ] Implement `render_lts_block step_id`
- [ ] Implement `detect_step_rel` in `register_hints` (hint name `"step"`)
- [ ] Fall back to name heuristic: relation named `"Step"` after disambiguation
- [ ] Append `lts_section` after generated code in `string_of_script`

**Checkpoint**: `./spectec --lean spec/4.*.spectec` produces a file ending with `wasmLTS`; `create_lts wasmStep wasmLTS` compiles in Lean 4

→ Details: [phase6-lts.md](phase6-lts.md)

---

### Phase 7 — Full Spec Smoke Test  *(~half a day)*

- [ ] `./spectec --lean spec/wasm-3.0/*.spectec -o wasm3.lean`
- [ ] File is syntactically valid Lean 4
- [ ] No `sorry` except in `partial def` stubs
- [ ] All type, function, and relation names are valid Lean 4 identifiers
- [ ] Repeat for wasm-2.0

→ Details: [phase7-smoke-test.md](phase7-smoke-test.md)

---

### Phase 8 — Test Suite Integration  *(~half a day)*

- [ ] Add `spectec/test-lean/` mirroring `test-latex/` structure
- [ ] Add minimal test spec with expected output checked into the repo
- [ ] Add `dune runtest` integration (snapshot testing)
- [ ] Add to top-level `Makefile` `test` target

→ Details: [phase8-testing.md](phase8-testing.md)

---

## Deferred Work

→ Details: [deferred.md](deferred.md)

- **Termination**: Replace `partial def` with `def` + `termination_by` for structurally recursive functions
- **BitVec numerics**: Use `BitVec 32` / `BitVec 64` from Mathlib for modular arithmetic
- **Observable labels**: Extend `Label := Unit` for WASI / component model
- **Proof generation**: Port WasmCert soundness proof structure using CSLib LTS lemmas
- **CI**: Add `lake build` job on generated `wasm3.lean` with CSLib + Mathlib toolchain

---

## Reference

- [Middlend passes](middlend-passes.md) — Why each of the 13 passes is needed for Lean 4
