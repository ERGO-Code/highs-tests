# Copyright (c) 2022: jump-dev/benchmarks contributors
#
# Use of this source code is governed by an MIT-style license that can be found
# in the LICENSE.md file or at https://opensource.org/licenses/MIT.

import CSV
using DataFrames
import Dates
import Downloads
import GitHub
import JSON
import Pkg
import TOML

# Holds GitHub secrets. Not committed to the repository.
println("START iG ")
println(@__DIR__)

if isfile(joinpath(@__DIR__, "dev.env"))
    include("dev.env")
    println("Loaded GH secret IG")
end

const DATA_DIR = joinpath(dirname(@__DIR__), "repositories")

function Repository(repo; since, until, my_auth)
    println("Getting : ", repo)
    return GitHub.issues(
        repo;
        auth = my_auth,
        params = Dict("state" => "all", "since" => since, "until" => until),
    )
end

function get_repos(since, until)
    my_auth = GitHub.authenticate(ENV["PERSONAL_ACCESS_TOKEN"])
    all_repos, _ = GitHub.repos("ERGO-Code", auth = my_auth)
    return Dict(
        repo => Repository(
            "ERGO-Code/" * repo;
            since = since,
            until = until,
            my_auth = my_auth,
        ) for repo in map(r -> "$(r.name)", all_repos)
    )
end

function get_pkg_uuids()
    pkg_uuids = Dict{String,String}()
    r = first(Pkg.Registry.reachable_registries())
    Pkg.Registry.create_name_uuid_mapping!(r)
    for (uuid, pkg) in r.pkgs
        Pkg.Registry.init_package_info!(pkg)
        url = replace(pkg.info.repo, "https://github.com/" => "")
        pkg_uuids["$uuid"] = replace(url, ".git" => "")
    end
    return pkg_uuids
end


function update_package_statistics()
    since = "2013-01-01T00:00:00"
    repos = get_repos(since, Dates.now())
    data = Dict()
    for (k, v) in repos
        # if !(endswith(k, ".jl") || k in ("MathOptFormat",))
        #     continue
        # end
        events = Dict{String,Any}[]
        map(v[1]) do issue
            event = Dict(
                "user" => issue.user.login,
                "is_pr" => issue.pull_request !== nothing,
                "type" => "opened",
                "date" => issue.created_at,
            )
            push!(events, event)
            if issue.closed_at !== nothing
                event = copy(event)
                event["type"] = "closed"
                event["date"] = issue.closed_at
                push!(events, event)
            end
            return
        end
        data[k] = sort!(events, by = x -> x["date"])
    end
    open(joinpath(DATA_DIR, "data.json"), "w") do io
        return write(io, JSON.json(data))
    end
    return
end

function update_contributor_prs_over_time()
    data = JSON.parsefile(joinpath(DATA_DIR, "data.json"))
    # Compute the number of PRs per month
    all_prs = Dict{String,Int}()
    for (pkg, pkg_data) in data
        for item in pkg_data
            if item["is_pr"] && item["type"] == "opened"
                key = String(item["date"][1:7])
                all_prs[key] = get(all_prs, key, 0) + 1
            end
        end
    end
    # Find the earliest date of each contributor
    first_prs = Dict{String,String}()
    for (pkg, pkg_data) in data
        for item in pkg_data
            if item["is_pr"] && item["type"] == "opened"
                date = get(first_prs, item["user"], "9999-99")
                key = String(item["date"][1:7])
                if key < date
                    first_prs[item["user"]] = key
                end
            end
        end
    end
    # Compute the number of PRs by users in their first month
    new_prs = Dict{String,Int}()
    for (pkg, pkg_data) in data
        for item in pkg_data
            if item["is_pr"] && item["type"] == "opened"
                key = String(item["date"][1:7])
                if first_prs[item["user"]] == key
                    new_prs[key] = get(new_prs, key, 0) + 1
                end
            end
        end
    end
    dates = sort(collect(union(keys(all_prs), keys(new_prs))))
    counts = [(get(all_prs, date, 0), get(new_prs, date, 0)) for date in dates]
    open(joinpath(DATA_DIR, "contributor_prs_over_time.json"), "w") do io
        return write(io, JSON.json(Dict("dates" => dates, "counts" => counts)))
    end
    return
end

# This script was used to generate the list of contributors for the JuMP 1.0
# release. It may be helpful in future.
function print_all_contributors(; minimum_prs::Int = 1)
    data = JSON.parsefile(joinpath(DATA_DIR, "data.json"))
    prs_by_user = Dict{String,Int}()
    for (_, pkg_data) in data
        for item in pkg_data
            if item["is_pr"] && item["type"] == "opened"
                user = item["user"]
                if user in
                   ("github-actions[bot]", "JuliaTagBot", "femtocleaner[bot]")
                    continue
                end
                if haskey(prs_by_user, user)
                    prs_by_user[user] += 1
                else
                    prs_by_user[user] = 1
                end
            end
        end
    end
    names = collect(keys(prs_by_user))
    sort!(names; by = name -> (-prs_by_user[name], name))
    for name in names
        if prs_by_user[name] >= minimum_prs
            println(" * [@$(name)](https://github.com/$(name))")
        end
    end
    return prs_by_user
end

function prs_by_user(user)
    data = JSON.parsefile(joinpath(DATA_DIR, "data.json"))
    prs_by_user = Any[]
    for (pkg, pkg_data) in data
        for item in pkg_data
            if item["user"] == user && item["is_pr"] && item["type"] == "opened"
                push!(prs_by_user, (pkg, item))
            end
        end
    end
    return prs_by_user
end


has_arg(arg) = any(isequal(arg), ARGS)

if has_arg("--update")
    update_package_statistics()
    update_contributor_prs_over_time()
end


print("End of file IG")

# print_all_contributors()