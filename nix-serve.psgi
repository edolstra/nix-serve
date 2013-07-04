use strict;
use Nix::Config;
use Nix::Store;

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
        return [200, ['Content-Type' => 'text/plain'], [$res]];
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
