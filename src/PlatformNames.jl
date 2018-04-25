export platform_key, platform_dlext, valid_dl_path, arch, wordsize, triplet,
       Platform, UnknownPlatform, Linux, MacOS, Windows, FreeBSD
import Base: show

abstract type Platform end

struct UnknownPlatform <: Platform
end

struct Linux <: Platform
    arch::Symbol
    libc::Symbol
    abi::Symbol

    function Linux(arch::Symbol, libc::Symbol=:glibc,
                                 abi::Symbol=:default_abi)
        if !in(arch, [:i686, :x86_64, :aarch64, :powerpc64le, :armv7l])
            throw(ArgumentError("Unsupported architecture '$arch' for Linux"))
        end

        # The default libc on Linux is glibc
        if libc === :blank_libc
            libc = :glibc
        end

        if !in(libc, [:glibc, :musl])
            throw(ArgumentError("Unsupported libc '$libc' for Linux"))
        end

        # The default abi on Linux is blank, so map over to that by default,
        # except on armv7l, where we map it over to :eabihf
        if abi === :default_abi
            if arch != :armv7l
                abi = :blank_abi
            else
                abi = :eabihf
            end
        end

        if !in(abi, [:eabihf, :blank_abi])
            throw(ArgumentError("Unsupported abi '$abi' for Linux"))
        end

        # If we're constructing for armv7l, we MUST have the eabihf abi
        if arch == :armv7l && abi != :eabihf
            throw(ArgumentError("armv7l Linux must use eabihf, not '$abi'"))
        end
        # ...and vice-versa
        if arch != :armv7l && abi == :eabihf
            throw(ArgumentError("eabihf Linux is only on armv7l, not '$arch'!"))
        end

        return new(arch, libc, abi)
    end
end

struct MacOS <: Platform
    arch::Symbol
    libc::Symbol
    abi::Symbol

    # Provide defaults for everything because there's really only one MacOS
    # target right now.  Maybe someday iOS.  :fingers_crossed:
    function MacOS(arch::Symbol=:x86_64, libc::Symbol=:blank_libc,
                                         abi=:blank_abi)
        if arch !== :x86_64
            throw(ArgumentError("Unsupported architecture '$arch' for macOS"))
        end
        if libc !== :blank_libc
            throw(ArgumentError("Unsupported libc '$libc' for macOS"))
        end
        if abi !== :blank_abi
            throw(ArgumentError("Unsupported abi '$abi' for macOS"))
        end
        return new(arch, libc, abi)
    end
end

struct Windows <: Platform
    arch::Symbol
    libc::Symbol
    abi::Symbol

    function Windows(arch::Symbol, libc::Symbol=:blank_libc,
                                   abi::Symbol=:blank_abi)
        if !in(arch, [:i686, :x86_64])
            throw(ArgumentError("Unsupported architecture '$arch' for Windows"))
        end
        # We only support the one libc/abi on Windows, so no need to play
        # around with "default" values.
        if libc !== :blank_libc
            throw(ArgumentError("Unsupported libc '$libc' for Windows"))
        end
        if abi !== :blank_abi
            throw(ArgumentError("Unsupported abi '$abi' for Windows"))
        end
        return new(arch, libc, abi)
    end
end

struct FreeBSD <: Platform
    arch::Symbol
    libc::Symbol
    abi::Symbol

    function FreeBSD(arch::Symbol, libc::Symbol=:blank_libc,
                                   abi::Symbol=:default_abi)
        # `uname` on FreeBSD reports its architecture as amd64 and i386 instead of x86_64
        # and i686, respectively. In the off chance that Julia hasn't done the mapping for
        # us, we'll do it here just in case.
        if arch === :amd64
            arch = :x86_64
        elseif arch === :i386
            arch = :i686
        elseif !in(arch, [:i686, :x86_64, :aarch64, :powerpc64le, :armv7l])
            throw(ArgumentError("Unsupported architecture '$arch' for FreeBSD"))
        end

        # The only libc we support on FreeBSD is the blank libc, which corresponds to
        # FreeBSD's default libc
        if libc !== :blank_libc
            throw(ArgumentError("Unsupported libc '$libc' for FreeBSD"))
        end

        # The default abi on FreeBSD is blank, execpt on armv7l
        if abi === :default_abi
            if arch != :armv7l
                abi = :blank_abi
            else
                abi = :eabihf
            end
        end

        if !in(abi, [:eabihf, :blank_abi])
            throw(ArgumentError("Unsupported abi '$abi' for FreeBSD"))
        end

        # If we're constructing for armv7l, we MUST have the eabihf abi
        if arch == :armv7l && abi != :eabihf
            throw(ArgumentError("armv7l FreeBSD must use eabihf, no '$abi'"))
        end
        # ...and vice-versa
        if arch != :armv7l && abi == :eabihf
            throw(ArgumentError("eabihf FreeBSD is only on armv7l, not '$arch'!"))
        end

        return new(arch, libc, abi)
    end
end

"""
    platform_name(p::Platform)

Get the "platform name" of the given platform.  E.g. returns "Linux" for a
`Linux` object, or "Windows" for a `Windows` object.
"""
platform_name(p::Linux) = "Linux"
platform_name(p::MacOS) = "MacOS"
platform_name(p::Windows) = "Windows"
platform_name(p::FreeBSD) = "FreeBSD"
platforn_name(p::UnknownPlatform) = "UnknownPlatform"

"""
    arch(p::Platform)

Get the architecture for the given `Platform` object as a `Symbol`.

# Examples
```jldoctest
julia> arch(Linux(:aarch64))
:aarch64

julia> arch(MacOS())
:x86_64
```
"""
arch(p::Platform) = p.arch
arch(u::UnknownPlatform) = :unknown

"""
    libc(p::Platform)

Get the libc for the given `Platform` object as a `Symbol`.

# Examples
```jldoctest
julia> libc(Linux(:aarch64))
:glibc

julia> libc(FreeBSD(:x86_64))
:default_libc
```
"""
libc(p::Platform) = p.libc
libc(u::UnknownPlatform) = :unknown

"""
    abi(p::Platform)

Get the ABI for the given `Platform` object as a `Symbol`.

# Examples
```jldoctest
julia> abi(Linux(:x86_64))
:blank_abi

julia> abi(FreeBSD(:armv7l))
:eabihf
```
"""
abi(p::Platform) = p.abi
abi(u::UnknownPlatform) = :unknown

"""
    wordsize(platform)

Get the word size for the given `Platform` object.

# Examples
```jldoctest
julia> wordsize(Linux(:arm7vl))
32

julia> wordsize(MacOS())
64
```
"""
wordsize(p::Platform) = (arch(p) === :i686 || arch(p) === :armv7l) ? 32 : 64
wordsize(u::UnknownPlatform) = 0

"""
    triplet(platform)

Get the target triplet for the given `Platform` object as a `String`.

# Examples
```jldoctest
julia> triplet(MacOS())
"x86_64-apple-darwin14"

julia> triplet(Windows(:i686))
"i686-w64-mingw32"

julia> triplet(Linux(:armv7l))
"arm-linux-gnueabihf"
```
"""
triplet(w::Windows) = string(arch_str(w), "-w64-mingw32")
triplet(m::MacOS) = string(arch_str(m), "-apple-darwin14")
triplet(l::Linux) = string(arch_str(l), "-linux", libc_str(l), abi_str(l))
triplet(f::FreeBSD) = string(arch_str(f), "-unknown-freebsd11.1", libc_str(f), abi_str(f))
triplet(u::UnknownPlatform) = "unknown-unknown-unknown"

# Helper functions for Linux and FreeBSD libc/abi mishmashes
arch_str(p::Platform) = (arch(p) == :armv7l) ? "arm" : "$(arch(p))"
function libc_str(p::Platform)
    if libc(p) == :blank_libc
        return ""
    elseif libc(p) == :glibc
        return "-gnu"
    else
        return "-$(libc(p))"
    end
end
abi_str(p::Platform) = (abi(p) == :blank_abi) ? "" : "$(abi(p))"

# Override Compat definitions as well
Compat.Sys.isapple(p::Platform) = p isa MacOS
Compat.Sys.islinux(p::Platform) = p isa Linux
Compat.Sys.iswindows(p::Platform) = p isa Windows
Compat.Sys.isbsd(p::Platform) = (p isa FreeBSD) || (p isa MacOS)

"""
    platform_key(machine::AbstractString = Sys.MACHINE)

Returns the platform key for the current platform, or any other though the
the use of the `machine` parameter.
"""
function platform_key(machine::AbstractString = Sys.MACHINE)
    # We're going to build a mondo regex here to parse everything:
    arch_mapping = Dict(
        :x86_64 => "(x86_|amd)64",
        :i686 => "i\\d86",
        :aarch64 => "aarch64",
        :armv7l => "arm(v7l)?",
        :powerpc64le => "p(ower)?pc64le",
    )
    platform_mapping = Dict(
        :darwin => "-apple-darwin\\d*",
        :freebsd => "-(.*-)?freebsd[\\d\\.]*",
        :mingw32 => "-w64-mingw32",
        :linux => "-(.*-)?linux",
    )
    libc_mapping = Dict(
        :blank_libc => "",
        :glibc => "-gnu",
        :musl => "-musl",
    )
    abi_mapping = Dict(
        :blank_abi => "",
        :eabihf => "eabihf",
    )

    # Helper function to collapse dictionary of mappings down into a regex of
    # named capture groups joined by "|" operators
    c(mapping) = string("(",join(["(?<$k>$v)" for (k, v) in mapping], "|"), ")")

    triplet_regex = Regex(string(
        c(arch_mapping),
        c(platform_mapping),
        c(libc_mapping),
        c(abi_mapping),
    ))

    m = match(triplet_regex, machine)
    if m != nothing
        # Helper function to find the single named field within the giant regex
        # that is not `nothing` for each mapping we give it.
        get_field(m, mapping) = begin
            for k in keys(mapping)
                if m[k] != nothing
                   return k
                end
            end
        end

        # Extract the information we're interested in:
        arch = get_field(m, arch_mapping)
        platform = get_field(m, platform_mapping)
        libc = get_field(m, libc_mapping)
        abi = get_field(m, abi_mapping)

        # First, figure out what platform we're dealing with, then sub that off
        # to the appropriate constructor.  All constructors take in (arch, libc,
        # abi)  but they will throw errors on trouble, so we catch those and
        # return the value UnknownPlatform() here to be nicer to client code.
        try
            if platform == :darwin
                return MacOS(arch, libc, abi)
            elseif platform == :mingw32
                return Windows(arch, libc, abi)
            elseif platform == :freebsd
                return FreeBSD(arch, libc, abi)
            elseif platform == :linux
                return Linux(arch, libc, abi)
            end
        end
    end

    Compat.@warn("Platform `$(machine)` is not an officially supported platform")
    return UnknownPlatform()
end

"""
    platform_dlext(platform::Platform = platform_key())

Return the dynamic library extension for the given platform, defaulting to the
currently running platform.  E.g. returns "so" for a Linux-based platform,
"dll" for a Windows-based platform, etc...
"""
platform_dlext(l::Linux) = "so"
platform_dlext(f::FreeBSD) = "so"
platform_dlext(m::MacOS) = "dylib"
platform_dlext(w::Windows) = "dll"
platform_dlext(u::UnknownPlatform) = "unknown"
platform_dlext() = platform_dlext(platform_key())

"""
    valid_dl_path(path::AbstractString, platform::Platform)

Return `true` if the given `path` ends in a valid dynamic library filename.
E.g. returns `true` for a path like `"usr/lib/libfoo.so.3.5"`, but returns
`false` for a path like `"libbar.so.f.a"`.
"""
function valid_dl_path(path::AbstractString, platform::Platform)
    dlext_regexes = Dict(
        # On Linux, libraries look like `libnettle.so.6.3.0`
        "so" => r"^(.*).so(\.[\d]+){0,3}$",
        # On OSX, libraries look like `libnettle.6.3.dylib`
        "dylib" => r"^(.*).dylib$",
        # On Windows, libraries look like `libnettle-6.dylib`
        "dll" => r"^(.*).dll$"
    )

    # Given a platform, find the dlext regex that matches it
    dlregex = dlext_regexes[platform_dlext(platform)]

    # Return whether or not that regex matches the basename of the given path
    return ismatch(dlregex, basename(path))
end


# Define show() for these objects for two reasons:
#  - I don't like the `BinaryProvider.` at the beginning of the types;
#    it's unnecessary as these are exported
#  - I don't like the :blank_* arguments, they're unnecessary
function show(io::IO, p::Platform)
    write(io, "$(platform_name(p))($(repr(arch(p)))")
    omit_libc = libc(p) == :blank_libc
    omit_abi = abi(p) == :blank_abi

    if !omit_libc || !omit_abi
        write(io, ", $(repr(libc(p)))")
    end
    if !omit_abi
        write(io, ", $(repr(abi(p)))")
    end
    write(io, ")")
end
