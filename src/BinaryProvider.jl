module BinaryProvider

using Libdl

# Utilities for controlling verbosity
include("LoggingUtils.jl")
# Include our subprocess running functionality
include("OutputCollector.jl")
# External utilities such as downloading/decompressing tarballs
include("PlatformEngines.jl")
# Platform naming
include("PlatformNames.jl")
# Everything related to file/path management
include("Prefix.jl")
# Abstraction of "needing" a file, that would trigger an install
include("Products.jl")

# Compat shims
include("CompatShims.jl")

function __init__()
    # Initialize our global_prefix
    path = joinpath(@__DIR__, "..", "global_prefix")
    global_prefix[] = Prefix(path)
    default_platkey[] = platform_key_abi(string(
        Sys.MACHINE,
        compiler_abi_str(detect_compiler_abi()),
    ))
    # Find the right download/compression engines for this platform
    try
        probe_platform_engines!()
    catch e
        @show e
    end
end

# gotta go fast
include("precompile.jl")
_precompile_()

end # module
