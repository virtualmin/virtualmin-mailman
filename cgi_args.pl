
do 'virtualmin-mailman-lib.pl';

sub cgi_args
{
my ($cgi) = @_;
my ($d) = grep { &virtual_server::can_edit_domain($_) &&
	         $_->{$module_name} } &virtual_server::list_domains();
if ($cgi eq 'list_mems.cgi') {
	return 'none' if (!$d);
	my @lists = grep { &can_edit_list($_) &&
			   $_->{'dom'} eq $d->{'dom'} } &list_lists();
	return @lists ? 'list='.&urlize($lists[0]->{'list'}) : 'none';
	}
elsif ($cgi eq 'index.cgi') {
	return 'show='.$d->{'dom'};
	}
return undef;
}
