using Documenter
using Quarto

Quarto.render(joinpath(@__DIR__, "src"))

Documenter.deploydocs(repo = "github.com/cadojo/ExperimentalTagBot.jl")
