# This file contains the ingredients to create a PackageManager for BinDeps
using BinDeps
import BinDeps: Binaries, can_use, package_available, libdir, generate_steps,
                LibraryDependency, provider, provides
import Base: show

type BP <: Binaries
    pkg::String
    url::String
    hash::String
    prefix::Prefix
end

show(io::IO, p::BP) = write(io, "BinaryProvider for $(p.pkg)")

# We are cross-platform baby, and we never say no to a party
can_use(::Type{BP}) = true
package_available(p::BP) = true
libdir(p::BP, dep) = @static if is_windows()
    joinpath(p.prefix, "bin")
else
    joinpath(p.prefix, "lib")
end

# We provide (heh) our own overload of provides() for BP
macro BP_provides(pkg, url, hash, dep, opts...)
    return quote
        prefix = Prefix(joinpath(dirname(@__FILE__)))
        activate(prefix)
        return provides(BP, ($pkg, $url, $hash, prefix), $(esc(dep)), $(opts...))
    end
end
provider(::Type{BP}, data; opts...) = BP(data...)

function generate_steps(dep::LibraryDependency, p::BP, opts)
    () -> begin
        install(p.pkg, p.url, p.hash; prefix=p.prefix)
    end
end
