use MIME::Base64;
use Nix::Config;
use Nix::Manifest;
use Nix::Store;
use Nix::Utils;
use strict;

sub stripPath {
    my ($x) = @_;
    $x =~ s/.*\///; $x
}

my $secretKey;
BEGIN {
	my $secretKeyFile = $ENV{'NIX_SECRET_KEY_FILE'};
	if (defined $secretKeyFile) {
		$secretKey = readFile $secretKeyFile;
		chomp $secretKey;
	}
}

my $app = sub {
    my $env = shift;
    my $path = $env->{PATH_INFO};

    if ($path eq "/nix-cache-info") {
        return [200, ['Content-Type' => 'text/plain'], ["StoreDir: $Nix::Config::storeDir\nWantMassQuery: 1\nPriority: 30\n"]];
    }

    elsif ($path =~ /^\/([0-9a-z]+)\.narinfo$/) {
        my $hashPart = $1;
        my $storePath = queryPathFromHashPart($hashPart);
        return [404, ['Content-Type' => 'text/plain'], ["No such path.\n"]] unless $storePath;
        my ($deriver, $narHash, $time, $narSize, $refs, $sigs) = queryPathInfo($storePath, 1) or die;
        $narHash =~ /^sha256:(.*)/ or die;
        my $narHash2 = $1;
        die unless length($narHash2) == 52;
        my $res =
            "StorePath: $storePath\n" .
            "URL: nar/$hashPart-$narHash2.nar\n" .
            "Compression: none\n" .
            "NarHash: $narHash\n" .
            "NarSize: $narSize\n";
        $res .= "References: " . join(" ", map { stripPath($_) } @$refs) . "\n"
            if scalar @$refs > 0;
        $res .= "Deriver: " . stripPath($deriver) . "\n" if defined $deriver;
        if (defined $secretKey) {
            my $fingerprint = fingerprintPath($storePath, $narHash, $narSize, $refs);
            my $sig = signString($secretKey, $fingerprint);
            $res .= "Sig: $sig\n";
        } elsif (defined $sigs) {
            $res .= join("", map { "Sig: $_\n" } @$sigs);
        }
        return [200, ['Content-Type' => 'text/x-nix-narinfo', 'Content-Length' => length($res)], [$res]];
    }

    elsif ($path =~ /^\/nar\/([0-9a-z]+)-([0-9a-z]+)\.nar$/) {
        my $hashPart = $1;
        my $expectedNarHash = $2;
        my $storePath = queryPathFromHashPart($hashPart);
        return [404, ['Content-Type' => 'text/plain'], ["No such path.\n"]] unless $storePath;
        my ($deriver, $narHash, $time, $narSize, $refs, $sigs) = queryPathInfo($storePath, 1) or die;
        return [404, ['Content-Type' => 'text/plain'], ["Incorrect NAR hash. Maybe the path has been recreated.\n"]]
            unless $narHash eq "sha256:$expectedNarHash";
        my $fh = new IO::Handle;
        open $fh, "-|", "nix", "dump-path", "--", $storePath;
        return [200, ['Content-Type' => 'text/plain', 'Content-Length' => $narSize], $fh];
    }

    # FIXME: remove soon.
    elsif ($path =~ /^\/nar\/([0-9a-z]+)\.nar$/) {
        my $hashPart = $1;
        my $storePath = queryPathFromHashPart($hashPart);
        return [404, ['Content-Type' => 'text/plain'], ["No such path.\n"]] unless $storePath;
        my ($deriver, $narHash, $time, $narSize, $refs) = queryPathInfo($storePath, 1) or die;
        my $fh = new IO::Handle;
        open $fh, "-|", "nix", "dump-path", "--", $storePath;
        return [200, ['Content-Type' => 'text/plain', 'Content-Length' => $narSize], $fh];
    }

    elsif ($path =~ /^\/log\/([0-9a-z]+-[0-9a-zA-Z\+\-\.\_\?\=]+)/) {
        my $storePath = "$Nix::Config::storeDir/$1";
        my $fh = new IO::Handle;
        open $fh, "-|", "nix", "log", $storePath;
        return [200, ['Content-Type' => 'text/plain' ], $fh];
    }

    else {
        return [404, ['Content-Type' => 'text/plain'], ["File not found.\n"]];
    }
}
