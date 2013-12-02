#!/usr/bin/perl -w
package MyPlace::Program::Download;
use strict;
use warnings;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw();
    @EXPORT_OK      = qw();
}
use Cwd;
use MyPlace::Script::Message;
use Getopt::Long qw/GetOptionsFromArray/;
use Pod::Usage;
use MyPlace::Filename qw/get_uniqname/;
use URI;

my @OPTIONS = qw/
		help|h
		manual|man
		verbose|v
		url|u:s
		saveas|s:s
		directory|d
		name|n:s
		cookie|b:s
		log|l
		refurl|r:s
		autoname|a
		program|p:s
		maxtime|m:i
		force|f
		connect-timeout:i
	/;
my $proxy = '127.0.0.1:9050';
my $blocked_host = '\n';#wretch\.cc|facebook\.com|fbcdn\.net';
my $BLOCKED_EXP = qr/^[^\/]+:\/\/[^\/]*(?:$blocked_host)(?:\/?|\/.*)$/;
my @WGET = qw{
    wget --user-agent Mozilla/5.0 --connect-timeout 15 -q --progress bar
};
my @CURL = qw{
        curl
		--fail --globoff --location
		--user-agent Mozilla/5.0
		--progress-bar --create-dirs
		--connect-timeout 15
		--location
};
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
	push @{$self->{urls}},@_ if(@_);
}

sub execute {
	my $self = shift;
	my $OPT;
	if(@_) {
		$OPT= {};
		GetOptionsFromArray(\@_,$OPT,@OPTIONS);
		$OPT = cathash($self->{options},$OPT);
		push @{$self->{urls}},@_ if(@_);
	}
	else {
		$OPT = $self->{options};
	}
	if($OPT->{help}) {
		pod2usage('-exitval'=>1,'-verbose'=>1);
		return 1;
	}
	elsif($OPT->{manual}) {
		pod2usage('--exitval'=>1,'-verbose'=>2);
		return 2;
	}
	my $exitval = $self->_download($OPT);
	return $exitval;
}

sub log($$) {
    my $text=shift;
    my $fn=shift;
    open FO,">>",$fn or return;
    print FO $text;
    close FO;
}

sub build_cmdline {
    my($name,$url,$saveas,$refer,$cookie,$verbose,$maxtime) = @_;
    return undef unless($url);
    my @result;
    if($name =~ /^wget$/i) {
        push @result,@WGET;
        push @result,"--referer",$refer ? $refer : $url;
        push @result,"--output-document",$saveas if($saveas);
        push @result,"--load-cookie",$cookie if(-f $cookie);
        push @result,"--save-cookie",$cookie if($cookie);
        push @result,'--read-timeout',$maxtime if($maxtime);
        push @result,$url;
    }
    else {
        push @result,@CURL;
        push @result,"--url",$url;
        push @result,"--referer",$refer ? $refer : $url;
        push @result,"--output",$saveas if($saveas);
        push @result,"--cookie",$cookie if(-f $cookie);
        push @result,"--cookie-jar",$cookie if($cookie);
        push @result,"--max-time",$maxtime if($maxtime);
        if($url =~ $BLOCKED_EXP) {
            app_message "USE PROXY $proxy\n";
            push @result,"--socks5-hostname",$proxy;
        }
    }
    return @result;
}

sub _process {
    my $taskname=shift;
    my $cmdline=shift;
    my $retry = shift || 2;
    my $r=0;
    while($retry) {
        $retry--;
		if(!open FI,'-|',@{$cmdline}) {
			return undef,"$!";
		}
		my @data = <FI>;
		close FI;# or return undef,"$!";
		$r = $?;
#        $r=system(@{$cmdline});
        return (0,@data) if($r==0);
        return 2 if($r==2); #/KILL,TERM,USERINT;
        $r = $r>>8;
        #2 =>
        #22 => Request Error 404,403,400
        #56 => Recv failure: Connection reset by peer
		#47 => Reach max redirects.
		#52 => curl: (52) Empty reply from server
        return $r if(
			$r == 2 
			or $r == 22 
			or $r == 56 
			or $r == 6 
			or $r=47
			or $r = 52
			);
        app_warning "\rdownload:error($r), wait 1 second,retry $taskname\n";
        sleep 1;
    }
    return 1;
}

sub fixlength_msg {
		my $a = shift;
		my $max = shift;
		my $l = length($a);
		if($l > $max) {
			my $left = int(($max)/2*3);
			my $right = $l - int($max/3)-6;
			return substr($a,0,$left) . " ... " . substr($a,$right);
		}
		else {
			return $a;
		}
}

#my $OptFlag='m:lvu:s:dn:r:b:ap:f';
#my %OPT;
#getopts($OptFlag,\%OPT);
sub _download {
	my $self = shift;
	my $options = shift;
#	my $options = $self->{options} || {};
	my $downloader = $options->{program} || 'curl';
	my $cookie= $options->{cookie} || '';
	my $FAILLOG="download.failed";
	my $DOWNLOADLOG="download.log";
	
	push @{$self->{urls}},$options->{url} if($options->{url});
	#use Data::Dumper;print Data::Dumper->Dump([$self->{urls},$options->{url}],[qw/*urls *url/]);
	#die();
	if(!$self->{urls}) {
		app_error("No URL specified\n");
		return 11;
	}
	my $idx = 0;
	my $count = scalar(@{$self->{urls}});
	my $exitval = 0;
	while(@{$self->{urls}}) {
		$_ = shift @{$self->{urls}};
		next unless($_);
		my $url = $_;
		my $saveas = $options->{saveas};
		#$options->{saveas} = undef;
		if(ref $_) {
			$url = $_->[0];
			$saveas = $_->[1] if($_->[1]);
		}
		if ($url !~ m/^\w+:\/\// ) {
		    app_error("Invaild URL:\"",$url,"\"\n");
			$exitval = 12;
			next;
		}
		if($url =~ m/^([^\t]+)(?:\t+|    )(.+)$/) {
			$url = $1;
			$saveas = $2 if($2);
		}
		
		my $eurl = URI->new($url);
		my $refer=$options->{refurl} || $url;
		if($options->{createdir} && !$saveas) {
		    my $filename=$url;
		    $filename =~ s/^\w+:\/+[^\/]*\/+//;
		    $filename =~ s/^[^\?]*\?[^\/]*\/+//g;
		    $saveas=$filename;
		}
		if(!$saveas) {
		    my $basename=$url;
		    $basename =~ s/^.*\///g;
		    $basename = "index.html" unless($basename);
		    $saveas=$basename;
		}
		if($saveas =~ m/\/$/) {
		    $saveas .= "index.html";
		}
		if($saveas and $options->{autoame} and -f $saveas) {
		    $saveas = get_uniqname($saveas);
		}
		
		my $name= $options->{"name"} || "";
		$idx++;
		$name = "${name}[$idx/$count]" if($count>1);
		my $message;
		if($options->{verbose}) {
		    $message = sprintf("%s\n%-8s: %s\n%-8s: %s\n%-8s: %s\n",
		            $name ? "\n$name" : "",
		            "URL",$url,
		            "SaveAs",$saveas,
		            "Refer",$refer);
		}
		else {
		    $message = "$name$url\t[starting]\n";
		}
		app_message fixlength_msg($message,60);
		
		if ((!$options->{force}) and -f "$saveas" ) {
		    app_warning "$saveas exists\t[canceled]\n";
			$exitval = 13;
			next;
		}
		
		if($cookie) {
		    if(!-f $cookie) {
		        app_message "creating cookie for $url...\n";
		        my @match = $url =~ /^(http:\/\/[^\/]+)\//;
		        if(@match) {
		            my $domain=$match[0];
		            system("curl --url '$domain' -c '$cookie' -o '/dev/null'");
		        }
		    }
		}
		
		#my $saveas_temp = "$saveas.downloading";
		my @cmdline = build_cmdline(
			$downloader,
			$eurl,
			undef,
#			$saveas_temp,
			$refer,
			$cookie,
			$options->{verbose},
			$options->{maxtime}
		);
		my ($r,@data)=_process("$name$url",\@cmdline,2);
#		print STDERR "EXITVAL:$r\n";
		if(!defined $r) {
			app_error("\nExecuting \'" . join(" ",@cmdline) . "\'\nError: ",@data,"\n");
			next;
		}
		elsif($r==0 and @data) {
			open FO, ">:raw",$saveas or die("Error writting $saveas: $!\n");
			print FO @data;
			close FO;
#		    unlink ($saveas) if(-f $saveas);
#		    rename($saveas_temp,$saveas) or die("$!\n");
		    &log("$url->$saveas\n","$DOWNLOADLOG") if($options->{log});
		    app_ok "$name$saveas\t[completed]\n";
			$exitval = 0;
			next;
		}
		elsif($r==2) {
#		    unlink $saveas_temp if(-f $saveas_temp);
		    app_warning "$name$url\t[killed]\n";
			$exitval = 2;
			return $exitval;
		}
		else {
#		    unlink $saveas_temp if(-f $saveas_temp);
		    app_error "$name$url\t[failed]\n";
		    &log("$url->$saveas\n","$FAILLOG") if($options->{log});
			$exitval = 1;
			next;
		}
	}
	return $exitval;
}

1;

__END__

=pod

=head1 NAME

download - customized frontend for wget/curl

=head1 SYNOPSIS

download [OPTIONS] URL

	download "http://www.google.com"
	download -s google.html "http://www.google.com"
	download -a "http://www.google.com"

=head1 OPTIONS

=over

=item B<--verbose>,B<-v>

Verbose messaging

=item B<--url>,B<-u>

Specify the URL

=item B<--saveas>,B<-s>

Specify target filename

=item B<--directory>,B<-d>

Create directories if necessary

=item B<--name>,B<-n>

Name downloading session

=item B<--refurl>,B<-r>

Set referer URL

=item B<--cookie>,B<-b>

Set cookie file

=item B<--log>,B<-l>

Enable logging

=item B<--autoname>,B<-a>

Auto rename if target exists

=item B<--program>,B<-p>

Specify downloader, either wget or curl

=item B<--maxtime>,B<-m>

Set timeout

=item B<--force>,B<-f>

Force overwritting

=back

=head1 DESCRIPTION

Not a downloader indeed, but simply a frontend for
some real downloader e.g. B<curl> or B<wget>.

=head1 CHANGELOG

2007-10-28	xiaoranzzz	<xiaoranzzz@myplace.hell>

* Initial version

2012-12-19	xiaoranzzz	<xiaoranzzz@myplace.hell>

* Add pod document
* Use Getopt::Long.

=head1 AUTHOR

xiaoranzzz <xiaoranzzz@myplace.hell>

=cut




# vim:filetype=perl
