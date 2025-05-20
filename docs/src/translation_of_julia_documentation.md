# Translation of Julia documentation

## 概要

English follows Japanese

How it works でも述べたとおり，我々のパッケージは既存のメソッドをオーバーライドすることで翻訳エンジンを挿入し，翻訳されたマークダウンの出力をユーザに提供することができます．Julia のドキュメント，そして多くのサードパーティのパッケージは Documenter.jl とマークダウンのエコシステムを元に構築されています．この状況を利用し，英語で書かれた Julia 公式ドキュメント，サードパーティのパッケージのドキュメント
を別の自然言語に翻訳することができます．マークダウンフォーマットのファイルがどのタイミングで読み込まれるかを把握し，そのタイミングをコントロールする関数・メソッドに翻訳エンジンを挿入する必要がありますが，この要件はすでに `@switchlang!` マクロが解決しています．

---

## Description

As mentioned in "How it works", our package can insert a translation engine by overriding existing methods to provide users with translated markdown output. Julia's documentation and many third-party packages are built on the Documenter.jl and markdown ecosystem. Taking advantage of this situation, we can translate Julia's official documentation and third-party package documentation written in English into other natural languages. While we need to understand when markdown format files are loaded and insert translation engines into functions and methods that control this timing, this requirement has already been solved by the `@switchlang!` macro.


## How to translate Julia documentation

### Build Julia from source

ja: Julia の公式ドキュメントを完全にビルドし，翻訳を実行するには（juliaup などで導入した Julia を使わずに） Julia 自信をビルドする必要があります．したがって，翻訳の前に下記のコマンドがローカル環境で実行できるかを確認してください．

en: To fully build and translate Julia's official documentation, you need to build Julia itself (rather than using Julia installed via juliaup etc.). Therefore, before proceeding with translation, please verify that the following commands can be executed in your local environment.


```sh
$ git clone https://github.com/JuliaLang/julia.git
$ cd julia
$ make
$ make -C doc
```

If `make -C doc` works successfully on your machine (meaning you can build the Julia documentation), you can proceed to the next section. If you encounter any errors, make sure you have all the required dependencies installed and your build environment is properly configured.

### Update `julia/doc/make.jl`

ja: 下記のパッチを `julia/doc/make.jl` に適用します． Julia 1.11.5 で動作を確認しています．
en: Apply the following patch to `julia/doc/make.jl`. This has been tested with Julia 1.11.5.

```diff
diff --git a/doc/make.jl b/doc/make.jl
index e8ccbad85c..a3f89f608b 100644
--- a/doc/make.jl
+++ b/doc/make.jl
@@ -9,6 +9,27 @@ using Pkg
 Pkg.instantiate()

 using Documenter
+
+# using DotEnv; DotEnv.load!()
+
+using DocstringTranslation
+DocstringTranslation.switchtranslationcachedir!(joinpath(dirname(dirname(@__DIR__)), "translation"))
+DocstringTranslation.switchtargetpackage!("julia")
+
+lang = "ja" # choose your favorite language
+@switchlang! lang
+
+for (i, _stdlib) in enumerate(readdir(Sys.STDLIB))
+    stdlib = Symbol(_stdlib)
+    @info "Translating docstrings in $(stdlib)"
+    @eval begin
+        import $(stdlib)
+        Base.Threads.@threads for n in names($(stdlib))
+            (Base.Docs.doc)((Base.Docs.Binding)($(stdlib), n))
+        end
+    end
+end
+
 import LibGit2

 baremodule GenStdLib end
@@ -222,6 +243,7 @@ DevDocs = [
         "devdocs/aot.md",
         "devdocs/gc-sa.md",
         "devdocs/gc.md",
+        #"devdocs/gc-mmtk.md",
         "devdocs/jit.md",
         "devdocs/builtins.md",
         "devdocs/precompile_hang.md",
@@ -241,6 +263,7 @@ DevDocs = [
         "devdocs/build/windows.md",
         "devdocs/build/freebsd.md",
         "devdocs/build/arm.md",
+        #"devdocs/build/riscv.md",
         "devdocs/build/distributing.md",
     ]
 ]
@@ -363,13 +386,13 @@ else
     )
 end

-const output_path = joinpath(buildroot, "doc", "_build", (render_pdf ? "pdf" : "html"), "en")
+const output_path = joinpath(buildroot, "doc", "_build", (render_pdf ? "pdf" : "html"), lang)
 makedocs(
     build     = output_path,
     modules   = [Main, Base, Core, [Base.root_module(Base, stdlib.stdlib) for stdlib in STDLIB_DOCS]...],
     clean     = true,
-    doctest   = ("doctest=fix" in ARGS) ? (:fix) : ("doctest=only" in ARGS) ? (:only) : ("doctest=true" in ARGS) ? true : false,
-    linkcheck = "linkcheck=true" in ARGS,
+    doctest   = false,
+    linkcheck = false,
     linkcheck_ignore = ["https://bugs.kde.org/show_bug.cgi?id=136779"], # fails to load from nanosoldier?
     checkdocs = :none,
     format    = format,
@@ -377,6 +400,7 @@ makedocs(
     authors   = "The Julia Project",
     pages     = PAGES,
     remotes   = documenter_stdlib_remotes,
+    warnonly = [:cross_references, :footnote, :eval_block]
 )

 # Update URLs to external stdlibs (JuliaLang/julia#43199)
@@ -464,8 +488,8 @@ if "deploy" in ARGS
     deploydocs(
         repo = "github.com/JuliaLang/docs.julialang.org.git",
         deploy_config = BuildBotConfig(),
-        target = joinpath(buildroot, "doc", "_build", "html", "en"),
-        dirname = "en",
+        target = joinpath(buildroot, "doc", "_build", "html", lang),
+        dirname = lang,
         devurl = devurl,
         versions = Versions(["v#.#", devurl => devurl]),
         archive = get(ENV, "DOCUMENTER_ARCHIVE", nothing),
```

### Update `julia/doc/Project.toml`

Apply the following patch to　`julia/doc/Project.toml`

```diff
diff --git a/doc/Project.toml b/doc/Project.toml
index dfa65cd107..b4f1f03bfa 100644
--- a/doc/Project.toml
+++ b/doc/Project.toml
@@ -1,2 +1,3 @@
 [deps]
+DocstringTranslation = "d404e13b-1f8e-41a5-a26a-0b758a0c6c97"
 Documenter = "e30172f5-a6a5-5a46-863b-614d45cd2de4"
```

### Update `julia/doc/Manifest.toml`

Apply the following patch to　`julia/doc/Manifest.toml`

```diff
diff --git a/doc/Manifest.toml b/doc/Manifest.toml
index 76bdc332ff..fb4d338cd1 100644
--- a/doc/Manifest.toml
+++ b/doc/Manifest.toml
@@ -1,8 +1,8 @@
 # This file is machine-generated - editing it directly is not advised

-julia_version = "1.11.1"
+julia_version = "1.11.5"
 manifest_format = "2.0"
-project_hash = "e0c77beb18dc1f6cce661ebd60658c0c1a77390f"
+project_hash = "1d69248681ccaf34797736d74c42d8a3677cb49d"

 [[deps.ANSIColoredPrinters]]
 git-tree-sha1 = "574baf8110975760d391c710b6341da1afa48d8c"
@@ -26,11 +26,22 @@ version = "1.11.0"
 uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"
 version = "1.11.0"

+[[deps.BitFlags]]
+git-tree-sha1 = "0691e34b3bb8be9307330f88d1a3c3f25466c24d"
+uuid = "d1d4a3ce-64b1-5f1a-9ba4-7e7e69966f35"
+version = "0.1.9"
+
 [[deps.CodecZlib]]
 deps = ["TranscodingStreams", "Zlib_jll"]
-git-tree-sha1 = "bce6804e5e6044c6daab27bb533d1295e4a2e759"
+git-tree-sha1 = "962834c22b66e32aa10f7611c08c8ca4e20749a9"
 uuid = "944b1d66-785c-5afd-91f1-9de20f533193"
-version = "0.7.6"
+version = "0.7.8"
+
+[[deps.ConcurrentUtilities]]
+deps = ["Serialization", "Sockets"]
+git-tree-sha1 = "d9d26935a0bcffc87d2613ce14c527c99fc543fd"
+uuid = "f0e56b4a-5159-44fe-b623-3e5288b988bb"
+version = "2.5.0"

 [[deps.Dates]]
 deps = ["Printf"]
@@ -38,43 +49,62 @@ uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"
 version = "1.11.0"

 [[deps.DocStringExtensions]]
-deps = ["LibGit2"]
-git-tree-sha1 = "2fb1e02f2b635d0845df5d7c167fec4dd739b00d"
+git-tree-sha1 = "e7b7e6f178525d17c720ab9c081e4ef04429f860"
 uuid = "ffbed154-4ef7-542d-bbb7-c09d3a79fcae"
-version = "0.9.3"
+version = "0.9.4"
+
+[[deps.DocstringTranslation]]
+deps = ["Documenter", "Markdown", "OpenAI", "SHA", "Scratch"]
+git-tree-sha1 = "199744cf6fea89695458269649354f5817a568e6"
+repo-rev = "main"
+repo-url = "https://github.com/AtelierArith/DocstringTranslation.jl.git"
+uuid = "d404e13b-1f8e-41a5-a26a-0b758a0c6c97"
+version = "0.1.0"

 [[deps.Documenter]]
-deps = ["ANSIColoredPrinters", "AbstractTrees", "Base64", "CodecZlib", "Dates", "DocStringExtensions", "Downloads", "Git", "IOCapture", "InteractiveUtils", "JSON", "LibGit2", "Logging", "Markdown", "MarkdownAST", "Pkg", "PrecompileTools", "REPL", "RegistryInstances", "SHA", "TOML", "Test", "Unicode"]
-git-tree-sha1 = "d0ea2c044963ed6f37703cead7e29f70cba13d7e"
+deps = ["ANSIColoredPrinters", "AbstractTrees", "Base64", "CodecZlib", "Dates", "DocStringExtensions", "Downloads", "Git", "IOCapture", "InteractiveUtils", "JSON", "Logging", "Markdown", "MarkdownAST", "Pkg", "PrecompileTools", "REPL", "RegistryInstances", "SHA", "TOML", "Test", "Unicode"]
+git-tree-sha1 = "6c182d0bd94142d7cbc3ae8a1e74668f15d0dd65"
 uuid = "e30172f5-a6a5-5a46-863b-614d45cd2de4"
-version = "1.8.0"
+version = "1.11.4"

 [[deps.Downloads]]
 deps = ["ArgTools", "FileWatching", "LibCURL", "NetworkOptions"]
 uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"
 version = "1.6.0"

+[[deps.ExceptionUnwrapping]]
+deps = ["Test"]
+git-tree-sha1 = "d36f682e590a83d63d1c7dbd287573764682d12a"
+uuid = "460bff9d-24e4-43bc-9d9f-a8973cb893f4"
+version = "0.1.11"
+
 [[deps.Expat_jll]]
 deps = ["Artifacts", "JLLWrappers", "Libdl"]
-git-tree-sha1 = "1c6317308b9dc757616f0b5cb379db10494443a7"
+git-tree-sha1 = "d55dffd9ae73ff72f1c0482454dcf2ec6c6c4a63"
 uuid = "2e619515-83b5-522b-bb60-26c02a35a201"
-version = "2.6.2+0"
+version = "2.6.5+0"

 [[deps.FileWatching]]
 uuid = "7b1f6079-737a-58dc-b8bc-7a2ca5c1b5ee"
 version = "1.11.0"

 [[deps.Git]]
-deps = ["Git_jll"]
-git-tree-sha1 = "04eff47b1354d702c3a85e8ab23d539bb7d5957e"
+deps = ["Git_jll", "JLLWrappers", "OpenSSH_jll"]
+git-tree-sha1 = "2230a9cc32394b11a3b3aa807a382e3bbab1198c"
 uuid = "d7ba0133-e1db-5d97-8f8c-041e4b3a1eb2"
-version = "1.3.1"
+version = "1.4.0"

 [[deps.Git_jll]]
 deps = ["Artifacts", "Expat_jll", "JLLWrappers", "LibCURL_jll", "Libdl", "Libiconv_jll", "OpenSSL_jll", "PCRE2_jll", "Zlib_jll"]
-git-tree-sha1 = "ea372033d09e4552a04fd38361cd019f9003f4f4"
+git-tree-sha1 = "2f6d6f7e6d6de361865d4394b802c02fc944fc7c"
 uuid = "f8c6e375-362e-5223-8a59-34ff63f689eb"
-version = "2.46.2+0"
+version = "2.49.0+0"
+
+[[deps.HTTP]]
+deps = ["Base64", "CodecZlib", "ConcurrentUtilities", "Dates", "ExceptionUnwrapping", "Logging", "LoggingExtras", "MbedTLS", "NetworkOptions", "OpenSSL", "PrecompileTools", "Random", "SimpleBufferStream", "Sockets", "URIs", "UUIDs"]
+git-tree-sha1 = "f93655dc73d7a0b4a368e3c0bce296ae035ad76e"
+uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
+version = "1.10.16"

 [[deps.IOCapture]]
 deps = ["Logging", "Random"]
@@ -89,9 +119,9 @@ version = "1.11.0"

 [[deps.JLLWrappers]]
 deps = ["Artifacts", "Preferences"]
-git-tree-sha1 = "be3dc50a92e5a386872a493a10050136d4703f9b"
+git-tree-sha1 = "a007feb38b422fbdab534406aeca1b86823cb4d6"
 uuid = "692b3bcd-3c85-4b1f-b108-f13ce0eb3210"
-version = "1.6.1"
+version = "1.7.0"

 [[deps.JSON]]
 deps = ["Dates", "Mmap", "Parsers", "Unicode"]
@@ -99,6 +129,18 @@ git-tree-sha1 = "31e996f0a15c7b280ba9f76636b3ff9e2ae58c9a"
 uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
 version = "0.21.4"

+[[deps.JSON3]]
+deps = ["Dates", "Mmap", "Parsers", "PrecompileTools", "StructTypes", "UUIDs"]
+git-tree-sha1 = "196b41e5a854b387d99e5ede2de3fcb4d0422aae"
+uuid = "0f8b85d8-7281-11e9-16c2-39a750bddbf1"
+version = "1.14.2"
+
+    [deps.JSON3.extensions]
+    JSON3ArrowExt = ["ArrowTypes"]
+
+    [deps.JSON3.weakdeps]
+    ArrowTypes = "31f734f8-188a-4ce0-8406-c8a06bd891cd"
+
 [[deps.LazilyInitializedFields]]
 git-tree-sha1 = "0f2da712350b020bc3957f269c9caad516383ee0"
 uuid = "0e77f7df-68c5-4e49-93ce-4cd80f5598bf"
@@ -135,14 +177,20 @@ version = "1.11.0"

 [[deps.Libiconv_jll]]
 deps = ["Artifacts", "JLLWrappers", "Libdl"]
-git-tree-sha1 = "61dfdba58e585066d8bce214c5a51eaa0539f269"
+git-tree-sha1 = "be484f5c92fad0bd8acfef35fe017900b0b73809"
 uuid = "94ce4f54-9a6c-5748-9c1c-f9c7231a4531"
-version = "1.17.0+1"
+version = "1.18.0+0"

 [[deps.Logging]]
 uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"
 version = "1.11.0"

+[[deps.LoggingExtras]]
+deps = ["Dates", "Logging"]
+git-tree-sha1 = "f02b56007b064fbfddb4c9cd60161b6dd0f40df3"
+uuid = "e6f89c97-d47a-5376-807f-9c37f3926c36"
+version = "1.1.0"
+
 [[deps.Markdown]]
 deps = ["Base64"]
 uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"
@@ -154,6 +202,12 @@ git-tree-sha1 = "465a70f0fc7d443a00dcdc3267a497397b8a3899"
 uuid = "d0879d2d-cac2-40c8-9cee-1863dc0c7391"
 version = "0.1.2"

+[[deps.MbedTLS]]
+deps = ["Dates", "MbedTLS_jll", "MozillaCACerts_jll", "NetworkOptions", "Random", "Sockets"]
+git-tree-sha1 = "c067a280ddc25f196b5e7df3877c6b226d390aaf"
+uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
+version = "1.1.9"
+
 [[deps.MbedTLS_jll]]
 deps = ["Artifacts", "Libdl"]
 uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"
@@ -171,11 +225,29 @@ version = "2023.12.12"
 uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"
 version = "1.2.0"

+[[deps.OpenAI]]
+deps = ["Dates", "HTTP", "JSON3"]
+git-tree-sha1 = "d69de972e2c9140a42afc83a9e3331826d73e27e"
+uuid = "e9f21f70-7185-4079-aca2-91159181367c"
+version = "0.10.1"
+
+[[deps.OpenSSH_jll]]
+deps = ["Artifacts", "JLLWrappers", "Libdl", "OpenSSL_jll", "Zlib_jll"]
+git-tree-sha1 = "cb7acd5d10aff809b4d0191dfe1956c2edf35800"
+uuid = "9bd350c2-7e96-507f-8002-3f2e150b4e1b"
+version = "10.0.1+0"
+
+[[deps.OpenSSL]]
+deps = ["BitFlags", "Dates", "MozillaCACerts_jll", "OpenSSL_jll", "Sockets"]
+git-tree-sha1 = "38cb508d080d21dc1128f7fb04f20387ed4c0af4"
+uuid = "4d8831e6-92b7-49fb-bdf8-b643e874388c"
+version = "1.4.3"
+
 [[deps.OpenSSL_jll]]
 deps = ["Artifacts", "JLLWrappers", "Libdl"]
-git-tree-sha1 = "7493f61f55a6cce7325f197443aa80d32554ba10"
+git-tree-sha1 = "9216a80ff3682833ac4b733caa8c00390620ba5d"
 uuid = "458c3c95-2e84-50aa-8efc-19380b2a3a95"
-version = "3.0.15+1"
+version = "3.5.0+0"

 [[deps.PCRE2_jll]]
 deps = ["Artifacts", "Libdl"]
@@ -184,9 +256,9 @@ version = "10.42.0+1"

 [[deps.Parsers]]
 deps = ["Dates", "PrecompileTools", "UUIDs"]
-git-tree-sha1 = "8489905bcdbcfac64d1daa51ca07c0d8f0283821"
+git-tree-sha1 = "7d2f8f21da5db6a806faf7b9b292296da42b2810"
 uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
-version = "2.8.1"
+version = "2.8.3"

 [[deps.Pkg]]
 deps = ["Artifacts", "Dates", "Downloads", "FileWatching", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "Random", "SHA", "TOML", "Tar", "UUIDs", "p7zip_jll"]
@@ -234,14 +306,31 @@ version = "0.1.0"
 uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"
 version = "0.7.0"

+[[deps.Scratch]]
+deps = ["Dates"]
+git-tree-sha1 = "3bac05bc7e74a75fd9cba4295cde4045d9fe2386"
+uuid = "6c6a2e73-6563-6170-7368-637461726353"
+version = "1.2.1"
+
 [[deps.Serialization]]
 uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"
 version = "1.11.0"

+[[deps.SimpleBufferStream]]
+git-tree-sha1 = "f305871d2f381d21527c770d4788c06c097c9bc1"
+uuid = "777ac1f9-54b0-4bf8-805c-2214025038e7"
+version = "1.2.0"
+
 [[deps.Sockets]]
 uuid = "6462fe0b-24de-5631-8697-dd941f90decc"
 version = "1.11.0"

+[[deps.StructTypes]]
+deps = ["Dates", "UUIDs"]
+git-tree-sha1 = "159331b30e94d7b11379037feeb9b690950cace8"
+uuid = "856f2bd8-1eba-4b0a-8007-ebc267875bd4"
+version = "1.11.0"
+
 [[deps.StyledStrings]]
 uuid = "f489334b-da3d-4c2e-b8f0-e476e12c162b"
 version = "1.11.0"
@@ -266,6 +355,11 @@ git-tree-sha1 = "0c45878dcfdcfa8480052b6ab162cdd138781742"
 uuid = "3bb67fe8-82b1-5028-8e26-92a6c54297fa"
 version = "0.11.3"

+[[deps.URIs]]
+git-tree-sha1 = "cbbebadbcc76c5ca1cc4b4f3b0614b3e603b5000"
+uuid = "5c2747f8-b7ea-4ff2-ba2e-563bfd36b1d4"
+version = "1.5.2"
+
 [[deps.UUIDs]]
 deps = ["Random", "SHA"]
 uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"
```

ja: 翻訳結果が事前に用意されていれば　`julia` と同階層に `translation` を配置します．
もし，用意できない場合は OpenAI API キーを用意し環境変数 `OPENAI_API_KEY` を設定しておきます．
en: If you have pre-prepared translation results, place the `translation` directory at the same level as `julia`.
If you don't have them ready, prepare an OpenAI API key and set it as the environment variable `OPENAI_API_KEY`.

### Build translated Julia documentation

Just run the following command:

```sh
$ JULIA_NUM_THREADS=auto make -C julia/doc
```

Here, we used `JULIA_NUM_THREADS=auto` to improve the translation speed.
The built documentation is stored in `julia/doc/_build/html/<lang>`, where `lang` corresponds to the argument value passed to the `@switchlang!` macro.

