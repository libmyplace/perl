#!/usr/bin/perl -w
package MyPlace::URLRule::Utils;
use strict;
use warnings;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw(
		&get_url
		&url_getinfo
		&url_getbase
		&url_extract
		&url_getname
		&url_getfull
		&get_safename
	);
    @EXPORT_OK      = qw(
		&new_file_data
		&new_json_data &get_url
		&parse_pages &unescape_text
		&get_html &decode_html
		&js_unescape &strnum
		new_html_data &expand_url
		&create_title &extract_text
		&html2text &htmlcontent_to_text
		&parse_html
		&uri_rel2abs
		&get_url_redirect
		&extract_title
		&decode
		&encode
		&from_to
		&create_torrent_title
	);
}
use Encode qw/from_to decode encode/;
use MyPlace::Curl;

my $cookie = $ENV{HOME} . "/.curl_cookies.dat";
#my $cookiejar = $ENV{HOME} . "/.curl_cookies2.dat";
my $curl = MyPlace::Curl->new(
	"location"=>'',
	"silent"=>'',
	"show-error"=>'',
	"cookie"=>$cookie,
	#	"cookie-jar"=>$cookiejar,
#	"retry"=>4,
	"max-time"=>120,
);

#sub from_to {
#	return Encode::from_to(@_);
#}
#sub decode {
#	return Encode::decode(@_);
#}
#sub encode {
#	return Encode::encode(@_);
#}

sub new_html_data {
	my $html = shift;
	my $title = shift;
	my $base = shift;
	my $r = '
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />';
$r = $r . "\n<title>$title</title>" if($title);
$r = $r . "\n<base href=\"$base\"> " if($base);
$r = $r . "\n</head>\n<body>\n" . $html . "\n</body>\n</html>";
$r =~ s/\n/\0/sg;
	return "data://$r\t$title.html";
}

sub new_file_data {
	my $file = shift;
	my $t = join("",@_);
	$t =~ s/\n/\\n/sg;
	return "data://$t\t$file";
}

sub hash2str {
	my %data = @_;
	my $r = "{";
	foreach(keys %data) {
		my $rt = ref $data{$_};
		if(!$rt) {
			$r = $r . "'$_':'$data{$_}',";
		}
		elsif($rt eq 'ARRAY') {
			$r = $r . "'$_':['" . join("','",@{$data{$_}}) . "'],";
		}
		elsif($rt eq 'HASH') {
			$r = $r . "'$_':" . hash2str(%{$data{$_}}) . ","; 
		}
		else {
			$r = $r . "'$_':'$data{$_}',";
		}
	}
	$r .= "};";
	return $r;
}

sub new_json_data {
	my $varname = shift;
	my $filename = shift;
	die "data://$varname = " . hash2str(@_) . "\t$filename.json";
	return "data://$varname = " . hash2str(@_) . "\t$filename.json";
}


sub strnum {
	my $val = shift;
	my $numlen = shift(@_) || 0;
	return $val if($numlen<2);
	return $val if($val >= (10**$numlen));
	my $str = "0"x$numlen . $val;
	return substr($str,length($str) - $numlen);
}
sub js_unescape {
	if(!@_) {
		return;
	}
	elsif(@_ == 1) {
		local $_ = $_[0];
        $_ =~ s/%u([0-9a-f]+)/chr(hex($1))/eig;
        $_ =~ s/%([0-9a-f]{2})/chr(hex($1))/eig;
		return $_;
	}
	else {
		my @r;
		local $_;
		foreach(@_) {
			$_ = js_unescape($_);
			push @r,$_;
	    }
		return @r;
	}
}
sub extract_title {
	my $title = shift;
	return unless($title);
	$title = js_unescape($title);
	$title = decode('utf8',$title);
	$title =~ s/\@微拍小秘书//g;
	$title =~ s/”//g;
	$title =~ s/<[^.>]+>//g;
	$title =~ s/\/\?\*'"//g;
	$title =~ s/&amp;amp;/&/g;
	$title =~ s/&amp;/&/g;
	$title =~ s/&hellip;/…/g;
	$title =~ s/&[^&]+;//g;
#	$title =~ s/\x{1f60f}|\x{1f614}|\x{1f604}//g;
#	$title =~ s/[\P{Print}]+//g;
#	$title =~ s/[^\p{CJK_Unified_Ideographs}\p{ASCII}]//g;
	$title =~ s/[^{\p{Punctuation}\p{CJK_Unified_Ideographs}\p{CJK_SYMBOLS_AND_PUNCTUATION}\p{HALFWIDTH_AND_FULLWIDTH_FORMS}\p{CJK_COMPATIBILITY_FORMS}\p{VERTICAL_FORMS}\p{ASCII}\p{LATIN}\p{CJK_Unified_Ideographs_Extension_A}\p{CJK_Unified_Ideographs_Extension_B}\p{CJK_Unified_Ideographs_Extension_C}\p{CJK_Unified_Ideographs_Extension_D}]//g;
#	$title =~ s/[\p{Block: Emoticons}]//g;
	#print STDERR "\n\n$title=>\n", length($title),"\n\n";
	$title =~ s/\s{2,}/ /g;
	$title =~ s/[\r\n\/\?:\*\>\<\|]+/ /g;
	$title =~ s/_+$//;
	my $maxlen = 70;
	if(length($title) > $maxlen) {
		$title = substr($title,0,$maxlen);
	}	
	$title =~ s/^[-\s]+//;
	$title =~ s/[-\s]+$//;
	return encode('utf8',$title);
}

sub get_url {
	my $url = shift;
	my $verbose = shift(@_) || '-q';
	my $silent;

	my $retry = 4;
	return undef unless($url);

	if(!$verbose) {
	}
	elsif('-q' eq "$verbose") {
		$verbose = undef;
		$silent = 1;
	}
	elsif('-v' eq "$verbose") {
		$verbose = 1;
		$silent = undef;
	}
	else {
		unshift @_,$verbose;
		$verbose = undef;
		$silent = undef;
	}

	my $data;
	my $status;
	print STDERR "[Retriving URL] $url ..." if($verbose);
	while($retry) {
		($status,$data) = $curl->get($url,@_);
		if($status != 0) {
			print STDERR "[Retry " . (5 - $retry) . "][Retriving URL] $url ..." if($verbose);
		}
		else {
			print STDERR "\t[OK]\n" unless($silent);
			last;
		}
		$retry--;
		sleep 3;
	}
	if(wantarray) {
		return $status,$data;
	}
	else {
		return $data;
	}
}
sub decode_html {
	my $html = shift;
	my $charset;
	if($html =~ /(<meta[^>]*http-equiv\s*=\s*"?Content-Type"?[^>]*>)/i) {
		my $meta = $1;
		if($meta =~ m/charset\s*=\s*["']?([^"'><]+)["']?/) {
			$charset = $1;
		}
	}
	return $html unless($charset);
	if($charset =~ m/^[Gg][Bb]\d+/) {
		$charset = "gbk";
	}
#	from_to($html,$charset,'utf-8');
	$html = decode($charset,$html);
	return $html;
}

sub get_html {
	my $url = shift;
	my $html = get_url($url,@_);
	return decode_html($html) if($html);
}

sub extract_pages {
	my $url = shift;
	my $rule = shift;
	my @exps = (
			'<[Aa][^>]*href=[\'"]([^\'"<]*\/list\/[\d\-]+\/index_)(\d+)([^\/"\'<]+)[\'"]',
			'<a href=["\']([^\'"]*\/(?:cn\/index|flei\/index|list\/|part\/|list\/index|list\/\?|cha\/index|html\/part\/index)\d+[-_])(\d+)(\.html?)',
			'<[Aa][^>]*href=[\'"]([^\'"<]*\/[^\/<]+\/index_)(\d+)([^\/"\'<]+)[\'"]',
			'<[Aa][^>]*href=[\'"](index_)(\d+)([^\/"\']+)[\'"]',

		);
	my %r;
	my $html = get_html($url,'-v');
	foreach(@exps) {
		next unless($html =~ m/$_/);
		%r = urlrule_quick_parse(
			"url"=>$url,
			html=>$html,
			'pages_exp'=>$_,
			'pages_map'=>'$2',
			'pages_pre'=>'$1',
			'pages_suf'=>'$3',
		);
		last;
	}
	if(!%r) {
		%r = (
			url=>$url,
			pass_data=>[$url]
		);
	}
	else {
		patch_result($url,\%r,$url);
	}
	return %r;
}


sub parse_pages {
	my %d = @_;
	my $url = $d{source};
	my $html = $d{data};
	my $pages_exp = $d{exp};
	my $pages_start = $d{start};
	my $pages_margin = $d{margin};
	my $pages_map = $d{map};
	my $pages_pre = $d{prefix};
	my $pages_suf = $d{suffix};
	my @pass_data = ($url);
	if($pages_exp) {
		$pages_margin = 1 unless(defined $pages_margin);
		$pages_start = 2 unless(defined $pages_start);
        my $last = 0;
        my $pre = "";
        my $suf = "";
        while($html =~ m/$pages_exp/g) {
			my $this = eval $pages_map;
            if($this > $last) {
                    $last = $this;
                    $pre = eval $pages_pre  if($pages_pre);
                    $suf = eval $pages_suf if($pages_suf);
            }
        }
		$last = $d{limit} if($d{limit} and $d{limit} < $last);
		if($d{error} and $last > $d{error}) {
			return "Too much page [$last] return, something maybe wrong";
		}
		for(my $i = $pages_start;$i<=$last;$i+=$pages_margin) {
			push @pass_data,"$pre$i$suf";
		}
    }
	return \@pass_data;
}

sub unescape_text {
    my %ESCAPE_MAP = (
        "&lt;","<" ,"&gt;",">",
        "&amp;","&" ,"&quot;","\"",
        "&agrave;","à" ,"&Agrave;","à",
        "&acirc;","a" ,"&auml;","?",
        "&Auml;","?" ,"&Acirc;","?",
        "&aring;","?" ,"&Aring;","?",
        "&aelig;","?" ,"&AElig;","?" ,
        "&ccedil;","?" ,"&Ccedil;","?",
        "&eacute;","é" ,"&Eacute;","é" ,
        "&egrave;","è" ,"&Egrave;","è",
        "&ecirc;","ê" ,"&Ecirc;","ê",
        "&euml;","?" ,"&Euml;","?",
        "&iuml;","?" ,"&Iuml;","?",
        "&ocirc;","?" ,"&Ocirc;","?",
        "&ouml;","?" ,"&Ouml;","?",
        "&oslash;","?" ,"&Oslash;","?",
        "&szlig;","?" ,"&ugrave;","ù",
        "&Ugrave;","ù" ,"&ucirc;","?",
        "&Ucirc;","?" ,"&uuml;","ü",
        "&Uuml;","ü" ,"&nbsp;"," ",
        "&copy;","\x{00a9}",
        "&reg;","\x{00ae}",
        "&euro;","\x{20a0}",
    );
    my $text = shift;
    return unless($text);
    foreach (keys %ESCAPE_MAP) {
        $text =~ s/$_/$ESCAPE_MAP{$_}/g;
    }
    $text =~ s/&#(\d+);/chr($1)/eg;
	require URI::Escape;
    $text = URI::Escape::uri_unescape($text);
#    $text =~ s/[_-]+/ /g;
    $text =~ s/[\:]+/, /g;
    $text =~ s/[\\\<\>"\^\&\*\?]+//g;
    $text =~ s/\s{2,}/ /g;
    $text =~ s/(?:^\s+|\s+$)//;
    return $text;
}
sub create_title {
	my $title = shift;
	my $ext = shift;
	$title =~ s/\s*<[^>]+>\s*//g;
	$title = unescape_text($title);
	return unless($title);
	$ext = 0 unless(defined $ext);
	if($ext == 0) {
		$title =~ s/[<>\?*\:\"\|\/\\]+/_/g;
	}
	else {
		$title =~ s/[<>\?*\:\"\|]+/_/g;
	}
	$title =~ s/-|－|【|】|\[|\]|\[|\]|\(|\)|\（|\）|\［|\］/_/g if($ext == 1);
#	$title =~ tr'靠[][]()靠靠'________';
	$title =~ s/[-\s_]*-[-\s_]*/-/g;
	$title =~ s/[-\s_]*_[-\s_]*/_/g;
	$title =~ s/[-\s_]*\s[-\s_]*/ /g;
	$title =~ s/^[\s!*?#~&^+_\-]*//g;
	$title =~ s/[\s!*?#~&^+_\-]*$//g;
	$title =~ s/^\[?www\.\w+\.\w+\]?//;
	$title =~ s/^[-_\s]+//;
	$title =~ s/[-_\s]+$//;
	$title =~ s/\s+/_/g;
	$title =~ s/\s*\[email&#160;protected\]\s*//g;
	return $title;
}

sub get_safename {
	my $title = shift;
	$title = unescape_text($title);
	$title =~ s/[<>\?*\:\"\|\/\\]+/_/g;
	$title =~ s/[-\s_]*-[-\s_]*/-/g;
	$title =~ s/[-\s_]*_[-\s_]*/_/g;
	$title =~ s/[-\s_]*\s[-\s_]*/ /g;
	$title =~ s/^[\s!*?#~&^+_\-]*//g;
	$title =~ s/[\s!*?#~&^+_\-]*$//g;
	$title =~ s/^\[?www\.\w+\.\w+\]?//;
	$title =~ s/^[-_\s]+//;
	$title =~ s/[-_\s]+$//;
	$title =~ s/\s+/_/g;
	$title =~ s/\s*\[email&#160;protected\]\s*//g;
	return $title;
}

sub create_torrent_title {
	my $title = create_title(@_);
	$title =~ s/^\s*[^@]+@[^@]+@\s*//;
	$title =~ s/^(.*?)[\(\[]([A-Za-z]+)[-_](\d+)[\)\]]/$2-$3_$1/;
	return $title;
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
						print STDERR "URL: $url \n => $next\n";
						close FI;
						return $next;
						last;
					}
				}
				close FI;
			}
	return $url;
}

sub extract_text {
	my $sortedKeys = shift;
	my $defs = shift;
	my %in;
	my %done;
	my %r;

		foreach my $k((@$sortedKeys)) {
			next unless(defined $defs->{$k});
			next if($done{$k});
			foreach(@_) {
				if($in{$k} and m/$defs->{$k}->[1]/i) {
					push @{$r{$k}},$_;
					$in{$k} = 0;
					$done{$k} = 1;
					last;
				}
				elsif($in{$k}) {
					push @{$r{$k}},$_;
					next;
				}
				elsif(m/$defs->{$k}->[0]/i) {
					if(!$defs->{$k}->[1]) {
						$r{$k} = $1 ? $1 : $_;
						$done{$k} = 1;
						last;
					}
					$in{$k} = 1;
					push @{$r{$k}},$_;
					next;
				}
			}
		}	
	return %r;
}

sub html2text {
	my @text = @_;
	my @r;
	foreach(@text) {
		next unless($_);
		s/&nbsp;/ /g;
		s/[\r\n]+$//;
		s/<\/?(?:br|div|td)\s*\/?>/###NEWLINE###/gi;
		s/<\/p\s*>/###NEWLINE######NEWLINE###/gi;
		s/\s*<[^>]+>\s*//g;
		s/###NEWLINE###/\n/g;
		s/^\s+//;
		s/\s+$//;
		s/([\r\n]){2,}/$1/g;
		next unless($_);
		push @r,$_;
	}
	if(wantarray) {
		return @r;
	}
	else {
		return join("\n",@r);
	}

}
sub parse_html {
	my $parser_rule = shift;
	return unless($parser_rule);
	return unless(ref $parser_rule);
	return unless(ref $parser_rule eq 'HASH');
	my %PARSER = %$parser_rule;
	my %R;
	my $now;
	my @cached;
	foreach(@_) {
		next if(m/^\s*$/);
		foreach my $k (keys %PARSER) {
			my ($b,$e) = @{$PARSER{$k}};
			if(m/$b/) {
				if($now and @cached) {
					push @{$R{$k}},[@cached];
				}
				$now = $k;
				@cached = ();
			}
			if(m/$e/) {
				if($now) {
					push @{$R{$now}},[@cached,$_];
				}
				$now = undef;
				@cached = ();
			}
		}
		if($now) {
			push @cached,$_;		
		}
	}
	if($now and @cached) {
		push @{$R{$now}},[@cached];
	}
	foreach my $k (keys %PARSER) {
		if($PARSER{$k} and $R{$k}) {
			my ($extractor,$max,$joiner,$to_string) = (
				$PARSER{$k}->[2],
				$PARSER{$k}->[3],
				$PARSER{$k}->[4],
				$PARSER{$k}->[5],
			);
			$extractor ||= 'default';
			$max = $max || scalar(@{$R{$k}}); 
			$joiner = $joiner || '';
			my $cur = 0;
			my @captures = @{$R{$k}};
			my @data;
			my $ext_type = ref $extractor;
			#	print STDERR "Extractor: $ext_type, $extractor\n";

			while(@captures) {
				last if($cur>=$max);
				$cur++;
				my $cols = shift(@captures);
				next unless($cols and @$cols);
				#print STDERR $cur++,"\n";
				my $texts;
				if(!$ext_type) {
					$texts = join($joiner,@$cols);
				}
				elsif($ext_type eq 'GLOB') {
					$texts = join($joiner,&$extractor(@$cols));
				}
				elsif($ext_type eq 'CODE') {
					$texts = join($joiner,&$extractor(@$cols));
				}
				else {
					$texts = join($joiner,@$cols);
				}
				push @data,$texts if($texts);
			}	
			$R{$k} = $to_string ? join("",@data) : \@data;
		}
	}
	return %R;

}
sub htmlcontent_to_text {
	my @text = @_;
	foreach(@text) {
		s/\s*<[^>]+>\s*//g;	
		#print STDERR $_,"\n";
	}
	$_ = join("",@text);
	s/^\s+//;
	s/\s+$//;
	return $_;
}

sub url_extract {
	my $url = shift;
	my $path = $url;
	my $name = $url;
	if($url =~ m/^(.+)\/([^\/]+)$/) {
		$path = "$1/";
		$name = $2;
	}
	elsif($url =~ m/^.+\/([^\/]+)\/$/) {
		$path = $url;
		$name = $1;
	}
	if(wantarray) {
		$name =~ s/[\?#].*//;
		$name =~ s/\+/ /g;
		$name = create_title($name);
		return ($path,$name);
	}
	else {
		return $path;
	}
}
sub url_getbase {
	my $url = shift;
	my $base = $url;
	if($url =~ m/^([^\/]+:\/\/[^\/]+)/) {
		$base = $1;
	}
	return $base;
}

sub url_getinfo {
	my @r;
	push @r,url_getbase(@_);
	push @r,url_extract(@_);
	return @r;
}

sub url_getname {
	my $url = shift;
	my $filename = $url;
	$filename =~ s/[\?#].*$//;
	${filename} =~ s/\/+$//;
	${filename} =~ s/^.*\///;
	${filename} =~ s/\+/ /g;
	${filename} = get_safename(${filename});
	return $filename;
}


sub url_getfull {
	my $leaf = shift;
	my $root = shift;
	if($leaf =~ m/^[^\/]+:/) {
		return $leaf;
	}
	my ($base,$path) = @_;
	$base = url_getbase($root) unless($base);
	$path = url_extract($root) unless($path);
	if($leaf =~ m/^\/\/+/) {
		my $scheme = $root;
		$scheme =~ s/^([^:]+):.*$/$1/;
		return $scheme . ":" . $leaf;
	}
	elsif($leaf =~ m/^\/+/) {
		return $base . $leaf;
	}
	else {
		return $path . $leaf;
	}
}

sub url_rel2abs {
	my $leaf = shift;
	my $root = shift;
	return $leaf unless($root and $leaf);
	return $leaf if($leaf =~ m/^\w+:\/\//);
	return "http:\/\/$leaf" if($leaf =~ m/^www\./);
	$root =~ s/\/[^\/]+$//;
	if($leaf =~ m/^\//) {
		$root =~ s/^(\w+:\/\/[^\/]+).*$/$1/;
		$leaf =~ s/^\/+//;
	}
	return $root . "/" . $leaf;
}
sub get_url_redirect {
	my $url = shift;
	my @postdata = @_;
	my @CURL = qw/curl --silent -D -/;
	my $verbose = 0;
	if(@postdata) {
		foreach(@postdata) {
			if($_ eq '-v' or $_ eq '--verbose') {
				$verbose++;
				next;
			}
			push @CURL,'-d',$_;
		}
	}
	my $error;
	my $rurl;
	push @CURL,'--verbose' if($verbose>1);
	print STDERR "HTTP request sending to $url\n";
	open FI,'-|',@CURL,'--url',$url;
	foreach(<FI>) {
		#print STDERR $_ if($verbose);
		chomp;
		if(m/"why_captcha_detail"[^>]*>([^<]*)</) {
			$error = "需要验证：$1";
			last;
		}
		if(m/^[\s\r\n]*[Ll]ocation:\s*([^\r\n]+)/) {
			$rurl = $1;
			$rurl =~ s/^:?\/\//http:\/\//;
			last;
		}
	}
	close FI;
	if($error) {
		print STDERR "ERROR, $error\n";
	}
	if($verbose) {
		print STDERR "ERROR, No URL redirection\n" unless($rurl);
	}
	return $rurl;
}

1;

__END__
=pod

=head1  NAME

MyPlace::uRLRule::Utils - PERL Module

=head1  SYNOPSIS

use MyPlace::uRLRule::Utils;

=head1  DESCRIPTION

___DESC___

=head1  CHANGELOG

    2012-01-18 23:52  xiaoranzzz  <xiaoranzzz@myplace.hell>
        
        * file created.

=head1  AUTHOR

xiaoranzzz <xiaoranzzz@myplace.hell>


# vim:filetype=perl

