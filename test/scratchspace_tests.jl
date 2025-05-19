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

    @testset "insertversion" begin
        @testset "insertversion adds version string at index 2" begin
            svec = ["a", "b", "c"]
            v = VersionNumber(1, 2, 3)
            result = DocstringTranslation.insertversion(svec, v)
            @test result == ["a", "1.2", "b", "c"]
        end

        @testset "insertversion works with empty vector" begin
            svec = String[]
            v = VersionNumber(2, 3, 4)
            @test_throws BoundsError DocstringTranslation.insertversion(svec, v)
        end

        @testset "insertversion preserves original vector" begin
            svec = ["x", "y", "z"]
            v = VersionNumber(3, 4, 5)
            result = DocstringTranslation.insertversion(svec, v)
            @test svec == ["x", "y", "z"]  # Original vector should be unchanged
            @test result == ["x", "3.4", "y", "z"]
        end

        @testset "insertversion handles single element vector" begin
            svec = ["single"]
            v = VersionNumber(4, 5, 6)
            result = DocstringTranslation.insertversion(svec, v)
            @test result == ["single", "4.5"]
        end
    end # insertversion
end # testitem "scratchspace"
