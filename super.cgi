#!/usr/local/bin/perl
# Add or update a Mailman superuser

use strict;
use warnings;
our (%access, %text, %in);

require './virtualmin-mailman-lib.pl';
&ReadParse();
&error_setup($text{'super_err'});

# Validate inputs
$in{'suser'} =~ /^[a-z0-9\_\-\.]+$/i || &error($text{'super_esuser'});
$in{'semail'} =~ /^\S+\@\S+$/ || &error($text{'super_esemail'});
$in{'spass'} =~ /\S/ || &error($text{'super_espass'});

my @supes = &list_django_superusers();
my $err;
if (&indexof($in{'suser'}, @supes) < 0) {
	$err = &create_django_superuser($in{'suser'}, $in{'semail'}, $in{'spass'});
	}
else {
	$err = &set_django_superuser_pass($in{'suser'}, $in{'spass'});
	}
&error($err) if ($err);

&webmin_log("super");
&redirect("");
