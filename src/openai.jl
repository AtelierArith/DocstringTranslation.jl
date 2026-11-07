const DEFAULT_MODEL = Ref{String}("gpt-6-luna")

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
- Skip the translation of `Extended Help` since it has a special meaning in Julia.
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
- Preserve every marker beginning with DTPROTECTED exactly once.
- A marker containing URL identifies a URL: never exchange it with another marker; if it is a link destination, keep it in that link destination.
- Markers containing CODE represent code or mathematics; keep them in their original paragraph or table cell.
- Markers containing BLOCK represent complete blocks; keep each in its original position.
- Preserve all Markdown structure, including tables, links, and paragraphs.
- Translate link display text and table prose.
- Return only the resulting Markdown text, without a surrounding code fence.
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
    raw::Bool = false,
)
    provider = OpenAI.OpenAIProvider(
        api_key=ENV["OPENAI_API_KEY"],
        base_url=get(ENV, "OPENAI_BASE_URL_OVERRIDE", "https://api.openai.com/v1")
    )
    try
        c = create_chat(
            provider,
            model,
            [
                Dict("role" => "system", "content" => system_promptfn(lang)),
                Dict("role" => "user", "content" => string(doc)),
            ];
            reasoning_effort = "none",
            temperature = 0,
        )
        choice = c.response[:choices][begin]
        get(choice, :finish_reason, nothing) == "stop" ||
            error("Translation did not finish successfully: $(get(choice, :finish_reason, nothing))")
        content = choice[:message][:content]
        content isa AbstractString && !isempty(strip(content)) || error("Translation returned empty content")
        return raw ? content : Markdown.parse(postprocess_content(content))
    catch e
        error_msg = string(e)
        # Check for 401 Unauthorized errors
        if occursin("401", error_msg) || occursin("Unauthorized", error_msg)
            error("""
            Authentication failed (401 Unauthorized).

            Possible causes:
            1. The OPENAI_API_KEY is invalid or expired
            2. The API key is not valid for the endpoint: $(get(ENV, "OPENAI_BASE_URL_OVERRIDE", "https://api.openai.com/v1"))
            3. The API key format is incorrect
            4. The API key was not loaded from .env file

            Please verify:
            - Your .env file contains: OPENAI_API_KEY=sk-<your-key>
            - You've run: using DotEnv; DotEnv.load!()
            - Check that the API key is set: @assert haskey(ENV, "OPENAI_API_KEY")
            - The API key is valid for the endpoint being used

            Original error: $(error_msg)
            """)
        else
            rethrow(e)
        end
    end
end


# Retry only invalid page output; never save a response that failed validation.
page_openai_request(text, prompt) = translate_with_openai(text; system_promptfn = prompt, raw = true)

function translate_documenter_page_with_openai(source::AbstractString; max_attempts::Int = 3, request = page_openai_request)
    feedback = ""
    for attempt in 1:max_attempts
        requested = Ref(false)
        try
            return translate_documenter_page(source; translator = text -> begin
                prompt = lang -> default_documenter_md_system_promptfn(lang) * feedback
                response = request(text, prompt)
                requested[] = true
                response
            end)
        catch err
            if !(err isa ArgumentError && requested[] && attempt < max_attempts)
                rethrow()
            end
            @warn "Documenter page translation failed validation; retrying" attempt exception = err
            feedback *= "\nAn earlier translation failed validation: $(sprint(showerror, err)). Preserve all markers in their original paragraph, table cell, and link destination.\n"
        end
    end
    error("Page translation attempts exhausted")
end
