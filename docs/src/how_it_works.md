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

### Documenter pages and docstrings

Each docstring uses the same protected translation and cache flow as pages.
The pristine docstring is retained so subsequent language changes always start
from its original content.

A Documenter Markdown page is sent to the translation service as one request,
so the service can use the surrounding page as context. Headings, code blocks,
inline code, mathematical expressions, and complete links (including their
display text and destinations) are protected by placeholders. Table prose and
other unprotected text remain available for translation.

Before saving a translation, the package checks the placeholders and Markdown
structure. A response that loses or duplicates a placeholder, changes a link
or moves protected content to a different paragraph or table cell is rejected.
Invalid page responses are retried up to three times; if validation still fails,
the build stops and no completed translation is cached. Pages that exceed the
model's input or output limits also fail rather than caching partial results.
Some Markdown node types are not yet supported and cause a clear error instead
of being translated unsafely. Cached pages from the previous paragraph-based
implementation are not reused.

Display math is serialized with math fences and inline math with double backticks,
so Julia reads the same mathematical structure back even when translation places
an inline formula at the beginning of a paragraph.
