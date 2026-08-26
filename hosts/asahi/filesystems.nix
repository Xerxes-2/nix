# Btrfs tuning layered on top of the generated hardware-configuration.nix.
#
# `fileSystems.<name>.options` is a list, so these are merged with the options
# already declared there instead of replacing them - hardware-configuration.nix
# stays untouched and regenerable.
#
# Mount options only take effect on the next boot; `nixos-rebuild switch` does
# not remount the root filesystem. Compression also only applies to data
# written afterwards; to compress what is already on disk, run
# `btrfs filesystem defragment -czstd -r /` once (this unshares reflinks, so
# expect it to use extra space).
{ ... }:
{
  # compress-force=zstd:1, measured on this machine rather than guessed.
  #
  # Extracting 2 GiB of /nix/store as a real tree of 124k files (88.7% of the
  # bytes sit in files larger than 128 KiB):
  #
  #   compress=no             2154 MiB   (>2048: metadata + 4 KiB rounding)
  #   compress=zstd:1         1291 MiB   1.59x
  #   compress-force=zstd:1    961 MiB   2.13x   <- 26% below plain compress=
  #   compress-force=zstd:3    929 MiB   2.20x
  #
  # `compress=` leaves a quarter of the achievable savings on the table because
  # btrfs guesses which data is worth compressing: if the first blocks of a file
  # do not shrink the whole file is permanently flagged to skip compression, and
  # on top of that each range is entropy-sampled and skipped if it looks
  # incompressible. On mixed data like a store tree those guesses are simply
  # wrong a lot of the time. `compress-force=` hands the decision to zstd, which
  # still stores an extent uncompressed when compressing it would not help.
  #
  # The level is nearly worthless under `compress=` (1.63x at zstd:1 vs 1.67x at
  # zstd:9 - the higher levels never get to see the data the heuristic threw
  # away) and only mildly useful under force (2.13x -> 2.20x at zstd:3), which
  # costs 25% of write throughput (2268 -> 1708 MB/s). Level 1 it is.
  #
  # Compression here is a speedup, not a cost: 2 GiB written sequentially runs
  # at 2268 MB/s with compress-force=zstd:1 versus 1913 MB/s with no compression
  # at all, because the bottleneck is bytes reaching the SSD, not CPU - btrfs
  # spreads compression across worker threads. Even the worst case, 1 GiB of
  # incompressible data, only drops from 2458 to 2067 MB/s.
  #
  # The usual argument against force - btrfs-progs#960, uncompressed extents
  # capped at 512 KiB causing fragmentation - does not reproduce on this kernel:
  # 1 GiB of random data lands in 11 extents (~95 MiB each), against 1 extent
  # without force.
  #
  # These three entries must stay identical: btrfs compression mount options are
  # a property of the filesystem, not of the subvolume, so all mounts of this
  # device share whatever the options say.
  fileSystems = {
    "/".options = [
      "compress-force=zstd:1"
      "noatime"
    ];
    "/home".options = [
      "compress-force=zstd:1"
      "noatime"
    ];
    "/nix".options = [
      "compress-force=zstd:1"
      "noatime"
    ];
  };

  # All three subvolumes live on the same device, and scrub works per
  # filesystem, so scrubbing "/" covers them all - listing each mountpoint
  # would just read the same disk three times.
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/" ];
  };
}
