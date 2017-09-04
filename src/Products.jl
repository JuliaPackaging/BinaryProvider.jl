export Product, LibraryResult, FileResult, ExecutableResult, satisfied, @write_deps_file

# Products are things that should exist after we install something
abstract Product

# A Library Result is a special kind of Result that not only needs to exist,
# but needs to have a special set of audit rules applied to it to show
# that the library can be loaded, that it does not have dependencies that live
# outside of its prefix/the base Julia distribution, etc...
immutable LibraryResult <: Product
    path::String

    function LibraryResult(path::AbstractString)
        # For LibraryResults, abstract away adding a dlext by manually slapping
        # it on, but only do this if one doesn't already exist.  Because we
        # cross-compile quite a bit, we must check ALL dlexts.  This is simple
        # for OSX and Windows (just check if it ends with `.dylib` and `.dll`)
        # but on Linux, we have to allow for versioned shared object names:
        const dlext_regexes = [
            # On Linux, libraries look like `libnettle.so.6.3.0`
            r"^(.*).so(\.[\d]+){0,3}$",
            # On OSX, libraries look like `libnettle.6.3.dylib`
            r"^(.*).dylib$",
            # On Windows, libraries look like `libnettle-6.dylib`
            r"^(.*).dll$"
        ]

        # If none of these match, then slap our native dlext on the end
        if !any(ismatch(dlregex, path) for dlregex in dlext_regexes)
            path = "$(path).$(Libdl.dlext)"
        end
        return new(path)
    end
end

function satisfied(lr::LibraryResult; verbose::Bool = false)
    if !isfile(lr.path)
        if verbose
            info("$(lr.path) does not exist, reporting unsatisfied")
        end
        return false
    end

    lr_handle = Libdl.dlopen_e(lr.path)
    if lr_handle == C_NULL
        if verbose
            info("$(lr.path) cannot be dlopen'ed, reporting unsatisfied")
        end
        
        # Eventually, I would like to add better debugging here to inspect the
        # library to determine _why_ it cannot be dlopen()'ed.
        return false
    end
    Libdl.dlclose(lr_handle)

    return true
end


immutable ExecutableResult <: Product
    path::AbstractString
end

function satisfied(er::ExecutableResult; verbose::Bool = false)
    if !isfile(er.path)
        if verbose
            info("$(er.path) does not exist, reporting unsatisfied")
        end
        return false
    end

    if uperm(er.path) & 0x1 == 0
        if verbose
            info("$(er.path) is not executable, reporting unsatisfied")
        end
        return false
    end

    return true
end


immutable FileResult <: Product
    path::AbstractString
end

function satisfied(fr::FileResult; verbose::Bool = false)
    if !isfile(fr.path)
        if verbose
            info("FileResult $(fr.path) does not exist, reporting unsatisfied")
        end
        return false
    end
    return true
end

"""
`@write_deps_file(products...)`

Helper macro to generate a `deps.jl` file out of a mapping of variable name
to  `Product` objects. Call using something like:

    fooifier = ExecutableResult(...)
    libbar = LibraryResult(...)
    @write_deps_file fooifier libbar

If any `Product` object cannot be satisfied (e.g. `LibraryResult` objects must
be `dlopen()`-able, `FileResult` objects must exist on the filesystem, etc...)
this macro will error out.  Ensure that you have used `install()` to install
the binaries you wish to write a `deps.jl` file for, and, optionally that you
have used `activate()` on the `Prefix` in which the binaries were installed so
as to make sure that the binaries are locatable.

The result of this macro call is a `deps.jl` file containing variables named
the same as the keys of the passed-in dictionary, holding the full path to the
installed binaries.  Given the example above, it would contain code similar to:

    global const fooifier = "<pkg path>/deps/usr/bin/fooifier"
    global const libbar = "<pkg path>/deps/usr/lib/libbar.so"

This file is intended to be `include()`'ed from within the `__init__()` method
of your package.  Note that all files are checked for consistency on package
load time, and if an error is discovered, package loading will fail, asking
the user to re-run `Pkg.build("package_name")`.
"""
macro write_deps_file(capture...)
    # props to @tshort for his macro wizardry
    const names = :($(capture))
    const products = esc(Expr(:tuple, capture...))

    return quote
        # First pick up important pieces of information from the call-site
        const depsjl_path = joinpath(@__DIR__, "deps.jl")
        const package_name = basename(dirname(@__DIR__))

        const rebuild = strip("""
        Please re-run Pkg.build(\\\"$(package_name)\\\"), and restart Julia.
        """)

        # Begin by ensuring that we can satisfy every product RIGHT NOW
        for product in $(products)
            # Check to make sure that we've passed in the right kind of
            # objects, e.g. subclasses of `Product`
            if !(typeof(product) <: Product)
                msg = "Cannot @write_deps_file for $product, which is " *
                        "of type $(typeof(product)), which is not a " *
                        "subtype of `Product`!"
                error(msg)
            end

            if !satisfied(product; verbose=true)
                error("$product is not satisfied, cannot generate deps.jl!")
            end
        end

        # If things look good, let's generate the `deps.jl` file
        open(depsjl_path, "w") do depsjl_file
            # First, dump the preamble
            println(depsjl_file, strip("""
            ## This file autogenerated by BinaryProvider.@write_deps_file.
            ## Do not edit.
            """))

            # Next, spit out the paths of all our products
            for idx in 1:$(length(capture))
                product = $(products)[idx]
                name = $(names)[idx]

                println(depsjl_file, strip("""
                const $(name) = \"$(product.path)\"
                """))
            end

            # Next, generate a function to check they're all on the up-and-up
            println(depsjl_file, "function check_deps()")

            for product in $(products)
                # Check that any file exists
                println(depsjl_file, """
                if !isfile(\"$(product.path)\")
                    error("$(product.path) does not exist, $(rebuild)")
                end
                """)

                # For Library products, check that we can dlopen it:
                if typeof(product) <: LibraryResult
                    println(depsjl_file, """
                    if Libdl.dlopen_e(\"$(product.path)\") == C_NULL
                        error("$(product.path) cannot be opened, $(rebuild)")
                    end
                    """)
                end
            end

            # Close the `check_deps()` function
            println(depsjl_file, "end")
        end
    end
end