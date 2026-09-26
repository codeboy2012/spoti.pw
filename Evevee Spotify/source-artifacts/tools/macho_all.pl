#!/usr/bin/perl
# Dump ALL load commands raw, including unknown ones, to find hidden injection commands
use strict; use warnings;
use Digest::SHA;

sub rd_u32 { my ($d,$o,$swap)=@_; return $swap ? unpack("N",substr($d,$o,4)) : unpack("V",substr($d,$o,4)); }
sub rd_u64 { my ($d,$o,$swap)=@_; return $swap ? unpack("Q>",substr($d,$o,8)) : unpack("Q<",substr($d,$o,8)); }

sub read_strz {
    my ($data,$off,$max) = @_;
    $max = 512 unless defined $max;
    return "" if $off >= length($data);
    my $end = $off + $max; $end = length($data) if $end > length($data);
    my $chunk = substr($data,$off,$end-$off);
    my $z = index($chunk,"\0");
    return $z >= 0 ? substr($chunk,0,$z) : $chunk;
}

my %names = (
    0x1=>"LC_SEGMENT",0x2=>"LC_SYMTAB",0xB=>"LC_DYSYMTAB",0xC=>"LC_LOAD_DYLIB",
    0xD=>"LC_LOAD_WEAK_DYLIB",0xE=>"LC_ID_DYLIB",0x19=>"LC_SEGMENT_64",0x1B=>"LC_CODE_SIGNATURE",
    0x1E=>"LC_SEGMENT_SPLIT_INFO",0x21=>"LC_ENCRYPTION_INFO",0x22=>"LC_DYLD_INFO",
    0x25=>"LC_VERSION_MIN_MACOSX",0x26=>"LC_VERSION_MIN_IPHONEOS",0x27=>"LC_DYLD_ENVIRONMENT",
    0x29=>"LC_DATA_IN_CODE",0x2A=>"LC_SOURCE_VERSION",0x2B=>"LC_DYLIB_CODE_SIGN_DRS",
    0x2C=>"LC_ENCRYPTION_INFO_64",0x2D=>"LC_LINKER_OPTION",0x2E=>"LC_LINKER_OPTIMIZATION_HINT",
    0x32=>"LC_UUID",0x8000001C=>"LC_RPATH",0x8000001D=>"LC_CODE_SIGNATURE_ALT",
    0x8000001E=>"LC_LOAD_UPWARD_DYLIB",0x8000001F=>"LC_DYLD_EXPORTS_TRIE",
    0x80000020=>"LC_DYLD_INFO_ONLY",0x80000021=>"LC_LOAD_AFTER_DYLIB?",
    0x80000022=>"LC_REEXPORT_DYLIB",0x80000023=>"LC_LAZY_LOAD_DYLIB",
    0x80000028=>"LC_BUILD_VERSION_ALT",0x8000002A=>"LC_ATOM_INFO?",
    0x80000033=>"LC_FUNCTION_STARTS",0x80000034=>"LC_BUILD_VERSION",
    0x80000035=>"LC_DYLD_EXPORTS_TRIE_ALT",0x80000036=>"LC_DYLD_CHAINED_FIXUPS",
    0x80000037=>"LC_FILESET_ENTRY",
);

sub parse_macho {
    my ($data, $label, $showall) = @_;
    my $m0 = unpack("N", substr($data,0,4));
    my $m1 = unpack("V", substr($data,0,4));
    if ($m0 == 0xCAFEBABE || $m1 == 0xCAFEBABE) {
        my $swap = ($m1 == 0xCAFEBABE) ? 1 : 0;
        my $narch = rd_u32($data,4,$swap);
        for my $i (0..$narch-1) {
            my $o = 8 + $i*20;
            parse_macho(substr($data, rd_u32($data,$o,$swap), rd_u32($data,$o+4,$swap)), "$label/arch", $showall);
        }
        return;
    }
    my ($swap, $is64);
    if    ($m1 == 0xFEEDFACF) { $swap=0; $is64=1; }
    elsif ($m1 == 0xFEEDFACE) { $swap=0; $is64=0; }
    elsif ($m0 == 0xFEEDFACF) { $swap=1; $is64=1; }
    elsif ($m0 == 0xFEEDFACE) { $swap=1; $is64=0; }
    else { print "  [$label] not Mach-O\n"; return; }
    my $ncmds = rd_u32($data,16,$swap);
    print "  [$label] ncmds=$ncmds\n";
    my $off = $is64 ? 32 : 28;
    for my $i (0..$ncmds-1) {
        last if $off + 8 > length($data);
        my $cmd     = rd_u32($data,$off,$swap);
        my $cmdsize = rd_u32($data,$off+4,$swap);
        last if $cmdsize < 8 || $off+$cmdsize > length($data);
        my $nm = $names{$cmd} // sprintf("UNKNOWN_0x%08x", $cmd);
        my $extra = "";
        if ($cmd == 0xC || $cmd == 0xD || $cmd == 0x80000022 || $cmd == 0xE || $cmd == 0x8000001E || $cmd == 0x80000023) {
            my $s = read_strz($data, $off + rd_u32($data,$off+8,$swap));
            $extra = " $s";
        } elsif ($cmd == 0x8000001C || $cmd == 0x8000001D) {
            my $s = read_strz($data, $off + rd_u32($data,$off+8,$swap));
            $extra = " $s";
        } elsif ($cmd == 0x19 || $cmd == 0x1) {
            my $segname = read_strz($data,$off+8,16);
            my $fileoff = rd_u32($data,$off+24,$swap);
            my $filesize = rd_u32($data,$off+28,$swap);
            $extra = sprintf(" %s off=%d size=%d", $segname, $fileoff, $filesize);
        } elsif ($cmd == 0x1B || $cmd == 0x1E || $cmd == 0x29 || $cmd == 0x8000001F || $cmd == 0x80000033 || $cmd == 0x80000035 || $cmd == 0x80000036 || $cmd == 0x2B) {
            my $doff = rd_u32($data,$off+8,$swap);
            my $dsz  = rd_u32($data,$off+12,$swap);
            $extra = sprintf(" off=%d size=%d", $doff, $dsz);
        } elsif ($cmd == 0x27) {   # LC_DYLD_ENVIRONMENT
            my $s = read_strz($data, $off + rd_u32($data,$off+8,$swap));
            $extra = " $s";
        } elsif ($cmd == 0x32) {
            $extra = " " . unpack("H*", substr($data,$off+8,16));
        } elsif ($cmd == 0x21 || $cmd == 0x2C) {
            my $cryptid = rd_u32($data,$off+16,$swap);
            $extra = " cryptid=$cryptid";
        } elsif ($cmd == 0x2A) {
            my $v = rd_u32($data,$off+8,$swap) . "." . rd_u32($data,$off+12,$swap);
            $extra = " $v";
        }
        # hex dump of first 64 bytes of unknown commands
        if ($nm =~ /^UNKNOWN/ || $cmd == 0x27) {
            my $n = $cmdsize < 64 ? $cmdsize : 64;
            printf("    cmd[%2d] %s size=%d  HEX: %s\n", $i, $nm, $cmdsize, unpack("H*", substr($data,$off,$n)));
        } else {
            printf("    cmd[%2d] %s size=%d%s\n", $i, $nm, $cmdsize, $extra);
        }
        $off += $cmdsize;
    }
}

my $showall = 0;
for my $f (@ARGV) {
    open(my $fh, '<:raw', $f) or next;
    local $/; my $data = <$fh>; close($fh);
    printf("=== %s (%d bytes)\n", $f, length($data));
    parse_macho($data, $f, $showall);
}
