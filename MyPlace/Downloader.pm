#!/usr/bin/perl -w
package MyPlace::Downloader;
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
use base 'MyPlace::Program';
use MyPlace::Script::Message qw/app_message app_warning app_error/;
use MyPlace::WWW::Utils qw/decode_title strnum/;

my @BLOCKED_URLS = qw{
	www.vxotu.com/u/20200204/19042770.jpg
	www.vxotu.com/u/20200204/19042267.jpg
	s2tu.com/images/2018/03/23/32412e0fffbf91b76a.md.jpg
	sximg.com/u/20200128/22530283.jpg
	sxotu.com/u/20200122/09444911.jpg
	s2tu.com/images/2020/01/23/fghgn2__0464b8a2ff631999.jpg
};
my @BLOCKED_SITES = qw{
	vlook.cn
	i.imgur.com
	wifi588.net
	202.101.235.102
};

my $BLOCKED_EXP = '^https?:(?:\/\/www\.|\/\/)(?:' .
	join('|',map {s/([\.\\\/])/\\$1/rg} @BLOCKED_URLS) . "|" .
	join('|',map {s/([\.\\\/])/\\$1/rg} @BLOCKED_SITES) . 
')'; $BLOCKED_EXP = qr/$BLOCKED_EXP/;
my @TRANS_URLS = (
	['http:((?:\/\/www\.|\/\/)(?:s\d+\.img26\.com|s2tu\.com|s\d+.z2x5c8\.com))','https:$1'],
);


sub OPTIONS {qw/
	help|h|? 
	manual|man
	quiet
	history|hist
	overwrite
	force|f
	touch
	markdone
	no-download
	output|saveas|o=s
	max-time|mt=i
	connect-timeout|ct=i
	max-retry|mr=i
	keep-ts
/;}

my %EXPS = (
	"bdhd"=>'^(bdhd:\/\/.*\|)([^\|]+?)(\|?)$',
	'ed2k'=>'^(ed2k:\/\/\|file\|)([^\|]+)(\|.*)$',
	'http'=>'^(http:\/\/.*\/)([^\/]+)$',
	'qvod'=>'^(qvod:\/\/.*\|)([^\|]+?)(\|?)$',
	'torrent'=>'^torrent:\/\/([A-Za-z0-9]+)\|?(.+)$',
	'magnet'=>'^(magnet:\?[^\t]+)',
);

my %DOWNLOADERS = (
	'Vlook'=>{
		'TEST'=>'^(?:http:\/\/|http:\/\/[^\.]+\.)vlook\.cn\/.*\/qs\/',
	},
	'Weishi'=>{
		'TEST'=>'^http:\/\/[^\.]+\.weishi\.com\/.*downloadVideo\.php',
	},
	'Weibo'=>{
		'TEST'=>'^http:\/\/video\.weibo\.com\/',
	},
	'Xiaoying'=>{
		'TEST'=>'^http:\/\/xiaoying.tv\/v\/',
	},
	'HLS'=>{
		'TEST'=>'^hls:\/\/',
	},
	'Yiqi'=>{
		'TEST'=>'^http:\/\/yiqihdl.*\.flv$',
	}

);

my $MAX_RETRY = 3;
my %RETRIED;
sub FAILED_RETRY {
	my $self = shift;
	my $key = "@_";
	my $retry = $RETRIED{$key} || 0;
	if($retry > $MAX_RETRY) {
		app_error "Failed too much time\n";
		$RETRIED{$key} = 0;
		return $self->EXIT_CODE("FAILED");
	}
	else {
		$retry++;
		$RETRIED{$key} = $retry;
		app_warning "Failed, retring ...\n";
		return $self->EXIT_CODE("RETRY");
	}
}

sub extname {
	my $filename = shift;
	return "" unless($filename);
	if($filename =~ m/\.([^\.\/\|]+)$/) {
		return $1;
	}
	return "";
}

sub normalize {
	local $_ = $_[0];
	if($_) {
		s/[\?\*:\\\/]/ /g;
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
	push @prog,'--hist' if($self->{OPTS}->{'history'});
	push @prog,('--mtm',@_,'--',$url);
	push @prog,$filename if($filename);
	my $r = system(@prog);
	$r = $r>>8 if(($r != 0) and $r != 2);
	return $r;
}

sub save_vlook {
	my $self = shift;
	my $url = shift;
	my $filename = shift;

}

sub expand_url {
	my $url = shift;
			if(open FI,"-|","curl","--silent","--dump-header","/dev/stdout","--",$url) {
				while(<FI>) {
					#print STDERR $_;
					chomp;
					if(m/^\s*<?\s*location\s*:\s*(.+?)\s*$/i) {
						my $next = $1;
						next unless($next =~ m/^http/);
						app_message "URL: $url \n => $next\n";
						close FI;
						return $next;
						last;
					}
				}
				close FI;
			}
	return $url;
}
sub read_m3u8_url {
	my $self = shift;
	my $url = shift;
	my $f_m3u = shift;
	my @opts = @_;
	my $inc_mode;
	if($url =~ m/^(.+)#inc$/) {
		$url = $1;
		$inc_mode = 1;
	}
	my $furl = $url;
	
	if(!-f $f_m3u) {
		$furl = expand_url($url);
	}
	
	my $f_base1 = $furl;
	my $f_base2 = $furl;
	$f_base1 =~ s/^([^\/]+\/\/[^\/]+).*/$1/;
	$f_base2 =~ s/\/[^\/]+$//;

	if(!-f $f_m3u) {
		$self->save_http($furl,$f_m3u,@opts);
		#return undef,undef unless(-f $f_m3u);
	}
	my $FI;
	if(!open $FI,"<:utf8",$f_m3u) {
		app_error "Error opening file $f_m3u: $!\n";
		return;
	}
	my @urls;
	my @m3u8;
	my $idx = 0;
	while(<$FI>) {
		chomp;
		next if(m/^#/);
		s/^\s+//;
		s/\s+$//;
		if(m/^http/) {
		}
		elsif(m/^\/+/) {
			$_ = "$f_base1/$_";
		}
		else {
			$_ = "$f_base2/$_";
		}
		if($_ =~ m/(?:\.m3u8\?|\.m3u8$)/ or ($f_base1 =~ m/ahcdn\.com/ and $_ =~ m/\.mp4$/)) {
			if($inc_mode) {
				$idx++;
				my $fn = $f_m3u;
				$fn =~ s/\.m3u8$/_$idx.m3u8/;
				$fn =~ s/\.m3u8\?.*$/_$idx.m3u8/;
				push @urls,$self->read_m3u8_url($_,$fn,@opts);
			}
			else {
				close $FI;
				unlink $f_m3u;
				return $self->read_m3u8_url($_,$f_m3u,@opts);
			}
		}
		else {
			push @urls,$_;
			last if($inc_mode);
		}
	}
	close $FI;
	unlink $f_m3u;
	return @urls;
}
sub save_m3u8 {
	my ($self,$url,$name,@opts) = @_;
	my $ext;
	my $filename = $name;
	my $referer;
	if(!$filename) {
		if($url =~ m/youku.com\/playlist\/.*[?\&]vid=([^&]+)/) {
			my $web = 'https://v.youku.com/v_show/id_' . $1 . "==.html";
			$referer = $web;
			app_message "Get title from $web ...\n";
			if(open FI,"-|","curl","--silent","--",$web,"--referer",$web) {
				while(<FI>) {
					if(m/property="og:title"[^>]+content="([^"]+)/) {
						$filename = decode_title($1,"utf-8");
						last;
					}
				}
				close FI;
			}
			if($filename) {
				app_message " => " . $filename,"\n";
			}
			else {
				app_message " Failed.\n";
			}
		}
		else {
			$filename = $url;
			$filename =~ s/.*[\/\\]//;
			if($filename =~ m/^(.+)\.([^\.]+)$/) {
				$filename = $1;
				$ext = $2;
			}
		}
	}
	if($filename =~ m/^(.+)\.([^\.]+)$/) {
		$filename = $1;
		$ext = $2;
	}
	else {
		$ext = "ts";
	}
	my $dst = "$filename.$ext";
	if(-f $dst) {
		app_warning "File exists: $dst\n";
		return $self->EXIT_CODE("DONE");
	}
	#ENCRYPTED 加密的
	my @FFMPEG_SITE = (
		'www\.aitis\.space',
		'v\d+\.sanzhuliang\.cc',
		'\d+.lantianxian.org',
		'v\d+.yhcher\.vip',
		'v\d+\.qxkja\.top',
	);
	my $FFMPEG_EXP = '^https?://(?:' . join("|",@FFMPEG_SITE) . ')';
	if($url =~ /$FFMPEG_EXP/) {
		system('ffmpeg','-i',$url,'-c','copy',$dst);
		if(-f $dst) {
			return $self->EXIT_CODE("DONE");
		}
		else {
			return $self->FAILED_RETRY($url,$filename,@opts);
		}
	}
	my $f_m3u = $filename . ".m3u8";
	my @urls = $self->read_m3u8_url($url,$f_m3u,@opts);
	my $idx = 0;
	my $count = @urls;
	my @data;
	my @files;
	my $inc_mode;
	if($count < 1) {
		return $self->FAILED_RETRY($url,$filename,@opts);
	}
	elsif($count == 1) {
		$inc_mode = 1;
		$count = "*";
	}
	while(@urls) {
		my $url1 = shift(@urls);
		$idx++;
		my $try = 0;
		my $output = $filename . '_' .  $idx . '.' . $ext;
		app_message "  [$idx/$count] ";
		while((!-f $output) and $try<3) {
			$self->save_http('save_m3u8',$url1,$output,@opts);
			last if(-f $output);
			app_warning "Try again ...\n";
			$try++;
		}
		if(-f $output) {
			push @files,$output;
		}
		elsif($inc_mode) {
			last;
		}
		else {
			app_error "Download playlist falied\n";
			return $self->FAILED_RETRY($url,$filename,@opts);
		}
		if($inc_mode and $url1 =~ m/^(.+?)(\d+)(\.[^\.]+)$/) {
			my $prefix = $1;
			my $num = $2;
			my $suffix = $3;
			my $l = length($num);
			my $n = $num; 
			$n =~ s/^0+//;
			$n++;
			#last if(scalar(@files)>100);
			push @urls,$prefix . strnum($n,$l) . $suffix;
		}
	}
	if($self->{OPTS}->{'keep-ts'}) {
		app_message "Options 'keep-ts' on, files will not combined!"
	}
	elsif(@files) {
		if(!open FO,">:raw",$dst) { 
			app_error "Error writting $dst : $!\n";
			return $self->EXIT_CODE("ERROR");
		}
		foreach(@files) {
			if(!open FI,"<:raw",$_) {
				app_error "Error reading $_ : $!\n";
				return $self->EXIT_CODE("ERROR");
			}
			print FO <FI>;
			close FI;
		}
		app_message "Playlist saved to : $dst\n";
		close FO;
		unlink @files;
	}
	return $self->EXIT_CODE("DONE");
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
		$self->print_warn("Ignored <$url>\n\tFile exists: $filename\n");
		$self->{LAST_EXIT} = $self->EXIT_CODE("OK");
		return 1;
	}
	else {
		return undef;
	}
}

sub save_http {
	my $self = shift;
	my $from = shift;
	if($from eq 'save_m3u8') {
	}
	else {
		unshift @_,$from;
	}
	my $url = shift;
	my $filename = shift;
	if($url =~ m/:\/\/www.shoplineimg.co/) {
		my @prog = ('wget','--progress','bar','--no-check-certificate',$url);
		if($filename) {
			return 1 if(-f $filename);
			push @prog,"-O",$filename;
		}
		my $r = system(@prog);
		$r = $r>>8 if(($r != 0) and $r != 2);
		return $r;
	}
	my @opts = @_;
	if($url =~ m/(.+)#testing_aria2_rpc$/) {

		$url = $1;
		push @opts,'--program','aria2_rpc';
	}
	elsif($url =~ m/arzon\.jp\//) {
		push @opts,"--quiet","--program","wget","--insecure";
	}
	push @opts,'--url',$url;
	foreach(qw/max-time connect-timeout/) {
		if($self->{OPTS}->{$_}) {
			push @opts,'--' . $_,$self->{OPTS}->{$_};
		}
	}
	if($filename) {
		return $self->{LAST_EXIT} if($self->file_exists($url,$filename));
		push @opts,'--saveas',$filename;
	}
	if($url =~ m{//[^\/]*(?:yximgs|kwai|weibo|weibocdn)\.(?:com|net)/}) {
		#push @opts,'--program','curl';
	}
	elsif($from eq 'save_m3u8') {
	}
	#elsif($filename and $filename =~ m/\.(?:mp4|mpeg|iso|avi)$/i) {
	#	push @opts,'--program','aria2_rpc';
	#}
	if($url =~ m/:\/\/mtl.ttsqgs.com/) {
		push @opts,"--refurl","https://www.meitulu.com/item/12345.html";
	}
	elsif($url =~ m/:\/\/[^.\/]+\.anyhentai\.com/) {
		push @opts,"--refurl","https://japanhub.net/video/123976/icd-17";
	}
	#print STDERR join("","downloader:","download",@opts,"\n");
	my $r = system('download',@opts);
	$r = $r>>8 if(($r != 0) and $r != 2);
#	if(-f $filename) {
#		if($filename =~ m/^(.+)\.(?:ts|mp4|avi|mpeg|flv)$/) {
#			my $basename = $1;
#			my $filetype = `file --mime-type -b "$filename"`;
#			chomp($filetype);
#			if($filetype =~ m/text\/plain|playlist|m3u/i) {				
#				rename $filename,"$basename.m3u8";
#				return $self->save_m3u8($url,$filename,@_);
#			}
#		}
#	}
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
	else {
		print STDERR "$!\n";
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
			local $_ = $EXPS{$p};
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
			local $_ = $EXPS{$p};
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
			local $_ = $EXPS{$p};
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
			local $_ = $EXPS{$p};
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
	$data =~ s/(?:\0|\\n)/\n/g;
	$data =~ s/(?:\\t)/    /g;
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

sub save_urlrule {
	my $self = shift;
	my $url = shift;
	my $title = shift;
	my $ext = "";
	my $exit = 0;
	if($title) {
		
		$self->print_msg("Downloading <$title>\n");
		foreach($title,$title . ".ts") {
			if(-f $_) {
				app_message "$title exists\n";
				return $self->EXIT_CODE("DONE");
			}
		}
		$ext = "";
		if($title =~ m/^(.+)\.([^\.]+)$/) {
			$title = $1;
			$ext = ".$2";
		}
	}
	use MyPlace::URLRule;
	use MyPlace::WWW::Utils qw/url_getfull url_getbase url_extract/;
	my ($status,$info) = MyPlace::URLRule::request($url,{filename=>$title,ext=>$ext});
	if($info->{data}) {
		my $idx = 0;
		my $url_base = url_getbase($url);
		my $url_path = url_extract($url);
		foreach(@{$info->{data}}) {
			$_ = url_getfull($_,$url,$url_base,$url_path);
			if($title and $_ !~ m/(?:    |\t)+/) {
				my ($base,$ext2);
				if(m/^(.+)\.([^\.]+)$/) {
					$base = $1;
					$ext2 = ".$2";
				}
				else {
					$base = $_;
					$ext2 = "";
				}
				if($idx>0) {
					$_ = $_ . "\t" . $title . "_" . strnum($idx,2) . ($ext ? $ext : $ext2);
				}
				else {
					$_ = $_ . "\t" . $title . ($ext ? $ext : $ext2);
				}
			}
			my $r = $self->download($_);
			$exit = $r if($r);
		}
		if(!$self->EXIT_NAME($exit)) {
			$exit = $self->EXIT_CODE("UNKNOWN");
		}
	}
	elsif($info->{error}) {
		app_error "Error: ",$info->{error},"\n";
		if($info->{killme}) {
			app_error "Fantal error, terminating myself...\n";
			return $self->EXIT_CODE("KILLED");
		}
		return $self->EXIT_CODE("ERROR");
	}
	else {
		return $self->EXIT_CODE("FAILED");
	}
	if($title) {
		$title = $title . $ext;
		foreach($title,$title . ".ts") {
			if(-f $_) {
				return $self->EXIT_CODE("DONE");
			}
		}
	}
	return $exit;
}

use Cwd qw/getcwd/;
sub download {
	my $self = shift;
	my @original_args = (@_);
	my $line = shift;
	my @opts = @_;
	$_ = $line;
	my $KWD;
	my $exit;
	#$self->print_msg("DOWNLOAD: $line\n");
	if(!$_) {
		return $self->EXIT_CODE('IGNORED');
	}
	my ($url,$filename,$wd,@append) = split(/(?:    |\t)+/,$_);
	if(index($_,"\t")>1) {
		($url,$filename,$wd,@append) = split(/\t+/,$_);
	}
	if($filename) {
		$filename =~ s/^\s+//;
		$filename =~ s/\s+$//;
		$filename =~ s/[\/\\]+$//;
		$filename =~ s/\s+$//;
		if(-d $filename) {
			my $base = $filename;
			$base =~ s/.*\///;
			$base = $filename unless($base);
			$filename = $filename . "/"  . $base;
		}
	}
	if($wd) {
		if($wd =~ m/^-/) {
			unshift @append,$wd;
			$wd = undef;
		}
		else {

		}
		$KWD = getcwd();
	}
	elsif($filename and $filename =~ m/[\/\\]+/) {
			my @dirs = split(/[\/\\]+/,$filename);
			my $cur = "";
			pop @dirs;
			foreach(@dirs) {
				$cur = $cur . $_;
				if(!-d $cur) {
					if(mkdir $cur) {
						app_message "Create directory $cur\n";
					}
					else {
						app_message "Create directory $cur FAILED\n";
						last;
					}
				}
			}
	}
	#$filename =~ s/.*[\/\\]+// if($filename);
	if($wd) {
		mkdir $wd unless(-d $wd);
		if(!chdir $wd) {
			app_error "Error change directory: $wd!\n";
			return $self->EXIT_CODE("ERROR");
		}
		else {
			$self->print_msg("Change directory: $wd\n");
			if($self->{mtm}) {
				$self->{saved_prompt} = $self->{mtm}->get_prompt;
				$self->{mtm}->set_prompt($self->{saved_prompt} . ":" . $wd);
			}
		}
	}
	if(-f "files.lst" and open FI,'<',"files.lst") {
		foreach(<FI>) {
			chomp;
			if($_ eq $filename) {
				close FI;
				app_message "Ignored: \"$filename\" in FILES.LST\n"; 
				return $self->EXIT_CODE("IGNORED");
			}
		}
		close FI;
	}
	if($self->{OPTS}->{touch}) {
		$self->print_msg("[Touch] $filename\n");
		system("touch","--",$filename);
		$exit = $self->EXIT_CODE("DEBUG");
	}
	elsif($filename and $self->{OPTS}->{markdone}) {
		if(-f $filename) {
			$self->print_msg("[Mark done] $filename\n");
			$exit = $self->EXIT_CODE("DONE");
		}
		elsif($self->{OPTS}->{force}) {
			$self->print_msg("[FORCE Mark done] $filename\n");
			$exit = $self->EXIT_CODE("DONE");
		}
		else {
			$self->print_msg("[Not exists] $filename\n");
			$exit = $self->EXIT_CODE("UNKNOWN");
		}
	}

	$MAX_RETRY = $self->{OPTS}->{"max-retry"} if(defined $self->{OPTS}->{"max-retry"});
	foreach my $dld(keys %DOWNLOADERS) {
		if(m/$DOWNLOADERS{$dld}->{'TEST'}/) {
			my @args;
			push @args,$1 if($1);
			push @args,$2 if($2);
			push @args,$3 if($3);
			push @args,$4 if($4);
			my $package = $DOWNLOADERS{$dld}->{PACKAGE} || ('MyPlace::Downloader::' . ($DOWNLOADERS{$dld}->{NAME} || $dld));
#			app_message "Downloader> import downloader [$dld <$package>]\n";
			eval "require $package;";
			app_message "$@\n" if($@);
			my $dl = bless {OPTS=>$self->{OPTS}},$package;
			$exit = $dl->download($_,@args);
			last;
		}
	}
	
	$_ = $url;
	foreach my $t (@TRANS_URLS) {
		eval("\$_ =~ s/$t->[0]/$t->[1]/g;");
	}
	if(defined $exit) {
	}
	elsif(!$_) {
		$exit = 1;
	}
	elsif($_ =~ $BLOCKED_EXP) {
		app_warning "\nIgnored, url blocked: $_\n";
		$exit = $self->EXIT_CODE("ERROR");
	}
	elsif(m/^urlrule:(.+)$/) {
		$exit = $self->save_urlrule($1,$filename,@append);
	}
	elsif(m/^post:\/\/(.+)$/) {
		$exit = $self->save_http_post($1,$filename,@append);
	}
	elsif(m/^qvod:(.+)$/) {
		$exit = $self->save_qvod($1,$filename,@append);
	}
	elsif(m/^bdhd:(.+)$/) {
		$exit = $self->save_bdhd($1,$filename,@append);
	}
	elsif(m/^(ed2k:\/\/.+)$/) {
		$exit = $self->save_bhdh($1,$filename,@append);
	}
	elsif(m/^http:\/\/[^\/]*(?:weipai\.cn|oldvideo\.qiniudn\.com)\/.*/) {
		$exit = $self->save_weipai($_,$filename,@append);
	}
	#https://pl.dfdkmj.com//20181102/bpz5ojNu/1435kb/hls/index.m3u8
	elsif(m/youku\.com\/playlist\//) {
		$exit = $self->save_m3u8($_,$filename,@append);
	}
	elsif(m/^m3u8:(.+)/) {
		$exit = $self->save_m3u8($1,$filename,@append);
	}
	elsif(m/\.m3u8$|\.m3u8\t|\.m3u8[#\?]/) {
		$exit = $self->save_m3u8($url,$filename,@append);
	}
	elsif(m/^(https?:\/\/.+)$/) {
		$exit = $self->save_http($1,$filename,@append);
	}
	elsif(m/^:?(\/\/.+)$/) {
		$exit = $self->save_http("http:$1",$filename,@append);
	}
	elsif(m/^file:\/\/(.+)$/) {
		$exit = $self->save_file($1,$filename,@append);
	}
	elsif(m/^data:\/\/(.+)$/) {
		$exit = $self->save_data($1,$filename,@append);
	}
	elsif(m/$EXPS{torrent}/) {
		$exit = $self->save_torrent($1,$filename,@append);
	}
	elsif(m/$EXPS{magnet}/) {
		##$exit = $self->save_torrent($1,$filename,@append);
		$exit = $self->EXIT_CODE("IGNORED");
	}
	else {
		$self->print_err("Error: URL not supported [$_]\n");
		$exit = $self->EXIT_CODE("ERROR");
	}
	if($KWD) {
		$self->{mtm}->set_prompt($self->{saved_prompt}) if($self->{mtm});
		chdir $KWD;
	}
	if($exit == $self->EXIT_CODE("RETRY")) {
		return $self->download(@original_args);
	}
	return $exit;
}


 

sub MAIN {
	my $self = shift;
	my $OPTS = shift;
	$self->{OPTS} = $OPTS;
	my @lines = @_;
	if(!@lines) {
		while(<STDIN>) {
			chomp;
			push @lines,$_;
		}
	}
	if((scalar(@lines) == 1) and $self->{OPTS}->{output}) {
		$lines[0] .= "\t" . $self->{OPTS}->{output};
	}
	$MAX_RETRY = $self->{OPTS}->{"max-retry"} if(defined $self->{OPTS}->{"max-retry"});
	my $exit;
	foreach my $bfile(qw{blacklist.lst ../blacklist.lst}) {
		next unless(-f $bfile);
		my @text;
		open FI,"<".$bfile or next;
		while(<FI>) {
			chomp;
			s/^\s+//;
			s/\s+$//;
			next unless($_);
			push @text,$_;
		}
		close FI;
		my $exp = join("|",@text);
		if($exp) {
			app_message "Read blacklist from $bfile: " . scalar(@text) . " rules.\n";
			$BLOCKED_EXP .= "|" . $exp;
		}
	}
	foreach my $url (@lines) {
		if($url =~ m/^#([^:]+?)\s*:\s*(.*)$/) {
			$self->{source}->{$1} = $2;
			next;
		}
		my $r = $self->download($url);
		if($self->EXIT_NAME($r)) {
			$exit = $r;
		}
		else {
			$exit = $self->EXIT_CODE("UNKNOWN");
		}
		if($exit eq $self->EXIT_CODE("KILLED")) {
			last;
		}
	}
	return $exit;
}

return 1 if caller;
my $PROGRAM = new MyPlace::Downloader;
exit $PROGRAM->execute(@ARGV);

