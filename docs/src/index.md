# DocstringTranslation.jl

DocstringTranslation.jl は、Julia のドキュメント文字列（docstring）を自動的に翻訳するためのパッケージです。OpenAI API を利用して、ドキュメントの多言語化を支援します。

## 主な機能

- ドキュメント文字列の自動翻訳
- 翻訳結果のキャッシュ機能
- Documenter.jl との統合
- 複数言語への対応

## インストール

```julia
using Pkg
Pkg.add("DocstringTranslation")
```

## 基本的な使い方

```julia
using DocstringTranslation

# 翻訳先の言語を設定（例：日本語）
@switchlang! "ja"

# これ以降、ドキュメントの生成時に自動的に翻訳が行われます
```

## 設定

### 翻訳先の言語設定

`@switchlang!` マクロを使用して翻訳先の言語を設定します：

```julia
@switchlang! "ja"  # 日本語に翻訳
@switchlang! "en"  # 英語に翻訳
```

### キャッシュディレクトリの設定

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

- OpenAI API の利用には、適切な API キーの設定が必要です
- 翻訳の品質は OpenAI API の性能に依存します
- キャッシュを活用することで、API の使用量を抑えることができます

## ライセンス

MIT License

---

# DocstringTranslation.jl

DocstringTranslation.jl is a package for automatically translating Julia docstrings. It uses the OpenAI API to help with documentation internationalization.

## Key Features

- Automatic docstring translation
- Translation result caching
- Integration with Documenter.jl
- Support for multiple languages

## Installation

```julia
using Pkg
Pkg.add("DocstringTranslation")
```

## Basic Usage

```julia
using DocstringTranslation

# Set target language (e.g., Japanese)
@switchlang! "ja"

# From this point, docstrings will be automatically translated during documentation generation
```

## Configuration

### Setting Target Language

Use the `@switchlang!` macro to set the target language:

```julia
@switchlang! "ja"  # Translate to Japanese
@switchlang! "en"  # Translate to English
```

### Setting Cache Directory

To change the cache directory for translation results, use the following function:

```julia
switchtranslationcachedir!("path/to/cache/directory")
```

### Setting Target Package

To set the target package for translation, use the following function:

```julia
switchtargetpackage!("PackageName")
```

## How It Works

1. When the `@switchlang!` macro is executed, the following processes occur:
   - Target language is set
   - `Docs.parsedoc` is overridden to insert the translation engine
   - `Documenter.Page` constructor is overridden to enable translation of entire documentation pages

2. During documentation generation:
   - Each docstring is translated
   - Translation results are cached for reuse in subsequent generations

## Notes

- OpenAI API key configuration is required
- Translation quality depends on the OpenAI API performance
- API usage can be reduced by utilizing the cache

## License

MIT License
