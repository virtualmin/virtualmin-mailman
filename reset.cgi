#!/usr/local/bin/perl
# Reset a mailing lists password to a random one
use strict;
use warnings;
our (%text, %in);
our $changepw_cmd;

require './virtualmin-mailman-lib.pl';
&ReadParse();
my @lists = &list_lists();
my ($list) = grep { $_->{'list'} eq $in{'list'} } @lists;
&can_edit_list($list) || &error($text{'mems_ecannot'});

&ui_print_header(&text('mems_sub', $in{'list'}), $text{'reset_title'}, "");

my $conf = &get_list_config($in{'list'});
print "$text{'reset_doing'}<br>\n";
my $out = `$changepw_cmd -l $in{'list'} 2>&1 </dev/null`;
if ($?) {
	print "<pre>$out</pre>\n";
	print "$text{'reset_failed'}<p>\n";
	}
else {
	my $email = ref($conf->{'owner'}) ?
			join(", ", @{$conf->{'owner'}}) : $conf->{'owner'};
	print &text('reset_done', $email),"<p>\n";
	}

&ui_print_footer("", $text{'index_return'});
