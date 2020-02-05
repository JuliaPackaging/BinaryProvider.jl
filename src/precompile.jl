function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(BinaryProvider.safe_isfile), String})
    precompile(Tuple{typeof(BinaryProvider.info_onchange), String, String, Int64})
    precompile(Tuple{typeof(BinaryProvider.libdir), BinaryProvider.Prefix})
    precompile(Tuple{typeof(BinaryProvider.readuntil_many), Base.Pipe, Array{Char, 1}})
    precompile(Tuple{typeof(BinaryProvider.locate), BinaryProvider.ExecutableProduct})
    precompile(Tuple{typeof(BinaryProvider.package), BinaryProvider.Prefix, String, Base.VersionNumber})
    precompile(Tuple{typeof(BinaryProvider.libdir), BinaryProvider.Prefix, BinaryProvider.Linux})
    precompile(Tuple{typeof(BinaryProvider.libdir), BinaryProvider.Prefix, BinaryProvider.MacOS})
    precompile(Tuple{typeof(BinaryProvider.locate), BinaryProvider.LibraryProduct})
    precompile(Tuple{typeof(BinaryProvider.collect_stdout), BinaryProvider.OutputCollector})
    precompile(Tuple{typeof(BinaryProvider.collect_stderr), BinaryProvider.OutputCollector})
end
