# BinaryProvider

[![Travis Status](https://travis-ci.org/JuliaPackaging/BinaryProvider.jl.svg?branch=master)](https://travis-ci.org/JuliaPackaging/BinaryProvider.jl)

[![Appveyor Status](https://ci.appveyor.com/api/projects/status/0sbp28iie07c5dn3/branch/master?svg=true)](https://ci.appveyor.com/project/staticfloat/binaryprovider-jl-fu5p5/branch/master)

[![codecov.io](http://codecov.io/github/JuliaPackaging/BinaryProvider.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaPackaging/BinaryProvider.jl?branch=master)

## Basic concepts

Packages are installed to a `Prefix`; a folder that acts similar to the `/usr/local` directory on Unix-like systems, containing a `bin` folder for binaries, a `lib` folder for libraries, etc...  `Prefix` objects can have tarballs `install()`'ed within them, `uninstall()`'ed from them, etc...

`BinaryProvider` has the concept of a `Product`, the result of a package installation.  `LibraryProduct` and `ExecutableProduct` are two example `Product` object types that can be used to keep track of the binary objects installed by an `install()` invocation.  `Products` can check to see if they are already satisfied (e.g. whether a file exists, or is executable, or is `dlopen()`'able), allowing for very quick and easy `build.jl` construction.

`BinaryProvider` also contains a platform abstraction layer for common operations like downloading and unpacking tarballs.  The primary method you should be using to interact with these operations is through the `install()` method, however if you need more control, there are more fundamental methods such as `download_verify()`, or `unpack()`, or even the wittingly-named `download_verify_unpack()`.

The method documentation within the `BinaryProvider` module should be considered the primary source of documentation for this package, usage examples are provided in the form of the `LibFoo.jl` mock package [within this repository](test/LibFoo.jl), as well as other packages that use this package for binary installation such as 

## Usage

To download and install a package into a `Prefix`, the basic syntax is:
```julia
prefix = Prefix("./deps")
install(url, tarball_hash; prefix=prefix)
```

It is recommended to inspect examples for a fuller treatment of installation, the [`LibFoo.jl` package within this repository](test/LibFoo.jl) contains a [`deps/build.jl` file](test/LibFoo.jl/deps/build.jl) that may be instructive.

To actually generate the tarballs that are installed by this package, check out the [`BinaryBuilder.jl` package](https://github.com/JuliaPackaging/BinaryBuilder.jl).

## Miscellanea

* This package contains a `run(::Cmd)` wrapper class named `OutputCollector` that captures the output of shell commands, and in particular, captures the `stdout` and `stderr` streams separately, colorizing, buffering and timestamping appropriately to provide seamless printing of shell output in a consistent and intuitive way.  Critically, it also allows for saving of the captured streams to log files, a very useful feature for [`BinaryBuilder.jl`](https://github.com/JuliaPackaging/BinaryBuilder.jl), which makes extensive use of this class, however all commands run by `BinaryProvider.jl` also use this same mechanism to provide coloring of `stderr`.

* When providing `ExecutableProduct`s to a client package, `BinaryProvider` will automatically append Julia's private library directory to `LD_LIBRARY_PATH` on Linux, and `DYLD_LIBRARY_PATH` on macOS.  This is due to the fact that the compiled binaries may be dependent on libraries such as `libgfortran`, which ship with Julia and must be found by the system linker or else the binaries will not function.  If you wish to use the binaries outside of Julia, you may need to override those environment variables in a similar fashion; see the generated `deps.jl` file for the `check_deps()` function where the precise overriding values can be found.