using BinaryProvider
using Base.Test
using SHA

# A single file we know the contents of
const caeser_url = "https://gist.githubusercontent.com/staticfloat/f587161d8f16295718ee24987d6cf3ed/raw/e819ce4ad053849ed8826c0040f8368ec2eb7fed/known_file"
const caeser_sha256 = "9f80985ded860600dabb3ccd057513f33fef1e7ce85725e5c640b5d5550b8509"

# A .tar.gz that we know the contents of
const socrates_url = "https://github.com/staticfloat/small_bin/raw/master/socrates.tar.gz"
const socrates_sha256 = "e65d2f13f2085f2c279830e863292312a72930fee5ba3c792b14c33ce5c5cc58"
const socrates_output_sha = "d7bd7543123b88d29a34bbcf980514b2562d5daf3c46219668d460d2b2b6bb75"


# Dirty appveyor hacks to get mingw64 toolchains in our path
@static if is_windows()
    const mingw_path = @static if Sys.WORD_SIZE == 64
        "C:\\mingw-w64\\x86_64-6.3.0-posix-seh-rt_v5-rev1\\mingw64\\bin"
    else
        "C:\\mingw-w64\\i686-6.3.0-posix-dwarf-rt_v5-rev1\\mingw32\\bin"
    end

    if isdir(mingw_path)
        ENV["PATH"] = "$(ENV["PATH"]);$mingw_path"
    end
end

@testset "parsing" begin
    @test BinaryProvider.get_tar_ext("") == ""
    @test BinaryProvider.get_tar_ext("foo") == ""
    @test BinaryProvider.get_tar_ext("foo.Z") == ".Z"
    @test BinaryProvider.get_tar_ext("foo.tgz") == ".tgz"
    @test BinaryProvider.get_tar_ext("foo.gz") == ".gz"
    @test BinaryProvider.get_tar_ext("foo.tar.gz") == ".tar.gz"
    @test BinaryProvider.get_tar_ext("foo.tar.xz") == ".tar.xz"
    @test BinaryProvider.get_tar_ext("foo.7z.exe") == ".7z.exe"
    @test BinaryProvider.get_tar_ext("foo.7z.exe") == ".7z.exe"

    @test BinaryProvider.get_tar_ext("foo.exe.7z") == ".7z"
    @test BinaryProvider.get_tar_ext("foo.t4r.xz") == ".xz"
end


@testset "downloading" begin
    engine = probe_download_engine()
    @test typeof(engine) <: Function

    mktempdir() do tempdir
        # Download a known file
        filename = joinpath(tempdir, "caeser")
        engine(caeser_url, filename)

        # Ensure its SHA256 is what we expect
        open(filename) do file
            @test bytes2hex(sha256(file)) == caeser_sha256
        end

        @test verify(filename, caeser_sha256)
        @test !verify(filename, caeser_sha256[1:end-1] * "8")
        @test_throws ErrorException verify(filename, "not a hash")
    end
end

function run_libtest(fooifier_path, libtest_path)
    # We know that foo(a, b) returns 2*a^2 - b
    result = 2*2.2^2 - 1.1

    # Test that we can invoke fooifier
    @test !success(`$fooifier_path`)
    @test success(`$fooifier_path 1.5 2.0`)
    @test_approx_eq parse(Float64,readchomp(`$fooifier_path 2.2 1.1`)) result

    # Test that we can dlopen() libtest and invoke it directly
    libtest = C_NULL
    try libtest = Libdl.dlopen(libtest_path) end
    @test libtest != C_NULL
    foo = Libdl.dlsym_e(libtest, :foo)
    @test foo != C_NULL
    @test_approx_eq ccall(foo, Cdouble, (Cdouble, Cdouble), 2.2, 1.1) result
    Libdl.dlclose(libtest)
end

const libtest_dir = joinpath(dirname(@__FILE__), "libtest")
const libtest = "libtest.$(Libdl.dlext)"
const fooifier = @static if is_windows() "fooifier.exe" else "fooifier" end

@testset "libtest build" begin
    # Begin by building our libtest archive
    cd(libtest_dir) do
        @static if is_windows()
            @test run(`mingw32-make libtest.tar.gz`) == nothing
        else
            @test run(`make libtest.tar.gz`) == nothing
        end
    end

    # Ensure that important files are created
    fooifier_path = joinpath(libtest_dir, fooifier)
    libtest_path = joinpath(libtest_dir, libtest)
    @test isfile(joinpath(libtest_dir, "libtest.tar.gz"))

    # Ensure that we can invoke the libtest stuff from this directory
    run_libtest(fooifier_path, libtest_path)
end

const libtest_archive = joinpath(libtest_dir, "libtest.tar.gz")
const libtest_sha256 = bytes2hex(sha256(open(libtest_archive)))
# Set libdir on windows to point to `bin`
const libdir = @static if is_windows() "bin" else "lib" end


@testset "receipts" begin
    mktempdir() do tempdir
        receipt_files = list_archive_files(libtest_archive)
        @test joinpath("bin", fooifier) in receipt_files
        @test joinpath(libdir, libtest) in receipt_files
    end
end

@testset "unpacking" begin
    # Now, test unpacking this file into a directory
    mktempdir() do tempdir
        unpack(libtest_archive, tempdir)

        fooifier_path = joinpath(tempdir, "bin", fooifier)
        libtest_path = joinpath(tempdir, libdir, libtest)

        # Ensure that we can invoke the libtest stuff from this directory
        run_libtest(fooifier_path, libtest_path)
    end
end


@testset "installing" begin
    # Test installing the archive from file into a prefix of our choosing
    mktempdir() do prefix_path
        prefix = Prefix(prefix_path)
        activate(prefix)
        install("libtest", libtest_archive, libtest_sha256; prefix=prefix)
        run_libtest(fooifier, libtest)

        # Test installing an archive from the web
        install("socrates", socrates_url, socrates_sha256; prefix=prefix)
        wisdom = readchomp(`bash socrates`)
        @test bytes2hex(sha256(wisdom)) == socrates_output_sha

        # Test that removing a package we don't have the receipt for fails
        @test_throws ErrorException remove("not_installed"; prefix=prefix)

        # Remove libtest, make sure it's gone, but socrates is still there
        remove("libtest"; prefix=prefix)
        @test !isfile(joinpath(prefix_path, "usr", "bin", fooifier))
        @test !isfile(joinpath(prefix_path, "usr", libdir, libtest))
        @test  isfile(joinpath(prefix_path, "usr", "bin", "socrates"))
    end
end
