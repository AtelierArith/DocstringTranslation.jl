# Whole-page translation works on a Markdown syntax tree. Opaque nodes and link
# destinations are replaced by unique markers before the text leaves Julia.
mutable struct PageProtection
    prefix::String
    originals::Vector{String}
    markers::Vector{String}
end

function protect!(state::PageProtection, original::AbstractString, kind::String)
    push!(state.originals, String(original))
    marker = state.prefix * kind * string(length(state.originals)) * "END"
    push!(state.markers, marker)
    return marker
end

markdown_block(node) = chomp(markdown_source(Markdown.MD(node)))
markdown_inline(node) = chomp(string(Markdown.MD(Markdown.Paragraph(Any[node]))))

function protect_block(node, state)
    if node isa Union{Markdown.Header,Markdown.Code,Markdown.LaTeX,Markdown.HorizontalRule}
        return Markdown.Paragraph(Any[protect!(state, markdown_block(node), "BLOCK")])
    end
    return protect_node(node, state)
end

function protect_inline(node, state)
    if node isa Union{Markdown.Code,Markdown.LaTeX}
        return protect!(state, markdown_inline(node), "CODE")
    end
    return protect_node(node, state)
end

function protect_node(node::AbstractString, state)
    return replace(node, r"https?://[^\s<>\"]+" => url -> protect!(state, url, "URL"))
end
function protect_node(node::Markdown.Paragraph, state)
    node.content = Any[protect_inline(c, state) for c in node.content]
    return node
end
function protect_node(node::Markdown.Link, state)
    return protect!(state, markdown_inline(node), "LINK")
end
function protect_node(node::Markdown.Image, state)
    node.url = protect!(state, node.url, "URL")
    return node
end
function protect_node(node::Union{Markdown.Bold,Markdown.Italic}, state)
    node.text = Any[protect_inline(c, state) for c in node.text]
    return node
end
function protect_node(node::Markdown.List, state)
    node.items = [Any[protect_block(c, state) for c in item] for item in node.items]
    return node
end
function protect_node(node::Union{Markdown.BlockQuote,Markdown.Admonition}, state)
    node.content = Any[protect_block(c, state) for c in node.content]
    return node
end
function protect_node(node::Markdown.Footnote, state)
    node.id = protect!(state, node.id, "FOOTNOTE")
    if !isnothing(node.text)
        node.text = Any[protect_block(c, state) for c in node.text]
    end
    return node
end
function protect_node(node::Markdown.Table, state)
    for row in node.rows, i in eachindex(row)
        cell = row[i]
        content = cell isa AbstractVector ? cell : Any[cell]
        row[i] = Any[protect_inline(c, state) for c in content]
    end
    return node
end
function protect_node(node, state)
    throw(
        ArgumentError(
            "Unsupported Markdown element $(typeof(node)); cannot translate this page safely",
        ),
    )
end

# Compare structure and marker locations while ignoring translated prose.
function page_structure(value::AbstractString, prefix::String)
    markers = Tuple(m.match for m in eachmatch(Regex(prefix * raw"[A-Z]+\d+END"), value))
    return isempty(markers) ? nothing : markers
end
function page_structure(value::AbstractVector, prefix::String)
    return Tuple(filter(!isnothing, [page_structure(item, prefix) for item in value]))
end
function inline_structure(content, prefix::String)
    pieces = Any[]
    for node in content
        if node isa AbstractString
            append!(
                pieces,
                (
                    (:marker, m.match) for
                    m in eachmatch(Regex(prefix * raw"[A-Z]+\d+END"), node)
                ),
            )
        elseif node isa Markdown.Link
            push!(pieces, (:link, page_structure(node.url, prefix)))
            append!(pieces, inline_structure(node.text, prefix))
        elseif node isa Union{Markdown.Bold,Markdown.Italic}
            push!(pieces, (typeof(node), inline_structure(node.text, prefix)))
        else
            push!(pieces, page_structure(node, prefix))
        end
    end
    return Tuple(sort!(pieces; by = repr))
end
page_structure(node::Markdown.Paragraph, prefix::String) =
    (:paragraph, inline_structure(node.content, prefix))
function page_structure(node::Markdown.Table, prefix::String)
    rows = Tuple(
        Tuple(
            inline_structure(cell isa AbstractVector ? cell : Any[cell], prefix) for
            cell in row
        ) for row in node.rows
    )
    return (:table, Tuple(node.align), rows)
end
page_structure(md::Markdown.MD, prefix::String) = page_structure(md.content, prefix)
function page_structure(value, prefix::String)
    if parentmodule(typeof(value)) === Markdown && isstructtype(typeof(value))
        return (
            typeof(value),
            Tuple(
                page_structure(getfield(value, name), prefix) for
                name in fieldnames(typeof(value))
            ),
        )
    end
    return value
end

# Canonical markers let us compare protected values after restoration, even if
# the translated prose changed the order of inline elements within a cell.
function restored_structure(source::AbstractString, prefix::String)
    md = Markdown.parse(source)
    state = PageProtection(prefix, String[], String[])
    md.content = Any[protect_block(node, state) for node in md.content]
    canonical = string(md)
    for (marker, original) in zip(state.markers, state.originals)
        kind = match(r"[A-Z]+(?=\d+END$)", marker).match
        digest = sha256(kind * original)
        digits = join(lpad(string(byte), 3, '0') for byte in digest)
        canonical = replace(canonical, marker => prefix * "VALUE" * digits * "END")
    end
    return page_structure(Markdown.parse(canonical), prefix)
end

"""Translate a complete Documenter page using `translator` and restore protected syntax."""
function translate_documenter_page(source::AbstractString; translator)
    md = Markdown.parse(source)
    prefix = "DTPROTECTED" * uppercase(bytes2hex(sha256(source))[1:16]) * "X"
    occursin(prefix, source) &&
        throw(ArgumentError("Page contains a reserved translation marker"))
    state = PageProtection(prefix, String[], String[])
    md.content = Any[protect_block(node, state) for node in md.content]
    protected = string(md)
    translated = translator(protected)
    translated isa AbstractString ||
        throw(ArgumentError("Page translator must return text"))
    isempty(strip(translated)) && throw(ArgumentError("Page translation is empty"))
    for marker in state.markers
        length(collect(eachmatch(Regex(marker), translated))) == 1 || throw(
            ArgumentError("Page translation lost or duplicated protected marker $marker"),
        )
    end
    # Block markers must occupy a line by themselves, apart from container prefixes.
    for marker in state.markers
        occursin("BLOCK", marker) || continue
        line = Regex(
            "(?m)^[ \t]*(?:(?:>[ \t]*)|(?:(?:[-+*]|\\d+[.)])[ \t]+))*" *
            marker *
            "[ \t]*\$",
        )
        occursin(line, translated) || throw(
            ArgumentError("Protected block marker $marker was joined to other content"),
        )
    end
    # Reject invented markers as well as altered marker fragments.
    markers = collect(eachmatch(Regex(prefix * raw"[A-Z]+\d+END"), translated))
    length(markers) == length(state.originals) ||
        throw(ArgumentError("Page translation contains invalid protected markers"))
    page_structure(Markdown.parse(protected), prefix) ==
    page_structure(Markdown.parse(translated), prefix) || throw(
        ArgumentError("Page translation changed Markdown structure or marker placement"),
    )
    result = String(translated)
    for (marker, original) in zip(state.markers, state.originals)
        if occursin("BLOCK", marker) && occursin('\n', original)
            location = findfirst(marker, result)
            start = first(location)
            prior =
                start == firstindex(result) ? nothing :
                findprev('\n', result, prevind(result, start))
            line_start = isnothing(prior) ? firstindex(result) : nextind(result, prior)
            leading = start == line_start ? "" : result[line_start:prevind(result, start)]
            continuation = replace(
                leading,
                r"(?<!\S)(?:[-+*]|\d+[.)])(?=\s)" =>
                    bullet -> repeat(" ", length(bullet)),
            )
            original = replace(original, "\n" => "\n" * continuation)
        end
        result = replace(result, marker => original)
    end
    restored_structure(source, prefix) == restored_structure(result, prefix) || throw(
        ArgumentError("Restored page does not preserve the original Markdown structure"),
    )
    return result
end
