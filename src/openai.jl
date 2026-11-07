const DEFAULT_MODEL = Ref{String}("gpt-6-luna")
const DEFAULT_FALLBACK_MODEL = Ref{Union{Nothing,String}}("gpt-6.1-sol")

function default_lang()
    return DEFAULT_LANG[]
end

function default_model()
    return DEFAULT_MODEL[]
end

function switchmodel!(model::String)
    DEFAULT_MODEL[] = model
end

default_fallback_model() = DEFAULT_FALLBACK_MODEL[]

"""Set the model used only after primary translation fails; `nothing` disables it."""
function switchfallbackmodel!(model::Union{Nothing,AbstractString})
    DEFAULT_FALLBACK_MODEL[] = isnothing(model) || isempty(model) ? nothing : String(model)
    return DEFAULT_FALLBACK_MODEL[]
end

function default_reasoning_effort(model::AbstractString)
    return startswith(model, "gpt-6.1-sol") || startswith(model, "gpt-6-astra") ? "medium" :
           "none"
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

function translate_docstring_with_openai(
    doc::Union{Markdown.MD,AbstractString};
    request = page_openai_request,
)
    return Markdown.parse(
        translate_documenter_page_with_openai(
            markdown_source(doc);
            request,
            source_label = doc isa Markdown.MD ? translation_source_label(doc) :
                           "docstring",
        ),
    )
end

function default_documenter_md_system_promptfn(lang)
    return """
Translate the Markdown content or text I'll paste later into $(lang).

Use natural technical prose in the target language instead of copying English word order.
Preserve meaning carefully, especially negation, conditions, alternatives and requirements.
Keep Julia identifiers and established technical names unchanged where appropriate.
Emphasis may be adapted to the translated sentence; do not omit the meaning it conveys.

You must strictly follow the rules below.

- Natural target-language word order, emphasis changes and prose paragraph reflow are allowed.
- Preserve every marker beginning with DTPROTECTED exactly once.
- Treat markers as opaque placeholders: never translate, split, rename, or wrap them in backticks or new Markdown formatting. Preserve every character, including digits.
- A marker containing URL identifies a URL: never exchange it with another marker; if it is a link destination, keep it in that link destination.
- Markers containing CODE represent code or mathematics; keep them in their original section, list item or table cell. Inline markers may change order within that context.
- Markers containing BLOCK represent complete blocks; keep each in its original position.
- Keep each BLOCK marker on its own line, preserving the surrounding list/quote/admonition indentation. Never join it to prose.
- Preserve headings, block boundaries, lists/items, tables/cells, links, quotes and admonitions.
- Keep table rows/columns and list items in their original order. Do not move protected content to another cell or list item.
- You may split or combine adjacent prose paragraphs within the same section or list item; never move content across a protected block or structural container.
- Markers containing LINK represent complete links, including their display text; preserve them unchanged.
- Translate table prose and other unprotected text.
- Return only the resulting Markdown text, without a surrounding code fence.
- Do not add explanations, translator notes, a preamble, or an extra heading.
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
    reasoning_effort::String = default_reasoning_effort(model),
    chat_request = create_chat,
    request_timeout::Integer = parse(
        Int,
        get(ENV, "DOCSTRINGTRANSLATION_REQUEST_TIMEOUT_SECONDS", "180"),
    ),
)
    request_timeout > 0 || throw(ArgumentError("request_timeout must be positive"))
    provider = OpenAI.OpenAIProvider(
        api_key = ENV["OPENAI_API_KEY"],
        base_url = get(ENV, "OPENAI_BASE_URL_OVERRIDE", "https://api.openai.com/v1"),
    )
    try
        options =
            reasoning_effort == "none" ? (; reasoning_effort, temperature = 0) :
            (; reasoning_effort)
        c = chat_request(
            provider,
            model,
            [
                Dict("role" => "system", "content" => system_promptfn(lang)),
                Dict("role" => "user", "content" => string(doc)),
            ];
            options...,
            http_kwargs = (;
                readtimeout = request_timeout,
                connect_timeout = min(30, request_timeout),
                retry = false,
            ),
        )
        content = translation_content(c.response)
        return raw ? content : Markdown.parse(postprocess_content(content))
    catch e
        error_msg = string(e)
        # Check for 401 Unauthorized errors
        if occursin("401", error_msg) || occursin("Unauthorized", error_msg)
            error(
                """
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
          """,
            )
        else
            rethrow(e)
        end
    end
end


# Retry only invalid page output; never save a response that failed validation.
page_openai_request(text, prompt) =
    translate_with_openai(text; system_promptfn = prompt, raw = true)

function translate_page_attempts(
    source::AbstractString;
    max_attempts::Int = 3,
    request = page_openai_request,
    source_label::AbstractString = "Markdown input [$(first(bytes2hex(sha256(source)), 12))]",
    diagnostics_dir::Union{Nothing,AbstractString} = get(
        ENV,
        "DOCSTRINGTRANSLATION_DIAGNOSTICS_DIR",
        nothing,
    ),
)
    max_attempts > 0 || throw(ArgumentError("max_attempts must be positive"))
    feedback = ""
    for attempt = 1:max_attempts
        requested = Ref(false)
        protected_input = Ref("")
        response_text = Ref{Any}(nothing)
        try
            return translate_documenter_page(
                source;
                source_label,
                translator = text -> begin
                    protected_input[] = text
                    prompt =
                        lang -> default_documenter_md_system_promptfn(lang) * feedback
                    response = request(text, prompt)
                    response_text[] = response
                    requested[] = true
                    response
                end,
            )
        catch err
            if !(err isa ArgumentError && requested[])
                rethrow()
            end
            reason = safe_translation_error(err)
            diagnostic_path = nothing
            if diagnostics_dir !== nothing
                try
                    mkpath(diagnostics_dir)
                    diagnostic_path = mktempdir(
                        diagnostics_dir;
                        prefix = "$(first(bytes2hex(sha256(source)), 12))-attempt$attempt-",
                        cleanup = false,
                    )
                    atomic_cache_write(joinpath(diagnostic_path, "original.md"), source)
                    atomic_cache_write(
                        joinpath(diagnostic_path, "protected.md"),
                        protected_input[],
                    )
                    atomic_cache_write(
                        joinpath(diagnostic_path, "response.md"),
                        string(response_text[]),
                    )
                    atomic_cache_write(
                        joinpath(diagnostic_path, "error.txt"),
                        "$source_label\n$reason\n",
                    )
                catch diagnostic_error
                    @warn "Could not save translation diagnostics" source=source_label reason=safe_translation_error(
                        diagnostic_error,
                    )
                end
            end
            if attempt == max_attempts
                artifact_note =
                    isnothing(diagnostic_path) ? "" : " Diagnostics: $diagnostic_path."
                throw(
                    ArgumentError(
                        "Translation of $source_label failed validation after $attempt attempt(s): $reason.$artifact_note No translated result was cached.",
                    ),
                )
            end
            @warn "Translation validation failed; retrying" source=source_label attempt max_attempts reason diagnostics=diagnostic_path
            feedback = "\nThe previous response failed validation: $reason. Preserve every protected marker, block boundary, list item and table cell; natural prose rewording and emphasis changes are allowed.\n"
        end
    end
    error("Page translation attempts exhausted")
end


# OpenAI.jl exposes response choices as symbol-keyed dictionaries.
function translation_content(response)
    choices = get(response, :choices, nothing)
    choices isa AbstractVector && !isempty(choices) ||
        error("Translation response has no choices")
    choice = first(choices)
    choice isa AbstractDict || error("Translation response has an invalid choice")
    reason = get(choice, :finish_reason, nothing)
    reason == "stop" || error("Translation did not finish successfully: $reason")
    message = get(choice, :message, nothing)
    message isa AbstractDict || error("Translation response has no message")
    content = get(message, :content, nothing)
    content isa AbstractString && !isempty(strip(content)) ||
        error("Translation returned empty content")
    return content
end
