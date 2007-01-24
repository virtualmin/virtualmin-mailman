#!/usr/local/bin/perl
# Add a new mailing list, and record it

require './virtualmin-mailman-lib.pl';
&ReadParse();

# Validate inputs
&error_setup($text{'add_err'});
$in{'list'} = lc($in{'list'});
$in{'list'} =~ /^[a-z0-9\.\-]+$/i || &error($text{'add_elist'});
$in{'dom'} =~ /^[a-z0-9\.\-]+$/i || &error($text{'add_edom'});
@lists = &list_lists();
($clash) = grep { $_->{'list'} eq $in{'list'} } @lists;
$clash && &error($text{'add_eclash'});
$in{'email_def'} || $in{'email'} =~ /^\S+\@\S+$/ || &error($text{'add_eemail'});
$in{'pass_def'} || $in{'pass'} =~ /\S/ || &error($text{'add_epass'});

# Check limit on lists
@alllists = &list_lists();
@lists = grep { &can_edit_list($_) } @alllists;
if ($access{'max'} && @lists >= $access{'max'}) {
	&error($text{'index_max'});
	}

# Get the Virtualmin domain
$vdom = &virtual_server::get_domain_by("dom", $in{'dom'});
$vdom || &error($text{'add_evdom'});
if ($vdom->{'parent'}) {
	$parentdom = &virtual_server::get_domain($vdom->{'parent'});
	}

# Create the list
$err = &create_list($in{'list'}, $in{'dom'}, $in{'desc'}, $in{'lang'},
	    $in{'email_def'} && $vdom->{'emailto'} ? $vdom->{'emailto'} :
	    $in{'email_def'} ? "$remote_user\@$in{'dom'}" :
			       $in{'email'},
	    $in{'pass_def'} && $parentdom ? $parentdom->{'pass'} :
	    $in{'pass_def'} ? $vdom->{'pass'} : $in{'pass'});
&error($err) if ($err);

&redirect("");

