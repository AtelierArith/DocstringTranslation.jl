function _switchlang!(lang::Union{String,Symbol})
    DEFAULT_LANG[] = normalize_language(lang)
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

Translation failures produce a warning and fall back to pristine original Markdown;
they never become translated cache entries. Inspect `DocstringTranslation.translation_failures()`
and clear failures between builds with `DocstringTranslation.clear_translation_failures!()`.

# Example
```julia
@switchlang! "ja"  # Switch to Japanese translation
```
"""
macro switchlang!(lang)
    if !haskey(ENV, "OPENAI_API_KEY")
        @warn(
            "The OPENAI_API_KEY has not been set. Please set OPENAI_API_KEY to the environment variable to use the translation function."
        )
    end
    @eval function Docs.parsedoc(d::DocStr)
        translated_docstring(d; on_error = :fallback)
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

        mdpage = translated_page(source; on_error = :fallback)
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


# Keep the pristine object in DocStr.data, which survives subsequent parsedoc calls.
function translated_docstring(
    d::DocStr;
    translator = translate_docstring_with_openai,
    available::Bool = haskey(ENV, "OPENAI_API_KEY"),
    on_error::Symbol = :throw,
)
    original = lock(TRANSLATION_STATE_LOCK) do
        get!(d.data, :docstringtranslation_original) do
            md = copy_markdown(d.object === nothing ? Docs.formatdoc(d) : d.object)
            md.meta[:module] = d.data[:module]
            md.meta[:path] = get(d.data, :path, "")
            md.meta[:docstring_translation] = true
            md
        end
    end
    d.object = cached_translation(original; translator, available, on_error)
    return d.object
end
