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
	"API" => "api.md",
    ],
)

deploydocs(;
    repo="github.com/AtelierArith/DocstringTranslation.jl",
    devbranch="main",
)
