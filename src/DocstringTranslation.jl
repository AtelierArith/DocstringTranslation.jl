module DocstringTranslation

using Base.Docs: DocStr, Binding
using REPL: find_readme
import REPL
using Markdown: Markdown
using OpenAI: create_chat
using JSON3: JSON3

export @switchlang!, @revertlang!

function translate_with_openai(inp::String, lang)
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
    )
    return c.response[:choices][begin][:message][:content]
end

function translate_with_openai_streaming(inp::String, lang)
    model = "gpt-4o-mini"
    prompt = """
    Translate the following markdown in $(lang)

    $(inp)

    Just return result.

    Note that if $(lang) represents English such as en or english, do not translate and modify anything
    Remember Just return result.
    """

    channel = Channel()
    task = @async create_chat(
        ENV["OPENAI_API_KEY"],
        model,
        [Dict("role" => "user", "content" => string(prompt))];
        streamcallback = (x -> put!(channel, x)),
    )
    channel, task
end

function translate_with_openai(md::Markdown.MD, lang)
    translated = Markdown.parse(translate_with_openai(string(md), lang))
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
            channel, _ =
                translate_with_openai_streaming(join(readme_lines, '\n'), string($(lang)))
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
            length(readme_lines) > nlines &&
                println(io, "\n[output truncated to first $nlines lines]")
        end
    end
end

end # module DocstringTranslation
