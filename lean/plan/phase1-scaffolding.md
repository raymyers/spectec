# Phase 1 — Scaffolding

*Estimated: ~2 hours*

Wire the `--lean` CLI flag through to a stub backend that produces placeholder output.

## New files

```
src/backend-lean/
  disamb.ml       identifier sanitiser (Lean 4 conventions) — stub
  print.ml        IL → Lean 4 source printer — stub
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

## Changes to existing files

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

**c) Pass selection** — copy the `| Rocq ->` block verbatim and change the label:
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

## Stub `print.ml`

```ocaml
let string_of_script (_il : Il.Ast.script) = "-- TODO\n"
```

## Checkpoint

`./spectec --lean spec/*.spectec` produces `-- TODO` and `dune build` passes with no errors.
