using BinaryProvider
using Base.Test
using SHA

# The platform we're running on
const platform = platform_key()

# On windows, the `.exe` extension is very important
const exe_ext = is_windows() ? ".exe" : ""

# Useful command to launch `bash` on any given platform
const bash = gen_bash_cmd

# Output of a few scripts we are going to run
const simple_out = "1\n2\n3\n4\n"
const long_out = join(["$(idx)\n" for idx in 1:100], "")

@testset "OutputCollector" begin
    cd("output_tests") do
        # Collect the output of `simple.sh``
        oc = OutputCollector(bash(`./simple.sh`))

        # Ensure we can wait on it and it exited properly
        @test wait(oc)

        # Ensure further waits are fast and still return 0
        let
            tstart = time()
            @test wait(oc)
            @test time() - tstart < 0.1
        end

        # Test that we can merge properly
        @test merge(oc) == simple_out

        # Test that merging twice works
        @test merge(oc) == simple_out

        # Test that `tail()` gives the same output as well
        @test tail(oc) == simple_out

        # Test that colorization works
        let
            red = Base.text_colors[:red]
            def = Base.text_colors[:default]
            gt = "1\n$(red)2\n$(def)3\n4\n"
            @test merge(oc; colored=true) == gt
            @test tail(oc; colored=true) == gt
        end

        # Test that we can grab stdout and stderr separately
        @test stdout(oc) == "1\n3\n4\n"
        @test stderr(oc) == "2\n"
    end

    # Next test a much longer output program
    cd("output_tests") do
        oc = OutputCollector(bash(`./long.sh`))

        # Test that it worked, we can read it, and tail() works
        @test wait(oc)
        @test merge(oc) == long_out
        @test tail(oc; len=10) == join(["$(idx)\n" for idx in 91:100], "")
    end

    # Next, test a command that fails
    cd("output_tests") do
        oc = OutputCollector(bash(`./fail.sh`))

        @test !wait(oc)
        @test merge(oc) == "1\n2\n"
    end

    # Next, test a command that kills itself (NOTE: This doesn't work on windows.  sigh.)
    @static if !is_windows()
        cd("output_tests") do
            oc = OutputCollector(bash(`./kill.sh`))

            @test !wait(oc)
            @test merge(oc) == "1\n2\n"
        end
    end

    # Next, test reading the output of a pipeline()
    grepline = pipeline(bash(`-c 'printf "Hello\nWorld\nJulia"'`), `grep ul`)
    oc = OutputCollector(grepline)

    @test wait(oc)
    @test merge(oc) == "Julia\n"
end

@testset "Prefix" begin
    mktempdir() do temp_dir
        prefix = Prefix(temp_dir)

        # Test that it's taking the absolute path
        @test prefix.path == abspath(temp_dir)

        # Test that `bindir()` works
        mkpath(joinpath(bindir(prefix)))
        @test isdir(joinpath(bindir(prefix)))

        # Create a little script within the bindir to ensure we can run it
        ppt_path = joinpath(bindir(prefix), "prefix_path_test.sh")
        open(ppt_path, "w") do f
            write(f, "#!/bin/bash\n")
            write(f, "echo yolo\n")
        end
        chmod(ppt_path, 0o775)

        # Test that activation adds certain paths to our environment variables
        activate(prefix)

        # PATH[1] should be "<prefix>/bin" now
        @test BinaryProvider.split_PATH()[1] == bindir(prefix)
        @test Libdl.DL_LOAD_PATH[1] == libdir(prefix)

        # Test we can run the script we dropped within this prefix.  Once again,
        # something about Windows | busybox | Julia won't pick this up even though
        # the path clearly points to the file.  :(
        @static if !is_windows()
            @test success(bash(`prefix_path_test.sh`))
        end
        
        # Now deactivate and make sure that all traces are gone
        deactivate(prefix)
        @test BinaryProvider.split_PATH()[1] != bindir(prefix)
        @test Libdl.DL_LOAD_PATH[1] != libdir(prefix)
    end
end

@testset "Dependency Results" begin
    temp_prefix() do prefix
        f = FileResult(joinpath(bindir(prefix), "fooifier"))
        @test !satisfied(f; verbose=true)
        l = LibraryResult(joinpath(libdir(prefix), "libfoo.$(Libdl.dlext)"))
        @test !satisfied(l, verbose=true)
        mkpath(dirname(l.path))
        touch(l.path)
        @test !satisfied(l, verbose=true)
    end
end

@testset "Packaging" begin
    # Clear out previous build products
    for f in readdir(".")
        if !endswith(f, ".tar.gz")
            continue
        end
        rm(f; force=true)
    end
    
    # Gotta set this guy up beforehand
    tarball_path = nothing

    temp_prefix() do prefix
        # Create random files
        mkpath(bindir(prefix))
        mkpath(libdir(prefix))
        bar_path = joinpath(bindir(prefix), "bar.sh")
        open(bar_path, "w") do f
            write(f, "#!/bin/bash\n")
            write(f, "echo yolo\n")
        end
        baz_path = joinpath(libdir(prefix), "baz.so")
        open(baz_path, "w") do f
            write(f, "this is not an actual .so\n")
        end
        
        # Next, package it up as a .tar.gz file
        tarball_path = package(prefix, "./libfoo"; verbose=true)
        @test isfile(tarball_path)

        # Test that packaging into a file that already exists fails
        @test_throws ErrorException package(prefix, "./libfoo")
    end

    tarball_hash = open(tarball_path, "r") do f
        bytes2hex(sha256(f))
    end

    # Test that we can inspect the contents of the tarball
    contents = list_tarball_files(tarball_path)
    const libdir_name = is_windows() ? "bin" : "lib"
    @test joinpath("bin", "bar.sh") in contents
    @test joinpath(libdir_name, "baz.so") in contents

    # Install it within a new Prefix
    temp_prefix() do prefix
        # Install the thing
        @test install(tarball_path, tarball_hash; prefix=prefix, verbose=true)

        # Ensure we can use it
        bar_path = joinpath(bindir(prefix), "bar.sh")
        baz_path = joinpath(libdir(prefix), "baz.so")

        # Ask for the manifest that contains these files to ensure it works
        manifest_path = manifest_for_file(bar_path; prefix=prefix)
        @test isfile(manifest_path)
        manifest_path = manifest_for_file(baz_path; prefix=prefix)
        @test isfile(manifest_path)

        # Ensure that manifest_for_file doesn't work on nonexistant files
        @test_throws ErrorException manifest_for_file("nonexistant"; prefix=prefix)

        # Ensure that manifest_for_file doesn't work on orphan files
        orphan_path = joinpath(bindir(prefix), "orphan_file")
        touch(orphan_path)
        @test isfile(orphan_path)
        @test_throws ErrorException manifest_for_file(orphan_path; prefix=prefix)

        # Ensure that trying to install again over our existing files is an error
        @test_throws ErrorException install(tarball_path, tarball_path; prefix=prefix)

        # Ensure we can uninstall this tarball
        @test uninstall(manifest_path; verbose=true)
        @test !isfile(bar_path)
        @test !isfile(baz_path)
        @test !isfile(manifest_path)

        # Ensure that we don't want to install tarballs from other platforms
        cp(tarball_path, "./libfoo_juliaos64.tar.gz")
        @test_throws ErrorException install("./libfoo_juliaos64.tar.gz", tarball_hash; prefix=prefix)
        rm("./libfoo_juliaos64.tar.gz"; force=true)

        # Ensure that hash mismatches throw errors
        fake_hash = reverse(tarball_hash)
        @test_throws ErrorException install(tarball_path, fake_hash; prefix=prefix)
    end

    rm(tarball_path; force=true)
end


# Use `build_libfoo_tarball.jl` in the BinDeps2.jl repository to generate more of these
bin_prefix = "https://github.com/staticfloat/small_bin/raw/74b7fd81e3fbc8963b14b0ebbe5421e270d8bdcf"
libfoo_downloads = Dict(
    :linux32 =>      ("$bin_prefix/libfoo.i686-linux-gnu.tar.gz",
                      "1398353bcbbd88338189ece9c1d6e7c508df120bc4f93afbaed362a9f91358ff"),
    :linux64 =>      ("$bin_prefix/libfoo.x86_64-linux-gnu.tar.gz",
                      "b9d57a6e032a56b1f8641771fa707523caa72f1a2e322ab99eeeb011f13ad9f3"),
    :linuxaarch64 => ("$bin_prefix/libfoo.aarch64-linux-gnu.tar.gz",
                      "19d9da0e6e7fb506bf4889eb91e936fda43493a39cd4fd7bd5d65506cede6f95"),
    :linuxarmv7l =>  ("$bin_prefix/libfoo.arm-linux-gnueabihf.tar.gz",
                      "8e33c1a0e091e6e5b8fcb902e5d45329791bb57763ee9cbcde49c1ec9bd8532a"),
    :linuxppc64le => ("$bin_prefix/libfoo.powerpc64le-linux-gnu.tar.gz",
                      "b48a64d48be994ec99b1a9fb60e0af7f4415a57596518cb90a340987b79fad81"),
    :mac64 =>        ("$bin_prefix/libfoo.x86_64-apple-darwin14.tar.gz",
                      "661b71edb433ab334b0fef70db3b5c45d35f2b3bee0d244f54875f1ec899c10f"),
    :win32 =>        ("$bin_prefix/libfoo.i686-w64-mingw32.tar.gz",
                      "3d4a8d4bf0169007a42d809a1d560083635b1540a1bc4a42108841dcb6d2aaea"),
    :win64 =>        ("$bin_prefix/libfoo.x86_64-w64-mingw32.tar.gz",
                      "2d08fbc9a534cd021f36b6bbe86ddabb2dafbedeb589581240aa4a8c5b896055"),
)

@testset "Downloading" begin
    temp_prefix() do prefix
        if !haskey(libfoo_downloads, platform)
            warn("Platform $platform does not have a libfoo download, skipping download tests")
        else
            # Test a good download works
            url, hash = libfoo_downloads[platform]
            @test install(url, hash; prefix=prefix, verbose=true)

            activate(prefix) do
                fooifier_path = "fooifier$(exe_ext)"
                libfoo_path = "libfoo.$(Libdl.dlext)"

                # We know that foo(a, b) returns 2*a^2 - b
                result = 2*2.2^2 - 1.1
            
                # Test that we can invoke fooifier
                @test !success(`$fooifier_path`)
                @test success(`$fooifier_path 1.5 2.0`)
                @test parse(Float64,readchomp(`$fooifier_path 2.2 1.1`)) ≈ result
            
                # Test that we can dlopen() libfoo and invoke it directly
                libfoo = Libdl.dlopen_e(libfoo_path)
                @test libfoo != C_NULL
                foo = Libdl.dlsym_e(libfoo, :foo)
                @test foo != C_NULL
                @test ccall(foo, Cdouble, (Cdouble, Cdouble), 2.2, 1.1) ≈ result
                Libdl.dlclose(libfoo)
            end
        end

        # Test a bad download fails properly
        bad_url = "http://localhost:1/this_is_not_a_file_linux64.tar.gz"
        bad_hash = "0"^64
        @test_throws ErrorException install(bad_url, bad_hash; prefix=prefix, verbose=true)
    end
end

# @testset "BinDeps integration" begin
#     mktempdir() do tmpdir
#         # Write out a fake build.jl that just tells BinDeps to use the
#         # BinaryProvider machinery to install libtest
#         open(joinpath(tmpdir, "build.jl"), "w") do file
#             write(file, """
# using BinDeps
# using BinaryProvider

# @BinDeps.setup

# libtest = library_dependency("libtest")
# @BP_provides("libtest", "$(escape_string(libtest_archive))", "$libtest_sha256", libtest)

# @BinDeps.install Dict(:libtest => :bindeps_libtest)
# """)
#         end

#         run(`$(Base.julia_cmd()) $(joinpath(tmpdir, "build.jl"))`)

#         # Ensure that deps.jl was built
#         @test isfile(joinpath(tmpdir, "deps.jl"))

#         # Ensure that deps.jl contains the path to an installed libtest
#         include(joinpath(tmpdir, "deps.jl"))
#         @test isfile(bindeps_libtest)

#         # Ensure that libtest is installed within this tmpdir
#         info("bindeps_libtest: $(bindeps_libtest)")
#         info("tmpdir: $(tmpdir)")
#         @test startswith(bindeps_libtest, tmpdir)
#     end
# end