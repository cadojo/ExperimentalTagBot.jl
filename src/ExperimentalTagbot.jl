module ExperimentalTagBot

import Pkg
using Git: git
import GitHub
import Markdown

export versions, url, project, untagged, parent, message, update

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
Given a package name, return the project repository registered in the General 
registry.
"""
function url(package::AbstractString; registry="General")
    reg = only(filter(r -> r.name == registry, Pkg.Registry.reachable_registries()))
    pkg = only(filter(pkg -> pkg.name == package, collect(values(reg.pkgs))))
    return Pkg.Registry.registry_info(pkg).repo
end

"""
Given a package name, return `<owner>/<project>`.
"""
function project(package::AbstractString)
    return replace(
        url(package),
        "http://" => "",
        "https://" => "",
        "www." => "",
        "github.com/" => "",
        ".git" => ""
    )
end

"""
Given a package name, return all registered versions which are not yet released.
"""
function untagged(package::AbstractString; kwargs...)
    registered = versions(package)
    tags, metadata = GitHub.tags(project(package); kwargs...)
    tags = [tag.tag for tag in tags if !isnothing(tag.tag)]

    for tag in tags
        delete!(registered, replace(tag, (package * "-") => ""))
    end

    tags = collect(keys(registered))
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

function message(package::AbstractString, version; kwargs...)
    base = parent(version, versions(package))
    diff = GitHub.compare(project(package), base, version; kwargs...)

    messages = [
        replace(commit.commit.message, "\n\n" => "\n")
        for commit in diff.commits
    ]

    return Markdown.MD([
        Markdown.Header{2}("Commits"),
        Markdown.List(messages)
    ])
end


function update(package::AbstractString; kwargs...)
    registered = registered(package)
    unreleased = untagged(package; kwargs...)

    for version in unreleased

    end
end

end # module ExperimentalTagbot
