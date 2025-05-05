# coding: utf-8

#
#  Rake tasks to manage native gem packages with binary executables from stripe/stripe-cli
#
#  TL;DR: run "rake package"
#
#  The native platform gems (defined by StripeCLI::Upstream::NATIVE_PLATFORMS) will each contain
#  two files in addition to what the vanilla ruby gem contains:
#
#     exe/
#     ├── stripe                                  #  generic ruby script to find and run the binary
#     └── <Gem::Platform architecture name>/
#         └── stripe                              #  the stripe cli binary executable
#
#  The ruby script `exe/stripe` is installed into the user's path, and it simply locates the
#  binary and executes it. Note that this script is required because rubygems requires that
#  executables declared in a gemspec must be Ruby scripts.
#
#  Windows support note: we ship the same executable in two gems, the `x64-mingw32` and
#  `x64-mingw-ucrt` flavors because Ruby < 3.1 uses the MSCVRT runtime libraries, and Ruby >= 3.1
#  uses the UCRT runtime libraries. You can read more about this change here:
#
#     https://rubyinstaller.org/2021/12/31/rubyinstaller-3.1.0-1-released.html
#
#  As a concrete example, an x86_64-linux system will see these files on disk after installing
#  stripe-cli-bin-1.x.x-x86_64-linux.gem:
#
#     exe/
#     ├── stripe
#     └── x86_64-linux/
#         └── stripe
#
#  So the full set of gem files created will be:
#
#  - pkg/stripe-cli-bin-1.0.0.gem
#  - pkg/stripe-cli-bin-1.0.0-aarch64-linux.gem
#  - pkg/stripe-cli-bin-1.0.0-arm64-darwin.gem
#  - pkg/stripe-cli-bin-1.0.0-x64-mingw32.gem
#  - pkg/stripe-cli-bin-1.0.0-x64-mingw-ucrt.gem
#  - pkg/stripe-cli-bin-1.0.0-x86_64-darwin.gem
#  - pkg/stripe-cli-bin-1.0.0-x86_64-linux.gem
#
#  Note that in addition to the native gems, a vanilla "ruby" gem will also be created without
#  either the `exe/stripe` script or a binary executable present.
#
#
#  New rake tasks created:
#
#  - rake gem:ruby           # Build the ruby gem
#  - rake gem:aarch64-linux  # Build the aarch64-linux gem
#  - rake gem:arm64-darwin   # Build the arm64-darwin gem
#  - rake gem:x64-mingw32    # Build the x64-mingw32 gem
#  - rake gem:x64-mingw-ucrt # Build the x64-mingw-ucrt gem
#  - rake gem:x86_64-darwin  # Build the x86_64-darwin gem
#  - rake gem:x86_64-linux   # Build the x86_64-linux gem
#  - rake download           # Download all stripe cli binaries
#
#  Modified rake tasks:
#
#  - rake gem                # Build all the gem files
#  - rake package            # Build all the gem files (same as `gem`)
#  - rake repackage          # Force a rebuild of all the gem files
#
#  Note also that the binary executables will be lazily downloaded when needed, but you can
#  explicitly download them with the `rake download` command.
#
require "rubygems/package_task"
require "open-uri"
require "zlib"
require_relative "../lib/stripe_cli/upstream"

def stripe_cli_download_url(filename)
  "https://github.com/stripe/stripe-cli/releases/download/v#{StripeCLI::Upstream::VERSION}/#{filename}"
end

STRIPECLI_GEMSPEC = Bundler.load_gemspec("stripe-cli-ruby.gemspec")

# prepend the download task before the Gem::PackageTask tasks
task package: :download

gem_path = Gem::PackageTask.new(STRIPECLI_GEMSPEC).define
desc "Build the ruby gem"
task "gem:ruby" => [ gem_path ]

tmpdir = "tmp"
directory tmpdir

sumpath = File.join(tmpdir, "stripe_#{StripeCLI::Upstream::VERSION}_checksums.txt")
file sumpath => [ tmpdir ] do
  %w[ linux mac windows ].each do |platform|
    checksums_url = stripe_cli_download_url("stripe-#{platform}-checksums.txt")
    warn "Downloading checksums from #{checksums_url} ..."

    File.open(sumpath, "a") do |local|
      URI.open(checksums_url) do |remote|
        local.write(remote.read)
      end
    end
  end
end

tarpaths = []
exepaths = []
StripeCLI::Upstream::NATIVE_PLATFORMS.each do |platform, filename|
  STRIPECLI_GEMSPEC.dup.tap do |gemspec|
    tarpath = File.join(tmpdir, filename)
    tarpaths << tarpath

    exedir = File.join(gemspec.bindir, platform) # "exe/x86_64-linux"
    exepath = File.join(exedir, "stripe") # "exe/x86_64-linux/stripe"
    exepaths << exepath

    # modify a copy of the gemspec to include the native executable
    gemspec.platform = platform
    gemspec.files += [ exepath, "LICENSE-DEPENDENCIES" ]

    # create a package task
    gem_path = Gem::PackageTask.new(gemspec).define
    desc "Build the #{platform} gem"
    task "gem:#{platform}" => [ gem_path ]

    file tarpath => [ tmpdir ] do
      release_url = stripe_cli_download_url(filename)
      warn "Downloading #{tarpath} from #{release_url} ..."

      URI.open(release_url) do |remote|
        File.open(tarpath, "wb") do |local|
          local.write(remote.read)
        end
      end
    end

    directory exedir
    file exepath => [ tarpath, sumpath, exedir ] do
      checksums = File.open(sumpath).each_line.map do |line|
        checksum, file = line.split
        [ File.basename(file), checksum ]
      end.to_h

      local_sha256 = Digest::SHA256.file(tarpath).hexdigest
      remote_sha256 = checksums.fetch(filename)

      if local_sha256 == remote_sha256
        puts "Checksum OK for #{exepath} (#{local_sha256})"
      else
        abort "Checksum mismatch for #{exepath} (#{local_sha256} != #{remote_sha256})"
      end

      warn "Extracting #{tarpath} ..."

      File.open(tarpath) do |tarball|
        Zlib::GzipReader.wrap(tarball) do |gz|
          Gem::Package::TarReader.new(gz) do |reader|
            reader.seek("stripe") do |file|
              File.binwrite(exepath, file.read)
            end
          end
        end
      end
      FileUtils.chmod(0755, exepath, verbose: true)
    end
  end
end

desc "Download all stripe cli binaries"
task "download" => exepaths

CLOBBER.add(tmpdir)
CLOBBER.add(exepaths.map { |p| File.dirname(p) })
