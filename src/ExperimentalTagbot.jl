module ExperimentalTagBot

import Pkg
using Git: git
import GitHub
import Markdown
import IOCapture

export
    registered, versions, url, project, untagged, parent, message, release, update

"""
Given a package name, return map from all versions released in the general 
registry to the Git SHA1 hashes in the project location.

# Extended Help

This code was originally written by user @yakir12 on Julia's Discourse in 
the following post: https://discourse.julialang.org/t/pkg-version-list/1257/10.
"""
function registered(package::AbstractString)
    registry = only(filter(r -> r.name == "General", Pkg.Registry.reachable_registries()))

    local pkg

    try
        pkg = only(filter(pkg -> pkg.name == package, collect(values(registry.pkgs))))
    catch e
        if e isa ArgumentError
            throw(ErrorException("$package is not registered in the General package registry"))
        else
            rethrow(e)
        end
    end

    vs = [pair.first => pair.second.git_tree_sha1 for pair in Pkg.Registry.registry_info(pkg).version_info]
    sort!(vs, by=x -> x.first)
    return Dict(["v" * string(pair.first) => pair.second for pair in vs])
end

"""
Given a package name, return all versions released in the general registry.
"""
function versions(package::AbstractString)
    vs = collect(keys(registered(package)))
    sort!(vs, by=VersionNumber)
    return vs
end

"""
Given a registry name, return the repository.
"""
function registry_url(registry)
    reg = only(filter(r -> r.name == registry, Pkg.Registry.reachable_registries()))
    return reg.repo
end

"""
Given a package name, return the project repository registered in the General 
registry.
"""
function url(package::AbstractString; registry="General")
    reg = only(filter(r -> r.name == registry, Pkg.Registry.reachable_registries()))
    pkg = only(filter(pkg -> pkg.name == package, collect(values(reg.pkgs))))
    return Pkg.Registry.registry_info(pkg).repo
end

repo(url) = replace(url, "http://" => "",
    "https://" => "",
    "www." => "",
    "github.com/" => "",
    ".git" => ""
)

"""
Given a package name, return `<owner>/<project>`.
"""
function project(package::AbstractString)
    return repo(url(package))
end

"""
Given a package name, return all registered versions which are not yet released.
"""
function untagged(package::AbstractString; kwargs...)
    registered = versions(package)
    tags, metadata = GitHub.tags(project(package); kwargs...)
    tags = String[tag.tag for tag in tags if !isnothing(tag.tag)]

    for tag in tags
        version = replace(tag, (package * "-") => "")
        deleteat!(registered, findall(v -> v == version, registered))
    end

    tags = registered
    sort!(tags, by=VersionNumber)

    return tags
end

function parent(version, versions)
    v = VersionNumber(version)
    vs = map(VersionNumber, collect(versions))

    filter!(n -> n < v, vs)

    v = maximum(vs)
    return "v" * string(v)
end

function release_prs(package, version; registry="General", kwargs...)
    v = "v" * string(VersionNumber(version))
    # TODO add registry specification
    results = GitHub.gh_get_json(GitHub.DEFAULT_API, "/search/issues"; kwargs..., params="q=$package%20$v%20in%3Atitle%20is%3Apr%20repo%3A$(repo(registry_url(registry)))", kwargs...)
    return [GitHub.PullRequest(result) for result in results["items"]]
end


function commit(package::AbstractString, version; registry="General", kwargs...)
    prs = [
        GitHub.pull_request(repo(registry_url(registry)), pr.number; kwargs...)
        for pr in release_prs(package, version; registry=registry, kwargs...)
    ]

    filter!(pr -> pr.merged, prs) # remove PRs which did not merge
    sort!(prs; by=pr -> pr.closed_at) # sort PRs by merge timestamp

    pr = last(prs) # take the most recent merged PR

    lines = readlines(IOBuffer(pr.body))
    for line in lines
        if startswith(line, "- Commit: ")
            prefix, hash = rsplit(line, ":"; limit=2)
            return strip(hash)
        end
    end
    error("commit not found for $package $version")
end

function message(package::AbstractString, version; kwargs...)
    version = string(VersionNumber(version))
    base = parent(version, versions(package))
    head = commit(package, version)
    diff = GitHub.compare(project(package), "$(prefix)$(base)", "$(prefix)$(head)"; kwargs...)

    messages = [
        replace(commit.commit.message, "\n\n" => "\n")
        for commit in diff.commits
    ]

    return Markdown.MD([
        Markdown.Link("diff since $parent", "$(url(package))/compare/$(prefix)$(base)...$(prefix)$(head)"),
        Markdown.Header{2}("Changelog"),
        Markdown.List(messages)
    ])
end

function release(package::AbstractString, version; prefix=nothing, kwargs...)
    prefix = isnothing(prefix) ? package * "-" : prefix

    repo = project(package)
    version = string(VersionNumber(version))
    hash = commit(package, version)

    tag = "$(prefix)v$(version)"

    default = Dict(
        "tag_name" => tag,
        "target_commitish" => hash,
        "name" => "Release v$version for $package.jl",
        "body" => string(message(package, version; kwargs...)),
        "draft" => false,
        "prerelease" => false,
        "generate_release_notes" => false
    )

    options = merge(
        (; params=default),
        kwargs
    )

    @info """creating release with the following options:
    $(collect(options))
    """

    GitHub.create_release(repo; options...)

end


function update(package::AbstractString; registry="General", prefix=nothing, kwargs...)
    unreleased = untagged(package; kwargs...)

    for version in unreleased
        release(package, version; registry=registry, prefix=prefix, kwargs...)
    end
end

end # module ExperimentalTagbot
