#!/usr/bin/perl -w
package MyPlace::Tasks::Center::Git;
use strict;
use warnings;
use parent "MyPlace::Tasks::Center";
use MyPlace::Tasks::File qw/read_tasks/;
use MyPlace::Tasks::Utils qw/strtime/;
use MyPlace::Script::Message;
use MyPlace::Tasks::Task qw/$TASK_STATUS/;



sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	$self->{pending_commits} = [];
	$self->{status_commit} = {commands=>[],subject=>'',comments=>[]};
	return $self;
}

sub now {
	return strtime(time);
}
sub more {
	my $self = shift;
	my $r = $self->SUPER::more();
	return $r if($r);
	app_message2 "[" . now() . "] Git> Checking repository ...  ";
	$self->read_repository;
	$self->write_repository;
	print STDERR "\n";
	return scalar(@{$self->{tasks}});
}

sub read_repository {
	my $self = shift;
	if($self->{options}{'no-pull'}) {
		print STDERR "\n";
		app_warning "Skip pull repository, option \"no-pull\" is on.\n";
		return;
	}
	$self->git_pull();
	$self->git_collect_tasks();
}

sub git_commit_item {
	my $commit = shift;
	my $all = shift;
	foreach(@{$commit->{commands}}) {
		run("git",@{$_});
	}
	my $comment = $commit->{comments} ? join("\n    ",@{$commit->{comments}}) : "";
	if($commit->{subject}) {
		$comment = $commit->{subject} .($comment ?  "\n\n    " . $comment : "");
	}			
	if($all) {
		run("git","commit","-am",$comment);
	}
	else {
		run("git","commit","-m",$comment);
	}
	#app_message2 "[" . now() . "] Git>  Commit " . $commit->{comment} . "\n";
}

sub write_repository {
	my $self = shift;
	if($self->{options}{'no-push'}) {
		app_warning "Skip push repository, option \"no-push\" is on.\n";
		return;
	}
	if($self->{pending_commits} && @{$self->{pending_commits}}) {
		if($self->{DEBUG}) {
			app_warning "DEBUG MODE: " . scalar(@{$self->{pending_commits}}) . " commits pending\n";
			app_warning "DEBUG MODE: commit nothing\n";
			$self->{pending_commits} = [];
			return;
		}
		app_message2 "[" . now() . "] Git> Perform pending commits \n";
		my $lastcommit = pop(@{$self->{pending_commits}});
		foreach my $commit (@{$self->{pending_commits}}) {
			git_commit_item($commit);
		}
		git_commit_item($lastcommit,1);
		app_message2 "[" . now() . "] Git> Pushed to repository\n";
		run("git","push","--force");
		$self->{pending_commits} = [];
	}
	return 0;
}

sub run {
	return system(@_) == 0;
}

sub git_head {
	my $self = shift;
	if(open FI,'<','.git/refs/heads/master') {
		my $r = <FI>;
		chomp $r;
		return $r;
		close FI;
	}
	else {
		return '';
	}
}

sub git_rm {
	my $self = shift;
	run('git','rm','--',@_);
}

sub git_empty_files {
	my $self = shift;
	foreach(@_) {
		open FO,">",$_;
		close FO;
	}
}

sub exit {
	my $self = shift;
	$self->update_database();
	$self->SUPER::exit(@_);
	return $self->write_repository();
}

sub git_pull {
	my $self = shift;
	$self->{lasthead} = git_head();
	run('git','pull');
	$self->{head} = git_head();
#	run('git','push');
}

sub git_commit {
	my $self = shift;
	run('git','commit','-am',$_[0]);
}

sub git_push {
	my $self = shift;
	run('git','push');
	$self->{head} = $self->{lasthead} = git_head();
	return $self;
}

sub ignore {
	my $self = shift;
	$self->{ignore} = [] unless($self->{ignore});
	push @{$self->{ignore}},@_ if(@_);
	return $self->{ignore};
}


sub git_collect_tasks {
	my $self = shift;
	if($self->{head} eq $self->{lasthead}) {
		#app_message22 now() . " [Git] Nothing changed\n";
		return $self;
	}
#	app_warning now() . " [Git] Head changed: $self->{lasthead} => $self->{head}\n";
	my $tree = $self->git_load_tree($self->{head});
	my $lasttree = $self->git_load_tree($self->{lasthead});
	my $total = 0;
	my @comments;
	my %commit = (commands=>[],comment=>[]);

TREEFILE:
	foreach my $file (keys %$tree) {
		#app_message2 "Try reading tasks from $file ...\n";
		next if($file =~ m/^[^\/\\]+$/); #Ignore files in top directory
		next if($file =~ m/^\.myplace\//); #Ignore myplace configuration files
		next if($file =~ m/\.(?:log|old)$/);#Ignore log files, backup files
		next if($file =~ m/\.log\.(?:txt|md)$/);# --
		next if($file =~ m/README/);#Ignore README
		if($self->{ignore}) {
			foreach(@{$self->{ignore}}) {
				next TREEFILE if($file =~ m/$_/);
			}
		}
		my $lastid = $lasttree->{$file} || '';
		my $id = $tree->{$file} || '';
		#app_warning "$lastid <=> $id\n";
		next if($lastid eq $id);
		my @tasks = $self->git_add_task($file);
		my $count = scalar(@tasks);
		if(@tasks) {
			$total += $count;
			push @{$commit{commands}},['add',$file];
			push @{$commit{comments}},"Add tasks from $file:";
			foreach(@tasks) {
				push @{$commit{comments}},"    <" . $_->to_string;
			}	
		}
		app_message2  "[" . now() . "] Git> Load $count task(s) from <$file>\n";
	}
	if($total > 0) {
		$commit{subject} = "Load $total task(s) from files";
		app_message2 "[" . now() . "] Git> " . $commit{subject} . "\n";
		push @{$self->{pending_commits}},\%commit;
		$self->save();
		return 1;
	}
	else {
		return 0;
	}
}

sub git_add_file {
	my $self = shift;
	run("git","add","--",@_);
}

sub git_add_task {
	my $self = shift;
	my $file = shift;
	my @data = ();
	#app_message2 "[" . now() . "] Git> Read tasks from file <$file> ...";
	my $tasks = read_tasks($file,$file,1);
				#read_tasks:
				#	param1: file to read
				#	param2: namespace (prefixes)
				#	param3:	write back or not
	if($tasks && @{$tasks}) {
		print STDERR "\t [OK]\n";
		push @{$self->{tasks}},@{$tasks};
		return @{$tasks};
	}
	else {
		print STDERR "\t [Failed]\n";
		return undef;
	}
}

sub git_load_tree {
	my $self = shift;
	my $head = shift;
	my %tree;
	if(!$head) {
		return {};
	}
	open FI,'-|','git','ls-tree','-r','--',$head;
	while(<FI>) {
		#print STDERR $_;
		chomp;
		if(m/^\d+\s+([^\s]+)\s+([^\s]+)\s+(.+?)\s*$/) {
			$tree{$3} = "$1$2";
		}
	}
	close FI;
	return \%tree;
}

sub pending_commit {
	my $self = shift;
	my $subject = shift;
	my %commit = (
		subject=>$subject,
		commands=>[@_],
	);
	push @{$self->{pending_commits}},\%commit;
	return \%commit;
}
sub file_changed {
	my $self = shift;
	my $filepath = shift;
	my $msg = shift;
	$self->pending_commit($msg,['add',$filepath]);
}


sub update_database {
	my $self = shift;
	my $dirs = $self->trace;
	return unless($dirs);
	foreach(@$dirs) {
		app_warning "Updating database [$_] ...";
		run("find \"$_/\" -type f >\"$_.txt\"");
		run("grep \\.txt\$ \"$_.txt\" | xargs git add --force --verbose");
		print STDERR "\n";
		run("git add --force --verbose \"$_.txt\"");
	}
}

sub status_update {
	my $self = shift;
	my $tasks_summary = $self->SUPER::status_update(@_);

	return unless($tasks_summary);

	my $task = shift;
	my $force = shift;

	$self->{status_commit}->{commands} = [['add',".myplace/*"]];
	if($task && !$task->{no_git}) {
		$self->{status_commit}->{comments} = [] unless($self->{status_commit}->{comments});
		if(@{$self->{status_commit}{comments}} > 20) {
			shift @{$self->{status_commit}{comments}};
		}
		push @{$self->{status_commit}->{comments}},
			$task->status . "< " . ($task->{title} || $task->to_string);
		
		if($task->{git_commands}) {
			push @{$self->{status_commit}->{commands}},@{$task->{git_commands}};
		}

		if($task->{status} == $TASK_STATUS->{FINISHED} || $task->{status} == $TASK_STATUS->{ERROR}) {
#			$self->update_database();
			$self->{status_commit}->{subject} = $task->{title} || $task->to_string;

			if($task->{status} != $TASK_STATUS->{FINISHED}){
				$self->{status_commit}->{subject} = $task->status . "<" . $self->{status_commit}->{subject};
			}
			if(1 < @{$self->{status_commit}->{comments}}) {
				unshift @{$self->{status_commit}->{comments}},"Tasks: $tasks_summary\n";
			}
			else {
				$self->{status_commit}->{comments} = [];
			}
			push @{$self->{pending_commits}},$self->{status_commit};
			$self->{status_commit} = {commands=>[],subject=>'',comments=>[]};
			$self->{counter} = {};
			#{$TASK_STATUS->{FINISHED}} = 0;
			#$self->{counter}{$TASK_STATUS->{ERROR}} = 0;
			$self->read_repository;
			$self->write_repository;
			return;
		}
	}
		if($force) {
			$self->{status_commit}->{subject} = "Tasks: $tasks_summary";
			push @{$self->{pending_commits}},$self->{status_commit};
			$self->{status_commit} = {commands=>[],subject=>'',comments=>[]};
			$self->{counter} = {};
			$self->read_repository;
			$self->write_repository;
		}
}


1;

