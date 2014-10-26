#!/usr/bin/perl -w
package MyPlace::Tasks::Worker;
use strict;
use warnings;
use MyPlace::Tasks::Task qw/$TASK_STATUS/;
use MyPlace::Script::Message;




sub new {
	my $class = shift;
	return bless {@_},$class;
}

sub process {
	my $self = shift;
	my $task = shift;
	$task->{time_begin} = time;
	my $r;
	my $s;
	if($task->{workdir}) {
		app_message2 "Directory: " . $task->{workdir} . "\n";
		if(!chdir $task->{workdir}) {
			$r = $TASK_STATUS->{ERROR};
			$task->{summary} = "Error changing directory to " . $task->{workdir} . ": $!";
			app_error $task->{summary},"\n";
		}
		else {
			($r,$s) = $self->{routine}->($task,$task->content());
		}
	}
	else {
		($r,$s) = $self->{routine}->($task,$task->content());
	}
	if(!$r) {
		$task->{status} =  $TASK_STATUS->{FINISHED};
	}
	else {
		$task->{status} = $r;
	}
	if($s) {
		$task->{summary} = $s;
	}
	$task->{time_end} = time;
	return $task->{status};
}
1;

