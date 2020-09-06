#!/usr/bin/perl -w
package MyPlace::URLRule::Rule;
use strict;
use warnings;
use MyPlace::URLRule qw//;

sub new {
	my $class = shift;
	return bless {@_},$class;
}

sub apply_rule {
	my $self = shift;
	if(defined $self->{apply_rule}) {
		unshift @_,$self;
		return $self->{apply_rule}->(@_);
	}
	return (
		error=>"Subroutine [apply_rule] not implemented.",
	);
}
sub apply_quick {
	my $self = shift;
	return (
	    '#use quick parse'=>1,
		@_,
	);
}
sub apply {
	my $self = shift(@_);
	my $url = shift(@_);
	my $level = shift(@_);
	my $info = MyPlace::URLRule::parse_rule($url,$level,@_);
	$info->{options} = $self->{options};
	$info = {%{$self->{rule}},%$info};
	my ($status,@result) = $self->apply_rule($url,$info);
	my %result;
	if(!@result) {
		if($status) {
			%result = (data=>[$status]);
		}
		else {
			%result = (error=>"Nothing to do");
		}
	}
	elsif(!$status) {
		%result = (error=>$result[0]);
	}
	else {
		%result = ($status,@result);
	}
    if($result{"#use quick parse"}) {
		%result = MyPlace::URLRule::urlrule_quick_parse(url=>$url,%result);
    }
	return MyPlace::URLRule::new_response($url,$info,\%result);
}

sub get_print {
	my $self = shift;
	my $value = shift;
	my $key = shift;
	my $store = shift;
	unless(defined $key) {
		print STDERR "  Get: $value\n";
		return $value;
	}
	unless(defined $store) {
		print STDERR "  Get <$key>: $value\n";
		return $value;
	}
	my $t = ref $store;
	if($t eq 'HASH') {
		print STDERR " Get $key => $value\n";
		$store->{$key} = $value;
		return $value;
	}
	elsif($t eq 'ARRAY') {
		print STDERR " Push $key:$value\n";
		push @$store,$value;
		return $value;
	}
	print STDERR "  Get <$key>: $value\n";
	print STDERR "    " . join(", ",$store,@_),"\n";
	return $value;
}

1;
