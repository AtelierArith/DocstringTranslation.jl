# Caching translated results

English follows Japanese

## キャッシュディレクトリの設定

REPL のセッションを起動する度に OpenAI API 毎回呼び出すことを避けるために，DocstringTranslation パッケージは
翻訳結果をキャッシュする機能を実装しています．この機能は [Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl) パッケージ
によって実現されています．デフォルトでは `joinpath(DEPOT_PATH[1], "scratchspaces", "d404e13b-1f8e-41a5-a26a-0b758a0c6c97", "translation")` 以下に格納されます．
要するに `~/.julia/scratchspaces/d404e13b-1f8e-41a5-a26a-0b758a0c6c97/translation` のことです．`d404e13b-1f8e-41a5-a26a-0b758a0c6c97` は我々のパッケージ DocstringTranslation の UUID を指しています．
`tree` コマンドでディレクトリの構造を調べてみましょう：

```
$ tree ~/.julia/scratchspaces/d404e13b-1f8e-41a5-a26a-0b758a0c6c97/translation
├── Base
│   └── 1.11
│       └── Math
│           └── 77be4ada26c623c913ebbdae5d8450a4dfe8f3cbf67837faac9d7193342d2bfe
│               ├── ja.md
│               └── original.md
└── LinearAlgebra
    └── 1.11
        └── 46c0494a8a2adffc6f71752b60448da1743997b5b1791b71e3830113e9b9cc46
            ├── ja.md
            └── original.md

8 directories, 4 files
```

`@doc exp` を実行することで Julia は `exp` に関する docstring を収集します．先ほどのデモンストレーションでは `exp(x)` と `exp(A::AbstractMatrix)` に対する２種類の docstring を収集していました．各は Math v1.11, LinearAlgebra v1.11 モジュール内で定義されているのでこのようなディレクトリ構造が生まれます．
`77be4ada26c623c913ebbdae5d8450a4dfe8f3cbf67837faac9d7193342d2bfe` や `46c0494a8a2adffc6f71752b60448da1743997b5b1791b71e3830113e9b9cc46` などは原文 (`original.md` に格納されている格納する) のハッシュ値です．`original.md` は手動で変更しないでください．翻訳結果に不満があれば `ja.md` を編集することで所望の翻訳結果を得ることができます．

翻訳結果のキャッシュディレクトリを変更する場合は、以下の関数を使用します：

```julia
switchtranslationcachedir!("path/to/cache/directory")
```

---

## Target Language Setting

Use the macro `@switchlang! lang` to set the target language:

```julia-repl
julia> @switchlang! "ja"  # Translate to Japanese
julia> @switchlang! "de"  # Translate to German
```

Here, "ja" is the language code for Japanese registered in ISO 639-1. The value `lang` is passed to the system prompt provided by the OpenAI API.
Therefore, as long as ChatGPT can appropriately interpret the meaning of `lang`, users can freely choose this value.

## Cache Directory Setting

To avoid calling the OpenAI API every time you start a REPL session, the DocstringTranslation package implements
a caching feature for translation results. This feature is implemented using the [Scratch.jl](https://github.com/JuliaPackaging/Scratch.jl) package.
By default, it is stored under `joinpath(DEPOT_PATH[1], "scratchspaces", "d404e13b-1f8e-41a5-a26a-0b758a0c6c97", "translation")`.
In other words, `~/.julia/scratchspaces/d404e13b-1f8e-41a5-a26a-0b758a0c6c97/translation`. The UUID `d404e13b-1f8e-41a5-a26a-0b758a0c6c97` refers to our package DocstringTranslation.
Let's examine the directory structure using the `tree` command:

```
$ tree ~/.julia/scratchspaces/d404e13b-1f8e-41a5-a26a-0b758a0c6c97/translation
├── Base
│   └── 1.11
│       └── Math
│           └── 77be4ada26c623c913ebbdae5d8450a4dfe8f3cbf67837faac9d7193342d2bfe
│               ├── ja.md
│               └── original.md
└── LinearAlgebra
    └── 1.11
        └── 46c0494a8a2adffc6f71752b60448da1743997b5b1791b71e3830113e9b9cc46
            ├── ja.md
            └── original.md

8 directories, 4 files
```

When you run `@doc exp`, Julia collects the docstrings related to `exp`. In the previous demonstration, we collected two types of docstrings for `exp(x)` and `exp(A::AbstractMatrix)`. Since each is defined within the Math v1.11 and LinearAlgebra v1.11 modules, this directory structure is created.
The hashes like `77be4ada26c623c913ebbdae5d8450a4dfe8f3cbf67837faac9d7193342d2bfe` and `46c0494a8a2adffc6f71752b60448da1743997b5b1791b71e3830113e9b9cc46` are hash values of the original text (stored in `original.md`). Do not modify `original.md` manually. If you are dissatisfied with the translation results, you can edit `ja.md` to obtain the desired translation.

To change the cache directory for translation results, use the following function:

```julia
switchtranslationcachedir!("path/to/cache/directory")
```
