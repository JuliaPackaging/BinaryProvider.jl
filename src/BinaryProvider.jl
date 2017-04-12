__precompile__()
module BinaryProvider
export Prefix, activate, install, remove, download, unpack,
       probe_download_engine, prune, verify, list_archive_files

include("Prefix.jl")
# Utilities for downloading and unpacking remote resources
include("download.jl")
include("API.jl")

function __init__()
    # Find the right download engine for this platform
    global download, global_prefix
    download = probe_download_engine()

    # Initialize our global_prefix
    global_prefix = Prefix(joinpath(dirname(@__FILE__), "../", "global_prefix"))
    activate(global_prefix)
end

end # module
