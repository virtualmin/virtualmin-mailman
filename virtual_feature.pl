# Defines functions for this feature

require 'virtualmin-mailman-lib.pl';
$input_name = $module_name;
$input_name =~ s/[^A-Za-z0-9]/_/g;

# feature_name()
# Returns a short name for this feature
sub feature_name
{
return $text{'feat_name'};
}

# feature_losing(&domain)
# Returns a description of what will be deleted when this feature is removed
sub feature_losing
{
return $text{'feat_losing'};
}

# feature_disname(&domain)
# Returns a description of what will be turned off when this feature is disabled
sub feature_disname
{
return $text{'feat_disname'};
}

# feature_label(in-edit-form)
# Returns the name of this feature, as displayed on the domain creation and
# editing form
sub feature_label
{
return $text{'feat_label'};
}

sub feature_hlink
{
return "label";
}

# feature_check()
# Returns undef if all the needed programs for this feature are installed,
# or an error message if not
sub feature_check
{
return &mailman_check();
}

# feature_depends(&domain)
# Returns undef if all pre-requisite features for this domain are enabled,
# or an error message if not
sub feature_depends
{
return $_[0]->{'mail'} ? undef : $text{'feat_edepmail'};
}

# feature_clash(&domain)
# Returns undef if there is no clash for this domain for this feature, or
# an error message if so
sub feature_clash
{
return undef;
}

# feature_suitable([&parentdom], [&aliasdom], [&subdom])
# Returns 1 if some feature can be used with the specified alias and
# parent domains
sub feature_suitable
{
return $_[1] || $_[2] ? 0 : 1;		# not for alias domains
}

# feature_setup(&domain)
# Called when this feature is added, with the domain object as a parameter
sub feature_setup
{
if ($config{'mode'} == 0) {
	# Add postfix config
	&foreign_require("postfix", "postfix-lib.pl");
	&$virtual_server::first_print($text{'setup_map'});
	&virtual_server::create_replace_mapping($maillist_map,
				 { 'name' => "lists.".$_[0]->{'dom'},
				   'value' => "lists.".$_[0]->{'dom'} },
				 [ $maillist_file ]);
	&postfix::regenerate_any_table($maillist_map,
				       [ $maillist_file ]);
	&virtual_server::create_replace_mapping($transport_map,
				 { 'name' => "lists.".$_[0]->{'dom'},
				   'value' => "mailman:" });
	&postfix::regenerate_any_table($transport_map);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});
	}

if ($_[0]->{'web'}) {
	# Add server alias, and redirect for /cgi-bin/mailman and /mailman
	# to anonymous wrappers
	&virtual_server::require_apache();
	&$virtual_server::first_print($text{'setup_alias'});
	local $conf = &apache::get_config();
	local @ports = ( $_[0]->{'web_port'},
			 $_[0]->{'ssl'} ? ( $_[0]->{'web_sslport'} ) : ( ) );
	local $added;
	foreach my $p (@ports) {
		local ($virt, $vconf) = &virtual_server::get_apache_virtual(
			$_[0]->{'dom'}, $p);
		next if (!$virt);

		# Add lists.$domain alias
		local @sa = &apache::find_directive("ServerAlias", $vconf);
		push(@sa, "lists.$_[0]->{'dom'}");
		&apache::save_directive("ServerAlias", \@sa, $vconf, $conf);

		# Add wrapper redirects
		local @rm = &apache::find_directive("RedirectMatch", $vconf);
		local $webminurl;
		if ($config{'webminurl'}) {
			$webminurl = $config{'webminurl'};
			}
		elsif ($ENV{'SERVER_PORT'}) {
			# Running inside Webmin
			$webminurl = uc($ENV{'HTTPS'}) eq "ON" ? "https"
							       : "http";
			$webminurl .= "://$_[0]->{'dom'}:$ENV{'SERVER_PORT'}";
			}
		else {
			# From command line
			local %miniserv;
			&get_miniserv_config(\%miniserv);
			$webminurl = $miniserv{'ssl'} ? "https" : "http";
			$webminurl .= "://$_[0]->{'dom'}:$miniserv{'port'}";
			}
		foreach my $p ("/cgi-bin/mailman", "/mailman") {
			local ($already) = grep { /^\Q$p\E\// } @rm;
			if (!$already) {
				push(@rm, "$p/([^/]*)(.*) ".
					  "$webminurl/$module_name/".
					  "unauthenticated/\$1.cgi\$2");
				}
			}
		&apache::save_directive("RedirectMatch", \@rm, $vconf, $conf);
		$added++;
		}
	if ($added) {
		&flush_file_lines();
		&virtual_server::register_post_action(
		    defined(&main::restart_apache) ? \&main::restart_apache
					   : \&virtual_server::restart_apache);
		&$virtual_server::second_print(
			$virtual_server::text{'setup_done'});
		}
	else {
		&$virtual_server::second_print(
			$virtual_server::text{'delete_noapache'});
		}
	}

# Set default limit from template
if (!exists($_[0]->{$module_name."limit"})) {
	local $tmpl = &virtual_server::get_template($_[0]->{'template'});
	$_[0]->{$module_name."limit"} =
		$tmpl->{$module_name."limit"} eq "none" ? "" :
		 $tmpl->{$module_name."limit"};
	}
}

# feature_modify(&domain, &olddomain)
# Called when a domain with this feature is modified
sub feature_modify
{
if ($_[0]->{'dom'} ne $_[1]->{'dom'} && $config{'mode'} == 0) {
	# Domain has been re-named
	if ($config{'mode'} == 0) {
		# Update filtering
		&feature_delete($_[1]);
		&feature_setup($_[0]);
		}

	# Change domain for any lists
	local %lists;
	&lock_file($lists_file);
	&read_file($lists_file, \%lists);
	foreach my $f (keys %lists) {
		local ($dom, $desc) = split(/\t+/, $lists{$f}, 2);
		if ($dom eq $_[1]->{'dom'}) {
			$dom = $_[0]->{'dom'};
			$lists{$f} = join("\t", $dom, $desc);
			}
		}
	&write_file($lists_file, \%lists);
	&unlock_file($lists_file);
	}
}

# feature_delete(&domain)
# Called when this feature is disabled, or when the domain is being deleted
sub feature_delete
{
if ($config{'mode'} == 0) {
	# Remove postfix config
	&foreign_require("postfix", "postfix-lib.pl");
	&$virtual_server::first_print($text{'delete_map'});
	local $ok = 0;
	local $mmap = &postfix::get_maps($maillist_map, [ $maillist_file ]);
	local ($maillist) = grep { $_->{'name'} eq "lists.".$_[0]->{'dom'} } @$mmap;
	if ($maillist) {
		&postfix::delete_mapping($maillist_map, $maillist);
		&postfix::regenerate_any_table($maillist_map,
					       [ $maillist_file ]);
		$ok++;
		}
	local $tmap = &postfix::get_maps($transport_map);
	local ($trans) = grep { $_->{'name'} eq "lists.".$_[0]->{'dom'} } @$tmap;
	if ($trans) {
		&postfix::delete_mapping($transport_map, $trans);
		&postfix::regenerate_any_table($transport_map);
		$ok++;
		}
	if ($ok == 2) {
		&$virtual_server::second_print($virtual_server::text{'setup_done'});
		}
	else {
		&$virtual_server::second_print($text{'delete_missing'});
		}
	}

if ($_[0]->{'web'}) {
	# Remove server alias and redirects
	&virtual_server::require_apache();
	&$virtual_server::first_print($text{'delete_alias'});
	local $conf = &apache::get_config();
	local @ports = ( $_[0]->{'web_port'},
			 $_[0]->{'ssl'} ? ( $_[0]->{'web_sslport'} ) : ( ) );
	local $deleted;
	foreach my $p (@ports) {
		local ($virt, $vconf) = &virtual_server::get_apache_virtual(
			$_[0]->{'dom'}, $p);
		next if (!$virt);

		# Remove server alias
		local @sa = &apache::find_directive("ServerAlias", $vconf);
		@sa = grep { $_ ne "lists.$_[0]->{'dom'}" } @sa;
		&apache::save_directive("ServerAlias", \@sa, $vconf, $conf);

		# Remove redirects
		local @rm = &apache::find_directive("RedirectMatch", $vconf);
		foreach my $p ("/cgi-bin/mailman", "/mailman") {
			@rm = grep { !/^\Q$p\E\// } @rm;
			}
		&apache::save_directive("RedirectMatch", \@rm, $vconf, $conf);
		$deleted++;
		}
	if ($deleted) {
		&flush_file_lines();
		&virtual_server::register_post_action(
		    defined(&main::restart_apache) ? \&main::restart_apache
					   : \&virtual_server::restart_apache);
		&$virtual_server::second_print(
			$virtual_server::text{'setup_done'});
		}
	else {
		&$virtual_server::second_print(
			$virtual_server::text{'delete_noapache'});
		}
	}

# Remove mailing lists
local @lists = grep { $_->{'dom'} eq $_[0]->{'dom'} } &list_lists();
if (@lists) {
	&$virtual_server::first_print(&text('delete_lists', scalar(@lists)));
	foreach $l (@lists) {
		&delete_list($l->{'list'}, $l->{'dom'});
		}
	&$virtual_server::second_print(
		$virtual_server::text{'setup_done'});
	}
}

# feature_webmin(&main-domain, &all-domains)
# Returns a list of webmin module names and ACL hash references to be set for
# the Webmin user when this feature is enabled
sub feature_webmin
{
local @doms = map { $_->{'dom'} } grep { $_->{$module_name} } @{$_[1]};
if (@doms) {
	return ( [ $module_name,
		   { 'dom' => join(" ", @doms),
		     'max' => $_[0]->{$module_name.'limit'},
		     'noconfig' => 1 } ] );
	}
else {
	return ( );
	}
}

# feature_limits_input(&domain)
# Returns HTML for editing limits related to this plugin
sub feature_limits_input
{
local ($d) = @_;
return undef if (!$d->{$module_name});
return &ui_table_row(&hlink($text{'limits_max'}, "limits_max"),
	&ui_opt_textbox($input_name."limit", $d->{$module_name."limit"},
			4, $virtual_server::text{'form_unlimit'},
			   $virtual_server::text{'form_atmost'}));
}

# feature_limits_parse(&domain, &in)
# Updates the domain with limit inputs generated by feature_limits_input
sub feature_limits_parse
{
local ($d, $in) = @_;
return undef if (!$d->{$module_name});
if ($in->{$input_name."limit_def"}) {
	delete($d->{$module_name."limit"});
	}
else {
	$in->{$input_name."limit"} =~ /^\d+$/ || return $text{'limit_emax'};
	$d->{$module_name."limit"} = $in->{$input_name."limit"};
	}
return undef;
}

# feature_links(&domain)
# Returns an array of link objects for webmin modules for this feature
sub feature_links
{
local ($d) = @_;
return ( { 'mod' => $module_name,
	   'desc' => $text{'links_link'},
	   'page' => 'index.cgi?show='.$d->{'dom'},
	   'cat' => 'services',
	 } );
}

# feature_backup(&domain, file, &opts, &all-opts)
# Create a tar file of all list directories for this domain
sub feature_backup
{
local ($d, $file, $opts, $allopts) = @_;
local @lists = grep { $_->{'dom'} eq $d->{'dom'} } &list_lists();
&$virtual_server::first_print($text{'feat_backup'});

if (!@lists) {
	# No lists, so we can skip most of this
	open(EMPTY, ">$file");
	close(EMPTY);
	if ($opts->{'archive'} && -d $archives_dir) {
		open(EMPTY, ">".$file."_private");
		close(EMPTY);
		open(EMPTY, ">".$file."_public");
		close(EMPTY);
		}
	&$virtual_server::second_print($text{'feat_nolists'});
	return 1;
	}

# Tar up lists directories
local $out = &backquote_command("cd $lists_dir && tar cf ".quotemeta($file)." ".join(" ", map { $_->{'list'} } @lists)." 2>&1");
if ($?) {
	&$virtual_server::second_print(&text('feat_failed', "<pre>$out</pre>"));
	return 0;
	}
else {
	# Create file of list names and descriptions
	local %dlists;
	foreach my $l (@lists) {
		$dlists{$l->{'list'}} = $l->{'desc'};
		}
	&write_file($file."_lists", \%dlists);
	&$virtual_server::second_print($virtual_server::text{'setup_done'});

	# Tar up archive directories, if selected
	if ($opts->{'archive'} && -d $archives_dir) {
		# Tar up private dir
		&$virtual_server::first_print($text{'feat_barchive'});
		local $anyfiles = 0;
		local @files = grep { -e "$archives_dir/private/$_" }
			map { $_->{'list'}, "$_->{'list'}.mbox" } @lists;
		if (@files) {
			local $out = &backquote_command(
				"cd $archives_dir/private && tar cf ".
				quotemeta($file."_private")." ".
				join(" ", @files)." 2>&1");
			if ($?) {
				&$virtual_server::second_print(&text('feat_failed', "<pre>$out</pre>"));
				return 0;
				}
			$anyfiles += scalar(@files);
			}

		# Tar up public dir
		local @files = grep { -e "$archives_dir/public/$_" }
			map { $_->{'list'}, "$_->{'list'}.mbox" } @lists;
		if (@files) {
			local $out = &backquote_command(
				"cd $archives_dir/public && tar cf ".
				quotemeta($file."_public")." ".
				join(" ", @files)." 2>&1");
			if ($?) {
				&$virtual_server::second_print(&text('feat_failed', "<pre>$out</pre>"));
				return 0;
				}
			$anyfiles += scalar(@files);
			}
		if ($anyfiles) {
			&$virtual_server::second_print(
				$virtual_server::text{'setup_done'});
			}
		else {
			&$virtual_server::second_print($text{'feat_noarchive'});
			}
		}

	return 1;
	}
}

# feature_restore(&domain, file, &opts, &all-opts)
# Restore the tar file of all list directories for this domain
sub feature_restore
{
local ($d, $file) = @_;
&$virtual_server::first_print($text{'feat_restore'});

# Delete existing lists
local @lists = grep { $_->{'dom'} eq $d->{'dom'} } &list_lists($d);
foreach my $l (@lists) {
	&delete_list($l->{'list'}, $l->{'dom'});
	}


# Delete old list archives, if they are in the backup
if (-r $file."_public") {
	foreach my $l (@lists) {
		&system_logged("rm -rf ".quotemeta("$archives_dir/public/$l"));
		&system_logged("rm -rf ".quotemeta("$archives_dir/public/$l.mbox"));
		}
	}
if (-r $file."_private") {
	foreach my $l (@lists) {
		&system_logged("rm -rf ".quotemeta("$archives_dir/private/$l"));
		&system_logged("rm -rf ".quotemeta("$archives_dir/private/$l.mbox"));
		}
	}

local @st = stat($file);
if (@st && $st[7] == 0) {
	# Source had no mailing lists .. so nothing to do
	&$virtual_server::second_print($text{'feat_nolists2'});
	return 1;
	}

# Extract lists tar file
local $out = &backquote_command("cd $lists_dir && tar xf ".quotemeta($file)." 2>&1");
if ($?) {
	&$virtual_server::second_print(&text('feat_failed', "<pre>$out</pre>"));
	return 0;
	}
else {
	# Re-add domain and descriptions for lists
	local %dlists;
	&read_file($file."_lists", \%dlists);
	local %lists;
	&read_file($lists_file, \%lists);
	foreach my $l (keys %dlists) {
		$lists{$l} = $d->{'dom'}."\t".$dlists{$l};
		}
	&write_file($lists_file, \%lists);

	# Re-create aliases
	if ($config{'mode'} == 1) {
		foreach my $l (keys %dlists) {
			local $a;
			foreach $a (@mailman_aliases) {
				local $virt = { 'from' => ($a eq "post" ? $l :
						   "$l-$a")."\@".$d->{'dom'},
					'to' => [ "|$mailman_cmd $a $l" ] };
				&virtual_server::create_virtuser($virt);
				}
			}
		}
	&$virtual_server::second_print($virtual_server::text{'setup_done'});

	# If the backup included archives, restore them too
	if (-r $file."_public" || -r $file."_private") {
		&$virtual_server::first_print($text{'feat_rarchive'});
		}
	if (-r $file."_public") {
		local $out = &backquote_command("cd $archives_dir/public && tar xf ".quotemeta($file."_public")." 2>&1");
		if ($?) {
			&$virtual_server::second_print(&text('feat_failed', "<pre>$out</pre>"));
			return 0;
			}
		}
	if (-r $file."_private") {
		local $out = &backquote_command("cd $archives_dir/private && tar xf ".quotemeta($file."_private")." 2>&1");
		if ($?) {
			&$virtual_server::second_print(&text('feat_failed', "<pre>$out</pre>"));
			return 0;
			}

		}
	if (-r $file."_public" || -r $file."_private") {
		&$virtual_server::second_print($virtual_server::text{'setup_done'});
		}

	return 1;
	}
}

# feature_backup_name()
# Returns a description for what is backed up for this feature
sub feature_backup_name
{
return $text{'feat_backupname'};
}

# feature_backup_opts(&opts)
# Returns HTML for selecting options for a backup of this feature
sub feature_backup_opts
{
local ($opts) = @_;
if (-d $archives_dir) {
	return "(".&ui_checkbox("virtualmin_mailman_archive", 1,
			    $text{'feat_archive'}, $opts->{'archive'}).")";
	}
else {
	return undef;
	}
}

# feature_backup_parse(&in)
# Return a hash reference of backup options, based on the given HTML inputs
sub feature_backup_parse
{
local ($in) = @_;
if (-d $archives_dir) {
	return { 'archive' => $in->{'virtualmin_mailman_archive'} };
	}
else {
	return { };
	}
}

# virtusers_ignore([&domain])
# Returns a list of virtuser addresses (like foo@bar.com) that are used by
# mailing lists.
sub virtusers_ignore
{
local ($d) = @_;
local @rv;
foreach my $l (&list_lists()) {
	if ($d && $l->{'dom'} eq $d->{'dom'} ||
	    !$d && $l->{'dom'}) {
		push(@rv, $l->{'list'}."\@".$l->{'dom'});
		foreach my $a (@mailman_aliases) {
			push(@rv, $l->{'list'}."-".$a."\@".$l->{'dom'});
			}
		}
	}
return @rv;
}

# template_input(&template)
# Returns HTML for editing per-template options for this plugin
sub template_input
{
local ($tmpl) = @_;
local $v = $tmpl->{$module_name."limit"};
$v = "none" if (!defined($v) && $tmpl->{'default'});
return &ui_table_row($text{'tmpl_limit'},
	&ui_radio($input_name."_mode",
		  $v eq "" ? 0 : $v eq "none" ? 1 : 2,
		  [ $tmpl->{'default'} ? ( ) : ( [ 0, $text{'default'} ] ),
		    [ 1, $text{'tmpl_unlimit'} ],
		    [ 2, $text{'tmpl_atmost'} ] ])."\n".
	&ui_textbox($input_name, $v eq "none" ? undef : $v, 10));
}

# template_parse(&template, &in)
# Updates the given template object by parsing the inputs generated by
# template_input. All template fields must start with the module name.
sub template_parse
{
local ($tmpl, $in) = @_;
if ($in->{$input_name.'_mode'} == 0) {
	$tmpl->{$module_name."limit"} = "";
	}
elsif ($in->{$input_name.'_mode'} == 1) {
	$tmpl->{$module_name."limit"} = "none";
	}
else {
	$in->{$input_name} =~ /^\d+$/ || &error($text{'tmpl_elimit'});
	$tmpl->{$module_name."limit"} = $in->{$input_name};
	}
}

1;

