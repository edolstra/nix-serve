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

    if ($path eq "/nix-cache-info") {
        return [200, ['Content-Type' => 'text/plain'], ["StoreDir: $Nix::Config::storeDir\nWantMassQuery: 1\nPriority: 30\n"]];
    }

    elsif ($path =~ "/([0-9a-z]+)\.narinfo") {
        my $hashPart = $1;
        my $storePath = queryPathFromHashPart($hashPart);
        return [404, ['Content-Type' => 'text/plain'], ["No such path.\n"]] unless $storePath;
        my ($deriver, $narHash, $time, $narSize, $refs) = queryPathInfo($storePath, 1) or die;
        my $res =
            "StorePath: $storePath\n" .
            "URL: nar/$hashPart.nar.bz2\n" .
            "Compression: bzip2\n" .
            "NarHash: $narHash\n" .
            "NarSize: $narSize\n";
        $res .= "References: " . join(" ", map { stripPath($_) } @$refs) . "\n"
            if scalar @$refs > 0;
        $res .= "Deriver: " . stripPath($deriver) . "\n" if defined $deriver;
        my $secretKeyFile = $ENV{'NIX_SECRET_KEY_FILE'};
        if (defined $secretKeyFile) {
            my $s = readFile $secretKeyFile;
            chomp $s;
            my ($keyName, $secretKey) = split ":", $s;
            die "invalid secret key file ‘$secretKeyFile’\n" unless defined $keyName && defined $secretKey;
            my $fingerprint = fingerprintPath($storePath, $narHash, $refs);
            my $sig = encode_base64(signString(decode_base64($secretKey), $fingerprint), "");
            $res .= "Sig: $keyName:$sig\n";
        }
        return [200, ['Content-Type' => 'text/x-nix-narinfo'], [$res]];
    }

    elsif ($path =~ "/nar/([0-9a-z]+)\.nar.bz2") {
        my $hashPart = $1;
        my $storePath = queryPathFromHashPart($hashPart);
        return [404, ['Content-Type' => 'text/plain'], ["No such path.\n"]] unless $storePath;
        my $fh = new IO::Handle;
        open $fh, "nix-store --dump '$storePath' | bzip2 |";
        return [200, ['Content-Type' => 'text/plain'], $fh];
    }

    else {
        return [404, ['Content-Type' => 'text/plain'], ["File not found.\n"]];
    }
}
