#!/usr/bin/perl -w
package MyPlace::Program::Downloader;
use strict;
use warnings;
use base 'MyPlace::Program';

sub OPTIONS {qw/
	help|h|? 
	manual|man
	input|i=s
	directory|d=s
	title|t=s
	retry
	ignore-failed|g
	simple
	recursive|r
	quiet
	history
	referer=s
	overwrite|o
	force|f
	exclude|X=s
	include|I=s
	url=s
	touch
	images|img
	videos|vid
	markdone
	no-queue|nq
	no-download
/;}
use MyPlace::Tasks::Manager;
my %EXPS = (
	"bdhd"=>'^(bdhd:\/\/.*\|)([^\|]+?)(\|?)$',
	'ed2k'=>'^(ed2k:\/\/\|file\|)([^\|]+)(\|.*)$',
	'http'=>'^(http:\/\/.*\/)([^\/]+)$',
	'qvod'=>'^(qvod:\/\/.*\|)([^\|]+?)(\|?)$',
	'torrent'=>'^torrent:\/\/([A-Za-z0-9]+)\|?(.+)$',
	'magnet'=>'^(magnet:\?[^\t]+)',
);


sub extname {
	my $filename = shift;
	return "" unless($filename);
	if($filename =~ m/\.([^\.\/\|]+)$/) {
		return $1;
	}
	return "";
}

sub normalize {
	my $_ = $_[0];
	if($_) {
		s/[\?\*\/:\\]/ /g;
	}
	return $_;
}

sub save_weipai {
	my $self = shift;
	my $url = shift;
	my $filename = shift;
	my @prog = ('download_weipai_video');
	if($self->{OPTS}->{'no-download'}) {
		push @prog,"--no-download";
	}
	push @prog,('--mtm',@_,'--',$url);
	push @prog,$filename if($filename);
	my $r = system(@prog);
	$r = $r>>8 if(($r != 0) and $r != 2);
	return $r;
}

sub save_http_post {
	my $self = shift;
	my $url = shift;
	my $data = shift;
	my $filename = shift;
	my @opts = @_;
	if($url =~ m/^([^\t]+)\t(.+)$/) {
		$url = $1;
		$filename = $filename || $2;
	}
	if($url !~ m/^(?:http|https|ftp):\/\//) {
		$url = 'http://' . $url;
	}
	if($url =~ m/^([^\?]+)\?(.+)$/) {
		$url = $1;
		push @opts, '--post', $2;
	}
	return $self->save_http($url,$filename || '',@opts);
}

sub file_exists {
	my $self = shift;
	my $url = shift;
	my $filename = shift;
	return unless($filename);
	return if($self->{OPTS}->{force});
	return if($self->{OPTS}->{overwrite});
	if(-f $filename) {
		$self->print_warn("Ignored <$url>\n  File exists: $filename\n");
		$self->{LAST_EXIT} = $self->EXIT_CODE("OK");
		return 1;
	}
	else {
		return undef;
	}
}

sub save_http {
	my $self = shift;
	my $url = shift;
	my $filename = shift;
	my @opts = @_;
	push @opts,'--url',$url;
	if($filename) {
		return $self->{LAST_EXIT} if($self->file_exists($url,$filename));
		push @opts,'--saveas',$filename if($filename);
	}
	my $r = system('download',@opts);
	$r = $r>>8 if(($r != 0) and $r != 2);
	return $r;
}


sub file_open {
	my $self = shift;
	my $filename = shift;
	my $mode = shift;
	my $FH;
	if(open $FH,$mode,$filename) {
		return $FH;
	}
	return undef;
}

sub save_file {
	my $self = shift;
	my ($link,$filename) = @_;
	$filename = normalize($filename);
	if($self->file_exists($link,$filename)) {
		return $self->{LAST_EXIT};
	}
	$self->print_msg("Write file: $filename\n");
	my $r = system('mv','--',$link,$filename);
	if($r == 0) {
		return $self->EXIT_CODE('OK');
	}
	elsif($r) {
		return $r;
	}
	else {
		return $self->EXIT_CODE('ERROR');
	}
}


sub save_bdhd {
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
		if($self->file_exists($link,$filename)) {
			return $self->{LAST_EXIT};
		}
		$self->print_msg("Write file:$filename\n");
		my $FH = $self->file_open($filename,">:utf8");
		if(!$FH) {
			$self->print_err("Error open file: $filename\n");
			return $self->EXIT_CODE("ERROR");
		}
		print $FH 
<<"EOF";
{
	"bsed":{
		"version":"1,19,0,195",
		"seeds_href":{"bdhd":"$link"}
	}
}
EOF
		close $FH;
		return $self->EXIT_CODE("OK");
	}
	else {
		$self->print_err("Error, No filename specified for: $link\n");
		return $self->EXIT_CODE("ERROR");
	}
}

sub save_qvod {
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
		return $self->{LAST_EXIT} if($self->file_exists($link,$filename));
		$self->print_msg("Write file:$filename\n");
		my $FH = $self->file_open($filename,">:utf8");
		if(!$FH) {
			$self->print_err("Error open file: $filename\n");
			return $self->EXIT_CODE("ERROR");
		}
		print $FH 
<<"EOF";
<qsed version="3.5.0.61"><entry>
<ref href="$link" />
</entry></qsed>
EOF
		close $FH;
		return $self->EXIT_CODE("OK");
	}
}

sub save_data {
	my $self = shift;
	my %OPTS = %{$self->{OPTS}};
	my $data=shift;
	my $filename = shift;
	return unless($filename);
	$data =~ s/\0/\n/g;
	return $self->{LAST_EXIT} if($self->file_exists('<DATA>',$filename));
		$self->print_msg("Write file:$filename\n");
		my $FH = $self->file_open($filename,">:raw");
		if(!$FH) {
			$self->print_err("Error open file: $filename\n");
			return $self->EXIT_CODE("ERROR");
		}
	print $FH $data;
	close $FH;
	return $self->EXIT_CODE("OK");
}

sub save_torrent {
	my $self = shift;
	my $hash = shift;
	my $title = shift;
	require MyPlace::Program::DownloadTorrent;
	my $r;
	if($title) {
		$r = MyPlace::Program::DownloadTorrent::download_torrent($hash,normalize($title));
	}
	else {
		$r = MyPlace::Program::DownloadTorrent::download_torrent($hash);
	}
	return $r;
	if($r == 0) {
		return $self->EXIT_CODE("OK");
	}
	elsif($r) {
		return $r;
	}
	else {
		return $self->EXIT_CODE("ERROR");
	}
}

sub download {
	my $self = shift;
	my $line = shift;
	my @opts = @_;
	$_ = $line;
	my $filename = $_;
	if(!$_) {
		return $self->EXIT_CODE('IGNORED');
	}
	elsif(m/^.+\s*\t\s*(.+)$/) {
		$filename = $1;
	}
	$filename =~ s/.*[\/\\]+//;
	if($self->{OPTS}->{touch}) {
		$self->print_msg("[Touch] $filename\n");
		system("touch","--",$filename);
		return $self->EXIT_CODE("DEBUG");
	}
	elsif($self->{OPTS}->{markdone}) {
		if(-f $filename) {
			$self->print_msg("[Mark done] $filename\n");
			return $self->EXIT_CODE("IGNORED");
		}
		else {
			$self->print_msg("[Not exists] $filename\n");
			return $self->EXIT_CODE("UNKNOWN");
		}
	}
	if(!$_) {
		1;
	}
	elsif(m/^post:\/\/(.+)$/) {
		$self->save_http_post($1);
	}
	elsif(m/^qvod:(.+)\t(.+)$/) {
		$self->save_qvod($1,$2);
	}
	elsif(m/^qvod:(.+)$/) {
		$self->save_qvod($1);
	}
	elsif(m/^bdhd:(.+)\t(.+)$/) {
		$self->save_bdhd($1,$2);
	}
	elsif(m/^bdhd:(.+)$/) {
		$self->save_bdhd($1);
	}
	elsif(m/^(ed2k:\/\/.+)\t(.+)$/) {
		$self->save_bhdh($1,$2);
	}
	elsif(m/^(ed2k:\/\/.+)$/) {
		$self->save_bhdh($1);
	}
	elsif(m/^(http:\/\/[^\/]*(?:weipai\.cn|oldvideo\.qiniudn\.com)\/.*\.(?:jpg|mp4|flv|f4v|mov|ts))\t(.+)$/) {
		$self->save_weipai($1,$2);
	}
	elsif(m/^(http:\/\/[^\/]*(?:weipai\.cn|oldvideo\.qiniudn\.com)\/.*\.(?:jpg|mp4|flv|f4v|mov|ts))$/) {
		$self->save_weipai($_);
	}
	elsif(m/^(https?:\/\/.+)\t(.+)$/) {
		$self->save_http($1,$2);
	}
	elsif(m/^(https?:\/\/.+)$/) {
		$self->save_http($1);
	}
	elsif(m/^file:\/\/(.+)\t(.+)$/) {
		$self->save_file($1,$2);
	}
	elsif(m/^file:\/\/(.+)$/) {
		$self->save_file($1,"./");
	}
	elsif(m/^data:\/\/(.+)\t(.+)$/) {
		$self->save_data($1,$2);
	}
	elsif(m/$EXPS{torrent}/) {
		$self->save_torrent($1,$2);
	}
	elsif(m/$EXPS{magnet}\t(.+)$/) {
		$self->save_torrent($1,$2);
	}
	elsif(m/$EXPS{magnet}/) {
		$self->save_torrent($1);
	}
	else {
		$self->print_err("Error: URL not supported [$_]\n");
		$self->EXIT_CODE("ERROR");
	}
}

sub MAIN {
	my $self = shift;
	my $OPTS = shift;
	$self->{OPTS} = $OPTS;
	if($OPTS->{directory}) {
		system("ls","-ld","--",$OPTS->{directory});
	}
	elsif($OPTS->{url}) {
	}
	elsif(@_) {
		foreach(@_) {
			if(-e $_) {
				system("ls","-ld","--",$_);
			}
		}	
	}
	if($self->{OPTS}->{url}) {
		return $self->download($self->{OPTS}->{url});
	}
	my @include;
	push @include,$OPTS->{include} if($OPTS->{include});
	push @include,'\.(?:jpg|gif|png|jpeg)' if($OPTS->{images});
	push @include,'\.(?:flv|mov|f4v|avi|mkv|mpg|mpeg|rmvb|asf|wmv|ts|mp4|3pg)' if($OPTS->{'videos'});
	if(@include) {
		$OPTS->{include} = join("|",@include);
	}
	my @exclude;
	push @exclude,$OPTS->{exclude} if($OPTS->{exclude});
	push @exclude,'\.(?:jpg|gif|png|jpeg)' if($OPTS->{'no-images'});
	push @exclude,'\.(?:flv|mov|f4v|avi|mkv|mpg|mpeg|rmvb|asf|wmv|ts|mp4|3pg)' if($OPTS->{'no-videos'});
	if(@exclude) {
		$OPTS->{exclude} = join("|",@exclude);
	}

	my $mtm = MyPlace::Tasks::Manager->new(
		directory=>$OPTS->{directory},
		worker=>sub {
			return $self->download(@_);
		},
		title=>
			defined($OPTS->{title}) ? $OPTS->{title} : 
			defined($OPTS->{directory}) ? $OPTS->{directory} :
			'MyPlace Downloader',
		force=>$OPTS->{force},
		overwrite=>$OPTS->{overwrite},
		retry=>$OPTS->{retry},
		'ignore-failed'=>$OPTS->{'ignore-failed'},
		simple=>$OPTS->{simple},
		'recursive'=>$OPTS->{recursive},
		quiet=>$OPTS->{quiet},
		include=>$OPTS->{include},
		exclude=>$OPTS->{exclude},
		'no-queue'=>$OPTS->{'no-queue'},
		'no-download'=>$OPTS->{'no-download'},
	);
	
	if($OPTS->{input}) {
		$mtm->set('input',$OPTS->{input});
	}
	return $mtm->run(@_);
}

return 1 if caller;
my $PROGRAM = new MyPlace::Program::Downloader;
my ($done,$error,$msg) = $PROGRAM->execute(@ARGV);
if($error) {
	print STDERR "Error($error): $msg\n";
}
if($done) {
	exit 0;
}
elsif($error) {
	exit $error;
}
else {
	exit 0;
}


1;
__END__

=pod

=head1  NAME

myplace-downloader - PERL script

=head1  SYNOPSIS

myplace-downloader [options] inputs...

	myplace-downloader --force 'http://aliv.weipai.cn/201408/14/16/007F1EF5-0AE5-41B9-950B-97655752B0DA.jpg  2014081416_rococoshop.jpg'
	cat urls.txt | myplace-downloader --overwrite
	myplace-downloader --force --overwrite --input urls.lst

=head1  OPTIONS

=over 12

=item B<-g>,B<--ignore-failed>

Write failed task to DB_IGNORE

=item B<-i>,B<--input>

Read URLs definition from specified file

=item B<-f>,B<--force>

Force download mode, ignore DB_DONE, DB_IGNORE

=item B<-o>,B<--overwrite>

Overwrite download mode

=item B<-t>,B<--title>

Specified prompting text

=item B<-d>,B<--directory>

Specified working directory

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

Downloader use MyPlace::Tasks::Manager

=head1  CHANGELOG

    2015-01-26 02:34  xiaoranzzz  <xiaoranzzz@MyPlace>

		* version 0.1

    2015-01-26 02:19  xiaoranzzz  <xiaoranzzz@MyPlace>
        
        * file created.

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@MyPlace>

=cut

#       vim:filetype=perl
