#!/usr/bin/env perl
# Add an LC_LOAD_DYLIB / LC_LOAD_WEAK_DYLIB to a thin 64-bit Mach-O, in place, unless the
# install name is already loaded. Mirrors the proven scripts/insert-dylib.py logic:
# the command goes into the zero padding between the load commands and the first section;
# the signature is invalidated and the IPA is signed again later by the user's signer.
#
#   PwEvevee/build-system/inject/inject-dylib.pl <binary> <install name> [--weak]
use strict;
use warnings;
use File::Basename qw(dirname);
use lib dirname($0) . '/../lib';
use macho;

my ($path, $name, @extra) = @ARGV;
defined $name && defined $path or die "usage: inject-dylib.pl <binary> <install name> [--weak]\n";
my $weak = grep { $_ eq '--weak' } @extra;

open(my $f, '<:raw', $path) or die "open $path: $!";
local $/; my $data = <$f>; close $f;
die "$path: not a thin 64-bit Mach-O\n" unless unpack('V', substr($data, 0, 4)) == 0xFEEDFACF;

# ncmds at 16, sizeofcmds at 20 (64-bit header)
my ($ncmds, $sizeofcmds) = unpack('x16 V V', $data);

my %present = map { $_ => 1 } macho::dylibs($data);
if ($present{$name}) { print "    $name already loaded\n"; exit 0; }

my $slack = macho::slack($data);
my $raw = $name . "\0";
my $cmdsize = (24 + length($raw) + 7) & ~7;
die "$path: no room for another load command (need $cmdsize, slack $slack)\n"
    if $slack < $cmdsize;

my $LC = $weak ? 0x80000018 : 0xC;
my $cmd = pack('V6', $LC, $cmdsize, 24, 2, 0x10000, 0x10000) . $raw;
$cmd .= "\0" x ($cmdsize - length($cmd));

my $end = 32 + $sizeofcmds;
substr($data, $end, $cmdsize) eq "\0" x $cmdsize
    or die "$path: padding after load commands is not zero - refusing\n";
substr($data, $end, $cmdsize) = $cmd;
substr($data, 16, 8) = pack('VV', $ncmds + 1, $sizeofcmds + $cmdsize);

open(my $o, '>:raw', $path) or die "write $path: $!";
print $o $data; close $o;
print "    $name added (ncmds " . ($ncmds + 1) . ", slack was $slack)\n";
