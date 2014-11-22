#!/usr/bin/perl -w
package MyPlace::Program;
use strict;
use warnings;
use Getopt::Long qw/GetOptionsFromArray/;

my $DEF_OPTIONS = [qw/
	help|h|? 
	manual|man
	/];
sub new {
	my $class = shift;
	my $self = bless {},$class;
	$self->{DEF_OPTIONS} = $self->OPTIONS;
	$self->set(@_) if(@_);
	return $self;
}

sub cathash {
	my $lef = shift;
	my $rig = shift;
	return $lef unless($rig);
	return $lef unless(%$rig);
	my %res = $lef ? %$lef : ();
	foreach(keys %$rig) {
		$res{$_} = $rig->{$_} if(defined $rig->{$_});
	}
	return \%res;
}

sub set {
	my $self = shift;
	my %OPT;
	if(@_) {
		GetOptionsFromArray(\@_,\%OPT,@{$self->{DEF_OPTIONS}});
	}
	else {
		$OPT{'help'} = 1;
	}
	$self->{options} = cathash($self->{options},\%OPT);
	push @{$self->{argv}},@_ if(@_);
}

sub OPTIONS {
	return $DEF_OPTIONS;
}

sub USAGE {
	my $self = shift;
	require Pod::Usage;
	Pod::Usage::pod2usage(@_);
	return 0;
}

sub MAIN {
	print STDERR "sub MAIN not implemented\n";
	return;
}

sub execute {
	my $self = shift;
	my $OPT;
	if(@_) {
		$OPT= {};
		GetOptionsFromArray(\@_,$OPT,@{$self->{DEF_OPTIONS}});
		$OPT = cathash($self->{options},$OPT);
	}
	else {
		$OPT = $self->{options};
		@_ = $self->{argv} ? @{$self->{argv}} : ();
	}
	if((!@_) && $self->{NEEDARGV}) {
		$OPT->{help} = 1;
	}
	if($OPT->{help}) {
		return $self->USAGE('-exitval'=>1,'-verbose'=>1);
	}
	elsif($OPT->{manual}) {
		return $self->USAGE('--exitval'=>1,'-verbose'=>2);
	}
	return $self->MAIN($OPT,@_);
}

1;
__END__
