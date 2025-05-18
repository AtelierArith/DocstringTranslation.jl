function prevminor(v::VersionNumber)
    return VersionNumber(v.major, v.minor - 1, 0)
end

function insertversion(svec::AbstractVector, v::VersionNumber)
    major = v.major
    minor = v.minor
    insert!(deepcopy(svec), 2, "$(major).$(minor)")
end

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
        v = VERSION
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

function istranslated(md::Markdown.MD)
    allowold = true
    cachedir = joinpath(pathofcachedir(md, allowold), hashmd(md))
    lang = DEFAULT_LANG[]
    mdpath = joinpath(cachedir, lang * ".md")
    isfile(mdpath)
end

function load_translation(md::Markdown.MD)
    allowold = true
    cachedir = joinpath(pathofcachedir(md, allowold), hashmd(md))
    lang = DEFAULT_LANG[]
    mdpath = joinpath(cachedir, lang * ".md")
    Markdown.parse(postprocess_content(read(mdpath, String)))
end

function cache_original(md::Markdown.MD)
    cachedir = joinpath(pathofcachedir(md), hashmd(md))
    mkpath(cachedir)
    mdpath = joinpath(cachedir, "original.md")
    write(mdpath, string(md))
end

function cache_translation(md_hash_original::String, transmd::Markdown.MD)
    cachedir = joinpath(pathofcachedir(transmd), md_hash_original)
    lang = DEFAULT_LANG[]
    mdpath = joinpath(cachedir, lang * ".md")
    mkpath(cachedir)
    write(mdpath, string(transmd))
end
