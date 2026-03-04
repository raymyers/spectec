# Phase 4 — Expression and Function Rendering

*Estimated: ~2 days*

## Environment and setup

Same `rocq_env` pattern, renamed `lean_env`:

```ocaml
type lean_env = {
  mutable tf_set  : StringSet.t;   (* type-family ids *)
  mutable il_env  : Il.Env.t;
  mutable proj_set: StringSet.t;   (* projection / coercion functions *)
  mutable step_rel: string option; (* id of the Step relation, once detected *)
}
```

`register_hints` is unchanged; it reads `HintD` annotations to populate
`tf_set` and `proj_set`.

## Operator mappings

| IL op | Rocq | Lean 4 |
|---|---|---|
| `NotOp` | `negb ` | `!` |
| `PlusOp` | `` | `+` |
| `MinusOp` | `0 - ` | `-` |
| `AndOp` | ` && ` | ` && ` |
| `OrOp` | ` \|\| ` | ` \|\| ` |
| `ImplOp` | ` -> ` | ` → ` |
| `EquivOp` | ` <-> ` | ` ↔ ` |
| `AddOp` | ` + ` | ` + ` |
| `SubOp` | ` - ` | ` - ` |
| `MulOp` | ` * ` | ` * ` |
| `DivOp` | ` / ` | ` / ` |
| `ModOp` | ` mod ` | ` % ` |
| `PowOp` | ` ^ ` | ` ^ ` |
| `EqOp` | ` == ` | ` == ` |
| `NeOp` | ` != ` | ` != ` |
| `LtOp` | ` < ` | ` < ` |
| `GtOp` | ` > ` | ` > ` |
| `LeOp` | ` <= ` | ` ≤ ` |
| `GeOp` | ` >= ` | ` ≥ ` |

## Expression nodes

| IL node | Rocq output | Lean 4 output |
|---|---|---|
| `VarE id` | `id` | `id` |
| `BoolE b` | `true`/`false` | `true`/`false` |
| `NumE n` | `n` | `n` |
| `TextE s` | `"s"` | `"s"` |
| `TupE []` | `()` | `()` |
| `TupE es` | `(e1, e2, e3)` | `(e1, e2, e3)` |
| `ProjE (e, 0)` | `fst` chain | `e.1` |
| `ProjE (e, i)` | `fst`/`snd` chain | `e.i` (1-indexed) |
| `CaseE (m, e) LHS` | `ConstructorName e` | `ConstructorName e` |
| `CaseE (m, e) RHS` | `(ConstructorName _ e)` | `(ConstructorName e)` |
| `OptE (Some e)` | `(Some e)` | `.some e` |
| `OptE None` | `None` | `.none` |
| `TheE e` | `(!(e))` | `(the! e)` ¹ |
| `StrE fields` | `{\ f := v; ... \|}` | `{ f := v, ... }` |
| `DotE (e, a)` | `(field e)` | `e.field` |
| `CompE (e1, e2)` | `(e1 @@ e2)` | `(e1 ++ e2)` |
| `ListE []` | `[:: ]` | `[]` |
| `ListE es` | `[:: e1; e2; ...]` | `[e1, e2, ...]` |
| `LiftE e` | `(option_to_list e)` | `(e.toList)` |
| `MemE (e1, e2)` | `(e1 \in e2)` | `(e1 ∈ e2)` |
| `LenE e` | `(\|e\|)` | `e.length` |
| `CatE (e1, e2)` | `(e1 ++ e2)` | `(e1 ++ e2)` |
| `IdxE (e1, e2)` | `(e1 [\| e2 \|])` | `e1[e2]!` |
| `SliceE (e1, e2, e3)` | `(list_slice e1 e2 e3)` | `(e1.extract e2 (e2 + e3))` ² |
| `UpdE (e1, p, e2)` | RecordUpdate `<\|` `\|>` | `{ e1 with p := e2 }` |
| `ExtE (e1, p, e2)` | `list_update_func` | `listExtend e1 p e2` ³ |
| `CallE (id, args)` | `(id arg1 arg2)` | `(id arg1 arg2)` |
| `IterE (e, (ListN n _, []))` | `(seq.mkseq f n)` | `(List.range n).map f` |
| `IterE (e, (_, [q]))` | `(seq.map f xs)` | `(xs.map f)` |
| `IterE (e, (_, [q1,q2]))` | `(list_zipWith f xs ys)` | `(List.zipWith f xs ys)` |
| `IfE (e1, e2, e3)` | `(if e1 then e2 else e3)` | `(if e1 then e2 else e3)` |
| `CvtE (e, _, nt2)` | `(e : T)` | `(e : T)` |

¹ `the!` is defined in the preamble as `def the! [Inhabited α] : Option α → α := Option.getD default`  
² `List.extract` is `drop i ∘ take j`; define as preamble helper if not in Mathlib  
³ `listExtend` is a preamble helper for the path-extension operations

## `IterE` with multiple quantifiers

The Rocq backend dispatches on the number of quantifiers using
`iter_exp_lst_funcs = ["seq.map"; "list_zipWith"; "list_map3"]`.
Lean 4 equivalents:

```ocaml
let iter_list_funcs = ["List.map"; "List.zipWith"; "List.zipWith3"]  (* custom for 3 *)
let iter_opt_funcs  = ["Option.map"; "Option.map₂"; "Option.map₃"]  (* preamble helpers *)
```

## Path updates (`UpdE` / `ExtE`)

Rocq uses the `RecordUpdate` library (`<| f := v |>`).
Lean 4 has native record update `{ r with f := v }`.
For list-path updates (`IdxP`, `SliceP`) emit helpers defined in the
preamble:

```lean
def listUpdate {α} (l : List α) (n : Nat) (y : α) : List α := ...
def listSlice {α} (l : List α) (i j : Nat) : List α := ...
def listSliceUpdate {α} (l : List α) (i j : Nat) (u : List α) : List α := ...
def listExtendFunc {α} (l : List α) (n : Nat) (f : α → α) : List α := ...
```

## Function definitions — `DecD`

| Clause pattern | Lean 4 output |
|---|---|
| No clauses | `axiom id : T` |
| `[{DefD ([], [], exp, _)}]` — single, no args, no prems | `def id : T := exp` |
| Clauses with premises | `axiom id : T  -- partial; needs proof` |
| Clauses without premises, multiple | `partial def id (params) : T :=\n  match ... with\n  \| ...` |
| Projection function (in `proj_set`) | emit `def` + `instance : Coe A B := ⟨id⟩` |

All multi-clause definitions start with `partial def`; a later cleanup pass
can replace with `def` + `termination_by` where appropriate.

### Mutual function blocks (`RecD` containing `DecD`)
```lean
mutual
partial def a (params) : TA := ...
partial def b (params) : TB := ...
end
```

### Projection coercions
```lean
instance : Coe SrcType DstType := ⟨projFuncName⟩
```

## Quant / param rendering

| IL param | Lean 4 |
|---|---|
| `ExpP (id, t)` | `(id : T)` |
| `TypP id` | `(id : Type)` |
| `DefP (id, ps, t)` | `(id : P1 → P2 → T)` |
| `GramP` | comment |

## `string_of_script` — top-level entry point

```ocaml
let string_of_script (il : script) =
  !env_ref.il_env <- Il.Env.env_of_script il;
  List.iter (register_hints !env_ref) il;
  let il' = Disamb.transform il in
  preamble ^
  "-- Generated Code\n\n" ^
  String.concat "" (List.filter_map filter_def il'
                    |> List.map (string_of_def true false)) ^
  lts_section !env_ref.step_rel ^
  "\nend Wasm\n"
```

### String-of-def dispatch

```
Rocq prefix          →  Lean 4 prefix
─────────────────────────────────────
"Inductive "         →  "inductive "
"Definition "        →  "def "
"Fixpoint "          →  "partial def "
"Axiom "             →  "axiom "
"Record "            →  "structure "
with\n\n             →  (inside mutual block)
.\n\n                →  \n\n  (no trailing dot)
```

Comments (`(* Type Alias Definition at: ... *)`) become `-- Type Alias Definition at: ...`.

## Checkpoint

`./spectec --lean spec/0.*.spectec` produces a Lean 4 file with well-formed
auxiliary function definitions.
