# In this file, we setup the `gen_download_cmd()`, `gen_unpack_cmd()` and
# `gen_package_cmd()` functions by providing methods to probe the environment
# and determine the most appropriate platform binaries to call.

export gen_download_cmd, gen_unpack_cmd, gen_package_cmd, gen_list_tarball_cmd,
       parse_tarball_listing, gen_sh_cmd, parse_7z_list, parse_tar_list,
       download_verify_unpack, download_verify, unpack

"""
`gen_download_cmd(url::AbstractString, out_path::AbstractString)`

Return a `Cmd` that will download resource located at `url` and store it at
the location given by `out_path`.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
gen_download_cmd = (url::AbstractString, out_path::AbstractString) ->
    error("Call `probe_platform_engines()` before `gen_download_cmd()`")

"""
`gen_unpack_cmd(tarball_path::AbstractString, out_path::AbstractString)`

Return a `Cmd` that will unpack the given `tarball_path` into the given
`out_path`.  If `out_path` is not already a directory, it will be created.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
gen_unpack_cmd = (tarball_path::AbstractString, out_path::AbstractString) ->
    error("Call `probe_platform_engines()` before `gen_unpack_cmd()`")

"""
`gen_package_cmd(in_path::AbstractString, tarball_path::AbstractString)`

Return a `Cmd` that will package up the given `in_path` directory into a
tarball located at `tarball_path`.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
gen_package_cmd = (in_path::AbstractString, tarball_path::AbstractString) ->
    error("Call `probe_platform_engines()` before `gen_package_cmd()`")

"""
`gen_list_tarball_cmd(tarball_path::AbstractString)`

Return a `Cmd` that will list the files contained within the tarball located at
`tarball_path`.  The list will not include directories contained within the
tarball.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
gen_list_tarball_cmd = (tarball_path::AbstractString) ->
    error("Call `probe_platform_engines()` before `gen_list_tarball_cmd()`")

"""
`parse_tarball_listing(output::AbstractString)`

Parses the result of `gen_list_tarball_cmd()` into something useful.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
parse_tarball_listing = (output::AbstractString) ->
    error("Call `probe_platform_engines()` before `parse_tarball_listing()`")

"""
`gen_sh_cmd(cmd::Cmd)`

Runs a command using `sh`.  On Unices, this will default to the first `sh`
found on the `PATH`, however on Windows if that is not found it will fall back
to the `sh` provided by the `busybox.exe` shipped with Julia.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
gen_sh_cmd = (cmd::Cmd) ->
    error("Call `probe_platform_engines()` before `gen_sh_cmd()`")


"""
`probe_cmd(cmd::Cmd; verbose::Bool = false)`

Returns `true` if the given command executes successfully, `false` otherwise.
"""
function probe_cmd(cmd::Cmd; verbose::Bool = false)
    if verbose
        info("Probing $(cmd.exec[1]) as a possibility...")
    end
    try
        success(cmd)
        if verbose
            info("  Probe successful for $(cmd.exec[1])")
        end
        return true
    catch
        return false
    end
end

"""
`probe_platform_engines!(;verbose::Bool = false)`

Searches the environment for various tools needed to download, unpack, and
package up binaries.  Searches for a download engine to be used by
`gen_download_cmd()` and a compression engine to be used by `gen_unpack_cmd()`,
`gen_package_cmd()`, `gen_list_tarball_cmd()` and `parse_tarball_listing()`, as
well as a `sh` execution engine for `gen_sh_cmd()`.  Running this function
will set the global functions to their appropriate implementations given the
environment this package is running on.

This probing function will automatically search for download engines using a
particular ordering; if you wish to override this ordering and use one over all
others, set the `BINARYPROVIDER_DOWNLOAD_ENGINE` environment variable to its
name, and it will be the only engine searched for. For example, put:

    ENV["BINARYPROVIDER_DOWNLOAD_ENGINE"] = "fetch"

within your `~/.juliarc.jl` file to force `fetch` to be used over `curl`.  If
the given override does not match any of the download engines known to this
function, a warning will be printed and the typical ordering will be performed.

Similarly, if you wish to override the compression engine used, set the
`BINARYPROVIDER_COMPRESSION_ENGINE` environment variable to its name (e.g. `7z`
or `tar`) and it will be the only engine searched for.  If the given override
does not match any of the compression engines known to this function, a warning
will be printed and the typical searching will be performed.

If `verbose` is `true`, print out the various engines as they are searched.
"""
function probe_platform_engines!(;verbose::Bool = false)
    global gen_download_cmd, gen_list_tarball_cmd, gen_package_cmd
    global gen_unpack_cmd, parse_tarball_listing, gen_sh_cmd

    # download_engines is a list of (test_cmd, download_opts_functor)
    # The probulator will check each of them by attempting to run `$test_cmd`,
    # and if that works, will set the global download functions appropriately.
    download_engines = [
        (`curl --help`, (url, path) -> `curl -C - -\# -f -o $path -L $url`),
        (`wget --help`, (url, path) -> `wget -c -O $path $url`),
        (`fetch --help`, (url, path) -> `fetch -f $path $url`),
    ]

    # 7z is rather intensely verbose.  We also want to try running not only
    # `7z` but also a direct path to the `7z.exe` bundled with Julia on
    # windows, so we create generator functions to spit back functors to invoke
    # the correct 7z given the path to the executable:
    unpack_7z = (exe7z) -> begin
        return (tarball_path, out_path) ->
            pipeline(`$exe7z x $(tarball_path) -y -so`,
                     `$exe7z x -si -y -ttar -o$(out_path)`)
    end
    package_7z = (exe7z) -> begin
        return (in_path, tarball_path) ->
            pipeline(`$exe7z a -ttar -so a.tar "$(joinpath(".",in_path,"*"))"`,
                     `$exe7z a -si $(tarball_path)`)
    end
    list_7z = (exe7z) -> begin
        return (path) ->
            pipeline(`$exe7z x $path -so`, `$exe7z l -ttar -y -si`)
    end

    # Tar is rather less verbose, and we don't need to search multiple places
    # for it, so just rely on PATH to have `tar` available for us:
    unpack_tar = (tarball_path, out_path) ->
        `tar xf $(tarball_path) --directory=$(out_path)`
    package_tar = (in_path, tarball_path) ->
        `tar -czvf $tarball_path -C $(in_path) .`
    list_tar = (in_path) -> `tar tf $in_path`

    # compression_engines is a list of (test_cmd, unpack_opts_functor,
    # package_opts_functor, list_opts_functor, parse_functor).  The probulator
    # will check each of them by attempting to run `$test_cmd`, and if that
    # works, will set the global compression functions appropriately.
    gen_7z = (p) -> (unpack_7z(p), package_7z(p), list_7z(p), parse_7z_list)
    compression_engines = Tuple[
        (`tar --help`, unpack_tar, package_tar, list_tar, parse_tar_list),
    ]

    # sh_engines is just a list of Cmds-as-paths
    sh_engines = [
        `sh`
    ]

    # For windows, we need to tweak a few things, as the tools available differ
    @static if Compat.Sys.iswindows()
        # For download engines, we will most likely want to use powershell.
        # Let's generate a functor to return the necessary powershell magics
        # to download a file, given a path to the powershell executable
        psh_download = (psh_path) -> begin
            return (url, path) -> begin
                webclient_code = """
                [System.Net.ServicePointManager]::SecurityProtocol =
                    [System.Net.SecurityProtocolType]::Tls12;
                \$webclient = (New-Object System.Net.Webclient);
                \$webclient.DownloadFile(\"$url\", \"$path\")
                """
                replace(webclient_code, "\n", " ")
                return `$psh_path -NoProfile -Command "$webclient_code"`
            end
        end

        # We want to search both the `PATH`, and the direct path for powershell
        psh_path = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell"
        prepend!(download_engines, [
            (`$psh_path -Help`, psh_download(psh_path))
        ])
        prepend!(download_engines, [
            (`powershell -Help`, psh_download(`powershell`))
        ])

        # We greatly prefer `7z` as a compression engine on Windows
        prepend!(compression_engines, [(`7z --help`, gen_7z("7z")...)])

        # On windows, we bundle 7z with Julia, so try invoking that directly
        exe7z = joinpath(JULIA_HOME, "7z.exe")
        prepend!(compression_engines, [(`$exe7z --help`, gen_7z(exe7z)...)])

        # And finally, we want to look for sh as busybox as well:
        busybox = joinpath(JULIA_HOME, "busybox.exe")
        prepend!(sh_engines, [(`$busybox sh`)])
    end

    # Allow environment override
    if haskey(ENV, "BINARYPROVIDER_DOWNLOAD_ENGINE")
        engine = ENV["BINARYPROVIDER_DOWNLOAD_ENGINE"]
        dl_ngs = filter(e -> e[1].exec[1] == engine, download_engines)
        if isempty(dl_ngs)
            all_ngs = join([d[1].exec[1] for d in download_engines], ", ")
            warn_msg  = "Ignoring BINARYPROVIDER_DOWNLOAD_ENGINE as its value "
            warn_msg *= "of `$(engine)` doesn't match any known valid engines."
            warn_msg *= " Try one of `$(all_ngs)`."
            warn(warn_msg)
        else
            # If BINARYPROVIDER_DOWNLOAD_ENGINE matches one of our download engines,
            # then restrict ourselves to looking only at that engine
            download_engines = dl_ngs
        end
    end

    if haskey(ENV, "BINARYPROVIDER_COMPRESSION_ENGINE")
        engine = ENV["BINARYPROVIDER_COMPRESSION_ENGINE"]
        comp_ngs = filter(e -> e[1].exec[1] == engine, compression_engines)
        if isempty(comp_ngs)
            all_ngs = join([c[1].exec[1] for c in compression_engines], ", ")
            warn_msg  = "Ignoring BINARYPROVIDER_COMPRESSION_ENGINE as its "
            warn_msg *= "value of `$(engine)` doesn't match any known valid "
            warn_msg *= "engines. Try one of `$(all_ngs)`."
            warn(warn_msg)
        else
            # If BINARYPROVIDER_COMPRESSION_ENGINE matches one of our download
            # engines, then restrict ourselves to looking only at that engine
            compression_engines = comp_ngs
        end
    end

    download_found = false
    compression_found = false
    sh_found = false

    if verbose
        info("Probing for download engine...")
    end

    # Search for a download engine
    for (test, dl_func) in download_engines
        if probe_cmd(`$test`; verbose=verbose)
            # Set our download command generator
            gen_download_cmd = dl_func
            download_found = true

            if verbose
                info("Found download engine $(test.exec[1])")
            end
            break
        end
    end

    if verbose
        info("Probing for compression engine...")
    end

    # Search for a compression engine
    for (test, unpack, package, list, parse) in compression_engines
        if probe_cmd(`$test`; verbose=verbose)
            # Set our compression command generators
            gen_unpack_cmd = unpack
            gen_package_cmd = package
            gen_list_tarball_cmd = list
            parse_tarball_listing = parse

            if verbose
                info("Found compression engine $(test.exec[1])")
            end

            compression_found = true
            break
        end
    end

    if verbose
        info("Probing for sh engine...")
    end

    for path in sh_engines
        if probe_cmd(`$path --help`; verbose=verbose)
            gen_sh_cmd = (cmd) -> `$path -c $cmd`
            if verbose
                info("Found sh engine $(path.exec[1])")
            end
            sh_found = true
            break
        end
    end


    # Build informative error messages in case things go sideways
    errmsg = ""
    if !download_found
        errmsg *= "No download engines found. We looked for: "
        errmsg *= join([d[1].exec[1] for d in download_engines], ", ")
        errmsg *= ". Install one and ensure it  is available on the path.\n"
    end

    if !compression_found
        errmsg *= "No compression engines found. We looked for: "
        errmsg *= join([c[1].exec[1] for c in compression_engines], ", ")
        errmsg *= ". Install one and ensure it is available on the path.\n"
    end

    if !sh_found
        errmsg *= "No sh engines found. We looked for: "
        errmsg *= join([b.exec[1] for b in sh_engines], ", ")
        errmsg *= ". Install one and ensure it is available on the path.\n"
    end

    # Error out if we couldn't find something
    if !download_found || !compression_found || !sh_found
        error(errmsg)
    end
end

"""
`parse_7z_list(output::AbstractString)`

Given the output of `7z l`, parse out the listed filenames.  This funciton used
by  `list_tarball_files`.
"""
function parse_7z_list(output::AbstractString)
    lines = [chomp(l) for l in split(output, "\n")]
    # Remove extraneous "\r" for windows platforms
    for idx in 1:length(lines)
        if endswith(lines[idx], '\r')
            lines[idx] = lines[idx][1:end-1]
        end
    end

    # Find index of " Name". (can't use `findfirst(generator)` until this is
    # closed: https://github.com/JuliaLang/julia/issues/16884
    header_row = find(contains(l, " Name") && contains(l, " Attr") for l in lines)[1]
    name_idx = search(lines[header_row], "Name")[1]
    attr_idx = search(lines[header_row], "Attr")[1] - 1

    # Filter out only the names of files, ignoring directories
    lines = [l[name_idx:end] for l in lines if length(l) > name_idx && l[attr_idx] != 'D']
    if isempty(lines)
        return []
    end

    # Extract within the bounding lines of ------------
    bounds = [i for i in 1:length(lines) if all([c for c in lines[i]] .== '-')]
    lines = lines[bounds[1]+1:bounds[2]-1]

    # Eliminate `./` prefix, if it exists
    for idx in 1:length(lines)
        if startswith(lines[idx], "./") || startswith(lines[idx], ".\\")
            lines[idx] = lines[idx][3:end]
        end
    end

    return lines
end

"""
`parse_7z_list(output::AbstractString)`

Given the output of `tar -t`, parse out the listed filenames.  This funciton
used by `list_tarball_files`.
"""
function parse_tar_list(output::AbstractString)
    lines = [chomp(l) for l in split(output, "\n")]

    # Drop empty lines and and directories
    lines = [l for l in lines if !isempty(l) && !endswith(l, '/')]

    # Eliminate `./` prefix, if it exists
    for idx in 1:length(lines)
        if startswith(lines[idx], "./") || startswith(lines[idx], ".\\")
            lines[idx] = lines[idx][3:end]
        end
    end

    return lines
end

"""
    download(url::AbstractString, dest::AbstractString;
             verbose::Bool = false)

Download file located at `url`, store it at `dest`, continuing if `dest`
already exists and the server and download engine support it.
"""
function download(url::AbstractString, dest::AbstractString;
                  verbose::Bool = false)
    download_cmd = gen_download_cmd(url, dest)
    if verbose
        info("Downloading $(url) to $(dest)...")
    end
    oc = OutputCollector(download_cmd; verbose=verbose)
    try
        if !wait(oc)
            error()
        end
    catch e
        if isa(e, InterruptException)
            rethrow()
        end
        error("Could not download $(url) to $(dest)")
    end
end

"""
    download_verify(url::AbstractString, hash::AbstractString,
                    dest::AbstractString; verbose::Bool = false,
                    force::Bool = false, quiet_download::Bool = false)

Download file located at `url`, verify it matches the given `hash`, and throw
an error if anything goes wrong.  If `dest` already exists, just verify it. If
`force` is set to `true`, overwrite the given file if it exists but does not
match the given `hash`.

This method returns `true` if the file was downloaded successfully, `false`
if an existing file was removed due to the use of `force`, and throws an error
if `force` is not set and the already-existant file fails verification, or if
`force` is set, verification fails, and then verification fails again after
redownloading the file.

If `quiet_download` is set to `false` (the default), this method will print to
stdout when downloading a new file.  If it is set to `true` (and `verbose` is
set to `false`) the downloading process will be completely silent.  If
`verbose` is set to `true`, messages about integrity verification will be
printed in addition to messages regarding downloading.
"""
function download_verify(url::AbstractString, hash::AbstractString,
                         dest::AbstractString; verbose::Bool = false,
                         force::Bool = false, quiet_download::Bool = false)
    # Whether the file existed in the first place
    file_existed = false

    if isfile(dest)
        file_existed = true
        if verbose
            info_onchange(
                "Destination file $(dest) already exists, verifying...",
                "download_verify_$(dest)",
                @__LINE__,
            )
        end

        # verify download, if it passes, return happy.  If it fails, (and
        # `force` is `true`, re-download!)
        try
            verify(dest, hash; verbose=verbose)
            return true
        catch e
            if isa(e, InterruptException)
                rethrow()
            end
            if !force
                rethrow()
            end
            if verbose
                info_onchange(
                    "Verification failed, re-downloading...",
                    "download_verify_$(dest)",
                    @__LINE__,
                )
            end
        end
    end

    # Make sure the containing folder exists
    mkpath(dirname(dest))

    try
        # Download the file, optionally continuing
        download(url, dest; verbose=verbose || !quiet_download)

        verify(dest, hash; verbose=verbose)
    catch e
        if isa(e, InterruptException)
            rethrow()
        end
        # If the file already existed, it's possible the initially downloaded chunk
        # was bad.  If verification fails after downloading, auto-delete the file
        # and start over from scratch.
        if file_existed
            if verbose
                info("Continued download didn't work, restarting from scratch")
            end
            rm(dest; force=true)

            # Download and verify from scratch
            download(url, dest; verbose=verbose || !quiet_download)
            verify(dest, hash; verbose=verbose)
        else
            # If it didn't verify properly and we didn't resume, something is
            # very wrong and we must complain mightily.
            rethrow()
        end
    end

    # If the file previously existed, this means we removed it (due to `force`)
    # and redownloaded, so return `false`.  If it didn't exist, then this means
    # that we successfully downloaded it, so return `true`.
    return !file_existed
end

"""
`unpack(tarball_path::AbstractString, dest::AbstractString;
        verbose::Bool = false)`

Unpack tarball located at file `tarball_path` into directory `dest`.
"""
function unpack(tarball_path::AbstractString, dest::AbstractString;
                verbose::Bool = false)
    # unpack into dest
    mkpath(dest)
    oc = OutputCollector(gen_unpack_cmd(tarball_path, dest); verbose=verbose)
    try 
        if !wait(oc)
            error()
        end
    catch e
        if isa(e, InterruptException)
            rethrow()
        end
        error("Could not unpack $(tarball_path) into $(dest)")
    end
end


"""
`download_verify_unpack(url::AbstractString, hash::AbstractString,
                        dest::AbstractString; verbose::Bool = false,
                        force::Bool = false)`

Helper method to download tarball located at `url`, verify it matches the
given `hash`, then unpack it into folder `dest`.  In general, the method
`install()` should be used to download and install tarballs into a `Prefix`;
this method should only be used if the extra functionality of `install()` is
undesired.

If `tarball_path` is specified, the given `url` will be downloaded to
`tarball_path`, and it will not be removed after downloading and verification
is complete.  If it is not specified, the tarball will be downloaded to a
temporary location, and removed after verification is complete.

If `force` is specified, a verification failure will cause `tarball_path` to be
deleted (if it exists), the `dest` folder to be removed (if it exists) and the
tarball to be redownloaded and reverified.  If the verification check is failed
a second time, an exception is raised.  If `force` is not specified, a
verification failure will result in an immediate raised exception.
"""
function download_verify_unpack(url::AbstractString,
                                hash::AbstractString,
                                dest::AbstractString;
                                tarball_path = nothing,
                                force::Bool = false,
                                verbose::Bool = false)
    # First, determine whether we should keep this tarball around
    remove_tarball = false
    if tarball_path === nothing
        remove_tarball = true
        tarball_path = "$(tempname())-download.tar.gz"
    end

    # Download the tarball; if it already existed and we needed to remove it
    # then we should remove the unpacked path as well
    should_delete = !download_verify(url, hash, tarball_path;
                                     force=force, verbose=verbose)
    if should_delete
        if verbose
            info("Removing dest directory $(dest) as source tarball changed")
        end
        rm(dest; recursive=true, force=true)
    end

    # If the destination path already exists, don't bother to unpack
    if isdir(dest)
        if verbose
            info("Destination directory $(dest) already exists, returning")
        end
        return
    end

    try
        if verbose
            info("Unpacking $(tarball_path) into $(dest)...")
        end
        unpack(tarball_path, dest; verbose=verbose)
    finally
        if remove_tarball
            rm(tarball_path)
        end
    end
end
