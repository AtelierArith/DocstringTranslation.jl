const DEFAULT_MODEL = Ref{String}("gpt-4o-mini-2024-07-18")

function default_lang()
    return DEFAULT_LANG[]
end

function default_model()
    return DEFAULT_MODEL[]
end

function switchmodel!(model::String)
    DEFAULT_MODEL[] = model
end

function default_docstring_system_promptfn(lang = default_lang())
    return """
Translate the Markdown content I'll paste later into $(lang).

Please note:
- Never alter the Julia markdown formatting.
- Never change code fence such as jldoctest or math.
- Skip changing words in the form of `[xxx](@ref)` or `[xxx](@ref yyy)`.
- Do not change any URL.
- If $(lang) indicates English (e.g., "en"), return the input unchanged.

Return only the resulting text.
"""
end

function translate_docstring_with_openai(doc::Union{Markdown.MD,AbstractString})
    translate_with_openai(doc; system_promptfn = default_docstring_system_promptfn)
end

function default_documenter_md_system_promptfn(lang)
    return """
Translate the Markdown content or text I'll paste later into $(lang).

You must strictly follow the rules below.

- Do not alter the Markdown formatting.
- Return only the resulting text.
"""
end

function translate_documenter_md_with_openai(doc::Union{Markdown.MD,AbstractString})
    translate_with_openai(doc; system_promptfn = default_documenter_md_system_promptfn)
end

function translate_with_openai(
    doc::Union{Markdown.MD,AbstractString};
    lang::String = default_lang(),
    model::String = default_model(),
    system_promptfn = default_docstring_system_promptfn,
)
    c = create_chat(
        ENV["OPENAI_API_KEY"],
        model,
        [
            Dict("role" => "system", "content" => system_promptfn(lang)),
            Dict("role" => "user", "content" => string(doc)),
        ];
        temperature = 0,
    )
    content = c.response[:choices][begin][:message][:content]
    content = postprocess_content(content)
    return Markdown.parse(content)
end

function _create_hex(l::Markdown.Link)
    (bytes2hex(codeunits(join(l.text))) * "_" * bytes2hex(codeunits(l.url)))
end

function _translate!(p::Markdown.Paragraph)
    hex2link = Dict()
    link2hex = Dict()
    content = map(p.content) do c
        # Protect Link so that it does not break during translation
        if c isa Markdown.Link
            h = _create_hex(c)
            hex2link[string(h)] = c
            link2hex[c] = h
            "`" * h * "`"
        else
            c
        end
    end
    p_orig = deepcopy(p)
    p.content = content
    result = translate_documenter_md_with_openai(Markdown.MD(p))
    try
        translated_content = map(result[1].content) do c
            if c isa Markdown.Code
                if isempty(c.language)
                    if c.code in keys(hex2link)
                        _c = hex2link[c.code]
                        delete!(hex2link, c.code)
                        c = _c
                        c
                    else
                        c
                    end
                else
                    c
                end
            else
                c
            end
        end
        if isempty(hex2link)
            p.content = translated_content
        else
            @warn "Failed to translate by hex2link. Fallback to original content"
            p.content = p_orig.content
        end
    catch e
        @warn "Failed to translate by $(e)" p
        p.content = p_orig.content
    end
    nothing
end

function _translate!(list::Markdown.List)
    for item in list.items
        Base.Threads.@threads for i in item
            _translate!(i)
        end
    end
end

function _translate!(c)
    if hasproperty(c, :content)
        Base.Threads.@threads for c in c.content
            _translate!(c)
        end
    end
    c
end

function translate_md!(md::Markdown.MD)
    Base.Threads.@threads for c in md.content
        _translate!(c)
    end
    md
end
