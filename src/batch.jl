# Both the Documenter hook and batch workers must use the same pristine source,
# metadata and cache identity. A batch can require a translation; the hook retains
# its existing fallback to English when neither a cache nor an API key is present.
function page_translation(
    source::AbstractString;
    request = page_openai_request,
    available::Bool = haskey(ENV, "OPENAI_API_KEY"),
    require_translation::Bool = false,
    on_error::Symbol = :throw,
)
    mdsrc = replace(read(source, String), '\r' => "")
    mdpage = Markdown.parse(mdsrc)
    mdpage.meta[:path] = abspath(source)
    if !isabspath(source) && !(".." in splitpath(source))
        mdpage.meta[:legacy_cache_path] =
            joinpath(DOCUMENTER_TARGET_PACKAGE[][:name], first(splitext(source)))
    end
    mdpage.meta[:documenter_page_translation] = true
    hit = istranslated(mdpage)
    if require_translation && !hit && !available
        throw(
            ArgumentError("No cached translation; set OPENAI_API_KEY to translate $source"),
        )
    end
    @debug "Documenter translation cache lookup" source cachedir=pathofcachedir(mdpage) hit
    translated = cached_translation(
        mdpage;
        translator = _ -> parse_translation(
            translate_documenter_page_with_openai(
                mdsrc;
                request,
                source_label = translation_source_label(mdpage),
            ),
        ),
        available,
        on_error,
    )
    if require_translation && hit
        # A reused legacy alias must also be visible through its canonical path.
        filename = cache_component(normalize_language(DEFAULT_LANG[])) * ".md"
        if !isfile(joinpath(pathofcachedir(mdpage), hashmd(mdpage), filename))
            cache_translation(hashmd(mdpage), translated)
        end
    end
    return (; markdown = translated, cached = hit)
end

function translated_page(
    source::AbstractString;
    request = page_openai_request,
    available::Bool = haskey(ENV, "OPENAI_API_KEY"),
    on_error::Symbol = :throw,
)
    return page_translation(source; request, available, on_error).markdown
end

"""
    DocstringTranslation.translate_pages(paths; concurrency=32)

Translate Markdown files into the current language and populate the same cache
used by `@switchlang!` and Documenter. Run this before `Documenter.makedocs` to
overlap API requests across pages. Up to `concurrency` asynchronous workers run
even with one Julia thread; `concurrency` must be a positive integer.

Return `(translated, cached, failed)` in input order. The first two fields are
vectors of absolute file paths. `failed` contains `path => exception` pairs.
Individual failures do not discard successful peers; rerun the batch to resume.
Duplicate paths (including symlinks) are processed once per call. An empty input
returns empty vectors. Without `OPENAI_API_KEY`, cached pages remain usable and
uncached pages are reported as failures.

Set the language with `@switchlang!`, and configure the cache directory, target
package and model before calling. Keep that configuration fixed until the batch
completes. Concurrent calls have independent worker limits and do not deduplicate
each other's requests.

For custom providers or offline testing, `request(text, promptfn)` may supply the
response text, with `available=true` to enable it without an API key. Responses
undergo the same protection and validation as ordinary page translations.
"""
function translate_pages(
    paths;
    concurrency::Integer = 32,
    request = page_openai_request,
    available::Bool = haskey(ENV, "OPENAI_API_KEY"),
)
    concurrency > 0 || throw(ArgumentError("concurrency must be positive"))
    paths isa AbstractString && throw(ArgumentError("Pass a collection of file paths"))
    files = String[]
    sources = String[]
    seen = Set{String}()
    for path in paths
        path isa AbstractString || throw(ArgumentError("Each path must be a string"))
        file = abspath(path)
        identity = isfile(file) ? realpath(file) : file
        identity in seen && continue
        push!(seen, identity)
        push!(files, file)
        # Preserve relative spellings for the legacy cache lookup used by Page.
        push!(sources, String(path))
    end

    states = fill(:pending, length(files))
    errors = Vector{Any}(undef, length(files))
    jobs = Channel{Tuple{Int,String}}(length(files))
    for job in enumerate(sources)
        put!(jobs, job)
    end
    close(jobs)
    @sync for _ = 1:min(concurrency, length(files))
        @async for (i, file) in jobs
            try
                result =
                    page_translation(file; request, available, require_translation = true)
                states[i] = result.cached ? :cached : :translated
            catch err
                err isa InterruptException && rethrow()
                states[i] = :failed
                errors[i] = err
            end
        end
    end
    return (
        translated = files[states .== :translated],
        cached = files[states .== :cached],
        failed = [files[i] => errors[i] for i in eachindex(files) if states[i] == :failed],
    )
end
