#!/usr/local/bin/perl
# Run a mailman CGI program, and display output with Webmin header

require './virtualmin-mailman-lib.pl';
$ENV{'PATH_INFO'} =~ /^\/([^\/]+)(.*)/ ||
	&error($text{'edit_eurl'});
$list = $1;
$prog = $ENV{'SCRIPT_NAME'};
$prog =~ s/^.*\///;
$prog =~ s/\.cgi$//;

@lists = &list_lists();
($list) = grep { $_->{'list'} eq $list } @lists;
&can_edit_list($list) || &error($text{'edit_ecannot'});
$d = &virtual_server::get_domain_by("dom", $list->{'dom'});

$cgiuser = &get_mailman_apache_user($d);
$realhost = &get_system_hostname();
$httphost = $ENV{'HTTP_HOST'};
if ($httphost !~ /:\d+$/) {
	# Need to add the port
	$httphost .= ":".$ENV{'SERVER_PORT'};
	}

# Read posted data
$temp = &transname();
open(TEMP, ">$temp");
if (defined(&read_fully)) {
	&read_fully(STDIN, \$qs, $ENV{'CONTENT_LENGTH'});
	}
else {
	read(STDIN, $qs, $ENV{'CONTENT_LENGTH'});
	}
print TEMP $qs;
close(TEMP);

# Run the real command, and fix up output
$cmd = &command_as_user($cgiuser, 0, "$mailman_dir/cgi-bin/$prog");
$prot = $ENV{'HTTPS'} eq 'ON' ? "https" : "http";
open(CGI, "$cmd <$temp |");
while(<CGI>) {
	if (!/<input.*type=\S*text/i) {
		if (!/\.(gif|png|jpg|jpeg)/) {
			s/\/(cgi-bin\/)?mailman\/([^\/ "']+)\.cgi/\/$module_name\/$2.cgi/g || s/\/(cgi-bin\/)?mailman\/([^\/ "']+)/\/$module_name\/$2.cgi/g;
			}
                if (!/pipermail/) {
			s/(http|https):\/\/$realhost\//$prot:\/\/$httphost\//g;
			s/(http|https):\/\/(lists\.)?$d->{'dom'}\//$prot:\/\/$httphost\//g;
			}
		}
	s/\/(icons|mailmanicons|images)\/(mailman\/)?(\S+\.(gif|png|jpg|jpeg))/\/$module_name\/icons.cgi\/$3/g;
	if (/^Set-Cookie:/i) {
		s/\/mailman/\/$module_name/g;
		}
	if (/^(\S+):\s*(.*)\r?\n$/ && !$doneheaders) {
		$headers .= $_;
		}
	elsif (/^\r?\n/) {
		$doneheaders = 1;
		}
	else {
		$body .= $_;
		}
	}
close(CGI);

print $headers;
if ($body =~ /<title>([^>]*)<\/title>/i) {
	$title = $1;
	}
$body =~ s/^[\000-\377]*<body[^>]*>//i;
$body =~ s/<\/body[^>]*>[\000-\377]*//i;
&ui_print_header(undef, $title, "");
print $body;
&ui_print_footer("", $text{'index_return'});


