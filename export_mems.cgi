#!/usr/local/bin/perl
# Output text list of members

require './virtualmin-mailman-lib.pl';
&ReadParse();
@lists = &list_lists();
($list) = grep { $_->{'list'} eq $in{'list'} } @lists;
&can_edit_list($list) || &error($text{'mems_ecannot'});

print "Content-type: text/plain\n\n";
foreach $m (&list_members($list)) {
	print $m->{'email'},"\n";
	}

