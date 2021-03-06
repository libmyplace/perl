#!/usr/bin/perl -w
package MyPlace::JSON;
use strict;
use warnings;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw(decode_json encode_json);
    @EXPORT_OK      = qw();
}
use JSON qw//;
sub decode_json {
	my $json = eval { JSON::decode_json($_[0]); };
	if($@) {
		print STDERR "Error deocding JSON text:$@\n";
		$@ = undef;
		return undef;
	}
	else {
		if((ref $json) eq "HASH" and $json->{reason}) {
			print STDERR "Error: " . $json->{reason},"\n";
		}
		return $json;
	}
}

sub encode_json {
	return JSON::encode_json($_[0]);
}
1;
