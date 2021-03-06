#!/usr/local/bin/perl
# Fix Webmin redirect URLs on a list of domains
use strict;
use warnings;
our (%text, %in);
our $module_name;

require './virtualmin-mailman-lib.pl';
&ReadParse();

# Get all the domains
my @doms = ( );
foreach my $id (split(/\0/, $in{'d'})) {
	my $d = &virtual_server::get_domain($id);
	if ($d && &virtual_server::can_edit_domain($d) && $d->{$module_name}) {
		push(@doms, $d);
		}
	}

# Fix them, showing progress
&ui_print_header(undef, $text{'fixurls_title'}, "");

foreach my $d (@doms) {
	print &text('fixurls_fixing', $d->{'dom'},
		    &get_mailman_webmin_url($d)),"<br>\n";
	&virtual_server::obtain_lock_web($d);
	my $err = &fix_webmin_mailman_urls($d);
	if ($err) {
		print &text('fixurls_failed', $err),"<p>\n";
		}
	else {
		print $text{'fixurls_done'},"<p>\n";
		}
	&virtual_server::release_lock_web($d);
	}

&virtual_server::run_post_actions();
&webmin_log("fixurls");

&ui_print_footer("", $text{'index_return'});
