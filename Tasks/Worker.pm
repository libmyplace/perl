#!/usr/bin/perl -w
package MyPlace::Tasks::Worker;
use strict;
use warnings;
use MyPlace::Tasks::Task qw/$TASK_STATUS/;
use MyPlace::Script::Message;


sub new {
	my $class = shift;
	my $self = bless {@_},$class;
	return $self;
}

sub set_workdir {
	my $self = shift;
	my $task = shift;
	my $WD = shift;
	my $r;
	if($WD) {
		app_message2 "Directory: $WD\n";
		my $EWD;
		unless(-d $WD or mkdir $WD) {
			$EWD = 1;
			$r = $TASK_STATUS->{ERROR};
			$task->{summary} = "Error creating directory $WD:$!";
		}
		unless($EWD or chdir $WD) {
			$EWD = 1;
			$r = $TASK_STATUS->{ERROR};
			$task->{summary} = "Error changing directory to $WD:$!";
		}
		if($EWD) {
			app_error $task->{summary},"\n";
			if($WD eq $self->{workdir}) {
				$r = $TASK_STATUS->{FATALERROR};
				#app_error "Error, Worker [$self->{name}] works in invalid directory: $WD\n";
				return $r;
			}
			return $r;
		}
	}
	return undef;
}

sub process {
	my $self = shift;
	my $task = shift;
	$task->{time_begin} = time;
	my $r;
	my $s;
	$r = $self->set_workdir($task,$task->{workdir} || $self->{workdir});
	return $r if($r);
	($r,$s) = $self->{routine}->($self,$task,$task->content());
	if(!$r) {
		$task->{status} =  $TASK_STATUS->{FINISHED};
	}
	else {
		$task->{status} = $r;
	}
	if($s) {
		if(ref $s) {
			$self->process_result($task,@$s);
		}
		else {
			$task->{summary} = $s;
		}
	}
	$task->{time_end} = time;
	return $task->{status};
}

sub process_result {
	my $self = shift;
	my $task = shift;
	foreach my $r (@_) {
		if(ref $r) {
		}
	}
}

1;

