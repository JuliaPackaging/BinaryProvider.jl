# BinaryProvider

[![Build Status](https://travis-ci.org/staticfloat/BinaryProvider.jl.svg?branch=master)](https://travis-ci.org/JuliaPackaging/BinaryProvider.jl)

[![Coverage Status](https://coveralls.io/repos/staticfloat/BinaryProvider.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/JuliaPackaging/BinaryProvider.jl?branch=master)

[![codecov.io](http://codecov.io/github/JuliaPackaging/BinaryProvider.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaPackaging/BinaryProvider.jl?branch=master)

# `@staticfloat`'s third draft

This draft is intended to work alongside [`BinDeps2.jl`](https://github.com/staticfloat/BinDeps2.jl); this package holds all logic necessary to download and unpack tarballs into `Prefix`es, where a `Prefix` is a folder with a particular directory structure similar in spirit to the linux filesystem hierarchy, with a `bin` folder, a `lib` folder (on non-Windows platforms), etc...

## Basic concepts

TODO

## Usage

To download and install a package into a `Prefix`, the basic syntax is:
```julia
prefix = Prefix("./deps")
install(url, tarball_hash; prefix=prefix)
```

It is recommended to inspect examples for a fuller treatment of installation, the [`LibFoo.jl` package within this repository](test/LibFoo.jl) contains a [`deps/build.jl` file](test/LibFoo.jl/deps/build.jl) that may be instructive.

## OutputCollector

This package contains a `run(::Cmd)` wrapper class named `OutputCollector` that captures the output of shell commands, and in particular, captures the `stdout` and `stderr` streams separately, colorizing and buffering appropriately to provide seamless printing of shell output in a consistent and intuitive way.  Critically, it also allows for saving of the captured streams to log files, a very useful feature for `BinDeps2.jl`, which makes extensive use of this class, however all commands run by `BinaryProvider.jl` also use this same mechanism to provide coloring of `stderr`.