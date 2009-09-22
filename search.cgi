#!/usr/local/bin/perl
# Search for list members across all lists

require './virtualmin-mailman-lib.pl';
&ReadParse();
&error_setup($text{'search_err'});
$in{'email'} || &error($text{'search_eemail'});

# Get all lists
@alllists = &list_lists();
@lists = grep { &can_edit_list($_) } @alllists;
if (!$in{'doms'}) {
	# In this domain only
	@lists = grep { $_->{'dom'} eq $in{'show'} } @lists;
	}

$desc = $in{'doms'} ? &virtual_server::text('indom', $in{'show'}) : undef;
&ui_print_header($desc, $text{'search_title'}, "");

# Build table of matching emails
@table = ( );
$re = $in{'email'};
foreach my $l (@lists) {
	@mems = &list_members($l);
	foreach my $m (@mems) {
		if ($m->{'email'} =~ /\Q$re\E/i) {
			@acts = ( );
			push(@acts, "<a href='delete_member.cgi?list=".
				    &urlize($l->{'list'})."&".
				    "show=".&urlize($in{'show'})."&".
				    &urlize($m->{'email'})."=1'>".
				    $text{'search_delete'}."</a>");
			push(@acts, "<a href='admin.cgi/$l->{'list'}'>".
				    $text{'search_man'}."</a>");
			push(@table, [ $m->{'email'},
				       $l->{'list'},
				       $l->{'dom'},
				       &ui_links_row(\@acts) ]);
			}
		}
	}

# Show the table
print &ui_columns_table(
	[ $text{'search_email'}, $text{'search_list'},
	  $text{'search_dom'}, $text{'search_actions'} ],
	100,
	\@table,
	undef,
	0,
	undef,
	$text{'search_none'}
	);

&ui_print_footer("index.cgi?show=$in{'show'}", $text{'index_return'});

