
"""
`install(pkg::String, url::String, hash::String; prefix::Prefix, verbose::Bool)`

Given a `pkg` name, install it from `url` (either an HTTP/HTTPS url that will be
downloaded from the internet, or a direct path to a local file) which should
point to some kind of archive, e.g. a `.tar.gz` file, or a `.7z` file, etc.
Verify file integrity through the use of a given sha256 `hash` from the user.
Install this `pkg` into the given `prefix` (which defualts to `global_prefix`),
downloading, verifying, and unpacking it all in one fell swoop.
"""
function install(pkg::AbstractString, url::AbstractString, hash::AbstractString;
                 prefix::Prefix = global_prefix, verbose::Bool = false)
    # Start off by getting some initial paths
    tar_ext = get_tar_ext(url)
    usr_path = joinpath(prefix, "usr")
    archive_path = joinpath(prefix, "archives", "$pkg.$tar_ext")
    receipt_path = joinpath(prefix, "receipts", "$pkg.receipt")

    # Whoops, it's already installed.  Quit out immediately
    if isfile(receipt_path)
        if verbose
            info("Receipt found for $pkg; refusing to install")
        end
        return
    end

    # If `url` is actually a file, just copy it into `archives`
    if isfile(url)
        if verbose
            info("Copying file $url to $archive_path")
        end
        cp(url, archive_path; follow_symlinks=true)
    else
        download(url, archive_path; verbose=verbose)
    end

    if !verify(archive_path, hash; verbose=verbose)
        error("Verification failed for $archive_path")
    end

    # Unpack the file directly into the prefix, and save its receipt
    unpack(archive_path, usr_path; verbose=verbose)

    # Write out the file receipt
    open(receipt_path, "w") do file
        receipt_files = list_archive_files(archive_path)

        # Only write out those that are actually files (e.g. not directories)
        for f in receipt_files
            if isfile(joinpath(usr_path, f))
                write(file, f)
                write(file, "\n")
            end
        end
    end

    # Finally, remove the downloaded archive to save some disk space
    if verbose
        info("Removing archive $archive_path")
    end
    rm(archive_path)
end

"""
`remove(pkg::String; prefix::Prefix, verbose::Bool)`

Given an installed `pkg` name, load its receipt and remove all files listed
within it from the given `prefix` (which defaults to `global_prefix`).

Throws an error if a receipt cannot be found.
"""
function remove(pkg::AbstractString;
                prefix::Prefix = global_prefix,
                verbose::Bool = false)
    receipt_path = joinpath(prefix, "receipts", "$pkg.receipt")
    if !isfile(receipt_path)
        if verbose
            info("No receipt found for $pkg; cannot remove")
        end
        return
    end

    if verbose
        info("Removing \"$pkg\" from prefix $prefix")
    end

    # Load up the file installation receipt, delete all files
    open(receipt_path) do file
        for path in chomp.(readlines(file))
            f = joinpath(prefix, "usr", path)
            if verbose
                info("Removing $f")
                info(readdir(dirname(f)))
            end
            rm(f)
        end
    end

    # Remove the installation receipt
    rm(receipt_path)
end
