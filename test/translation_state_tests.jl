@testitem "Language aliases and safe cache paths" begin
    using Test, Markdown, DocstringTranslation
    D = DocstringTranslation
    for lang in (:Japanese, "JA", :ja, "japanese")
        D._switchlang!(lang)
        @test D.default_lang() == "ja"
    end
    D._switchlang!("A custom/dialect")
    @test D.default_lang() == "A custom/dialect"
    mktempdir() do dir
        D.switchtranslationcachedir!(dir)
        D.switchtargetpackage!(Main)
        paths = String[]
        for source in (
            "Pkg/src/index",
            "/tmp/project/docs/index",
            "../outside/index",
            "/other/docs/index",
        )
            md = Markdown.parse("Hello")
            md.meta[:path] = source
            push!(paths, D.pathofcachedir(md))
            @test !startswith(relpath(last(paths), dir), "..")
        end
        @test length(unique(paths)) == 4
        md = Markdown.parse("Hello")
        md.meta[:module] = Main
        D.cache_translation(D.hashmd(md), md)
        @test D.istranslated(md)
        @test string(D.load_translation(md)) == "Hello\n"
    end
end

@testitem "Response validation rejects unusable responses" begin
    using Test, DocstringTranslation
    D = DocstringTranslation
    good = Dict(
        :choices => [
            Dict(:finish_reason => "stop", :message => Dict(:content => "translated")),
        ],
    )
    @test D.translation_content(good) == "translated"
    for response in (
        Dict(:choices => []),
        Dict(),
        Dict(
            :choices =>
                [Dict(:finish_reason => "length", :message => Dict(:content => "partial"))],
        ),
        Dict(
            :choices =>
                [Dict(:finish_reason => "stop", :message => Dict(:content => nothing))],
        ),
        Dict(
            :choices =>
                [Dict(:finish_reason => "stop", :message => Dict(:content => "  "))],
        ),
        Dict(:choices => [Dict(:finish_reason => "stop")]),
    )
        @test_throws ErrorException D.translation_content(response)
    end
end

@testitem "Cache transactions retain metadata and never save failures" begin
    using Test, Markdown, DocstringTranslation
    D = DocstringTranslation
    mktempdir() do dir
        D.switchtranslationcachedir!(dir)
        D._switchlang!(:Japanese)
        md = Markdown.parse("Hello")
        md.meta[:module] = Main
        md.meta[:path] = "example.jl"
        md.meta[:docstring_translation] = true
        @test_throws ErrorException D.cached_translation(
            md;
            translator = _ -> error("API failure"),
            available = true,
        )
        @test !D.istranslated(md)
        result = D.cached_translation(
            md;
            translator = _ -> Markdown.parse("こんにちは"),
            available = true,
        )
        @test result.meta[:path] == "example.jl"
        @test occursin("こんにちは", string(result))
        D._switchlang!("ja")
        cached = D.cached_translation(
            md;
            translator = _ -> error("must use cache"),
            available = false,
        )
        @test string(cached) == string(result)
        @test cached.meta[:module] === Main
        D._switchlang!("de")
        @test string(D.cached_translation(md; available = false)) == "Hello\n"
        @test !D.istranslated(md)
    end
end

@testitem "Parsed docstrings switch from pristine originals" begin
    using Test, Markdown, DocstringTranslation
    D = DocstringTranslation
    d = Base.Docs.DocStr(
        Core.svec("Hello [world](https://example.org)."),
        nothing,
        Dict{Symbol,Any}(:module => Main, :path => "example.jl"),
    )
    d.object = Markdown.parse("Hello [world](https://example.org).")
    mktempdir() do dir
        D.switchtranslationcachedir!(dir)
        D._switchlang!("ja")
        translate = md -> Markdown.parse(replace(string(md), "Hello" => "こんにちは"))
        ja = D.translated_docstring(d; translator = translate, available = true)
        @test occursin("こんにちは", string(ja))
        @test occursin("[world](https://example.org)", string(ja))
        D._switchlang!("de")
        de = D.translated_docstring(
            d;
            translator = md -> Markdown.parse(replace(string(md), "Hello" => "Hallo")),
            available = true,
        )
        @test occursin("Hallo", string(de))
        @test !occursin("こんにちは", string(de))
        D._switchlang!(:Japanese)
        @test string(D.translated_docstring(d; available = false)) == string(ja)
        D.switchtranslationcachedir!(mktempdir())
        @test occursin("Hello", string(D.translated_docstring(d; available = false)))
    end
end

@testitem "Compatible alias and previous-version caches remain readable" begin
    using Test, Markdown, DocstringTranslation
    D = DocstringTranslation
    mktempdir() do dir
        D.switchtranslationcachedir!(dir)
        D.DOCUMENTER_TARGET_PACKAGE[] = Dict(:name => "Fixture", :version => v"1.2.0")
        D._switchlang!("ja")
        md = Markdown.parse("Hello")
        md.meta[:path] = "Fixture/src/index"
        md.meta[:documenter_page_translation] = true
        olddir = joinpath(dir, "Fixture", "1.1", "src", "index", D.hashmd(md))
        mkpath(olddir)
        write(joinpath(olddir, "Japanese.md"), "こんにちは\n")
        mkpath(D.pathofcachedir(md))
        @test D.istranslated(md)
        @test occursin("こんにちは", string(D.cached_translation(md; available = false)))
        D.cache_original(md)
        @test D.istranslated(md)
        legacy = Markdown.parse("Hello")
        legacy.meta[:module] = Main
        D.cache_translation(D.hashmd(legacy), legacy)
        legacy.meta[:docstring_translation] = true
        @test !D.istranslated(legacy)
    end
end

@testitem "Docstring translation protects full links and code" begin
    using Test, Markdown, DocstringTranslation
    D = DocstringTranslation
    fence = repeat(string(Char(96)), 3)
    source =
        "# Heading\n\nHello [world](https://example.org).\n\n" *
        fence *
        "julia\nprintln(1)\n" *
        fence *
        "\n"
    result = D.translate_docstring_with_openai(
        source;
        request = (text, prompt) ->
            replace(text, "Hello" => "こんにちは", "world" => "世界"),
    )
    @test occursin("こんにちは [world](https://example.org)", string(result))
    @test occursin("# Heading", string(result))
    @test occursin("println(1)", string(result))
end

@testitem "Offline Documenter build preserves IDs and cross-page references" begin
    using Test, Markdown, Documenter, DocstringTranslation
    D = DocstringTranslation
    mktempdir() do dir
        D.switchtranslationcachedir!(joinpath(dir, "cache"))
        D.DOCUMENTER_TARGET_PACKAGE[] = Dict(:name => "Fixture", :version => v"1.0.0")
        D._switchlang!("ja")
        mkpath(joinpath(dir, "src"))
        fence = repeat(string(Char(96)), 3)
        sources = [
            "index.md" => "# Home\n\nHello [the target](@ref target).\n\n| Function | Description |\n|:---|:---|\n| f(x) | compute value |\n",
            "other.md" =>
                "# [Target](@id target)\n\nHello [Home](@ref).\n\n" *
                fence *
                "julia\nprintln(1)\n" *
                fence *
                "\n",
        ]
        for (name, source) in sources
            path = joinpath(dir, "src", name)
            write(path, source)
            original = Markdown.parse(source)
            original.meta[:path] = path
            original.meta[:documenter_page_translation] = true
            translated = Markdown.parse(
                D.translate_documenter_page(
                    source;
                    translator = text -> replace(
                        text,
                        "Hello" => "こんにちは",
                        "Description" => "説明",
                        "compute value" => "値を計算",
                    ),
                ),
            )
            merge!(translated.meta, original.meta)
            D.cache_translation(D.hashmd(original), translated)
        end
        withenv("OPENAI_API_KEY" => nothing) do
            @switchlang! :Japanese
            Base.invokelatest(
                Documenter.makedocs;
                root = dir,
                sitename = "Translation fixture",
                modules = Module[],
                pages = ["index.md", "other.md"],
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
        home = read(joinpath(dir, "build", "index.html"), String)
        other = read(joinpath(dir, "build", "other.html"), String)
        @test occursin("こんにちは", home)
        @test occursin("値を計算", home)
        @test occursin("説明", home)
        @test occursin("other.html#target", home)
        @test occursin("id=\"target\"", other)
        @test occursin("println", other)
        @test !occursin("@ref", home)
    end
end

@testitem "Installed parsedoc hook respects cache-only language changes" begin
    using Test, Markdown, DocstringTranslation
    D = DocstringTranslation
    mktempdir() do dir
        D.switchtranslationcachedir!(dir)
        d = Base.Docs.DocStr(
            Core.svec("Hello"),
            nothing,
            Dict{Symbol,Any}(:module => Main, :path => "fixture.jl"),
        )
        withenv("OPENAI_API_KEY" => nothing) do
            @switchlang! :ja
            @test string(Base.invokelatest(Base.Docs.parsedoc, d)) == "Hello\n"
            original = d.data[:docstringtranslation_original]
            for (lang, text) in (("ja", "こんにちは"), ("de", "Hallo"))
                D._switchlang!(lang)
                translated = Markdown.parse(text)
                merge!(translated.meta, original.meta)
                D.cache_translation(D.hashmd(original), translated)
            end
            for (lang, expected) in
                ((:Japanese, "こんにちは"), (:German, "Hallo"), (:ja, "こんにちは"))
                D._switchlang!(lang)
                @test occursin(expected, string(Base.invokelatest(Base.Docs.parsedoc, d)))
            end
        end
    end
end

@testitem "Reserved language names cannot overwrite pristine originals" begin
    using Test, Markdown, DocstringTranslation
    D = DocstringTranslation
    mktempdir() do dir
        D.switchtranslationcachedir!(dir)
        md = Markdown.parse("Pristine")
        md.meta[:module] = Main
        for lang in ("original", "Original", "../escape", "/absolute")
            D._switchlang!(lang)
            translated = D.cached_translation(
                md;
                translator = _ -> Markdown.parse("Translated"),
                available = true,
            )
            @test occursin("Translated", string(translated))
            @test read(
                joinpath(D.pathofcachedir(md), D.hashmd(md), "original.md"),
                String,
            ) == "Pristine\n"
        end
        @test !isfile(joinpath(dir, "escape.md"))
    end
end

@testitem "Encoded cache filenames are not treated as language aliases" begin
    using Test, Markdown, DocstringTranslation
    D = DocstringTranslation
    mktempdir() do dir
        D.switchtranslationcachedir!(dir)
        original = Markdown.parse("Hello")
        original.meta[:module] = Main
        D._switchlang!("A/B")
        D.cached_translation(
            original;
            translator = _ -> Markdown.parse("Dialect A"),
            available = true,
        )
        D._switchlang!("encoded-412f42")
        @test !D.istranslated(original)
        @test string(D.cached_translation(original; available = false)) == "Hello\n"
    end
end

@testitem "Docstring display math survives translation and cache reload" begin
    using Test, Markdown, DocstringTranslation
    D = DocstringTranslation
    fence = repeat(string(Char(96)), 3)
    native = Markdown.parse("Hello\n\n" * fence * "math\nx^2 + y^2\n" * fence)
    # Docs.formatdoc wraps parsed Markdown inside another Markdown.MD.
    doc = Markdown.MD(Any[native])
    doc.meta[:module] = Main
    doc.meta[:docstring_translation] = true
    mktempdir() do dir
        D.switchtranslationcachedir!(dir)
        D._switchlang!("ja")
        translated = D.cached_translation(
            doc;
            available = true,
            translator = md -> D.translate_docstring_with_openai(
                md;
                request = (text, prompt) -> replace(text, "Hello" => "こんにちは"),
            ),
        )
        @test occursin("こんにちは", string(translated))
        @test translated.content[2] isa Markdown.LaTeX
        @test translated.content[2].formula == "x^2 + y^2"
        restored = D.cached_translation(doc; available = false)
        @test restored.content[2] isa Markdown.LaTeX
        @test restored.content[2].formula == "x^2 + y^2"
    end
end
