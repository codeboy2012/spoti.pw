# Minimal store-only ZIP writer/reader for deterministic IPA packaging.
#
#   PwEvevee/build-system/lib/zip.pm
#
# IPAs are ZIP archives. Apple's installers accept store-only (method 0) entries, which is
# what keeps the output byte-reproducible: no compression, fixed DOS timestamps, entries in
# a caller-supplied order. CRC-32 is implemented locally so no extra modules are needed.
package zip;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT_OK = qw(crc32 write_zip read_zip_listing);

my @CRC_TABLE;
sub _crc_table {
  return @CRC_TABLE if @CRC_TABLE;
  for my $n (0 .. 255) {
    my $c = $n;
    for (1 .. 8) { $c = ($c & 1) ? (0xEDB88320 ^ ($c >> 1)) : ($c >> 1); }
    $CRC_TABLE[$n] = $c;
  }
  return @CRC_TABLE;
}

sub crc32 {
  my ($data) = @_;
  my @t = _crc_table();
  my $c = 0xFFFFFFFF;
  for my $b (unpack('C*', $data)) { $c = $t[($c ^ $b) & 0xFF] ^ ($c >> 8); }
  return $c ^ 0xFFFFFFFF;
}

# Fixed timestamp (1980-01-01 00:00:00 DOS) keeps builds reproducible.
my $DOS_TIME  = 0;
my $DOS_DATE  = (40 << 9) | (1 << 5) | 1;

# write_zip( $path, \@entries )
#   Each entry: { name => 'Payload/Spotify.app/Spotify', data => '...' }
#   Names must use forward slashes and must not start with '/'.
sub write_zip {
  my ($out, $entries) = @_;
  my $body = '';
  my @central;
  for my $e (@$entries) {
    my $name = $e->{name};
    # printable ASCII only, no leading slash, no drive letters; parentheses/+ occur inside
    # Spotify resource names (SpotifyRAPI_BMW-ID4++_Images.zip) and are fine for IPAs
    die "bad zip name: $name" if $name =~ m{^/} || $name =~ m{[\x00-\x1f\x7f]} || $name =~ m{[<>:"\\|?*]} && $name !~ m{^Payload/};
    my $data = $e->{data};
    my $crc = crc32($data);
    my $off = length($body);
    my $local = pack('VvvvvvVVVvv',
      0x04034B50, 20, 0, 0, $DOS_TIME, $DOS_DATE, $crc,
      length($data), length($data), length($name), 0) . $name;
    $body .= $local . $data;
    push @central, pack('VvvvvvvVVVvvvvvVV',
      0x02014B50, 20, 20, 0, 0, $DOS_TIME, $DOS_DATE, $crc,
      length($data), length($data), length($name), 0, 0, 0, 0, 0, $off) . $name;
  }
  my $cd = join('', @central);
  my $eocd = pack('VvvvvVVv',
    0x06054B50, 0, 0, scalar(@central), scalar(@central), length($cd), length($body), 0);
  open(my $o, '>:raw', $out) or die "write $out: $!";
  print $o $body, $cd, $eocd;
  close $o;
  return length($body) + length($cd) + length($eocd);
}

# read_zip_listing( $path ) -> { name => size }
# Parses via the End-of-Central-Directory record - raw scanning would mis-sync on
# signatures that occur inside stored file data.
sub read_zip_listing {
  my ($path) = @_;
  my $data = _slurp($path);
  my $cd = _central_dir($data);
  my %out;
  for my $e (@$cd) { $out{ $e->{name} } = $e->{usize}; }
  return \%out;
}

sub _find_eocd {
  my ($data) = @_;
  my $sig = pack('V', 0x06054B50);
  my $pos = rindex($data, $sig);
  die "zip: end of central directory not found" if $pos < 0;
  return $pos;
}

sub _central_dir {
  my ($data) = @_;
  my $eocd = _find_eocd($data);
  my $count = unpack('x10 v', substr($data, $eocd, 12));
  my $cdoff = unpack('x16 V', substr($data, $eocd, 20));
  my @out;
  my $pos = $cdoff;
  for (1 .. $count) {
    die "zip: central directory truncated" if $pos + 46 > length($data);
    my $sig = unpack('V', substr($data, $pos, 4));
    die "zip: bad central directory entry at $pos" if $sig != 0x02014B50;
    my $csize     = unpack('x20 V', substr($data, $pos, 24));
    my $usize     = unpack('x24 V', substr($data, $pos, 28));
    my $namelen   = unpack('x28 v', substr($data, $pos, 30));
    my $extralen  = unpack('x30 v', substr($data, $pos, 32));
    my $commentlen= unpack('x32 v', substr($data, $pos, 34));
    my $lhoff     = unpack('x42 V', substr($data, $pos, 46));
    my $name      = substr($data, $pos + 46, $namelen);
    push @out, { name => $name, csize => $csize, usize => $usize, lhoff => $lhoff };
    $pos += 46 + $namelen + $extralen + $commentlen;
  }
  return \@out;
}

# read_zip_entry( $path, $name ) -> data (store-only archives)
sub read_zip_entry {
  my ($path, $want) = @_;
  my $data = _slurp($path);
  my $cd = _central_dir($data);
  my ($e) = grep { $_->{name} eq $want } @$cd;
  die "zip entry not found: $want" unless $e;
  my $off = $e->{lhoff};
  my $sig = unpack('V', substr($data, $off, 4));
  die "zip: bad local header for $want" if $sig != 0x04034B50;
  my $namelen  = unpack('x26 v', substr($data, $off, 28));
  my $extralen = unpack('x28 v', substr($data, $off, 30));
  return substr($data, $off + 30 + $namelen + $extralen, $e->{usize});
}

sub _slurp {
  my ($p) = @_;
  open(my $f, '<:raw', $p) or die "open $p: $!";
  local $/; my $d = <$f>; close $f;
  return $d;
}

1;
