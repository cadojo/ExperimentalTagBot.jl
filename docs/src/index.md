# 🏷️ 🤖 `ExperimentalTagBot.jl`

*A partial [TagBot](https://GitHub.com/JuliaRegistries/TagBot) implementation in Julia!*

## Overview

Julia's [TagBot](https://GitHub.com/JuliaRegistries/TagBot) has been automatically generating GitHub releases across the package ecosystem for several years.
It uses [`jinja`](https://jinja.palletsprojects.com/en/stable/) for release notes, and this (along with GPG signature support, need for mocking libraries, etc.) [motivated](https://github.com/JuliaRegistries/TagBot/issues/55#issuecomment-583796550) its development in Python.
The Julia ecosystem has grown considerably since this initial Python development effort occurred.
This project explores Julia as an option for [rewriting](https://github.com/JuliaRegistries/TagBot/issues/55) TagBot.

## Installation

*Choose one of the following lines below.*

::: callout-caution
This package is not yet registered, and is not affiliated with the [JuliaRegistries](https://GitHub.com/JuliaRegistries) GitHub organization.
:::

``` julia
julia> import Pkg; Pkg.add("https://github.com/cadojo/ExperimentalTagBot.jl")
```

``` julia
pkg> add https://github.com/cadojo/ExperimentalTagBot.jl
```

## Usage

*A minimum working example.*

This package can use the GitHub API to query Julia's [General Registry](https://github.com/JuliaRegistries/General) for a package version's PR, and then create a corresponding GitHub release.
To do this, you'll need to authenticate with the GitHub API. The simplest way is to install the [GitHub CLI](https://cli.github.com) and authenticate with the following command: `gh auth login`.
The GitHub CLI prompts will guide you through the one-time authentication process.
Once you've authenticated the CLI, you can execute the code below to authenticate with the API.

``` julia
import GitHub 
auth = GitHub.authenticate(readchomp(`gh auth token`))
```

With this authentication, you can use `ExperimentalTagBot` to query Git commits for each registered package version, find registered versions without tags, and create tags for all un-tagged registered package versions.

``` julia
import ExperimentalTagBot

# some (registered) package you own
# package = "ExperimentalTagBot"

# create releases for all untagged (registered) versions
ExperimentalTagBot.create_releases(package; auth = auth)
```