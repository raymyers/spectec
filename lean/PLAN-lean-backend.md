# Plan: `--lean` Backend for SpecTec (Lean 4 + CSLib)

## 1. Goal

Add a `--lean` flag to the `spectec` binary that, given any set of `.spectec`
source files, emits a single Lean 4 file containing:

- All WebAssembly **syntax** as `inductive` / `structure` / `abbrev` types with
  `deriving DecidableEq, Inhabited, Repr`
- All **auxiliary functions** as `def` or `partial def`
- All **typing / validation relations** as `inductive ... : ... → Prop where`
- All **reduction rules** as `inductive Step` plus a CSLib `LTS` instance that
  gives multi-step reduction, reachability, and bisimulation reasoning for free

The Rocq backend (`src/backend-rocq/`) is the direct template. Approximately
70 % of its code transfers with syntax substitutions; the remaining 30 % is
replaced by Lean 4 idioms (primarily decidable equality, records, mutual blocks,
and the CSLib LTS section).

---

## 2. New files

```
src/backend-lean/
  disamb.ml       identifier sanitiser (Lean 4 conventions)
  print.ml        IL → Lean 4 source printer
  dune
```

**`dune`**:
```
(library
  (name backend_lean)
  (libraries il middlend xl)
  (modules print disamb)
)
```

---

## 3. Changes to existing files

### `src/dune`
Add one line inside the `(libraries ...)` list:
```
(re_export backend_lean)
```

### `src/exe-spectec/main.ml`

**a) `target` type** — add one variant:
```ocaml
| Lean
```

**b) CLI flag** — add alongside `--rocq`:
```ocaml
"--lean", Arg.Unit (fun () -> target := Lean),
  " Generate Lean 4 definitions (CSLib LTS for semantics)";
```

**c) Pass selection** — copy the `| Rocq ->` block verbatim and change the
label. All 13 passes are needed for the same reasons as Rocq:
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

**d) Output dispatch**:
```ocaml
| Lean ->
  log "Lean Generation...";
  let code = Backend_lean.Print.string_of_script il in
  (match !odsts with
  | [] -> print_endline code
  | [odst] ->
    let oc = open_out odst in
    output_string oc code; close_out oc
  | _ -> error no_region "Lean backend: at most one -o file")
```

---

## 4. Middlend passes — why each one is needed

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

---

## 5. `disamb.ml`

Mirrors the structure of `backend-rocq/disamb.ml` exactly. Two functions are
changed: the reserved-name set and the case-conversion of atoms.

### 5.1 Reserved names

```ocaml
let reserved_ids = StringSet.of_list [
  (* Lean 4 keywords *)
  "abbrev"; "and"; "apply"; "as"; "attribute"; "axiom"; "by"; "calc";
  "class"; "constructor"; "decreasing_by"; "def"; "deriving"; "do";
  "else"; "end"; "example"; "export"; "extend"; "extern"; "false";
  "for"; "forall"; "fun"; "have"; "if"; "import"; "in"; "include";
  "inductive"; "infix"; "infixl"; "infixr"; "initialize"; "instance";
  "let"; "macro"; "match"; "mutual"; "namespace"; "noncomputable";
  "not"; "notation"; "obtain"; "of"; "open"; "opaque"; "or";
  "partial"; "postfix"; "prefix"; "private"; "protected"; "public";
  "return"; "run"; "section"; "set_option"; "show"; "sorry";
  "structure"; "suffices"; "syntax"; "termination_by"; "then";
  "theorem"; "true"; "type"; "universe"; "unless"; "variable";
  "where"; "with";
  (* Lean 4 Prelude / Std types that live in the global namespace *)
  "Nat"; "Int"; "Float"; "Bool"; "Unit"; "Char"; "String";
  "List"; "Array"; "Option"; "Prop"; "Type"; "Sort";
  "True"; "False"; "UInt8"; "UInt16"; "UInt32"; "UInt64";
]
```

Collision strategy: prefix with `wasm_` (terms) or `Wasm` (types/constructors),
matching the heuristic already used for `res_` in the Rocq backend.

```ocaml
let render_id id =
  if StringSet.mem id reserved_ids then "wasm_" ^ id
  else id
```

### 5.2 Atom case conventions

The Rocq backend leaves identifiers in their original mixed-case form.
Lean 4 conventions: **`PascalCase`** for types and constructors;
**`camelCase`** for term-level definitions.

Implement `to_pascal` and `to_camel` as post-processors applied after
the core disambiguation:

```ocaml
(* snake_case or ALLCAPS → PascalCase *)
let to_pascal s =
  String.split_on_char '_' s
  |> List.map (fun w ->
       if w = "" then ""
       else String.make 1 (Char.uppercase_ascii w.[0])
            ^ String.sub (String.lowercase_ascii w) 1 (String.length w - 1))
  |> String.concat ""

(* same → camelCase: lower first segment *)
let to_camel s =
  let p = to_pascal s in
  if p = "" then ""
  else String.make 1 (Char.lowercase_ascii p.[0]) ^ String.sub p 1 (String.length p - 1)
```

Apply `to_pascal` to `TypD` ids, `VariantT` constructor atoms, and
`StructT` type ids; apply `to_camel` to `DecD` ids, `RelD` ids and
`VarE` ids. (The IL `Env` tells us which ids denote types vs terms.)

### 5.3 Everything else

`t_exp`, `t_path`, `t_atom_opt`, `t_atom_new`, `t_mixop_new`, `t_inst`,
`t_def`, `t_rule_new`, `remove_overlapping_clauses`, and `transform` all
carry over from the Rocq disambiguator with no structural change — only the
`render_id` and atom-case functions differ.

---

## 6. `print.ml` — full rendering specification

### 6.1 Environment and setup

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

### 6.2 Type rendering — `render_type`

Direct substitution from the Rocq version:

| IL type | Rocq output | Lean 4 output |
|---|---|---|
| `VarT (id, [])` | `id` | `id` |
| `VarT (id, args)` | `(id arg1 arg2)` | `(id arg1 arg2)` |
| `BoolT` | `bool` | `Bool` |
| `NumT NatT` | `nat` | `Nat` |
| `NumT IntT` | `nat` | `Int` |
| `NumT RatT` | `nat` | `Rat` |
| `NumT RealT` | `nat` | `Float` |
| `TextT` | `string` | `String` |
| `TupT []` | `unit` | `Unit` |
| `TupT ts` | `T1 * T2 * T3` | `T1 × T2 × T3` |
| `IterT (t, Opt)` | `(option T)` | `Option T` |
| `IterT (t, _)` | `(seq T)` | `List T` |

### 6.3 Expression rendering — `render_exp`

#### Operators

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

#### Expression nodes

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

#### `IterE` with multiple quantifiers

The Rocq backend dispatches on the number of quantifiers using
`iter_exp_lst_funcs = ["seq.map"; "list_zipWith"; "list_map3"]`.
Lean 4 equivalents:

```ocaml
let iter_list_funcs = ["List.map"; "List.zipWith"; "List.zipWith3"]  (* custom for 3 *)
let iter_opt_funcs  = ["Option.map"; "Option.map₂"; "Option.map₃"]  (* preamble helpers *)
```

#### Path updates (`UpdE` / `ExtE`)

Rocq uses the `RecordUpdate` library (`<| f := v |>`).
Lean 4 has native record update `{ r with f := v }`.
For list-path updates (`IdxP`, `SliceP`) emit helpers defined in the
preamble exactly as in Rocq, but with Lean 4 syntax:

```lean
def listUpdate {α} (l : List α) (n : Nat) (y : α) : List α := ...
def listSlice {α} (l : List α) (i j : Nat) : List α := ...
def listSliceUpdate {α} (l : List α) (i j : Nat) (u : List α) : List α := ...
def listExtendFunc {α} (l : List α) (n : Nat) (f : α → α) : List α := ...
```

### 6.4 Premise rendering — `render_prem`

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

### 6.5 Quant / param rendering

| IL param | Rocq | Lean 4 |
|---|---|---|
| `ExpP (id, t)` | `(id : T)` | `(id : T)` |
| `TypP id` | `(id : Type)` | `(id : Type)` |
| `DefP (id, ps, t)` | `(id : P1 → P2 → T)` | `(id : P1 → P2 → T)` |
| `GramP` | comment | comment |

In `inductive` constructor positions, quantifiers become `∀ (id : T),`.

### 6.6 Type definitions

#### `AliasT`
```lean
-- Rocq: Definition name (quants) : Type := T.
abbrev Name (quants) := T
```

#### `VariantT` (inductive sum type)
```lean
-- Rocq: Inductive name ... := | Con1 : T1 | Con2 : T2 | ...
--       + HB.instance + Inhabited + eq_dec boilerplate (40+ lines per type)
inductive Name (quants) where
  | con1 : fields → Name
  | con2 : fields → Name
  deriving DecidableEq, Inhabited, Repr
```

This replaces ~45 lines of Rocq boilerplate per type with 1 `deriving` line.

#### `StructT` (record type)
```lean
-- Rocq: Record name := { f1 : T1; f2 : T2 } + Record/RecordUpdate boilerplate
structure Name (quants) where
  mk ::
  field1 : T1
  field2 : T2
  deriving DecidableEq, Inhabited, Repr
```

Native `{ r with f := v }` replaces the `RecordUpdate` library.

#### Type family handling

Type families are eliminated by the `TypeFamilyRemoval` pass before the
printer runs. The `tf_set` registered from hints is still used to guard
match exhaustiveness (same as Rocq).

### 6.7 Function definitions — `DecD`

| Clause pattern | Lean 4 output |
|---|---|
| No clauses | `axiom id : T` |
| `[{DefD ([], [], exp, _)}]` — single, no args, no prems | `def id : T := exp` |
| Clauses with premises | `axiom id : T  -- partial; needs proof` |
| Clauses without premises, multiple | `partial def id (params) : T :=\n  match ... with\n  \| ...` |
| Projection function (in `proj_set`) | emit `def` + `instance : Coe A B := ⟨id⟩` |

The Rocq printer uses `Fixpoint` for recursive functions and `Definition`
for non-recursive ones. Lean 4 uses `def` for both; the kernel decides
whether a termination proof is needed. Start all multi-clause definitions
with `partial def` and add a `-- TODO: termination_by` comment; a later
cleanup pass can replace this.

#### Mutual function blocks (`RecD` containing `DecD`)
```lean
-- Rocq: Fixpoint A ... with B ...
mutual
partial def a (params) : TA := ...
partial def b (params) : TB := ...
end
```

#### Projection coercions

The Rocq backend emits a custom `Coercion` class instance for each
projection function in `proj_set`. Lean 4:
```lean
instance : Coe SrcType DstType := ⟨projFuncName⟩
```

### 6.8 Relation definitions — `RelD`

This is the most direct translation from Rocq because Lean 4 has native
inductive propositions.

**Rocq output** (from `wasm3.v`, e.g. for `Instr_ok`):
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

Differences from Rocq:
- `Inductive` → `inductive`
- `:= \n\t| rule :` → `where\n  | rule :`
- `forall` → `∀`
- ` -> ` (premise separator) → ` →\n    `
- Final `.` → none (Lean 4 is indentation-delimited)
- `deriving Inhabited` (note: not `DecidableEq` — `Prop`-valued inductives do
  not need decidable equality)

#### Mutual inductive relations (`RecD` containing `RelD`)
```lean
-- Rocq: Inductive A ... with B ...
mutual
inductive A where ...
inductive B where ...
end
```

#### Mixed `RecD` (both `DecD` and `RelD`)

Lean 4 `mutual` blocks support mixing `def` and `inductive`.

### 6.9 String-of-def dispatch

The Lean `string_of_def` function mirrors the Rocq version with these
structural changes:

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

The `comment_desc_def` comments (e.g. `(* Type Alias Definition at: ... *)`)
carry over as `-- Type Alias Definition at: ...`.

---

## 7. CSLib LTS wiring

This is a purely **additive** block appended after all generated definitions.
It does not change how any other definition is emitted.

### 7.1 What CSLib provides

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

### 7.2 Mapping the wasm spec

From the generated Rocq output:

```
config          := mk_config (state : State) (instrs : List Instr)
Step            : config → config → Prop    -- single step  (generated)
Steps           : config → config → Prop    -- multi-step   (generated, to be superseded)
```

The `Steps` relation is emitted faithfully from the spec. The CSLib section
then connects `Step` to CSLib as follows:

### 7.3 Emitted LTS block (hardcoded suffix in `print.ml`)

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

### 7.4 Detection of `Step`

The printer must know the name of the top-level reduction relation so it can
reference it in the LTS block. Strategy (in order of preference):

1. **Hint annotation**: if a `RelD` carries `hint(step)`, register it in
   `lean_env.step_rel`. Emit the LTS block using that name.
2. **Name heuristic**: the relation named exactly `Step` (after disambiguation)
   is the wasm reduction relation. Fall back to this if no hint is present.
3. **Manual override**: add a `--lean-step-rel NAME` CLI flag so the user can
   specify the name if it changes.

---

## 8. Preamble

The Rocq preamble (hardcoded in `print.ml`) is 200 lines. The Lean 4
preamble is much shorter because standard library and language features
replace most of it.

```lean
-- Generated by SpecTec --lean
-- WebAssembly formal semantics (Lean 4 + Mathlib + CSLib)

import Mathlib.Data.List.Basic
import Mathlib.Data.List.Zip
import Mathlib.Data.Option.Basic
import Cslib.Foundations.Semantics.LTS.Basic

open Cslib List Option

namespace Wasm

-- ---------------------------------------------------------------------------
-- Preamble helpers (replacing Rocq's custom operators)
-- ---------------------------------------------------------------------------

/-- Total lookup with default value (replaces lookup_total). -/
def lookupTotal [Inhabited α] (l : List α) (n : Nat) : α :=
  l.getD n default

/-- Partial extraction from Option, with default (replaces `the`). -/
def the! [Inhabited α] (x : Option α) : α := x.getD default

/-- Zip two lists with a 3-argument function. -/
def List.zipWith3 {α β γ δ} (f : α → β → γ → δ)
    (xs : List α) (ys : List β) (zs : List γ) : List δ :=
  (xs.zip (ys.zip zs)).map fun (x, y, z) => f x y z

/-- Forall over three lists simultaneously. -/
inductive List.Forall₃ {α β γ} (R : α → β → γ → Prop) :
    List α → List β → List γ → Prop where
  | nil  : List.Forall₃ R [] [] []
  | cons : R x y z → List.Forall₃ R xs ys zs →
           List.Forall₃ R (x :: xs) (y :: ys) (z :: zs)

/-- Indexed Forall (replaces List_Foralli). -/
def List.forallIdx {α} (f : Nat → α → Prop) (xs : List α) : Prop :=
  ∀ i h, f i xs[i]

/-- Option.map₂ — zip two options. -/
def Option.map₂ {α β γ} (f : α → β → γ) : Option α → Option β → Option γ
  | some a, some b => some (f a b)
  | _, _ => none

/-- Option.map₃. -/
def Option.map₃ {α β γ δ} (f : α → β → γ → δ) :
    Option α → Option β → Option γ → Option δ
  | some a, some b, some c => some (f a b c)
  | _, _, _ => none

/-- List slice  [i .. i+j). -/
def List.slice {α} (l : List α) (i j : Nat) : List α :=
  (l.drop i).take j

/-- List slice update. -/
def List.sliceUpdate {α} (l : List α) (i j : Nat) (u : List α) : List α :=
  l.take i ++ u.take j ++ l.drop (i + j)

/-- List index update. -/
def List.update {α} (l : List α) (n : Nat) (y : α) : List α :=
  l.set n y

/-- List index update by a function. -/
def List.updateF {α} (l : List α) (n : Nat) (f : α → α) : List α :=
  l.modify n f

notation:10 l " [|" n "|]" => lookupTotal l n
notation:10 "!(" x ")"    => the! x
```

This preamble is about 70 lines — a 65 % reduction from the Rocq version.
Key savings:

| Rocq preamble section | Lean 4 replacement |
|---|---|
| `Class Inhabited` + 8 instances | Built-in `Inhabited` + `deriving Inhabited` |
| `Class Append` + 3 instances | `++` operator on `List`, `Option`, `Nat` |
| `Class Coercion` + 5 instances | `Coe` typeclass, native |
| `HintDb eq_dec_db` + `decidable_equality_step` + `eq_dec_Equality_axiom` | `deriving DecidableEq` |
| `List_Forall3`, `Foralli_help`, `List_Foralli` | `List.Forall₃` (preamble), `List.forallIdx` |
| `list_zipWith`, `option_zipWith`, `list_map3`, `option_map3` | `List.zipWith`, `Option.map₂/₃` |
| `ssreflect` `seq`, `eqtype`, `rat`, `ssrint` imports | Mathlib |
| `RecordUpdate` library | Native `{ r with f := v }` |

---

## 9. `string_of_script` — top-level entry point

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

Where `lts_section` returns the CSLib block if a step relation was detected,
or a comment placeholder if not:

```ocaml
let lts_section = function
  | Some step_id -> render_lts_block step_id
  | None -> "-- Note: no Step relation detected; CSLib LTS not generated\n"
```

---

## 10. Implementation phases

### Phase 1 — Scaffolding  *(~2 hours)*

- [ ] Add `| Lean` to `target` in `main.ml`
- [ ] Register `--lean` CLI flag
- [ ] Copy `| Rocq ->` pass block; change label to `| Lean`
- [ ] Copy `| Rocq ->` output dispatch; change to call `Backend_lean.Print.string_of_script`
- [ ] Create `src/backend-lean/` with stub `dune` and stubs for `disamb.ml` / `print.ml`
  - Stub `string_of_script` returns `"-- TODO\n"`
- [ ] Add `(re_export backend_lean)` to `src/dune`
- [ ] `dune build` passes with no errors

**Checkpoint**: `./spectec --lean spec/*.spectec` produces `-- TODO`

---

### Phase 2 — Disambiguator  *(~1 day)*

- [ ] Copy `backend-rocq/disamb.ml` to `backend-lean/disamb.ml`
- [ ] Replace `reserved_ids` with the Lean 4 set (Section 5.1)
- [ ] Replace `render_id` collision strategy (`res_` → `wasm_`)
- [ ] Add `to_pascal` and `to_camel` helpers
- [ ] Apply `to_pascal` in `t_inst` for type/constructor atoms
- [ ] Apply `to_camel` in `t_def` for term-level ids (`DecD`, `RelD`)
- [ ] Unit-test on `0.1-aux.vars.spectec` alone: check that output ids are
  well-formed Lean 4 identifiers and no reserved words appear

**Checkpoint**: `./spectec --lean spec/0.1*.spectec spec/1.1*.spectec` prints
disambiguated ids in Lean 4 case format

---

### Phase 3 — Preamble + type rendering  *(~1 day)*

- [ ] Implement `preamble` string constant (Section 8)
- [ ] Implement `render_type` (Section 6.2 table)
- [ ] Implement `render_numtyp`
- [ ] Implement `render_typealias` → `abbrev Name := T`
- [ ] Implement `render_variant_typ` → `inductive ... where | ... deriving ...`
  - No Rocq `HB.instance` block; replace with `deriving DecidableEq, Inhabited, Repr`
- [ ] Implement `render_record` → `structure ... where\n  mk ::\n  ...`
- [ ] Implement `render_extra_info` → `none` (no Rocq eq_dec proofs needed)

**Checkpoint**: `./spectec --lean spec/1.2*.spectec` produces a Lean 4 file
with well-formed type definitions for the wasm type syntax

---

### Phase 4 — Expression and function rendering  *(~2 days)*

- [ ] Implement `render_exp` (Section 6.3 table)
  - All operator mappings
  - `ListE` → `[e1, e2, ...]`
  - `StrE` → `{ f := v, ... }`
  - `DotE` → `e.field`
  - `IterE` dispatch using `iter_list_funcs` / `iter_opt_funcs`
  - `UpdE` → `{ e with path := v }` + `listUpdate`/`listSlice` helpers
- [ ] Implement `render_function_def` → `partial def id (params) : T :=\n  match ...`
- [ ] Implement `render_axiom` → `axiom id : T`
- [ ] Implement `render_global_declaration` → `def id : T := exp`
- [ ] Implement projection coercion emission → `instance : Coe A B := ⟨id⟩`
- [ ] Implement mutual function blocks → `mutual\n...\nend`

**Checkpoint**: `./spectec --lean spec/0.*.spectec` produces a Lean 4 file
with well-formed auxiliary function definitions

---

### Phase 5 — Relation rendering  *(~1 day)*

- [ ] Implement `render_relation` → `inductive Name : T → Prop where\n  | ...`
  - `forall` → `∀`, ` -> ` → ` →\n    `
  - Premises as anonymous hypotheses `(_ : e)`
  - `IterPr` → `List.Forall` / `List.Forall₂` / `List.Forall₃`
- [ ] Implement mutual inductive blocks → `mutual\ninductive ...\ninductive ...\nend`
- [ ] Implement mixed `RecD` (def + inductive) → `mutual\ndef ...\ninductive ...\nend`

**Checkpoint**: `./spectec --lean spec/2.*.spectec` produces well-formed
validation/typing `inductive Prop` definitions

---

### Phase 6 — CSLib LTS wiring  *(~half a day)*

- [ ] Implement `render_lts_block step_id` emitting the block from Section 7.3
- [ ] Implement `detect_step_rel` in `register_hints` (hint name `"step"`)
- [ ] Fall back to name heuristic: relation named `"Step"` after disambiguation
- [ ] Append `lts_section` after generated code in `string_of_script`

**Checkpoint**: `./spectec --lean spec/4.*.spectec` produces a file ending with
the `wasmLTS` definition; `create_lts wasmStep wasmLTS` compiles in Lean 4

---

### Phase 7 — Full spec smoke test  *(~half a day)*

- [ ] `./spectec --lean spec/wasm-3.0/*.spectec -o wasm3.lean`
- [ ] File is syntactically valid Lean 4 (check with `lean --only-export wasm3.lean`)
- [ ] No `sorry` except in `partial def` stubs
- [ ] All type, function, and relation names are valid Lean 4 identifiers
- [ ] Repeat for wasm-2.0

---

### Phase 8 — Test suite integration  *(~half a day)*

- [ ] Add `spectec/test-lean/` mirroring `test-latex/` structure
- [ ] Add a minimal test spec (e.g. `0.*.spectec`) with expected output checked
  into the repo
- [ ] Add `dune runtest` integration using `mdx` or diff-based snapshot testing
- [ ] Add to top-level `Makefile` `test` target

---

## 11. Open questions and deferred work

### Termination

All multi-clause `DecD` definitions are emitted as `partial def`.
A follow-up pass should:
- Identify structurally recursive functions from the IL (measure = list length
  of the primary argument)
- Replace `partial def` with `def` + `termination_by xs.length`
- Functions that are genuinely partial (e.g. host function calls) remain
  `partial def` permanently

### BitVec numerics

`NumT NatT` is mapped to `Nat` throughout. WebAssembly's 32-/64-bit arithmetic
should eventually use `BitVec 32` / `BitVec 64` from Mathlib, which gives
modular arithmetic automatically.  This requires a second pass over `render_exp`
that detects width annotations and inserts `BitVec` casts.

### Observable labels

`Label := Unit` in `wasmLTS` is correct for the core spec (all transitions are
internal). For WASI or the component model, extend to:
```lean
inductive WasmLabel where | tau | hostCall (name : String) (args : List Val)
```
and change the `wasmStep` type to `Config → WasmLabel → Config → Prop`.

### Proof generation

Once the file type-checks, port the WasmCert soundness proof structure using:
- `LTS.MTr.comp` for progress chaining
- `LTS.STr` for weak bisimulation
- `LTS.Bisimulation` from `Cslib.Foundations.Semantics.LTS.Bisimulation`

### `lean --check` in CI

Add a CI job that runs `lake build` on the generated `wasm3.lean` using the
CSLib + Mathlib toolchain (pinned to the current `lean-toolchain` in
`leanprover/cslib`).

---

## 12. Summary

| Item | Detail |
|---|---|
| New source files | `src/backend-lean/disamb.ml`, `print.ml`, `dune` |
| Changed files | `src/exe-spectec/main.ml` (4 edits), `src/dune` (1 line) |
| Template | ~70 % of `backend-rocq/print.ml` adapted with syntax substitutions |
| Key savings vs Rocq | `deriving` replaces ~45 lines of boilerplate per type; native record update; shorter preamble |
| Key addition vs Rocq | CSLib `LTS` block (~15 hardcoded lines) wired to the `Step` relation |
| Output | `wasm3.lean` — single Lean 4 file, `namespace Wasm`, CSLib import |
| Estimated effort | 5–7 developer-days for a working first version |
