@testitem "Batch page requests overlap with a bounded worker count" begin
    using Test, DocstringTranslation
    D = DocstringTranslation
    mktempdir() do dir
        D.switchtranslationcachedir!(joinpath(dir, "cache"))
        D.switchtargetpackage!(Main)
        D._switchlang!("ja")
        paths = [joinpath(dir, "$i.md") for i = 1:5]
        for (i, path) in enumerate(paths)
            write(path, "# Heading\n\nHello $i.\n")
        end
        alias = joinpath(dir, "alias.md")
        symlink(first(paths), alias)
        active = Ref(0)
        peak = Ref(0)
        request = (text, prompt) -> begin
            active[] += 1
            peak[] = max(peak[], active[])
            try
                sleep(0.02)
                replace(text, "Hello" => "こんにちは")
            finally
                active[] -= 1
            end
        end
        result = D.translate_pages(
            [paths; first(paths); alias];
            concurrency = 2,
            request,
            available = true,
        )
        @test peak[] == 2
        @test result.translated == paths
        @test isempty(result.cached)
        @test isempty(result.failed)
        @test active[] == 0

        # A complete second pass must not contact the API, even without a key.
        cached = D.translate_pages(
            paths;
            request = (_, _) -> error("cache miss"),
            available = false,
        )
        @test cached.cached == paths
        @test isempty(cached.translated)
        @test isempty(cached.failed)
        for path in paths
            md = D.translated_page(path; available = false)
            @test occursin("こんにちは", string(md))
            @test md.meta[:path] == path
        end
        @test occursin("こんにちは", string(D.translated_page(alias; available = false)))

        # Deduplication must also populate the real path when an alias comes first.
        D.switchtranslationcachedir!(joinpath(dir, "alias-first-cache"))
        alias_first = D.translate_pages([alias, paths[1]]; request, available = true)
        @test alias_first.translated == [alias]
        @test occursin("こんにちは", string(D.translated_page(paths[1]; available = false)))
    end
end

@testitem "Default page worker pool runs thirty-two requests concurrently" begin
    using Test, DocstringTranslation
    D = DocstringTranslation
    mktempdir() do dir
        D.switchtranslationcachedir!(joinpath(dir, "cache"))
        D._switchlang!("ja")
        paths = [joinpath(dir, "$i.md") for i = 1:40]
        for (i, path) in enumerate(paths)
            write(path, "Hello $i.\n")
        end
        release = Channel{Nothing}(40)
        active = Ref(0)
        peak = Ref(0)
        request = (text, prompt) -> begin
            active[] += 1
            peak[] = max(peak[], active[])
            take!(release)
            active[] -= 1
            text
        end
        task = @async D.translate_pages(paths; request, available = true)
        try
            @test timedwait(() -> active[] >= 32, 1.0) == :ok
            @test active[] == 32
        finally
            for _ = 1:40
                put!(release, nothing)
            end
            result = fetch(task)
            @test length(result.translated) == 40
            @test isempty(result.failed)
        end
        @test peak[] == 32
    end
end

@testitem "Batch failures preserve successful peers and resume from cache" begin
    using Test, Logging, DocstringTranslation
    D = DocstringTranslation
    mktempdir() do dir
        D.switchtranslationcachedir!(joinpath(dir, "cache"))
        D.switchtargetpackage!(Main)
        D._switchlang!("ja")
        paths = [joinpath(dir, "$i.md") for i = 1:3]
        write(paths[1], "# First\n\nHello one.\n")
        write(paths[2], "# Second\n\nHello two.\n")
        write(paths[3], "# Third\n\nHello three.\n")
        request = (text, prompt) -> begin
            occursin("two", text) && error("API unavailable")
            occursin("three", text) && return "invalid output"
            replace(text, "Hello" => "こんにちは")
        end
        result = with_logger(Logging.NullLogger()) do
            D.translate_pages(paths; concurrency = 2, request, available = true)
        end
        @test result.translated == paths[1:1]
        @test first.(result.failed) == paths[2:3]
        @test last(result.failed[1]) isa ErrorException
        @test last(result.failed[2]) isa ArgumentError
        @test occursin("API unavailable", sprint(showerror, last(result.failed[1])))
        request_ok = (text, prompt) -> replace(text, "Hello" => "こんにちは")
        resumed = D.translate_pages(paths; request = request_ok, available = true)
        @test resumed.cached == paths[1:1]
        @test resumed.translated == paths[2:3]
        @test isempty(resumed.failed)
    end
end

@testitem "Batch validates worker counts and reports unreadable or unavailable pages" begin
    using Test, DocstringTranslation
    D = DocstringTranslation
    @test_throws ArgumentError D.translate_pages(String[]; concurrency = 0)
    @test_throws ArgumentError D.translate_pages(String[]; concurrency = -1)
    @test_throws ArgumentError D.translate_pages("page.md")
    @test_throws ArgumentError D.translate_pages([42])
    result = D.translate_pages(String[])
    @test isempty(result.translated) && isempty(result.cached) && isempty(result.failed)
    mktempdir() do dir
        D.switchtranslationcachedir!(joinpath(dir, "cache"))
        D.switchtargetpackage!(Main)
        D._switchlang!("ja")
        path = joinpath(dir, "page.md")
        missing = joinpath(dir, "missing.md")
        write(path, "Hello.\n")
        result = D.translate_pages([path, missing]; available = false)
        @test isempty(result.translated) && isempty(result.cached)
        @test first.(result.failed) == [path, missing]
        @test occursin("OPENAI_API_KEY", sprint(showerror, last(result.failed[1])))
    end
end

@testitem "Batch caches feed an offline Documenter build" begin
    using Test, Documenter, DocstringTranslation
    D = DocstringTranslation
    mktempdir() do dir
        D.switchtranslationcachedir!(joinpath(dir, "cache"))
        D.DOCUMENTER_TARGET_PACKAGE[] = Dict(:name => "Fixture", :version => v"1.0.0")
        D._switchlang!("ja")
        mkpath(joinpath(dir, "src"))
        paths = [joinpath(dir, "src", name) for name in ("index.md", "other.md")]
        write(paths[1], "# Home\n\nHello [target](@ref target).\n")
        write(paths[2], "# [Target](@id target)\n\nHello world.\n")
        request = (text, prompt) -> replace(text, "Hello" => "こんにちは")
        result = D.translate_pages(paths; request, available = true)
        @test result.translated == paths
        @test isempty(result.failed)
        withenv("OPENAI_API_KEY" => nothing) do
            @switchlang! "ja"
            Base.invokelatest(
                Documenter.makedocs;
                root = dir,
                sitename = "Batch fixture",
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
        @test occursin("こんにちは", other)
        @test occursin("other.html#target", home)
        @test occursin("id=\"target\"", other)
    end
end

@testitem "Batch relative sources reuse legacy page caches" begin
    using Test, Markdown, DocstringTranslation
    D = DocstringTranslation
    mktempdir() do dir
        D.switchtranslationcachedir!(joinpath(dir, "cache"))
        D.DOCUMENTER_TARGET_PACKAGE[] = Dict(:name => "Fixture", :version => v"1.0.0")
        D._switchlang!("ja")
        cd(dir) do
            mkpath("src")
            write("src/index.md", "Hello.\n")
            original = Markdown.parse("Hello.\n")
            original.meta[:path] = "Fixture/src/index"
            original.meta[:documenter_page_translation] = true
            translated = Markdown.parse("こんにちは。\n")
            merge!(translated.meta, original.meta)
            D.cache_translation(D.hashmd(original), translated)
            result = D.translate_pages(["src/index.md"]; available = false)
            @test result.cached == [abspath("src/index.md")]
            @test isempty(result.failed)
        end
    end
end

@testitem "Page caches are portable across checkout locations" begin
    using Test, DocstringTranslation
    D = DocstringTranslation
    mktempdir() do dir
        D.switchtranslationcachedir!(joinpath(dir, "cache"))
        D.DOCUMENTER_TARGET_PACKAGE[] = Dict(:name => "Fixture", :version => v"1.0.0")
        D._switchlang!("ja")
        # The same documentation checked out on a developer machine and on CI.
        local_page = joinpath(dir, "Users", "dev", "repo", "doc", "src", "index.md")
        ci_page = joinpath(dir, "home", "runner", "repo", "doc", "src", "index.md")
        for page in (local_page, ci_page)
            mkpath(dirname(page))
            write(page, "# Heading\n\nHello.\n")
        end
        request = (text, _) -> replace(text, "Hello" => "こんにちは")
        @test D.translate_pages([local_page]; request, available = true).translated ==
              [local_page]

        result = D.translate_pages([ci_page]; available = false)
        @test result.cached == [ci_page]
        @test isempty(result.failed)
        md = D.translated_page(ci_page; available = false)
        @test occursin("こんにちは", string(md))
        @test md.meta[:path] == ci_page
    end
end
