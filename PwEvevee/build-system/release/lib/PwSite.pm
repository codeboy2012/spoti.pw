package PwSite;
# Shared helpers for the PwEevee website tooling.
#
#   update-releases.pl  — fetches GitHub release metadata -> website/data/releases.json
#   render-site.pl      — renders that data (plus releases/index.json) into the pages
#   website-tests.pl    — checks the generated site
#
# Core Perl only (JSON::PP ships with perl >= 5.14). No CPAN, no network code here —
# HTTP lives in update-releases.pl so this module stays trivially testable.
use strict;
use warnings;
use utf8;    # the em dash and ellipsis literals below are real characters
use Exporter 'import';
use File::Basename qw(dirname basename);
use File::Path qw(make_path);
use File::Spec;
use JSON::PP ();
use POSIX qw(strftime);

our @EXPORT_OK = qw(
  repo_root slurp spew spew_atomic read_json write_json
  h attr fmt_bytes fmt_date fmt_date_iso date_epoch
  inject_slot notes_to_html text_excerpt decode_entities is_safe_url slugify
);

# ---------------------------------------------------------------- filesystem

# Walk upward from a starting directory until the repository marker is found.
sub repo_root {
    my ($start) = @_;
    my $dir = File::Spec->rel2abs($start // dirname(__FILE__));
    while (!-f File::Spec->catfile($dir, 'PwEvevee', 'dependencies.json')) {
        my $up = dirname($dir);
        die "cannot locate repository root above $dir\n" if $up eq $dir;
        $dir = $up;
    }
    return $dir;
}

sub slurp {
    my ($path) = @_;
    open my $fh, '<:raw', $path or die "open $path: $!\n";
    local $/;
    my $data = <$fh>;
    close $fh;
    return defined $data ? $data : '';
}

sub spew {
    my ($path, $data) = @_;
    make_path(dirname($path));
    open my $fh, '>:raw', $path or die "write $path: $!\n";
    print {$fh} $data;
    close $fh or die "close $path: $!\n";
    return 1;
}

# Write via a temporary file + rename so a crash can never leave a half-written
# data file behind (requirement: never silently replace valid data with garbage).
sub spew_atomic {
    my ($path, $data) = @_;
    make_path(dirname($path));
    my $tmp = "$path.tmp$$";
    spew($tmp, $data);
    unlink $path if -e $path;    # rename() over an existing file fails on Windows
    rename $tmp, $path or do {
        my $err = $!;
        unlink $tmp;
        die "rename $tmp -> $path: $err\n";
    };
    return 1;
}

my $JSON = JSON::PP->new->utf8->canonical->pretty->space_before(0);

sub read_json {
    my ($path) = @_;
    my $raw = slurp($path);
    my $data = eval { JSON::PP->new->utf8->relaxed->decode($raw) };
    die "invalid JSON in $path: $@" unless defined $data;
    return $data;
}

sub write_json {
    my ($path, $data) = @_;
    return spew_atomic($path, $JSON->encode($data));
}

# ---------------------------------------------------------------- escaping

# HTML text escaping. Everything that comes from GitHub goes through this before it
# reaches a page; release bodies are never injected as markup.
sub h {
    my ($s) = @_;
    return '' unless defined $s;
    $s = "$s";
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    $s =~ s/'/&#39;/g;
    return $s;
}

# Attribute value escaping for URLs: reject anything that is not a safe target.
sub attr {
    my ($s) = @_;
    return '' unless defined $s;
    return h($s) if $s =~ m{^(?:/|\#|mailto:)} && $s !~ /[\x00-\x1f"'<>]/;
    return is_safe_url($s) ? h($s) : '';
}

sub is_safe_url {
    my ($url) = @_;
    return 0 unless defined $url && length $url;
    return 0 if $url =~ /[\x00-\x20"'<>\\]/;
    return 0 unless $url =~ m{^https://[A-Za-z0-9.-]+(?::\d+)?(?:/|$)};
    return 1;
}

sub slugify {
    my ($s) = @_;
    $s = lc($s // '');
    $s =~ s/[^a-z0-9]+/-/g;
    $s =~ s/^-+|-+$//g;
    return length $s ? $s : 'item';
}

# ---------------------------------------------------------------- formatting

sub fmt_bytes {
    my ($bytes) = @_;
    return '—' unless defined $bytes && $bytes =~ /^\d+$/ && $bytes > 0;
    my @unit = ('bytes', 'KB', 'MB', 'GB');
    my $n = $bytes;
    my $i = 0;
    while ($n >= 1024 && $i < $#unit) { $n /= 1024; $i++ }
    return $i == 0 ? "$bytes bytes"
         : $n >= 100 ? sprintf('%.0f %s', $n, $unit[$i])
         :             sprintf('%.1f %s', $n, $unit[$i]);
}

# "2026-09-23T22:00:43Z" -> epoch seconds (UTC, no Time::Local dependency needed
# for the common case because GitHub always returns UTC 'Z' timestamps).
sub date_epoch {
    my ($iso) = @_;
    return 0 unless defined $iso && $iso =~ /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2}):(\d{2})/;
    my ($Y, $M, $D, $h, $m, $s) = ($1, $2, $3, $4, $5, $6);
    # days since 1970-01-01 (civil-from-days, Howard Hinnant's algorithm)
    my $y = $Y;
    $y -= $M <= 2 ? 1 : 0;
    my $era = int(($y >= 0 ? $y : $y - 399) / 400);
    my $yoe = $y - $era * 400;
    my $doy = int((153 * ($M + ($M > 2 ? -3 : 9)) + 2) / 5) + $D - 1;
    my $doe = $yoe * 365 + int($yoe / 4) - int($yoe / 100) + $doy;
    my $days = $era * 146097 + $doe - 719468;
    return $days * 86400 + $h * 3600 + $m * 60 + $s;
}

sub fmt_date_iso {
    my ($iso) = @_;
    return '' unless defined $iso && $iso =~ /^(\d{4}-\d{2}-\d{2})/;
    return $1;
}

# "23 September 2026" — unambiguous for every locale, no invented precision.
my @MONTH = qw(January February March April May June July August September October November December);

sub fmt_date {
    my ($iso) = @_;
    return 'date unavailable' unless defined $iso && $iso =~ /^(\d{4})-(\d{2})-(\d{2})/;
    my ($Y, $M, $D) = ($1, $2 + 0, $3 + 0);
    return sprintf('%d %s %d', $D, $MONTH[$M - 1] // '?', $Y);
}

# ---------------------------------------------------------------- page slots

# Replace the inner region of <!-- slot:NAME --> ... <!-- /slot:NAME -->.
# Idempotent: running the renderer twice produces the same file.
sub inject_slot {
    my ($file, $slot, $html) = @_;
    my $doc = slurp($file);
    my $re = qr{(<!--\s*\Q$slot\E\s*-->).*?(<!--\s*/\Q$slot\E\s*-->)}s;
    unless ($doc =~ s{$re}{$1 . $html . $2}se) {
        die "slot '$slot' not found in $file\n";
    }
    spew($file, $doc);
    return 1;
}

# ---------------------------------------------------------------- release notes

# Render upstream release notes without ever trusting them as markup.
#
# Every character is HTML-escaped FIRST; only then is a tiny, fixed set of block
# structures recognised in the escaped text. There is no path by which GitHub
# content can introduce an element, attribute or script.
sub notes_to_html {
    my ($body, %opt) = @_;
    return '' unless defined $body && $body =~ /\S/;
    my $limit = $opt{limit} || 6000;

    $body = decode_entities($body);
    $body =~ s/\r\n?/\n/g;
    my $truncated = 0;
    if (length($body) > $limit) {
        $body = substr($body, 0, $limit);
        $body =~ s/\n[^\n]*$//;    # don't cut mid-line
        $truncated = 1;
    }

    my @out;
    my $in_list = 0;
    my @para;

    my $flush_para = sub {
        return unless @para;
        push @out, '<p>' . join('<br>', @para) . '</p>';
        @para = ();
    };
    my $close_list = sub {
        return unless $in_list;
        push @out, '</ul>';
        $in_list = 0;
    };

    for my $raw (split /\n/, $body, -1) {
        my $line = h($raw);
        $line =~ s/\s+$//;

        if ($line !~ /\S/) { $flush_para->(); $close_list->(); next }

        # A release note's headings are third-party content, nested inside a
        # <details> inside a panel that already carries its own heading. Emitting
        # real heading elements spliced arbitrary levels into the page outline —
        # and skipped levels, because the surrounding panel is an h2 when it is
        # the featured download and an h3 otherwise. They become labelled
        # paragraphs instead. Nothing is lost: this grammar has no nesting for a
        # heading to establish in the first place.
        if ($line =~ /^\s{0,3}#{1,6}\s+(.*)$/) {
            $flush_para->();
            $close_list->();
            push @out, '<p class="notes__h">' . inline($1) . '</p>';
            next;
        }
        if ($line =~ /^\s{0,3}(?:[-*+]|\d{1,2}[.)])\s+(.*)$/) {
            $flush_para->();
            unless ($in_list) { push @out, '<ul>'; $in_list = 1 }
            push @out, '<li>' . inline($1) . '</li>';
            next;
        }
        if ($line =~ /^\s{0,3}(?:---+|___+|\*\*\*+)\s*$/) {
            $flush_para->();
            $close_list->();
            next;
        }
        $close_list->();
        push @para, inline($line);
    }
    $flush_para->();
    $close_list->();

    push @out, '<p class="notes-truncated">Notes truncated. Read the complete release notes on GitHub.</p>'
        if $truncated;
    return join('', @out);
}

# Upstream release notes are markdown, and authors sometimes write HTML entities
# in them because GitHub renders markdown as HTML — "Mod &gt; Licenses" is meant
# to read "Mod > Licenses", not to show the entity. Decode a small fixed set so
# the text reads as intended.
#
# This is safe because every consumer re-escapes immediately afterwards with h():
# decoding "&lt;" to "<" and then escaping it back to "&lt;" is a round trip, so
# no markup can be introduced. "&amp;" is decoded LAST, which is what makes
# "&amp;gt;" correctly stay the literal text "&gt;".
sub decode_entities {
    my ($t) = @_;
    return $t unless defined $t;
    $t =~ s/&(?:lt|#0*60|#x0*3c);/</gi;
    $t =~ s/&(?:gt|#0*62|#x0*3e);/>/gi;
    $t =~ s/&(?:quot|#0*34|#x0*22);/"/gi;
    $t =~ s/&(?:apos|#0*39|#x0*27);/'/gi;
    $t =~ s/&nbsp;/ /gi;
    $t =~ s/&(?:amp|#0*38|#x0*26);/&/gi;
    return $t;
}

# Characters allowed in a URL we are willing to linkify.
#
# NOTE the backslashes: inside a regex literal an unescaped $& or @x would be
# INTERPOLATED, which would splice the release-notes text straight into the
# pattern. Every sigil here is escaped deliberately.
my $URLCHARS = qr{[A-Za-z0-9._~:/?\#\[\]\@!\$&'()*+,;=%-]};
my $URL      = qr{https://$URLCHARS{4,300}};

# Inline formatting inside already-escaped text: `code`, **strong**, *em*, and
# https links. Operating on escaped text means the output can only ever contain
# the few tags produced here.
sub inline {
    my ($t) = @_;
    $t =~ s{`([^`]{1,200})`}{<code>$1</code>}g;
    $t =~ s{\*\*([^*]{1,200})\*\*}{<strong>$1</strong>}g;
    $t =~ s{(?<![\w*])\*([^*\s][^*]{0,200})\*(?![\w*])}{<em>$1</em>}g;
    # [text](https://url) -> anchor, both halves already escaped
    $t =~ s{\[([^\]<>]{1,120})\]\(($URL)\)}{_link($2, $1)}ge;
    # bare URL — the lookbehind keeps it out of an href we just produced
    $t =~ s{(?<!["'=>])\b($URL)}{_link($1, $1)}ge;
    return $t;
}

sub _link {
    my ($url, $text) = @_;
    # the text arrives HTML-escaped, so &amp; must be undone before validating
    my $clean = $url;
    $clean =~ s/&amp;/&/g;
    $clean =~ s/&#39;/'/g;
    return $text unless is_safe_url($clean);
    return sprintf('<a href="%s" rel="noopener nofollow ugc" target="_blank">%s</a>', h($clean), $text);
}

# First meaningful sentence of a release body, as plain text.
sub text_excerpt {
    my ($body, $max) = @_;
    $max ||= 200;
    return '' unless defined $body;
    my $t = decode_entities($body);
    $t =~ s/\r//g;
    $t =~ s/^\s*#.*$//mg;              # drop headings
    $t =~ s/^\s*[-*+]\s+/ /mg;         # flatten bullets
    $t =~ s/[`*_>]+//g;
    $t =~ s{\[([^\]]*)\]\([^)]*\)}{$1}g;
    $t =~ s{https?://\S+}{}g;
    $t =~ s/\s+/ /g;
    $t =~ s/^\s+|\s+$//g;
    return '' unless length $t;
    if (length($t) > $max) {
        $t = substr($t, 0, $max);
        $t =~ s/\s+\S*$//;
        $t .= '…';
    }
    return $t;
}

1;
