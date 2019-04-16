# In this file, we setup the `gen_download_cmd()`, `gen_unpack_cmd()` and
# `gen_package_cmd()` functions by providing methods to probe the environment
# and determine the most appropriate platform binaries to call.

export gen_download_cmd, gen_unpack_cmd, gen_package_cmd, gen_list_tarball_cmd,
       parse_tarball_listing, gen_sh_cmd, parse_7z_list, parse_tar_list,
       download_verify_unpack, download_verify, unpack

const download_command_func = Ref{Function}()
"""
    gen_download_cmd(url::AbstractString, out_path::AbstractString)

Return a `Cmd` that will download resource located at `url` and store it at
the location given by `out_path`.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
function gen_download_cmd(url::AbstractString, out_path::AbstractString)
    if isassigned(download_command_func)
        download_command_func[](url, out_path)
    else
        error("Call `probe_platform_engines()` before `gen_download_cmd()`")
    end
end


const gen_unpack_cmd_func = Ref{Function}()
"""
    gen_unpack_cmd(tarball_path::AbstractString, out_path::AbstractString)

Return a `Cmd` that will unpack the given `tarball_path` into the given
`out_path`.  If `out_path` is not already a directory, it will be created.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
function gen_unpack_cmd(tarball_path::AbstractString, out_path::AbstractString)
    if isassigned(gen_unpack_cmd_func)
        gen_unpack_cmd_func[](tarball_path, out_path)
    else
        error("Call `probe_platform_engines()` before `gen_unpack_cmd()`")
    end
end

const gen_package_cmd_func = Ref{Function}()
"""
    gen_package_cmd(in_path::AbstractString, tarball_path::AbstractString)

Return a `Cmd` that will package up the given `in_path` directory into a
tarball located at `tarball_path`.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
function gen_package_cmd(in_path::AbstractString, tarball_path::AbstractString)
    if isassigned(gen_package_cmd_func)
        gen_package_cmd_func[](in_path, tarball_path)
    else
        error("Call `probe_platform_engines()` before `gen_package_cmd()`")
    end
end

const gen_list_tarball_cmd_func = Ref{Function}()
"""
    gen_list_tarball_cmd(tarball_path::AbstractString)

Return a `Cmd` that will list the files contained within the tarball located at
`tarball_path`.  The list will not include directories contained within the
tarball.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
function gen_list_tarball_cmd(tarball_path::AbstractString)
    if isassigned(gen_list_tarball_cmd_func)
        gen_list_tarball_cmd_func[](tarball_path)
    else
        error("Call `probe_platform_engines()` before `gen_list_tarball_cmd()`")
    end
end


const parse_tarball_listing_func = Ref{Function}()
"""
    parse_tarball_listing(output::AbstractString)

Parses the result of `gen_list_tarball_cmd()` into something useful.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
function parse_tarball_listing(output::AbstractString)
    if isassigned(parse_tarball_listing_func)
        parse_tarball_listing_func[](output)
    else
        error("Call `probe_platform_engines()` before `parse_tarball_listing()`")
    end
end

const gen_sh_cmd_func = Ref{Function}()
"""
    gen_sh_cmd(cmd::Cmd)

Runs a command using `sh`.  On Unices, this will default to the first `sh`
found on the `PATH`, however on Windows if that is not found it will fall back
to the `sh` provided by the `busybox.exe` shipped with Julia.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
function gen_sh_cmd(cmd::Cmd)
    if isassigned(gen_sh_cmd_func)
        gen_sh_cmd_func[](cmd)
    else
        error("Call `probe_platform_engines()` before `gen_sh_cmd()`")
    end
end


"""
    probe_cmd(cmd::Cmd; verbose::Bool = false)

Returns `true` if the given command executes successfully, `false` otherwise.
"""
function probe_cmd(cmd::Cmd; verbose::Bool = false)
    if verbose
        @info("Probing $(cmd.exec[1]) as a possibility...")
    end
    try
        success(cmd)
        if verbose
            @info("  Probe successful for $(cmd.exec[1])")
        end
        return true
    catch
        return false
    end
end

"""
    probe_symlink_creation(dest::AbstractString)

Probes whether we can create a symlink within the given destination directory,
to determine whether a particular filesystem is "symlink-unfriendly".
"""
function probe_symlink_creation(dest::AbstractString)
    while !isdir(dest)
        dest = dirname(dest)
    end

    # Build arbitrary (non-existent) file path name
    link_path = joinpath(dest, "binaryprovider_symlink_test")
    while ispath(link_path)
        link_path *= "1"
    end

    try
        symlink("foo", link_path)
        return true
    catch e
        if isa(e, Base.IOError)
            return false
        end
        rethrow(e)
    finally
        rm(link_path; force=true)
    end
end

# Global variable that tells us whether tempdir() can have symlinks
# created within it.
const tempdir_symlink_creation = Ref(false)

# 7z is rather intensely verbose.  We also want to try running not only
# `7z` but also a direct path to the `7z.exe` bundled with Julia on
# windows, so we create generator functions to spit back functors to invoke
# the correct 7z given the path to the executable:

const exe7z = Ref{String}()

function unpack_7z(tarball_path, out_path)
    pipeline(
        `$(exe7z[]) x $(tarball_path) -y -so`,
        `$(exe7z[]) x -si -y -ttar -o$(out_path)`
    )
end

function package_7z(in_path, tarball_path)
    pipeline(
        `$(exe7z[]) a -ttar -so a.tar "$(joinpath(".",in_path,"*"))"`,
        `$(exe7z[]) a -si $(tarball_path)`
    )
end

function list_7z(path)
    pipeline(`$(exe7z[]) x $path -so`, `$(exe7z[]) l -ttar -y -si`)
end

const tar_cmd = Ref{String}()

function unpack_tar(tarball_path, out_path)
    Jjz = "z"
    if endswith(tarball_path, ".xz")
        Jjz = "J"
    elseif endswith(tarball_path, ".bz2")
        Jjz = "j"
    end
    return `$(tar_cmd[]) -x$(Jjz)f $(tarball_path) --directory=$(out_path)`
end

function package_tar(in_path, tarball_path)
    `$(tar_cmd[]) -czvf $tarball_path -C $(in_path) .`
end

function list_tar(in_path)
    `$(tar_cmd[]) -tzf $in_path`
end



const binary_provider_agent = "BinaryProvider.jl (https://github.com/JuliaPackaging/BinaryProvider.jl)"

function download_curl(url, path)
    `curl -H "User-Agent: $binary_provider_agent" -C - -\# -f -o $path -L $url`
end

function download_wget(url, path)
    `wget --tries=5 -U $binary_provider_agent -c -O $path $url`
end

function download_fetch(url, path)
    `fetch --user-agent=$binary_provider_agent -f $path $url`
end
function download_busybox(url, path)
    `busybox wget -U $binary_provider_agent -c -O $path $url`
end

const powershell_path = Ref{String}()

# For download engines, we will most likely want to use powershell.
# Let's generate a functor to return the necessary powershell magics
# to download a file, given a path to the powershell executable
function download_powershell(url, path)
    webclient_code = """
    [System.Net.ServicePointManager]::SecurityProtocol =
        [System.Net.SecurityProtocolType]::Tls12;
    \$webclient = (New-Object System.Net.Webclient);
    \$webclient.Headers.Add("user-agent", "$binary_provider_agent");
    \$webclient.DownloadFile("$url", "$path")
    """
    replace(webclient_code, "\n" => " ")
    return `$(powershell_path[]) -NoProfile -Command "$webclient_code"`
end

"""
    probe_platform_engines!(;verbose::Bool = false)

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
    # First things first, determine whether tempdir() can have symlinks created
    # within it.  This is important for our copyderef workaround for e.g. SMBFS
    tempdir_symlink_creation[] = probe_symlink_creation(tempdir())
    if verbose
        @info("Symlinks allowed in $(tempdir()): $(tempdir_symlink_creation[])")
    end

    # download_engines is a list of (test_cmd, download_opts_functor)
    # The probulator will check each of them by attempting to run `$test_cmd`,
    # and if that works, will set the global download functions appropriately.
    download_engines = [
        (Ref{String}() => ["curl"], ["--help"], download_curl),
        (Ref{String}() => ["wget"], ["--help"], download_wget),
        (Ref{String}() => ["fetch"], ["--help"], download_fetch),
        (Ref{String}() => ["busybox"], ["wget", "--help"], download_busybox),
    ]

    # compression_engines is a list of (test_cmd, unpack_opts_functor,
    # package_opts_functor, list_opts_functor, parse_functor).  The probulator
    # will check each of them by attempting to run `$test_cmd`, and if that
    # works, will set the global compression functions appropriately.
    compression_engines = Tuple[]

    # sh_engines is just a list of Cmds-as-paths
    sh_engines = [
        `sh`,
    ]

    exe7zips = String[]
    # Tar is rather less verbose, and we don't need to search multiple places
    # for it, so just rely on PATH to have `tar` available for us:
    # Some tar's aren't smart enough to auto-guess decompression method. :(
    push!(compression_engines, (
        tar_cmd => ["tar", "busybox tar"],
        ["--help"],
        unpack_tar,
        package_tar,
        list_tar,
        parse_tar_list,
    ))

    # For windows, we need to tweak a few things, as the tools available differ
    @static if Sys.iswindows()

        # We want to search both the `PATH`, and the direct path for powershell
        psh_paths = [
            joinpath(get(ENV, "SYSTEMROOT", "C:\\Windows"), "System32\\WindowsPowerShell\\v1.0\\powershell.exe"),
            "powershell"
        ]
        prepend!(download_engines, [
            (powershell_path => psh_paths, ["-Command", ""], download_powershell)
        ])

        # We greatly prefer `7z` as a compression engine on Windows
        push!(exe7zips, "7z")
        # On windows, we bundle 7z with Julia, so try invoking that directly
        push!(exe7zips, joinpath(Sys.BINDIR, "7z.exe"))
        # And finally, we want to look for sh as busybox as well:
        busybox = joinpath(Sys.BINDIR, "busybox.exe")
        prepend!(sh_engines, [(`$busybox sh`)])
    end

    # Allow environment override
    if haskey(ENV, "BINARYPROVIDER_DOWNLOAD_ENGINE")
        engine = ENV["BINARYPROVIDER_DOWNLOAD_ENGINE"]
        es = split(engine)
        dl_ngs = filter(e -> e[1].exec[1:length(es)] == es, download_engines)
        if isempty(dl_ngs)
            all_ngs = join([d[1].exec[1] for d in download_engines], ", ")
            warn_msg  = "Ignoring BINARYPROVIDER_DOWNLOAD_ENGINE as its value "
            warn_msg *= "of `$(engine)` doesn't match any known valid engines."
            warn_msg *= " Try one of `$(all_ngs)`."
            @warn(warn_msg)
        else
            # If BINARYPROVIDER_DOWNLOAD_ENGINE matches one of our download engines,
            # then restrict ourselves to looking only at that engine
            download_engines = dl_ngs
        end
    end

    if haskey(ENV, "BINARYPROVIDER_COMPRESSION_ENGINE")
        engine = ENV["BINARYPROVIDER_COMPRESSION_ENGINE"]
        es = split(engine)
        comp_ngs = filter(e -> e[1].exec[1:length(es)] == es, compression_engines)
        if isempty(comp_ngs)
            all_ngs = join([c[1].exec[1] for c in compression_engines], ", ")
            warn_msg  = "Ignoring BINARYPROVIDER_COMPRESSION_ENGINE as its "
            warn_msg *= "value of `$(engine)` doesn't match any known valid "
            warn_msg *= "engines. Try one of `$(all_ngs)`."
            @warn(warn_msg)
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
        @info("Probing for download engine...")
    end

    # Search for a download engine
    for ((ref, exes), args, dl_func) in download_engines
        for exe in exes
            ref[] = exe # update exe ref
            if probe_cmd(`$exe $args`; verbose=verbose)
                # Set our download command generator
                download_command_func[] = dl_func
                download_found = true

                if verbose
                    @info("Found download engine $(exe)")
                end
                break
            end
        end
    end

    if verbose
        @info("Probing for compression engine...")
    end
    push!(compression_engines, (
        exe7z => exe7zips,
        ["--help"],
        unpack_7z,
        package_7z,
        list_7z,
        parse_7z_list,
    ))
    # Search for a compression engine
    for ((ref, exes), arg, unpack, package, list, parse) in compression_engines
        for exe in exes
            # update the exe
            ref[] = exe
            if probe_cmd(`$exe $arg`; verbose=verbose)
                # Set our compression command generators
                gen_unpack_cmd_func[] = unpack
                gen_package_cmd_func[] = package
                gen_list_tarball_cmd_func[] = list
                parse_tarball_listing_func[] = parse

                if verbose
                    @info("Found compression engine $exe")
                end

                compression_found = true
                break
            end
        end
    end

    if verbose
        @info("Probing for sh engine...")
    end

    for path in sh_engines
        if probe_cmd(`$path --help`; verbose=verbose)
            gen_sh_cmd_func[] = (cmd) -> `$path -c $cmd`
            if verbose
                @info("Found sh engine $(path.exec[1])")
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

    if !sh_found && verbose
        @warn("No sh engines found.  Test suite will fail.")
    end

    # Error out if we couldn't find something
    if !download_found || !compression_found
        error(errmsg)
    end
end

"""
    parse_7z_list(output::AbstractString)

Given the output of `7z l`, parse out the listed filenames.  This funciton used
by  `list_tarball_files`.
"""
function parse_7z_list(output::AbstractString)
    lines = [chomp(l) for l in split(output, "\n")]

    # If we didn't get anything, complain immediately
    if isempty(lines)
        return []
    end

    # Remove extraneous "\r" for windows platforms
    for idx in 1:length(lines)
        if endswith(lines[idx], '\r')
            lines[idx] = lines[idx][1:end-1]
        end
    end

    # Find index of " Name".  Have to `collect()` as `findfirst()` doesn't work with
    # generators: https://github.com/JuliaLang/julia/issues/16884
    header_row = findfirst(collect(occursin(" Name", l) && occursin(" Attr", l) for l in lines))
    name_idx = findfirst("Name", lines[header_row])[1]
    attr_idx = findfirst("Attr", lines[header_row])[1] - 1

    # Filter out only the names of files, ignoring directories
    lines = [l[name_idx:end] for l in lines if length(l) > name_idx && l[attr_idx] != 'D']
    if isempty(lines)
        return []
    end

    # Extract within the bounding lines of ------------
    bounds = [i for i in 1:length(lines) if all([c for c in lines[i]] .== Ref('-'))]
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
    parse_tar_list(output::AbstractString)

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
        @info("Downloading $(url) to $(dest)...")
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
        error("Could not download $(url) to $(dest):\n$(e)")
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
if `force` is not set and the already-existent file fails verification, or if
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
                @info("Continued download didn't work, restarting from scratch")
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
    package(src_dir::AbstractString, tarball_path::AbstractString;
            verbose::Bool = false)

Compress `src_dir` into a tarball located at `tarball_path`.
"""
function package(src_dir::AbstractString, tarball_path::AbstractString;
                  verbose::Bool = false)
    # For now, use environment variables to set the gzip compression factor to
    # level 9, eventually there will be new enough versions of tar everywhere
    # to use -I 'gzip -9', or even to switch over to .xz files.
    withenv("GZIP" => "-9") do
        oc = OutputCollector(gen_package_cmd(src_dir, tarball_path); verbose=verbose)
        try
            if !wait(oc)
                error()
            end
        catch e
            if isa(e, InterruptException)
                rethrow()
            end
            error("Could not package $(src_dir) into $(tarball_path)")
        end
    end
end

"""
    unpack(tarball_path::AbstractString, dest::AbstractString;
           verbose::Bool = false)

Unpack tarball located at file `tarball_path` into directory `dest`.
"""
function unpack(tarball_path::AbstractString, dest::AbstractString;
                verbose::Bool = false)
    # The user can force usage of our dereferencing workaround for filesystems
    # that don't support symlinks, but it is also autodetected.
    copyderef = get(ENV, "BINARYPROVIDER_COPYDEREF", "") == "true" ||
                (tempdir_symlink_creation[] && !probe_symlink_creation(dest))

    # If we should "copyderef" what we do is to unpack into a temporary directory,
    # then copy without preserving symlinks into the destination directory.  This
    # is to work around filesystems that are mounted (such as SMBFS filesystems)
    # that do not support symlinks.  Note that this does not work if you are on
    # a system that completely disallows symlinks (Even within temporary
    # directories) such as Windows XP/7.
    true_dest = dest
    if copyderef
        dest = mktempdir()
    end

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

    if copyderef
        # We would like to use `cptree(; follow_symlinks=false)` here, but it
        # freaks out if there are any broken symlinks, which is too finnicky
        # for our use cases.  For us, we will just print a warning and continue.
        function cptry_harder(src, dst)
            mkpath(dst)
            for name in readdir(src)
                srcname = joinpath(src, name)
                dstname = joinpath(dst, name)
                if isdir(srcname)
                    cptry_harder(srcname, dstname)
                else
                    try
                        Base.Filesystem.sendfile(srcname, dstname)
                    catch e
                        if isa(e, Base.IOError)
                            if verbose
                                @warn("Could not copy $(srcname) to $(dstname)")
                            end
                        else
                            rethrow(e)
                        end
                    end
                end
            end
        end
        cptry_harder(dest, true_dest)
        rm(dest; recursive=true, force=true)
    end
end


"""
    download_verify_unpack(url::AbstractString, hash::AbstractString,
                           dest::AbstractString; tarball_path = nothing,
                           verbose::Bool = false, ignore_existence::Bool = false,
                           force::Bool = false)

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

If `ignore_existence` is set, the tarball is unpacked even if the destination
directory already exists.

Returns `true` if a tarball was actually unpacked, `false` if nothing was
changed in the destination prefix.
"""
function download_verify_unpack(url::AbstractString,
                                hash::AbstractString,
                                dest::AbstractString;
                                tarball_path = nothing,
                                ignore_existence::Bool = false,
                                force::Bool = false,
                                verbose::Bool = false)
    # First, determine whether we should keep this tarball around
    remove_tarball = false
    if tarball_path === nothing
        remove_tarball = true

        function url_ext(url)
            url = basename(url)

            # Chop off urlparams
            qidx = findfirst(isequal('?'), url)
            if qidx !== nothing
                url = url[1:qidx]
            end

            # Try to detect extension
            dot_idx = findlast(isequal('.'), url)
            if dot_idx === nothing
                return nothing
            end

            return url[dot_idx+1:end]
        end

        # If extension of url contains a recognized extension, use it, otherwise use ".gz"
        ext = url_ext(url)
        if !(ext in ["tar", "gz", "tgz", "bz2", "xz"])
            ext = "gz"
        end

        tarball_path = "$(tempname())-download.$(ext)"
    end

    # Download the tarball; if it already existed and we needed to remove it
    # then we should remove the unpacked path as well
    should_delete = !download_verify(url, hash, tarball_path;
                                     force=force, verbose=verbose)
    if should_delete
        if verbose
            @info("Removing dest directory $(dest) as source tarball changed")
        end
        rm(dest; recursive=true, force=true)
    end

    # If the destination path already exists, don't bother to unpack
    if !ignore_existence && isdir(dest)
        if verbose
            @info("Destination directory $(dest) already exists, returning")
        end

        # Signify that we didn't do any unpacking
        return false
    end

    try
        if verbose
            @info("Unpacking $(tarball_path) into $(dest)...")
        end
        unpack(tarball_path, dest; verbose=verbose)
    finally
        if remove_tarball
            rm(tarball_path)
        end
    end

    # Signify that we did some unpacking!
    return true
end
