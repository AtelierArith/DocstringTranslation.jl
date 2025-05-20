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

"""
    pathofcachedir(md::Markdown.MD, allowold::Bool = false)

Get the cache directory path for a given Markdown document.

# Arguments
- `md::Markdown.MD`: The Markdown document to get the cache path for
- `allowold::Bool = false`: If true, allows falling back to previous minor version's cache directory

# Returns
A string containing the full path to the cache directory.

# Details
The cache directory path is constructed based on either:
- The module path from `md.meta[:module]` if present, using the module's version or `VERSION`
- The file path from `md.meta[:path]` if present, using `VERSION`

If `allowold` is true and the target directory doesn't exist, falls back to the previous minor version's directory.

# Throws
- `ArgumentError`: If neither `:module` nor `:path` is found in the markdown metadata
"""
function pathofcachedir(md::Markdown.MD, allowold::Bool = false)
    if haskey(md.meta, :module)
        svec = split(string(md.meta[:module]), ".")
        v = something(pkgversion(md.meta[:module]), VERSION)
        svec_with_version = insertversion(svec, v)
        d = joinpath(TRANSLATION_CACHE_DIR[], svec_with_version...)
        if !isdir(d) && allowold
            # we try to find the previous minor version.
            svec_with_prev_version = insertversion(deepcopy(svec), prevminor(v))
            return joinpath(TRANSLATION_CACHE_DIR[], svec_with_prev_version...)
        else
            return d
        end
    elseif haskey(md.meta, :path)
        # In case the module is not set.
        # This happens when we translate markdown in doc/src/<blah>.md
        svec = splitpath(md.meta[:path])
        v = DOCUMENTER_TARGET_PACKAGE[][:version]
        svec_with_version = insertversion(svec, v)
        d = joinpath(TRANSLATION_CACHE_DIR[], svec_with_version...)
        if !isdir(d) && allowold
            # we try to find the previous minor version.
            svec_with_prev_version = insertversion(deepcopy(svec), prevminor(v))
            return joinpath(TRANSLATION_CACHE_DIR[], svec_with_prev_version...)
        else
            return d
        end
    else
        throw(ArgumentError("No module or path found in the markdown metadata."))
    end
end

"""
    istranslated(md::Markdown.MD)

Check if a translation exists for the given Markdown document.

# Arguments
- `md::Markdown.MD`: The Markdown document to check for translation

# Returns
`true` if a translation file exists in the cache directory for the current language,
`false` otherwise.
"""
function istranslated(md::Markdown.MD)
    allowold = true
    cachedir = joinpath(pathofcachedir(md, allowold), hashmd(md))
    lang = DEFAULT_LANG[]
    mdpath = joinpath(cachedir, lang * ".md")
    isfile(mdpath)
end

"""
    load_translation(md::Markdown.MD)

Load the cached translation for a given Markdown document.

# Arguments
- `md::Markdown.MD`: The Markdown document to load the translation for

# Returns
A new `Markdown.MD` object containing the translated content.

# Details
Loads the translation file from cache, post-processes it, and parses it as Markdown.
"""
function load_translation(md::Markdown.MD)
    allowold = true
    cachedir = joinpath(pathofcachedir(md, allowold), hashmd(md))
    lang = DEFAULT_LANG[]
    mdpath = joinpath(cachedir, lang * ".md")
    Markdown.parse(postprocess_content(read(mdpath, String)))
end

"""
    cache_original(md::Markdown.MD)

Cache the original version of a Markdown document.

# Arguments
- `md::Markdown.MD`: The Markdown document to cache

# Details
Creates a cache directory if it doesn't exist and saves the original Markdown content
to 'original.md' within that directory.
"""
function cache_original(md::Markdown.MD)
    cachedir = joinpath(pathofcachedir(md), hashmd(md))
    mkpath(cachedir)
    mdpath = joinpath(cachedir, "original.md")
    write(mdpath, string(md))
end

"""
    cache_translation(md_hash_original::String, transmd::Markdown.MD)

Cache a translated version of a Markdown document.

# Arguments
- `md_hash_original::String`: The hash of the original Markdown document
- `transmd::Markdown.MD`: The translated Markdown document to cache

# Details
Creates a cache directory if it doesn't exist and saves the translated content
to a language-specific file (e.g., 'ja.md' for Japanese) within that directory.
"""
function cache_translation(md_hash_original::String, transmd::Markdown.MD)
    cachedir = joinpath(pathofcachedir(transmd), md_hash_original)
    lang = DEFAULT_LANG[]
    mdpath = joinpath(cachedir, lang * ".md")
    mkpath(cachedir)
    write(mdpath, string(transmd))
end
