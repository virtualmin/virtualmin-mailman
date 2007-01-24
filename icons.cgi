#!/usr/local/bin/perl
# Output some mailman icon

require './virtualmin-mailman-lib.pl';
$ENV{'PATH_INFO'} =~ /^\/(.*)/ ||
	&error($text{'edit_eurl'});
$icon = $1;
if ($icon =~ /\.\./ || $icon =~ /\0/) {
	&error($text{'edit_eurl'});
	}

$type = &guess_mime_type($icon);
print "Content-type: $type\n\n";
open(ICON, "$icons_dir/$icon");
while(<ICON>) {
	print $_;
	}
close(ICON);

