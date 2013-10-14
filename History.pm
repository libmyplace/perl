#!/usr/bin/perl -w
use strict;
use warnings;
package MyPlace::History;

sub new {
	my $class = shift;
	my $self =  bless {},$class;
	$self->{storage} = $_[0] || '.myplace.history.db';
	$self->{database} = {};
	return $self;
}
sub save {
	my $self = shift;
	my $url = shift;
	return undef if($self->{database}->{$url});
	$self->{database}->{$url} = 1;
	return 1;
}
sub write {
	my $self = shift;
	close $self->{storage_handler} if($self->{storage_handler});
}
sub load{
	my $self = shift;
	my $storage = $_[0] || $self->{storage} || '.myplace.history.db';
	$self->{storage} = $storage;
	if(open FI,'<',$storage) {
		foreach(<FI>) {
			chomp;
			$self->{database}->{$_}=1;
		}
		close FI;
	}
	open my $FO, ">>",$storage;
	$self->{storage_handler}= $FO;
	return $FO;
}
sub check {
	my $self = shift;
	foreach(@_) {
		return 1 if($self->{database}->{$_});
	}
	return undef;
}

sub notify_next {
	my $self = shift;
	my $next = shift;
	my $savelast = shift;
	$self->save_last() if($savelast);
	$self->{lasttask}=$next;
	return $next;
}
sub save_last {
	my $self = shift;
	$self->save($self->{lasttask}) if($self->{lasttask});
}

sub DESTORY {
	my $self = shift;
	$self->write() if(ref $self);
}

1;
__END__

