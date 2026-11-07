struct TranslationFailure
    source::String
    reason::String
    cache_key::String
end

const TRANSLATION_STATE_LOCK = ReentrantLock()
const TRANSLATION_KEY_LOCKS = Dict{String,ReentrantLock}()
const TRANSLATION_FAILURES = Dict{String,TranslationFailure}()
const REPORTED_TRANSLATION_FAILURES = Set{String}()

function translation_source_label(md::Markdown.MD)
    kind =
        get(md.meta, :docstring_translation, false) ?
        "docstring in $(get(md.meta, :module, "unknown module"))" : "page"
    path = get(md.meta, :path, "unknown source")
    return "$kind $path [$(first(hashmd(md), 12))]"
end

function safe_translation_error(err)
    message = sprint(showerror, err)
    secret = get(ENV, "OPENAI_API_KEY", "")
    return isempty(secret) ? message : replace(message, secret => "[REDACTED]")
end

function translation_key(md)
    return joinpath(
               pathofcachedir(md),
               hashmd(md),
               cache_component(normalize_language(DEFAULT_LANG[])),
           ) *
           "|" *
           default_model() *
           "|fallback=" *
           something(default_fallback_model(), "none")
end

function translation_key_lock(key)
    lock(TRANSLATION_STATE_LOCK) do
        get!(ReentrantLock, TRANSLATION_KEY_LOCKS, key)
    end
end

"""Return failures recorded in this process, including source and sanitized reason."""
function translation_failures()
    lock(TRANSLATION_STATE_LOCK) do
        sort!(collect(values(TRANSLATION_FAILURES)); by = failure -> failure.cache_key)
    end
end

"""Clear recorded failures between builds, allowing fallback hooks to retry them."""
function clear_translation_failures!()
    lock(TRANSLATION_STATE_LOCK) do
        empty!(TRANSLATION_FAILURES)
        empty!(REPORTED_TRANSLATION_FAILURES)
    end
    return nothing
end

function recorded_translation_failure(key)
    lock(TRANSLATION_STATE_LOCK) do
        get(TRANSLATION_FAILURES, key, nothing)
    end
end

function report_translation_failure(failure)
    report = lock(TRANSLATION_STATE_LOCK) do
        failure.cache_key in REPORTED_TRANSLATION_FAILURES && return false
        push!(REPORTED_TRANSLATION_FAILURES, failure.cache_key)
        true
    end
    report &&
        @warn "Translation failed; using original Markdown (not cached as translated)" source=failure.source reason=failure.reason
    return nothing
end
