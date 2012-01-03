#!/usr/bin/perl -w
# $Id$
package MyPlace::Program::Batchget;
our $VERSION = 'v0.3';
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw();
    @EXPORT_OK      = qw();
}
use strict;
use warnings;
use Cwd qw/getcwd/;
use MyPlace::ParallelRun;
use URI::Escape;
use MyPlace::Script::Message;
use Getopt::Long;
use MyPlace::Usage;
my @OPTIONS = qw/
                help|h|? version|ver edit-me manual|man
                autoname|a cookie|b=s createdir|d ext|e=s 
                fullname|f logger|L=s maxtime|M=i maxtask|m=i
                taskname|n=s referer|r=s workdir|w=s urlhist|U
                no-clobber|nc|c numlen|i=i
              /;

my $URL_DATABASE_FILE = 'URLS.txt';
my %URL_DATABASE;

sub load_database {
	my $self = shift;
    open FI,"<",$URL_DATABASE_FILE or return;
    while(<FI>) {
        chomp;
        $self->{database}->{$_}=1;
    }
    close FI;
}
sub check_database {
	my $self = shift;
    my $url = shift;
	return undef unless($self->{database});
	return 1 if($self->{database}->{$url});
	$self->{database}->{$url} = 1;
	return undef;
}
sub save_database {
	my $self = shift;
	return 1 unless($self->{database});
    open FO,">",$URL_DATABASE_FILE or return;
    foreach (keys %{$self->{database}}) {
        print FO $_,"\n";
    }
    close FO;
}
sub Uniqname($) {
    my $ext =shift;
    my $max = 10000000000;
    my $result;
    do { 
        my $n1 = int (rand($max));
        my $n2 = log($max / $n1)/log(10);
        $result=$n1 . "0"x$n2 . $ext;
    } until (! -f $result);
    return $result;
}
sub GetFilename_Fullname {
	my $self = shift;
    my $result=shift;
    $result =~ s/^.*:\/\///;
    $result =~ s/[\/\?\:\\\*\&]/_/g;
    $result =~ s/&//g;
    return $result;
}

sub GetFilename_Auto {
	my $self = shift;
    my $URL=shift;
    my $num=shift;
	my $createdir = $self->{options}->{createdir};
    my $result;
    $result = $URL;
    $result =~ s/^.*:\/\///;
    $result =~ s/[\/\?\:\\\*\&]/_/g;
    $result =~ s/&//g;
    if(length($result)>=128) {
        $result = substr($result,0,127);
    }
    $result = "$num.$result" if($num);
    if($createdir) {
        my $dirname=$URL;
        $dirname =~ s/^.*:\/*[^\/]*\///;
        $dirname =~ s/\/[^\/]*//;
        $dirname .= "/" if($dirname);
        $result = $dirname . $result;    
    }
    return $result;
}
sub	GetFilename_NoAuto {
	my $self = shift;
    my $result=shift;
	my $createdir = $self->{options}->{createdir};
    if($createdir) {
        $result =~ s/^.*:\/*[^\/]*\///;
    }
    else {
        $result =~ s/^.*\///;
    }
    return $result;
}

sub set_workdir {
    my $w = shift;
    return undef unless($w);
    if(! -d $w) {
        system("mkdir","-p","--",$w) and die("$!\n");
    }
    chdir $w or die("$!\n");
    return $w;
}

sub new {
	my $class = shift;
	my $self = bless {},$class;
	$self->set(@_);
	return $self;
}

sub set {
	my $self = shift;
	my %OPTS;
	if(@_)
	{
		Getopt::Long::Configure('no_ignore_case');
	    Getopt::Long::GetOptionsFromArray(\@_,\%OPTS,@OPTIONS);
		MyPlace::Usage::Process(\%OPTS,$VERSION);
	}
	$self->{options} = \%OPTS;
	push @{$self->{tasks}},@_ if(@_);
	return $self;
}

sub readfile {
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
		$self->add($_);
	}
	close $fh unless($GLOB);
	return $self->{tasks};
}

sub add {
	my $self = shift;
	my $task = shift;
	if(!$task) {
		app_error("Error nothing to add\n");
		return undef;
	}
    elsif($self->check_database($_)) {
        app_warning("[Ignored, In DATABASE]$_\n");
		return undef;
    }
    elsif($_ =~ /^([^\t]+)\t+(.+)$/) {
		push @{$self->{tasks}},[$1,$2];
    }
	else {
		push @{$self->{tasks}},$_;
    }
	return $self->{tasks};
}

sub execute {
	my $self = shift;
	my %OPTS;
	if(@_)
	{
		Getopt::Long::Configure('no_ignore_case');
	    Getopt::Long::GetOptionsFromArray(@_,\%OPTS,@OPTIONS);
		MyPlace::Usage::Process(\%OPTS,$VERSION);
	}
	%OPTS = (%{$self->{options}},%OPTS);
	$self->add($_) foreach(@_);
	my $def_mul=3;
	my $createdir = $OPTS{"createdir"} ? $OPTS{"createdir"} : 0;
	my $muldown   = $OPTS{"maxtask"} ? $OPTS{"maxtask"} : $def_mul;
	my $taskname  = $OPTS{"taskname"} ? $OPTS{"taskname"} : "";
	my $autoname  = $OPTS{"autoname"} ? $OPTS{"autoname"} : 0;
	my $extname   = $OPTS{"ext"} ? $OPTS{"ext"} : "";
	my $workdir   = $OPTS{"workdir"} ? $OPTS{"workdir"} : "";
	my $refer     = $OPTS{"referer"} ? $OPTS{"referer"} : "";
	my $logger    = $OPTS{"logging"} ? $OPTS{"logging"} : "";
	my $number    = $OPTS{"numlen"} ? $OPTS{"numlen"} : "";
	my $fullname  = $OPTS{"fullname"} ? 1 : 0;
	my $urlhist   = $OPTS{'urlhist'} ? 1 : 0;
	$autoname="true" if($number);
	$taskname = "" unless($taskname);
	$muldown = 1 if( $muldown<1);
	my $prefix = $taskname ? $taskname . " " : "";
	my $index=0;
	my $count=0;
	my $PWD;
	if($workdir) {
	    set_workdir($workdir);
	}
	$PWD = getcwd;
	if($OPTS{cookie}) {
	    system("mkcookie '$OPTS{cookie}' >download.cookie");
	    $OPTS{cookie}="download.cookie";
	}
	$self->load_database() if($urlhist);
	$count = $self->{tasks} ? scalar(@{$self->{tasks}}) : 0;
	if($count < 1) {
		app_error("Nothing to do\n");
		return 0;
	}
	app_message("Initializing...\n");
	#para_init $muldown;
	use MyPlace::Program::Download;
	my $dl = new MyPlace::Program::Download (
		-maxtime=>$OPTS{maxtime} || '0',
		-cookie=>$OPTS{cookie} || '',
		"-d",
	);
	my %QUEUE;
	while (@{$self->{tasks}}) {
		my $_ = shift @{$self->{tasks}};
		$index++;
		my $msghd = "${prefix}\[$index/$count]";
		next unless($_);
		my $url;
		my $filename ;
		if(ref $_) {
			$url = $_->[0];
			$filename = $_->[1];
		}
		else {
			$url = $_;
			$filename = "";
		}
		app_message($msghd,"Queuing $url...\n");
		app_message("\t$filename\n") if($filename);
	    if($url =~ m/^#BATCHGET:chdir:(.+)$/) {
	        my $w = $1;
	        $w =~ s/[:\?\*]+//g;
	        if($w) {
				app_message($msghd,"Program action [chdir] to $1\n");
	            chdir $PWD or die("$!\n");
	            set_workdir($w);
	        }
	    }
		elsif($QUEUE{$_}) {
			app_warning($msghd,"Duplicated task. [Ignored]\n");
		}
		else {
			if(!$filename) {
				my $stridx = "0" x (length($count)-length($index)+1) . $index if($number);
				$filename = $fullname ? $self->GetFilename_Fullname($url) 
					: $autoname ? $self->GetFilename_Auto($url,$stridx) 
					: $self->GetFilename_NoAuto($url);
			}
			if($OPTS{"no-clobber"} and -f $filename) {
				app_warning($msghd,"$url\t[Ignored, TARGET EXISTS]\n");
	            next;
			}
			if($logger) {system($logger,$filename,$url);}
			my $exitval = $dl->execute(
				'-saveas'=>$filename,
				#'-n'=>$msghd,
				'-r'=>$OPTS{'referer'} || $url,
				'-url'=>$url
			);
			if($exitval == 2) {
				app_warning("Child process killed\n");
				return 2;
			}
	    }
	}
	chdir $PWD;
#	para_cleanup();
	$self->save_database() if($urlhist);
	return 0;
}

1;
#print STDERR ("\n");
#exit 0 unless($count);



__END__

=pod

=head1  NAME

batchget - A batch mode downloader

=head1  SYNOPSIS

batchget [options] ...

cat url.lst | batchget

cat url.lst | batchget -a -d 

=head1  OPTIONS

=over 12

=item B<-a,--autoname>

Use indexing of URLs as output filename 

=item B<-b,--cookie>

Use cookie jar

=item B<-c,--nc,--no-clobber>

No clobber when target exists.

=item B<-d,--createdir>

Create directories

=item B<-e,--ext>

Extension name for autonaming

=item B<-f,--fullname>

Use URL as output filename

=item B<-i,--numlen>

Number length for index filename

=item B<-M,--maxtime>

Max time for a single download process

=item B<-m,--maxtask>

Max number of simulatanous downloading task

=item B<-n,--taskname>

Task name

=item B<-r,--referer>

Global referer URL

=item B<-w,--workdir>

Global working directory

=item B<-U,--urlhist>

Use URL downloading history databasa

=item B<--version>

Print version infomation.

=item B<-h>,B<--help>

Print a brief help message and exits.

=item B<--manual>,B<--man>

View application manual

=item B<--edit-me>

Invoke 'editor' against the source

=back

=head1  DESCRIPTION

A downloader which can download multiple urls at the same time and/or in queue.

=head1  CHANGELOG

    2007-10-28  xiaoranzzz  <xiaoranzzz@myplace.hell>
    
        * file created, version 0.1

    2010-08-03  xiaoranzzz  <xiaoranzzz@myplace.hell>
        
        * update to version 0.2

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@myplace.hell>

=cut


1;

__END__
=pod

=head1  NAME

MyPlace::Program::Batchget - PERL Module

=head1  SYNOPSIS

use MyPlace::Program::Batchget;

=head1  DESCRIPTION

___DESC___

=head1  CHANGELOG

    2012-01-03 18:03  afun  <afun@myplace.hell>
        
        * file created.

=head1  AUTHOR

afun <afun@myplace.hell>


# vim:filetype=perl

