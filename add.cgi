#!/usr/local/bin/perl
# Add a new mailing list, and record it
use strict;
use warnings;
our (%access, %text, %in);
our $remote_user;

require './virtualmin-mailman-lib.pl';
&ReadParse();

# Validate inputs
&error_setup($text{'add_err'});
$in{'list'} = lc($in{'list'});
$in{'list'} =~ /^[a-z0-9\.\-\_]+$/i || &error($text{'add_ename'});
if ($in{'list'} ne 'mailman') {
	$in{'dom'} =~ /^[a-z0-9\.\-]+$/i || &error($text{'add_edom'});
	}
my @lists = &list_lists();
my ($clash) = grep { $_->{'list'} eq $in{'list'} } @lists;
$clash && &error($text{'add_eclash'});
$in{'email_def'} || $in{'email'} =~ /^\S+\@\S+$/ || &error($text{'add_eemail'});
$in{'pass_def'} || $in{'pass'} =~ /\S/ || &error($text{'add_epass'});

# Check limit on lists
my @alllists = &list_lists();
@lists = grep { &can_edit_list($_) } @alllists;
if ($access{'max'} && @lists >= $access{'max'}) {
	&error($text{'index_max'});
	}

if ($in{'list'} eq 'mailman') {
	# The special 'mailman' list has no domain
	my $err = &create_list($in{'list'}, $in{'dom'},
			    "Mailman administration list",
			    undef, $in{'email'}, $in{'pass'});
	&error($err) if ($err);

	# Setup the queue runner, if we can
	&foreign_require("init", "init-lib.pl");
	if (&init::action_status("mailman")) {
		&init::enable_at_boot("mailman");
		&init::stop_action("mailman");
		my ($ok, $err) = &init::start_action("mailman");
		&error(&text('add_einit', "<pre>".&html_escape($err)."</pre>"))
			if (!$ok);
		}
	}
else {
	# Get the Virtualmin domain
	my $vdom = &virtual_server::get_domain_by("dom", $in{'dom'});
	my $parentdom;
	$vdom || &error($text{'add_evdom'});
	if ($vdom->{'parent'}) {
		$parentdom = &virtual_server::get_domain($vdom->{'parent'});
		}

	# Check for a clash on aliases or users
	my @aliases = &virtual_server::list_virtusers();
	my @clash = grep {
		$_->{'from'} eq $in{'list'}.'@'.$vdom->{'dom'} ||
		$_->{'from'} =~ /^\Q$in{'list'}\E\-.*\@\Q$vdom->{'dom'}\E/
		      } @aliases;
	if (@clash) {
		&error(&text('add_ealiases',
			join(" ", map { $_->{'from'} } @clash)));
		}
	my @users = &virtual_server::list_domain_users($vdom);
	@clash = grep {
		$_->{'email'} eq $in{'list'}.'@'.$vdom->{'dom'} ||
		$_->{'email'} =~ /^\Q$in{'list'}\E\-.*\@\Q$vdom->{'dom'}\E/
		      } @users;
	if (@clash) {
		&error(&text('add_eusers',
			join(" ", map { $_->{'user'} } @clash)));
		}

	# Create the list
	my $pass = $in{'pass_def'} && $parentdom ? $parentdom->{'pass'} :
		$in{'pass_def'} ? $vdom->{'pass'} : $in{'pass'};
	$pass || &error(&text('add_epass2', $vdom->{'dom'}));
	my $err = &create_list($in{'list'}, $in{'dom'}, $in{'desc'}, $in{'lang'},
		    $in{'email_def'} && $vdom->{'emailto'} ? $vdom->{'emailto'}:
		    $in{'email_def'} ? "$remote_user\@$in{'dom'}" :
				       $in{'email'},
		    $pass);
	&error($err) if ($err);
	}

&redirect("index.cgi?show=$in{'show'}");
