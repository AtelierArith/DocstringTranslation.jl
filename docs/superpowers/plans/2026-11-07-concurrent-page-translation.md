# Concurrent Page Translation Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Overlap page translation requests with bounded asynchronous workers.

**Architecture:** Add a batch API and share the page cache preparation path with
the existing Documenter hook. Workers use existing whole-page validation.

**Tech Stack:** Julia tasks, Channels, existing Markdown and Documenter dependencies.

**Spec:** ../specs/2026-11-07-concurrent-page-translation-design.md

## Global Constraints

- Default concurrency 32, configurable positive integer; Julia 1.10 compatible.
- Preserve whole-page validation, atomic cache writes and existing cache identity.
- No real API requests in verification; leave untracked extern/ untouched.

## Review Focus

- Duplicate paths and symlinks: only one translation per batch.
- Failed or invalid responses: no translated cache file; successful peers survive.
- Empty inputs and invalid worker counts: return empty results or ArgumentError.
- Missing keys: use existing cache, report untranslated files as failures.
- Documenter integration: pretranslated pages must be cache hits.

## Task 1: Bounded page translation and cache integration

Files: src/batch.jl, src/switchlang.jl, src/DocstringTranslation.jl,
test/batch_tests.jl, docs/src/translation_of_julia_documentation.md, README.md.

Interface: `DocstringTranslation.translate_pages(paths; concurrency=32)` returns
`(translated, cached, failed)`; failed entries pair paths with captured errors.
An optional request callable uses the existing `(text, prompt)` HTTP boundary.

- [x] Write failing tests for bounded overlap, deduplication, cache reuse,
  invalid output, partial failures/resume, missing keys, bad inputs and Page reuse.
- [x] Run focused tests and confirm failure due to the missing batch API.
- [x] Share page metadata preparation; implement fixed async worker pool and API.
- [x] Run focused tests, then full `Pkg.test()` on Julia 1.13.3.
- [x] Document usage before makedocs, configuration and failure handling.
- [x] Inspect the diff and formatting; leave changes available for user review.

## Verification results

- Julia 1.13.3: full `Pkg.test()` passed, 189 assertions in 36 test items.
- Batch-focused suite passed 48 assertions; no real API calls in tests.
- JuliaFormatter check and `git diff --check` passed.
- Read-only review found a symlink cache mismatch; regression tests and canonical
  identity with legacy fallback/promotion fixed it. Follow-up review found no
  remaining important issues.
- One-thread simulated 50ms API waits, 12 pages, median of three warmed runs:
  serial 0.638s, four async workers 0.162s (3.93x). This is not a real API benchmark.
- Changes remain uncommitted for user review. The registered 0.1.5 used by the
  separate UnofficialJuliaDoc-ja build does not yet include this new API.
