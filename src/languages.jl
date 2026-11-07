# Explicit aliases only: arbitrary prompt targets retain their spelling.
const LANGUAGE_ALIASES = Dict(
    "english" => "en",
    "japanese" => "ja",
    "german" => "de",
    "french" => "fr",
    "spanish" => "es",
    "italian" => "it",
    "portuguese" => "pt",
    "chinese" => "zh",
    "korean" => "ko",
    "russian" => "ru",
    "arabic" => "ar",
    "hindi" => "hi",
)

function normalize_language(lang::Union{AbstractString,Symbol})
    text = String(lang)
    lower = lowercase(text)
    return get(LANGUAGE_ALIASES, lower, lower in values(LANGUAGE_ALIASES) ? lower : text)
end
