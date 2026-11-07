@testitem "Only exhausted primary translations use the fallback model" begin
    using Test, DocstringTranslation
    D = DocstringTranslation
    calls = Symbol[]
    primary = (text, prompt) -> (push!(calls, :luna); "invalid")
    fallback =
        (text, prompt) -> (push!(calls, :sol); replace(text, "Hello" => "こんにちは"))
    translated = D.translate_documenter_page_with_openai(
        "# Heading\n\nHello.\n";
        request = primary,
        fallback_request = fallback,
        fallback_model = "gpt-6.1-sol",
        max_attempts = 3,
        fallback_max_attempts = 1,
    )
    @test calls == [:luna, :luna, :luna, :sol]
    @test occursin("こんにちは", translated)
    empty!(calls)
    D.translate_documenter_page_with_openai(
        "# Heading\n\nHello.\n";
        request = (text, prompt) -> (push!(calls, :luna); text),
        fallback_request = fallback,
        fallback_model = "gpt-6.1-sol",
    )
    @test calls == [:luna]
    empty!(calls)
    @test_throws ArgumentError D.translate_documenter_page_with_openai(
        "# Heading\n\nHello.\n";
        request = primary,
        fallback_request = fallback,
        fallback_model = nothing,
        max_attempts = 1,
    )
    @test calls == [:luna]
end

@testitem "Failure after both models reports both causes and remains uncached" begin
    using Test, Markdown, DocstringTranslation
    D = DocstringTranslation
    mktempdir() do dir
        D.switchtranslationcachedir!(dir)
        D._switchlang!("ja")
        md = Markdown.parse("# Heading\n\nHello.\n")
        md.meta[:module] = Main
        translator =
            doc -> Markdown.parse(
                D.translate_documenter_page_with_openai(
                    string(doc);
                    request = (_, _) -> error("primary provider outage"),
                    fallback_request = (_, _) -> "invalid fallback",
                    fallback_model = "gpt-6.1-sol",
                    max_attempts = 1,
                    fallback_max_attempts = 1,
                ),
            )
        err = try
            D.cached_translation(md; translator, available = true)
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        message = sprint(showerror, err)
        @test occursin("primary provider outage", message)
        @test occursin("gpt-6.1-sol", message)
        @test occursin("fallback", lowercase(message))
        @test !D.istranslated(md)
    end
end

@testitem "Reasoning model API parameters omit unsupported temperature" begin
    using Test, DocstringTranslation
    D = DocstringTranslation
    recorded = []
    chat_request =
        (provider, model, messages; kwargs...) -> begin
            push!(recorded, (model = model, options = (; kwargs...), messages = messages))
            (;
                response = Dict(
                    :choices=>[
                        Dict(
                            :finish_reason=>"stop",
                            :message=>Dict(:content=>"こんにちは"),
                        ),
                    ],
                )
            )
        end
    withenv("OPENAI_API_KEY" => "offline-test-key") do
        @test_throws ArgumentError D.translate_with_openai(
            "Hello";
            request_timeout = 0,
            chat_request,
        )
        D.translate_with_openai("Hello"; model = "gpt-6-luna", chat_request)
        D.translate_with_openai("Hello"; model = "gpt-6.1-sol", chat_request)
    end
    @test recorded[1].model == "gpt-6-luna"
    @test recorded[1].options.reasoning_effort == "none"
    @test recorded[1].options.temperature == 0
    @test recorded[2].model == "gpt-6.1-sol"
    @test recorded[2].options.reasoning_effort == "medium"
    @test recorded[2].options.http_kwargs.readtimeout == 180
    @test recorded[2].options.http_kwargs.readtimeout isa Int
    @test !haskey(recorded[2].options, :temperature)
    @test recorded[2].messages[2]["content"] == "Hello"
end
