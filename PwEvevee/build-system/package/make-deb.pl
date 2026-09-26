#!/usr/bin/env perl
# Build a .deb with the correct ar format DIRECTLY - no post-build patching.
#
#   PwEvevee/build-system/package/make-deb.pl <payload-dir> <control-dir> <out.deb>
#
# The layout is the one proven in the working build (audit §3):
#   ar magic   = "!<arch>\n"
#   members    = debian-binary (2.0\n), control.tar.gz, data.tar.lzma   [in this order]
#   member hdr = GNU 60-byte, name "name/", mode octal 100644, decimal size, "`\n" end
#   bodies     = padded to even length
# data.tar is ustar (fixed-width fields, 2-block terminator), compressed xz --format=lzma -9.
#
# Automated tests: PwEvevee/build-system/tests/deb-format-test.pl
use strict;
use warnings;
use File::Find;
use File::Basename qw(dirname);
use Digest::SHA qw(sha256_hex);

my ($payload, $controldir, $out) = @ARGV;
defined $out or die "usage: make-deb.pl <payload-dir> <control-dir> <out.deb>\n";
-d $payload && -d $controldir or die "payload and control dirs must exist\n";

my $MTIME = $ENV{DEB_MTIME} // 1750000000;   # fixed for reproducibility

# ---------------- control.tar.gz ----------------
my $control = tar_dir($controldir);
my $control_gz = gzip($control);

# ---------------- data.tar.lzma ----------------
my $data = tar_dir($payload);
my $tmp = "$out.data.tar";
_spew($tmp, $data);
my $data_lzma = _capture("xz --format=lzma -9 -T1 -c $tmp");
unlink $tmp;
die "xz produced nothing" unless length $data_lzma;

# ---------------- ar archive ----------------
my $ar = "!<arch>\n";
$ar .= ar_member('debian-binary', "2.0\n");
$ar .= ar_member('control.tar.gz', $control_gz);
$ar .= ar_member('data.tar.lzma', $data_lzma);
_spew($out, $ar);

printf "    deb: %s (%d bytes, control %d, data.lzma %d)\n    sha256 %s\n",
       $out, length($ar), length($control_gz), length($data_lzma), sha256_hex($ar);

# ---------------- ustar writer (fixed-width fields) ----------------
sub ustar_entry {
  my ($name, $type, $mode, $content) = @_;
  $content = '' unless defined $content;
  my $size = length $content;
  my ($prefix, $fname) = ('', $name);
  if (length($name) > 100) {
    my @parts = split('/', $name);
    for my $i (reverse 1 .. $#parts) {
      my $p = join('/', @parts[0 .. $i - 1]);
      my $n = join('/', @parts[$i .. $#parts]);
      if (length($p) <= 155 && length($n) <= 100) { $prefix = $p; $fname = $n; last; }
    }
    die "cannot split name: $name" if length($fname) > 100;
  }
  my $hdr = "\0" x 512;
  substr($hdr,   0, 100) = pad($fname, 100);
  substr($hdr, 100,   8) = pad(sprintf('%07o', $mode), 8);
  substr($hdr, 108,   8) = pad('0000000', 8);                  # uid
  substr($hdr, 116,   8) = pad('0000000', 8);                  # gid
  substr($hdr, 124,  12) = pad(sprintf('%011o', $size), 12);
  substr($hdr, 136,  12) = pad(sprintf('%011o', $MTIME), 12);
  substr($hdr, 148,   8) = '        ';                          # checksum placeholder
  substr($hdr, 156,   1) = $type;
  substr($hdr, 257,   6) = "ustar\0";
  substr($hdr, 263,   2) = '00';
  substr($hdr, 345, 155) = pad($prefix, 155);
  my $sum = 0; $sum += ord for split //, $hdr;
  substr($hdr, 148, 8) = sprintf('%06o', $sum) . "\0 ";
  die "header not 512" unless length($hdr) == 512;
  return $hdr . $content . ("\0" x ((512 - $size % 512) % 512));
}

sub pad { my ($s, $n) = @_; die "field too long: '$s' > $n" if length($s) > $n; return $s . ("\0" x ($n - length($s))); }

sub tar_dir {
  my ($dir) = @_;
  my @entries;
  find({ wanted => sub {
    return if $File::Find::name eq $dir;
    my $rel = $File::Find::name;
    $rel =~ s/^\Q$dir\E\/?//;
    return unless length $rel;
    if (-d $_) { push @entries, [$rel, '5', 0755, '']; }
    else { push @entries, [$rel, '0', 0644, scalar _slurp($_)]; }
  }, no_chdir => 1 }, $dir);
  @entries = sort { $a->[0] cmp $b->[0] } @entries;
  my $tar = '';
  $tar .= ustar_entry(@$_) for @entries;
  $tar .= "\0" x 1024;
  return $tar;
}

# ---------------- ar member ----------------
sub ar_member {
  my ($name, $data) = @_;
  # mode is the literal octal STRING "100644" left-aligned in 8 - the decimal 100644 must
  # never go through %o (it would come out 304444 and APT reports 'Unknown archive type')
  my $hdr = sprintf('%-16s%-12d%-6d%-6d%-8s%-10d`' . "\n",
                    "$name/", 0, 0, 0, '100644', length $data);
  die "bad ar header length" unless length($hdr) == 60;
  $data .= "\n" if length($data) % 2;
  return $hdr . $data;
}

# ---------------- helpers ----------------
sub gzip {
  require Compress::Zlib;
  my $gz = Compress::Zlib::memGzip($_[0]);
  die "memGzip failed" unless defined $gz && length $gz;
  return $gz;
}

sub _capture {
  my ($cmd) = @_;
  my $out = `$cmd`;
  die "command failed: $cmd" if $? != 0;
  return $out;
}

sub _slurp { my ($p) = @_; open(my $f, '<:raw', $p) or die "open $p: $!"; local $/; my $d = <$f>; close $f; return $d; }
sub _spew  { my ($p, $d) = @_; open(my $o, '>:raw', $p) or die "write $p: $!"; print $o $d; close $o; }
