@testitem "JET" begin
    using Test
    using JET
    @testset "JET" begin
        JET.test_package(DocstringTranslation; target_modules = (DocstringTranslation,))
    end
end
