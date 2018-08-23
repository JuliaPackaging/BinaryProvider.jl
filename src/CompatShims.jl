# Compatibility shims for old BP versions, when we make a change

for T in [:Linux, :MacOS, :Windows, :FreeBSD]
    @eval $T(arch, libc) = $T(arch; libc=libc)
    @eval $T(arch, libc, call_abi) = $T(arch; libc=libc, call_abi=call_abi)
end

# Compatibility shim to deal with old build.jl files that don't yet use download_info()
function platform_key(machine::AbstractString = Sys.MACHINE)
    Base.depwarn("platform_key() is deprecated, use platform_key_abi() from now on", :binaryprovider_platform_key)
    platkey = platform_key_abi(machine)
    return typeof(platkey)(platkey.arch, platkey.libc, platkey.call_abi)
end