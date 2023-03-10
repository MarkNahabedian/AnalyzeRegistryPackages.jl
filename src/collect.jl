export collect_stats_from_registry

EXCEPTION = nothing

function collect_stats_from_registry(registry_repo)
    collection_file = new_file_path(COLLECTION_FILE)
    uri_file = new_file_path(REPO_URIS_FILE)
    ensure_tsv_file(collection_file, COLLECTION_FILE_COLUMNS)
    ensure_tsv_file(uri_file, REPO_URIS_COLUMNS)
    throttle = throttle_for(registry_repo)
    throttle_request(throttle)
    toml = fetch_registry_toml(registry_repo)
    packages = toml["packages"]
    remaining = length(packages)
    done = whats_done(collection_file)
    remaining -= length(done)
    function do_package(uuid, d)
        name = d["name"]
        if name == get(done, uuid, nothing)
            # Skip a package if it's already been analyzed
            return
        end
        path = d["path"]
        throttle_request(throttle)
        t = TOML.parse(fetch_gh_file_contents(registry_repo, "$path/Package.toml"))
        @assert uuid == t["uuid"]
        stats = get_stats_from_package(t["repo"])
        write_tsv_row(uri_file, name, uuid, t["repo"])
        write_tsv_row(collection_file, name, uuid, stats...)
        remaining -= 1
        if mod(remaining, 10) == 0
            println("$remaining remaining.")
        end
    end
    println("$remaining remaining.")
    for (uuid, d) in packages
        try
            do_package(uuid, d)
        catch e
            global EXCEPTION = e
            show(e)
            break
            "API rate limit exceeded"
        end
    end
end

function get_stats_from_package(package_url::String)
    println("$(Dates.format(Dates.now(), "HH:MM:SS"))   Analyzing $package_url")
    analysis =
        mktempdir(; prefix="AnalyzePackages_") do root
            PackageAnalyzer.analyze(package_url; root=root)
        end
    reach = analysis.reachable
    src = PackageAnalyzer.count_julia_loc(analysis, "src")
    tests = PackageAnalyzer.count_julia_loc(analysis, "test")
    docs = PackageAnalyzer.count_docs(analysis)
    readme = PackageAnalyzer.count_readme(analysis)
    return reach, src, tests, docs, readme
end

