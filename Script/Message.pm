#!/usr/bin/perl
package MyPlace::Script::Message;
use Term::ANSIColor;
BEGIN {
    use Exporter ();
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw(&app_ok &app_message &app_message2 &app_error &app_warning &app_abort &color_print &colored &color &app_prompt &with_color);
    @EXPORT_OK      = map "print_$_",(qw/red blue yellow white black cyan green/);
}


my $id = $0;
$id =~ s/^.*\///g;
my $prefix="\r$id> ";

my %CHANNEL = (
    "message"=>"cyan",
    "message2"=>"green",
    "ok"=>"green",
    "warning"=>"yellow",
    "warn"=>"yellow",
    "error"=>"red",
    "abort"=>"red"
);
no warnings;
sub color {
	goto &Term::ANSIColor::color;
}
sub colored {
	goto &Term::ANSIColor::colored;
}
use warnings;
sub color_print($$@) {
    my $out=shift;
    my $ref=ref $out ? $out : \$out;
    if(!((ref $ref) eq "GLOB")) {
        $ref=*STDERR;
        unshift @_,$out;
    }
    my $color=shift;
    if($ENV{OS} and $ENV{OS} =~ /windows/i) {
        print STDERR @_;
    }
    else {
        print $ref color($color),@_,color('reset') if(@_);
    }
}
sub app_prompt {
	my ($subject,@texts) = @_;
	if($subject) {
		$subject .= ': '; 
	}
	else {
		$subject = '';
	}
	print STDERR $prefix,$subject,color($CHANNEL{message}),@texts,color('RESET');
}

sub with_color {
	my @texts = @_;
	foreach(@texts) {
		s/(?:COLOR|\^)\(([A-Z]+)\)/color("$1")/ge;
	}
	return @texts;
}

sub new {
	my $class = shift;
	my $self = bless {@_},$class;
	return $self;
}

#sub app_error {
#    print STDERR $prefix;
#    color_print *STDERR,'red',@_;
#}
#
#sub app_message {
#    print STDERR $prefix,@_;
#}
#sub app_message2 {
#    print STDERR $prefix,color('green'),@_,color('reset');
#    color_print *STDERR,'green',@_;
#}
#}
#sub app_warning {
#    print STDERR $prefix;
#    color_print *STDERR,'yellow',@_;
#}

sub app_abort {
    &app_error(@_);
    exit $?;
}

sub AUTOLOAD {
    if($ENV{OS} and $ENV{OS} =~ /windows/i) {
        print STDERR @_;
    }
    elsif($AUTOLOAD =~ /::(app|print)_([\w\d_]+)$/) {
		my $need_header = ($1 eq 'app');
        my $channel = $CHANNEL{$2} || $2 || 'RESET';
		my $flag = shift(@_);
		if($flag eq '--no-prefix') {
			$need_header = undef;
		}
		else {
			unshift @_,$flag;
		}
		if($need_header) {
			print STDERR $prefix,color($channel),@_,color('RESET');
		}
		else {
			print STDERR color($channel),@_,color('RESET');
		}
        return 1;
    }
    return undef;
}
return 1;

__END__
=pod

=head1 NAME

MyPlace::Script::Message - Colorized messages outputing

=head1 SYNOPSIS

use MyPlace::Script::Message;

app_message("myprogram","Hello, World\n");

app_message("--no-prefix","Hello, World\n");

=head1 Functions

=over

=item B<app_message>

=item B<app_warning>

=item B<app_error>

=item B<app_ok>

=item B<app_abort>

=item B<app_message2>

=back

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@myplace.hell>

=cut


