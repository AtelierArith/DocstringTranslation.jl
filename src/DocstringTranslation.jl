module DocstringTranslation

using Base.Docs: DocStr, Binding
using REPL: find_readme
import REPL
using Markdown: Markdown
using OpenAI: create_chat
using JSON3: JSON3

export @switchlang!, @revertlang!

function translate_with_openai(inp, lang; streamcallback=nothing)
    model = "gpt-4o-mini"
    prompt = """
  Translate the following markdown in $(lang)

  $(inp)

  Just return result.

  Note that if $(lang) represents English such as en or english, do not translate and modify anything
  Remember Just return result.
  """
    c = create_chat(
            ENV["OPENAI_API_KEY"],
            model,
            [Dict("role" => "user", "content" => string(prompt))];
            streamcallback,
    )
    if isnothing(streamcallback)
        return c.response[:choices][begin][:message][:content]
    else
        map(r->r["choices"][1]["delta"], c.response)
    end
end

function translate_with_openai(md::Markdown.MD, lang)
    buff = IOBuffer()
    show(buff, md)
    str = String(take!(buff))
    translated = Markdown.parse(translate_with_openai(str, lang))
    md.content = translated.content
    md
end

"""
	@switchlang!(lang)

Modify Docs.parsedoc(d::DocStr) to insert translation engine.
"""
macro switchlang!(lang)
    @eval function Docs.parsedoc(d::DocStr)
        if d.object === nothing
            md = Docs.formatdoc(d)
            md.meta[:module] = d.data[:module]
            md.meta[:path] = d.data[:path]
            d.object = md
        end
        translate_with_openai(d.object, string($(lang)))
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
            translated_md = translate_with_openai(join(readme_lines, '\n'), string($(lang)))
            readme_lines = split(string(translated_md), '\n')
            for line in readme_lines # first(readme_lines, nlines)
                println(io, line)
            end
            # length(readme_lines) > nlines && println(io, "\n[output truncated to first $nlines lines]")
        end
    end
end

"""
	@revertlang!

re-evaluate original implementation for 
Docs.parsedoc(d::DocStr)
"""
macro revertlang!()

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
            length(readme_lines) > nlines && println(io, "\n[output truncated to first $nlines lines]")
        end
    end
end

end # module DocstringTranslation
