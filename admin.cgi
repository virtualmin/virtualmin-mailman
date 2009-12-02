#!/usr/local/bin/perl
# Run a mailman CGI program, and display output with Webmin header

require './virtualmin-mailman-lib.pl';
if ($ENV{'PATH_INFO'} =~ /^\/([^\/]+)(.*)/) {
	$lname = $1;
	}
elsif ($ENV{'PATH_INFO'} eq '' || $ENV{'PATH_INFO'} eq '/') {
	# No list name
	$lname = '';
	}
else {
	&error($text{'edit_eurl'});
	}
$prog = $ENV{'SCRIPT_NAME'};
$prog =~ s/^.*\///;
$prog =~ s/\.cgi$//;

@lists = &list_lists();
if ($lname) {
	# Get the list, and from it the domain
	($list) = grep { $_->{'list'} eq $lname } @lists;
	&can_edit_list($list) || &error($text{'edit_ecannot'});
	$d = &virtual_server::get_domain_by("dom", $list->{'dom'});
	}
else {
	# Get the domain from the URL
	$dname = $ENV{'HTTP_HOST'};
	$dname =~ s/:\d+$//;
	$d = &virtual_server::get_domain_by("dom", $dname);
	if (!$d) {
		$dname =~ s/^(www|ftp|mail|lists)\.//i;
		$d = &virtual_server::get_domain_by("dom", $dname);
		}
	$dname || &error(&text('edit_edname', &html_escape($dname)));
	}

$cgiuser = &get_mailman_apache_user($d);
if ($config{'rewriteurl'}) {
	# Custom URL for Mailman, perhaps if behind proxy
	($httphost, $httpport, $httppage, $httpssl) =
		&parse_http_url($config{'rewriteurl'});
	$httphost .= ":".$httpport if ($httpport != ($httpssl ? 443 : 80));
	$prot = $httpssl ? "https" : "http";
	}
else {
	# Same as supplied by browser
	$httphost = $ENV{'HTTP_HOST'};
	if ($httphost !~ /:\d+$/) {
		# Need to add the port
		$httphost .= ":".$ENV{'SERVER_PORT'};
		}
	$prot = $ENV{'HTTPS'} eq 'ON' ? "https" : "http";
	}

# Work out possible hostnames for URLs
@realhosts = ( &get_system_hostname(),
	       (map { $_->{'dom'} } grep { $_->{$module_name} }
			&virtual_server::list_domains()) );

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
$textarea = 0;
open(CGI, "$cmd <$temp |");
while(<CGI>) {
	# Check if we are in a textarea
	if (/<textarea/i) { $textarea = 1; }
	if (/<\/textarea/i) { $textarea = 0; }

	# Replace URLs, if not in input fields
	if (!/<input.*type=\S*text/i && !$textarea) {
		if (!/\.(gif|png|jpg|jpeg)/) {
			s/\/(cgi-bin\/)?mailman\/([^\/ "']+)\.cgi/\/$module_name\/$2.cgi/g || s/\/(cgi-bin\/)?mailman\/([^\/ "']+)([\/ "'])/\/$module_name\/$2.cgi$3/g;
			}
                if (!/pipermail/) {
			foreach $realhost (@realhosts) {
				s/(http|https):\/\/$realhost\//$prot:\/\/$httphost\//g && last;
				}
			s/(http|https):\/\/(lists\.)?$d->{'dom'}\//$prot:\/\/$httphost\//g;
			}
		}
	s/\/(icons|mailmanicons|images)\/(mailman\/)?(\S+\.(gif|png|jpg|jpeg))/\/$module_name\/icons.cgi\/$3/g;
	if (/^Set-Cookie:/i) {
		s/(\/cgi-bin)?\/mailman/\/$module_name/;
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


