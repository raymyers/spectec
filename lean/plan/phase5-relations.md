# Phase 5 — Relation Rendering

*Estimated: ~1 day*

The most direct translation from Rocq because Lean 4 has native inductive
propositions.

## Relation definitions — `RelD`

**Rocq output** (e.g. for `Instr_ok`):
```coq
Inductive Instr_ok : context -> instr -> instrtype -> Prop :=
  | nop : Instr_ok C NOP (mk_instrtype [] [])
  | unreachable : forall (t1_lst t2_lst : seq valtype),
      Instr_ok C UNREACHABLE (mk_instrtype t1_lst t2_lst)
  ...
```

**Lean 4 output**:
```lean
inductive InstrOk : Context → Instr → Instrtype → Prop where
  | nop : InstrOk c NOP (mkInstrtype [] [])
  | unreachable : ∀ (t1List t2List : List Valtype),
      InstrOk c UNREACHABLE (mkInstrtype t1List t2List)
  ...
  deriving Inhabited
```

### Differences from Rocq

- `Inductive` → `inductive`
- `:= \n\t| rule :` → `where\n  | rule :`
- `forall` → `∀`
- ` -> ` (premise separator) → ` →\n    `
- Final `.` → none (Lean 4 is indentation-delimited)
- `deriving Inhabited` (note: not `DecidableEq` — `Prop`-valued inductives do
  not need decidable equality)

## Premise rendering — `render_prem`

| IL prem | Lean 4 hypothesis in constructor |
|---|---|
| `IfPr e` | `(_ : e)` — anonymous hypothesis |
| `IterPr (List, [p])` | `(_ : List.Forall (fun x => P x) xs)` |
| `IterPr (List, [p1,p2])` | `(_ : List.Forall₂ (fun x y => P x y) xs ys)` |
| `IterPr (List, [p1,p2,p3])` | preamble `List.Forall₃` |
| `IterPr (Opt, [p])` | `(_ : optForall P x)` — preamble helper |
| `RulePr (rel_id, _, e)` | `(_ : RelName e1 e2 ...)` |
| `LetPr` | eliminated by `LetIntro` pass before reaching the printer |
| `ElsePr` | eliminated by `Else` / `ElseSimp` passes |

In `inductive` constructor positions, quantifiers become `∀ (id : T),`.

## Mutual inductive relations (`RecD` containing `RelD`)
```lean
mutual
inductive A where ...
inductive B where ...
end
```

## Mixed `RecD` (both `DecD` and `RelD`)

Lean 4 `mutual` blocks support mixing `def` and `inductive`:
```lean
mutual
partial def a (params) : TA := ...
inductive B where ...
end
```

## Checkpoint

`./spectec --lean spec/2.*.spectec` produces well-formed validation/typing
`inductive Prop` definitions.
