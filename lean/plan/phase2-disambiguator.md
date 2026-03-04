# Phase 2 — Disambiguator

*Estimated: ~1 day*

Mirrors the structure of `backend-rocq/disamb.ml` exactly. Two functions are
changed: the reserved-name set and the case-conversion of atoms.

## Reserved names

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

## Atom case conventions

The Rocq backend leaves identifiers in their original mixed-case form.
Lean 4 conventions: **`PascalCase`** for types and constructors;
**`camelCase`** for term-level definitions.

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

## Everything else

`t_exp`, `t_path`, `t_atom_opt`, `t_atom_new`, `t_mixop_new`, `t_inst`,
`t_def`, `t_rule_new`, `remove_overlapping_clauses`, and `transform` all
carry over from the Rocq disambiguator with no structural change — only the
`render_id` and atom-case functions differ.

## Checkpoint

`./spectec --lean spec/0.1*.spectec spec/1.1*.spectec` prints disambiguated ids
in Lean 4 case format. No reserved words appear in the output.
