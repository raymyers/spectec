# Phase 6 — CSLib LTS Wiring

*Estimated: ~half a day*

A purely **additive** block appended after all generated definitions. It does
not change how any other definition is emitted.

## What CSLib provides

```lean
structure LTS (State : Type u) (Label : Type v) where
  Tr : State → Label → State → Prop

inductive LTS.MTr (lts : LTS State Label) :
    State → List Label → State → Prop where
  | refl  : lts.MTr s [] s
  | stepL : lts.Tr s₁ μ s₂ → lts.MTr s₂ μs s₃ →
            lts.MTr s₁ (μ :: μs) s₃
```

`lts.MTr` is the reflexive–transitive closure. All lemmas for splitting,
composing, and converting multi-step transitions come for free.

## Mapping the wasm spec

From the generated Rocq output:

```
config          := mk_config (state : State) (instrs : List Instr)
Step            : config → config → Prop    -- single step  (generated)
Steps           : config → config → Prop    -- multi-step   (generated, to be superseded)
```

The `Steps` relation is emitted faithfully from the spec. The CSLib section
then connects `Step` to CSLib as follows:

## Emitted LTS block (hardcoded suffix in `print.ml`)

```lean
/-!
## WebAssembly reduction as a Labelled Transition System (CSLib)

`wasmLTS` wraps the spec-generated `Step` relation as a CSLib `LTS` over
`Config` states with `Unit` labels (internal, unobservable transitions).

This gives multi-step reduction (`wasmLTS.MTr`), infinite traces (`wasmLTS.ωTr`),
bisimulation (`LTS.Bisimulation`), and reachability as standard CSLib definitions —
superseding the spec-generated `Steps` relation.
-/

/-- The WebAssembly single-step reduction as a CSLib LTS. -/
def wasmStep (s : Config) (_ : Unit) (s' : Config) : Prop := Step s s'

create_lts wasmStep wasmLTS

scoped lts_transition_notation wasmLTS

/-
Usage:
  s [()]⭢ s'    one reduction step       (= Step s s')
  s [μs]↠ s'   multi-step reduction     (= wasmLTS.MTr s μs s')
  wasmLTS.CanReach s s'                  reachability

Key lemmas from CSLib (all apply to wasmLTS.MTr):
  LTS.MTr.refl   : wasmLTS.MTr s [] s
  LTS.MTr.single : Step s s' → wasmLTS.MTr s [()] s'
  LTS.MTr.comp   : wasmLTS.MTr s μs1 t → wasmLTS.MTr t μs2 s' →
                   wasmLTS.MTr s (μs1 ++ μs2) s'
  LTS.MTr.split  : wasmLTS.MTr s (μs1 ++ μs2) s' →
                   ∃ t, wasmLTS.MTr s μs1 t ∧ wasmLTS.MTr t μs2 s'
-/
```

## `lts_section` in `string_of_script`

```ocaml
let lts_section = function
  | Some step_id -> render_lts_block step_id
  | None -> "-- Note: no Step relation detected; CSLib LTS not generated\n"
```

## Detection of `Step`

The printer must know the name of the top-level reduction relation so it can
reference it in the LTS block. Strategy (in order of preference):

1. **Hint annotation**: if a `RelD` carries `hint(step)`, register it in
   `lean_env.step_rel`. Emit the LTS block using that name.
2. **Name heuristic**: the relation named exactly `Step` (after disambiguation)
   is the wasm reduction relation. Fall back to this if no hint is present.
3. **Manual override**: add a `--lean-step-rel NAME` CLI flag so the user can
   specify the name if it changes.

## Checkpoint

`./spectec --lean spec/4.*.spectec` produces a file ending with the `wasmLTS`
definition; `create_lts wasmStep wasmLTS` compiles in Lean 4.
