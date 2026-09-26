package PwPng;
# Minimal PNG read / resize / write for the website's brand assets.
#
# Used by:
#   make-brand-assets.pl  — derives the icon sizes from the official logo
#   make-social-card.pl   — composites the official logo into the OG image
#
# Supports 8-bit RGB and RGBA, non-interlaced — which is what the project's
# artwork is. Anything else returns undef so callers can fail soft rather than
# emit a corrupt asset.
#
# Core Perl only: Compress::Zlib ships with perl and provides inflate, deflate
# and CRC32, which is everything a PNG needs.
use strict;
use warnings;
use Exporter 'import';
use Compress::Zlib qw(compress uncompress crc32);

our @EXPORT_OK = qw(png_read png_write png_resize png_info);

# ---------------------------------------------------------------- reading

# Returns { w, h, bpp, rows => [ packed scanlines ] } or undef.
sub png_read {
    my ($path) = @_;
    open my $fh, '<:raw', $path or return undef;
    local $/;
    my $d = <$fh>;
    close $fh;
    return undef unless defined $d && substr($d, 0, 8) eq "\x89PNG\r\n\x1a\n";

    my ($w, $h, $depth, $ctype, $interlace);
    my $idat = '';
    my $pos = 8;
    while ($pos + 8 <= length $d) {
        my ($len, $type) = unpack('Na4', substr($d, $pos, 8));
        last if $len > length($d);                  # malformed length
        my $data = substr($d, $pos + 8, $len);
        $pos += 12 + $len;
        if ($type eq 'IHDR') {
            ($w, $h, $depth, $ctype) = unpack('NNCC', $data);
            $interlace = unpack('C', substr($data, 12, 1));
        }
        elsif ($type eq 'IDAT') { $idat .= $data }
        elsif ($type eq 'IEND') { last }
    }
    return undef unless $w && $h && length $idat;
    return undef if $depth != 8;                   # 8-bit only
    return undef if $ctype != 2 && $ctype != 6;    # RGB or RGBA only
    return undef if $interlace;                    # non-interlaced only

    my $raw = uncompress($idat);
    return undef unless defined $raw;

    my $bpp = $ctype == 6 ? 4 : 3;
    my $stride = $w * $bpp;
    return undef if length($raw) < ($stride + 1) * $h;

    my @rows;
    my $prev = "\0" x $stride;
    for my $y (0 .. $h - 1) {
        my $off = $y * ($stride + 1);
        my $filter = ord(substr($raw, $off, 1));
        my $line = _unfilter($filter, substr($raw, $off + 1, $stride), $prev, $bpp, $stride);
        return undef unless defined $line;
        push @rows, $line;
        $prev = $line;
    }
    return { w => $w, h => $h, bpp => $bpp, rows => \@rows };
}

sub png_info {
    my ($img) = @_;
    return sprintf('%dx%d %s', $img->{w}, $img->{h}, $img->{bpp} == 4 ? 'RGBA' : 'RGB');
}

sub _unfilter {
    my ($filter, $line, $prev, $bpp, $stride) = @_;
    return $line if $filter == 0;
    my @cur = unpack('C*', $line);
    my @up  = unpack('C*', $prev);
    for my $i (0 .. $stride - 1) {
        my $a = $i >= $bpp ? $cur[ $i - $bpp ] : 0;
        my $b = $up[$i] // 0;
        my $c = $i >= $bpp ? ($up[ $i - $bpp ] // 0) : 0;
        if    ($filter == 1) { $cur[$i] = ($cur[$i] + $a) & 0xff }
        elsif ($filter == 2) { $cur[$i] = ($cur[$i] + $b) & 0xff }
        elsif ($filter == 3) { $cur[$i] = ($cur[$i] + int(($a + $b) / 2)) & 0xff }
        elsif ($filter == 4) {
            my $p = $a + $b - $c;
            my ($pa, $pb, $pc) = (abs($p - $a), abs($p - $b), abs($p - $c));
            my $pred = ($pa <= $pb && $pa <= $pc) ? $a : ($pb <= $pc ? $b : $c);
            $cur[$i] = ($cur[$i] + $pred) & 0xff;
        }
        else { return undef }
    }
    return pack('C*', @cur);
}

# ---------------------------------------------------------------- resizing

# Box (area-average) downscale. Alpha is premultiplied before averaging and
# un-premultiplied afterwards, so transparent edges do not bleed dark fringes
# into the artwork — which matters for a rounded-corner icon.
#
# Only geometry changes: no recolouring, no cropping, no sharpening.
sub png_resize {
    my ($img, $tw, $th) = @_;
    $th //= $tw;
    return undef unless $img && $tw > 0 && $th > 0;

    my ($sw, $sh, $bpp) = ($img->{w}, $img->{h}, $img->{bpp});
    my @out;

    for my $ty (0 .. $th - 1) {
        my $y0 = int($ty * $sh / $th);
        my $y1 = int(($ty + 1) * $sh / $th);
        $y1 = $y0 + 1 if $y1 <= $y0;
        my @line;
        for my $tx (0 .. $tw - 1) {
            my $x0 = int($tx * $sw / $tw);
            my $x1 = int(($tx + 1) * $sw / $tw);
            $x1 = $x0 + 1 if $x1 <= $x0;

            my ($r, $g, $b, $a, $n) = (0, 0, 0, 0, 0);
            for my $sy ($y0 .. $y1 - 1) {
                my $row = $img->{rows}[$sy];
                for my $sx ($x0 .. $x1 - 1) {
                    my @c = unpack("C$bpp", substr($row, $sx * $bpp, $bpp));
                    my $al = $bpp == 4 ? $c[3] / 255 : 1;
                    $r += $c[0] * $al;
                    $g += $c[1] * $al;
                    $b += $c[2] * $al;
                    $a += $al;
                    $n++;
                }
            }
            next unless $n;
            my $alpha = $a / $n;
            if ($alpha > 0) {
                push @line, _b($r / $n / $alpha), _b($g / $n / $alpha), _b($b / $n / $alpha),
                            _b($alpha * 255);
            } else {
                push @line, 0, 0, 0, 0;
            }
        }
        push @out, pack('C*', @line);
    }
    return { w => $tw, h => $th, bpp => 4, rows => \@out };
}

sub _b { my ($v) = @_; return 0 if !defined $v || $v != $v; $v = 0 if $v < 0;
         $v = 255 if $v > 255; return int($v + 0.5) }

# ---------------------------------------------------------------- writing

sub png_write {
    my ($path, $img, $level) = @_;
    $level //= 9;
    my $ctype = $img->{bpp} == 4 ? 6 : 2;
    my $raw = '';
    $raw .= "\0" . $img->{rows}[$_] for 0 .. $img->{h} - 1;

    my $png = "\x89PNG\r\n\x1a\n"
            . _chunk('IHDR', pack('NNCCCCC', $img->{w}, $img->{h}, 8, $ctype, 0, 0, 0))
            . _chunk('IDAT', compress($raw, $level))
            . _chunk('IEND', '');

    open my $fh, '>:raw', $path or die "write $path: $!\n";
    print {$fh} $png;
    close $fh or die "close $path: $!\n";
    return length $png;
}

sub _chunk {
    my ($type, $data) = @_;
    return pack('N', length $data) . $type . $data . pack('N', crc32($type . $data));
}

1;
