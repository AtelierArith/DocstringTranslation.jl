# Concurrent page translation

Approved in conversation: add page-level concurrency to DocstringTranslation itself,
using bounded asynchronous workers (default 32). The purpose is to overlap API wait
time when translating Julia's many documentation pages, including on one thread.

Approaches: paragraph-level threading reproduces v0.1.2 but weakens whole-page
validation; page-level asynchronous workers preserve the v0.1.5 validation boundary
and are the selected approach. No change to the page protection algorithm.

`translate_pages(paths; concurrency=32)` prepares the existing Documenter cache.
It deduplicates files within a batch, reuses cached translations, saves only valid
results, continues after individual failures, and returns translated/cached/failed
file lists. Repeating a batch resumes from successful cached work. Configuration
(language, model, target package and cache root) stays fixed for the batch.
Documenter then reads the exact same cache without additional API calls.

No real API calls in tests. Inject the request function at the existing HTTP
boundary to test overlapping requests, the concurrency cap, failures and resume.
Keep compatibility with Julia 1.10 and existing package dependencies.
