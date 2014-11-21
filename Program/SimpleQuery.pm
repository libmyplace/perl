#!/usr/bin/perl -w
package MyPlace::Program::SimpleQuery;
use strict;
use warnings;
use File::Spec::Functions qw/catfile/;
use Getopt::Long;
use MyPlace::URLRule::SimpleQuery;
use Getopt::Long qw/GetOptionsFromArray/;

my %EXIT_CODE = qw/
	OK			0
	FAILED		1
	DO_NOTHING	2
	ERROR_USAGE 3
/;


my $DEFAULT_HOST = "weibo.com,weipai.cn,vlook.cn,google.search.image";
my @DEFAULT_HOST = split(/\s*,\s*/,$DEFAULT_HOST);
my @OPTIONS = qw/
		help|h
		manual|man
		list|l
		debug|d
		database|hosts|sites|db=s
		command|c:s
		update|u
		add|a
		additem
		saveurl=s
		overwrite|o
		thread|t:i
/;

sub new {
	my $class = shift;
	my $self = bless {},$class;
	if(@_) {
		$self->set(@_);
	}
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
		GetOptionsFromArray(\@_,\%OPT,@OPTIONS);
	}
	else {
		$OPT{'help'} = 1;
	}
	$self->{options} = cathash($self->{options},\%OPT);
	$self->{ARGV} = @_ ? [@_] : undef;
}


sub do_list {
	my $self = shift;
	my @target = @_;
	my $idx = 1;
	foreach(@target) {
		my @rows = @$_;
		my $dbname = shift(@rows);
		next unless($dbname);
		print STDERR "[" . uc($dbname),"]:\n";
		foreach my $item(@rows) {
			printf "\t[%03d] %-20s [%d]  %s\n",$idx,$item->[2],$item->[3],$item->[1];
			$idx++;
		}
	}
	return $EXIT_CODE{OK};
}

sub do_update {
	my $self = shift;
	my $cmd = shift(@_) || "UPDATE";
	my @target = @_;
	my $OPTS = $self->{options};
	use MyPlace::URLRule::OO;
	my @request;
	my $count = 0;
	foreach(@target) {
		my @rows = @$_;
		my $dbname = shift(@rows);
		next unless($dbname);
		print STDERR "[" . uc($dbname),"]:\n";
		foreach my $item(@rows) {
			next unless($item && @{$item});
			push @request,{
				count=>1,
				level=>$item->[3],
				url=>$item->[2],
				title=>$item->[1] . "/$dbname/",
			};
			$count++;
		}
	}
	my $idx = 0;
	my $URLRULE = new MyPlace::URLRule::OO('action'=>$cmd,'thread'=>$OPTS->{thread});
	foreach(@request) {
		$idx++;
		$_->{progress} = "[$idx/$count]";
		$URLRULE->autoApply($_);
		$URLRULE->reset();
	}
	if($URLRULE->{DATAS_COUNT}) {
		return $EXIT_CODE{OK};
	}
	else {
		return $EXIT_CODE{DO_NOTHING};
	}
}

sub do_add {
	my $self = shift;
	my $COMMAND = shift(@_) || $self->{COMMAND};
	my $NAMES = shift(@_) || $self->{NAMES};
	my $DATABASE = shift(@_) || $self->{DATABASE};
	my $OPTS = $self->{options};
	my $r = $EXIT_CODE{OK};
	if(!$NAMES) {
		print STDERR "Arguments requried for COMMAND <add>\n";
		$r = $EXIT_CODE{ERROR_USAGE};
	}
	else {
		foreach my $db (@$DATABASE) {
			my $SQ;
			if($OPTS->{overwrite}) {
				$SQ = MyPlace::URLRule::SimpleQuery->new([$db,'overwrite']);
			}
			else {
				$SQ = MyPlace::URLRule::SimpleQuery->new($db);
			}
			my ($count,$msg);
			if($COMMAND eq 'ADD') {
				($count,$msg) = $SQ->add(@$NAMES);
			}
			else {
				($count,$msg) = $SQ->additem(@$NAMES);
			}
			#print STDERR "SimpleQuery Add ",join(", ",$count,$msg),"\n";
			if($count) {
				$SQ->save;
			}
			else {
				$r = $EXIT_CODE{NO_NOTHING};
			}
		}
	}
	return $r;
}


sub do_upgrade {
	my $self = shift;
	my $COMMAND = shift(@_) || $self->{COMMAND};
	my $NAMES = shift(@_) || $self->{NAMES};
	my $DATABASE = shift(@_) || $self->{DATABASE};
	my $OPTS = $self->{options};
	if(!$NAMES) {
		print STDERR "Arguments requried for COMMAND <_UPGRADE>\n";
		return $EXIT_CODE{ERROR_USAGE};
	}
	my $SRCD = $OPTS->{srcd} || ".";
	my $DSTD = $OPTS->{dstd} || "_upgrade";
	foreach my $db (@$DATABASE) {
		my $SQ = MyPlace::URLRule::SimpleQuery->new($db);
		foreach(@$NAMES) {
			my($id,$name) = $SQ->item($_);
			if($id and $name) {
				my $src = catfile($SRCD,$_);
				my $dstd = catfile($DSTD,"$_/$db");
				print STDERR "\"$src\" => \"$dstd/$id\"\n";
				system('mkdir','-p','--',$dstd) unless(-d $dstd);
				system('mv','-v','--',$src,catfile($dstd,$id));
				print STDERR "\n";
			}
			else {
				print STDERR "Id not found for \"$_\"\n";
			}
		}
	}
	return $EXIT_CODE{OK};
}

sub do_saveurl {
	my $self = shift;
	my $COMMAND = shift(@_) || $self->{COMMAND};
	my $NAMES = shift(@_) || $self->{NAMES};
	my $DATABASE = shift(@_) || $self->{DATABASE};
	my $DATABASENAME = $DATABASE->[0];
	my $OPTS = $self->{options};
		my $SQ = MyPlace::URLRule::SimpleQuery->new($DATABASENAME);
		my($id,$name) = $SQ->item(@$NAMES);
		if(!$id) {
			print STDERR "Error: ",$name,"\n";
			exit 3;
		}
		use MyPlace::URLRule::OO;
		my $URLRULE = new MyPlace::URLRule::OO('action'=>'SAVE','thread'=>$OPTS->{thread});
		$URLRULE->autoApply({
				count=>1,
				level=>0,
				url=>$OPTS->{saveurl},
				title=>join("/",$name,$DATABASENAME,$id),
		});
		if($URLRULE->{DATAS_COUNT}) {
			return $EXIT_CODE{OK};
		}
		else {
			return $EXIT_CODE{DO_NOTHING};
		}
}

sub query {
	my $self = shift;
	my $NAMES = shift(@_) || $self->{NAMES};
	my $DATABASE = shift(@_) || $self->{DATABASE};
	my $OPTS = $self->{options};
	my @target;
	foreach my $db (@$DATABASE) {
		my $SQ = new MyPlace::URLRule::SimpleQuery($db);
		if(!$NAMES) {
			my($status,@result) = $SQ->all();
			if(!$status) {
				print STDERR "[$db] Error: ",@result,"\n";
			}
			else {
				push @target,[$db,@result];
			}
		}
		else {
			foreach my $keyword (@$NAMES) {
				my($status,@result) = $SQ->query($keyword);
				if(!$status) {
					print STDERR "[$db] Error: ",@result,"\n";
				}
				else {
					push @target,[$db,@result];
				}
			}
		}
		$SQ = undef;
	}
	return @target;
}

sub process_target {
	my $self = shift;
	my $cmd = shift(@_) || $self->{COMMAND};
	if($cmd eq 'LIST') {
		my @target = $self->query();
		return $self->do_list(@target);
	}
	elsif(($cmd eq 'UPDATE') or ($cmd eq 'SAVE')) {
		my @target = $self->query();
		return $self->do_update($cmd,@target);
	}
	else {
		print STDERR "Error, COMMAND $cmd not supported!\n";
		return $EXIT_CODE{ERROR_USAGE};
	}
}

sub process_command {
	my $self = shift;
	my $COMMAND = shift(@_) || $self->{COMMAND};
	if($COMMAND eq 'ADD' || $COMMAND eq 'ADDITEM') {
		return $self->do_add($COMMAND);
	}
	elsif($COMMAND eq '_UPGRADE') {
		return $self->do_upgrade($COMMAND);
	}
	elsif($COMMAND eq 'SAVEURL') {
		return $self->do_saveurl($COMMAND);
	}
	else {
		return $self->process_target($self->{COMMAND});
	}

}
sub execute {
	my $self = shift;
	my $OPT;
	my @argv;
	if(@_) {
		$OPT= {};
		GetOptionsFromArray(\@_,$OPT,@OPTIONS);
		$OPT = cathash($self->{options},$OPT);
		@argv = @_ if(@_);
	}
	else {
		$OPT = $self->{options};
		@argv = $self->{ARGV} ? @{$self->{ARGV}} : undef;
	}
	if($OPT->{help}) {
		pod2usage('-exitval'=>1,'-verbose'=>1);
		return $EXIT_CODE{OK};
	}
	elsif($OPT->{manual}) {
		pod2usage('--exitval'=>1,'-verbose'=>2);
		return $EXIT_CODE{OK};
	}
	$self->{NAMES} = @argv ? \@argv : undef;
	$self->{COMMAND} = 	$OPT->{additem} ? 'ADDITEM' : $OPT->{add} ? 'ADD' : $OPT->{list} ? 'LIST' : $OPT->{update} ? 'UPDATE' : $OPT->{command} ? uc($OPT->{command}) : 'UPDATE';
	$self->{COMMAND} = "SAVEURL" if($OPT->{saveurl});
	$self->{DATABASE} = [$OPT->{database} ? split(/\s*,\s*/, $OPT->{database}) : @DEFAULT_HOST];
	return $self->process_command($self->{COMMAND});
}


1;
__END__


