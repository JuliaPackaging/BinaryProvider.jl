__precompile__()
module BinaryProvider
export Prefix, activate, install, remove, download, unpack,
       probe_download_engine, prune, verify, list_archive_files,
       @BP_provides

include("Prefix.jl")
# Utilities for downloading and unpacking remote resources
include("download.jl")
# The definition of our `install()` and `remove()` functions.
include("API.jl")

# Include BinDeps support
include("bindeps_integration.jl")

function __init__()
    # Find the right download engine for this platform
    global download, global_prefix
    download = probe_download_engine()

    # Initialize our global_prefix
    global_prefix = Prefix(joinpath(dirname(@__FILE__), "../", "global_prefix"))
    activate(global_prefix)
end

end # module
