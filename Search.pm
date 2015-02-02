package MyPlace::Search;
BEGIN {
#    sub debug_print {
#        return unless($ENV{XR_PERL_MODULE_DEBUG});
#        print STDERR __PACKAGE__," : ",@_;
#    }
#    &debug_print("BEGIN\n");
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw(build_keyword build_url get_url);
}
use MyPlace::Curl;
my $HTTP;

sub build_keyword {
    my $keyword = shift;
	return $keyword;
    my $no_or = shift;
    my @keywords;
    while($keyword =~ m/(["'])([^\1]+)\1|([^\s]+)/g)
    {
        my $word = $2 ? $2 : $3;
        next unless($word);
        $word =~ s/\s+/+/g;
        push @keywords,$word;
    }
    return $no_or ? join("+",@keywords) : join("+OR+",@keywords);
}

sub build_url {
    my ($base,$p_ref) = @_;
    my %params = %{$p_ref};
    my $text =join("&",map ("$_=" . $params{$_},keys %params));
	if(wantarray) {
	    return $base . $text, $base, $text;
	}
	return $base . $text;
}
sub get_url {
    my ($URL,$referer,$decoder,$verbose) = @_;
    print STDERR "Retriving $URL..." if($verbose);
    if(!$HTTP) {
        $HTTP = MyPlace::Curl->new();
    }
    my ($status,$data) =  $HTTP->get($URL,"--referer"=>$referer ? $referer : $URL);
    if(wantarray) {
        return ($status, ($decoder ? $decoder->decode($data) : $data));
    }
    else {
        return $data;
    }
}

1;
