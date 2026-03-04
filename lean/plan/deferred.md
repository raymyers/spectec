# Deferred Work

## Termination

All multi-clause `DecD` definitions are emitted as `partial def`.
A follow-up pass should:
- Identify structurally recursive functions from the IL (measure = list length
  of the primary argument)
- Replace `partial def` with `def` + `termination_by xs.length`
- Functions that are genuinely partial (e.g. host function calls) remain
  `partial def` permanently

## BitVec numerics

`NumT NatT` is mapped to `Nat` throughout. WebAssembly's 32-/64-bit arithmetic
should eventually use `BitVec 32` / `BitVec 64` from Mathlib, which gives
modular arithmetic automatically. This requires a second pass over `render_exp`
that detects width annotations and inserts `BitVec` casts.

## Observable labels

`Label := Unit` in `wasmLTS` is correct for the core spec (all transitions are
internal). For WASI or the component model, extend to:
```lean
inductive WasmLabel where | tau | hostCall (name : String) (args : List Val)
```
and change the `wasmStep` type to `Config → WasmLabel → Config → Prop`.

## Proof generation

Once the file type-checks, port the WasmCert soundness proof structure using:
- `LTS.MTr.comp` for progress chaining
- `LTS.STr` for weak bisimulation
- `LTS.Bisimulation` from `Cslib.Foundations.Semantics.LTS.Bisimulation`

## `lean --check` in CI

Add a CI job that runs `lake build` on the generated `wasm3.lean` using the
CSLib + Mathlib toolchain (pinned to the current `lean-toolchain` in
`leanprover/cslib`).
