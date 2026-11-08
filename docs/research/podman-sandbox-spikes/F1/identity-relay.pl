#!/usr/bin/perl
# Root-owned relay. 127.0.0.1:8443 plain HTTP in, mTLS out with the current SVID (read at each request).
use strict; use warnings; use IO::Socket::INET;
$SIG{CHLD} = 'IGNORE';
my $gw = $ENV{GATEWAY_URL} or die "GATEWAY_URL";
my $l = IO::Socket::INET->new(Listen => 16, LocalAddr => '127.0.0.1', LocalPort => 8443, ReuseAddr => 1) or die $!;
while (my $c = $l->accept) {
  next if fork;                      # child handles the request
  my $req = <$c>; my ($path) = ($req // '') =~ m{^GET (/\S*) HTTP};
  while (my $h = <$c>) { last if $h =~ /^\r?\n$/ }
  $path //= '/';
  my $body = `/usr/bin/curl -sS --max-time 5 --cert /run/identity/svid.0.pem --key /run/identity/svid.0.key --cacert /run/gwca/ca.pem '$gw' 2>&1`;
  print $c "HTTP/1.0 200 OK\r\nContent-Length: " . length($body) . "\r\n\r\n$body";
  exit 0;
}
