export supported_platforms, platform_triplet, platform_key

const platform_to_triplet_mapping = Dict(
    :linux64 => "x86_64-linux-gnu",
    :linuxaarch64 => "aarch64-linux-gnu",
    :linuxarmv7l => "arm-linux-gnueabihf",
    :linuxppc64le => "powerpc64le-linux-gnu",
    :mac64 => "x86_64-apple-darwin14",
    :win64 => "x86_64-w64-mingw32",
)

function supported_platforms()
    global platform_to_triplet_mapping
    return keys(platform_to_triplet_mapping)
end

function platform_triplet(platform::Symbol)
    global platform_to_triplet_mapping
    return platform_to_triplet_mapping[platform]
end

"""
`platform_key(machine::AbstractString = Sys.MACHINE)`

Returns the platform key for the current platform, or any other though
the use of the `machine` parameter.
"""
function platform_key(machine = Sys.MACHINE)
    global platform_to_triplet_mapping

    # First, off, if `machine` is literally one of the values of our mapping
    # above, just return the relevant key
    for key in supported_platforms()
        if machine == platform_triplet(key)
            return key
        end
    end
    
    # Otherwise, try to parse the machine into one of our keys
    if startswith(machine, "x86_64-apple-darwin")
        return :mac64
    end
    if ismatch(r"x86_64-(pc-)?(unknown-)?linux-gnu", machine)
        return :linux64
    end

    error("Platform `$(machine)` is not an officially supported platform")
end