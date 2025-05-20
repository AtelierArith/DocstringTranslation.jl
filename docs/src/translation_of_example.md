# How to translate documentation of Example.jl

Apply the following patch to `docs/make.jl` in Example.jl

```diff
diff --git a/docs/make.jl b/docs/make.jl
index 450ae47..9feba34 100644
--- a/docs/make.jl
+++ b/docs/make.jl
@@ -1,5 +1,9 @@
 using Documenter, Example

+using DocstringTranslation
+@switchlang! :ja
+DocstringTranslation.switchtargetpackage!(Example)
+
 makedocs(modules = [Example],
          sitename = "Example.jl",
          format = Documenter.HTML()
```
