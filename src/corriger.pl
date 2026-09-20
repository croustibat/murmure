#!/usr/bin/perl
# Applique les corrections de vocabulaire sur le texte reçu sur stdin.
use strict; use warnings; use utf8;
use open qw(:std :encoding(UTF-8));

my $file = shift // '';
my @rules;
if (open my $fh, '<:encoding(UTF-8)', $file) {
    while (my $line = <$fh>) {
        chomp $line;
        $line =~ s/^\s+|\s+$//g;
        next if $line =~ /^#/ || $line eq '' || $line !~ /\|/;
        my ($from, $to) = split /\|/, $line, 2;
        next unless length $from;
        push @rules, [$from, $to];
    }
    close $fh;
}
my $text = do { local $/; <STDIN> } // '';
for my $r (@rules) {
    my ($from, $to) = @$r;
    $text =~ s/\b\Q$from\E\b/$to/gi;
}
print $text;
