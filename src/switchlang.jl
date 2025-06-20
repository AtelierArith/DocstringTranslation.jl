function _switchlang!(lang::Union{String,Symbol})
    DEFAULT_LANG[] = String(lang)
end

"""
	@switchlang!(lang)

Switch the target language for docstring translation and modify the documentation system to automatically translate docstrings.

# Arguments
- `lang`: The target language code (e.g., "ja", "en") to translate docstrings into.

# Details
This macro performs the following operations:
1. Sets the target language for translation
2. Overrides `Docs.parsedoc` to insert translation engine for individual docstrings
3. Overrides `Documenter.Page` constructor to enable translation of entire documentation pages

# Example
```julia
@switchlang! "ja"  # Switch to Japanese translation
```
"""
macro switchlang!(lang)
    if !haskey(ENV, "OPENAI_API_KEY")
        @warn("The OPENAI_API_KEY has not been set. Please set OPENAI_API_KEY to the environment variable to use the translation function.")
    end
    @eval function Docs.parsedoc(d::DocStr)
        if d.object === nothing
            md = Docs.formatdoc(d)
            md.meta[:module] = d.data[:module]
            md.meta[:path] = d.data[:path]
            begin # hack
                md_hash_original = hashmd(md)
                translated_md = if istranslated(md)
                    translated_md = load_translation(md)
                    translated_md.meta[:module] = d.data[:module]
                    translated_md.meta[:path] = d.data[:path]
                    translated_md
                else
                    if haskey(ENV, "OPENAI_API_KEY")
                        cache_original(md)
                        translated_md = translate_docstring_with_openai(md)
                        translated_md.meta[:module] = d.data[:module]
                        translated_md.meta[:path] = d.data[:path]
                        cache_translation(md_hash_original, translated_md)
                        # set meta again
                        translated_md
                    else
                        # do nothing when OPENAI_API_KEY is unset
                        md
                    end
                end
                md = translated_md
            end # hack
            d.object = md
        end
        d.object
    end

    # Overrides Page constructor to hack Documenter to translate docstrings
    @eval function Documenter.Page(
        source::AbstractString,
        build::AbstractString,
        workdir::AbstractString,
    )
        # The Markdown standard library parser is sensitive to line endings:
        #   https://github.com/JuliaLang/julia/issues/29344
        # This can lead to different AST and therefore differently rendered docs, depending on
        # what platform the docs are being built (e.g. when Git checks out LF files with
        # CRFL line endings on Windows). To make sure that the docs are always built consistently,
        # we'll normalize the line endings when parsing Markdown files by removing all CR characters.

        mdsrc = replace(read(source, String), '\r' => "")
        mdpage = Markdown.parse(mdsrc)
        begin # hack
            target_package = DOCUMENTER_TARGET_PACKAGE[][:name]
            mdpage.meta[:path] = joinpath(target_package, first(splitext(source)))
            cache_original(mdpage)
            @debug "Translating ..." mdpage
            mdhash_original = hashmd(mdpage)
            if !istranslated(mdpage)
                # Update mdpage object
                mdpage = translate_md!(mdpage)
                cache_translation(mdhash_original, mdpage)
            else
                mdpage = load_translation(mdpage)
            end
            @debug "Translated" mdpage
        end # hack
        mdast = try
            convert(Documenter.MarkdownAST.Node, mdpage)
        catch err
            @error """
            MarkdownAST conversion error on $(source).
            This is a bug — please report this on the Documenter issue tracker
            """
            rethrow(err)
        end
        return Documenter.Page(
            source,
            build,
            workdir,
            mdpage.content,
            Documenter.Globals(),
            mdast,
        )
    end

    quote
        local _lang = $(esc(lang))
        _switchlang!(_lang)
    end
end
