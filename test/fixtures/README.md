# Translation validation fixtures

`range-original.md` is the range-operator docstring from Julia v1.13.3,
[base/range.jl](https://github.com/JuliaLang/julia/blob/v1.13.3/base/range.jl).
Julia is distributed under the MIT license; see its
[license](https://github.com/JuliaLang/julia/blob/v1.13.3/LICENSE.md).

`range-response-protected.md` is a captured Japanese API response for that
docstring. All protected markers survive, but italic English `not` becomes
unitalicized Japanese negation. This reproduces a false rejection by the older
exact Markdown structure comparison. Tests replay the response offline.
