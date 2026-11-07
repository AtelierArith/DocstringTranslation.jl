# Open Issues Implementation Plan

**Goal:** Resolve #18–#22 using the updated English issue contracts.
**Architecture:** A shared cache transaction selects from pristine Markdown, restores metadata, and saves only validated translations. Both hooks use protected whole-document translation; docstrings receive a new hash namespace.
**Tech Stack:** Julia 1.10+, Markdown, Documenter 1, existing OpenAI.jl.
**Spec:** GitHub issues #18–#22, updated before implementation.

## Constraints and decisions

Preserve all headings, complete links, code and math. Keep public API signatures. Do not reuse legacy docstring translations that may contain changed links. Preserve page v5 caches when safe. Unknown language targets remain available, with encoded filenames. Use Julia version when package version is unavailable.

## Tasks

- [x] Add failing offline regressions for language aliases, safe paths, response validation, shared cache failure behavior, and already parsed docstring switching.
- [x] Implement language canonicalization, safe cache locations/legacy lookup, response validation and shared cache transaction.
- [x] Route parsed docstrings and Documenter pages through the transaction, protecting docstrings and preserving originals.
- [x] Build a deterministic offline Documenter fixture with tables, heading IDs and cross-page references.
- [x] Document migration; format; run full tests on current/LTS Julia and fresh SpecialFunctions API build.
- [x] Review, create PR, and pass CI. Integration: merge PR #26 into main, closing all five issues.

## Review focus

Cache lookup must honor language/directory changes without retranslating translations. Absolute/parent paths cannot escape the root. Missing keys allow cache-only use. Failures leave no completed cache. Cache namespaces must prevent incompatible old translations from being reused.


## Verification record

- Julia 1.13.3 and 1.10.12: 141 assertions passed, including Aqua, JET and offline Documenter build.
- Review caught an encoded-filename alias collision; reproduced with two failing assertions, fixed and reviewed.
- Fresh SpecialFunctions API build caught display-math serialization through nested Markdown.MD; reproduced, fixed, and reviewed. Math now serializes as Julia-compatible fences; code containing dollar signs remains unchanged.
- Fresh SpecialFunctions API build succeeded from an empty cache: 3 pages and 107 docstrings. All 374 links, 44 headings, 563 code nodes and 259 mathematics nodes are preserved.

- Captured dawson API response now passes: inline math uses double backticks so translated math at paragraph start remains inline. Regression checks fresh translation and cache reload.
