# Julia documentation build resilience

Requested: use the local checkout temporarily and redesign validation and error
reporting so Julia's complete documentation can build while translating.

Evidence: the actual range operator docstring response retains every protected
marker but translates italic `not` into an unitalicized Japanese negative. The
old exact AST comparison incorrectly rejects that response.

Selected design: ignore prose emphasis and allow adjacent prose paragraphs to
split/merge; retain structural boundaries for blocks, lists/items, tables/cells,
quotes and admonitions. Preserve every protected marker exactly once. Validate
restored code, mathematics and links as before. Errors identify source, hash,
first differing structural location, attempts and optional diagnostic artifacts.

Build hooks fall back to pristine original Markdown after translation failure,
report once per source/language/model/cache identity, and never cache fallback as
a successful translation. Strict batch/direct APIs still report failures. A
per-key lock prevents repeated concurrent requests; failed keys can be explicitly
cleared between builds. Diagnostic original/protected/response/error files stay
outside successful translation caches. Report failures at the end of the build.

Use `[sources]` to point the Julia 1.13.3 environment to the requested absolute
local path. Preserve its current package version metadata; relax the app's exact
registered-version pin while the source override is active. Load .env via DotEnv.
Use configurable bounded async concurrency in the build (default 32).

Verify offline regressions, the captured real response, full package tests and
Julia's complete HTML pipeline. Do not weaken validation by accepting missing
protected data or falsely claiming fallback content is translated.

## Verification so far

- Captured range docstring response reproduces the old false rejection; it now
  passes offline and a fresh live request passes the revised prompt/validator.
- Full Julia 1.13.3 cache-only HTML build completed with the local source override.
- Full package suite passed 227 assertions in 43 test items, including JET,
  concurrent singleflight, fallback HTML, structural damage rejection, and
  diagnostic persistence after a subprocess exits.
- User requested clearing ./translation and a complete real first-run build;
  the directory was removed and that build is running with 16 async workers.

## Requested model escalation and table fix

- Primary Luna keeps up to three validation attempts; only exhausted failures use
  GPT-6.1 Sol medium for one further attempt. Both failing still falls back to
  pristine original; injected request callbacks never cause unintended network
  calls without an explicit fallback callback. Both model errors are reported.
- Reasoning models omit temperature; integer read timeout defaults to 180 seconds
  and SDK HTTP retries are disabled to keep attempt counts bounded.
- A real SDK smoke test caught a Float64/Int timeout mismatch missed by the mock;
  corrected to integer timeout and added a boundary-type regression. Live Luna
  failure -> Sol success is confirmed. Full package suite now passes 255 checks.
- Restoring protected elements in table cells preserves the escaped pipe layer.
  Offline identity tests and replay of the failing open docstring now pass.
- Read-only review found no remaining important issues in these changes.
