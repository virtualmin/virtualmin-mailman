#!/usr/local/bin/perl
# Output some mailman icon

require './virtualmin-mailman-lib.pl';
$ENV{'PATH_INFO'} =~ /^\/(.*)/ ||
	&error($text{'edit_eurl'});
$icon = $1;
if ($icon =~ /\.\./ || $icon =~ /\0/) {
	&error($text{'edit_eurl'});
	}

$type = &guess_mime_type("$icons_dir/$icon");
@st = stat("$icons_dir/$icon");
print "Content-type: $type\n";
print "Content-length: ",$st[7],"\n";
print "Last-Modified: ",&http_date($st[9]),"\n";
print "Expires: ",&http_date(time()+7*24*60*60),"\n";
print "\n";
open(ICON, "$icons_dir/$icon");
while(<ICON>) {
	print $_;
	}
close(ICON);

