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
# Markdown's printer indents every list continuation by four spaces, but its
# parser reads an ordered item's content at the marker width ("1. " is three),
# so fenced code inside ordered items does not survive a round trip.
struct SourceList
    list::Markdown.List
end
function Markdown.plain(io::IO, wrapper::SourceList)
    list = wrapper.list
    for (i, item) in enumerate(list.items)
        marker = Markdown.isordered(list) ? "$(i + list.ordered - 1). " : "  * "
        print(io, marker)
        lines = split(rstrip(sprint(Markdown.plain, item)), "\n")
        for (n, line) in enumerate(lines)
            print(io, (n == 1 || isempty(line)) ? "" : " "^length(marker), line)
            n < length(lines) && println(io)
        end
        println(io)
    end
end
function source_block(node::Markdown.List)
    result = deepcopy(node)
    result.items = [Any[source_block(c) for c in item] for item in node.items]
    return SourceList(result)
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

# Single-dollar math at the start of a line is parsed as a block by Julia.
# Double-backtick math remains inline after natural-language reordering.
source_inline(node) = node
source_inline(node::Markdown.LaTeX) =
    "``" * node.formula * "``"
function source_inline(node::Union{Markdown.Bold,Markdown.Italic,Markdown.Link})
    result = deepcopy(node)
    result.text = Any[source_inline(c) for c in node.text]
    return result
end
source_block(node::Markdown.Paragraph) =
    Markdown.Paragraph(Any[source_inline(c) for c in node.content])
function source_block(node::Markdown.Table)
    result = deepcopy(node)
    for row in result.rows, i in eachindex(row)
        cell = row[i]
        row[i] = Any[source_inline(c) for c in (cell isa AbstractVector ? cell : Any[cell])]
    end
    return result
end
