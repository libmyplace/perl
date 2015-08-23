#!/usr/bin/perl -w
package MyPlace::Program::Saveurl;
use strict;
use warnings;

use MyPlace::Script::Message;
use MyPlace::Program::Batchget;
use MyPlace::Program::Download;
use MyPlace::Data::BlockedSites;
use Getopt::Long;

my @BLOCKED = @MyPlace::Data::BlockedSites::ALL;


my %EXPS = (
	"bdhd"=>'^(bdhd:\/\/.*\|)([^\|]+?)(\|?)$',
	'ed2k'=>'^(ed2k:\/\/\|file\|)([^\|]+)(\|.*)$',
	'http'=>'^(http:\/\/.*\/)([^\/]+)$',
	'qvod'=>'^(qvod:\/\/.*\|)([^\|]+?)(\|?)$',
	'torrent'=>'^torrent:\/\/([A-Za-z0-9]+)\|?(.+)$',
	'magnet'=>'^(magnet:\?[^\t]+)',
);
my $MSG = MyPlace::Script::Message->new('saveurl');
my @DOWNLOADS;

sub parse_options {
	my @OPTIONS = qw/
	help|h|? 
	manual|man
	referer|r=s
	base|b=s
	overwrite|f
	history|hist
	no-http|nh
	no-qvod|nq
	no-ed2k|ne
	no-bdhd|nb
	no-file|nf
	no-data|nd
	no-torrent|nt
	no|n=s
	thread|t=i
	output|o=s
	include|I=s
	exclude|X=s
	/;
	my %OPTS;
	Getopt::Long::Configure('no_ignore_case');
	Getopt::Long::GetOptionsFromArray(\@_,\%OPTS,@OPTIONS);
	return \%OPTS,@_;
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

sub setOptions {
	my $self = shift;
	my ($opts,@remains) = parse_options(@_);
	$self->addTask(@remains) if(@remains);
	return @remains if(!$opts);
	if($self->{OPTS}) {
		$self->{OPTS} = cathash($self->{OPTS},$opts);
	}
	else {
		$self->{OPTS} = $opts;
	}
	return @remains;
}

sub addTask {
	my $self = shift;
	push @{$self->{Tasks}},@_ if(@_);
	#print STDERR join("\n",@{$self->{Tasks}}),"\n";
	return $self->{Tasks};
}
sub addTaskFromFile {
	my $self = shift;
	my $file = shift;
	my $GLOB = ref $file;
	my $fh;
	if($GLOB eq 'GLOB') {
		$GLOB = 1;
	}
	else {
		$GLOB = 2;
	}
	if($GLOB) {
		$fh = $file;
	}
	elsif(!open $fh,"<",$file) {
	#elsif(!open $fh,"<:utf8",$file) {
		app_error("(line " . __LINE__ . ") Error opening $file:$!\n");
		return undef;
	}
	my $count = 0;
	my @tasks = ();
	while(<$fh>) {
	    chomp;
	    s/^\s+//;
	    s/\s+$//;
	    if(!$_) {
	        next;
	    }
		$self->addTask($_);
	}
	close $fh unless($GLOB);
	return $self->{Tasks};
}

sub new {
	my $class = shift;
	my $self = bless {},$class;
	$self->{Tasks} = [];
	$self->{OPTS} = {};
	$self->setOptions(@_) if(@_);
	return $self;
}

sub execute {
	my $self = shift;	
	$self->setOptions(@_);
	my $OPTS = $self->{OPTS};
	if($OPTS->{'help'} or $OPTS->{'manual'}) {
		require Pod::Usage;
		my $v = $OPTS->{'help'} ? 1 : 2;
		Pod::Usage::pod2usage(-exitval=>$v,-verbose=>$v);
		exit $v;
	}
	$self->doTasks();
	return 0;
}

sub extname {
	my $filename = shift;
	return "" unless($filename);
	if($filename =~ m/\.([^\.\/\|]+)$/) {
		return $1;
	}
	return "";
}
sub blocked {
	my $url = shift;
	foreach(@BLOCKED) {
		if($url =~ m/$_/) {
			return 1;
		}
	}
	return undef;
}

sub normalize {
	my $_ = $_[0];
	if($_) {
		s/[\?\*\/:\\]/ /g;
	}
	return $_;
}

sub process_weipai_urls {
	my $self = shift;
	return unless(@_);
	require MyPlace::Weipai::Downloader;
	MyPlace::Weipai::Downloader::init();
	my $exitcode;
	my @tasks;
	foreach(@_) {
		my ($link,$filename) = @$_;
		if(blocked($link)) {
			$MSG->warning("Blocked: $link\n");
			return;
		}
		$filename = normalize($filename) if($filename);
		push @tasks,[$link,$filename];
	}
	$exitcode = MyPlace::Weipai::Downloader::download_urls(\@tasks,$self->{OPTS}->{history});
	return ($exitcode == 0)
}

sub process_http {
	my $self = shift;
	my ($link,$filename) = @_;
	if(blocked($link)) {
		$MSG->warning("Blocked: $link\n");
		return;
	}
	if(!$filename) {
		if($link =~ m/$EXPS{http}/) {
			$filename = $2;
		}
	}
	$filename = normalize($filename) if($filename);

	#if(-f $filename) {
	#	$MSG->warning("Ignored: File exists, $filename\n");
	#	return;
	#}
	push @DOWNLOADS,[$link,$filename];
}
sub process_file {
	my $self = shift;
	my ($link,$filename) = @_;
	$filename = normalize($filename);
#	if(-f $filename) {
#		print STDERR "Ignored: File exists, $filename\n";
#		return;
#	}
	$MSG->green("Saving file:\n==> $filename\n");
	system('mv','--',$link,$filename);
}


sub process_bdhd {
	my $self = shift;
	my %OPTS = %{$self->{OPTS}};
	my $link = shift;
	my $filename = shift;
	$link = lc($link);
	if(!$filename) {
		foreach my $p (qw/bdhd ed2k/) {
			my $_ = $EXPS{$p};
			if($link =~ m/$_/) {
				$filename = "$2.$p";
				$filename = normalize($filename);
				last;
			}
		}
	}
	else {
		$filename = normalize($filename);
		foreach my $p (qw/bdhd ed2k/) {
			my $_ = $EXPS{$p};
			if($link =~ m/$_/) {
				$link = $1 . $filename . $3;
				$filename = "$filename.$p";
				last;
			}
		}
	}
	$filename =~ s/\.bdhd$//;
	if($link && $filename) {
		$filename = $filename . ".bsed";
		$MSG->green("Saving text file:\n==> $filename\n");
		open FO,'>:utf8',$filename;
		#open FO,'>:utf8',$filename;
		print FO 
<<"EOF";
{
	"bsed":{
		"version":"1,19,0,195",
		"seeds_href":{"bdhd":"$link"}
	}
}
EOF
		close FO;
	}
	else {
		print STDERR "No filename specified for [$link]\n";
	}
}

sub process_qvod {
	my $self = shift;
	my %OPTS = %{$self->{OPTS}};
	my $link = shift;
	my $filename = shift;
	$link = lc($link);
	if(!$filename) {
		foreach my $p (qw/qvod bdhd ed2k http/) {
			my $_ = $EXPS{$p};
			if($link =~ m/$_/) {
				$filename = "$2.$p";
				last;
			}
		}
		$filename = normalize($filename) if($filename);
	}
	else {
		$filename = normalize($filename);
		foreach my $p (qw/qvod bdhd ed2k/) {
			my $_ = $EXPS{$p};
			if($link =~ m/$_/) {
				$link = "$1$filename$3";
				$filename = "$filename.$p";
				last;
			}
		}
	}
	$filename =~ s/\.qvod$//;
	if($link && $filename) {
		$MSG->green("Saving text file\n==> $filename.qsed\n");
		open FO,'>:utf8',$filename . '.qsed';
		print FO 
<<"EOF";
<qsed version="3.5.0.61"><entry>
<ref href="$link" />
</entry></qsed>
EOF
		close FO;
	}
}

sub process_data {
	my $self = shift;
	my %OPTS = %{$self->{OPTS}};
	my $data=shift;
	my $filename = shift;
	return unless($filename);
	$data =~ s/\0/\n/g;
	print STDERR "Saving file:\n==> $filename\n";
	open FO,">:raw",$filename or die("$!\n");
	#open FO,">:utf8",$filename or die("$!\n");
		print FO $data;
	close FO;
}

sub process_torrent {
	my $self = shift;
	my $hash = shift;
	my $title = shift;
	require MyPlace::Program::DownloadTorrent;
	if($title) {
		return MyPlace::Program::DownloadTorrent::download_torrent($hash,normalize($title)) == 0;
	}
	else {
		return MyPlace::Program::DownloadTorrent::download_torrent($hash) == 0;
	}
}



sub doTasks {
	my $self = shift;
	my %OPTS = %{$self->{OPTS}};
	my $tasks = $self->{Tasks};
	if(!($tasks && @{$tasks})) {
		$MSG->warn("No tasks to save\n");
		return 1;
	}
	my $idx = 0 ;
	my $count = scalar(@{$tasks});
	my $FH_OUT;
	if($self->{OPTS}->{output}) {
		if(!open($FH_OUT,">>",$self->{OPTS}->{output})) {
			$MSG->error("Error opening " .
				$self->{OPTS}->{output} .
				":$!\n"
			);
			return 1;

		}
	}
	#print STDERR "\n\n$count\n\n";
	my @weipai_urls;
	while($idx < $count) {
		$idx++;
		my $_ = shift(@{$tasks});
		my $proto = "http";
		if($_ =~ m/^([^:\/]+):\/\//) {
			$proto = $1;
		}
		if($self->{OPTS}->{"no-$proto"} || (
				$self->{OPTS}->{no} && 
				$self->{OPTS}->{no} eq $proto
			) || (
				$self->{OPTS}->{only} &&
				!($self->{OPTS}->{only} eq $proto)
			)
		) {
			$MSG->warn("Skip URL TYPE [$proto]: $_\n");
			next;
		}
		if($self->{OPTS}->{output}) {
			print STDERR "[$idx/$count] " .
				$self->{OPTS}->{output} . 
				"<<$_\r";
			print $FH_OUT $_;
			next;
		}
		if($self->{OPTS}->{include}) {
			if(m/$self->{OPTS}->{include}/) {
			}
			else {
				print STDERR "[NOT Included] Skipped $_\n";
				next;
			}
		}
		if($self->{OPTS}->{exclude}) {
			if(m/$self->{OPTS}->{exclude}/) {
				print STDERR "[Excluded] Skipped $_\n";
				next;
			}
		}
		s/[\r\n]+/ /g;
		if(m/^qvod:(.+)\t(.+)$/) {
			$self->process_qvod($1,$2);
		}
		elsif(m/^qvod:(.+)$/) {
			$self->process_qvod($1);
		}
		elsif(m/^bdhd:(.+)\t(.+)$/) {
			$self->process_bdhd($1,$2);
		}
		elsif(m/^bdhd:(.+)$/) {
			$self->process_bdhd($1);
		}
		elsif(m/^(ed2k:\/\/.+)\t(.+)$/) {
			$self->process_bhdh($1,$2);
		}
		elsif(m/^(ed2k:\/\/.+)$/) {
			$self->process_bhdh($1);
		}
		elsif(m/^(http:\/\/[^\/]*weipai\.cn\/.*\.(?:jpg|mp4|flv|f4v|mov|ts))\t(.+)$/) {
			push @weipai_urls,[$1,$2];
		}
		elsif(m/^http:\/\/[^\/]*weipai\.cn\/.*\.(?:jpg|mp4|flv|f4v|mov|ts)$/) {
			push @weipai_urls,[$_];
		}
		elsif(m/^(https?:\/\/.+)\t(.+)$/) {
			$self->process_http($1,$2);
		}
		elsif(m/^(https?:\/\/.+)$/) {
			$self->process_http($1);
		}
		elsif(m/^file:\/\/(.+)\t(.+)$/) {
			$self->process_file($1,$2);
		}
		elsif(m/^file:\/\/(.+)$/) {
			$self->process_file($1,"./");
		}
		elsif(m/^data:\/\/(.+)\t(.+)$/) {
			$self->process_data($1,$2);
		}
		elsif(m/$EXPS{torrent}/) {
			$self->process_torrent($1,$2);
		}
		elsif(m/$EXPS{magnet}\t(.+)$/) {
			$self->process_torrent($1,$2);
		}
		elsif(m/$EXPS{magnet}/) {
			$self->process_torrent($1);
		}
		else {
			$MSG->warning("Ignored: URL not supported [$_]\n");
		}
	}
	if($self->{OPTS}->{output}) {
		print STDERR "\n";
		close $FH_OUT;
		return $count;
	}

	if(@weipai_urls) {
		$self->process_weipai_urls(@weipai_urls);
	}

	my $D = scalar(@DOWNLOADS);
	return 1 unless($D);
	
	if($D) {
		my $BATCHGET = new MyPlace::Program::Batchget("--maxtime",3600);
		$BATCHGET->set("--referer",$OPTS{referer}) if($OPTS{referer});
		$BATCHGET->set("--no-clobber") unless($OPTS{overwrite});
		$BATCHGET->set("--urlhist") if($OPTS{history});
		$BATCHGET->set("--maxtask",$OPTS{thread}) if($OPTS{thread});
		foreach(@DOWNLOADS) {
			$BATCHGET->add("$_->[0]\t$_->[1]");
		}
		@DOWNLOADS = ();
		#$MSG->message("$D tasks start to download ...\n");
		$BATCHGET->execute();
	}
	return $count;
}

return 1 if caller;
my $PROGRAM = new(__PACKAGE__);
exit $PROGRAM->execute(@ARGV);

