#!/usr/local/bin/perl
# Delete one list member

require './virtualmin-mailman-lib.pl';
&ReadParse();
&error_setup($text{'deletemem_err'});
@lists = &list_lists();
($list) = grep { $_->{'list'} eq $in{'list'} } @lists;
&can_edit_list($list) || &error($text{'mems_ecannot'});

@mems = &list_members($list);
($email) = grep { $_ ne "list" && $_ ne "show" } (keys %in);
($mem) = grep { $_->{'email'} eq $email } @mems;
$mem || &error($text{'deletemem_emem'});

$err = &remove_member($mem, $list);
&error($err) if ($err);
&redirect("list_mems.cgi?list=$in{'list'}&show=$in{'show'}");
