#!/usr/bin/env perl
# Print one value from an XML or binary plist.
#
#   PwEvevee/build-system/lib/plist-value.pl <plist> <Key>
use strict;
use warnings;

my ($plist, $key) = @ARGV;
defined $key or die "usage: plist-value.pl <plist> <Key>\n";
open(my $f, '<:raw', $plist) or die "open $plist: $!";
local $/; my $d = <$f>; close $f;

if (substr($d, 0, 6) eq 'bplist') {
  # binary plist: key then the value string follows in the object table; take the first
  # printable run after the key that is not itself a key-ish token.
  my $i = index($d, $key);
  die "key not found in binary plist: $key\n" if $i < 0;
  my $rest = substr($d, $i + length($key));
  # skip binary junk up to the next printable run of length >= 1
  if ($rest =~ /[\x20-\x7e]+/) {
    my $v = $&;
    # the very next object may be the value; guard against obviously wrong grabs
    $v =~ s/[^[:print:]]//g;
    print "$v\n";
    exit 0;
  }
  die "could not read value for $key\n";
} else {
  # XML plist
  my $i = index($d, "<key>$key</key>");
  die "key not found in plist: $key\n" if $i < 0;
  my $rest = substr($d, $i + length("<key>$key</key>"));
  if ($rest =~ /<string>([^<]*)<\/string>/) { print "$1\n"; exit 0; }
  if ($rest =~ /<integer>([^<]*)<\/integer>/) { print "$1\n"; exit 0; }
  if ($rest =~ /<real>([^<]*)<\/real>/) { print "$1\n"; exit 0; }
  if ($rest =~ /<date>([^<]*)<\/date>/) { print "$1\n"; exit 0; }
  die "no scalar value for $key\n";
}
