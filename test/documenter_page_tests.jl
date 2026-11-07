@testitem "Documenter page translation protects structure" begin
    using Test
    using DocstringTranslation: translate_documenter_page

    source = """
    # Original heading

    Hello [world](https://example.org/a_(b)) and [world](https://example.org/a_(b)).

    ```@example demo
    println("Hello")
    ```

    See [the section](@ref target).
    """
    requests = String[]
    translator =
        text -> begin
            push!(requests, text)
            replace(text, "Hello" => "こんにちは", "world" => "世界", "the section" => "節")
        end
    result = translate_documenter_page(source; translator)
    @test length(requests) == 1
    @test occursin("# Original heading", result)
    @test occursin("こんにちは [world](https://example.org/a_(b))", result)
    @test occursin("[the section](@ref target)", result)
    @test occursin("println(\"Hello\")", result)
    @test !occursin("println(\"Hello\")", only(requests))
    @test_throws Exception translate_documenter_page(source; translator = _ -> "broken")
end

@testitem "Restored table code preserves escaped pipe operators" begin
    using Test, Markdown
    using DocstringTranslation: translate_documenter_page
    for cell in ("`a \\| b`", "**`a \\| b`**", "`!read & write \\| truncate \\| append`")
        source = "| Name | Default |\n|:---|:---|\n| open | $cell |\n"
        result = translate_documenter_page(source; translator = identity)
        @test string(Markdown.parse(result)) == string(Markdown.parse(source))
    end
end

@testitem "Documenter page rejects corrupted structure" begin
    using Test
    using DocstringTranslation: translate_documenter_page
    source = "# Title\n\nHello [world](https://example.org).\n"
    @test_throws ArgumentError translate_documenter_page(
        source;
        translator = s -> replace(s, "Hello" => "# Hello"),
    )
end

@testitem "Documenter tables and mathematics" begin
    using Test
    using DocstringTranslation: translate_documenter_page
    source = """
    # Heading

    | Function | Description |
    |:---------|:------------|
    | [`f(x)`](@ref f) | compute ``x^2`` |
    """
    result = translate_documenter_page(
        source;
        translator = s -> replace(s, "Description" => "説明", "compute" => "計算"),
    )
    @test occursin("# Heading", result)
    @test occursin("説明", result)
    @test occursin("計算", result)
    @test occursin("[\u0060f(x)\u0060](@ref f)", result)
    @test occursin("x^2", result)
end

@testitem "Documenter page rejects missing and duplicate markers" begin
    using Test
    using DocstringTranslation: translate_documenter_page
    source = "# Heading\n\nText.\n"
    @test_throws ArgumentError translate_documenter_page(source; translator = _ -> "Text.")
    @test_throws ArgumentError translate_documenter_page(source; translator = s -> s * s)
    @test_throws ArgumentError translate_documenter_page(source; translator = _ -> "  ")
end

@testitem "Invalid page output is retried without caching" begin
    using Test
    using DocstringTranslation: translate_documenter_page_with_openai
    calls = Ref(0)
    request =
        (text, prompt) -> begin
            calls[] += 1
            calls[] == 1 ? "invalid" : replace(text, "Hello" => "こんにちは")
        end
    result = translate_documenter_page_with_openai("# Heading\n\nHello.\n"; request)
    @test calls[] == 2
    @test occursin("こんにちは", result)
end

@testitem "Nested code blocks retain their enclosing structure" begin
    using Test, Markdown
    using DocstringTranslation: translate_documenter_page
    for source in (
        "> ```julia\n> println(1)\n> ```\n",
        "- item\n\n  ```julia\n  println(1)\n  ```\n",
        "!!! note\n    ```julia\n    println(1)\n    ```\n",
    )
        result = translate_documenter_page(source; translator = identity)
        original_ast = Markdown.parse(source)
        result_ast = Markdown.parse(result)
        @test typeof(result_ast.content[1]) == typeof(original_ast.content[1])
        @test string(result_ast) == string(original_ast)
    end
end

@testitem "Bare URLs and autolinks are protected" begin
    using Test
    using DocstringTranslation: translate_documenter_page
    source = "Visit https://example.com/docs and <https://example.com/path>.\n"
    result = translate_documenter_page(
        source;
        translator = s -> replace(s, "https://example.com" => "https://bad.test"),
    )
    @test occursin("https://example.com/docs", result)
    @test occursin("https://example.com/path", result)
end

@testitem "Footnotes and horizontal rules retain their meaning" begin
    using Test, Markdown
    using DocstringTranslation: translate_documenter_page
    source = "A[^1]\n\n---\n\n[^1]: footnote text\n"
    result = translate_documenter_page(source; translator = identity)
    @test string(Markdown.parse(result)) == string(Markdown.parse(source))
end

@testitem "Page cache preserves dollar signs in code" begin
    using Test, Markdown, DocstringTranslation
    D = DocstringTranslation
    old_cache, old_target = D.TRANSLATION_CACHE_DIR[], D.DOCUMENTER_TARGET_PACKAGE[]
    mktempdir() do dir
        try
            D.TRANSLATION_CACHE_DIR[] = dir
            D.DOCUMENTER_TARGET_PACKAGE[] =
                Dict(:name => "TestPackage", :version => v"1.0.0")
            D.DEFAULT_LANG[] = "ja"
            original = Markdown.parse(raw"""
            ```julia
            println("$$hello$$")
            ```
            """)
            original.meta[:path] = "TestPackage/src/index"
            original.meta[:documenter_page_translation] = true
            D.cache_translation(D.hashmd(original), original)
            restored = D.load_translation(original)
            @test restored.content[1].code == original.content[1].code
        finally
            D.TRANSLATION_CACHE_DIR[] = old_cache
            D.DOCUMENTER_TARGET_PACKAGE[] = old_target
        end
    end
end

@testitem "Complete links including nested markup are protected" begin
    using Test
    using DocstringTranslation: translate_documenter_page
    source = "See [function `x`](https://example.org) and [function `x`](https://example.org).\n"
    requests = String[]
    translator =
        text -> begin
            push!(requests, text)
            replace(
                text,
                "See" => "参照",
                "function" => "関数",
                "example.org" => "bad.test",
            )
        end
    result = translate_documenter_page(source; translator)
    @test occursin("参照", result)
    @test count("[function `x`](https://example.org)", result) == 2
    @test !occursin("function", only(requests))
    @test !occursin("example.org", only(requests))
end

@testitem "Protected blocks cannot be joined to prose" begin
    using Test
    using DocstringTranslation: translate_documenter_page
    source = "# Heading\n\nText.\n"
    corrupt = s -> replace(s, r"(DTPROTECTED[A-Z0-9]+XBLOCK\d+END)" => s"oops \1")
    @test_throws ArgumentError translate_documenter_page(source; translator = corrupt)
end

@testitem "Code in a quote nested inside a list remains nested" begin
    using Test, Markdown
    using DocstringTranslation: translate_documenter_page
    source = "- > ```julia\n  > println(1)\n  > ```\n"
    result = translate_documenter_page(source; translator = identity)
    @test string(Markdown.parse(result)) == string(Markdown.parse(source))
end

@testitem "Request errors are not retried as invalid translations" begin
    using Test
    using DocstringTranslation: translate_documenter_page_with_openai
    calls = Ref(0)
    request = (text, prompt) -> begin
        calls[] += 1
        throw(ArgumentError("request failed"))
    end
    @test_throws ArgumentError translate_documenter_page_with_openai("Text."; request)
    @test calls[] == 1
end

@testitem "Fenced code inside ordered list items survives restoration" begin
    using Test, Markdown
    using DocstringTranslation: translate_documenter_page

    # Markdown's printer indents ordered-list continuations by four spaces,
    # which its parser does not read back as a fence after a "1. " marker.
    for source in (
        "1. Item one:\n   ```sh\n   echo 0\n   ```\n   After.\n2. Two\n",
        "9. Nine:\n   ```sh\n   echo 9\n   ```\n10. Ten:\n    ```sh\n    echo 10\n    ```\n",
        "- Outer\n\n  1. Inner:\n     ```sh\n     echo nested\n     ```\n",
        "!!! note\n    1. In a note:\n       ```sh\n       echo note\n       ```\n",
    )
        result = translate_documenter_page(source; translator = identity)
        @test Markdown.parse(result) == Markdown.parse(source)
    end
end

@testitem "Admonitions inside list items do not end the list" begin
    using Test, Markdown
    using DocstringTranslation: translate_documenter_page

    # Admonitions print a trailing blank line; a second blank line inside a
    # list item makes Julia's parser end the list.
    for source in (
        "1. One\n\n   !!! note\n       Noted.\n\n   After the note.\n2. Two\n",
        "- One\n\n  !!! note\n      Noted.\n\n  After the note.\n- Two\n",
    )
        result = translate_documenter_page(source; translator = identity)
        @test Markdown.parse(result) == Markdown.parse(source)
    end
end

@testitem "Double-backtick math containing backticks round-trips" begin
    using Test, Markdown
    using DocstringTranslation: translate_documenter_page

    # Julia parses ``…`` as inline math; a formula that starts or ends with a
    # backtick needs padding spaces to be read back.
    for source in ("Quotes (`\"`, and `` ` ``) here.\n", "Math `` `a` `` and ``x``.\n")
        result = translate_documenter_page(source; translator = identity)
        @test Markdown.parse(result) == Markdown.parse(source)
    end
end
