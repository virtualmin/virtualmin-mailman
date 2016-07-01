# Functions for setting up mailman mailing lists, for a virtual domain
use strict;
use warnings;
our (%text, %config, %gconfig);
our $module_config_directory;
our $module_name;

BEGIN { push(@INC, ".."); };
eval "use WebminCore;";
&init_config();
&foreign_require("virtual-server", "virtual-server-lib.pl");

my %pconfig = &foreign_config("postfix");
my $postfix_dir;
if ($pconfig{'postfix_config_file'} =~ /^(.*)\//) {
        $postfix_dir = $1;
        }
else {
        $postfix_dir = "/etc/postfix";
        }
our @mailman_aliases = ( "post", "admin", "bounces", "confirm", "join",
		     "leave", "owner", "request", "subscribe", "unsubscribe" );

our $mailman_dir = $config{'mailman_dir'} || "/usr/local/mailman";
our $mailman_var = $config{'mailman_var'} || $mailman_dir;
our $newlist_cmd = "$mailman_dir/bin/newlist";
our $rmlist_cmd = "$mailman_dir/bin/rmlist";
our $mailman_cmd = $config{'mailman_cmd'} || "$mailman_dir/bin/mailman";
if (!-x $mailman_cmd && $config{'alt_mailman_cmd'}) {
	# Hack needed to handle CentOS 4
	$mailman_cmd = $config{'alt_mailman_cmd'};
	}
our $changepw_cmd = "$mailman_dir/bin/change_pw";
our $config_cmd = "$mailman_dir/bin/config_list";
our $withlist_cmd = "$mailman_dir/bin/withlist";
our $lists_dir = "$mailman_var/lists";
our $archives_dir = "$mailman_var/archives";
our $maillist_map = "relay_domains";
our $maillist_file = "$postfix_dir/maillists";
our $transport_map = "transport_maps";
our $cgi_dir = "$mailman_dir/cgi-bin";
our $icons_dir = "$mailman_dir/icons";
our $mailman_config = "$mailman_var/Mailman/mm_cfg.py";
if (!-r $mailman_config) {
	$mailman_config = "$mailman_dir/Mailman/mm_cfg.py";
	}

our %access = &get_module_acl();

our $lists_file = "$module_config_directory/list-domains";

sub get_mailman_version
{
my $out = `$mailman_dir/bin/version 2>/dev/null </dev/null`;
if ($out =~ /version\s+(\S+)/i || $out =~ /version:\s+(\S+)/i) {
	return $1;
	}
return undef;
}

# list_lists()
# Returns a list of mailing lists and domains and descriptions
sub list_lists
{
my @rv;
my %lists;
&read_file($lists_file, \%lists);
opendir(DIR, $lists_dir);
my $f;
while($f = readdir(DIR)) {
	next if ($f eq "." || $f eq "..");
	my ($dom, $desc) = split(/\t+/, $lists{$f}, 2);
	if (!$desc && $f eq 'mailman') {
		$desc = $text{'feat_adminlist'};
		}
	push(@rv, { 'list' => $f,
		    'dom' => $dom,
		    'desc' => $desc });
	}
closedir(DIR);
return @rv;
}

# can_edit_list(&list)
sub can_edit_list
{
foreach my $d (split(/\s+/, $access{'dom'})) {
	return 1 if ($d eq "*" || $d eq $_[0]->{'dom'});
	}
return 0;
}

sub mailman_check
{
return &text('feat_emailmancmd', "<tt>$mailman_cmd</tt>")
	if (!&has_command($mailman_cmd));
return &text('feat_emailman', "<tt>$mailman_dir</tt>")
	if (!-d $mailman_dir || !-d "$mailman_dir/bin");
return &text('feat_emailman2', "<tt>$mailman_var</tt>")
	if (!-d $mailman_var || !-d "$mailman_var/lists");
if ($config{'mode'} == 0) {
	# Check special postfix files
	return &text('feat_efile', "<tt>$maillist_file</tt>")
		if (!-r $maillist_file);
	my %vconfig = &foreign_config("virtual-server");
	return $text{'feat_epostfix'} if ($vconfig{'mail_system'} != 0);
	&foreign_require("postfix", "postfix-lib.pl");
	my @files = &postfix::get_maps_files(
			&postfix::get_real_value($transport_map));
	return $text{'feat_etransport'} if (!@files);
	@files = &postfix::get_maps_files(
			&postfix::get_real_value($maillist_map));
	return $text{'feat_emaillist'} if (!@files);
	}
# Make sure the www user has a valid shell, for use with su. Not needed on
# Linux, as we can pass -s to the su command.
if ($gconfig{'os_type'} !~ /-linux$/) {
	my $user = &get_mailman_apache_user();
	my @uinfo = getpwnam($user);
	if (@uinfo && $uinfo[8] =~ /nologin/) {
		return &text('feat_emailmanuser', "<tt>$user</tt>", "<tt>$uinfo[8]</tt>");
		}
	}
return undef;
}

# create_list(name, domain, desc, language, email, pass)
# Create a new mailing list, and returns undef on success or an error
# message on failure.
sub create_list
{
my ($list, $dom, $desc, $lang, $email, $pass) = @_;
my $full_list = $list;
if ($config{'append_prefix'}) {
	$full_list .= "_".$dom;
	}

# Make sure our hostname is set properly
my $conf = &get_mailman_config();
foreach my $c ("DEFAULT_URL_HOST", "DEFAULT_EMAIL_HOST") {
	my $url = &find_value($c, $conf);
	if ($url && $url =~ /has_not_been_edited|hardy2/) {
		&save_directive($conf, $c, &get_system_hostname());
		}
	}

# Construct and call the list creation command
my @args = ( $newlist_cmd );
if ($lang) {
	push(@args, "-l", $lang);
	}
if (&get_mailman_version() < 2.1) {
	push(@args, $full_list);
	}
elsif (!$dom) {
	push(@args, $full_list);
	}
elsif ($config{'mode'} == 0) {
	push(@args, "$full_list\@lists.$dom");
	}
else {
	push(@args, "$full_list\@$dom");
	}
push(@args, $email);
push(@args, $pass);
my $cmd = join(" ", map { $_ eq '' ? '""' : quotemeta($_) } @args);
my $out = &backquote_logged("$cmd 2>&1 </dev/null");
if ($?) {
	return &text('add_ecmd', "<pre>".&html_escape($out)."</pre>");
	}

if ($dom) {
	# Save domain and description
	&lock_file($lists_file);
  my %lists;
	&read_file($lists_file, \%lists);
	$lists{$full_list} = $dom."\t".$desc;
	&write_file($lists_file, \%lists);
	&unlock_file($lists_file);
	}

if ($config{'mode'} == 1 && $dom) {
	# Add aliases
	&virtual_server::obtain_lock_mail()
		if (defined(&virtual_server::obtain_lock_mail));
	my $a;
	foreach my $a (@mailman_aliases) {
		my $virt = { 'from' => ($a eq "post" ? $list :
					   "$list-$a")."\@".$dom,
				'to' => [ "|$mailman_cmd $a $full_list" ] };
		&virtual_server::create_virtuser($virt);
		}
	# Sync alias copy virtusers, if supported
	my $d = &virtual_server::get_domain_by("dom", $dom);
	if ($d && defined(&virtual_server::sync_alias_virtuals)) {
		&virtual_server::sync_alias_virtuals($d);
		}
	&virtual_server::release_lock_mail()
		if (defined(&virtual_server::release_lock_mail));
	}
return undef;
}

# delete_list(name, domain)
sub delete_list
{
my ($list, $dom) = @_;
my $short_list = $list;
$short_list =~ s/\_\Q$dom\E$//;

# Run the remove command
my $out = &backquote_logged("$rmlist_cmd -a $list 2>&1 </dev/null");
if ($?) {
	return "<pre>$out</pre>";
	}

# Delete from domain map
&lock_file($lists_file);
my %lists;
&read_file($lists_file, \%lists);
delete($lists{$list});
&write_file($lists_file, \%lists);
&unlock_file($lists_file);

if ($config{'mode'} == 1) {
	# Remove aliases
	my $d = &virtual_server::get_domain_by("dom", $dom);
	&virtual_server::obtain_lock_mail($d)
		if (defined(&virtual_server::obtain_lock_mail));
	my @virts = &virtual_server::list_domain_aliases($d);
	my $a;
	foreach my $a (@mailman_aliases) {
		my $vn = ($a eq "post" ? $list
					  : "$list-$a")."\@".$dom;
		my $short_vn = ($a eq "post" ? $short_list
					        : "$short_list-$a")."\@".$dom;
		my ($virt) = grep { $_->{'from'} eq $vn ||
				       $_->{'from'} eq $short_vn } @virts;
		if ($virt) {
			&virtual_server::delete_virtuser($virt);
			}
		}
	# Sync alias copy virtusers, if supported
	if (defined(&virtual_server::sync_alias_virtuals)) {
		&virtual_server::sync_alias_virtuals($d);
		}
	&virtual_server::release_lock_mail()
		if (defined(&virtual_server::release_lock_mail));
	}
}

# list_members(&list)
# Returns an array of user structures for some list
sub list_members
{
my @rv;
open(my $MEMS, "<", "$mailman_dir/bin/list_members -r $_[0]->{'list'} |");
while(<$MEMS>) {
	s/\r|\n//g;
	push(@rv, { 'email' => $_, 'digest' => 'n' });
	}
close($MEMS);
open($MEMS, "<", "$mailman_dir/bin/list_members -d $_[0]->{'list'} |");
while(<$MEMS>) {
	s/\r|\n//g;
	push(@rv, { 'email' => $_, 'digest' => 'y' });
	}
close($MEMS);
return sort { $a->{'email'} cmp $b->{'email'} } @rv;
}

# add_member(&member, &list)
# Add one subscriber to a list
sub add_member
{
my $temp = &transname();
my $cmd = "$mailman_dir/bin/add_members";
if ($_[0]->{'digest'} eq 'y') {
	$cmd .= " -d $temp";
	}
else {
	$cmd .= " -r $temp";
	}
if ($_[0]->{'welcome'}) {
	$cmd .= " -w ".$_[0]->{'welcome'};
	}
if ($_[0]->{'admin'}) {
	$cmd .= " -a ".$_[0]->{'admin'};
	}
$cmd .= " $_[1]->{'list'}";
open(my $TEMP, ">", "$temp");
print $TEMP "$_[0]->{'email'}\n";
close($TEMP);
my $out = &backquote_logged("$cmd <$temp 2>&1");
return $? ? $out : undef;
}

# remove_member(&member, &list)
# Deletes one person from a mailing list
sub remove_member
{
my $temp = &transname();
my $cmd = "$mailman_dir/bin/remove_members -f $temp $_[1]->{'list'}";
open(my $TEMP, ">", "$temp");
print $TEMP "$_[0]->{'email'}\n";
close($TEMP);
my $out = &backquote_logged("$cmd <$temp 2>&1");
return $? ? $out : undef;
}

# list_mailman_languages()
# Returns a list of all language codes know to Mailman
sub list_mailman_languages
{
my $tdir = $config{'mailman_templates'};
if (!$tdir || !-d $tdir) {
	$tdir = "$mailman_dir/templates";
	}
opendir(DIR, $tdir);
my @rv = grep { $_ !~ /^\./ &&
		   $_ !~ /\.(txt|html)$/i &&
		   -d "$tdir/$_" } readdir(DIR);
closedir(DIR);
return sort { $a cmp $b } @rv;
}

# get_mailman_config()
# Returns an array ref of mailman config options
my @mailman_config_cache;
sub get_mailman_config
{
if (!scalar(@mailman_config_cache)) {
	my $lnum = 0;
	open(my $CONF, "<", "$mailman_config");
	while(<$CONF>) {
		s/\r|\n//g;
		s/^\s*#.*$//;
		if (/^\s*(\S+)\s*=\s*'(.*)'/ ||
		    /^\s*(\S+)\s*=\s*"(.*)"/ ||
		    /^\s*(\S+)\s*=\s*\S+/) {
			push(@mailman_config_cache,
				{ 'name' => $1,
				  'value' => $2,
				  'line' => $lnum });
			}
		$lnum++;
		}
	close($CONF);
	}
return \@mailman_config_cache;
}

# find(name, &conf)
sub find
{
my ($rv) = grep { $_->{'name'} eq $_[0] } @{$_[1]};
return $rv;
}

# find_value(name, &conf)
sub find_value
{
my $rv = &find(@_);
return $rv ? $rv->{'value'} : undef;
}

# save_directive(&conf, name, value)
# Updates a setting in the mailman config
sub save_directive
{
my ($conf, $name, $value) = @_;
my $old = &find($name, $conf);
my $lref = &read_file_lines($mailman_config);
my $newline;
if (defined($value)) {
	$newline = "$name = ";
	if ($value =~ /^[0-9\.]+$/) {
		$newline .= $value;
		}
	elsif ($value =~ /'/) {
		$newline .= "\"$value\"";
		}
	else {
		$newline .= "'$value'";
		}
	}
if ($old && defined($value)) {
	# Just update
	$lref->[$old->{'line'}] = $newline;
	$old->{'value'} = $value;
	}
elsif ($old && !defined($value)) {
	# Take this value out
	splice(@$lref, $old->{'line'}, 1);
	@$conf = grep { $_ ne $old } @$conf;
	foreach my $c (@$conf) {
		$c->{'line'}-- if ($c->{'line'} > $old->{'line'});
		}
	}
elsif (!$old && defined($value)) {
	# Add a value
	push(@$conf, { 'name' => $name,
		       'value' => $value,
		       'line' => scalar(@$lref) });
	push(@$lref, $newline);
	}
&flush_file_lines($mailman_config);
}

# get_list_config(list, [name])
# Returns the configuration for some list as a hash reference, or a single
# config option if 'name' is given
sub get_list_config
{
my ($list, $name) = @_;
if ($name) {
	my $c = &get_list_config($list);
	return $c->{$name};
	}
my $temp = &transname();
&execute_command("$config_cmd -o ".quotemeta($temp)." ".
		 quotemeta($list));
my %rv;
open(my $CONFIG, "<", $temp);
while(<$CONFIG>) {
	s/\r|\n//g;
	s/^\s*#.*$//;
	if (/^\s*(\S+)\s*=\s*'(.*)'/ ||
	    /^\s*(\S+)\s*=\s*"(.*)"/ ||
	    /^\s*(\S+)\s*=\s*(\d+)/) {
		# Single value
		$rv{$1} = $2;
		}
	elsif (/^\s*(\S+)\s*=\s*\[(.*)\]/) {
		# A list of values
		my ($name, $values) = ($1, $2);
		my @values;
		while($values =~ /,?'([^']*)'(.*)/ ||
		      $values =~ /,?"([^"]*)"(.*)/ ||
		      $values =~ /,?(\d+)(.*)/) {
			push(@values, $1);
			$values = $2;
			}
		$rv{$name} = \@values;
		}
	elsif (/^\s*(\S+)\s*=\s*"""/) {
		# Multiline value
		my $name = $1;
		my $value;
		while(1) {
			my $line = <$CONFIG>;
			last if (!$line || $line =~ /^"""/);
			if ($line =~ /^(.*)"""/) {
				$value .= $1;
				last;
				}
			else {
				$value .= $line;
				}
			}
		$rv{$name} = $value;
		}
	}
close($CONFIG);
return \%rv;
}

# get_mailman_apache_user([&domain])
sub get_mailman_apache_user
{
my ($d) = @_;
if ($config{'cgiuser'}) {
	return $config{'cgiuser'};
	}
elsif (defined(&virtual_server::get_apache_user)) {
	return &virtual_server::get_apache_user($d);
	}
else {
	foreach my $u ("www", "httpd", "apache") {
		if (defined(getpwnam($u))) {
			return $u;
			}
		}
	return "nobody";
	}
}

# needs_mailman_list()
# Returns 1 if a list named 'mailman' is needed and missing
sub needs_mailman_list
{
my $ver = &get_mailman_version();
if ($ver < 2.1) {
	# Older versions don't
	return 0;
	}
my @lists = &list_lists();
my ($mailman) = grep { $_->{'list'} eq 'mailman' } @lists;
if ($mailman) {
	# Already exists
	return 0;
	}
&foreign_require("init", "init-lib.pl");
if (&init::action_status("mailman") == 0) {
	# No queue runner
	return 0;
	}
return 1;
}

sub http_date
{
my @weekday = ( "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" );
my @month = ( "Jan", "Feb", "Mar", "Apr", "May", "Jun",
	   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" );
my @tm = gmtime($_[0]);
return sprintf "%s, %d %s %d %2.2d:%2.2d:%2.2d GMT",
		$weekday[$tm[6]], $tm[3], $month[$tm[4]], $tm[5]+1900,
		$tm[2], $tm[1], $tm[0];
}

# save_list_config(list, name, value)
# Update a single config setting for a list. The value must be in a python
# format, like 'foo' or ['smeg', 'spod']
sub save_list_config
{
my ($list, $name, $value) = @_;
my $temp = &transname();
no strict "subs";
&open_tempfile(CONFIG, ">$temp");
&print_tempfile(CONFIG, $name." = ".$value."\n");
&close_tempfile(CONFIG);
use strict "subs";
my $out = &backquote_command("$config_cmd -i ".quotemeta($temp).
				" ".quotemeta($list)." 2>&1 </dev/null");
return $? ? $out : undef;
}

# get_mailman_webmin_url(&domain)
# Returns the correct URL for Webmin for redirects
sub get_mailman_webmin_url
{
my ($d) = @_;
my $webminurl;
if ($config{'webminurl'}) {
	$webminurl = $config{'webminurl'};
	$webminurl =~ s/\/+$//;
	}
elsif ($ENV{'SERVER_PORT'}) {
	# Running inside Webmin
	$webminurl = uc($ENV{'HTTPS'}) eq "ON" ? "https"
					       : "http";
	$webminurl .= "://$d->{'dom'}:$ENV{'SERVER_PORT'}";
	}
else {
	# From command line
	my %miniserv;
	&get_miniserv_config(\%miniserv);
	$webminurl = $miniserv{'ssl'} ? "https" : "http";
	$webminurl .= "://$d->{'dom'}:$miniserv{'port'}";
	}
return $webminurl;
}

# check_webmin_mailman_urls(&domain)
# Returns 1 if all redirects look OK, 0 if not
sub check_webmin_mailman_urls
{
my ($d) = @_;
my @ports = ( $d->{'web_port'},
	      $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
my $webminurl = &get_mailman_webmin_url($d);
foreach my $p (@ports) {
	my ($virt, $vconf) = &virtual_server::get_apache_virtual(
				$d->{'dom'}, $p);
	my @rm = &apache::find_directive_struct("RedirectMatch", $vconf);
	foreach my $p ("/cgi-bin/mailman", "/mailman") {
		my ($rm) = grep { $_->{'words'}->[0] =~ /^\Q$p\E/ } @rm;
		return 0 if (!$rm ||
			     $rm->{'words'}->[1] !~ /^\Q$webminurl\E\//);
		}
	}
return 1;
}

# fix_webmin_mailman_urls(&domain)
# Correct all mailman redirects to use current Webmin paths
sub fix_webmin_mailman_urls
{
my ($d) = @_;
my @ports = ( $d->{'web_port'},
	      $d->{'ssl'} ? ( $d->{'web_sslport'} ) : ( ) );
my $webminurl = &get_mailman_webmin_url($d);
foreach my $p (@ports) {
	my ($virt, $vconf, $conf) = &virtual_server::get_apache_virtual(
					$d->{'dom'}, $p);
	next if (!$virt);
	my @rm = &apache::find_directive("RedirectMatch", $vconf);
	foreach my $p ("/cgi-bin/mailman", "/mailman") {
		@rm = grep { !/^\Q$p\E\// } @rm;
		push(@rm, "$p/([^/\\.]*)(.cgi)?(.*) ".
			  "$webminurl/$module_name/".
			  "unauthenticated/\$1.cgi\$3");
		}
	&apache::save_directive("RedirectMatch", \@rm, $vconf, $conf);
	&flush_file_lines($virt->{'file'});
	}
&virtual_server::register_post_action(\&virtual_server::restart_apache);
return undef;
}

1;
