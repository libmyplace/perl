#!/usr/bin/perl -w
package MyPlace::MiaoPai;
use strict;
use warnings;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw();
    @EXPORT_OK      = qw(&extract_user_info);
}

sub extract_user_info {
	my $text = shift;
	if($text =~ m/<h1><a[^>]+title="([^"]+)"[^>]+href="[^"]+\/u\/([^\/"\&\?]+)/) {
		return $2,$1,"miaopai.com";
	}
}

1;
