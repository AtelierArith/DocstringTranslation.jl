function hashmd(md::Markdown.MD)::String
    return bytes2hex(
        sha256(
            (
                get(md.meta, :documenter_page_translation, false) ? "documenter-page-v5:" :
                get(md.meta, :docstring_translation, false) ? "docstring-v1:" : ""
            ) * string(md),
        ),
    )
end

function postprocess_content(content::AbstractString)
    # Replace each match with the text wrapped in a math code block
    return replace(content, r"\$\$(.*?)\$\$"s => s"```math\1```")
end

# Markdown's default printer emits display math as $$...$$, which Julia's
# Markdown parser does not read back as LaTeX. Use math fences at block positions.
source_block(node) = node
source_block(node::Markdown.LaTeX) = Markdown.Code("math", node.formula)
source_block(md::Markdown.MD) =
    Markdown.MD(Any[source_block(c) for c in md.content], copy(md.meta))
function source_block(node::Markdown.List)
    result = deepcopy(node)
    result.items = [Any[source_block(c) for c in item] for item in node.items]
    return result
end
function source_block(node::Union{Markdown.BlockQuote,Markdown.Admonition})
    result = deepcopy(node)
    result.content = Any[source_block(c) for c in node.content]
    return result
end
function source_block(node::Markdown.Footnote)
    result = deepcopy(node)
    if node.text !== nothing
        result.text = Any[source_block(c) for c in node.text]
    end
    return result
end
markdown_source(md::Markdown.MD) = string(source_block(md))
markdown_source(text::AbstractString) = String(text)
