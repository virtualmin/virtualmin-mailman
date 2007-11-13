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

@alllists = &list_lists();
@lists = grep { &can_edit_list($_) } @alllists;
if ($in{'show'}) {
	# Only show specified lists
	@lists = grep { $_->{'dom'} eq $in{'show'} } @lists;
	}
if (@lists) {
	if ($access{'max'} && $access{'max'} > @lists) {
		print "<b>",&text('index_canadd0', $access{'max'}-@lists),
		      "</b><p>\n";
		}
	print &ui_form_start("delete.cgi");
	print &ui_columns_start([ $text{'index_list'},
				  $text{'index_dom'},
				  $text{'index_desc'},
				  $text{'index_action'} ]);
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
		print &ui_columns_row([
		    $infourl ? "<a href='$infourl'>$l->{'list'}</a>"
			     : $l->{'list'},
		    $l->{'dom'},
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
	print &ui_columns_end();
	print &ui_form_end();
	}
elsif (@alllists) {
	print "<b>$text{'index_none'}</b><p>\n";
	}
else {
	print "<b>$text{'index_none2'}</b><p>\n";
	}

# Show form to add a list (if allowed)
if ($access{'max'} && @lists >= $access{'max'}) {
	print $text{'index_max'},"<br>\n";
	}
else {
	print &ui_form_start("add.cgi");
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

&ui_print_footer("/", $text{'index'});

