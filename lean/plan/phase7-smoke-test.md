# Phase 7 — Full Spec Smoke Test

*Estimated: ~half a day*

## Steps

1. Generate the full wasm-3.0 output:
   ```
   ./spectec --lean spec/wasm-3.0/*.spectec -o wasm3.lean
   ```

2. Verify syntactic validity:
   - File parses as valid Lean 4 (check with `lean --only-export wasm3.lean`)
   - No `sorry` except in `partial def` stubs

3. Verify naming:
   - All type, function, and relation names are valid Lean 4 identifiers
   - No Lean 4 reserved words appear unescaped

4. Repeat for wasm-2.0:
   ```
   ./spectec --lean spec/wasm-2.0/*.spectec -o wasm2.lean
   ```

5. Attempt `lake build` in the project that imports the generated file:
   - Confirm type definitions compile
   - Identify and document any type errors for fixing in subsequent iterations
