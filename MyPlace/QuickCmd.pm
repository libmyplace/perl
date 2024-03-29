#!/usr/bin/perl -w
use strict;
use warnings;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw(&qcmd_run &qcmd_set &qcmd_name &qcmd_add);
    @EXPORT_OK      = qw();
}
use Term::ANSIColor qw/color/;

my $CMD = 'echo';
my $NAME = '';
my @ARGS = ();
my $PROMPT = '';
my $PREFIX = '';

sub qcmd_set {
	if(@_) {
		($CMD,@ARGS) = @_;
	}
}

sub qcmd_name {
	$NAME = shift;
}

sub color1 {
	return color('GREEN') . join(" ",@_) . color('RESET');
}
sub color2 {
	return color('CYAN') . join(" ",@_) . color('RESET');
}

sub _build_prompt {
	my $c1 = shift;
	my $c2 = shift;
	my $p1 = $c1 ? color($c1) . $NAME . color('RESET') : $NAME if($NAME);
	my $p2 = $c1 ? color($c1) . $CMD . color('RESET') : $CMD if($CMD);
	my $p3 = $c1 ? color($c2) . $PROMPT . color('RESET') : $PROMPT if($PROMPT);

	my $p = $NAME ? $p1 . ">" : $CMD ? $p2 . ">" : ">";
	$p .= $PROMPT ? $p3 . ">" : "";
	$p .= " ";
	$p .= join(" ",@_) if(@_);
	$p = $p . "$PREFIX>";
	return $p;
}

sub qcmd_prompt {
	my $return_string = shift;
	print "\e]2;" . _build_prompt(undef,undef,@_) . "\7";;
	if($return_string) {
		return _build_prompt('GREEN','CYAN',@_);
	}
	else {
		print STDERR _build_prompt('GREEN','CYAN',@_);
	}
	return 0;
}

my %vtable = (
	'CMD'=>'COMMAND',
	'Q'=>'QUIT',
	'EXIT'=>'QUIT',
	'COMMAND'=>'COMMAND',
	'QUIT'=>'QUIT',
	'PROMPT'=>'PROMPT',
	'SYS'=>'SYSTEM',
	'SYSTEM'=>'SYSTEM',
	'PRE'=>'PREFIX',
	'PREFIX'=>'PREFIX',
	'P'=>'PREFIX',
);

my %ctable = (
);

sub qcmd_add {
	return unless(@_);
	my $name = shift;
	my $uname = uc($name);
	$vtable{$uname} = $uname;
	$ctable{$uname} = @_ ? [@_] : [$name];
}

sub qcmd_execute {
	my $cmd = shift;
	$cmd = 'echo' unless($cmd);
	if(ref $cmd) {
		return &$cmd(@_);
	}
#	if($ctable{uc($cmd)}) {
#		return system(@{$ctable{uc($cmd)}},@_) == 0;
#	}
	return system($cmd,@_) == 0;
}

sub qcmd_run {
	#&qcmd_prompt;		
	my $ok = 1;
	use Term::ReadLine;
	my $term = Term::ReadLine->new('MyPlace QuickCmd Controler');
	while(defined($_ = $term->readline(&qcmd_prompt(1)))) {
		chomp;
		if($_) {
			my($verb,@words) = split(/\s+/,$_);
			my $VERB = $vtable{uc($verb)} || '';
			if($VERB eq 'QUIT') {
				$ok = 1;
				last;
			}
			elsif($VERB eq 'COMMAND') {
				$ok = 1;
				qcmd_set(@words);
			}
			elsif($VERB eq 'SYSTEM') {
				$ok = qcmd_execute(@words);
			}
			elsif($VERB eq 'PREFIX') {
				$PREFIX = "@words";
			}
			elsif($ctable{$VERB}) {
				$ok = qcmd_execute(@{$ctable{$VERB}},@words);
			}
			else {
				@words = split(/\s+>\s+/,$PREFIX . $_);
				my @args;
				foreach(@ARGS) {
					if(m/^\$(\d+)$/) {
						my $n=$1-1;
						if(defined $words[$n]) {
							push @args,$words[$n];
							$words[$n] = undef;
						}
					}
					else {
						push @args,$_;
					}
				}
				foreach(@words) {
					push @args,$_ if(defined $_);
				}
				print STDERR join(" ",$CMD,@args),"\n";
				$ok = qcmd_execute($CMD,@args);
			}
		}
		#		&qcmd_prompt;
	}
	return $ok ? 0 : 1;
}

1;
