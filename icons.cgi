#!/usr/local/bin/perl
# Output some mailman icon
use strict;
use warnings;
our (%text);
our $icons_dir;

require './virtualmin-mailman-lib.pl';
$ENV{'PATH_INFO'} =~ /^\/(.*)/ ||
	&error($text{'edit_eurl'});
my $icon = $1;
if ($icon =~ /\.\./ || $icon =~ /\0/) {
	&error($text{'edit_eurl'});
	}

my $type = &guess_mime_type("$icons_dir/$icon");
my @st = stat("$icons_dir/$icon");
print "Content-type: $type\n";
print "Content-length: ",$st[7],"\n";
print "Last-Modified: ",&http_date($st[9]),"\n";
print "Expires: ",&http_date(time()+7*24*60*60),"\n";
print "\n";
open(my $ICON, "<", "$icons_dir/$icon");
while(<$ICON>) {
	print $_;
	}
close($ICON);
