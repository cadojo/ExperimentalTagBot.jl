# 🏷️🤖 Automated Package Releases in Julia

_A minimum-viable [TagBot](https://github.com/JuliaRegistries/TagBot) implementation in Julia!_

**This project is being actively developed!** It works in local testing, and will be made more robust in 2025.

## Installation

_Choose one of the following lines below._

```julia
julia> import Pkg; Pkg.add("https://github.com/cadojo/TagBot.jl")
```

```julia
pkg> add https://github.com/cadojo/TagBot.jl
```

## Usage

_A minimum working example._

This package can use the GitHub API to query Julia's [General Registry](https://github.com/JuliaRegistries/General) for a package version's PR, and then create a corresponding GitHub release.
To do this, you'll need to authenticate with the GitHub API. 
The simplest way is to install the [GitHub CLI](https://cli.github.com) and authenticate with the following command: `gh auth login`. 
The GitHub CLI prompts will guide you through the one-time authentication process.
Once you've authenticated the CLI, you can execute the code below to authenticate with the API.

```julia
import GitHub 
auth = GitHub.authenticate(readchomp(`gh auth token`))
```

With this authentication, you can use `TagBot` to query Git commits for each registered package version, find registered versions without tags, and create tags for all un-tagged registered package versions.

```julia
import TagBot

package = "" # some package you own
TagBot.create_releases(package; auth = auth)
```
