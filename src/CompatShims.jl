# Compatibility shims for old BP versions, when we make a change

for T in [:Linux, :MacOS, :Windows, :FreeBSD]
    @eval $T(arch, libc) = $T(arch; libc=libc)
    @eval $T(arch, libc, call_abi) = $T(arch; libc=libc, call_abi=call_abi)
end

# Compatibility shim to deal with old build.jl files that don't yet use download_info()
function platform_key(machine::AbstractString = Sys.MACHINE)
    Base.depwarn("platform_key() is deprecated, use platform_key_abi() from now on", :binaryprovider_platform_key)
    platkey = platform_key_abi(machine)
    return typeof(platkey)(arch(platkey), libc(platkey), call_abi(platkey))
end


# TODO: fill in better upper bound here when #27674 is backported
# ref: https://github.com/JuliaLang/julia/pull/27674
if v"0.7.0" <= VERSION < v"0.7.1"
    Base.peek(io::Base.AbstractPipe) = Base.peek(Base.pipe_reader(io))
end
