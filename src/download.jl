# In this file, we define the machinery for setting up the `download()` function
# (we evaluate a few different download engines such as `curl`, `powershell`,
# etc...) as well as the `unpack()` function.
using SHA

"""
`download(url, filename)`

Download resource located at `url` and store it within the file located at
`filename`.  This method is initialized by `probe_download_engine()`, which
should be automatically called upon first import of `BinaryProvider`.
"""
download = (url, filename; verbose=false) -> begin
    error("Must `probe_download_engine()` before calling `download()`")
end

"""
`probe_cmd(cmd::Cmd)`

Returns `true` if the given command executes successfully, `false` otherwise.
"""
function probe_cmd(cmd::Cmd)
    try
        return success(cmd)
    catch
        return false
    end
end

"""
`probe_download_engine(;verbose::Bool = false)`

Searches for a download engine to be used by `download()`, returning an
anonymous function that can be used to replace `download()`, which takes in two
parameters; the `url` to download and the `filename` to store it at.

This probing function will automatically search for download engines using a
particular ordering; if you wish to override this ordering and use one over all
others, set the `JULIA_DOWNLOAD_ENGINE` environment variable to its name, and it
will be the only engine searched for. For example, put:

    ENV["JULIA_DOWNLOAD_ENGINE"] = "fetch"

within your `~/.juliarc.jl` file to force `fetch` to be used over `curl`.  If
the given override does not match any of the download engines known to this
function, a warning will be printed and the typical ordering will be used.

If `verbose` is `true`, print out the download engines as they are searched.
"""
function probe_download_engine(;verbose::Bool = false)
    # download_engines is a list of (path, test_opts, download_opts_functor)
    # The probulator will check each of them by attempting to run
    # `$path $test_opts`, and if that works, will return a download()
    # function that runs `$name $(download_opts_functor(filename, url))`
    download_engines = [
        ("curl",  `--help`, (url, path) -> `-f -o $path -L $url`),
        ("wget",  `--help`, (url, path) -> `-O $path $url`),
        ("fetch", `--help`, (url, path) -> `-f $path $url`),
    ]

    # For windows, let's check real quick to see if we've got powershell
    @static if is_windows()
        # We hardcode in the path to powershell here, just in case it's not on
        # the path, but is still installed
        psh_path = "C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell"
        psh_copts = `-NoProfile -Command`
        psh_download = (url, path) -> begin
            webclient = "(new-object net.webclient)"
            return `$psh_copts "$webclient.DownloadFile(\"$url\", \"$path\")"`
        end

        # Push these guys onto the top of our download_engines search list
        prepend!(download_engines, [
            (psh_path,     `$psh_copts ""`, psh_download)
        ])
        prepend!(download_engines, [
            ("powershell", `$psh_copts ""`, psh_download)
        ])
    end

    # Allow environment override
    if haskey(ENV, "JULIA_DOWNLOAD_ENGINE")
        engine = ENV["JULIA_DOWNLOAD_ENGINE"]
        dl_ngs = filter(e -> e[1] == engine, download_engines)
        if isempty(dl_ngs)
            warn_msg = "Ignoring JULIA_DOWNLOAD_ENGINE value of \"$engine\" as "
            warn_msg *= "it does not match any known download engine"
            warn(warn_msg)
        else
            # If JULIA_DOWNLOAD_ENGINE matches one of our download engines, then
            # restrict ourselves to looking only at that engine
            download_engines = dl_ngs
        end
    end

    for (path, test_opts, dl_func) in download_engines
        if verbose
            info("Probing $path...")
        end
        if probe_cmd(`$path $test_opts`)
            if verbose
                info("  Probe Successful for $path")
            end
            # Return a function that actually runs our download engine
            return (url, filename; verbose = false) -> begin
                if verbose
                    info("$(basename(path)): downloading $url to $filename")
                end
                success(`$path $(dl_func(url, filename))`)
            end
        end
    end

    # If nothing worked, error out
    errmsg  = "No download agents found. We looked for:"
    errmsg *= join([d[1] for d in download_engines], ", ")
    errmsg *= ". Install one and ensure it is available on the path."
    error(errmsg)
end


"""
`verify(path::String, hash::String; verbose::Bool)`

Given a file `path` and a `hash`, calculate the SHA256 of the file and compare
it to `hash`, returning the comparison result.
"""
function verify(path::AbstractString, hash::AbstractString; verbose::Bool = false)
    if length(hash) != 64
        error("Hash must be 256 bits (64 characters) long, given hash is $(length(hash)) characters long")
    end
    return open(path) do file
        calc_hash = bytes2hex(sha256(file))
        if verbose
            info("Calculated hash $calc_hash for file $path")
        end

        if calc_hash != hash
            if verbose
                warn("Expected sha256:   $hash")
                warn("Calculated sha256: $calc_hash")
            end
            return false
        end
        return true
    end
end

"""
`get_tar_ext(path::String)`

Return the extension of the given path, including the `.tar` or `.7z` prefixes,
so that `unpack_cmd()` can correctly identify compressed archive formats.
"""
function get_tar_ext(path::AbstractString)
    # Grab the extension, unless there's a ".tar" or ".7z" before the extension
    # in which case grab that as well, so we get things like ".Z" and ".tar.gz"
    # equally reliably from this, returning "" if no extension can be found
    m = match(r".*?((\.tar|\.7z)?\.([^\.]+))$", basename(path))
    if m == nothing
        return ""
    end
    return m.captures[1]
end

"""
`unpack(file_path::String, dir::String)`

Unpack a compressed archive located at `file_path` into the directory given by
`directory`, using external utilities such as `tar` or `7z`.  Returns the `Cmd`
to be run to perform the actual unpacking.
"""
function unpack(file::AbstractString, dir::AbstractString;
                verbose::Bool = false)
    ext = get_tar_ext(file)
    if verbose
        info("Unpacking $file, autodetected extension as $ext")
    end

    @static if is_unix()
        if ext in [".tar.gz", ".tar.Z", ".tgz"]
            return success(`tar xzf $file --directory=$dir`)
        elseif ext in [".tar.bz2", ".tbz"]
            return success(`tar xjf $file --directory=$dir`)
        elseif ext in [".tar.xz"]
            return success(pipeline(`unxz -c $file `,`tar xv --directory=$dir`))
        elseif ext in [".tar"]
            return success(`tar xf $file --directory=$dir`)
        elseif ext in [".zip"]
            @static if is_bsd() && !is_apple()
                return success(`unzip -x $file -d $dir $file`)
            else
                return success(`unzip -x $file -d $dir`)
            end
        elseif ext in [".gz"]
            return success(pipeline(`mkdir $dir`, `cp $file $dir`,
                                    `gzip -d $dir/$file`))
        end
    end

    # this relies on 7zip being installed, which currently is bundled with Julia
    @static if is_windows()
        if ext in [".tar.Z", ".tar.gz", ".tar.xz", ".tar.bz2", ".tgz", ".tbz"]
            return success(pipeline(`7z x $file -y -so`,
                                    `7z x -si -y -ttar -o$dir`))
        elseif ext in [".zip", ".7z", ".tar", ".7z.exe"]
            return success(`7z x $file -y -o$dir`)
        end
    end

    error("I don't know how to unpack $file")
end

function unpack(file::AbstractString, prefix::Prefix; verbose::Bool = false)
    return unpack(file, prefix.path; verbose=verbose)
end

# Parse the output of `7z l $file`
function parse_7z_list(output::AbstractString)
    lines = split(output, "\n")
    # Remove extraneous "\r" for windows platforms
    for idx in 1:length(lines)
        if lines[idx][end] == '\r'
            lines[idx] = lines[idx][1:end-1]
        end
    end
    lines = [l[54:end] for l in lines if length(l) > 54]
    bounds = find(lines .== "------------------------")
    return lines[bounds[1]+1:bounds[2]-1]
end

function list_archive_files(file::AbstractString; verbose::Bool=false)
    ext = get_tar_ext(file)
    if verbose
        info("Listing files within $file, autodetected extension as $ext")
    end

    @static if is_unix()
        if ext in [".tar.gz", ".tar.Z", ".tgz"]
            return split(readchomp(`tar tzf $file`), "\n")
        elseif ext in [".tar.bz2", ".tbz"]
            return split(readchomp(`tar tjf $file`), "\n")
        elseif ext in [".tar.xz"]
            return split(readchomp(pipeline(`unxz -c $file `,`tar tv`)), "\n")
        elseif ext in [".tar"]
            return split(readchomp(`tar tf $file`), "\n")
        elseif ext in [".zip"]
            return split(readchomp(`unzip -Z1 $file`), "\n")
        elseif ext in [".gz"]
            return [file[1:end-length(ext)]]
        end
    end

    # this relies on 7zip being installed, which currently is bundled with Julia
    @static if is_windows()
        if ext in [".tar.Z", ".tar.gz", ".tar.xz", ".tar.bz2", ".tgz", ".tbz"]
            output = readchomp(pipeline(`7z x $file -so`, `7z l -ttar -y -si`))
            return parse_7z_list(output)
        elseif ext in [".zip", ".7z", ".tar", ".7z.exe"]
            return parse_7z_list(readchomp(`7z l $file -y -so`))
        end
    end

    error("I don't know how to unpack $file")
end
