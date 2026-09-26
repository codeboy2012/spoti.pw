#!/usr/bin/perl
# Unpack a .deb (ar archive) and print full tree of data.tar.*
use strict; use warnings;
use Compress::Zlib qw(memGunzip);
use IO::Uncompress::Unzip;
use File::Path qw(make_path);
use File::Basename;

my $deb = shift @ARGV or die "usage: deb_tree.pl file.deb [outdir]\n";
my $outdir = shift @ARGV;

open(my $fh, '<:raw', $deb) or die "open: $!";
local $/; my $data = <$fh>; close($fh);

my $off = 8;  # position of first member header
my %members;
while ($off + 60 <= length($data)) {
    my $hdr = substr($data,$off,60);
    my $name = substr($hdr,0,16); $name =~ s/\/\s*$//; $name =~ s/\s+$//;
    my $size = substr($hdr,48,10); $size =~ s/\s//g;
    if ($size =~ /^\d+$/) { $size = int($size); }  # decimal, never oct()
    else { last; }  # not a valid member header -> stop
    last if $off + 60 + $size > length($data) + 1;
    my $body = substr($data,$off+60,$size);
    $members{$name} = $body;
    $off += 60 + $size;
    $off++ if $off % 2;   # 2-byte padding
}
print "ar members: ", join(", ", sort keys %members), "\n";

for my $name (sort keys %members) {
    next unless $name =~ /^data\./;
    my $body = $members{$name};
    my $tar;
    if ($name =~ /\.gz$/) {
        $tar = memGunzip($body) or die "gunzip failed for $name";
    } elsif ($name =~ /xz|zst/) {
        print "!! $name is xz/zstd - cannot decompress here\n"; next;
    } else {
        $tar = $body;
    }
    # parse tar
    my $pos = 0;
    my $longname;
    while ($pos + 512 <= length($tar)) {
        my $block = substr($tar,$pos,512);
        last if $block eq ("\0" x 512);
        my $fname = substr($block,0,100); $fname =~ s/\0.*//;
        my $fsize = substr($block,124,12); $fsize =~ s/[\0 ]//g;
        $fsize = oct($fsize);
        my $type = substr($block,156,1);
        my $prefix = substr($block,345,155); $prefix =~ s/\0.*//;
        my $full = ($prefix ne "" ? "$prefix/" : "") . $fname;
        if ($type eq "L") { $longname = substr($tar,$pos+512,$fsize); $longname =~ s/\0.*//; $pos += 512 + $fsize; $pos += (512 - $fsize % 512) % 512; next; }
        if ($type eq "x" || $type eq "g") { $pos += 512 + $fsize; $pos += (512 - $fsize % 512) % 512; next; }
        if (defined $longname) { $full = $longname; $longname = undef; }
        my $content = substr($tar,$pos+512,$fsize);
        if ($outdir) {
            my $dest = "$outdir/$full";
            if ($type eq "5") { make_path($dest); }
            elsif ($type eq "0" || $type eq "") {
                make_path(dirname($dest));
                open(my $o, '>:raw', $dest) or warn "write $dest: $!"; print $o $content; close($o);
            }
        }
        printf("%s %10d  %s\n", $type, $fsize, $full);
        $pos += 512 + $fsize;
        $pos += (512 - $fsize % 512) % 512;
    }
}
