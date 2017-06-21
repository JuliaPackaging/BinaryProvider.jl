# BinaryProvider

[![Build Status](https://travis-ci.org/JuliaPackaging/BinaryProvider.jl.svg?branch=master)](https://travis-ci.org/JuliaPackaging/BinaryProvider.jl)

[![Coverage Status](https://coveralls.io/repos/JuliaPackaging/BinaryProvider.jl/badge.svg?branch=master&service=github)](https://coveralls.io/github/JuliaPackaging/BinaryProvider.jl?branch=master)

[![codecov.io](http://codecov.io/github/JuliaPackaging/BinaryProvider.jl/coverage.svg?branch=master)](http://codecov.io/github/JuliaPackaging/BinaryProvider.jl?branch=master)


# Work in progress

Sketching out a reliable binary provider!

# `@staticfloat`'s second draft

This (modified) initial draft eschews symlinks in favor of simply unpacking
archives into a single prefix.  Thank Windows for killing the elegant symlink
solution for file management.  In its place is an installation receipt-based
system that attempts to keep track of all files installed by a particular
package within a prefix.

A `Prefix` object represents a prefix that things can be installed into, by
default all operations occur within the `global_prefix`, stored within the
`BinaryProvider` package tree, however the general philosophy this package was
designed for is that each Julia package that wishes to install binaries using
this package will install into its own prefix directory a la BinDeps.  This will
provide separation on a per-Julia package basis.
