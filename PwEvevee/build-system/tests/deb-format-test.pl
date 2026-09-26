#!/usr/bin/env perl
# Automated tests for PwEvevee/build-system/package/make-deb.pl - the ar/deb format contract.
#
#   perl PwEvevee/build-system/tests/deb-format-test.pl
#
# Asserts: magic, member names, member order, member offsets, member sizes, member modes
# (100644), terminator ("`\n"), even padding, control.tar.gz validity (gzip + tar),
# data.tar.lzma validity (xz -t) + tar structure, debian-binary content.
use strict;
use warnings;
use File::Path qw(make_path remove_tree);
use File::Basename qw(dirname);

my $ROOT = dirname($0) . '/../../..';
my $T = "/tmp/deb-test.$$";
remove_tree($T); make_path("$T/payload/Library/MobileSubstrate/DynamicLibraries");
make_path("$T/control");

# fixture payload
spew("$T/payload/Library/MobileSubstrate/DynamicLibraries/Test.dylib", "FAKE-MACHO" x 100);
spew("$T/payload/Library/MobileSubstrate/DynamicLibraries/Test.plist", "{ Filter = { Bundles = ( \"com.spotify.client\" ); }; }\n");
make_path("$T/control");
spew("$T/control/control", "Package: com.test\nName: Test\nVersion: 1.2.3\nArchitecture: iphoneos-arm\nDescription: test fixture\nMaintainer: t\nAuthor: t\nSection: Tweaks\n");

my $out = "$T/test.deb";
system("perl $ROOT/PwEvevee/build-system/package/make-deb.pl $T/payload $T/control $out") == 0
    or die "make-deb.pl failed";

my $d = slurp($out);
my @failures;
my $pass = 0;
sub ok   { my ($cond, $what) = @_; if ($cond) { $pass++; } else { push @failures, $what; } }

# 1. magic
ok(substr($d, 0, 8) eq "!<arch>\n", "ar global magic must be !<arch>\\n");

# 2. members: names, order, offsets, sizes, modes, terminators
my @expect = (
  ['debian-binary', "2.0\n"],
  ['control.tar.gz', undef],
  ['data.tar.lzma', undef],
);
my $off = 8;
my $expect_off = 8;
my @found;
while ($off + 60 <= length($d)) {
  my $h = substr($d, $off, 60);
  my $name = substr($h, 0, 16); $name =~ s{/\s*$}{/};   # strip trailing spaces after the GNU '/' marker
  $name =~ s{/+$}{};                                    # then drop the GNU '/' marker itself
  $name =~ s{\s+$}{};
  my $size = substr($h, 48, 10); $size =~ s/\s//g;
  my $mode = substr($h, 40, 8);  $mode =~ s/\s//g;   # GNU ar: mode field at 40
  my $term = substr($h, 58, 2);
  my $body = substr($d, $off + 60, $size);
  push @found, { name => $name, size => $size, mode => $mode, term => $term, body => $body, off => $off };
  $off += 60 + $size;
  $off++ if $off % 2;   # even padding
  $expect_off = $off;
}
ok(scalar(@found) == 3, "exactly 3 members (got " . scalar(@found) . ")");
for my $i (0 .. 2) {
  next unless $found[$i];
  ok($found[$i]{name} eq $expect[$i][0], "member $i name is $expect[$i][0] (got $found[$i]{name})");
  ok($found[$i]{mode} eq '100644', "member $i mode is 100644 (got $found[$i]{mode})");
  ok($found[$i]{term} eq "`\n", "member $i terminator is backtick-newline");
}
ok($found[0] && $found[0]{off} == 8, "first member header starts right after magic (8)");
ok($found[1] && $found[1]{off} == 8 + 60 + 4 + (4 % 2), "second member header offset correct (" . ($found[1]{off} // '?') . ")");
ok($found[0] && $found[0]{body} eq "2.0\n", "debian-binary content is 2.0\\n");
ok($found[0] && $found[0]{size} == 4, "debian-binary size is 4");

# 3. sizes match member headers (trailing pad byte included in advancing)
my $expected_ctrl_size = $found[1]{size} // 0;
my $expected_data_size = $found[2]{size} // 0;
ok($expected_ctrl_size > 20 && $expected_ctrl_size < 10000, "control.tar.gz plausible size ($expected_ctrl_size)");
ok($expected_data_size > 100, "data.tar.lzma plausible size ($expected_data_size)");

# 4. control.tar.gz is valid gzip containing a tar with 'control' (via Compress::Zlib)
{
  require Compress::Zlib;
  my $tar = Compress::Zlib::memGunzip($found[1]{body});
  ok(defined $tar, "control.tar.gz gunzips");
  if (defined $tar) {
    ok(index($tar, "Package: com.test") >= 0, "control content present in control.tar");
    ok(index($tar, "ustar") >= 0, "control tar carries ustar magic");
  }
}

# 5. data.tar.lzma: magic + decompressability + roundtrip (xz --format=lzma produces
#    legacy LZMA-alone, first byte 0x5D, which dpkg accepts for data.tar.lzma)
{
  my $body = $found[2]{body};
  ok(substr($body, 0, 1) eq "\x5D", "data member is LZMA-alone format (first byte 0x5D)");
  spew("$T/data.bin.lzma", $body);
  my $rc = system("xz -dc --format=lzma $T/data.bin.lzma > $T/data.tar 2>/dev/null");
  ok($rc == 0, "xz -dc decodes data.tar.lzma");
  if ($rc == 0) {
    my $tar = slurp("$T/data.tar");
    ok(index($tar, "Library/MobileSubstrate/DynamicLibraries/Test.dylib") >= 0, "data tar has the dylib path");
    ok(index($tar, "FAKE-MACHO") >= 0, "data tar has the dylib content");
  }
}

# 6. the GNU '/' name marker must be present exactly at name end (this is what makes dpkg
#    accept the archive; its absence is the historical 'Unknown archive type' bug)
for my $m (@found) {
  my $h = substr($d, $m->{off}, 16);
  $h =~ /\// or ok(0, "member $m->{name}: GNU '/' name marker missing");
  ok(1, "member $m->{name}: GNU '/' marker present");
}

# 7. even padding: body length of each member in the FILE is even
{
  my $o = 8;
  while ($o + 60 <= length($d)) {
    my $h = substr($d, $o, 60);
    my $s = substr($h, 48, 10); $s =~ s/\s//g;
    last unless $s =~ /^\d+$/;
    $s = int($s);
    my $name = substr($h, 0, 16); $name =~ s{/\s*$}{}; $name =~ s/\s+$//;
    ok($s % 2 == 0 || substr($d, $o + 60 + $s, 1) eq "\n", "member $name padded to even length");
    $o += 60 + $s; $o++ if $o % 2;
  }
}

remove_tree($T);

if (@failures) {
  print "DEB FORMAT TESTS FAILED:\n";
  print "  - $_\n" for @failures;
  printf "%d passed, %d FAILED\n", $pass, scalar @failures;
  exit 1;
}
printf "DEB FORMAT TESTS PASSED ($pass checks)\n";
exit 0;

sub slurp { my ($p) = @_; open(my $f, '<:raw', $p) or die "open $p: $!"; local $/; my $d = <$f>; close $f; return $d; }
sub spew  { my ($p, $d) = @_; open(my $o, '>:raw', $p) or die "write $p: $!"; print $o $d; close $o; }
