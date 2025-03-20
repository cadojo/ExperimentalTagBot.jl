"""
A minimal TagBot implementation in Julia!

## Exports

$(EXPORTS)
"""
module TagBot

using DocStringExtensions

@template DEFAULT = """
                    $(SIGNATURES)
                    $(DOCSTRING)
                    """

import Pkg
using Git: git
import GitHub
using Markdown
import IOCapture
using Dates

"""
Given a package name, return map from all versions released in the general
registry to the Git SHA1 hashes in the project location.

# Extended Help

This code was originally written by user @yakir12 on Julia's Discourse in
the following post: https://discourse.julialang.org/t/pkg-version-list/1257/10.
"""
function registered_versions_map(package::AbstractString; registry = "General")
    registry = only(filter(r -> r.name == registry, Pkg.Registry.reachable_registries()))

    local pkg

    try
        pkg = only(filter(pkg -> pkg.name == package, collect(values(registry.pkgs))))
    catch e
        if e isa ArgumentError
            throw(
                ErrorException(
                "$package is not registered in the General package registry",
            ),
            )
        else
            rethrow(e)
        end
    end

    vs = [pair.first => pair.second.git_tree_sha1
          for
          pair in Pkg.Registry.registry_info(pkg).version_info]
    sort!(vs, by = x -> x.first)
    return Dict(["v" * string(pair.first) => pair.second for pair in vs])
end

"""
Given a package name, return all versions released in the general registry.
"""
function registered_versions(package::AbstractString; registry = "General")
    vs = collect(keys(registered_versions_map(package)))
    sort!(vs, by = VersionNumber)
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
function package_url(package::AbstractString; registry = "General")
    reg = only(filter(r -> r.name == registry, Pkg.Registry.reachable_registries()))
    pkg = only(filter(pkg -> pkg.name == package, collect(values(reg.pkgs))))
    return Pkg.Registry.registry_info(pkg).repo
end

"""
Given a repository URL, return the unique "{owner}/{project}" string.
"""
function repository_name(url::AbstractString)
    return replace(
        url,
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
function untagged_versions(package::AbstractString; registry = "General", kwargs...)
    registered = registered_versions(package; registry = registry)

    try
        tags, metadata = GitHub.tags(repository_name(package_url(package)); kwargs...)
    catch e
        if e isa ErrorException
            return registered
        else
            rethrow()
        end
    end

    tags = String[tag.tag for tag in tags if !isnothing(tag.tag)]

    for tag in tags
        version = replace(tag, (package * "-") => "")
        deleteat!(registered, findall(v -> v == version, registered))
    end

    tags = registered
    sort!(tags, by = VersionNumber)

    return tags
end

function parent_hash(version, versions)
    v = VersionNumber(version)
    vs = map(VersionNumber, collect(versions))

    filter!(n -> n < v, vs)

    if isempty(vs)
        return nothing
    end

    v = maximum(vs)
    return "v" * string(v)
end

"""
Given a package name and version, return release PRs from in the provided registry.
"""
function release_pull_requests(package, version; registry = "General", kwargs...)
    v = "v" * string(VersionNumber(version))
    results = GitHub.gh_get_json(
        GitHub.DEFAULT_API,
        "/search/issues";
        kwargs...,
        params = "q=$package%20$v%20in%3Atitle%20is%3Apr%20repo%3A$(repository_name(registry_url(registry)))",
        kwargs...
    )
    return [GitHub.PullRequest(result) for result in results["items"]]
end

"""
Given a package name and version, return all pull requests from the package
repository between the version and its parent.
"""
function find_pull_requests(package, version; kwargs...)
    repo = repository_name(package_url(package))
    parent = parent_hash(version, registered_versions(package))

    if isnothing(parent)
        commits, metadata = GitHub.commits(repository_name(package_url(package)); kwargs...)
        parent = commits[end].sha # TODO is the oldest commit what we want here?
    end

    base = GitHub.commit(
        repo, parent; kwargs...)
    head = GitHub.commit(repo, registered_version_info(package, version).commit_hash; kwargs...)

    base_date = string(Date(base.commit.author.date))
    base_date = replace(base_date, ":" => "%3A")

    head_date = string(Date(head.commit.author.date))
    head_date = replace(head_date, ":" => "%3A")

    results = GitHub.gh_get_json(
        GitHub.DEFAULT_API,
        "/search/issues";
        kwargs...,
        params = "q=merged%3A>=$base_date%20is%3Apr%20repo%3A$(repository_name(package_url(package)))",
        kwargs...
    )

    prs = [GitHub.PullRequest(result)
           for result in results["items"]]

    return [pr
            for pr in prs
            if pr.closed_at <= head.commit.author.date]
end
"""
Given a package name and version, return all pull requests from the package
repository between the version and its parent.
"""
function find_issues(package, version; kwargs...)
    repo = repository_name(package_url(package))
    parent = parent_hash(version, registered_versions(package))

    if isnothing(parent)
        commits, metadata = GitHub.commits(repository_name(package_url(package)); kwargs...)
        parent = commits[end].sha # TODO is the oldest commit what we want here?
    end

    base = GitHub.commit(
        repo, parent; kwargs...)
    head = GitHub.commit(repo, registered_version_info(package, version).commit_hash; kwargs...)

    base_date = string(Date(base.commit.author.date))
    base_date = replace(base_date, ":" => "%3A")

    head_date = string(Date(head.commit.author.date))
    head_date = replace(head_date, ":" => "%3A")

    results = GitHub.gh_get_json(
        GitHub.DEFAULT_API,
        "/search/issues";
        kwargs...,
        params = "q=closed%3A>=$base_date%20is%3Aissue%20repo%3A$(repository_name(package_url(package)))",
        kwargs...
    )

    issues = [GitHub.Issue(result)
              for result in results["items"]]

    return [issue
            for issue in issues
            if issue.closed_at <= head.commit.author.date]
end


"""
Given the package name and version, return the latest release PR commit which
has been merged.
"""
function registered_version_info(
        package::AbstractString, version; registry = "General", kwargs...
)
    prs = [GitHub.pull_request(
               repository_name(registry_url(registry)), pr.number; kwargs...)
           for
           pr in release_pull_requests(package, version; registry = registry, kwargs...)]

    filter!(pr -> pr.merged, prs) # remove PRs which did not merge
    sort!(prs; by = pr -> pr.closed_at) # sort PRs by merge timestamp

    pr = last(prs) # take the most recent merged PR

    lines = readlines(IOBuffer(pr.body))
    commit_line_idx = findfirst(startswith("- Commit: "), lines)
    isnothing(commit_line_idx) && error("commit not found for $package $version")
    _, commit_hash = rsplit(lines[commit_line_idx], ":"; limit = 2)
    commit_hash = strip(commit_hash)
    m = match(r"(?s)<!-- BEGIN RELEASE NOTES -->\n`````(.*)`````\n<!-- END RELEASE NOTES -->", pr.body)
    release_notes = isnothing(m) ? nothing : strip(m[1])

    return (; commit_hash, release_notes, body=pr.body)
end

function release_message(package::AbstractString, version; prefix = nothing, kwargs...)
    version = string(VersionNumber(version))
    base = parent_hash(version, registered_versions(package))
    if isnothing(base)
        commits, metadata = GitHub.commits(repository_name(package_url(package)); kwargs...)
        base = commits[end].sha # TODO is the oldest commit what we want here?
    end
    info = registered_version_info(package, version)
    head = info.commit_hash
    prefix = isnothing(prefix) ? "" : prefix
    diff = GitHub.compare(
        repository_name(package_url(package)), base, head; kwargs...)

    messages = ["* " * replace(commit.commit.message, "\n\n" => "\n")
                for commit in diff.commits]
    pull_requests = ["* $(pr.title) ([#$(pr.number)]($(pr.html_url)))"
                     for pr in find_pull_requests(package, version; kwargs...)]
    issues = ["* $(issue.title) ([#$(issue.number)]($(issue.html_url)))"
              for issue in find_issues(package, version; kwargs...)]

    if isempty(pull_requests)
        pull_requests = ["None"]
    end

    if isempty(issues)
        issues = ["None"]
    end

    release_notes = isnothing(info.release_notes) ? tuple() : (info.release_notes,)
    lines = (
        release_notes...,
        "[$base...$head]($(package_url(package))/compare/$base...$head)",
        "\n## Closed Issues",
        join(issues, "\n"),
        "\n## Merged Pull Requests",
        join(pull_requests, "\n"),
        "\n## Changelog",
        join(messages, "\n")
    )

    return join(lines, "\n")
end

function create_release(
        package::AbstractString, version; prefix = nothing, kwargs...)
    prefix = isnothing(prefix) ? "" : prefix

    repo = repository_name(package_url(package))
    version = string(VersionNumber(version))
    hash = registered_version_info(package, version).commit_hash

    tag = "$(prefix)v$(version)"

    default = Dict(
        "tag_name" => tag,
        "target_commitish" => hash,
        "name" => "Release v$version for `$package`",
        "body" => release_message(package, version; kwargs...),
        "draft" => false,
        "prerelease" => false,
        "generate_release_notes" => false
    )

    options = merge((; params = default), kwargs)

    @debug """creating release with the following options:
    $(collect(options))
    """

    @info "Creating Release v$(version) for $package.jl"

    GitHub.create_release(repo; options...)
end

function create_releases(
        package::AbstractString; prefix = nothing, registry = "General", kwargs...)
    unreleased = untagged_versions(package; registry = registry, kwargs...)

    for version in unreleased
        create_release(package, version; prefix = prefix, kwargs...)
    end
end

end # module TagBot
