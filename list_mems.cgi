#!/usr/local/bin/perl
# Show members of some mailing list, with form to add

require './virtualmin-mailman-lib.pl';
&ReadParse();
@lists = &list_lists();
($list) = grep { $_->{'list'} eq $in{'list'} } @lists;
&can_edit_list($list) || &error($text{'mems_ecannot'});

$desc = &text('mems_sub', $in{'list'});
&ui_print_header($desc, $text{'mems_title'}, "");

# Build data for members table
@mems = &list_members($list);
foreach $m (@mems) {
	push(@table, [
		$m->{'email'},
		$m->{'digest'} eq 'y' ? $text{'mems_digesty'}
				      : $text{'mems_digestn'},
		&ui_submit($text{'delete'}, $m->{'email'})
		]);
	}

# Show members table
print &ui_form_columns_table(
	"delete_member.cgi",
	undef,
	0,
	[ [ "export_mems.cgi?list=".&urlize($in{'list'}).
	    "&show=".&urlize($in{'show'}), $text{'mems_export'} ] ],
	[ [ "list", $in{'list'} ],
	  [ "show", $in{'show'} ] ],
	[ $text{'mems_email'}, $text{'mems_type'}, $text{'index_action'} ],
	undef,
	\@table,
	undef, 0, undef,
	$text{'mems_none'});
	
# Show form to add a new member
print &ui_form_start("add_member.cgi", "post");
print &ui_hidden("list", $in{'list'}),"\n";
print &ui_hidden("show", $in{'show'}),"\n";
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

&ui_print_footer("index.cgi?show=$in{'show'}", $text{'index_return'});
