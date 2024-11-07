module DocstringTranslation

using Base.Docs: DocStr
using Markdown: Markdown
using OpenAI: create_chat

export @switchlang!, @revertlang!

function translate_with_openai(inp, lang)
    model = "gpt-4o-mini"
    prompt = """
  Translate the following markdown in $(lang)

  $(inp)

  Just return result.

  Note that if $(lang) represents English such as en or english, do not translate and modify anything
  Remember Just return result.
  """

    r = create_chat(
        ENV["OPENAI_API_KEY"],
        model,
        [Dict("role" => "user", "content" => string(prompt))],
    )
    r.response[:choices][begin][:message][:content]
end

function translate_with_ai(md::Markdown.MD, lang)
    buff = IOBuffer()
    show(buff, md)
    str = String(take!(buff))
    translated = Markdown.parse(translate_with_openai(str, lang))
    md.content = translated.content
    md
end

"""
	@switchlang!(lang)

re-evaluate original implementation for 
Docs.parsedoc(d::DocStr)
"""
macro switchlang!(lang)
    @eval function Docs.parsedoc(d::DocStr)
        if d.object === nothing
            md = Docs.formatdoc(d)
            md.meta[:module] = d.data[:module]
            md.meta[:path] = d.data[:path]
            d.object = md
        end
        translate_with_ai(d.object, string($(lang)))
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
end

end # module DocstringTranslation
