# DocstringTranslation.jl

DocstringTranslation.jl は、Julia のドキュメント（docstring）を自動的に翻訳するためのパッケージです。OpenAI API を利用して、ドキュメントの多言語化を支援します。
翻訳の品質は OpenAI API の性能に依存します．

(English follows Japanese)

## 主な機能

- ドキュメント文字列の自動翻訳
- 翻訳結果のキャッシュ機能
- Documenter.jl との統合

## インストール

```julia-repl
julia> using Pkg
julia> Pkg.add("DocstringTranslation")
```

OpenAI API キーの設定が必要です．環境変数 `OPENAI_API_KEY` を設定してください．必要に応じて
[OpenAI.jl](https://github.com/JuliaML/OpenAI.jl) の README も参考になるでしょう.

[DotEnv.jl](https://github.com/tecosaur/DotEnv.jl) パッケージを使用することで `OPENAI_API_KEY` を陽に設定することを避けることができます．
作業ディレクトリに `.env` ファイルを配置し，そのファイルに OpenAI API キーを設定します．

```
# .env
OPENAI_API_KEY=sk-<ほにゃらら>
```

REPL を開いて下記を実行することで自動的に `ENV["OPENAI_API_KEY"]` を設定することができます：

```julia-repl
julia> using DotEnv; DotEnv.load!()
```

実際に `ENV["OPENAI_API_KEY"]` が設定されていることを間接的に確認しましょう：

```julia-repl
julia> @assert haskey(ENV, "OPENAI_API_KEY")
```

以上で準備は完了です．

## 基本的な使い方

指数関数 $e^x$ を計算する関数 `exp` に対応する docstring を日本語で表示してみましょう．ワンライナーで実行できます．

```julia-repl
julia> using DotEnv; DotEnv.load!(); using DocstringTranslation; @switchlang! "ja"; @doc exp
  exp(x)

  xの自然基底指数を計算します。言い換えれば、ℯ^xです。

  他にexp2、exp10、およびcisも参照してください。

  例
  ≡≡

  julia> exp(1.0)
  2.718281828459045

  julia> exp(im * pi) ≈ cis(pi)
  true

  exp(A::AbstractMatrix)

  行列 A の行列指数関数を計算します。これは次のように定義されます。

  e^A = \sum_{n=0}^{\infty} \frac{A^n}{n!}.

  対称行列またはエルミート行列 A
  の場合は、固有分解（eigen）が使用され、それ以外の場合はスケーリングと平方化アルゴリズムが選択されます（詳細は
  [^H05] を参照）。

  │ [^H05]
  │
  │  Nicholas J. Higham, "The squaring and scaling method for the matrix exponential
  │  revisited", SIAM Journal on Matrix Analysis and Applications, 26(4), 2005, 1179-1193.
  │  doi:10.1137/090768539 (https://doi.org/10.1137/090768539)

  例
  ≡≡

  julia> A = Matrix(1.0I, 2, 2)
  2×2 Matrix{Float64}:
   1.0  0.0
   0.0  1.0

  julia> exp(A)
  2×2 Matrix{Float64}:
   2.71828  0.0
   0.0      2.71828
```

`@doc exp` の代わりにヘルプモードに移行し `help?> exp` を実行しても構いません．

## 設定

### 翻訳先の言語設定

`@switchlang! lang` のようにマクロを使用して翻訳先の言語を設定します：

```julia-repl
julia> @switchlang! "ja"  # 日本語に翻訳
julia> @switchlang! "de"  # ドイツ語に翻訳
```

ここで， "ja" は ISO 639-1 に登録されている日本語に対応する言語コードです．値 `lang` は OpenAI API が提供するシステムプロンプトに渡されます．
したがって，ChatGPT が `lang` の意味を適切に解釈できる限り，ユーザはこの値を自由に選択することができます．

### キャッシュディレクトリの設定

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

### ターゲットパッケージの設定

翻訳対象のパッケージを設定する場合は、以下の関数を使用します：

```julia
switchtargetpackage!("PackageName")
```

## 動作の仕組み

1. `@switchlang!` マクロが実行されると、以下の処理が行われます：
   - 翻訳先の言語が設定される
   - `Docs.parsedoc` がオーバーライドされ、翻訳エンジンが挿入される
   - `Documenter.Page` コンストラクタがオーバーライドされ、ドキュメントページ全体の翻訳が可能になる

2. ドキュメント生成時に：
   - 各ドキュメント文字列が翻訳される
   - 翻訳結果はキャッシュされ、次回以降の生成時に再利用される

## 注意事項

- 翻訳の品質は OpenAI API の性能に依存します

---

# DocstringTranslation.jl

DocstringTranslation.jl is a package for automatically translating Julia documentation (docstrings). It uses the OpenAI API to support multilingual documentation.
The translation quality depends on the performance of the OpenAI API.

## Main Features

- Automatic translation of documentation strings
- Translation result caching
- Integration with Documenter.jl

## Installation

```julia-repl
julia> using Pkg
julia> Pkg.add("DocstringTranslation")
```

You need to set up your OpenAI API key. Set the environment variable `OPENAI_API_KEY`. You may also find the
[OpenAI.jl](https://github.com/JuliaML/OpenAI.jl) README helpful.

You can avoid explicitly setting `OPENAI_API_KEY` by using the [DotEnv.jl](https://github.com/tecosaur/DotEnv.jl) package.
Place a `.env` file in your working directory and set your OpenAI API key in that file:

```
# .env
OPENAI_API_KEY=sk-<your-key-here>
```

You can automatically set `ENV["OPENAI_API_KEY"]` by opening the REPL and running:

```julia-repl
julia> using DotEnv; DotEnv.load!()
```

Let's indirectly verify that `ENV["OPENAI_API_KEY"]` is set:

```julia-repl
julia> @assert haskey(ENV, "OPENAI_API_KEY")
```

That completes the setup.

## Basic Usage

Let's display the docstring for the `exp` function, which calculates the exponential function $e^x$, in Japanese. You can do this in one line:

```julia-repl
julia> using DotEnv; DotEnv.load!(); using DocstringTranslation; @switchlang! "ja"; @doc exp
  exp(x)

  xの自然基底指数を計算します。言い換えれば、ℯ^xです。

  他にexp2、exp10、およびcisも参照してください。

  例
  ≡≡

  julia> exp(1.0)
  2.718281828459045

  julia> exp(im * pi) ≈ cis(pi)
  true

  exp(A::AbstractMatrix)

  行列 A の行列指数関数を計算します。これは次のように定義されます。

  e^A = \sum_{n=0}^{\infty} \frac{A^n}{n!}.

  対称行列またはエルミート行列 A
  の場合は、固有分解（eigen）が使用され、それ以外の場合はスケーリングと平方化アルゴリズムが選択されます（詳細は
  [^H05] を参照）。

  │ [^H05]
  │
  │  Nicholas J. Higham, "The squaring and scaling method for the matrix exponential
  │  revisited", SIAM Journal on Matrix Analysis and Applications, 26(4), 2005, 1179-1193.
  │  doi:10.1137/090768539 (https://doi.org/10.1137/090768539)

  例
  ≡≡

  julia> A = Matrix(1.0I, 2, 2)
  2×2 Matrix{Float64}:
   1.0  0.0
   0.0  1.0

  julia> exp(A)
  2×2 Matrix{Float64}:
   2.71828  0.0
   0.0      2.71828
```

Instead of `@doc exp`, you can also enter help mode and run `help?> exp`.

## Configuration

### Target Language Setting

Use the macro `@switchlang! lang` to set the target language:

```julia-repl
julia> @switchlang! "ja"  # Translate to Japanese
julia> @switchlang! "de"  # Translate to German
```

Here, "ja" is the language code for Japanese registered in ISO 639-1. The value `lang` is passed to the system prompt provided by the OpenAI API.
Therefore, as long as ChatGPT can appropriately interpret the meaning of `lang`, users can freely choose this value.

### Cache Directory Setting

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

### Target Package Setting

To set the target package for translation, use the following function:

```julia
switchtargetpackage!("PackageName")
```

## How It Works

1. When the `@switchlang!` macro is executed, the following processes occur:
   - The target language is set
   - `Docs.parsedoc` is overridden to insert the translation engine
   - The `Documenter.Page` constructor is overridden to enable translation of entire documentation pages

2. During documentation generation:
   - Each documentation string is translated
   - Translation results are cached and reused in subsequent generations

## Notes

- Translation quality depends on the performance of the OpenAI API

