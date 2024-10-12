module ExperimentalTagbot

import Pkg
using Git
using GitHub

export versions, repository, clone, commits_between

"""
Given a package name, return map from all versions released in the general 
registry to the Git SHA1 hashes in the project location.

# Extended Help

This code was originally written by user @yakir12 on Julia's Discourse in 
the following post: https://discourse.julialang.org/t/pkg-version-list/1257/10.
"""
function versions(pkgname::AbstractString)
    registry = only(filter(r -> r.name == "General", Pkg.Registry.reachable_registries()))

    local pkg

    try
        pkg = only(filter(pkg -> pkg.name == pkgname, collect(values(registry.pkgs))))
    catch e
        if e isa ArgumentError
            throw(ErrorException("$pkgname is not registered in the General package registry"))
        else
            rethrow(e)
        end
    end

    vs = [pair.first => pair.second.git_tree_sha1 for pair in Pkg.Registry.registry_info(pkg).version_info]
    sort!(vs, by=x -> x.first)
    return vs
end

"""
Given a package name, return the project repository registered in the General 
registry.
"""
function url(pkgname::AbstractString)
    registry = only(filter(r -> r.name == "General", Pkg.Registry.reachable_registries()))
    pkg = only(filter(pkg -> pkg.name == pkgname, collect(values(registry.pkgs))))
    return Pkg.Registry.registry_info(pkg).repo
end

function clone(url)
    tmp = joinpath(tempdir(), tempname())
    run(git(["clone", convert(String, url), tmp, "--bare"]))
    return tmp
end


function commits_between(repo, base, tip)
    local hashes
    cd(repo) do
        hashes = readlines(git(["rev-list", "$base..$tip", "--exclude", tip]))
    end

    return map(hash -> commit(repo, hash), hashes)
end

end # module ExperimentalTagbot
