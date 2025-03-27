module DocstringTranslation

using Base.Docs: DocStr, Binding
using REPL: find_readme
import REPL
using Markdown: Markdown
using OpenAI: create_chat
using JSON3: JSON3

const DEFAULT_MODEL = Ref{String}("gpt-4o-mini-2024-07-18")
const DEFAULT_LANG = Ref{String}("English")

function default_model()
    return DEFAULT_MODEL[]
end

function default_lang()
    return DEFAULT_LANG[]
end

function default_system_promptfn(lang=default_lang())
    return """
Translate the Markdown content I'll paste later into $(lang).

Please note:
- Do not alter the Julia markdown formatting.
- Do not change code fence such as jldoctest or math.
- Do not change words in the form of `[xxx](@ref)`.
- Do not change any URL.
- If $(lang) indicates English (e.g., "en"), return the input unchanged.

Return only the resulting text.
"""
end

export @switchlang!, @revertlang!

function postprocess_content(content::AbstractString)
    # Replace each match with the text wrapped in a math code block
    return replace(
        content, 
        r":\$(.*?):\$"s => s"```math\n\1\n```",
        r"\$\$(.*?)\$\$"s => s"```math\n\1\n```"
        )
end

function translate_with_openai(
    doc::Union{Markdown.MD, AbstractString};
    lang::String = default_lang(),
    model::String = default_model(),
    system_promptfn = default_system_promptfn,
)
    c = create_chat(
        ENV["OPENAI_API_KEY"],
        model,
        [
            Dict("role" => "system", "content" => system_promptfn(lang)),
            Dict("role" => "user", "content" => string(doc)),
        ];
        temperature=0,
    )
    content = c.response[:choices][begin][:message][:content]
    content = postprocess_content(content)
    return Markdown.parse(content)
end

function translate_with_openai_streaming(
    doc::Union{Markdown.MD, AbstractString};
    lang::String = default_lang(),
    model::String = default_model(),
    system_promptfn = default_system_promptfn,
)
    channel = Channel()
    task = @async create_chat(
        ENV["OPENAI_API_KEY"],
        model,
        [
            Dict("role" => "system", "content" => system_promptfn(lang)),
            Dict("role" => "user", "content" => string(doc)),
        ];
        streamcallback = (x -> put!(channel, x)),
        temperature=0,
    )
    channel, task
end

function translate_with_openai(md::Markdown.MD, lang)
    translated = Markdown.parse(translate_with_openai(string(md), lang))
    md.content = translated.content
    md
end

function switchlang!(lang::Union{String,Symbol})
    DEFAULT_LANG[] = String(lang)
end

function switchlang!(node::QuoteNode)
    lang = node.value
    switchlang!(lang)
end

"""
	@switchlang!(lang)

Modify Docs.parsedoc(d::DocStr) to insert translation engine.
"""
macro switchlang!(lang)
    switchlang!(lang)
    @eval function Docs.parsedoc(d::DocStr)
        if d.object === nothing
            md = Docs.formatdoc(d)
            md.meta[:module] = d.data[:module]
            md.meta[:path] = d.data[:path]
            d.object = md
        end
        translate_with_openai(d.object)
    end

    @eval function REPL.summarize(io::IO, m::Module, binding::Binding; nlines::Int = 200)
        readme_path = find_readme(m)
        public = Base.ispublic(binding.mod, binding.var) ? "public" : "internal"
        if isnothing(readme_path)
            println(io, "No docstring or readme file found for $public module `$m`.\n")
        else
            println(io, "No docstring found for $public module `$m`.")
        end
        exports = filter!(!=(nameof(m)), names(m))
        if isempty(exports)
            println(io, "Module does not have any public names.")
        else
            println(io, "# Public names")
            print(io, "  `")
            join(io, exports, "`, `")
            println(io, "`\n")
        end
        if !isnothing(readme_path)
            readme_lines = readlines(readme_path)
            isempty(readme_lines) && return  # don't say we are going to print empty file
            println(io, "# Displaying contents of readme found at `$(readme_path)`")
            @info "Translating..."
            channel, _ =
                translate_with_openai_streaming(join(readme_lines, '\n'))
            for c in channel
                try
                    j = JSON3.read(c[length("data: "):end])
                    choice = j["choices"][begin]
                    if isnothing(choice["finish_reason"])
                        print(stdout, choice["delta"]["content"])
                        print(io, choice["delta"]["content"])
                    else
                        @info "Done!"
                        break
                    end
                catch e
                    # sometimes parsing string as json fails...
                    if e isa ArgumentError
                        continue
                    else
                        rethrow()
                    end
                end
            end
            close(channel)
        end
    end
end

function revertlang!()
    DEFAULT_LANG[] = "English"
end

"""
	@revertlang!

re-evaluate original implementation for 
Docs.parsedoc(d::DocStr)
"""
macro revertlang!()
    revertlang!("English")
    @eval function Docs.parsedoc(d::DocStr)
        if d.object === nothing
            md = Docs.formatdoc(d)
            md.meta[:module] = d.data[:module]
            md.meta[:path] = d.data[:path]
            d.object = md
        end
        d.object
    end

    @eval function REPL.summarize(io::IO, m::Module, binding::Binding; nlines::Int = 200)
        readme_path = find_readme(m)
        public = Base.ispublic(binding.mod, binding.var) ? "public" : "internal"
        if isnothing(readme_path)
            println(io, "No docstring or readme file found for $public module `$m`.\n")
        else
            println(io, "No docstring found for $public module `$m`.")
        end
        exports = filter!(!=(nameof(m)), names(m))
        if isempty(exports)
            println(io, "Module does not have any public names.")
        else
            println(io, "# Public names")
            print(io, "  `")
            join(io, exports, "`, `")
            println(io, "`\n")
        end
        if !isnothing(readme_path)
            readme_lines = readlines(readme_path)
            isempty(readme_lines) && return  # don't say we are going to print empty file
            println(io, "# Displaying contents of readme found at `$(readme_path)`")
            for line in first(readme_lines, nlines)
                println(io, line)
            end
            length(readme_lines) > nlines &&
                println(io, "\n[output truncated to first $nlines lines]")
        end
    end
end

end # module DocstringTranslation
