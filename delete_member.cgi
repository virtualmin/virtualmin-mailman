#!/usr/local/bin/perl
# Delete one list member
use strict;
use warnings;
our (%text, %in);

require './virtualmin-mailman-lib.pl';
&ReadParse();
&error_setup($text{'deletemem_err'});
my @lists = &list_lists();
my ($list) = grep { $_->{'list'} eq $in{'list'} } @lists;
&can_edit_list($list) || &error($text{'mems_ecannot'});

my @mems = &list_members($list);
my ($email) = grep { $_ ne "list" && $_ ne "show" } (keys %in);
my ($mem) = grep { $_->{'email'} eq $email } @mems;
$mem || &error($text{'deletemem_emem'});

my $err = &remove_member($mem, $list);
&error($err) if ($err);
&redirect("list_mems.cgi?list=$in{'list'}&show=$in{'show'}");
