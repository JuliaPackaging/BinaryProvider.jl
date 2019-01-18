## This file contains functionality related to the actual layout of the files
#  on disk.  Things like the name of where downloads are stored, and what
#  environment variables must be updated to, etc...
import Base: convert, joinpath, show, withenv
using SHA

export Prefix, bindir, libdir, includedir, logdir, activate, deactivate,
       extract_name_version_platform_key, extract_platform_key, isinstalled,
       install, uninstall, manifest_from_url, manifest_for_file,
       list_tarball_files, verify, temp_prefix, package


# Temporary hack around https://github.com/JuliaLang/julia/issues/26685
function safe_isfile(path)
    try
        return isfile(path)
    catch e
        if typeof(e) <: Base.IOError && e.code == Base.UV_EINVAL
            return false
        end
        rethrow(e)
    end
end

"""
    temp_prefix(func::Function)

Create a temporary prefix, passing the prefix into the user-defined function so
that build/packaging operations can occur within the temporary prefix, which is
then cleaned up after all operations are finished.  If the path provided exists
already, it will be deleted.

Usage example:

    out_path = abspath("./libfoo")
    temp_prefix() do p
        # <insert build steps here>

        # tarball up the built package
        tarball_path, tarball_hash = package(p, out_path)
    end
"""
function temp_prefix(func::Function)
    # Helper function to create a docker-mountable temporary directory
    function _tempdir()
        @static if Sys.isapple()
            # Docker, on OSX at least, can only mount from certain locations by
            # default, so we ensure all our temporary directories live within
            # those locations so that they are accessible by Docker.
            return "/tmp"
        else
            return tempdir()
        end
    end

    mktempdir(_tempdir()) do path
        prefix = Prefix(path)

        # Run the user function
        func(prefix)
    end
end

# This is the default prefix that things get saved to, it is initialized within
# __init__() on first module load.
global_prefix = nothing
struct Prefix
    path::String

    """
        Prefix(path::AbstractString)

    A `Prefix` represents a binary installation location.  There is a default
    global `Prefix` (available at `BinaryProvider.global_prefix`) that packages
    are installed into by default, however custom prefixes can be created
    trivially by simply constructing a `Prefix` with a given `path` to install
    binaries into, likely including folders such as `bin`, `lib`, etc...
    """
    function Prefix(path::AbstractString)
        # Canonicalize immediately, create the overall prefix, then return
        path = abspath(path)
        mkpath(path)
        return new(path)
    end
end

# Make it easy to bandy about prefixes as paths.  There has got to be a better
# way to do this, but it's hackin' time, so just go with the flow.
joinpath(prefix::Prefix, args...) = joinpath(prefix.path, args...)
joinpath(s::AbstractString, prefix::Prefix, args...) = joinpath(s, prefix.path, args...)

convert(::Type{AbstractString}, prefix::Prefix) = prefix.path
show(io::IO, prefix::Prefix) = show(io, "Prefix($(prefix.path))")


"""
    withenv(f::Function, prefixes::Vector{Prefix}; julia_libdir::Bool = true)

Wrapper function designed to help executables find dynamic libraries and child
binaries by wrapping PATH and `(DY)LD_(FALLBACK_)LIBRARY_PATH`.  If
`julia_libdir` is true, then the private library directory of this Julia
distribution will be added on to the end of the LD_LIBRARY_PATH settings.
"""
function withenv(f::Function, prefixes::Vector{Prefix};
                 julia_libdir::Bool = true)
    # Join `dirs` to ENV[key], removing duplicates and nonexistent directories
    # as we go, normalizing directory names, splitting and joining by `sep`.
    function joinenv(key, dirs, sep, tail_dirs = [])
        value = [dirs..., split(get(ENV, key, ""), sep)..., tail_dirs...]
        return join(unique([abspath(d) for d in value if isdir(d)]), sep)
    end
    # We're going to build up PATH and {DY,}LD_LIBRARY_PATH such that binaries
    # that use things from the given prefixes can function properly.
    sep = Sys.iswindows() ? ";" : ":"
    mapping = ["PATH" => joinenv("PATH", bindir.(prefixes), sep)]

    # {DY,}LD_LIBRARY_PATH only makes sense on non-windows
    if !Sys.iswindows()
        libdirs = libdir.(prefixes)
        tail_dirs = []
        if julia_libdir
            tail_dirs = [joinpath(Sys.BINDIR, Base.PRIVATE_LIBDIR)]
        end

        envname = Sys.isapple() ? "DYLD_FALLBACK_LIBRARY_PATH" : "LD_LIBRARY_PATH"
        push!(mapping, envname => joinenv(envname, libdirs, ":", tail_dirs))
    end

    # Use withenv to apply the calculated environment mappings to f.
    return withenv(f, mapping...)
end
withenv(f::Function, prefix::Prefix) = withenv(f, [prefix])

"""
    bindir(prefix::Prefix)

Returns the binary directory for the given `prefix`.
"""
function bindir(prefix::Prefix)
    return joinpath(prefix, "bin")
end

"""
    libdir(prefix::Prefix, platform = platform_key_abi())

Returns the library directory for the given `prefix` (note that this differs
between unix systems and windows systems).
"""
function libdir(prefix::Prefix, platform = platform_key_abi())
    if Sys.iswindows(platform)
        return joinpath(prefix, "bin")
    else
        return joinpath(prefix, "lib")
    end
end

"""
    includedir(prefix::Prefix)

Returns the include directory for the given `prefix`
"""
function includedir(prefix::Prefix)
    return joinpath(prefix, "include")
end

"""
    logdir(prefix::Prefix)

Returns the logs directory for the given `prefix`.
"""
function logdir(prefix::Prefix)
    return joinpath(prefix, "logs")
end

"""
    extract_platform_key(path::AbstractString)

Given the path to a tarball, return the platform key of that tarball. If none
can be found, prints a warning and return the current platform suffix.
"""
function extract_platform_key(path::AbstractString)
    try
        return extract_name_version_platform_key(path)[3]
    catch
        @warn("Could not extract the platform key of $(path); continuing...")
        return platform_key_abi()
    end
end

"""
    extract_name_version_platform_key(path::AbstractString)

Given the path to a tarball, return the name, platform key and version of that
tarball. If any of those things cannot be found, throw an error.
"""
function extract_name_version_platform_key(path::AbstractString)
    m = match(r"^(.*?)\.v(.*?)\.([^\.\-]+-[^\.\-]+-([^\-]+-){0,2}[^\-]+).tar.gz$", basename(path))
    if m === nothing
        error("Could not parse name, platform key and version from $(path)")
    end
    name = m.captures[1]
    version = VersionNumber(m.captures[2])
    platkey = platform_key_abi(m.captures[3])
    return name, version, platkey
end

"""
    isinstalled(tarball_url::AbstractString,
                hash::AbstractString;
                prefix::Prefix = global_prefix)

Given a `prefix`, a `tarball_url` and a `hash`, check whether the
tarball with that hash has been installed into `prefix`.

In particular, it checks for the tarball, matching hash file, and manifest
installed by `install`, and checks that the files listed in the manifest
are installed and are not older than the tarball.
"""
function isinstalled(tarball_url::AbstractString, hash::AbstractString;
                     prefix::Prefix = global_prefix)
    # check that the hash file and tarball exist and match hash
    tarball_path = joinpath(prefix, "downloads", basename(tarball_url))
    hash_path = "$(tarball_path).sha256"
    if safe_isfile(tarball_url)
        tarball_path = tarball_url
    end
    try
        verify(tarball_path, hash; verbose=false, hash_path=hash_path)
    catch
        return false
    end
    tarball_time = stat(tarball_path).mtime

    # check that manifest and the files listed within it exist
    # and are at least as new as the tarball.
    manifest_path = manifest_from_url(tarball_url, prefix=prefix)
    isfile(manifest_path) || return false
    stat(manifest_path).mtime >= tarball_time || return false
    for installed_file in (joinpath(prefix, f) for f in chomp.(readlines(manifest_path)))
        ((isfile(installed_file) || islink(installed_file)) &&
         stat(installed_file).ctime >= tarball_time) || return false
    end

    return true
end

"""
    install(tarball_url::AbstractString,
            hash::AbstractString;
            prefix::Prefix = global_prefix,
            force::Bool = false,
            ignore_platform::Bool = false,
            verbose::Bool = false)

Given a `prefix`, a `tarball_url` and a `hash`, download that tarball into the
prefix, verify its integrity with the `hash`, and install it into the `prefix`.
Also save a manifest of the files into the prefix for uninstallation later.

This will not overwrite any files within `prefix` unless `force=true` is set.
If `force=true` is set, installation will overwrite files as needed, and it
will also delete any files previously installed for `tarball_url`
as listed in a pre-existing manifest (if any).

By default, this will not install a tarball that does not match the platform of
the current host system, this can be overridden by setting `ignore_platform`.
"""
function install(tarball_url::AbstractString,
                 hash::AbstractString;
                 prefix::Prefix = global_prefix,
                 tarball_path::AbstractString =
                     joinpath(prefix, "downloads", basename(tarball_url)),
                 force::Bool = false,
                 ignore_platform::Bool = false,
                 verbose::Bool = false)
    # If we're not ignoring the platform, get the platform key from the tarball
    # and complain if it doesn't match the platform we're currently running on
    if !ignore_platform
        try
            platform = extract_platform_key(tarball_url)

            # Check if we had a well-formed platform that just doesn't match
            if !platforms_match(platform, platform_key_abi())
                msg = replace(strip("""
                Will not install a tarball of platform $(triplet(platform)) on
                a system of platform $(triplet(platform_key_abi())) unless
                `ignore_platform` is explicitly set to `true`.
                """), "\n" => " ")
                throw(ArgumentError(msg))
            end
        catch e
            # Check if we had a malformed platform
            if isa(e, ArgumentError)
                msg = "$(e.msg), override this by setting `ignore_platform`"
                throw(ArgumentError(msg))
            else
                # Something else went wrong, pass it along
                rethrow(e)
            end
        end
    end

    # Create the downloads directory if it does not already exist
    try mkpath(dirname(tarball_path)) catch; end

    # Check to see if we're "installing" from a file
    if safe_isfile(tarball_url)
        # If we are, just verify it's already downloaded properly
        hash_path = "$(tarball_path).sha256"
        tarball_path = tarball_url

        verify(tarball_path, hash; verbose=verbose, hash_path=hash_path)
    else
        # If not, actually download it
        download_verify(tarball_url, hash, tarball_path;
                        force=force, verbose=verbose)
    end

    if verbose
        @info("Installing $(tarball_path) into $(prefix.path)")
    end

    # remove old files if force=true
    manifest_path = manifest_from_url(tarball_url, prefix=prefix)
    force && isfile(manifest_path) && uninstall(manifest_path, verbose=verbose)

    # First, get list of files that are contained within the tarball
    file_list = list_tarball_files(tarball_path)

    # Check to see if any files are already present
    for file in file_list
        if safe_isfile(joinpath(prefix, file))
            if !force
                msg  = "$(file) already exists and would be overwritten while "
                msg *= "installing $(basename(tarball_path))\n"
                msg *= "Will not overwrite unless `force = true` is set."
                error(msg)
            else
                if verbose
                    @info("$(file) already exists, force-removing")
                end
                rm(file; force=true)
            end
        end
    end

    # Unpack the tarball into prefix
    unpack(tarball_path, prefix.path; verbose=verbose)

    # Save installation manifest
    mkpath(dirname(manifest_path))
    open(manifest_path, "w") do f
        write(f, join(file_list, "\n"))
    end

    return true
end

"""
    uninstall(manifest::AbstractString; verbose::Bool = false)

Uninstall a package from a prefix by providing the `manifest_path` that was
generated during `install()`.  To find the `manifest_file` for a particular
installed file, use `manifest_for_file(file_path; prefix=prefix)`.
"""
function uninstall(manifest::AbstractString;
                   verbose::Bool = false)
    # Complain if this manifest file doesn't exist
    if !isfile(manifest)
        error("Manifest path $(manifest) does not exist")
    end

    prefix_path = dirname(dirname(manifest))
    if verbose
        relmanipath = relpath(manifest, prefix_path)
        @info("Removing files installed by $(relmanipath)")
    end

    # Remove every file listed within the manifest file
    for path in [chomp(l) for l in readlines(manifest)]
        delpath = joinpath(prefix_path, path)
        if !isfile(delpath) && !islink(delpath)
            if verbose
                @info("  $delpath does not exist, but ignoring")
            end
        else
            if verbose
                delrelpath = relpath(delpath, prefix_path)
                @info("  $delrelpath removed")
            end
            rm(delpath; force=true)

            # Last one out, turn off the lights (cull empty directories,
            # but only if they're not our prefix)
            deldir = abspath(dirname(delpath))
            if isempty(readdir(deldir)) && deldir != abspath(prefix_path)
                if verbose
                    delrelpath = relpath(deldir, prefix_path)
                    @info("  Culling empty directory $delrelpath")
                end
                rm(deldir; force=true, recursive=true)
            end
        end
    end

    if verbose
        @info("  $(relmanipath) removed")
    end
    rm(manifest; force=true)
    return true
end

"""
    manifest_from_url(url::AbstractString; prefix::Prefix = global_prefix())

Returns the file path of the manifest file for the tarball located at `url`.
"""
function manifest_from_url(url::AbstractString;
                           prefix::Prefix = global_prefix())
    # Given an URL, return an autogenerated manifest name
    return joinpath(prefix, "manifests", basename(url)[1:end-7] * ".list")
end

"""
    manifest_for_file(path::AbstractString; prefix::Prefix = global_prefix)

Returns the manifest file containing the installation receipt for the given
`path`, throws an error if it cannot find a matching manifest.
"""
function manifest_for_file(path::AbstractString;
                           prefix::Prefix = global_prefix)
    if !isfile(path)
        error("File $(path) does not exist")
    end

    search_path = relpath(path, prefix.path)
    if startswith(search_path, "..")
        error("Cannot search for paths outside of the given Prefix!")
    end

    manidir = joinpath(prefix, "manifests")
    for fname in [f for f in readdir(manidir) if endswith(f, ".list")]
        manifest_path = joinpath(manidir, fname)
        if search_path in [chomp(l) for l in readlines(manifest_path)]
            return manifest_path
        end
    end

    error("Could not find $(search_path) in any manifest files")
end

"""
    list_tarball_files(path::AbstractString; verbose::Bool = false)

Given a `.tar.gz` filepath, list the compressed contents.
"""
function list_tarball_files(path::AbstractString; verbose::Bool = false)
    if !isfile(path)
        error("Tarball path $(path) does not exist")
    end

    # Run the listing command, then parse the output
    oc = OutputCollector(gen_list_tarball_cmd(path); verbose=verbose)
    try
        if !wait(oc)
            error()
        end
    catch
        error("Could not list contents of tarball $(path)")
    end
    return parse_tarball_listing(collect_stdout(oc))
end

"""
    verify(path::AbstractString, hash::AbstractString;
           verbose::Bool = false, report_cache_status::Bool = false)

Given a file `path` and a `hash`, calculate the SHA256 of the file and compare
it to `hash`.  If an error occurs, `verify()` will throw an error.  This method
caches verification results in a `"\$(path).sha256"` file to accelerate re-
verification of files that have been previously verified.  If no `".sha256"`
file exists, a full verification will be done and the file will be created,
with the calculated hash being stored within the `".sha256"` file..  If a
`".sha256"` file does exist, its contents are checked to ensure that the hash
contained within matches the given `hash` parameter, and its modification time
shows that the file located at `path` has not been modified since the last
verification.

If `report_cache_status` is set to `true`, then the return value will be a
`Symbol` giving a granular status report on the state of the hash cache, in
addition to the `true`/`false` signifying whether verification completed
successfully.
"""
function verify(path::AbstractString, hash::AbstractString; verbose::Bool = false,
                report_cache_status::Bool = false, hash_path::AbstractString="$(path).sha256")
    if length(hash) != 64
        msg  = "Hash must be 256 bits (64 characters) long, "
        msg *= "given hash is $(length(hash)) characters long"
        error(msg)
    end

    # First, check to see if the hash cache is consistent
    status = :hash_consistent

    # First, it must exist
    if isfile(hash_path)
        # Next, it must contain the same hash as what we're verifying against
        if read(hash_path, String) == hash
            # Next, it must be no older than the actual path
            if stat(hash_path).mtime >= stat(path).mtime
                # If all of that is true, then we're good!
                if verbose
                    info_onchange(
                        "Hash cache is consistent, returning true",
                        "verify_$(hash_path)",
                        @__LINE__,
                    )
                end
                status = :hash_cache_consistent

                # If we're reporting our status, then report it!
                if report_cache_status
                    return true, status
                else
                    return true
                end
            else
                if verbose
                    info_onchange(
                        "File has been modified, hash cache invalidated",
                        "verify_$(hash_path)",
                        @__LINE__,
                    )
                end
                status = :file_modified
            end
        else
            if verbose
                info_onchange(
                    "Verification hash mismatch, hash cache invalidated",
                    "verify_$(hash_path)",
                    @__LINE__,
                )
            end
            status = :hash_cache_mismatch
        end
    else
        if verbose
            info_onchange(
                "No hash cache found",
                "verify_$(hash_path)",
                @__LINE__,
            )
        end
        status = :hash_cache_missing
    end

    open(path) do file
        calc_hash = bytes2hex(sha256(file))
        if verbose
            info_onchange(
                "Calculated hash $calc_hash for file $path",
                "hash_$(hash_path)",
                @__LINE__,
            )
        end

        if calc_hash != hash
            msg  = "Hash Mismatch!\n"
            msg *= "  Expected sha256:   $hash\n"
            msg *= "  Calculated sha256: $calc_hash"
            error(msg)
        end
    end

    # Save a hash cache if everything worked out fine
    open(hash_path, "w") do file
        write(file, hash)
    end

    if report_cache_status
        return true, status
    else
        return true
    end
end

"""
    package(prefix::Prefix, output_base::AbstractString,
            version::VersionNumber;
            platform::Platform = platform_key_abi(),
            verbose::Bool = false, force::Bool = false)

Build a tarball of the `prefix`, storing the tarball at `output_base`,
appending a version number, a platform-dependent suffix and a file extension.
If no platform is given, defaults to current platform. Runs an `audit()` on the
`prefix`, to ensure that libraries can be `dlopen()`'ed, that all dependencies
are located within the prefix, etc... See the `audit()` documentation for a
full list of the audit steps.  Returns the full path to and hash of the
generated tarball.
"""
function package(prefix::Prefix,
                 output_base::AbstractString,
                 version::VersionNumber;
                 platform::Platform = platform_key_abi(),
                 verbose::Bool = false,
                 force::Bool = false)
    # Calculate output path
    out_path = "$(output_base).v$(version).$(triplet(platform)).tar.gz"

    if isfile(out_path)
        if force
            if verbose
                @info("$(out_path) already exists, force-overwriting...")
            end
            rm(out_path; force=true)
        else
            msg = replace(strip("""
            $(out_path) already exists, refusing to package into it without
            `force` being set to `true`.
            """), "\n" => " ")
            error(msg)
        end
    end

    # Package `prefix.path` into the tarball contained at `out_path`
    package(prefix.path, out_path; verbose=verbose)

    # Also spit out the hash of the archive file
    hash = open(out_path, "r") do f
        return bytes2hex(sha256(f))
    end
    if verbose
        @info("SHA256 of $(basename(out_path)): $(hash)")
    end

    return out_path, hash
end
