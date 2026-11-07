"""
    translate_documenter_page_with_openai(source; max_attempts=3,
        fallback_model=default_fallback_model(), fallback_max_attempts=1)

Translate and validate using the primary model. Only after it fails, try the
fallback model (by default GPT-6.1 Sol, medium reasoning) on the same pristine
source. Both phases use identical Markdown validation; neither caches bad output.
Set the fallback model to `nothing` to disable escalation.

An injected `request(text, promptfn)` disables automatic network fallback unless
`fallback_request` is supplied explicitly. This keeps custom providers and offline
tests in control of all external requests.
"""
function translate_documenter_page_with_openai(
    source::AbstractString;
    max_attempts::Int = 3,
    request = page_openai_request,
    source_label::AbstractString = "Markdown input [$(first(bytes2hex(sha256(source)), 12))]",
    diagnostics_dir::Union{Nothing,AbstractString} = get(
        ENV,
        "DOCSTRINGTRANSLATION_DIAGNOSTICS_DIR",
        nothing,
    ),
    fallback_model::Union{Nothing,AbstractString} = default_fallback_model(),
    fallback_request = nothing,
    fallback_max_attempts::Int = 1,
)
    max_attempts > 0 || throw(ArgumentError("max_attempts must be positive"))
    fallback_max_attempts > 0 ||
        throw(ArgumentError("fallback_max_attempts must be positive"))
    primary_model = request === page_openai_request ? default_model() : "custom primary"
    fallback = fallback_request
    if !isnothing(fallback_model) &&
       fallback_model != primary_model &&
       request === page_openai_request &&
       isnothing(fallback)
        model = String(fallback_model)
        fallback =
            (text, promptfn) ->
                translate_with_openai(text; model, system_promptfn = promptfn, raw = true)
    end
    try
        return translate_page_attempts(
            source;
            max_attempts,
            request,
            source_label = "$source_label (model=$primary_model)",
            diagnostics_dir,
        )
    catch primary_error
        primary_error isa Union{InterruptException,OutOfMemoryError,StackOverflowError} &&
            rethrow()
        if isnothing(fallback_model) ||
           isnothing(fallback) ||
           fallback_model == primary_model
            rethrow()
        end
        primary_reason = safe_translation_error(primary_error)
        # Changing models cannot repair missing or invalid credentials.
        if primary_error isa KeyError ||
           occursin("Authentication failed (401", primary_reason)
            rethrow()
        end
        @warn "Primary translation failed; trying fallback model" source=source_label primary_model fallback_model reason=primary_reason
        try
            translated = translate_page_attempts(
                source;
                request = fallback,
                max_attempts = fallback_max_attempts,
                source_label = "$source_label (model=$fallback_model)",
                diagnostics_dir,
            )
            @info "Fallback translation succeeded" source=source_label model=fallback_model
            return translated
        catch fallback_error
            fallback_error isa
            Union{InterruptException,OutOfMemoryError,StackOverflowError} && rethrow()
            throw(
                ArgumentError(
                    "Translation failed for $source_label. Primary model $primary_model: $primary_reason. Fallback model $fallback_model: $(safe_translation_error(fallback_error))",
                ),
            )
        end
    end
end
