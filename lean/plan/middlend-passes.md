# Middlend Passes — Why Each One Is Needed for Lean 4

All 13 passes are needed for the same reasons as Rocq.

| Pass | Lean 4 reason |
|---|---|
| `Ite` | Normalise conditionals to `if e then a else b` before printing |
| `LetIntro` | Eliminate let-premises; Lean 4 `inductive` constructors have no `let` |
| `TypeFamilyRemoval` | Convert type families to sum types; simplifies `inductive` emission |
| `Undep` | Replace indexed types with standalone types + well-formedness predicates |
| `Totalize` | Lean 4 `def` requires termination; partial functions must be made total or `partial` |
| `Else` | Eliminate `otherwise` premises before printing |
| `ElseSimp` | Simplify generated `otherwise` branches |
| `Uncaseremoval` | Eliminate `uncase` expressions; Lean 4 has no analog |
| `SubExpansion` | Expand subtype matching into explicit coercions |
| `Sub` | Synthesise `Coe` instances; required before `DefToRel` |
| `DefToRel` | Convert some function definitions to inductive relations for cleaner emission |
| `Sideconditions` | Infer side conditions needed as hypotheses in `inductive` constructors |
| `AliasDemut` | Lift type aliases out of `mutual` groups (Lean 4 `mutual` cannot contain `abbrev`) |
| `ImproveIds` | Disambiguate identifiers before Lean-specific renaming |

## Pass selection in `main.ml`

```ocaml
| Lean ->
  enable_pass Ite;
  enable_pass LetIntro;
  enable_pass TypeFamilyRemoval;
  enable_pass Undep;
  enable_pass Totalize;
  enable_pass Else;
  enable_pass ElseSimp;
  enable_pass Uncaseremoval;
  enable_pass SubExpansion;
  enable_pass Sub;
  enable_pass DefToRel;
  enable_pass Sideconditions;
  enable_pass AliasDemut;
  enable_pass ImproveIds
```
