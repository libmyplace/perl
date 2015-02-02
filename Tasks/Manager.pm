#!/usr/bin/perl -w
package MyPlace::Tasks::Manager;
use strict;
use warnings;

use File::Spec::Functions qw/catfile catdir/;

our $CONFIG_DIR = '.mtm';
our $DB_DONE = 'done.txt';
our $DB_QUEUE = 'queue.txt';
our $DB_FAILED = 'failed.txt';
our $DB_IGNORE = 'ignore.txt';


sub new {
	my $class = shift;
	my $self = bless {
			options=>{},
		},$class;
	$self->set(@_);
	return $self;
}

sub set {
	my $self = shift;
	$self->{options} = {%{$self->{options}},@_};
	return $self->{options};
}

sub get {
	my $self = shift;
	if(@_) {
		my %r;
		foreach(@_) {
			$r{$_} = $self->{options}->{$_};
		}
		return %r;
	}
	else {
		return (%{$self->{options}});
	}
}

use Cwd qw/getcwd/;

my $MSG_PROMPT = 'MTM';
sub p_msg {
	print STDERR "$MSG_PROMPT> ",@_;
}

sub p_err {
	print STDERR "$MSG_PROMPT> ",@_;
}

sub p_warn {
	print STDERR "$MSG_PROMPT> ",@_;
}
sub _read_lines {
	my $filename = shift;
	my $dir = shift;
	my $source = $dir ? catfile($dir,$filename) : $filename;
	my @input;
	my $counter = 0;
	if(! -f $source) {
		#&p_warn("Input file $source not exists [IGNORED]\n");
	}
	elsif(open(my $FI,'<',$source)) {
		$counter = 0;
		foreach(<$FI>) {
			chomp;
			next unless($_);
			$counter++;
			push @input,$_;
		}
		close $FI;
		&p_msg("Read $counter lines for $source\n");
	}
	else {
		&p_warn("Error opening $source [IGNORED]\n");
	}
	return @input;
}

sub _write_lines {
	my $data = shift;
	my $filename = shift;
	my $dir = shift;
	my $source = $dir ? catfile($dir,$filename) : $filename;

	my @input = (($data && @{$data}) ? @{$data} : ());
	my $counter = 0;
	if(open(my $FO,'>',$source)) {
		$counter = 0;
		foreach(@input) {
			$counter++;
			print $FO "$_\n";
		}
		close $FO;
		&p_msg("Write $counter lines to $source\n");
		return 1;
	}
	else {
		&p_err("Error opening $source [IGNORED]\n");
		return undef;
	}
}


sub unique {
	my $source = shift;

	return unless($source and @{$source});
	return @{$source} unless(@_);

	my @r;
	
	my %holder = map {$_=>1} @_;
	
	foreach(@{$source}) {
		if(!defined($holder{$_})) {
			push @r,$_;
		}
	}
	return @r;
}

sub run {
	my $self = shift;



	my %opt = %{$self->{options}};
	my @queue = @_;
	
	if(@queue and $queue[0] and -d $queue[0] and !$opt{directory}) {
		$opt{directory} = shift(@queue);
		
	}

	if(!(@queue or $opt{input})) {
		$opt{input} = 'urls.lst';
	}



	my $worker = $opt{worker};

	my $COUNTER = 0;

	$MSG_PROMPT = defined($opt{title}) ? $opt{title} :
			defined($opt{directory}) ? $opt{directory} : 
			'MyPlace Tasks Manager';


	if(!$worker) {
		p_err "Error not worker defined\n";
		return undef,4,"no worker defined"; 
	}
	
	my $CWD_KEPT;
	if($opt{directory}) {
		$CWD_KEPT = getcwd;
		#	print STDERR "CWD:$CWD_KEPT\n";
		p_msg "Entering $opt{directory}\n" unless($opt{simple} or $opt{quiet});
		if(!chdir $opt{directory}) {
			p_err "Error:$! [$opt{directory}]\n";
			return undef,4,"$! [$opt{directory}]";
		}
	}

	if($opt{recursive}) {
		my $kd = $opt{directory};
		my $kt = $opt{title};
		my $km = $MSG_PROMPT;
		#my $KWD = getcwd;
		my @subdir;
		foreach(glob('*')) {
			next if(m/^\.[^\/]*/);
			push @subdir,$_ if(-d $_);
		}
		foreach(@subdir) {
			$self->{options}->{directory} = $_;
			$self->{options}->{title} = $MSG_PROMPT . "/$_";
			$MSG_PROMPT .=  "/$_";
			my ($count,$val,$msg) = $self->run();
			$COUNTER += $count if($count);
			$opt{title} = $kt;
			$opt{directory} = $kd;
			$self->{options}->{directory} = $kd;
			$self->{options}->{title} = $kt;
			$MSG_PROMPT = $km;
		}
		#chdir $KWD;
	}



	my (@done,@failed,@ignore,@input);

	@input = &_read_lines($opt{input}) if($opt{input});

	if($opt{simple}) {
		push @queue,@input;
	}
	elsif(-d $CONFIG_DIR) {
		@done = &_read_lines($DB_DONE,$CONFIG_DIR);
		@failed = &_read_lines($DB_FAILED,$CONFIG_DIR);
		@ignore = &_read_lines($DB_IGNORE,$CONFIG_DIR);
		push @queue, &_read_lines($DB_QUEUE,$CONFIG_DIR);
		if($opt{force}) {
			unshift @queue,@input;
		}
		else {
			unshift @queue, unique(\@input,@queue,@failed,@done,@ignore);
		}

		if($opt{retry}) {
			push @queue,@failed;
			@failed = ();
		}
	}
	elsif(!@input) {
		$self->exit($CWD_KEPT,0);
		return 0;
	}
	else {
		@queue = @input;
	}
	my $count = scalar(@queue);

	if(!$count) {
		&p_warn("Tasks queue was empty\n") unless($opt{quiet});
		$self->exit($CWD_KEPT,2);
		return 2;
	}
	elsif($count > 1) {
		&p_msg("Get $count tasks in queue\n");
	}
	
	my @wopts;
	push @wopts,'--overwrite' if($opt{overwrite});
	push @wopts,"--force" if($opt{force});
	push @wopts,"--referer",$opt{referer} if($opt{referer});

	my $IAMKILLED = undef;
	
	$SIG{INT} = sub {
		return 2 if($IAMKILLED);
		$IAMKILLED = 1;
		print STDERR "MyPlace::Tasks::Manager KILLED\n";
		return 2;
	};
	my $index = 0;
	while($queue[0]) {
		last if($IAMKILLED);
		my $task = $queue[0];
		my $r;
		$index++;
			print STDERR "\n";
			&p_msg("[$index/$count]\n");
		if(ref $worker) {
			$r = &$worker($task,@wopts);
		}
		else {
			$r = system($worker,$task,@wopts);
		}
		last if($IAMKILLED);
		sleep 1;
		last if($IAMKILLED);
		if($r == 0) {
			#	&p_msg("[$index/$count] DONE\n");
			$COUNTER++;
			shift @queue;
			push @done,$task;
		}
		elsif($r == 2) {
			print STDERR ("I AM KILLED\n");
			last;
		}
		else {
			$r = $r>>8;
			if($r == 12) {
			#	&p_msg("[$index/$count] IGNORED\n");
				shift @queue;
				push @done,$task;
			}
			else {
				shift @queue;
				#&p_msg("[$index/$count] FAILED\n");
				push @failed,$task;
			}
		}
		last if($IAMKILLED);
	}
	if(!$opt{simple}) {
		print STDERR "\n";
		if(!-d $CONFIG_DIR) {
			if(!mkdir($CONFIG_DIR)) {
				&p_warn("Error creating directory $CONFIG_DIR: $!\n");
			}
		}
		&_write_lines(\@done,$DB_DONE,$CONFIG_DIR);
		&_write_lines(\@queue,$DB_QUEUE,$CONFIG_DIR);
		if($opt{'ignore-failed'}) {
			&_write_lines([@ignore,@failed],$DB_FAILED,$CONFIG_DIR);
		}
		else {
			&_write_lines(\@failed,$DB_FAILED,$CONFIG_DIR);
		}
	}
	return $self->exit($CWD_KEPT,$COUNTER,0,"OK");
}

sub exit {
	my $self = shift;
	my $CWD_KEPT = shift;
	if($CWD_KEPT) {
		#	p_msg "Return to directory:$CWD_KEPT\n" unless($opt{simple} or $opt{quiet});
		if(!chdir $CWD_KEPT) {
			p_err "Error:$!\n";
			return undef,4,"$!";
		}
	}
	else {
		return @_;
	}
}

1;

