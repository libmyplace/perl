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
	qw{
		http://torcache.net/torrent/:HASH:/TORRENTNAME.torrent
		http://torrentproject.se/torrent/:HASH:.torrent
		http://www.torrenthound.com/torrent/:HASH:
		http://torrage.com/torrent/:HASH:.torrent
		http://zoink.it/torrent/:HASH:.torrent
		http://torrage.ws/torrent/:HASH:.torrent
		http://www.sobt.org/url.php?hash=:HASH:&name=TORRENTNAME
	}
);

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
sub download {
	my $output = shift;
	my $URL = shift;
	my $REF = shift(@_) || $URL;
	$DL ||= MyPlace::Program::Download->new('--quiet','--maxtry',1);
	if($DL->execute("-r=$REF","-u=$URL","-s=$output") == 0) {
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
	my $hash = uc($URI);

	if($hash =~ m/^([\dA-Z]+)\s*\t\s*(.+?)\s*$/) {
		$hash = uc($1);
		$title = $2 if(!$title);
	}
	else {
		if($URI =~ m/^magnet:\?.*xt=urn:btih:([\dA-Za-z]+)/) {
			$hash = uc($1);
		}
		if(!$title and $URI =~ m/[^\t]+\t(.+)$/) {
			$title = $1;
		}
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
		$filename = ($title ? $title . "_" : "") . $hash . ".torrent";
	}
	if($dest) {
		$output = File::Spec->catfile($dest,$filename);
	}
	else {
		$output = $filename;
	}
	
	app_message2 "Downloading torrent:\n==> $output\n";
	if(checktype($output)) {
		app_warning "Error, File already downloaded, Ignored\n";
		return 0;
	}
	foreach(@SITES,@SITES) {
		my $sitename = $_;
		if(m/:\/\/([^\/]+)/) {
			$sitename = $1;
		}
		my $url = $_;
		$url =~ s/:HASH:/$hash/g;
		print STDERR "Try [$sitename] ... ";
		if(download($output,$url)) {
			color_print('GREEN',"  [OK]\n");
			return 0;
		}
		else {
			color_print('red',"  [FAILED]\n");
		}
	}
	return 1;
}

sub USAGE {
	my $self = shift;
	require Pod::Usage;
	Pod::Usage::pod2usage('-input',__FILE__,@_);
	return 0;
}

sub OPTIONS {
	return \@OPTIONS;
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
		download_torrent(@argv);
	}
}


__END__

=pod

=head1  NAME

download_torrent - PERL script

=head1  SYNOPSIS

download_torrent [options] ...

=head1  OPTIONS

=over 12

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

___DESC___

=head1  CHANGELOG

    2014-06-18 00:07  xiaoranzzz  <xiaoranzzz@MyPlace>
        
        * file created.

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@MyPlace>

=cut

#       vim:filetype=perl
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw();
    @EXPORT_OK      = qw();
}
1;

