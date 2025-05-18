@testitem "JET" begin
    using Test
    using JET
    @testset "JET" begin
        JET.test_package(DocstringTranslation; target_defined_modules = true)
    end
end
