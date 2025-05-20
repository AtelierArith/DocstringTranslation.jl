# How it works

English follows Japanese

## 動作の仕組み

ソースコードレベルで知りたい場合は `DocstringTranslation.jl/src/switchlang.jl` ファイルを参照してください．

1. `@switchlang!` マクロが実行されると、以下の処理が行われます：
   - 翻訳先の言語が設定される
   - `Docs.parsedoc(d::DocStr)` がオーバーライドされ、翻訳エンジンが挿入される
   - `Documenter.Page(source::AbstractString, build::AbstractString,workdir::AbstractString,)` がオーバーライドされ、ドキュメントページ全体の翻訳が可能になる

2. ドキュメント生成時に：
   - 各ドキュメント文字列が翻訳される
   - 翻訳結果はキャッシュされ、次回以降の生成時に再利用される

---

## How It Works

Please refer to the `DocstringTranslation.jl/src/switchlang.jl` file if you want to understand at the source code level.

1. When the `@switchlang!` macro is executed, the following processes occur:
   - The target language is set
   - `Docs.parsedoc(d::DocStr)` is overridden to insert the translation engine
   - The `Documenter.Page(source::AbstractString, build::AbstractString,workdir::AbstractString,)` is overridden to enable translation of entire documentation pages

2. During documentation generation:
   - Each documentation string is translated
   - Translation results are cached and reused in subsequent generations
