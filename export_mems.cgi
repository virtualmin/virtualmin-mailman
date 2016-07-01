#!/usr/local/bin/perl
# Output text list of members
use strict;
use warnings;
our (%text, %in);

require './virtualmin-mailman-lib.pl';
&ReadParse();
my @lists = &list_lists();
my ($list) = grep { $_->{'list'} eq $in{'list'} } @lists;
&can_edit_list($list) || &error($text{'mems_ecannot'});

print "Content-type: text/plain\n\n";
foreach my $m (&list_members($list)) {
	print $m->{'email'},"\n";
	}
