@testitem "switchfunction" begin

    using Test
    using DocstringTranslation

    @testset "switchtranslationcachedir! updates global variable" begin
        test_dir = mktempdir()
        DocstringTranslation.switchtranslationcachedir!(test_dir)
        @test DocstringTranslation.TRANSLATION_CACHE_DIR[] == test_dir
        rm(test_dir, recursive = true)
    end

    @testset "switchtranslationcachedir! returns new directory path" begin
        test_dir = mktempdir()
        result = DocstringTranslation.switchtranslationcachedir!(test_dir)
        @test result == test_dir
        @test DocstringTranslation.TRANSLATION_CACHE_DIR[] == test_dir
        rm(test_dir, recursive = true)
    end

end
