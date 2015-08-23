#!/usr/bin/perl -w
package MyPlace::Program::DownloadTorrent;
use strict;
use warnings;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw(&download_torrent);
    @EXPORT_OK      = qw(&download_torrent &download \@SITES);
}
use File::Spec;
use MyPlace::Script::Message;
use MyPlace::Program::Download;
use base 'MyPlace::Program';

our $DL;
our $VERSION = 'v0.1';
our @OPTIONS = qw/
	help|h|? 
	manual|man
	verbose|v
	log|l
/;


my $VERBOSE;
my $SCRIPTDIR;


our @SITES = (
	#http://www.520bt.com/Torrent/:HASH:
	#http://torcache.net/torrent/:HASH:.torrent	
	#http://torrage.ws/torrent/:HASH:.torrent
	#http://torrentproject.se/torrent/:HASH:.torrent
	qw{
		http://www.sobt.org/Tool/downbt?info=:HASH:
		http://torcache.net/torrent/:HASH:.torrent
		http://www.torrenthound.com/torrent/:HASH:
		http://torrage.com/torrent/:HASH:.torrent
		http://zoink.it/torrent/:HASH:.torrent
		http://www.mp4ba.com/down.php?date=1422367802&hash=:HASH:
	}
);

sub error_no {
	return MyPlace::Program::EXIT_CODE(@_);
}

sub checktype {
	my $output = shift;
	return unless(-f $output);
	my $type = `file -b --mime-type -- "$output"`;
	chomp $type;
	if($type =~ m/torrent|octet-stream/) {
		return 1,$type;
	}
	return undef,$type;
}
sub normalize {
	my $_ = $_[0];
	if($_) {
		s/[\?\*\/:\\]/ /g;
	}
	return $_;
}
sub download {
	my $output = shift;
	my $URL = shift;
	my $REF = shift(@_) || $URL;
	$DL ||= MyPlace::Program::Download->new('--compressed','--quiet','--maxtry',1);
	if($DL->execute("-r",$REF,"-u",$URL,"-s",$output) == 0) {
		my ($ok,$type) = checktype($output);
		if($ok) {
			return 1;
		}
		else {
			print STDERR " ($type) ";
			unlink($output);
		}
	}
	return undef;
}


sub download_torrent {
	my $URI = shift;
	my $title = shift;
	my $dest = shift;
	my $filename = shift;

	
	if(!$title and $URI =~ m/^([^\t]+)\t(.+)$/) {
		$URI = $1;
		$title = $2;
	}

	my $hash;

	if($URI =~ m/^([\dA-Za-z]+)$/) {
		$hash = uc($1);
	}
	elsif(uc($URI) =~ m/^MAGNET:\?.*XT=URN:BTIH:([\dA-Z]+)/) {
			$hash = $1;
	}
	else {
		app_error "No HASH information found in $URI\n";
		return error_no("ERROR");
	}
	
	my $output = "";
	
	if(!$filename) {
		if(!$title) {
			my $getor = File::Spec->catfile($SCRIPTDIR,"gettorrent_title.pl");
			$getor =  File::Spec->catfile($SCRIPTDIR,"gettorrent_title") unless(-f $getor);
			if(-f $getor) {
				$title = `perl "$getor" "$hash"`;
			}	
			else {
				$title = `gettorrent_title "$hash"`
			}
			chomp($title) if($title);
		}
		$filename = ($title ? normalize($title) . "_" : "") . $hash;
	}
	else {
		$filename =~ s/\.torrent$//gi;
	}
	if($dest) {
		$output = File::Spec->catfile($dest,$filename);
	}
	else {
		$output = $filename;
	}

	app_message "\n$URI\n";
	if($URI =~ m/^(magnet:[^\t]+)/) {
		$URI =~ s/&amp;/&/g;
		app_message2 "Save magnet uri:\n  =>$filename.txt\n";
		if(open FO,">:utf8",$output . ".txt") {
			print FO $URI,"\n";
			close FO;
			print STDERR "[OK]\n";
		}
		else {
			print STDERR "Error:$!\n";
		}
	}
	app_message2 "Save torrent file:\n  =>$filename.torrent\n";
	$output .= ".torrent";
	if(checktype($output)) {
		app_warning "Error, File already downloaded, Ignored\n";
		return error_no("IGNORED");
	}
	foreach my $site (@SITES) {
		my $sitename = $site;
		if($site =~ m/:\/\/([^\/]+)/) {
			$sitename = $1;
		}
		my $url = $site;
		$url =~ s/:HASH:/$hash/g;
#		print STDERR "<= $url\n";
		print STDERR "  Try [$sitename] ... ";
		if(download($output,$url)) {
			color_print('GREEN',"  [OK]\n");
			color_print('GREEN', "[OK]\n\n");
			return error_no("OK");
		}
		else {
			color_print('RED',"  [FAILED]\n");
		}
	}
	color_print('RED',"[Failed]\n\n");
	return error_no("FAILED");
}

sub USAGE {
	my $self = shift;
	require Pod::Usage;
	Pod::Usage::pod2usage('-input',__FILE__,@_);
	return 0;
}

sub OPTIONS {
	return @OPTIONS;
}

sub MAIN {
	my $self = shift;
	my $OPTS = shift;
	my @argv = @_;
	$VERBOSE = $OPTS->{'verbose'};
	$SCRIPTDIR = $0;
	$SCRIPTDIR =~ s/[\/\\]+[^\/\\]+$//;
	if(!@argv) {
		my @LINES;
		my $count;
		my $index;
		while(<STDIN>) {
			chomp;
			push @LINES,$_ if($_);
		}
		$count = @LINES;
		foreach my $line(@LINES) {
			$index++;
			print STDERR "TASK $index/$count: \n";
			my @args = split(/\s*\t\s*/,$line);
			download_torrent(@args);
		}
	}
	else {
		return download_torrent(@argv);
	}
}

return 1 if caller;
my $PROGRAM = new MyPlace::Program::DownloadTorrent;
exit $PROGRAM->execute(@ARGV);



__END__

=pod

=head1  NAME

download_torrent - Bittorrent torrent file downloader

=head1 SYNOPSIS

download_torrent [options] <hash value|magnet URI> <title>

	download_torrent ADFDSFEWAFDSAFDSAFDGREARAGFDSFD2214DAFDSA sorrynoname

=head1  OPTIONS

=over 12

=item B<--version>

Print version infomation.

=item B<-h>,B<--help>

Print a brief help message and exits.

=item B<--manual>,B<--man>

View application manual

=back

=head1  DESCRIPTION

Bittorrent torrent files downloader

=head1  CHANGELOG

    2014-06-18 00:07  xiaoranzzz  <xiaoranzzz@MyPlace>
        
        * file created.

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@MyPlace>

=cut

#       vim:filetype=perl

