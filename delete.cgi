#!/usr/local/bin/perl
# Remove one mailing list

require './virtualmin-mailman-lib.pl';
&ReadParse();
&error_setup($text{'delete_err'});

@lists = &list_lists();
($listname) = grep { $_ ne "confirm" } keys %in;

if ($listname =~ /^mems_(\S+)$/) {
	# Actually editing members .. redirect
	&redirect("list_mems.cgi?list=$1");
	exit;
	}
elsif ($listname =~ /^man_(\S+)$/) {
	# Actually managing list .. redirect
	if ($config{'manage_url'}) {
		# Custom URL
		($list) = grep { $_->{'list'} eq $1 } @lists;
		$d = &virtual_server::get_domain_by("dom", $list->{'dom'});
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
($list) = grep { $_->{'list'} eq $listname } @lists;
&can_edit_list($list) || &error($text{'delete_ecannot'});
$d = &virtual_server::get_domain_by("dom", $list->{'dom'});
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
	$err = &delete_list($listname, $list->{'dom'});
	&error($err) if ($err);

	&redirect("");
	}

