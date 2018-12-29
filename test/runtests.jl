using BinaryProvider
using Test
using Libdl
using Pkg
using SHA

# The platform we're running on
const platform = platform_key_abi()

# Useful command to launch `sh` on any platform
const sh = gen_sh_cmd

# Output of a few scripts we are going to run
const simple_out = "1\n2\n3\n4\n"
const long_out = join(["$(idx)\n" for idx in 1:100], "")
const newlines_out = join(["marco$(d)polo$(d)" for d in ("\n","\r","\r\n")], "")

# Explicitly probe platform engines in verbose mode to get coverage and make
# CI debugging easier
BinaryProvider.probe_platform_engines!(;verbose=true)

# Helper function to strip out color codes from strings to make it easier to
# compare output within tests that has been colorized
function strip_colorization(s)
    return replace(s, r"(\e\[\d+m)"m => "")
end

# Helper function to strip out log timestamps from strings
function strip_timestamps(s)
    return replace(s, r"^(\[\d\d:\d\d:\d\d\] )"m => "")
end

@testset "OutputCollector" begin
    cd("output_tests") do
        # Collect the output of `simple.sh``
        oc = OutputCollector(sh(`./simple.sh`))

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
        @test collect_stdout(oc) == "1\n3\n4\n"
        @test collect_stderr(oc) == "2\n"
    end

    # Next test a much longer output program
    cd("output_tests") do
        oc = OutputCollector(sh(`./long.sh`))

        # Test that it worked, we can read it, and tail() works
        @test wait(oc)
        @test merge(oc) == long_out
        @test tail(oc; len=10) == join(["$(idx)\n" for idx in 91:100], "")
    end

    # Next, test a command that fails
    cd("output_tests") do
        oc = OutputCollector(sh(`./fail.sh`))

        @test !wait(oc)
        @test merge(oc) == "1\n2\n"
    end

    # Next, test a command that kills itself (NOTE: This doesn't work on windows.  sigh.)
    @static if !Sys.iswindows()
        cd("output_tests") do
            oc = OutputCollector(sh(`./kill.sh`))

            @test !wait(oc)
            @test collect_stdout(oc) == "1\n2\n"
        end
    end

    # Next, test reading the output of a pipeline()
    grepline = pipeline(
        sh(`'printf "Hello\nWorld\nJulia\n"'`),
        sh(`'while read line; do case $line in *ul*) echo $line; esac; done'`)
    )
    oc = OutputCollector(grepline)

    @test wait(oc)
    @test merge(oc) == "Julia\n"

    # Next, test that \r and \r\n are treated like \n
    cd("output_tests") do
        oc = OutputCollector(sh(`./newlines.sh`))

        @test wait(oc)
        @test collect_stdout(oc) == newlines_out
    end

    # Next, test that tee'ing to a stream works
    cd("output_tests") do
        ios = IOBuffer()
        oc = OutputCollector(sh(`./simple.sh`); tee_stream=ios, verbose=true)
        @test wait(oc)
        @test merge(oc) == simple_out

        seekstart(ios)
        tee_out = String(read(ios))
        tee_out = strip_colorization(tee_out)
        tee_out = strip_timestamps(tee_out)
        @test tee_out == simple_out
    end

    # Also test that auto-tail'ing can be can be directed to a stream
    cd("output_tests") do
        ios = IOBuffer()
        oc = OutputCollector(sh(`./fail.sh`); tee_stream=ios)

        @test !wait(oc)
        @test merge(oc) == "1\n2\n"
        seekstart(ios)
        tee_out = String(read(ios))
        tee_out = strip_colorization(tee_out)
        tee_out = strip_timestamps(tee_out)
        @test tee_out == "1\n2\n"
    end

    # Also test that auto-tail'ing can be turned off
    cd("output_tests") do
        ios = IOBuffer()
        oc = OutputCollector(sh(`./fail.sh`); tee_stream=ios, tail_error=false)

        @test !wait(oc)
        @test merge(oc) == "1\n2\n"

        seekstart(ios)
        @test String(read(ios)) == ""
    end
end

@testset "PlatformNames" begin
    # Ensure the platform type constructors are well behaved
    @testset "Platform constructors" begin
        @test_throws ArgumentError Linux(:not_a_platform)
        @test_throws ArgumentError Linux(:x86_64, :crazy_libc)
        @test_throws ArgumentError Linux(:x86_64, :glibc, :crazy_abi)
        @test_throws ArgumentError Linux(:x86_64, :glibc, :eabihf)
        @test_throws ArgumentError Linux(:armv7l, :glibc, :blank_abi)
        @test_throws ArgumentError MacOS(:i686)
        @test_throws ArgumentError MacOS(:x86_64, :glibc)
        @test_throws ArgumentError MacOS(:x86_64, :blank_libc, :eabihf)
        @test_throws ArgumentError Windows(:armv7l)
        @test_throws ArgumentError Windows(:x86_64, :glibc)
        @test_throws ArgumentError Windows(:x86_64, :blank_libc, :eabihf)
        @test_throws ArgumentError FreeBSD(:not_a_platform)
        @test_throws ArgumentError FreeBSD(:x86_64, :crazy_libc)
        @test_throws ArgumentError FreeBSD(:x86_64, :blank_libc, :crazy_abi)
        @test_throws ArgumentError FreeBSD(:x86_64, :blank_libc, :eabihf)
        @test_throws ArgumentError FreeBSD(:armv7l, :blank_libc, :blank_abi)
    end

    @testset "Platform properties" begin
        # Test that we can get that arch of various platforms
        @test arch(Linux(:aarch64, :musl)) == :aarch64
        @test arch(Windows(:i686)) == :i686
        @test arch(UnknownPlatform()) == :unknown
        @test arch(FreeBSD(:amd64)) == :x86_64
        @test arch(FreeBSD(:i386)) == :i686

        # Test that our platform_dlext stuff works
        @test platform_dlext(Linux(:x86_64)) == platform_dlext(Linux(:i686))
        @test platform_dlext(Windows(:x86_64)) == platform_dlext(Windows(:i686))
        @test platform_dlext(MacOS()) != platform_dlext(Linux(:armv7l))
        @test platform_dlext(FreeBSD(:x86_64)) == platform_dlext(Linux(:x86_64))
        @test platform_dlext(UnknownPlatform()) == "unknown"
        @test platform_dlext() == platform_dlext(platform)

        @test wordsize(Linux(:i686)) == wordsize(Linux(:armv7l)) == 32
        @test wordsize(MacOS()) == wordsize(Linux(:aarch64)) == 64
        @test wordsize(FreeBSD(:x86_64)) == wordsize(Linux(:powerpc64le)) == 64
        @test wordsize(UnknownPlatform()) == 0

        @test triplet(Windows(:i686)) == "i686-w64-mingw32"
        @test triplet(Linux(:x86_64, :musl)) == "x86_64-linux-musl"
        @test triplet(Linux(:armv7l, :musl)) == "arm-linux-musleabihf"
        @test triplet(Linux(:x86_64)) == "x86_64-linux-gnu"
        @test triplet(Linux(:armv7l)) == "arm-linux-gnueabihf"
        @test triplet(MacOS()) == "x86_64-apple-darwin14"
        @test triplet(FreeBSD(:x86_64)) == "x86_64-unknown-freebsd11.1"
        @test triplet(FreeBSD(:i686)) == "i686-unknown-freebsd11.1"
        @test triplet(UnknownPlatform()) == "unknown-unknown-unknown"

        @test repr(Windows(:x86_64)) == "Windows(:x86_64)"
        @test repr(Linux(:x86_64, :glibc, :blank_abi)) == "Linux(:x86_64, libc=:glibc)"
        @test repr(MacOS()) == "MacOS(:x86_64)"
        @test repr(MacOS(compiler_abi=CompilerABI(:gcc_any, :cxx11))) == "MacOS(:x86_64, compiler_abi=CompilerABI(:gcc_any, :cxx11))"
    end

    @testset "Valid DL paths" begin
        # Test some valid dynamic library paths
        @test valid_dl_path("libfoo.so.1.2.3", Linux(:x86_64))
        @test valid_dl_path("libfoo.1.2.3.so", Linux(:x86_64))
        @test valid_dl_path("libfoo-1.2.3.dll", Windows(:x86_64))
        @test valid_dl_path("libfoo.1.2.3.dylib", MacOS())
        @test !valid_dl_path("libfoo.dylib", Linux(:x86_64))
        @test !valid_dl_path("libfoo.so", Windows(:x86_64))
        @test !valid_dl_path("libfoo.dll", MacOS())
        @test !valid_dl_path("libfoo.so.1.2.3.", Linux(:x86_64))
        @test !valid_dl_path("libfoo.so.1.2a.3", Linux(:x86_64))
    end

    @testset "platform_key_abi parsing" begin
        # Make sure the platform_key_abi() with explicit triplet works
        @test platform_key_abi("x86_64-linux-gnu") == Linux(:x86_64)
        @test platform_key_abi("x86_64-linux-musl") == Linux(:x86_64, libc=:musl)
        @test platform_key_abi("i686-unknown-linux-gnu") == Linux(:i686)
        @test platform_key_abi("x86_64-apple-darwin14") == MacOS()
        @test platform_key_abi("x86_64-apple-darwin17.0.0") == MacOS()
        @test platform_key_abi("armv7l-pc-linux-gnueabihf") == Linux(:armv7l)
        @test platform_key_abi("armv7l-linux-musleabihf") == Linux(:armv7l, libc=:musl)
        @test platform_key_abi("arm-linux-gnueabihf") == Linux(:armv7l)
        @test platform_key_abi("aarch64-unknown-linux-gnu") == Linux(:aarch64)
        @test platform_key_abi("powerpc64le-linux-gnu") == Linux(:powerpc64le)
        @test platform_key_abi("ppc64le-linux-gnu") == Linux(:powerpc64le)
        @test platform_key_abi("x86_64-w64-mingw32") == Windows(:x86_64)
        @test platform_key_abi("i686-w64-mingw32") == Windows(:i686)
        @test platform_key_abi("x86_64-unknown-freebsd11.1") == FreeBSD(:x86_64)
        @test platform_key_abi("i686-unknown-freebsd11.1") == FreeBSD(:i686)
        @test platform_key_abi("amd64-unknown-freebsd12.0") == FreeBSD(:x86_64)
        @test platform_key_abi("i386-unknown-freebsd10.3") == FreeBSD(:i686)

        # Test inclusion of ABI stuff
        @test platform_key_abi("x86_64-linux-gnu-gcc7") == Linux(:x86_64, compiler_abi=CompilerABI(:gcc7))
        @test platform_key_abi("x86_64-linux-gnu-gcc4-cxx11") == Linux(:x86_64, compiler_abi=CompilerABI(:gcc4, :cxx11))
        @test platform_key_abi("x86_64-linux-gnu-cxx11") == Linux(:x86_64, compiler_abi=CompilerABI(:gcc_any, :cxx11))

        # Make sure some of these things are rejected
        @test platform_key_abi("totally FREEFORM text!!1!!!1!") == UnknownPlatform()
        @test platform_key_abi("invalid-triplet-here") == UnknownPlatform()
        @test platform_key_abi("aarch64-linux-gnueabihf") == UnknownPlatform()
        @test platform_key_abi("armv7l-linux-gnu") == UnknownPlatform()
        @test platform_key_abi("x86_64-w32-mingw64") == UnknownPlatform()
    end

    @testset "platforms_match()" begin
        # Test our platform matching code
        @test BinaryProvider.platforms_match(Linux(:x86_64), Linux(:x86_64))
        @test BinaryProvider.platforms_match(Linux(:x86_64), Linux(:x86_64, compiler_abi=CompilerABI(:gcc7)))
        @test BinaryProvider.platforms_match(Linux(:x86_64, compiler_abi=CompilerABI(:gcc7)), Linux(:x86_64))

        @test !BinaryProvider.platforms_match(Linux(:x86_64), Linux(:i686))
        @test !BinaryProvider.platforms_match(Linux(:x86_64), Windows(:x86_64))
        @test !BinaryProvider.platforms_match(Linux(:x86_64), MacOS())
        @test !BinaryProvider.platforms_match(Linux(:x86_64), UnknownPlatform())
        @test !BinaryProvider.platforms_match(Linux(:x86_64, compiler_abi=CompilerABI(:gcc7)), Linux(:x86_64, compiler_abi=CompilerABI(:gcc8)))
        @test !BinaryProvider.platforms_match(Linux(:x86_64, compiler_abi=CompilerABI(:gcc7, :cxx11)), Linux(:x86_64, compiler_abi=CompilerABI(:gcc7, :cxx03)))

        # Test that :gcc4 matches with :gcc5 and :gcc6, as we only care aobut libgfortran version
        @test BinaryProvider.platforms_match(
            Linux(:x86_64; compiler_abi=CompilerABI(:gcc4)),
            Linux(:x86_64; compiler_abi=CompilerABI(:gcc5)),
        )
        @test BinaryProvider.platforms_match(
            Linux(:x86_64; compiler_abi=CompilerABI(:gcc4)),
            Linux(:x86_64; compiler_abi=CompilerABI(:gcc6)),
        )
        @test BinaryProvider.platforms_match(
            Linux(:x86_64; compiler_abi=CompilerABI(:gcc5)),
            Linux(:x86_64; compiler_abi=CompilerABI(:gcc6)),
        )
    end

    @testset "DL name/version parsing" begin
        # Make sure our version parsing code is working
        @test BinaryProvider.parse_dl_name_version("libgfortran.dll", Windows(:x86_64)) == ("libgfortran", nothing)
        @test BinaryProvider.parse_dl_name_version("libgfortran-3.dll", Windows(:x86_64)) == ("libgfortran", v"3")
        @test BinaryProvider.parse_dl_name_version("libgfortran-3.4.dll", Windows(:x86_64)) == ("libgfortran", v"3.4")
        @test BinaryProvider.parse_dl_name_version("libgfortran-3.4a.dll", Windows(:x86_64)) == ("libgfortran-3.4a", nothing)
        @test_throws ArgumentError BinaryProvider.parse_dl_name_version("libgfortran", Windows(:x86_64))
        @test BinaryProvider.parse_dl_name_version("libgfortran.dylib", MacOS(:x86_64)) == ("libgfortran", nothing)
        @test BinaryProvider.parse_dl_name_version("libgfortran.3.dylib", MacOS(:x86_64)) == ("libgfortran", v"3")
        @test BinaryProvider.parse_dl_name_version("libgfortran.3.4.dylib", MacOS(:x86_64)) == ("libgfortran", v"3.4")
        @test BinaryProvider.parse_dl_name_version("libgfortran.3.4a.dylib", MacOS(:x86_64)) == ("libgfortran.3.4a", nothing)
        @test_throws ArgumentError BinaryProvider.parse_dl_name_version("libgfortran", MacOS(:x86_64))
        @test BinaryProvider.parse_dl_name_version("libgfortran.so", Linux(:x86_64)) == ("libgfortran", nothing)
        @test BinaryProvider.parse_dl_name_version("libgfortran.so.3", Linux(:x86_64)) == ("libgfortran", v"3")
        @test BinaryProvider.parse_dl_name_version("libgfortran.so.3.4", Linux(:x86_64)) == ("libgfortran", v"3.4")
        @test_throws ArgumentError BinaryProvider.parse_dl_name_version("libgfortran.so.3.4a", Linux(:x86_64))
        @test_throws ArgumentError BinaryProvider.parse_dl_name_version("libgfortran", Linux(:x86_64))

        for p in [Windows(:i686), Linux(:armv7l, :musl), FreeBSD(:x86_64), MacOS(compiler_abi=CompilerABI(:gcc4))]
            fakepath = "/path/to/nowhere/Thingo.v1.2.3." * triplet(p) * ".tar.gz"
            @test extract_platform_key(fakepath) == p
            @test extract_name_version_platform_key(fakepath) == ("Thingo", v"1.2.3", p)
        end

        # This failed on me a while back.  NEVER AGAIN.
        @test extract_name_version_platform_key("libjpeg.v9.0.0-b.x86_64-apple-darwin14.tar.gz") == ("libjpeg", v"9.0.0-b", MacOS())
    end

    @testset "Sys.is* overloading" begin
        # Test that we can indeed ask if something is linux or windows, etc...
        @test Sys.islinux(Linux(:aarch64))
        @test !Sys.islinux(Windows(:x86_64))
        @test Sys.iswindows(Windows(:i686))
        @test !Sys.iswindows(Linux(:x86_64))
        @test Sys.isapple(MacOS())
        @test !Sys.isapple(Linux(:powerpc64le))
        @test Sys.isbsd(MacOS())
        @test Sys.isbsd(FreeBSD(:x86_64))
        @test !Sys.isbsd(Linux(:powerpc64le, :musl))
    end

    @testset "Compiler ABI detection" begin
        @test BinaryProvider.detect_libgfortran_abi("libgfortran.so.5", Linux(:x86_64)) == :gcc8
        @test BinaryProvider.detect_libgfortran_abi("libgfortran.4.dylib", MacOS()) == :gcc7
        @test BinaryProvider.detect_libgfortran_abi("libgfortran-3.dll", Windows(:x86_64)) == :gcc4
        @test BinaryProvider.detect_libgfortran_abi("blah.so", Linux(:aarch64)) == :gcc_any
    end
end

@testset "Prefix" begin
    mktempdir() do temp_dir
        prefix = Prefix(temp_dir)

        # Test that it's taking the absolute path
        @test prefix.path == abspath(temp_dir)

        # Test that `bindir()`, `libdir()` and `includedir()` all work
        for dir in unique([bindir(prefix), libdir(prefix), includedir(prefix)])
            @test !isdir(dir)
            mkpath(dir)
        end

        # Create a little script within the bindir to ensure we can run it
        ppt_path = joinpath(bindir(prefix), "prefix_path_test.sh")
        open(ppt_path, "w") do f
            write(f, "#!/bin/sh\n")
            write(f, "echo yolo\n")
        end
        chmod(ppt_path, 0o775)

        # Test that our `withenv()` stuff works.  :D
        withenv(prefix) do
            @test startswith(ENV["PATH"], bindir(prefix))

            if !Sys.iswindows()
                envname = Sys.isapple() ? "DYLD_FALLBACK_LIBRARY_PATH" : "LD_LIBRARY_PATH"
                @test startswith(ENV[envname], libdir(prefix))
                private_libdir = abspath(joinpath(Sys.BINDIR, Base.PRIVATE_LIBDIR))
                @test endswith(ENV[envname], private_libdir)

                # Test we can run the script we dropped within this prefix.
                # Once again, something about Windows | busybox | Julia won't
                # pick this up even though the path clearly points to the file.
                @test success(sh(`$(ppt_path)`))
                @test success(sh(`prefix_path_test.sh`))
            end
        end
        
        # Test that we can control libdir() via platform arguments
        @test libdir(prefix, Linux(:x86_64)) == joinpath(prefix, "lib")
        @test libdir(prefix, Windows(:x86_64)) == joinpath(prefix, "bin")
    end
end

@testset "Tarball listing parsing" begin
    fake_7z_output = """
	7-Zip [64] 9.20  Copyright (c) 1999-2010 Igor Pavlov  2010-11-18
	p7zip Version 9.20 (locale=en_US.UTF-8,Utf16=on,HugeFiles=on,4 CPUs)

	Listing archive:

	--
	Path =
	Type = tar

	   Date      Time    Attr         Size   Compressed  Name
	------------------- ----- ------------ ------------  ------------------------
	2017-04-10 14:45:00 D....            0            0  bin
	2017-04-10 14:44:59 .....          211          512  bin/socrates
	------------------- ----- ------------ ------------  ------------------------
									   211          512  1 files, 1 folders
	"""
	@test parse_7z_list(fake_7z_output) == ["bin/socrates"]

	fake_tar_output = """
	bin/
	bin/socrates
	"""
	@test parse_tar_list(fake_tar_output) == ["bin/socrates"]

end

@testset "Products" begin
    temp_prefix() do prefix
        # Test that basic satisfication is not guaranteed
        e_path = joinpath(bindir(prefix), "fooifier")
        l_path = joinpath(libdir(prefix), "libfoo.$(Libdl.dlext)")
        e = ExecutableProduct(prefix, "fooifier", :fooifier)
        ef = FileProduct(prefix, joinpath("bin", "fooifier"), :fooifier)
        l = LibraryProduct(prefix, "libfoo", :libfoo)
        lf = FileProduct(l_path, :libfoo)

        @test !satisfied(e; verbose=true)
        @test !satisfied(ef; verbose=true)
        @test !satisfied(l, verbose=true)
        @test !satisfied(l, verbose=true, isolate=true)
        @test !satisfied(lf, verbose=true)

        # Test that simply creating a file that is not executable doesn't
        # satisfy an Executable Product (and say it's on Linux so it doesn't
        # complain about the lack of an .exe extension)
        mkpath(bindir(prefix))
        touch(e_path)
        @test satisfied(ef, verbose=true)
        @static if !Sys.iswindows()
            # Windows doesn't care about executable bit, grumble grumble
            @test !satisfied(e, verbose=true, platform=Linux(:x86_64))
        end

        # Make it executable and ensure this does satisfy the Executable
        chmod(e_path, 0o777)
        @test satisfied(e, verbose=true, platform=Linux(:x86_64))

        # Remove it and add a `$(path).exe` version to check again, this
        # time saying it's a Windows executable
        Base.rm(e_path; force=true)
        touch("$(e_path).exe")
        chmod("$(e_path).exe", 0o777)
        @test locate(e, platform=Windows(:x86_64)) == "$(e_path).exe"

        # Test that simply creating a library file doesn't satisfy it if we are
        # testing something that matches the current platform's dynamic library
        # naming scheme, because it must be `dlopen()`able.
        mkpath(libdir(prefix))
        touch(l_path)
        @test satisfied(lf, verbose=true)
        @test !satisfied(l, verbose=true)
        @test satisfied(lf, verbose=true, isolate=true)
        @test !satisfied(l, verbose=true, isolate=true)

        # But if it is from a different platform, simple existence will be
        # enough to satisfy a LibraryProduct
        @static if Sys.iswindows()
            p = Linux(:x86_64)
            mkpath(libdir(prefix, p))
            l_path = joinpath(libdir(prefix, p), "libfoo.so")
            touch(l_path)
            @test satisfied(l, verbose=true, platform=p)
            @test satisfied(l, verbose=true, platform=p, isolate=true)

            # Check LibraryProduct objects with explicit directory paths
            ld = LibraryProduct(libdir(prefix, p), "libfoo", :libfoo)
            @test satisfied(ld, verbose=true, platform=p)
            @test satisfied(ld, verbose=true, platform=p, isolate=true)
        else
            p = Windows(:x86_64)
            mkpath(libdir(prefix, p))
            l_path = joinpath(libdir(prefix, p), "libfoo.dll")
            touch(l_path)
            @test satisfied(l, verbose=true, platform=p)
            @test satisfied(l, verbose=true, platform=p, isolate=true)
            
            # Check LibraryProduct objects with explicit directory paths
            ld = LibraryProduct(libdir(prefix, p), "libfoo", :libfoo)
            @test satisfied(ld, verbose=true, platform=p)
            @test satisfied(ld, verbose=true, platform=p, isolate=true)
        end
    end

    # Ensure that the test suite thinks that these libraries are foreign
    # so that it doesn't try to `dlopen()` them:
    foreign_platform = if platform == Linux(:aarch64)
        # Arbitrary architecture that is not dlopen()'able
        Linux(:powerpc64le)
    else
        # If we're not Linux(:aarch64), then say the libraries are
        Linux(:aarch64)
    end

    # Test for valid library name permutations
    for ext in ["1.so", "so", "so.1", "so.1.2", "so.1.2.3"]
        temp_prefix() do prefix
            l_path = joinpath(libdir(prefix, foreign_platform), "libfoo.$ext")
            l = LibraryProduct(prefix, "libfoo", :libfoo)
            mkdir(dirname(l_path))
            touch(l_path)
            @test satisfied(l; verbose=true, platform=foreign_platform)
        end
    end

    # Test for invalid library name permutations
    for ext in ["so.1.2.3a", "so.1.a"]
        temp_prefix() do prefix
            l_path = joinpath(libdir(prefix, foreign_platform), "libfoo.$ext")
            l = LibraryProduct(prefix, "libfoo", :libfoo)
            mkdir(dirname(l_path))
            touch(l_path)
            @test !satisfied(l; verbose=true, platform=foreign_platform)
        end
    end

    # Test for proper repr behavior
    temp_prefix() do prefix
        l = LibraryProduct(prefix, "libfoo", :libfoo)
        @test repr(l) == "LibraryProduct(prefix, $(repr(["libfoo"])), :libfoo)"
        l = LibraryProduct(libdir(prefix), ["libfoo", "libfoo2"], :libfoo)
        @test repr(l) == "LibraryProduct($(repr(libdir(prefix))), $(repr(["libfoo", "libfoo2"])), :libfoo)"

        e = ExecutableProduct(prefix, "fooifier", :fooifier)
        @test repr(e) == "ExecutableProduct(prefix, \"fooifier\", :fooifier)"
        e = ExecutableProduct(joinpath(bindir(prefix), "fooifier"), :fooifier)
        @test repr(e) == "ExecutableProduct($(repr(joinpath(bindir(prefix), "fooifier"))), :fooifier)"

        f = FileProduct(prefix, joinpath("etc", "fooifier"), :foo_conf)
        @test repr(f) == "FileProduct(prefix, $(repr(joinpath("etc", "fooifier"))), :foo_conf)"

        f = FileProduct(joinpath(prefix, "etc", "foo.conf"), :foo_conf)
        @test repr(f) == "FileProduct($(repr(joinpath(prefix, "etc", "foo.conf"))), :foo_conf)"
    end

    # Test that FileProduct's can have `${target}` within their paths:
    temp_prefix() do prefix
        multilib_dir = joinpath(prefix, "foo", triplet(platform))
        mkpath(multilib_dir)
        touch(joinpath(multilib_dir, "bar"))

        for path in ("foo/\$target/bar", "foo/\${target}/bar")
            f = FileProduct(prefix, path, :bar)
            @test satisfied(f; verbose=true, platform=platform)
        end
    end
end

@testset "Packaging" begin
    # Clear out previous build products
    for f in readdir(".")
        if !endswith(f, ".tar.gz") && !endswith(f, ".sha256")
            continue
        end
        Base.rm(f; force=true)
    end

    # Gotta set this guy up beforehand
    tarball_path = nothing
    tarball_hash = nothing

    temp_prefix() do prefix
        # Create random files
        mkpath(bindir(prefix))
        mkpath(libdir(prefix))
        mkpath(joinpath(prefix, "etc"))
        bar_path = joinpath(bindir(prefix), "bar.sh")
        open(bar_path, "w") do f
            write(f, "#!/bin/sh\n")
            write(f, "echo yolo\n")
        end
        baz_path = joinpath(libdir(prefix), "baz.so")
        open(baz_path, "w") do f
            write(f, "this is not an actual .so\n")
        end

        qux_path = joinpath(prefix, "etc", "qux.conf")
        open(qux_path, "w") do f
            write(f, "use_julia=true\n")
        end

        # Next, package it up as a .tar.gz file
        tarball_path, tarball_hash = package(prefix, "./libfoo", v"1.0.0"; verbose=true)
        @test isfile(tarball_path)

        # Check that we are calculating the hash properly
        tarball_hash_check = open(tarball_path, "r") do f
            bytes2hex(sha256(f))
        end
        @test tarball_hash_check == tarball_hash

        # Test that packaging into a file that already exists fails
        @test_throws ErrorException package(prefix, "./libfoo", v"1.0.0")
    end

    # Test that we can inspect the contents of the tarball
    contents = list_tarball_files(tarball_path)
    libdir_name = Sys.iswindows() ? "bin" : "lib"
    @test joinpath("bin", "bar.sh") in contents
    @test joinpath(libdir_name, "baz.so") in contents
    @test joinpath("etc", "qux.conf") in contents

    # Install it within a new Prefix
    temp_prefix() do prefix
        # Install the thing
        @test install(tarball_path, tarball_hash; prefix=prefix, verbose=true)

        # Ensure we can use it
        bar_path = joinpath(bindir(prefix), "bar.sh")
        baz_path = joinpath(libdir(prefix), "baz.so")
        qux_path = joinpath(prefix, "etc", "qux.conf")

        @test isfile(bar_path)
        @test isfile(baz_path)
        @test isfile(qux_path)

        # Ask for the manifest that contains these files to ensure it works
        manifest_path = manifest_for_file(bar_path; prefix=prefix)
        @test isfile(manifest_path)
        manifest_path = manifest_for_file(baz_path; prefix=prefix)
        @test isfile(manifest_path)
        manifest_path = manifest_for_file(qux_path; prefix=prefix)
        @test isfile(manifest_path)

        # Ensure that manifest_for_file doesn't work on nonexistent files
        @test_throws ErrorException manifest_for_file("nonexistent"; prefix=prefix)

        # Ensure that manifest_for_file doesn't work on orphan files
        orphan_path = joinpath(bindir(prefix), "orphan_file")
        touch(orphan_path)
        @test isfile(orphan_path)
        @test_throws ErrorException manifest_for_file(orphan_path; prefix=prefix)

        # Ensure that trying to install again over our existing files is an error
        @test_throws ErrorException install(tarball_path, tarball_hash; prefix=prefix)

        # Ensure we can uninstall this tarball
        @test isinstalled(tarball_path, tarball_hash; prefix=prefix)
        Base.rm(bar_path)
        @test !isinstalled(tarball_path, tarball_hash; prefix=prefix)
        @test uninstall(manifest_path; verbose=true)
        @test !isinstalled(tarball_path, tarball_hash; prefix=prefix)
        @test !isfile(bar_path)
        @test !isfile(baz_path)
        @test !isfile(qux_path)
        @test !isfile(manifest_path)

        # Also make sure that it removes the entire etc directory since it's now empty
        @test !isdir(dirname(qux_path))

        # Ensure that we don't want to install tarballs from other platforms
        other_path = "./libfoo.v1.0.0.x86_64-juliaos-chartreuse.tar.gz"
        cp(tarball_path, other_path)
        @test_throws ArgumentError install(other_path, tarball_hash; prefix=prefix, ignore_platform=false)
        Base.rm(other_path; force=true)

        # Ensure that hash mismatches throw errors
        fake_hash = reverse(tarball_hash)
        @test_throws ErrorException install(tarball_path, fake_hash; prefix=prefix)
    end

    # Get a valid platform tarball name that is not our native platform
    other_platform = Linux(:x86_64)
    if BinaryProvider.platforms_match(platform, Linux(:x86_64))
        other_platform = MacOS()
    end
    new_tarball_path = "libfoo.v1.0.0.$(triplet(other_platform)).tar.gz"
    cp(tarball_path, new_tarball_path)

    # Also generate a totally bogus tarball pathname
    bogus_tarball_path = "libfoo.v1.0.0.not-a-triplet.tar.gz"
    cp(tarball_path, bogus_tarball_path)

    # Check that installation fails with a valid but "incorrect" platform, but can be forced
    temp_prefix() do prefix
        @test_throws ArgumentError install(new_tarball_path, tarball_hash; prefix=prefix, verbose=true)
        @test install(new_tarball_path, tarball_hash; prefix=prefix, verbose=true, ignore_platform = true)
    end

    # Next, check installing with a bogus platform also fails, but can be forced
    temp_prefix() do prefix
        @test_throws ArgumentError install(bogus_tarball_path, tarball_hash; prefix=prefix, verbose=true)
        @test install(bogus_tarball_path, tarball_hash; prefix=prefix, verbose=true, ignore_platform = true)
    end

    # Cleanup after ourselves
    Base.rm(tarball_path; force=true)
    Base.rm("$(tarball_path).sha256"; force=true)
    Base.rm(bogus_tarball_path; force=true)
    Base.rm("$(bogus_tarball_path).sha256"; force=true)
    Base.rm(new_tarball_path; force=true)
    Base.rm("$(new_tarball_path).sha256"; force=true)
end

@testset "Verification" begin
    temp_prefix() do prefix
        foo_path = joinpath(prefix, "foo")
        open(foo_path, "w") do file
            write(file, "test")
        end
        foo_hash = bytes2hex(sha256("test"))

        # Check that verifying with the right hash works
        @info("This should say; no hash cache found")
        ret, status = verify(foo_path, foo_hash; verbose=true, report_cache_status=true)
        @test ret == true
        @test status == :hash_cache_missing

        # Check that it created a .sha256 file
        @test isfile("$(foo_path).sha256")

        # Check that it verifies the second time around properly
        @info("This should say; hash cache is consistent")
        ret, status = verify(foo_path, foo_hash; verbose=true, report_cache_status=true)
        @test ret == true
        @test status == :hash_cache_consistent

        # Sleep for imprecise filesystems
        sleep(2)

        # Get coverage of messing with different parts of the verification chain
        touch(foo_path)
        @info("This should say; file has been modified")
        ret, status = verify(foo_path, foo_hash; verbose=true, report_cache_status=true)
        @test ret == true
        @test status == :file_modified

        # Ensure that we throw an exception when we can't verify properly
        @test_throws ErrorException verify(foo_path, "0"^32; verbose=true)

        # Ensure that messing with the hash file works properly
        touch(foo_path)
        @test verify(foo_path, foo_hash; verbose=true)
        open("$(foo_path).sha256", "w") do file
            write(file, "this is not the right hash")
        end
        @info("This should say; hash has changed")
        ret, status = verify(foo_path, foo_hash; verbose=true, report_cache_status=true)
        @test ret == true
        @test status == :hash_cache_mismatch
    end
end

const socrates_urls = [
    "https://github.com/staticfloat/small_bin/raw/f1a92f5eafbd30a0c6a8efb6947485b0f6d1bec3/socrates.tar.gz" =>
    "e65d2f13f2085f2c279830e863292312a72930fee5ba3c792b14c33ce5c5cc58",
    "https://github.com/staticfloat/small_bin/raw/f1a92f5eafbd30a0c6a8efb6947485b0f6d1bec3/socrates.tar.bz2" =>
    "13fc17b97be41763b02cbb80e9d048302cec3bd3d446c2ed6e8210bddcd3ac76",
    "https://github.com/staticfloat/small_bin/raw/f1a92f5eafbd30a0c6a8efb6947485b0f6d1bec3/socrates.tar.xz" =>
    "61bcf109fcb749ee7b6a570a6057602c08c836b6f81091eab7aa5f5870ec6475",
]
const socrates_hash = "adcbcf15674eafe8905093183d9ab997cbfba9056fc7dde8bfa5a22dfcfb4967"

@testset "Downloading" begin
    for (url, hash) in socrates_urls
        temp_prefix() do prefix
            target_dir = joinpath(prefix.path, "target")
            download_verify_unpack(url, hash, target_dir; verbose=true)
            socrates_path = joinpath(target_dir, "bin", "socrates")
            @test isfile(socrates_path)

            unpacked_hash = open(socrates_path) do f
                bytes2hex(sha256(f))
            end
            @test unpacked_hash == socrates_hash
        end
    end
end

const collapse_url = "https://github.com/staticfloat/small_bin/raw/master/collapse_the_symlink/collapse_the_symlink.tar.gz"
const collapse_hash = "956c1201405f64d3465cc28cb0dec9d63c11a08cad28c381e13bb22e1fc469d3"
@testset "Copyderef unpacking" begin
    withenv("BINARYPROVIDER_COPYDEREF" => "true") do
        temp_prefix() do prefix
            target_dir = joinpath(prefix.path, "target")
            download_verify_unpack(collapse_url, collapse_hash, target_dir; verbose=true)

            # Test that we get the files we expect
            @test isfile(joinpath(target_dir, "collapse_the_symlink", "foo"))
            @test isfile(joinpath(target_dir, "collapse_the_symlink", "foo.1"))
            @test isfile(joinpath(target_dir, "collapse_the_symlink", "foo.1.1"))

            # Test that these are definitely not links
            @test !islink(joinpath(target_dir, "collapse_the_symlink", "foo"))
            @test !islink(joinpath(target_dir, "collapse_the_symlink", "foo.1.1"))

            # Test that broken symlinks get transparently dropped
            @test !ispath(joinpath(target_dir, "collapse_the_symlink", "broken"))
        end
    end
end

@testset "Download GitHub API #88" begin
    mktempdir() do tmp
        BinaryProvider.download("https://api.github.com/repos/JuliaPackaging/BinaryProvider.jl/tarball/c2a4fc38f29eb81d66e3322e585d0199722e5d71", joinpath(tmp, "BinaryProvider"))
        @test isfile(joinpath(tmp, "BinaryProvider"))
    end
end

@testset "choose_download" begin
    platforms = Dict(
        # Typical binning test
        Linux(:x86_64, compiler_abi=CompilerABI(:gcc4)) => "linux4",
        Linux(:x86_64, compiler_abi=CompilerABI(:gcc7)) => "linux7",
        Linux(:x86_64, compiler_abi=CompilerABI(:gcc8)) => "linux8",

        # Ambiguity test
        Linux(:aarch64, compiler_abi=CompilerABI(:gcc4)) => "linux4",
        Linux(:aarch64, compiler_abi=CompilerABI(:gcc5)) => "linux5",

        MacOS(:x86_64, compiler_abi=CompilerABI(:gcc4)) => "mac4",
        Windows(:x86_64, compiler_abi=CompilerABI(:gcc_any, :cxx11)) => "win",
    )

    @test choose_download(platforms, Linux(:x86_64)) == "linux8"
    @test choose_download(platforms, Linux(:x86_64, compiler_abi=CompilerABI(:gcc7))) == "linux7"
    
    # Ambiguity test
    @test choose_download(platforms, Linux(:aarch64)) == "linux5"
    @test choose_download(platforms, Linux(:aarch64; compiler_abi=CompilerABI(:gcc4))) == "linux5"
    @test choose_download(platforms, Linux(:aarch64; compiler_abi=CompilerABI(:gcc5))) == "linux5"
    @test choose_download(platforms, Linux(:aarch64; compiler_abi=CompilerABI(:gcc6))) == "linux5"
    @test choose_download(platforms, Linux(:aarch64; compiler_abi=CompilerABI(:gcc7))) == nothing
    
    @test choose_download(platforms, MacOS(:x86_64)) == "mac4"
    @test choose_download(platforms, MacOS(:x86_64, compiler_abi=CompilerABI(:gcc7))) == nothing

    @test choose_download(platforms, Windows(:x86_64, compiler_abi=CompilerABI(:gcc_any, :cxx11))) == "win"
    @test choose_download(platforms, Windows(:x86_64, compiler_abi=CompilerABI(:gcc_any, :cxx03))) == nothing
   
    # Poor little guy
    @test choose_download(platforms, FreeBSD(:x86_64)) == nothing
end

# Use `build_libfoo_tarball.jl` in the BinaryBuilder.jl repository to generate more of these
const bin_prefix = "https://github.com/staticfloat/small_bin/raw/51b13b44feb2a262e2e04690bfa54d03167533f2/libfoo"
const libfoo_downloads = Dict(
    Linux(:aarch64, :glibc) => ("$bin_prefix/libfoo.aarch64-linux-gnu.tar.gz", "36886ac25cf5678c01fe20630b413f9354b7a3721c6a2c2043162f7ebd147ff5"),
    Linux(:armv7l, :glibc)  => ("$bin_prefix/libfoo.arm-linux-gnueabihf.tar.gz", "147ebaeb1a722da43ee08705689aed71ac87c3c2c907af047c6721c0025ba383"),
    Linux(:powerpc64le, :glibc) => ("$bin_prefix/libfoo.powerpc64le-linux-gnu.tar.gz", "5c35295ac161272ada9a77d1f6b770e30ea864e521e31853258cbc36ad4c4468"),
    Linux(:i686, :glibc)    => ("$bin_prefix/libfoo.i686-linux-gnu.tar.gz", "97655b6a218d61284723b6923d7c96e6a256fa68b9419d723c588aa24404b102"),
    Linux(:x86_64, :glibc)  => ("$bin_prefix/libfoo.x86_64-linux-gnu.tar.gz", "5208c63a9d07e592c78f541fc13caa8cd191b11e7e77b31d407237c2b13ec391"),

    Linux(:aarch64, :musl)  => ("$bin_prefix/libfoo.aarch64-linux-musl.tar.gz", "81751477c1e3ee6c93e1c28ee7db2b99d1eed0d6ce86dc30d64c2e5dd4dfe88d"),
    Linux(:armv7l, :musl)   => ("$bin_prefix/libfoo.arm-linux-musleabihf.tar.gz", "bb65aad58f2e6fc39dc9688da1bca5e8103a3a3fa67dc589debbd2e98176f0e1"),
    Linux(:i686, :musl)     => ("$bin_prefix/libfoo.i686-linux-musl.tar.gz", "5f02fd1fe19f3a565fb128d3673b35c7b3214a101cef9dcbb202c0092438a87b"),
    Linux(:x86_64, :musl)   => ("$bin_prefix/libfoo.x86_64-linux-musl.tar.gz", "ea630600a12d2c1846bc93bcc8d9638a4991f63329205c534d93e0a3de5f641d"),

    FreeBSD(:x86_64)        => ("$bin_prefix/libfoo.x86_64-unknown-freebsd11.1.tar.gz", "5f6edd6247b3685fa5c42c98a53d2a3e1eef6242c2bb3cdbb5fe23f538703fe4"),
    MacOS(:x86_64)          => ("$bin_prefix/libfoo.x86_64-apple-darwin14.tar.gz", "fcc268772d6f21d65b45fcf3854a3142679b78e53c7673dac26c95d6ccc89a24"),

    Windows(:i686)          => ("$bin_prefix/libfoo.i686-w64-mingw32.tar.gz", "79181cf62ca8e0b2e0851fa0ace52f4ab335d0cad26fb7f9cd4ff356a9a96e70"),
    Windows(:x86_64)        => ("$bin_prefix/libfoo.x86_64-w64-mingw32.tar.gz", "7f8939e9529835b83810d3ae7e2556f6e002d571f619894e54ece42ea5262b7f"),
)

# Test manually downloading and using libfoo
@testset "Libfoo Downloading" begin
    temp_prefix() do prefix
        foo_path = joinpath(prefix,"foo")
        touch(foo_path)
        # Quick one-off tests for `safe_isfile()`:
        @test BinaryProvider.safe_isfile(foo_path)
        @test !BinaryProvider.safe_isfile("http://google.com")

        url, hash = try
            choose_download(libfoo_downloads, platform)
        catch e
            if isa(e, ArgumentError)
                @warn("Platform $platform does not have a libfoo download, skipping download tests")
                return
            else
                rethrow(e)
            end
        end

        @test install(url, hash; prefix=prefix, verbose=true)

        fooifier = ExecutableProduct(prefix, "fooifier", :fooifier)
        libfoo = LibraryProduct(prefix, "libfoo", :libfoo)

        @test satisfied(fooifier; verbose=true)
        @test satisfied(libfoo; verbose=true)

        fooifier_path = locate(fooifier)
        libfoo_path = locate(libfoo)


        # We know that foo(a, b) returns 2*a^2 - b
        result = 2*2.2^2 - 1.1

        # Test that we can invoke fooifier
        @test !success(`$fooifier_path`)
        @test success(`$fooifier_path 1.5 2.0`)
        @test parse(Float64,readchomp(`$fooifier_path 2.2 1.1`)) ≈ result

        # Test that we can dlopen() libfoo and invoke it directly
        hdl = Libdl.dlopen_e(libfoo_path)
        @test hdl != C_NULL
        foo = Libdl.dlsym_e(hdl, :foo)
        @test foo != C_NULL
        @test ccall(foo, Cdouble, (Cdouble, Cdouble), 2.2, 1.1) ≈ result
        Libdl.dlclose(hdl)

        # Test uninstallation
        @test uninstall(manifest_from_url(url; prefix=prefix); verbose=true)

        # Test that download_verify_unpack() works
        Base.rm(prefix.path; recursive=true, force=true)
        @test download_verify_unpack(url, hash, prefix.path)
        @test satisfied(fooifier; verbose=true)
        @test satisfied(libfoo; verbose=true)

        # Test that running download_verify_unpack again just returns `false`,
        # signifying that it didn't actually re-unpack anything.
        @test !download_verify_unpack(url, hash, prefix.path)

        # Test that download_verify twice in a row works, and that mucking
        # with the file causes a redownload if `force` is true:
        tmpfile = joinpath(prefix, "libfoo.tar.gz")
        @test download_verify(url, hash, tmpfile; verbose=true)
        @test download_verify(url, hash, tmpfile; verbose=true)

        # We sleep for at least a second here so that filesystems with low
        # precision in their mtime implementations don't get confused
        sleep(2)

        open(tmpfile, "w") do f
            write(f, "not the correct contents")
        end

        @test_throws ErrorException download_verify(url, hash, tmpfile; verbose=true)

        # This should return `false`, signifying that the download had to erase
        # the previously downloaded file.
        @test !download_verify(url, hash, tmpfile; verbose=true, force=true)

        # Now let's test that install() works the same way; freaking out if
        # the local path has been messed with, unless `force` has been given:
        tarball_path = joinpath(prefix, "downloads", basename(url))
        try mkpath(dirname(tarball_path)) catch; end
        open(tarball_path, "w") do f
            write(f, "not the correct contents")
        end

        @test_throws ErrorException install(url, hash; prefix=prefix, verbose=true)
        @test install(url, hash; prefix=prefix, verbose=true, force=true)
        @test isinstalled(url, hash; prefix=prefix)
        @test satisfied(fooifier; verbose=true)
        @test satisfied(libfoo; verbose=true)

        # Test that installing with a custom tarball_path works:
        tarball_path = joinpath(prefix, "downloads2", "tarball.tar.gz")
        @test install(url, hash; prefix=prefix, tarball_path=tarball_path, verbose=true, force=true)

        # Check that the tarball exists and hashes properly
        @test isfile(tarball_path)
        hash_check = open(tarball_path, "r") do f
            bytes2hex(sha256(f))
        end
        @test hash_check == hash

        # Check that we're still satisfied
        @test isinstalled(url, hash; prefix=prefix)
        @test satisfied(fooifier; verbose=true)
        @test satisfied(libfoo; verbose=true)

        # Test a bad download fails properly
        bad_url = "http://localhost:1/this_is_not_a_file.v1.0.0.$(triplet(platform)).tar.gz"
        @test_throws ErrorException install(bad_url, "0"^64; prefix=prefix, verbose=true)
    end
end

# Test installation and failure modes of the bundled LibFoo.jl
@testset "LibFoo.jl" begin
    color="--color=$(Base.have_color ? "yes" : "no")"
    cd("LibFoo.jl") do
        Base.rm("./deps/deps.jl"; force=true)
        Base.rm("./deps/usr"; force=true, recursive=true)

        # Install `libfoo` and build the `deps.jl` file for `LibFoo.jl`
        coverage = "--code-coverage=$(Base.JLOptions().code_coverage != 0 ? "user" : "none")"
        run(`$(Base.julia_cmd()) $(coverage) $(color) deps/build.jl`)

        # Ensure `deps.jl` was actually created
        @test isfile("deps/deps.jl")
    end

    # Test that the generated deps.jl file gives us the important stuff
    cd("LibFoo.jl/deps") do
        dllist = Libdl.dllist()
        libjulia = filter(x -> occursin("libjulia", x), dllist)[1]
        julia_libdir = joinpath(dirname(libjulia), "julia")
        envvar_name = @static if Sys.isapple()
            "DYLD_LIBRARY_PATH"
        else Sys.islinux()
            "LD_LIBRARY_PATH"
        end

        original_libdirs = split(get(ENV, envvar_name, ""), ":")
        @static if !Sys.iswindows()
            original_libdirs = filter(x -> x != julia_libdir, original_libdirs)
            ENV[envvar_name] = join(original_libdirs, ":")
        end

        # Include deps.jl, run check_deps() and see if we get our products,
        # and also if the julia libdir gets added to the end of *_LIBRARY_PATH
        include("LibFoo.jl/deps/deps.jl")
        Base.invokelatest(check_deps)
        @test isfile(libfoo)
        @test isfile(fooifier)

        @static if !Sys.iswindows()
            @test julia_libdir in split(ENV[envvar_name], ":")
        end
    end

    cd("LibFoo.jl") do
        # On julia 0.7, we can now rely on Project.toml to set the load path
        run(`$(Base.julia_cmd()) --project=$(pwd()) $(color) -e 'using Pkg; Pkg.test("LibFoo")'`)
    end
end
