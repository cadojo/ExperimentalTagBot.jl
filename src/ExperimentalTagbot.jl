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
        version = replace(tag, (package * "-") => "")
        deleteat!(registered, findall(v -> v == version, registered))
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

function clone(package)
    path = tempname()

    IOCapture.capture() do
        run(git(["clone", "--bare", url(package), path]))
    end

    return path
end

# git clone --no-checkout --filter=blob:none --sparse https://github.com/JuliaRegistries/General $(tempdir())
# cd General
# git sparse-checkout set G/GeneralAstrodynamics
# git checkout


function commit(package::AbstractString, version; kwargs...)
    prefix, version = rsplit(version, "v"; limit=2)

end

# https://arbitrary-but-fixed.net/git/julia/2021/03/18/git-tree-sha1-to-commit-sha1.html
function find_commit(package::AbstractString, version; kwargs...)
    prefix, version = rsplit(version, "v"; limit=2)
    tree = registered(package)["v$version"]

    path = clone(package)

    response = IOCapture.capture() do
        run(pipeline(Cmd(`git log --pretty=raw`; dir=path), `grep -B 1 $tree`))
    end

    hascommit(line) = startswith(line, "commit ")

    lines = collect(eachline(IOBuffer(response.output)))
    index = findfirst(hascommit, lines)


    if isnothing(index)
        throw(ErrorException("failed to find any commits associated with tree SHA1($tree)"))
    else
        line = lines[index]

        rm(path; force=true, recursive=true)

        return strip(replace(line, "commit " => ""))
    end

end

function message(package::AbstractString, version; kwargs...)
    prefix, version = rsplit(version, "v"; limit=2)
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

    @debug """creating release with the following options:
    $(collect(options))
    """

    GitHub.create_release(repo; options...)

end


function update(package::AbstractString; kwargs...)
    registered = registered(package)
    unreleased = untagged(package; kwargs...)

    for version in unreleased
        create_release
    end
end

end # module ExperimentalTagbot
