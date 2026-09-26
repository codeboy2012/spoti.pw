#!/usr/bin/perl
# Minimal static file server for local preview of website/ (PwEevee).
#
# Usage:  perl scripts/dev-server.pl [port] [document-root]
#   port            default 4173
#   document-root   default the website/ directory next to this script
#
# No dependencies beyond perl core modules (IO::Socket::INET). Mirrors the
# nginx example config in website/nginx.conf.example: root-mapped clean URLs
# (/downloads -> /downloads/index.html), index.html for directory roots and a
# correct content type for .ipa downloads.

use strict;
use warnings;
use IO::Socket::INET;
use File::Basename qw(dirname);
use File::Spec;

$| = 1;
$SIG{PIPE} = 'IGNORE';    # browsers close keep-alive sockets; don't die on it

my $port     = $ARGV[0] // 4173;
my $root_dir = $ARGV[1];
unless ($root_dir) {
    my $script_dir = dirname(File::Spec->rel2abs(__FILE__));
    $root_dir = File::Spec->catdir(File::Spec->catdir($script_dir, '..'), 'website');
}
$root_dir = File::Spec->canonpath($root_dir);
die "document root not found: $root_dir\n" unless -d $root_dir;

my %MIME = (
    html => 'text/html; charset=utf-8',
    htm  => 'text/html; charset=utf-8',
    css  => 'text/css; charset=utf-8',
    js   => 'text/javascript; charset=utf-8',
    mjs  => 'text/javascript; charset=utf-8',
    json => 'application/json',
    png  => 'image/png',
    jpg  => 'image/jpeg',
    jpeg => 'image/jpeg',
    gif  => 'image/gif',
    svg  => 'image/svg+xml',
    ico  => 'image/x-icon',
    webp => 'image/webp',
    txt  => 'text/plain; charset=utf-8',
    md   => 'text/plain; charset=utf-8',
    xml  => 'application/xml',
    woff => 'font/woff',
    woff2=> 'font/woff2',
    ipa  => 'application/octet-stream',
    deb  => 'application/vnd.debian.binary-package',
);

my $server = IO::Socket::INET->new(
    LocalAddr => '127.0.0.1',
    LocalPort => $port,
    Proto     => 'tcp',
    Listen    => 16,
    ReuseAddr => 1,
    Timeout   => 10,
) or die "cannot listen on 127.0.0.1:$port: $!\n";

print "PwEevee preview server listening on http://127.0.0.1:$port (root: $root_dir)\n";

while (1) {
    my $client = $server->accept or next;

    my $request = <$client>;    # request line only; we always close after one response
    if (!defined $request) { close $client; next; }
    $request =~ s/[\r\n]+$//;
    my ($method, $target) = $request =~ m{^(\w+)\s+(\S+)\s+HTTP/\d\.\d$};
    ($method, $target) = ('GET', '/') unless defined $method;

    # drain request headers (none of them change our response)
    while (my $h = <$client>) { last if $h =~ m{^[\r\n]+$}; }

    $target =~ s/\?.*$//;                 # ignore query strings
    $target =~ s/#.*$//;
    $target = '/' if $target eq '';

    my ($status, $type, $file, $body) = handle($target);

    my $head_only = ($method eq 'HEAD') ? 1 : 0;
    my $length = defined $file ? -s $file : length($body);
    my $msg = $status == 200 ? 'OK' : 'Not Found';

    print $client "HTTP/1.1 $status $msg\r\n"
                . "Content-Type: $type\r\n"
                . "Content-Length: $length\r\n"
                . "Cache-Control: no-cache\r\n"
                . "Connection: close\r\n\r\n";

    unless ($head_only) {
        if (defined $file) {
            # Streamed in chunks: the site hosts ~300 MB IPA files and slurping
            # one into memory per request would take the preview server down.
            if (open my $in, '<:raw', $file) {
                binmode $client;
                my $buf;
                while (my $n = read($in, $buf, 256 * 1024)) {
                    print $client $buf or last;
                }
                close $in;
            }
        } else {
            print $client $body;
        }
    }

    close $client;
    print "$method $target -> $status ($length bytes)\n";
}

# Returns (status, content-type, file-to-stream, inline-body).
# Exactly one of file-to-stream / inline-body is defined.
sub handle {
    my ($target) = @_;

    # security: reject anything that could escape the document root
    if ($target =~ m{\.\.} || $target =~ m{[\x00-\x1f]}) {
        return (404, 'text/plain; charset=utf-8', undef, "404 Not Found\n");
    }

    my $file = safe_join($target);
    if (-d $file) {
        # / and /downloads (with or without trailing slash) -> their index.html
        $file = File::Spec->catfile($file, 'index.html');
    }

    return (200, type_for($file), $file, undef) if -f $file;

    # nginx `try_files $uri $uri/ /404.html` equivalent
    my $custom = File::Spec->catfile($root_dir, '404.html');
    return (404, 'text/html; charset=utf-8', $custom, undef) if -f $custom;
    return (404, 'text/plain; charset=utf-8', undef, "404 Not Found: $target\n");
}

sub safe_join {
    my ($url_path) = @_;
    $url_path =~ s{^/}{};
    my @parts = grep { length && $_ ne '.' && $_ ne '..' } split m{/}, $url_path;
    return @parts ? File::Spec->catfile($root_dir, @parts) : $root_dir;
}

sub type_for {
    my ($file) = @_;
    my ($ext) = $file =~ m{\.([A-Za-z0-9]+)$};
    return $MIME{ lc($ext // '') } // 'application/octet-stream';
}


