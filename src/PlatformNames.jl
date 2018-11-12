export platform_key, platform_key_abi, platform_dlext, valid_dl_path, arch, libc, call_abi, wordsize, triplet, choose_download,
       CompilerABI, Platform, UnknownPlatform, Linux, MacOS, Windows, FreeBSD
import Base: show

abstract type Platform end

struct UnknownPlatform <: Platform
end

# We need to track our compiler ABI compatibility.
struct CompilerABI
    # Major GCC version that we're locked into.
    # Can be [:gcc4, :gcc5, :gcc6, :gcc7, :gcc8, :gcc_any]
    gcc_version::Symbol

    # Whether we're using cxx11abi strings
    # Can be [:cxx03, :cxx11, :cxx_any]
    cxx_abi::Symbol

    function CompilerABI(gcc_version::Symbol = :gcc_any, cxx_abi::Symbol = :cxx_any)
        if !in(gcc_version, [:gcc4, :gcc5, :gcc6, :gcc7, :gcc8, :gcc_any])
            throw(ArgumentError("Unsupported GCC major version '$gcc_version'"))
        end

        if !in(cxx_abi, [:cxx03, :cxx11, :cxx_any])
            throw(ArgumentError("Unsupported string ABI '$cxx_abi'"))
        end

        return new(gcc_version, cxx_abi)
    end
end

function show(io::IO, cabi::CompilerABI)
    write(io, "CompilerABI(")
    if cabi.gcc_version != :gcc_any || cabi.cxx_abi != :cxx_any
        write(io, "$(repr(cabi.gcc_version))")
    end
    if cabi.cxx_abi != :cxx_any
        write(io, ", $(repr(cabi.cxx_abi))")
    end
    write(io, ")")
end


struct Linux <: Platform
    arch::Symbol
    libc::Symbol
    call_abi::Symbol
    compiler_abi::CompilerABI

    function Linux(arch::Symbol;
                   libc::Symbol=:glibc,
                   call_abi::Symbol=:default_abi,
                   compiler_abi::CompilerABI=CompilerABI())
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

        # The default calling abi on Linux is blank (e.g. not "eabi" or "eabihf"
        # or anything like that, just "blank"), so map over to that by default
        # except on armv7l, where we map it over to :eabihf
        if call_abi === :default_abi
            if arch != :armv7l
                call_abi = :blank_abi
            else
                call_abi = :eabihf
            end
        end

        if !in(call_abi, [:eabihf, :blank_abi])
            throw(ArgumentError("Unsupported calling abi '$call_abi' for Linux"))
        end

        # If we're constructing for armv7l, we MUST have the eabihf abi
        if arch == :armv7l && call_abi != :eabihf
            throw(ArgumentError("armv7l Linux must use eabihf, not '$call_abi'"))
        end
        # ...and vice-versa
        if arch != :armv7l && call_abi == :eabihf
            throw(ArgumentError("eabihf Linux is only on armv7l, not '$arch'!"))
        end

        return new(arch, libc, call_abi, compiler_abi)
    end
end

struct MacOS <: Platform
    arch::Symbol
    libc::Symbol
    call_abi::Symbol
    compiler_abi::CompilerABI

    # Provide defaults for everything because there's really only one MacOS
    # target right now.  Maybe someday iOS.  :fingers_crossed:
    function MacOS(arch::Symbol=:x86_64;
                   libc::Symbol=:blank_libc,
                   call_abi::Symbol=:blank_abi,
                   compiler_abi::CompilerABI=CompilerABI())
        if arch !== :x86_64
            throw(ArgumentError("Unsupported architecture '$arch' for macOS"))
        end
        if libc !== :blank_libc
            throw(ArgumentError("Unsupported libc '$libc' for macOS"))
        end
        if call_abi !== :blank_abi
            throw(ArgumentError("Unsupported abi '$call_abi' for macOS"))
        end

        return new(arch, libc, call_abi, compiler_abi)
    end
end

struct Windows <: Platform
    arch::Symbol
    libc::Symbol
    call_abi::Symbol
    compiler_abi::CompilerABI

    function Windows(arch::Symbol;
                     libc::Symbol=:blank_libc,
                     call_abi::Symbol=:blank_abi,
                     compiler_abi::CompilerABI=CompilerABI())
        if !in(arch, [:i686, :x86_64])
            throw(ArgumentError("Unsupported architecture '$arch' for Windows"))
        end
        # We only support the one libc/abi on Windows, so no need to play
        # around with "default" values.
        if libc !== :blank_libc
            throw(ArgumentError("Unsupported libc '$libc' for Windows"))
        end
        if call_abi !== :blank_abi
            throw(ArgumentError("Unsupported abi '$call_abi' for Windows"))
        end

        return new(arch, libc, call_abi, compiler_abi)
    end
end

struct FreeBSD <: Platform
    arch::Symbol
    libc::Symbol
    call_abi::Symbol
    compiler_abi::CompilerABI

    function FreeBSD(arch::Symbol;
                     libc::Symbol=:blank_libc,
                     call_abi::Symbol=:default_abi,
                     compiler_abi::CompilerABI=CompilerABI())
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
        if call_abi === :default_abi
            if arch != :armv7l
                call_abi = :blank_abi
            else
                call_abi = :eabihf
            end
        end

        if !in(call_abi, [:eabihf, :blank_abi])
            throw(ArgumentError("Unsupported calling abi '$call_abi' for FreeBSD"))
        end

        # If we're constructing for armv7l, we MUST have the eabihf abi
        if arch == :armv7l && call_abi != :eabihf
            throw(ArgumentError("armv7l FreeBSD must use eabihf, no '$call_abi'"))
        end
        # ...and vice-versa
        if arch != :armv7l && call_abi == :eabihf
            throw(ArgumentError("eabihf FreeBSD is only on armv7l, not '$arch'!"))
        end

        return new(arch, libc, call_abi, compiler_abi)
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
platform_name(p::UnknownPlatform) = "UnknownPlatform"

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
   call_abi(p::Platform)

Get the calling ABI for the given `Platform` object as a `Symbol`.

# Examples
```jldoctest
julia> call_abi(Linux(:x86_64))
:blank_abi

julia> call_abi(FreeBSD(:armv7l))
:eabihf
```
"""
call_abi(p::Platform) = p.call_abi
call_abi(u::UnknownPlatform) = :unknown

"""
    compiler_abi(p::Platform)

Get the compiler ABI object for the given `Platform`
# Examples
```jldoctest
julia> compiler_abi(Linux(:x86_64))
CompilerABI(:gcc_any, :cxx_any)

julia> compiler_abi(Linux(:x86_64; compiler_abi=CompilerABI(:gcc7)))
CompilerABI(:gcc7, :cxx_any)
```
"""
compiler_abi(p::Platform) = p.compiler_abi
compiler_abi(p::UnknownPlatform) = CompilerABI()

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

julia> triplet(Linux(:armv7l, :default_libc, :default_abi, CompilerABI(:gcc4))
"arm-linux-gnueabihf-gcc4"
```
"""
triplet(p::Platform) = string(
    arch_str(p),
    vendor_str(p),
    libc_str(p),
    call_abi_str(p),
    compiler_abi_str(p),
)
vendor_str(p::Windows) = "-w64-mingw32"
vendor_str(p::MacOS) = "-apple-darwin14"
vendor_str(p::Linux) = "-linux"
vendor_str(p::FreeBSD) = "-unknown-freebsd11.1"

# Special-case UnknownPlatform
triplet(p::UnknownPlatform) = "unknown-unknown-unknown"

# Helper functions for Linux and FreeBSD libc/abi mishmashes
arch_str(p::Platform) = (arch(p) == :armv7l) ? "arm" : string(arch(p))
function libc_str(p::Platform)
    if libc(p) == :blank_libc
        return ""
    elseif libc(p) == :glibc
        return "-gnu"
    else
        return "-$(libc(p))"
    end
end
call_abi_str(p::Platform) = (call_abi(p) == :blank_abi) ? "" : string(call_abi(p))
function compiler_abi_str(cabi::CompilerABI)
    str = ""
    if cabi.gcc_version != :gcc_any
        str *= "-$(cabi.gcc_version)"
    end
    if cabi.cxx_abi != :cxx_any
        str *= "-$(cabi.cxx_abi)"
    end
    return str
end
compiler_abi_str(p::Platform) = compiler_abi_str(compiler_abi(p))

Sys.isapple(p::Platform) = p isa MacOS
Sys.islinux(p::Platform) = p isa Linux
Sys.iswindows(p::Platform) = p isa Windows
Sys.isbsd(p::Platform) = (p isa FreeBSD) || (p isa MacOS)


"""
    platform_key_abi(machine::AbstractString)

Returns the platform key for the current platform, or any other though the
the use of the `machine` parameter.
"""
function platform_key_abi(machine::AbstractString)
    # We're going to build a mondo regex here to parse everything:
    arch_mapping = Dict(
        :x86_64 => "(x86_|amd)64",
        :i686 => "i\\d86",
        :aarch64 => "aarch64",
        :armv7l => "arm(v7l)?",
        :powerpc64le => "p(ower)?pc64le",
    )
    platform_mapping = Dict(
        :darwin => "-apple-darwin[\\d\\.]*",
        :freebsd => "-(.*-)?freebsd[\\d\\.]*",
        :mingw32 => "-w64-mingw32",
        :linux => "-(.*-)?linux",
    )
    libc_mapping = Dict(
        :blank_libc => "",
        :glibc => "-gnu",
        :musl => "-musl",
    )
    call_abi_mapping = Dict(
        :blank_abi => "",
        :eabihf => "eabihf",
    )
    gcc_version_mapping = Dict(
        :gcc_any => "",
        :gcc4 => "-gcc4",
        :gcc5 => "-gcc5",
        :gcc6 => "-gcc6",
        :gcc7 => "-gcc7",
        :gcc8 => "-gcc8",
    )
    cxx_abi_mapping = Dict(
        :cxx_any => "",
        :cxx03 => "-cxx03",
        :cxx11 => "-cxx11",
    )

    # Helper function to collapse dictionary of mappings down into a regex of
    # named capture groups joined by "|" operators
    c(mapping) = string("(",join(["(?<$k>$v)" for (k, v) in mapping], "|"), ")")

    triplet_regex = Regex(string(
        "^",
        c(arch_mapping),
        c(platform_mapping),
        c(libc_mapping),
        c(call_abi_mapping),
        c(gcc_version_mapping),
        c(cxx_abi_mapping),
        "\$",
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
        call_abi = get_field(m, call_abi_mapping)
        gcc_version = get_field(m, gcc_version_mapping)
        cxx_abi = get_field(m, cxx_abi_mapping)

        # First, figure out what platform we're dealing with, then sub that off
        # to the appropriate constructor.  If a constructor runs into trouble,
        # catch the error and return `UnknownPlatform()` here to be nicer to client code.
        ctors = Dict(:darwin => MacOS, :mingw32 => Windows, :freebsd => FreeBSD, :linux => Linux)
        try
            T = ctors[platform]
            compiler_abi = CompilerABI(gcc_version, cxx_abi)
            return T(arch, libc=libc, call_abi=call_abi, compiler_abi=compiler_abi)
        catch
        end
    end

    @warn("Platform `$(machine)` is not an officially supported platform")
    return UnknownPlatform()
end


# Define show() for these Platform objects for two reasons:
#  - I don't like the `BinaryProvider.` at the beginning of the types;
#    it's unnecessary as these are exported
#  - I don't like the :blank_*/:any arguments, they're unnecessary
function show(io::IO, p::Platform)
    write(io, "$(platform_name(p))($(repr(arch(p)))")

    if libc(p) != :blank_libc
        write(io, ", libc=$(repr(libc(p)))")
    end
    if call_abi(p) != :blank_abi
        write(io, ", call_abi=$(repr(call_abi(p)))")
    end
    cabi = compiler_abi(p)
    if cabi.gcc_version != :gcc_any || cabi.cxx_abi != :cxx_any
        write(io, ", compiler_abi=$(repr(cabi))")
    end
    write(io, ")")
end


"""
    platform_dlext(platform::Platform = platform_key_abi())

Return the dynamic library extension for the given platform, defaulting to the
currently running platform.  E.g. returns "so" for a Linux-based platform,
"dll" for a Windows-based platform, etc...
"""
platform_dlext(::Linux) = "so"
platform_dlext(::FreeBSD) = "so"
platform_dlext(::MacOS) = "dylib"
platform_dlext(::Windows) = "dll"
platform_dlext(::UnknownPlatform) = "unknown"
platform_dlext() = platform_dlext(platform_key_abi())

"""
    parse_dl_name_version(path::AbstractString, platform::Platform)

Given a path to a dynamic library, parse out what information we can
from the filename.  E.g. given something like "lib/libfoo.so.3.2",
this function returns `"libfoo", v"3.2"`.  If the path name is not a
valid dynamic library, this method throws an error.  If no soversion
can be extracted from the filename, as in "libbar.so" this method
returns `"libbar", nothing`.
"""
function parse_dl_name_version(path::AbstractString, platform::Platform)
    dlext_regexes = Dict(
        # On Linux, libraries look like `libnettle.so.6.3.0`
        "so" => r"^(.*?).so((?:\.[\d]+)*)$",
        # On OSX, libraries look like `libnettle.6.3.dylib`
        "dylib" => r"^(.*?)((?:\.[\d]+)*).dylib$",
        # On Windows, libraries look like `libnettle-6.dylib`
        "dll" => r"^(.*?)(?:-((?:[\.\d]+)*))?.dll$"
    )

    # Use the regex that matches this platform
    dlregex = dlext_regexes[platform_dlext(platform)]
    m = match(dlregex, basename(path))
    if m === nothing
        throw(ArgumentError("Invalid dynamic library path '$path'"))
    end

    # Extract name and version
    name = m.captures[1]
    version = m.captures[2]
    if version === nothing || isempty(version)
        version = nothing
    else
        version = VersionNumber(strip(version, '.'))
    end
    return name, version
end

"""
    valid_dl_path(path::AbstractString, platform::Platform)

Return `true` if the given `path` ends in a valid dynamic library filename.
E.g. returns `true` for a path like `"usr/lib/libfoo.so.3.5"`, but returns
`false` for a path like `"libbar.so.f.a"`.
"""
function valid_dl_path(path::AbstractString, platform::Platform)
    try
        parse_dl_name_version(path, platform)
        return true
    catch
        return false
    end
end

"""
    detect_libgfortran_abi(libgfortran_name::AbstractString)

Examines the given libgfortran SONAME to see what version of GCC corresponds
to the given libgfortran version.
"""
function detect_libgfortran_abi(libgfortran_name::AbstractString, platform::Platform = platform_key_abi(Sys.MACHINE))
    # Extract the version number from this libgfortran.  Ironically, parse_dl_name_version()
    # wants a Platform, but we may not have initialized the default platform key yet when we
    # run this method for the first time (since we need the output of this function to set
    # that default platform) so we manually pass in Sys.MACHINE.  :P
    name, version = parse_dl_name_version(libgfortran_name, platform)
    if version === nothing
        @warn("Unable to determine libgfortran version from '$(libgfortran_name)'; returning :gcc_any")
        return :gcc_any
    end
    libgfortran_to_gcc = Dict(
        3 => :gcc4,
        4 => :gcc7,
        5 => :gcc8,
    )
    if !in(version.major, keys(libgfortran_to_gcc))
        @warn("Unsupported libgfortran version '$version'; returning :gcc_any")
        return :gcc_any
    end
    return libgfortran_to_gcc[version.major]
end

"""
    detect_libgfortran_abi()

If no parameter is given, introspects the current Julia process to determine
the version of GCC this Julia was built with.
"""
function detect_libgfortran_abi()
    libgfortran_paths = filter(x -> occursin("libgfortran", x), dllist())
    if isempty(libgfortran_paths)
         # One day, I hope to not be linking against libgfortran in base Julia
        return :gcc_any
    end
    return detect_libgfortran_abi(first(libgfortran_paths))
end

"""
    detect_libstdcxx_abi()

Introspects the currently running Julia process to find out what version of libstdc++
it is linked to (if any), as a proxy for GCC version compatibility.  E.g. if we are
linked against libstdc++.so.19, binary dependencies built by GCC 8.1.0 will have linker
errors.  This method returns the maximum GCC abi that we can support.
"""
function detect_libstdcxx_abi()
    libstdcxx_paths = filter(x -> occursin("libstdc++", x), dllist())
    if isempty(libstdcxx_paths)
        # This can happen if we were built by clang, so we don't link against
        # libstdc++ at all.
        return :gcc_any
    end

    # Extract all pieces of `.gnu.version_d` from libstdc++.so, find the `GLIBCXX_*`
    # symbols, and use the maximum version of that to find the GLIBCXX ABI version number
    #version_symbols = readmeta(first(libstdcxx_paths)) do oh
    #    unique(vcat((x -> x.names).(ELFVersionData(oh))...))
    #end
    #version_symbols = filter(x -> startswith(x, "GLIBCXX_"), version_symbols)
    #max_version = maximum([VersionNumber(split(v, "_")[2]) for v in version_symbols])

    # ^^ Okay, that's really cool, but unfortunately it introduces a dependency on
    # ObjectFile which is unacceptable for us.  So instead we just brute-force it.
    max_version = v"3.4.0"
    hdl = dlopen(first(libstdcxx_paths))
    for minor_version in 1:26
        if dlsym_e(hdl, "GLIBCXX_3.4.$(minor_version)") != C_NULL
            max_version = VersionNumber("3.4.$(minor_version)")
        end
    end
    dlclose(hdl)

    # Full list available here: https://gcc.gnu.org/onlinedocs/libstdc++/manual/abi.html
    if max_version < v"3.4.18"
        @warn "Cannot make sense of autodetected libstdc++ ABI version ('$max_version')"
        return :gcc_any
    elseif max_version < v"3.4.23"
        # If we aren't up to 7.1.0, then we fall all the way back to 4.8.5
        return :gcc4
    elseif max_version < v"3.4.25"
        return :gcc7
    else
        return :gcc8
    end
end

"""
    detect_cxx11_string_abi()

Introspects the currently running Julia process to see what version of the C++11 string
ABI it was compiled with.  (In reality, it checks for symbols within LLVM, but that is
close enough for our purposes, as you can't mix linkages between Julia and LLVM if they
are not compiled in the same way).
"""
function detect_cxx11_string_abi()
    function open_libllvm()
        for lib_name in ("libLLVM", "LLVM", "libLLVMSupport")
            hdl = dlopen_e(lib_name)
            if hdl != C_NULL
                return hdl
            end
        end
        error("Unable to open libLLVM!")
    end

    hdl = open_libllvm()
    # Check for llvm::sys::getProcessTriple(), first without cxx11 tag:
    if dlsym_e(hdl, "_ZN4llvm3sys16getProcessTripleEv") != C_NULL
        return :cxx03
    elseif dlsym_e(hdl, "_ZN4llvm3sys16getProcessTripleB5cxx11Ev") != C_NULL
        return :cxx11
    else
        error("Unable to find llvm::sys::getProcessTriple() in libLLVM!")
    end
end

function detect_compiler_abi()
    gcc_version = detect_libgfortran_abi()
    cxx11_string_abi = detect_cxx11_string_abi()

    # If we have no constraint from libgfortran linkage (impossible within current
    # Julia, but let's be planning for the future here) then inspect libstdc++.
    if gcc_version == :gcc_any
        gcc_version = detect_libstdcxx_abi()
    end

    return CompilerABI(gcc_version, cxx11_string_abi)
end


# Cache the default platform_key_abi() since that's by far the most common way
# we call platform_key_abi(), and we don't want to parse the same thing over
# and over and over again.  Note that we manually slap on a compiler abi
# string onto the end, so as to encode that in Sys.MACHINE like we expect our
# triplets to be encoded.
default_platkey = platform_key_abi(string(
    Sys.MACHINE,
    compiler_abi_str(detect_compiler_abi()),
))
function platform_key_abi()
    global default_platkey
    return default_platkey
end

function platforms_match(a::Platform, b::Platform)
    # Check to see if a and b  satisfy the rigid constraints first, these are
    # things that are simple equality checks:
    function rigid_constraints(a, b)
        return (typeof(a) <: typeof(b) || typeof(b) <: typeof(a)) &&
               (arch(a) == arch(b)) && (libc(a) == libc(b)) &&
               (call_abi(a) == call_abi(b))
    end

    # The flexible constraints are ones that can do equals, but also have things
    # like "any" values, etc....
    function flexible_constraints(a, b)
        ac = compiler_abi(a)
        bc = compiler_abi(b)

        # Map from GCC version to libgfortran SO version
        gfmap = Dict(
            :gcc4 => 3,
            :gcc5 => 3,
            :gcc6 => 3,
            :gcc7 => 4,
            :gcc8 => 5,
        )

        # We consider two GCC versions to match if their libgfortran
        # versions match; e.g. :gcc4 and :gcc5 match.
        gcc_match = (ac.gcc_version == :gcc_any
                  || bc.gcc_version == :gcc_any
                  || gfmap[ac.gcc_version] == gfmap[bc.gcc_version])
        cxx_match = (ac.cxx_abi == :cxx_any
                  || bc.cxx_abi == :cxx_any
                  || ac.cxx_abi == bc.cxx_abi)
        return gcc_match && cxx_match
    end

    return rigid_constraints(a, b) && flexible_constraints(a, b)
end

"""
    choose_download(download_info::Dict, platform::Platform = platform_key_abi())

Given a `download_info` dictionary mapping platforms to some value, choose
the value whose key best matches `platform`, returning `nothing` if no matches
can be found.

Platform attributes such as architecture, libc, calling ABI, etc... must all
match exactly, however attributes such as compiler ABI can have wildcards
within them such as `:gcc_any` which matches any version of GCC.
"""
function choose_download(download_info::Dict, platform::Platform = platform_key_abi())
    ps = collect(filter(p -> platforms_match(p, platform), keys(download_info)))

    if isempty(ps)
        return nothing
    end

    # At this point, we may have multiple possibilities.  E.g. if, in the future,
    # Julia can be built without a direct dependency on libgfortran, we may match
    # multiple tarballs that vary only within their libgfortran ABI.  To narrow it
    # down, we just sort by triplet, then pick the last one.  This has the effect
    # of generally choosing the latest release (e.g. a `libgfortran5` tarball
    # rather than a `libgfortran3` tarball)
    p = last(sort(ps, by = p -> triplet(p)))
    return download_info[p]
end
