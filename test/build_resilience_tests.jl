@testitem "Natural Japanese emphasis and prose regrouping preserve protected content" begin
    using Test, DocstringTranslation
    D = DocstringTranslation
    source = read(joinpath(@__DIR__, "fixtures", "range-original.md"), String)
    response = read(joinpath(@__DIR__, "fixtures", "range-response-protected.md"), String)
    result = D.translate_documenter_page(source; translator = _ -> response)
    @test occursin("範囲を作成しません", result)
    @test occursin("v[:2] == v[2] != v[begin:2]", result)
    @test occursin("[`quote`](@ref)", result)
    @test !occursin("DTPROTECTED", result)
    for (source, translator) in (
        ("Use *`x`* and **`y`**.\n", s -> replace(s, "*" => "")),
        ("Use `x` and `y`.\n", s -> replace(s, " and " => "。\n\n次に ")),
    )
        result = D.translate_documenter_page(source; translator)
        @test occursin("`x`", result) && occursin("`y`", result)
    end
end

@testitem "Structural containers keep protected content in its list item or table cell" begin
    using Test, DocstringTranslation
    D = DocstringTranslation
    for source in (
        "- Use `x`.\n- Use `y`.\n",
        "| A | B |\n|:--|:--|\n| `x` | `y` |\n",
        "First.\n\n```julia\nx = 1\n```\n\nLast.\n",
    )
        translator =
            text -> begin
                markers = [
                    m.match for m in
                    eachmatch(r"DTPROTECTED[A-Z0-9]+X(?:CODE|BLOCK)\d+END", text)
                ]
                if length(markers) == 2
                    return replace(text, markers[1] => markers[2], markers[2] => markers[1])
                end
                # A code block must not move across a prose group.
                return "Last.\n\nFirst.\n\n" * only(markers) * "\n"
            end
        @test_throws ArgumentError D.translate_documenter_page(source; translator)
    end
end

@testitem "Concurrent consumers share one request for a cache identity" begin
    using Test, Markdown, DocstringTranslation
    D = DocstringTranslation
    D.clear_translation_failures!()
    mktempdir() do dir
        D.switchtranslationcachedir!(dir)
        D._switchlang!("ja")
        md = Markdown.parse("Hello.\n")
        md.meta[:module] = Main
        calls = Ref(0)
        translator = _ -> begin
            calls[] += 1
            sleep(0.02)
            Markdown.parse("こんにちは。\n")
        end
        results = Vector{Markdown.MD}(undef, 8)
        @sync for i in eachindex(results)
            @async results[i] = D.cached_translation(md; translator, available = true)
        end
        @test calls[] == 1
        @test all(result -> occursin("こんにちは", string(result)), results)
    end
end

@testitem "Documenter builds with original text after recorded translation failures" begin
    using Test, Documenter, DocstringTranslation
    D = DocstringTranslation
    D.clear_translation_failures!()
    mktempdir() do dir
        D.switchtranslationcachedir!(joinpath(dir, "cache"))
        D.DOCUMENTER_TARGET_PACKAGE[] = Dict(:name => "Fixture", :version => v"1.0.0")
        D._switchlang!("ja")
        mkpath(joinpath(dir, "src"))
        path = joinpath(dir, "src", "index.md")
        write(path, "# Home\n\nHello `x`.\n")
        request = (_, _) -> error("simulated provider outage")
        result = D.translate_pages([path]; request, available = true)
        @test length(result.failed) == 1
        withenv("OPENAI_API_KEY" => "offline-fixture-key") do
            @switchlang! "ja"
            # The recorded failure must suppress further API calls in the hook.
            Base.invokelatest(
                Documenter.makedocs;
                root = dir,
                sitename = "Fallback fixture",
                modules = Module[],
                pages = ["index.md"],
                remotes = nothing,
                format = Documenter.HTML(
                    prettyurls = false,
                    disable_git = true,
                    edit_link = nothing,
                    repolink = nothing,
                    inventory_version = "1.0.0",
                ),
            )
        end
        html = read(joinpath(dir, "build", "index.html"), String)
        @test occursin("Hello", html)
        @test occursin("<code>x</code>", html)
        @test length(D.translation_failures()) == 1
    end
    D.clear_translation_failures!()
end

@testitem "Validation reports source, location, attempts and diagnostic files" begin
    using Test, DocstringTranslation
    D = DocstringTranslation
    mktempdir() do dir
        request = (text, prompt) -> replace(text, "Hello" => "# Hello")
        err = try
            D.translate_documenter_page_with_openai(
                "# Title\n\nHello.\n";
                request,
                max_attempts = 1,
                source_label = "docs/manual/example.md",
                diagnostics_dir = dir,
            )
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        message = sprint(showerror, err)
        @test occursin("docs/manual/example.md", message)
        @test occursin("1 attempt", message)
        @test occursin("document[", message)
        @test occursin("expected", message) && occursin("got", message)
        @test occursin(dir, message)
        files = [joinpath(root, f) for (root, _, fs) in walkdir(dir) for f in fs]
        @test any(p -> endswith(p, "original.md"), files)
        @test any(p -> endswith(p, "response.md"), files)
        @test_throws ArgumentError D.translate_documenter_page_with_openai(
            "Text";
            max_attempts = 0,
        )
    end
end

@testitem "Build fallback reports once, preserves original and never caches failure" begin
    using Test, Markdown, DocstringTranslation
    D = DocstringTranslation
    D.clear_translation_failures!()
    mktempdir() do dir
        D.switchtranslationcachedir!(dir)
        D._switchlang!("ja")
        md = Markdown.parse("Hello `x`.\n")
        md.meta[:module] = Main
        md.meta[:path] = "fixture.jl"
        md.meta[:docstring_translation] = true
        calls = Ref(0)
        translator = _ -> begin
            calls[] += 1
            error("provider failed with test-secret-token")
        end
        withenv("OPENAI_API_KEY" => "test-secret-token") do
            result =
                @test_logs (:warn, r"Translation failed.*original") D.cached_translation(
                    md;
                    translator,
                    available = true,
                    on_error = :fallback,
                )
            @test string(result) == "Hello `x`.\n"
            D.cached_translation(md; translator, available = true, on_error = :fallback)
            @test calls[] == 1
            @test !D.istranslated(md)
            failures = D.translation_failures()
            @test length(failures) == 1
            @test occursin("fixture.jl", only(failures).source)
            @test !occursin("test-secret-token", only(failures).reason)
            @test occursin("[REDACTED]", only(failures).reason)
            # Strict callers still see errors, even after a build fallback.
            @test_throws ErrorException D.cached_translation(
                md;
                translator,
                available = true,
            )
            @test calls[] == 2
        end
        D.clear_translation_failures!()
        @test isempty(D.translation_failures())
        @test_throws ArgumentError D.cached_translation(md; on_error = :ignore)
    end
end

@testitem "Validation diagnostics survive the translating process" begin
    using Test, DocstringTranslation
    mktempdir() do dir
        code = """
        using DocstringTranslation
        try
            DocstringTranslation.translate_documenter_page_with_openai(
                "# Heading\\n\\nHello.\\n";
                request = (_, _) -> "invalid response", max_attempts = 1,
                diagnostics_dir = ARGS[1], source_label = "subprocess fixture")
        catch err
            err isa ArgumentError || rethrow()
        end
        """
        project = dirname(Base.active_project())
        run(
            pipeline(
                `$(Base.julia_cmd()) --startup-file=no --project=$project -e $code $dir`;
                stdout = devnull,
                stderr = devnull,
            ),
        )
        files = [joinpath(root, f) for (root, _, fs) in walkdir(dir) for f in fs]
        @test any(p -> endswith(p, "response.md"), files)
        @test any(p -> endswith(p, "error.txt"), files)
    end
end
