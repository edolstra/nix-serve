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

my $app = sub {
    my $env = shift;
    my $path = $env->{PATH_INFO};

    # log to journald
    print "$env->{REQUEST_METHOD} $path\n";

    if ($path eq "/nix-cache-info") {
        return [200, ['Content-Type' => 'text/plain'], ["StoreDir: $Nix::Config::storeDir\nWantMassQuery: 1\nPriority: 30\n"]];
    }

    elsif ($path =~ /^\/([0-9a-z]+)\.narinfo$/) {
        my $hashPart = $1;
        my $storePath = queryPathFromHashPart($hashPart);
        return [404, ['Content-Type' => 'text/plain'], ["No such path.\n"]] unless $storePath;
        my ($deriver, $narHash, $time, $narSize, $refs, $sigs) = queryPathInfo($storePath, 1) or die;
        my $res =
            "StorePath: $storePath\n" .
            "URL: nar/$hashPart.nar\n" .
            "Compression: none\n" .
            "NarHash: $narHash\n" .
            "NarSize: $narSize\n";
        $res .= "References: " . join(" ", map { stripPath($_) } @$refs) . "\n"
            if scalar @$refs > 0;
        $res .= "Deriver: " . stripPath($deriver) . "\n" if defined $deriver;
        my $secretKeyFile = $ENV{'NIX_SECRET_KEY_FILE'};
        if (defined $secretKeyFile) {
            my $secretKey = readFile $secretKeyFile;
            chomp $secretKey;
            my $fingerprint = fingerprintPath($storePath, $narHash, $narSize, $refs);
            my $sig = signString($secretKey, $fingerprint);
            $res .= "Sig: $sig\n";
        } elsif (defined $sigs) {
            $res .= join("\n", map { "Sig: $_" } @$sigs) . "\n";
        }
        return [200, ['Content-Type' => 'text/x-nix-narinfo'], [$res]];
    }

    elsif ($path =~ /^\/nar\/([0-9a-z]+)\.nar$/) {
        my $hashPart = $1;
        my $storePath = queryPathFromHashPart($hashPart);
        return [404, ['Content-Type' => 'text/plain'], ["No such path.\n"]] unless $storePath;
        my $fh = new IO::Handle;
        open $fh, "-|", "nix-store", "--dump", "--", $storePath;
        return [200, ['Content-Type' => 'text/plain'], $fh];
    }

    else {
        return [404, ['Content-Type' => 'text/plain'], ["File not found.\n"]];
    }
}
