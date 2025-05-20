using DocstringTranslation
using Documenter

DocMeta.setdocmeta!(DocstringTranslation, :DocTestSetup, :(using DocstringTranslation); recursive=true)

makedocs(;
    modules=[DocstringTranslation],
    authors="Satoshi Terasaki <terasakisatoshi.math@gmail.com> and contributors",
    sitename="DocstringTranslation.jl",
    format=Documenter.HTML(;
        canonical="https://atelierarith.github.io/DocstringTranslation.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
        "Caching translated docstrings" => "caching.md",
        "Translation of Julia's official documentation" => "julia_documentation.md",
    	"API" => "api.md",
    ],
)

deploydocs(;
    repo="github.com/AtelierArith/DocstringTranslation.jl",
    devbranch="main",
)
