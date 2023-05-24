#!/usr/local/bin/perl
# Remove one mailing list
use strict;
use warnings;
our (%text, %in, %config);

require './virtualmin-mailman-lib.pl';
&ReadParse();
&error_setup($text{'delete_err'});

my @lists = &list_lists();
my ($listname) = grep { $_ ne "confirm" && $_ ne "show" } keys %in;

if ($listname =~ /^mems_(\S+)$/) {
	# Actually editing members .. redirect
	&redirect("list_mems.cgi?list=$1&show=$in{'show'}");
	exit;
	}
elsif ($listname =~ /^man_(\S+)$/) {
	# Actually managing list .. redirect
	# XXX
	if ($config{'manage_url'}) {
		# Custom URL
		my ($list) = grep { $_->{'list'} eq $1 } @lists;
		my $d = &virtual_server::get_domain_by("dom", $list->{'dom'});
		&redirect(&virtual_server::substitute_domain_template(
				$config{'manage_url'}, $d));
		}
	else {
		# Internal CGI wrappers
		&redirect("admin.cgi/$1");
		}
	exit;
	}
elsif ($listname =~ /^reset_(\S+)$/) {
	# Actually resetting password .. redirect
	&redirect("reset.cgi?list=$1");
	exit;
	}

# Get the list
$listname eq "mailman" && &error($text{'delete_emailman'});
my ($list) = grep { $_->{'list'} eq $listname } @lists;
&can_edit_list($list) || &error($text{'delete_ecannot'});
my $d = &virtual_server::get_domain_by("dom", $list->{'dom'});
$d || &error($text{'delete_edon'});

if (!$in{'confirm'}) {
	# Ask for confirmation
	&ui_print_header(undef, $text{'delete_title'}, "");
	print &ui_form_start("delete.cgi");
	print &ui_hidden($listname, "Delete"),"\n";
	print "<center>",&text('delete_rusure', $listname),"<p>\n",
	      &ui_submit($text{'delete_confirm'}, "confirm"),"</center>\n";
	print &ui_form_end();
	&ui_print_footer("", $text{'index_return'});
	}
else {
	# Do it
	my $err = &delete_list($listname, $list->{'dom'});
	&error($err) if ($err);

	&redirect("");
	}
