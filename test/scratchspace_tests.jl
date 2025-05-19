@testitem "scratchspace" begin

    using DocstringTranslation

    @testset "prevminor" begin
        @testset "prevminor decrements minor version" begin
            v = VersionNumber(1, 2, 3)
            result = DocstringTranslation.prevminor(v)
            @test result == VersionNumber(1, 1, 0)
            @test result.major == v.major
            @test result.minor == v.minor - 1
            @test result.patch == 0
        end

        @testset "prevminor returns VersionNumber with patch set to 0" begin
            v = VersionNumber(2, 3, 4)
            result = DocstringTranslation.prevminor(v)
            @test result == VersionNumber(2, 2, 0)
            @test result.patch == 0
        end

        @testset "prevminor keeps major version unchanged" begin
            v = VersionNumber(3, 5, 2)
            result = DocstringTranslation.prevminor(v)
            @test result.major == v.major
            @test result == VersionNumber(3, 4, 0)
        end

        @testset "prevminor returns 1.0.0 when input is 1.1.0" begin
            v = VersionNumber(1, 1, 0)
            result = DocstringTranslation.prevminor(v)
            @test result == VersionNumber(1, 0, 0)
            @test result.major == 1
            @test result.minor == 0
            @test result.patch == 0
        end
    end # prevminor
end # testitem "scratchspace"
