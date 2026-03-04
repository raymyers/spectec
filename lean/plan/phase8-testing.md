# Phase 8 — Test Suite Integration

*Estimated: ~half a day*

## Structure

Add `spectec/test-lean/` mirroring `test-latex/` structure:

```
spectec/test-lean/
  run.sh                  test runner script
  0-aux/
    expected.lean         expected output for 0.*.spectec
  1-types/
    expected.lean         expected output for 1.*.spectec
  ...
```

## Steps

1. Add a minimal test spec (e.g. `0.*.spectec`) with expected output checked
   into the repo

2. Add `dune runtest` integration using diff-based snapshot testing:
   - Generate output with `./spectec --lean`
   - `diff` against expected file
   - Fail on any difference

3. Add to top-level `Makefile` `test` target:
   ```makefile
   test-lean:
   	@echo "Testing Lean backend..."
   	@dune runtest test-lean
   ```

4. Consider adding a CI step that runs `lake build` on the generated output
   to verify it compiles with the current Lean/mathlib/CSLib toolchain.
