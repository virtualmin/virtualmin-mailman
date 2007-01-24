#!/usr/local/bin/perl
# Reset a mailing lists password to a random one

require './virtualmin-mailman-lib.pl';
&ReadParse();
@lists = &list_lists();
($list) = grep { $_->{'list'} eq $in{'list'} } @lists;
&can_edit_list($list) || &error($text{'mems_ecannot'});

&ui_print_header(&text('mems_sub', $in{'list'}), $text{'reset_title'}, "");

$conf = &get_list_config($in{'list'});
print "$text{'reset_doing'}<br>\n";
$out = `$changepw_cmd -l $in{'list'} 2>&1 </dev/null`;
if ($?) {
	print "<pre>$out</pre>\n";
	print "$text{'reset_failed'}<p>\n";
	}
else {
	$email = ref($conf->{'owner'}) ?
			join(", ", @{$conf->{'owner'}}) : $conf->{'owner'};
	print &text('reset_done', $email),"<p>\n";
	}

&ui_print_footer("", $text{'index_return'});
