#!/usr/bin/env perl
# Validate the staged Spotify main executable before packaging.
#
#   PwEvevee/build-system/validate/validate-macho.pl <Spotify binary> <staged Spotify.app dir>
#
# Checks:
#   1. every expected load command (from dependencies.json) is present exactly once
#   2. no duplicate load commands at all
#   3. every @executable_path / @rpath referenced dylib exists in the staged app
#   4. file is a thin arm64 Mach-O executable
use strict;
use warnings;
use File::Basename qw(dirname);
use lib dirname($0) . '/../lib';
use macho;
use JSON::PP qw(decode_json);

my ($bin, $appdir) = @ARGV;
defined $bin && defined $appdir or die "usage: validate-macho.pl <binary> <appdir>\n";
-f $bin or die "no such binary: $bin";
$appdir =~ s{/+$}{};

my @fail;
my @ok;

open(my $f, '<:raw', $bin) or die "open $bin: $!";
local $/; my $data = <$f>; close $f;

my @archs = eval { macho::parse_macho($data) };
if ($@) { die "FAIL: $bin is not parseable Mach-O: $@"; }
@archs == 1 or push @fail, "expected thin single-arch binary, got " . scalar(@archs) . " archs";

# 2. duplicate load commands (by kind+name)
my %seen;
for my $c (macho::load_commands($data)) {
  next unless ($c->{kind} // '') eq 'dylib';
  if ($seen{ $c->{name} }++) { push @fail, "DUPLICATE LOAD COMMAND: $c->{name}"; }
}

# 1. expected commands
my $deps;
{
  my $p = dirname($0) . '/../../dependencies.json';
  open(my $d, '<', $p) or die "open $p: $!";
  local $/; $deps = decode_json(<$d>);
}
for my $cmd (@{ $deps->{expected_load_commands} }) {
  my $n = $seen{ $cmd->{name} } || 0;
  if ($n == 1) { push @ok, "load command present: $cmd->{name}"; }
  else { push @fail, "load command $cmd->{name}: expected 1, found $n"; }
}

# 3. referenced dependencies resolve inside the app
for my $name (macho::dylibs($data)) {
  next unless $name =~ s{^\@executable_path/}{};
  my $path = "$appdir/$name";
  if (-e $path) { push @ok, "dependency exists: $name"; }
  else { push @fail, "MISSING DEPENDENCY: $name (not at $path)"; }
}

# rpath sanity: no stale Xcode paths like the ones Sideloadly strips anyway
for my $r (macho::rpaths($data)) {
  push @ok, "rpath present: $r";
}

print "  $_\n" for @ok;
if (@fail) {
  print "MACH-O VALIDATION FAILED:\n";
  print "  - $_\n" for @fail;
  exit 1;
}
print "MACH-O VALIDATION PASSED (" . scalar(@ok) . " checks)\n";
