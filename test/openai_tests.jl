@testitem "openai" begin
    using Test
    using DocstringTranslation
    lang = "ja" # Japanese
    @switchlang! lang
    if haskey(ENV, "OPENAI_API_KEY")
        md = @doc exp

        @testset "openai" begin
            @test occursin("例", string(md))
        end
    end
end
