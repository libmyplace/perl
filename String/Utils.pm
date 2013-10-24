#!/usr/bin/perl -w
use strict;
use warnings;
package MyPlace::String::Utils;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw();
    @EXPORT_OK      = qw(dequote);
}
use utf8;
my $DEBUG=0;
my @QUOTES = (
	[qw/【 】/],
	[qw/\[ \]/],
	[qw/\( \)/],
	[qw/《 》/],
	[qw/〔 〕/],
	[qw/〈 〉/],
	[qw/「 」/],
	[qw/『 』/],
	[qw/〖 〗/],
	[qw/｛ ｝/],
	[qw/［ ］/],
	[qw/（ ）/],
	[qw/‘ ’/],
	[qw/“ ”/],
);

sub setflag {
	foreach(@_) {
		if($_ eq 'debug') {
			$DEBUG = 1;
		}
	}
}

sub dequote_test {
	print STDERR dequote("【被催眠的冰球选手】作者：不明.txt\n");
}

sub dequote {
	my $_ = shift;
	return unless($_);
	print STDERR "TARGET: $_\n" if($DEBUG);
	foreach my $q(@QUOTES) {
		print STDERR "QUOTE: ",join(" ",@{$q}),"\n" if($DEBUG);
		my $exp = '^(.*?)' . $q->[0] . '([^'. $q->[1] . ']*)' . $q->[1] . '(.*)$';
		print STDERR "Exp: $exp\n" if($DEBUG);
		while(m/$exp/g) {
			print STDERR "\tMatch!\n" if($DEBUG);
			my $r = ($1 ? $1 . "_" : "") . $2 . ($3 ? "_$3" : "");
			s/$exp/$r/;
		}
	}
	return $_;
}

1;
