"""
    prevminor(v::VersionNumber)

Return a `VersionNumber` with the same major version as `v`, but with minor version decremented by 1
(bounded at 0) and patch version set to 0.
"""
function prevminor(v::VersionNumber)
    return VersionNumber(v.major, max(0, v.minor - 1), 0)
end


"""
    insertversion(svec::AbstractVector, v::VersionNumber)

Insert a version string into a copy of the given vector at the second position.

# Arguments
- `svec::AbstractVector`: The vector into which the version string will be inserted.
- `v::VersionNumber`: The version number used to create the version string.

# Returns
A new vector with the version string inserted at the second position.

# Details
The function creates a deep copy of the input vector `svec` and inserts a string
representation of the version number `v` in the format "major.minor" at the second position.
"""
function insertversion(svec::AbstractVector, v::VersionNumber)
    major = v.major
    minor = v.minor
    insert!(deepcopy(svec), 2, "$(major).$(minor)")
end

# Encode components without allowing separators, dot traversal, or reserved filenames.
function cache_component(value::AbstractString)
    if occursin(r"^[A-Za-z0-9_.-]+$", value) &&
       lowercase(value) ∉ (".", "..", "original") &&
       !startswith(lowercase(value), "encoded-")
        return String(value)
    end
    return "encoded-" * bytes2hex(codeunits(value))
end

function cache_parts(md::Markdown.MD)
    if haskey(md.meta, :module)
        mod = md.meta[:module]
        return cache_component.(split(string(mod), ".")),
        something(pkgversion(mod), VERSION)
    elseif haskey(md.meta, :path)
        source = String(md.meta[:path])
        version = something(DOCUMENTER_TARGET_PACKAGE[][:version], VERSION)
        if isabspath(source) || ".." in splitpath(source)
            # The full normalized source identity prevents basename collisions.
            canonical_source = ispath(source) ? realpath(source) : abspath(source)
            parts = [
                cache_component(DOCUMENTER_TARGET_PACKAGE[][:name]),
                "pages",
                bytes2hex(sha256(canonical_source)),
                cache_component(basename(canonical_source)),
            ]
        else
            parts = cache_component.(splitpath(normpath(source)))
            isempty(parts) && throw(ArgumentError("Empty page cache path"))
        end
        return parts, version
    end
    throw(ArgumentError("No module or path found in the markdown metadata."))
end

"""
    pathofcachedir(md::Markdown.MD, allowold::Bool=false)

Return a cache directory inside the configured root. Unversioned modules use
the Julia version. Absolute and parent-relative page paths use a source hash.
"""
function pathofcachedir(md::Markdown.MD, allowold::Bool = false)
    parts, version = cache_parts(md)
    current = joinpath(TRANSLATION_CACHE_DIR[], insertversion(parts, version)...)
    if allowold && !isdir(current)
        return joinpath(
            TRANSLATION_CACHE_DIR[],
            insertversion(parts, prevminor(version))...,
        )
    end
    return current
end

function translation_file(md::Markdown.MD)
    parts, version = cache_parts(md)
    lang = normalize_language(DEFAULT_LANG[])
    filename = cache_component(lang) * ".md"
    directories = [
        joinpath(TRANSLATION_CACHE_DIR[], insertversion(parts, v)..., hashmd(md)) for
        v in (version, prevminor(version))
    ]
    # Earlier caches combined the canonical path hash with the alias's basename.
    # Continue reading those entries after canonicalizing symlink cache identity.
    source = get(md.meta, :path, nothing)
    if !haskey(md.meta, :module) &&
       source isa AbstractString &&
       (isabspath(source) || ".." in splitpath(source))
        old_basename = cache_component(basename(normpath(source)))
        if old_basename != last(parts)
            old_parts = copy(parts)
            old_parts[end] = old_basename
            append!(
                directories,
                [
                    joinpath(
                        TRANSLATION_CACHE_DIR[],
                        insertversion(old_parts, v)...,
                        hashmd(md),
                    ) for v in (version, prevminor(version))
                ],
            )
        end
    end
    legacy = get(md.meta, :legacy_cache_path, nothing)
    if legacy isa AbstractString && !isabspath(legacy) && !(".." in splitpath(legacy))
        legacy_parts = cache_component.(splitpath(normpath(legacy)))
        if !isempty(legacy_parts)
            append!(
                directories,
                [
                    joinpath(
                        TRANSLATION_CACHE_DIR[],
                        insertversion(legacy_parts, v)...,
                        hashmd(md),
                    ) for v in (version, prevminor(version))
                ],
            )
        end
    end
    for dir in directories
        exact = joinpath(dir, filename)
        isfile(exact) && return exact
        # Compatible old language-name entries remain readable.
        if isdir(dir)
            for name in readdir(dir)
                lowercase(name) == "original.md" && continue
                startswith(lowercase(name), "encoded-") && continue
                endswith(name, ".md") || continue
                normalize_language(first(splitext(name))) == lang || continue
                return joinpath(dir, name)
            end
        end
    end
    return nothing
end

istranslated(md::Markdown.MD) = translation_file(md) !== nothing

"""Load a compatible cached translation and restore the original metadata."""
function load_translation(md::Markdown.MD)
    file = translation_file(md)
    file === nothing &&
        throw(ArgumentError("No cached translation for the selected language"))
    content = read(file, String)
    protected =
        get(md.meta, :documenter_page_translation, false) ||
        get(md.meta, :docstring_translation, false)
    translated = Markdown.parse(protected ? content : postprocess_content(content))
    merge!(translated.meta, copy(md.meta))
    return translated
end

function atomic_cache_write(path, text)
    mkpath(dirname(path))
    temporary, io = mktemp(dirname(path))
    try
        write(io, text)
        close(io)
        mv(temporary, path; force = true)
    finally
        isopen(io) && close(io)
        isfile(temporary) && rm(temporary)
    end
    return path
end

"""Save pristine Markdown as original.md."""
function cache_original(md::Markdown.MD)
    atomic_cache_write(
        joinpath(pathofcachedir(md), hashmd(md), "original.md"),
        markdown_source(md),
    )
end

"""Save a successfully translated document under its original hash."""
function cache_translation(md_hash_original::String, transmd::Markdown.MD)
    file = cache_component(normalize_language(DEFAULT_LANG[])) * ".md"
    atomic_cache_write(
        joinpath(pathofcachedir(transmd), md_hash_original, file),
        markdown_source(transmd),
    )
end

"""Select a cached translation, or translate the pristine original and save on success."""
function cached_translation(
    md::Markdown.MD;
    translator = translate_docstring_with_openai,
    available::Bool = haskey(ENV, "OPENAI_API_KEY"),
    on_error::Symbol = :throw,
)
    on_error in (:throw, :fallback) ||
        throw(ArgumentError("on_error must be :throw or :fallback"))
    key = translation_key(md)
    return lock(translation_key_lock(key)) do
        istranslated(md) && return load_translation(md)
        available || return copy_markdown(md)
        prior = recorded_translation_failure(key)
        if on_error == :fallback && prior !== nothing
            report_translation_failure(prior)
            return copy_markdown(md)
        end
        try
            cache_original(md)
            translated = translator(copy_markdown(md))
            translated isa Markdown.MD ||
                throw(ArgumentError("Translator must return Markdown.MD"))
            isempty(strip(string(translated))) &&
                error("Translation returned empty content")
            merge!(translated.meta, copy(md.meta))
            cache_translation(hashmd(md), translated)
            lock(TRANSLATION_STATE_LOCK) do
                delete!(TRANSLATION_FAILURES, key)
            end
            return translated
        catch err
            err isa Union{InterruptException,OutOfMemoryError,StackOverflowError} &&
                rethrow()
            failure = TranslationFailure(
                translation_source_label(md),
                safe_translation_error(err),
                key,
            )
            lock(TRANSLATION_STATE_LOCK) do
                TRANSLATION_FAILURES[key] = failure
            end
            on_error == :throw && rethrow()
            report_translation_failure(failure)
            return copy_markdown(md)
        end
    end
end

copy_markdown(md::Markdown.MD) = Markdown.MD(deepcopy(md.content), copy(md.meta))
