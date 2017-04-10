## This file contains functionality related to the actual layout of the files
#  on disk.  Things like the name of where downloads are stored, and what
#  environment variables must be updated to, etc...
import Base: convert, joinpath, show

# This is the default prefix that things get saved to, it is initialized within
# __init__() on first module load.
global_prefix = nothing
type Prefix
    path::String

    function Prefix(path::AbstractString)
        # Canonicalize immediately
        path = abspath(path)

        # Setup our important locations
        mkpath(joinpath(path, "usr"))
        mkpath(joinpath(path, "archives"))
        mkpath(joinpath(path, "receipts"))

        return new(path)
    end
end

# Make it easy to bandy about prefixes as paths
joinpath(prefix::Prefix, args...) = joinpath(prefix.path, args...)
convert(::Type{AbstractString}, prefix::Prefix) = prefix.path
show(io::IO, prefix::Prefix) = show(io, "Prefix($(prefix.path))")

function split_PATH(PATH::AbstractString = ENV["PATH"])
    @static if is_windows()
        return split(PATH, ";")
    else
        return split(PATH, ":")
    end
end

function join_PATH{S<:AbstractString}(paths::Vector{S})
    @static if is_windows()
        return join(paths, ";")
    else
        return join(paths, ":")
    end
end

"""
`activate(prefix::Prefix)`

Prepends paths to environment variables so that binaries and libraries are
available to Julia.
"""
function activate(prefix::Prefix = global_prefix)
    paths = split_PATH()
    binpath = joinpath(prefix, "usr", "bin")
    @static if is_windows()
        libpath = binpath
    else
        libpath = joinpath(prefix, "usr", "lib")
    end

    # Add to PATH
    if !(binpath in paths)
        prepend!(paths, [binpath])
    end
    ENV["PATH"] = join_PATH(paths)

    # Add to DL_LOAD_PATH
    if !(libpath in Libdl.DL_LOAD_PATH)
        prepend!(Libdl.DL_LOAD_PATH, [libpath])
    end
    return nothing
end

"""
`deactivate(prefix::Prefix)`

Removes paths added to environment variables by `activate()`
"""
function deactivate(prefix::Prefix = global_prefix)
    paths = split_PATH()
    libpath = joinpath(prefix, "usr", "lib")

    # Remove from PATH
    remove!(paths, joinpath(prefix, "usr", "bin"))
    ENV["PATH"] = join_PATH(paths)

    # Remove from DL_LOAD_PATH
    remove!(Libdl.DL_LOAD_PATH, libpath)
    return nothing
end
