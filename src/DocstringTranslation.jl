module DocstringTranslation

using Base.Docs: DocStr

using SHA
using Markdown

using Scratch
import Documenter

using OpenAI

const DEFAULT_LANG = Ref{String}()
const TRANSLATION_CACHE_DIR = Ref{String}()
const DOCUMENTER_TARGET_PACKAGE = Ref{Dict{Symbol, Any}}()

function switchtranslationcachedir!(dir::AbstractString)
    TRANSLATION_CACHE_DIR[] = dir
end

function switchtargetpackage!(pkg::Module)
    DOCUMENTER_TARGET_PACKAGE[] = Dict(:name=>string(pkg), :version=>pkgversion(pkg))
end

include("util.jl")
include("scratchspace.jl")
include("openai.jl")

include("switchlang.jl")
export @switchlang!

function __init__()
    scratch_name = "translation"
    DOCUMENTER_TARGET_PACKAGE[] = Dict(:name=>"julia", :version=>VERSION)
    global TRANSLATION_CACHE_DIR[] = @get_scratch!(scratch_name)
end

end # module DocstringTranslation
