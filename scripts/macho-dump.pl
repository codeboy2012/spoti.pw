#!/usr/bin/perl
# Mach-O load command parser (thin or FAT, LE or BE headers)
use strict; use warnings;
use Digest::SHA;
use File::Basename;

sub rd_u32 { my ($d,$o,$swap)=@_; return $swap ? unpack("N",substr($d,$o,4)) : unpack("V",substr($d,$o,4)); }

sub read_strz {
    my ($data,$off,$max) = @_;
    $max = 256 unless defined $max;
    return "" if $off >= length($data);
    my $end = $off + $max;
    $end = length($data) if $end > length($data);
    my $chunk = substr($data,$off,$end-$off);
    my $z = index($chunk,"\0");
    return $z >= 0 ? substr($chunk,0,$z) : $chunk;
}

sub parse_macho {
    my ($data, $label) = @_;
    my $m0 = unpack("N", substr($data,0,4));          # big-endian read of magic
    my $m1 = unpack("V", substr($data,0,4));          # little-endian read of magic

    if ($m0 == 0xCAFEBABE || $m1 == 0xCAFEBABE) {
        my $swap = ($m1 == 0xCAFEBABE) ? 1 : 0;       # magic itself stored LE => whole header BE-swapped
        my $narch = rd_u32($data,4,$swap);
        print "  [$label] FAT binary, $narch architectures:\n";
        for my $i (0..$narch-1) {
            my $o = 8 + $i*20;
            my $off     = rd_u32($data,$o+0,$swap);
            my $size    = rd_u32($data,$o+4,$swap);
            my $cputype = rd_u32($data,$o+8,$swap);
            printf("    arch: cputype=0x%x offset=%d size=%d\n", $cputype, $off, $size);
            parse_macho(substr($data,$off,$size), "$label/arch");
        }
        return;
    }

    my ($swap, $is64);
    if    ($m1 == 0xFEEDFACF) { $swap=0; $is64=1; }   # LE file: V-read already decoded MH_MAGIC_64
    elsif ($m1 == 0xFEEDFACE) { $swap=0; $is64=0; }
    elsif ($m0 == 0xFEEDFACF) { $swap=1; $is64=1; }   # BE-stored file
    elsif ($m0 == 0xFEEDFACE) { $swap=1; $is64=0; }
    else {
        printf("  [%s] NOT a Mach-O (m0=0x%08x m1=0x%08x)\n", $label, $m0, $m1);
        return;
    }

    my $cputype = rd_u32($data,4,$swap);
    my $cpusub  = rd_u32($data,8,$swap);
    my $filetype= rd_u32($data,12,$swap);
    my $ncmds   = rd_u32($data,16,$swap);
    my $sizeofcmds = rd_u32($data,20,$swap);
    printf("  [%s] Mach-O %d-bit cputype=0x%x cpusub=0x%x filetype=%d ncmds=%d sizeofcmds=%d\n",
        $label, $is64?64:32, $cputype, $cpusub, $filetype, $ncmds, $sizeofcmds);

    my $off = $is64 ? 32 : 28;
    my %segs;
    for my $i (0..$ncmds-1) {
        last if $off + 8 > length($data);
        my $cmd     = rd_u32($data,$off,$swap);
        my $cmdsize = rd_u32($data,$off+4,$swap);
        last if $cmdsize < 8 || $off+$cmdsize > length($data);
        if ($cmd == 0x19) {       # LC_SEGMENT_64
            my $segname = read_strz($data,$off+8,16);
            $segs{$segname} = 1;
        } elsif ($cmd == 0x1) {   # LC_SEGMENT
            my $segname = read_strz($data,$off+8,16);
            $segs{$segname} = 1;
        } elsif ($cmd == 0xC) {
            my $name = read_strz($data, $off + rd_u32($data,$off+8,$swap), 512);
            print "    LC_LOAD_DYLIB $name\n";
        } elsif ($cmd == 0xD) {
            my $name = read_strz($data, $off + rd_u32($data,$off+8,$swap), 512);
            print "    LC_LOAD_WEAK_DYLIB $name\n";
        } elsif ($cmd == 0x80000022) {
            my $name = read_strz($data, $off + rd_u32($data,$off+8,$swap), 512);
            print "    LC_REEXPORT_DYLIB $name\n";
        } elsif ($cmd == 0x8000001E) {
            my $name = read_strz($data, $off + rd_u32($data,$off+8,$swap), 512);
            print "    LC_LOAD_UPWARD_DYLIB $name\n";
        } elsif ($cmd == 0xE) {
            my $name = read_strz($data, $off + rd_u32($data,$off+8,$swap), 512);
            print "    LC_ID_DYLIB $name\n";
        } elsif ($cmd == 0x8000001C || $cmd == 0x8000001D) {
            my $path = read_strz($data, $off + rd_u32($data,$off+8,$swap), 512);
            print "    LC_RPATH $path\n";
        } elsif ($cmd == 0x32) {
            printf("    LC_UUID %s\n", unpack("H*", substr($data,$off+8,16)));
        } elsif ($cmd == 0x80000034) {
            my $platform = rd_u32($data,$off+8,$swap);
            my $minos    = rd_u32($data,$off+12,$swap);
            printf("    LC_BUILD_VERSION platform=%d minos=%d.%d.%d sdk=%d.%d.%d\n", $platform,
                ($minos>>16)&0xff,($minos>>8)&0xff,$minos&0xff,
                (rd_u32($data,$off+16,$swap)>>16)&0xff,(rd_u32($data,$off+16,$swap)>>8)&0xff,rd_u32($data,$off+16,$swap)&0xff);
        } elsif ($cmd == 0x21 || $cmd == 0x2E) {
            my $cryptid = rd_u32($data,$off+16,$swap);
            print "    LC_ENCRYPTION_INFO cryptid=$cryptid\n";
        } elsif ($cmd == 0x1B) {
            my $dataoff  = rd_u32($data,$off+8,$swap);
            my $datasize = rd_u32($data,$off+12,$swap);
            printf("    LC_CODE_SIGNATURE off=%d size=%d (%s)\n", $dataoff, $datasize,
                $datasize == 0 ? "EMPTY" : "present");
        }
        $off += $cmdsize;
    }
    print "    segments: ", join(", ", sort keys %segs), "\n";
    print "\n";
}

for my $f (@ARGV) {
    open(my $fh, '<:raw', $f) or do { print "Cannot open $f: $!\n"; next; };
    local $/; my $data = <$fh>; close($fh);
    printf("=== %s (%d bytes, sha256=%s)\n", $f, length($data), substr(Digest::SHA::sha256_hex($data),0,16));
    parse_macho($data, basename($f));
}
