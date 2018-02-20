export @write_deps_file

## Everything in this file can be thrown out once users aren't using the old
## Product syntax and old @write_deps_file macro anymore.  As of the time of
## this writing, those packages are:
##
##  - EzXML
##  - CALCEPH
##  - Sundials
##  - Snappy
##
## Once those packages update, we can drop these shims

# Jam a new variable name into a Product
function revar_product(p::Product, new_varname)
    if p isa LibraryProduct
        return LibraryProduct(p.dir_path, p.libnames, new_varname)
    elseif p isa ExecutableProduct
        return ExecutableProduct(p.path, new_varname)
    elseif p isa FileProduct
        return FileProduct(p.path, new_varname)
    else
        error("Unknown product type $(typeof(p))")
    end
end

# Deprecated backwards-compatibility macro
macro write_deps_file(capture...)
    # props to @tshort for his macro wizardry
    names = :($(capture))
    products = esc(Expr(:tuple, capture...))

    # We have to create this dummy_source, because we cannot, in a single line,
    # have both `@__FILE__` and `__source__` interpreted by the same julia.
    dummy_source = VERSION >= v"0.7.0-" ? __source__.file : ""

    # Set this to verbose if we've requested it from build.jl
    verbose = "--verbose" in ARGS

    return quote
        warn("@write_deps_file is deprecated, use the function not the macro!")
        const source = VERSION >= v"0.7.0-" ? $("$(dummy_source)") : @__FILE__
        const depsjl_path = joinpath(dirname(source), "deps.jl")

        # Insert our macro-captured information
        names = $(names)
        products = Product[p for p in $(products)]

        # Jam the captured names into here as new-style variable names
        for idx in 1:length(products)
            products[idx] = revar_product(products[idx], names[idx])
        end

        # Call the new write_deps_file() function
        write_deps_file(depsjl_path, products; verbose=$(verbose))
    end
end

function guess_varname(path::AbstractString)
    # Take the basename of the path
    path = basename(path)

    # Chop off things that can't be part of variable names but are
    # often part of paths:
    bad_idxs = findin(path, "-.")
    if !isempty(bad_idxs)
        path = path[1:minimum(bad_idxs)-1]
    end

    # Return this as a Symbol
    return Symbol(path)
end

function LibraryProduct(dir_or_prefix, libnames)
    varname = :unknown
    if libnames isa Vector
        varname = guess_varname(libnames[1])
    elseif libnames isa AbstractString
        varname = guess_varname(libnames)
    end
    warn("LibraryProduct() now takes a variable name! auto-choosing $(varname)")
    return LibraryProduct(dir_or_prefix, libnames, varname)
end

function ExecutableProduct(prefix::Prefix, binname::AbstractString)
    return ExecutableProduct(joinpath(bindir(prefix), binname))
end
function ExecutableProduct(binpath::AbstractString)
    varname = guess_varname(binpath)
    warn("ExecutableProduct() now takes a variable name!  auto-choosing $(varname)")
    return ExecutableProduct(binpath, varname)
end

function FileProduct(path)
    varname = guess_varname(path)
    warn("FileProduct() now takes a variable name!  auto-choosing $(varname)")
    return FileProduct(path, varname)
end
