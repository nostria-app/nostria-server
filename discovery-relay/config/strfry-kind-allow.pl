#!/usr/bin/env perl
use strict;
use warnings;

$| = 1;

my %allowed_kinds = map { $_ => 1 } (3, 10002);

while (my $line = <STDIN>) {
    chomp $line;
    next if $line eq '';

    next if $line !~ /"type":"new"/;

    my ($id) = $line =~ /"id":"([0-9a-f]{64})"/;
    my ($kind) = $line =~ /"kind":([0-9]+)/;

    next if !defined $id;

    if (defined $kind && $allowed_kinds{$kind}) {
        print qq|{"id":"$id","action":"accept"}\n|;
    } else {
        print qq|{"id":"$id","action":"reject","msg":"blocked: only kinds 3 and 10002 are allowed"}\n|;
    }
}