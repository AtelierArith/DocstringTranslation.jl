@testitem "Aqua" begin
    using Aqua
    using Test
    using DocstringTranslation

    @testset "Aqua" begin
        Aqua.test_all(DocstringTranslation)
    end
end
