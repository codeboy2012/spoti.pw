#!/usr/bin/env perl
# Package the staged Spotify.app into a deterministic, store-only IPA.
#
#   PwEvevee/build-system/package/make-ipa.pl <staged Spotify.app> <out.ipa>
#
# Determinism: fixed DOS timestamps, stable entry order (Payload/ first, then app dirs
# before files, then sorted), store-only (no compression), no extra fields.
use strict;
use warnings;
use File::Find;
use File::Basename qw(dirname);
use lib dirname($0) . '/../lib';
use zip;

my ($app, $out) = @ARGV;
defined $out or die "usage: make-ipa.pl <staged Spotify.app> <out.ipa>\n";
$app =~ s{/+$}{};

my @entries;

# directory entries (so empty dirs survive and unzips list a clean tree)
my @dirs;
find({ wanted => sub { push @dirs, $File::Find::name if -d $_ }, no_chdir => 1 }, $app);
my %seen_dir;
for my $d (sort @dirs) {
  (my $rel = $d) =~ s/^\Q$app\E//;
  next if $rel eq '' || $rel eq '/';
  $rel =~ s{^/}{};
  next if $seen_dir{$rel}++;
  push @entries, { name => "Payload/Spotify.app/$rel/", data => '' };
}

# file entries
my @files;
find({ wanted => sub { push @files, $File::Find::name if -f $_ }, no_chdir => 1 }, $app);
for my $p (sort @files) {
  (my $rel = $p) =~ s/^\Q$app\E//;
  $rel =~ s{^/}{};
  push @entries, { name => "Payload/Spotify.app/$rel", data => _slurp($p) };
}

# Payload/ dir entry first, then everything
unshift @entries, { name => 'Payload/', data => '' };

my $size = zip::write_zip($out, \@entries);
print "    " . scalar(@entries) . " entries, $size bytes\n";

# self-check: re-read and verify count + a couple of critical entries
my $listing = zip::read_zip_listing($out);
my $n = scalar keys %$listing;
die "packaged $n entries, expected " . (scalar @entries) . "\n" if $n != scalar @entries;
for my $critical ('Payload/Spotify.app/Info.plist', 'Payload/Spotify.app/Spotify') {
  die "critical entry missing from IPA: $critical\n" unless exists $listing->{$critical};
}
print "    self-check OK\n";

sub _slurp {
  my ($p) = @_;
  open(my $f, '<:raw', $p) or die "open $p: $!";
  local $/; my $d = <$f>; close $f;
  return $d;
}
