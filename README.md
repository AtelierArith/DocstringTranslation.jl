# DocstringTranslation.jl

## Description

This Julia package inserts Large Language Model (LLM) hooks into the API in the Base.Docs module, giving non-English speaking users the opportunity to help smooth API comprehension.

## Prerequisite

### Install Julia

Install Julia using juliaup.

```sh
$ curl -fsSL https://install.julialang.org | sh -s -- --yes
```

### Get OpenAI API Key

Currently, this package utilizes [OpenAI.jl](https://github.com/JuliaML/OpenAI.jl), a OpenAPI wrapper for Julia. Please prepare API key. See the following resources to learn more

- [OpenAI.jl's instruction](https://github.com/JuliaML/OpenAI.jl) to learn more.
- [Developer quickstart
](https://platform.openai.com/docs/quickstart)
- [Where do I find my OpenAI API Key?](https://help.openai.com/en/articles/4936850-where-do-i-find-my-openai-api-key)

### Set `OPENAAI_API_KEY` environment variable

To use the OpenAI API, you'll need to set your API key as an environment variable named `OPENAI_API_KEY`.
Create a file named `.env` the current working directory. Add the following line to the `.env` file, replacing <your_api_key> with your actual API key:

```
OPENAI_API_KEY=sk-<your_api_key>
```

Use the [DotEnv.jl](https://github.com/tecosaur/DotEnv.jl) package to load the environment variables from the `.env` file:

```julia
using Pkg; Pkg.add("DotEnv")
using DotEnv

DotEnv.load!()
```

To ensure the API key is set correctly, use the following Julia code:

```julia
@assert haskey(ENV, "OPENAI_API_KEY")
```

This assertion will throw an error if the `OPENAI_API_KEY` environment variable is not defined.

## Usage

```sh
$ cd path/to/directory
$ julia
               _
   _       _ _(_)_     |  Documentation: https://docs.julialang.org
  (_)     | (_) (_)    |
   _ _   _| |_  __ _   |  Type "?" for help, "]?" for Pkg help.
  | | | | | | |/ _` |  |
  | | |_| | | | (_| |  |  Version 1.11.1 (2024-10-16)
 _/ |\__'_|_|_|\__'_|  |  Official https://julialang.org/ release
|__/                   |

julia> using Pkg; Pkg.activate("."); Pkg.instantiate()

julia> using DocstringTranslation

julia> using DotEnv

julia> DotEnv.load!()

julia> @switchlang! :Japanese

julia> @doc pi
  π
  pi

  定数pi。

  Unicode πはJulia
  REPLで\piと入力してからタブキーを押すことで入力できます。また、多くのエディタでも同様です。

  参照: sinpi、sincospi、deg2rad。

  例
  ≡≡

  julia> pi
  π = 3.1415926535897...

  julia> 1/2pi
  0.15915494309189535

julia> @switchlang! :German

julia> # You can also ask from help mode

help?> ℯ
"ℯ" can be typed by \euler<tab>

search: ℯ

  ℯ
  e

  Die Konstante ℯ.

  Das Unicode-Zeichen ℯ kann getippt werden, indem man \euler schreibt
  und Tab im Julia REPL, und in vielen Editoren drückt.

  Siehe auch: exp, cis, cispi.

  Beispiele
  ≡≡≡≡≡≡≡≡≡

  julia> ℯ
  ℯ = 2.7182818284590...

  julia> log(ℯ)
  1

  julia> ℯ^(im)π ≈ -1
  true

julia>
```