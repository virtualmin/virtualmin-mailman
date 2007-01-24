#!/usr/local/bin/perl
# Show members of some mailing list, with form to add

require './virtualmin-mailman-lib.pl';
&ReadParse();
@lists = &list_lists();
($list) = grep { $_->{'list'} eq $in{'list'} } @lists;
&can_edit_list($list) || &error($text{'mems_ecannot'});

&ui_print_header(&text('mems_sub', $in{'list'}), $text{'mems_title'}, "");

@mems = &list_members($list);
if (@mems) {
	print &ui_form_start("delete_member.cgi");
	print &ui_hidden("list", $in{'list'}),"\n";
	print &ui_columns_start([ $text{'mems_email'},
				  $text{'mems_type'},
				  $text{'index_action'} ]);
	foreach $m (@mems) {
		print &ui_columns_row([
			$m->{'email'},
			$m->{'digest'} eq 'y' ? $text{'mems_digesty'}
					      : $text{'mems_digestn'},
			&ui_submit($text{'delete'}, $m->{'email'})
			]);
		}
	print &ui_columns_end();
	print &ui_form_end();
	}
else {
	print "<b>$text{'mems_none'}</b><p>\n";
	}

print &ui_form_start("add_member.cgi", "post");
print &ui_hidden("list", $in{'list'}),"\n";
print &ui_table_start($text{'mems_header'}, undef, 2);

print &ui_table_row($text{'mems_email'},
		    &ui_textbox("email", undef, 30));

print &ui_table_row($text{'mems_digest'},
		    &ui_radio("digest", "n",
			      [ [ "y", $text{'yes'} ],
				[ "n", $text{'no'} ] ]));

print &ui_table_row($text{'mems_welcome'},
		    &ui_radio("welcome", "",
			      [ [ "", $text{'mems_default'} ],
				[ "y", $text{'yes'} ],
				[ "n", $text{'no'} ] ]));

print &ui_table_row($text{'mems_admin'},
		    &ui_radio("admin", "",
			      [ [ "", $text{'mems_default'} ],
				[ "y", $text{'yes'} ],
				[ "n", $text{'no'} ] ]));

print &ui_table_end();
print &ui_form_end([ [ "add", $text{'mems_add'} ] ]);

&ui_print_footer("", $text{'index_return'});
