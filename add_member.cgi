#!/usr/local/bin/perl
# Add one list member
use strict;
use warnings;
our (%text, %in);

require './virtualmin-mailman-lib.pl';
&ReadParse();
&error_setup($text{'addmem_err'});
my @lists = &list_lists();
my ($list) = grep { $_->{'list'} eq $in{'list'} } @lists;
&can_edit_list($list) || &error($text{'mems_ecannot'});

# Validate and store inputs
$in{'email'} =~ /^\S+$/ || &error($text{'addmem_eemail'});
my $mem = { 'email' => $in{'email'},
	 'digest' => $in{'digest'},
	 'welcome' => $in{'welcome'},
	 'admin' => $in{'admin'} };
my $err = &add_member($mem, $list);
&error($err) if ($err);
&redirect("list_mems.cgi?list=$in{'list'}&show=$in{'show'}");
