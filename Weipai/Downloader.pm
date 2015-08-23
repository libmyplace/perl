#!/usr/bin/perl -w
package MyPlace::Weipai::Downloader;
use strict;
use warnings;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw(&download);
    @EXPORT_OK      = qw(&download);
}
use base 'MyPlace::Program';
use MyPlace::Program::Download;

my $DOWNLOADER;
my %VIDEO_TYPE = (
	'.mp4'=>'/500k.mp4',
	'.mov'=>'.mov',
	'.flv'=>'.flv',
);



my @URL_RECORD;

my $cookie = $ENV{HOME} . "/.cookies.weipai.dat";
sub init {
	$DOWNLOADER = new MyPlace::Program::Download('--cookie',$cookie);
	@URL_RECORD = ();
	print STDERR "Opening http://weipai.cn/...";
	if($DOWNLOADER->execute('--url','http://weipai.cn','--quiet','--test') == 0) {
		print STDERR "  [OK]\n";
	}
	else {
		print STDERR "  [FAILED]\n";
	}
}

sub hist_check_url {
	my $url = shift;
	my $basename = shift;
	my $suffixs = shift;
	my $dup = 0;
	if(!@URL_RECORD) {
		if(open FI,'<','URLS.txt') {
			foreach(<FI>) {
				chomp;
				push @URL_RECORD,$_;
			}
			close FI;
		}
	}
	return 0 unless($url);

	foreach(@URL_RECORD) {
		last if($dup);
		my $len2 = length($_);
		foreach my $suffix (@$suffixs) {
			my $eurl = $url . $suffix;
			my $len1 = length($eurl);
			#print STDERR "\n";
			#print STDERR "$eurl\n";
			#print STDERR "$_\n";
			#print STDERR substr($_,0,$len),"\n";
			#print STDERR "\n";
			if($len2 < $len1) {
				next;
			}
			elsif($len2 > $len1) {
				my $lastc = substr($_,$len1,1);
				if(($lastc eq ' ') || ($lastc eq "\t") || ($lastc eq "\n")) {
				}
				else {
					next;
				}
				if(!($eurl eq substr($_,0,$len1))) {
					next;
				}
			}
			elsif(!($eurl eq $_)) {
				next;
			}

			print STDERR "  Ignored, \"$eurl\"\n\tRecord in file <URLS.txt>\n";
			$dup = 1;
			last;
		}
		last if($dup);
	}
	return 2 if($dup);
	return 0;
}

sub hist_add_url {
	push @URL_RECORD,join("\t",@_);
}

sub hist_save {
	if(open FO,">","URLS.txt") {
		print FO join("\n",@URL_RECORD),"\n";
		close FO;
	}
	else {
		print STDERR "Error writing URLS.txt: $!\n";
	}
}
sub _parse_suffix {
	my $url = shift;
	my $suffix = shift;
	return $suffix if(ref $suffix);
	my $r;
	if(!$suffix) {
		if($url =~ m/\.jpg$/) {
			$r = [qw/.mov.3in1.jpg .jpg .1.jpg .2.jpg .p.1.jpg .p.2.jpg/];
		}
		else {
			$r = [qw/\/500k.ts .flv .mov \/500k.mp4/];
		}
	}
	else {
		$r = [split(/\s*,\s*/,$suffix)];
	}
	return $r;
}
sub download_urls {
	my $OPTS = shift;
	my $tasks = shift;
	my $hist = shift(@_) || $OPTS->{history};
	my $overwrite = shift(@_) || $OPTS->{overwrite};
	my $suffix = shift(@_) || $OPTS->{suffix};
	if(!($tasks and @{$tasks})) {
		print STDERR "No tasks to download\n";
		return 1;
	}
	my $idx = 0;
	my $count = scalar(@$tasks);
	use Cwd qw/getcwd/;
	my $PWD = getcwd;
	$PWD =~ s/\/+$//;
	$PWD =~ s/^.*\/([^\/]+\/[^\/]+\/[^\/]+)$/$1/;
	print STDERR "\n$PWD/\n";
	print STDERR "\tGet $count task(s) for download ...\n";
	foreach my $task(@$tasks) {
		$idx++;
		my $prom = "[$idx/$count] ";
		print STDERR $prom;
		if(!$task->[0]) {
			print STDERR "No URL specified for task!\n";
			next;
		}
		my @args = _preprocess($OPTS,$task->[0],$task->[1],$suffix);
		if(@args) {
			my($input,$output) = _download(@args);
			if($input) {
				hist_add_url($input,$output);
			}
			else {
			}
		}
	}
	hist_save() if($hist);
	return 0;
}
our @DOMAINS = (
	['v.weipai.cn','oldvideo.qiniudn.com'],
	['aliv3.weipai.cn', 'aliv.weipai.cn'],
);

sub DUP_URL {
	my $url = shift;
	my @r;
	my $lurl = $url;
	my $prefix;
	my $domain;
	my $suffix;
	if($lurl =~ m/^([a-z]+:\/\/)([^\/]+)(.*)$/) {
		$prefix = $1;
		$domain = lc($2);
		$suffix = $3;
	}
	else {
		return ($url);
	}
	foreach (@DOMAINS) {
		my $match = 0;
		foreach my $d(@$_) {
			if(lc($d) eq $domain) {
				$match = 1;
				last;
			}
		}
		if($match) {
			foreach my $d(@$_) {
				push @r, $prefix . $d . $suffix;
			}
			last;
		}
	}
	if(@r) {
		#	print STDERR "[DUPURL] $url =>\n";
		#print STDERR "\t" . join("\n\t",@r) . "\n";
		return @r;
	}	
	return ($url);
}

sub _preprocess {
	my $OPTS = shift;
	my $url = shift;
	my $basename = shift;
	my $suffix = shift(@_) || $OPTS->{exts};
	my $hist = shift(@_) || $OPTS->{history};
	my $overwrite = shift(@_) || $OPTS->{overwrite};
	my $mtm = $OPTS->{mtm};


	$suffix = _parse_suffix($url,$suffix);

	my $noext = qr/(?:\/500k\.ts|\/500k\.mp4|\.mov\.l\.jpg|\.mov\.3in1\.jpg|\.jpg|\.\d\.jpg|\.mov|\.mp4|\.flv|\.f4v)$/o;

	$url =~ s/$noext//;
	$url =~ s/\/thumbnail\/.*\/video\//\/video\//;

	if(!$basename) {
		$basename = $url;
		$basename =~ s/^.+\/(\d+)\/(\d+)\/(\d+)\/([^\/]+)$/$1$2$3_$4/;
	}
	else {
		$basename =~ s/$noext//;
	}
	if($hist) {
		return undef if(hist_check_url($url,$basename,$suffix));
	}
	else {
		hist_check_url();
	}
	my $exts = {};
	foreach(@$suffix) {
		if(m/(\.[^\.]+)$/) {
			$exts->{$_} = $1;
		}
	}
	if(!$overwrite) {
		my $o_basename = $basename;
		if($basename =~ m/^(\d+)_(.+)$/) {
			my $dstr = $1;
			my $o_name = $2;
			$dstr =~ s/\d\d$//;
			$o_basename = $dstr . '_' . $o_name;
		}
		foreach(keys %$exts,values %$exts) {
			if(-f $basename . $_) {
				print STDERR "  Ignored, File \"$basename" . $_ . "\" exists\n";
				return undef;
			}
			elsif( -f $o_basename . $_) {
				print STDERR "  Ignored, Old file \"$o_basename" . $_ . "\" exists\n";
				return undef;
			}
		}
	}
	if($mtm and -f '.mtm/done.txt' and open FI,'<','.mtm/done.txt') {
		print STDERR "  Checking MTM database <done.txt> ... ";
		my %DONE;
		foreach (<FI>) {
			chomp;
			s/\t.*$//;
			@DONE{(DUP_URL($_))} = (1,1,1,1,1);
		}
		close FI;
		if(%DONE) {
			foreach my $suf(@$suffix) {
				my $ext = $exts->{$suf};
				my $input = $url . $suf;
				if($DONE{$input}) {
					print STDERR "[EXIST]\n  Ignored, url recored in <.mtm/done.txt>\n   $input\n";
					return undef;
				}
			}
		}
		print STDERR "[OK]\n";
	}
	$url =~ s/aliv3\.weipai\.cn/aliv\.weipai\.cn/;
	$url =~ s/oldvideo\.qiniudn\.com/v.weipai.cn/;
	return $url,$basename,$suffix,$exts;
}

sub _download {
	my $url = shift;
	my $basename = shift;
	my $suffix = shift;
	my $exts = shift;
	$DOWNLOADER = $DOWNLOADER || new MyPlace::Program::Download;
	foreach my $suf(@$suffix) {
		my $ext = $exts->{$suf};
		my $input = $url . $suf;
		my $output = $basename . $ext;
		$DOWNLOADER->execute("--url",$input,"--saveas",$output,"--maxtry",4);
		if(-f $output) {
			system('touch','-c','-h','../');
			system('touch','-c','-h','../../');
			return $input,$output;
		}
	}
	return undef;
}

sub download {
	#$OPTS->{history},$OPTS->{overwrite},$OPTS->{exts}
	my $OPTS = shift;
	my @args = _preprocess($OPTS,@_);
	
	if(@args && $args[0]) {
		if($OPTS->{"no-download"}) {
			return MyPlace::Program::EXIT_CODE("UNKNOWN");
		}
		use Cwd qw/getcwd/;
		my $PWD = getcwd;
		$PWD =~ s/\/+$//;
		$PWD =~ s/^.*\/([^\/]+\/[^\/]+\/[^\/]+)$/$1/;
		print STDERR "\n$PWD/";
		my ($input,$output) = _download(@args);
		if($input) {
			&hist_add_url($input,$output);
			&hist_save();

			#SUCCESSED
			return 0;
		}
		else {

			#FAILED;
			return 11;
		}
	}
	else {

		#IGNORED
		return 12;
	}

	#FAILED
	return 11;
}

sub OPTIONS {
	qw/
		help|h|? 
		manual|man
		history|hist
		overwrite|o
		exts:s
		mtm
		no-download
	/;
}

sub USAGE {
	my $self = shift;
	require Pod::Usage;
	Pod::Usage::pod2usage(@_);
	return 0;
}

sub MAIN {
	my $self = shift;
	my $OPTS = shift;
	my @args = @_;
	return download($OPTS,@args);
	#$OPTS->{history},$OPTS->{overwrite},$OPTS->{exts}
	#);
}

return 1 if caller;
my $h = new MyPlace::Weipai::Downloader;
exit $h->execute(@ARGV);

__END__

=pod

=head1  NAME

MyPlace::Weipai::Downloader

=head1  SYNOPSIS

MyPlace::Weipai::Downloader [options...] URL TITLE


=head1  OPTIONS

=over 12

=item B<--history>

Enable tracking history of URL by URLS.txt

=item B<--overwrite>

Overwrite target if file exists

=item B<--exts>

File formats by orders for downloading, e.g. .mov, .mp4, .flv

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

    2014-11-26 00:18  xiaoranzzz  <xiaoranzzz@MyPlace>
        
        * file created.

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@MyPlace>

=cut

#       vim:filetype=perl


