function hashmd(md::Markdown.MD)::String
    return bytes2hex(sha256(string(md)))
end

function postprocess_content(content::AbstractString)
    # Replace each match with the text wrapped in a math code block
    return replace(content, r"\$\$(.*?)\$\$"s => s"```math\1```")
end
