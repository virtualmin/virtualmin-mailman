#!/usr/local/bin/perl
# Show all mailman lists that this user can manage

require './virtualmin-mailman-lib.pl';
&ReadParse();

$ver = &get_mailman_version();
$desc = $in{'show'} ? &virtual_server::text('indom', $in{'show'}) : undef;
&ui_print_header($desc, $text{'index_title'}, "", undef, 1, 1, 0,
		 undef, undef, undef,
		 $ver ? &text('index_version', $ver) : undef);
$err = &mailman_check();
if ($err) {
	&ui_print_endpage($err);
	}

# Build contents for lists table
@alllists = &list_lists();
@lists = grep { &can_edit_list($_) } @alllists;
if ($in{'show'}) {
	# Only show specified lists
	@lists = grep { $_->{'dom'} eq $in{'show'} } @lists;
	}
@table = ( );
foreach $l (@lists) {
	# Check if we can link to the list info page
	local $infourl;
	if ($l->{'dom'}) {
		$d = &virtual_server::get_domain_by("dom", $l->{'dom'});
		if ($d && $d->{'web'}) {
			local ($virt, $vconf) =
				&virtual_server::get_apache_virtual(
				$d->{'dom'}, $d->{'web_port'});
			local @rm = grep { /^\/mailman\// }
				&apache::find_directive("RedirectMatch",
							$vconf);
			if (@rm) {
				$infourl = "http://$d->{'dom'}/".
				   "mailman/listinfo/$l->{'list'}";
				}
			}
		}

	# Add the row
	push(@table, [
	    $infourl ? "<a href='$infourl'>$l->{'list'}</a>"
		     : $l->{'list'},
	    $l->{'dom'} || "<i>$text{'index_nodom'}</i>",
	    $l->{'desc'},
	    &ui_submit($text{'delete'}, $l->{'list'},
		       $l->{'list'} eq 'mailman')." ".
	    &ui_submit($text{'index_mems'}, "mems_".$l->{'list'})." ".
	    &ui_submit($text{'index_man'}, "man_".$l->{'list'})." ".
	    (-x $changepw_cmd ? 
	      &ui_submit($text{'index_reset'}, "reset_".$l->{'list'}) :
	      "")
	    ]);
	}

# Render table of lists
if ($access{'max'} && $access{'max'} > @lists) {
	print "<b>",&text('index_canadd0', $access{'max'}-@lists),
	      "</b><p>\n";
	}
print &ui_form_columns_table(
	"delete.cgi",
	undef,
	0,
	undef,
	[ [ 'show', $in{'show'} ] ],
	[ $text{'index_list'}, $text{'index_dom'},
	  $text{'index_desc'}, $text{'index_action'} ],
	100,
	\@table,
	undef,
	0,
	undef,
	@alllists ? $text{'index_none'} : $text{'index_none2'});

# Show form to add a list (if allowed)
if ($access{'max'} && @lists >= $access{'max'}) {
	print $text{'index_max'},"<br>\n";
	}
else {
	print &ui_form_start("add.cgi");
	print &ui_hidden("show", $in{'show'});
	print &ui_table_start($text{'index_header'}, undef, 2);
	print &ui_table_row("<b>$text{'index_list'}</b>",
			    &ui_textbox("list", undef, 20), 1);
	if ($access{'dom'} eq '*') {
		print &ui_table_row($text{'index_dom'},
			&ui_select("dom", $in{'show'},
				[ map { [ $_->{'dom'} ] }
				   sort { $a->{'dom'} cmp $b->{'dom'} }
				    grep { $_->{$module_name} } 
				      &virtual_server::list_domains() ]));
		}
	else {
		print &ui_table_row($text{'index_dom'},
		    &ui_select("dom", undef,
			[ map { [ $_ ] } split(/\s+/, $access{'dom'}) ]));
		}

	print &ui_table_row($text{'index_desc'},
			    &ui_textbox("desc", undef, 30), 1);

	print &ui_table_row($text{'index_lang'},
		    &ui_select("lang", $current_lang,
		       [ [ "", "&lt;$text{'default'}&gt;" ],
			 map { [ $_, $_ ] } &list_mailman_languages() ]));

	print &ui_table_row($text{'index_email'},
		    &ui_opt_textbox("email", undef, 30, $text{'index_fv'}), 1);

	print &ui_table_row($text{'index_pass'},
		    &ui_opt_textbox("pass", undef, 30, $text{'index_fv'}), 1);

	print &ui_table_end();
	print &ui_submit($text{'create'});
	print &ui_form_end();
	}

# Show warning and form if 'mailman' list is missing
if (&virtual_server::master_admin() && &needs_mailman_list()) {
	print "<b>",&text('index_mmlist'),"</b><p>\n";
	print &ui_form_start("add.cgi");
	print &ui_hidden("list", "mailman");
	print &ui_table_start($text{'index_mmheader'}, undef, 2,
			      [ "width=30%" ]);

	print &ui_table_row($text{'index_email'},
		    &ui_textbox("email", undef, 30));

	print &ui_table_row($text{'index_pass'},
		    &ui_textbox("pass", undef, 30));

	@doms = grep { $_->{'mail'} } &virtual_server::list_domains();
	if (@doms) {
		print &ui_table_row($text{'index_dom2'},
		    &ui_select("dom", undef,
			[ [ "", "&lt;$text{'index_nodom'}&gt;" ],
			  map { [ $_->{'dom'} ] }
			   sort { $a->{'dom'} cmp $b->{'dom'} } @doms ]));
		}

	print &ui_table_end();
	print &ui_submit($text{'create'});
	print &ui_form_end();
	}

# Form to search for members
print &ui_form_start("search.cgi");
print &ui_hidden("show", $in{'show'});
print &ui_table_start($text{'index_sheader'}, undef, 2);

# Email address
print &ui_table_row($text{'index_semail'},
	&ui_textbox("email", undef, 40));

# This domain or all?
if ($in{'show'}) {
	print &ui_table_row($text{'index_sdoms'},
		&ui_radio("doms", 1, [ [ 1, $text{'index_sdoms1'} ],
				       [ 0, $text{'index_sdoms0'} ] ]));
	}
else {
	print &ui_hidden("doms", 1);
	}

print &ui_table_end();
print &ui_submit($text{'index_search'});
print &ui_form_end();

&ui_print_footer("/", $text{'index'});

