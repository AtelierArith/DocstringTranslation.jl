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
markdown_inline(node) = chomp(markdown_source(Markdown.MD(Markdown.Paragraph(Any[node]))))

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
    # Translated CJK text follows a URL without a space, so a URL also ends at
    # the first non-ASCII character. A backtick left in text (e.g. swallowed by
    # mis-parsed emphasis) is protected and restored escaped, so a translation
    # cannot pair it into a new code span.
    return replace(
        node,
        r"https?://[^\s<>\"`[:^ascii:]]+|`" =>
            m -> m == "`" ? protect!(state, "\\`", "TICK") : protect!(state, m, "URL"),
    )
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
        first_marker = length(state.originals) + 1
        row[i] = Any[protect_inline(c, state) for c in content]
        # Inline serialization occurs outside the table; restore the table's
        # escape layer so bitwise | operators do not become cell separators.
        for j = first_marker:length(state.originals)
            state.originals[j] = replace(state.originals[j], "|" => "\\|")
        end
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
    pieces = Any[]
    prose = Any[]
    in_prose = false
    for item in value
        signature = page_structure(item, prefix)
        if item isa Markdown.Paragraph && first(signature) == :prose
            append!(prose, signature[2])
            in_prose = true
        else
            if in_prose
                push!(pieces, (:prose, Tuple(sort!(prose; by = repr))))
                empty!(prose)
                in_prose = false
            end
            isnothing(signature) || push!(pieces, signature)
        end
    end
    in_prose && push!(pieces, (:prose, Tuple(sort!(prose; by = repr))))
    return Tuple(without_bridging_prose(pieces))
end
# Word order may fold a short fragment that sits between two blocks (e.g. "in
# any shell." after a code block) into the preceding sentence. Such prose has
# no markers, so dropping it cannot move protected content; prose at the start
# or end still anchors where blocks appear.
isprose(piece) = piece isa Tuple && !isempty(piece) && first(piece) == :prose
function without_bridging_prose(pieces)
    keep = trues(length(pieces))
    for i = 2:(length(pieces)-1)
        pieces[i] == (:prose, ()) || continue
        !isprose(pieces[i-1]) && !isprose(pieces[i+1]) && (keep[i] = false)
    end
    return pieces[keep]
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
            # Emphasis can move or disappear when a sentence is rephrased.
            append!(pieces, inline_structure(node.text, prefix))
        else
            push!(pieces, page_structure(node, prefix))
        end
    end
    return Tuple(sort!(pieces; by = repr))
end
function page_structure(node::Markdown.Paragraph, prefix::String)
    signature = inline_structure(node.content, prefix)
    blocks = filter(signature) do piece
        piece isa Tuple &&
            length(piece) == 2 &&
            piece[1] == :marker &&
            startswith(piece[2], prefix * "BLOCK")
    end
    return isempty(blocks) ? (:prose, signature) : (:protected_block, signature)
end
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
    canonical = markdown_source(md)
    for (marker, original) in zip(state.markers, state.originals)
        kind = something(
            match(r"^([A-Z]+)\d+END$", marker[(length(prefix)+1):end]).captures[1],
        )
        digest = sha256(kind * original)
        digits = join(lpad(string(byte), 3, '0') for byte in digest)
        canonical = replace(canonical, marker => prefix * kind * "VALUE" * digits * "END")
    end
    return page_structure(Markdown.parse(canonical), prefix)
end

"""Translate a complete Documenter page using `translator` and restore protected syntax."""
function structure_difference(expected, actual, path = "document")
    expected == actual && return nothing
    if expected isa Tuple && actual isa Tuple
        for i = 1:min(length(expected), length(actual))
            difference = structure_difference(expected[i], actual[i], "$path[$i]")
            isnothing(difference) || return difference
        end
        return "$path: expected $(length(expected)) entries, got $(length(actual))"
    end
    # Signatures contain structure and opaque markers, never the original prose.
    return "$path: expected $(repr(expected)), got $(repr(actual))"
end

function check_structure(expected, actual, source_label, stage)
    difference = structure_difference(expected, actual)
    isnothing(difference) || throw(
        ArgumentError(
            "Translation validation failed for $source_label ($stage): $difference",
        ),
    )
end

function translate_documenter_page(
    source::AbstractString;
    translator,
    source_label::AbstractString = "Markdown input",
)
    md = Markdown.parse(source)
    prefix = "DTPROTECTED" * uppercase(bytes2hex(sha256(source))[1:16]) * "X"
    occursin(prefix, source) &&
        throw(ArgumentError("Page contains a reserved translation marker"))
    state = PageProtection(prefix, String[], String[])
    md.content = Any[protect_block(node, state) for node in md.content]
    protected = markdown_source(md)
    translated = translator(protected)
    translated isa AbstractString ||
        throw(ArgumentError("Page translator must return text"))
    isempty(strip(translated)) && throw(ArgumentError("Page translation is empty"))
    for marker in state.markers
        length(collect(eachmatch(Regex(marker), translated))) == 1 || throw(
            ArgumentError(
                "$source_label: protected marker $marker must occur exactly once; got $(length(collect(eachmatch(Regex(marker), translated))))",
            ),
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
            ArgumentError(
                "$source_label: protected block $marker must occupy its own line",
            ),
        )
    end
    # Reject invented markers as well as altered marker fragments.
    markers = collect(eachmatch(Regex(prefix * raw"[A-Z]+\d+END"), translated))
    length(markers) == length(state.originals) ||
        throw(ArgumentError("Page translation contains invalid protected markers"))
    check_structure(
        page_structure(Markdown.parse(protected), prefix),
        page_structure(Markdown.parse(translated), prefix),
        source_label,
        "protected response",
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
    check_structure(
        restored_structure(source, prefix),
        restored_structure(result, prefix),
        source_label,
        "restored Markdown",
    )
    return result
end
