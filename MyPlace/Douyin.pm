#!/usr/bin/perl -w
package MyPlace::Douyin;
use strict;
use warnings;
use MyPlace::Curl;
use MyPlace::WWW::Utils qw/extract_title/;
use MyPlace::String::Utils qw/from_xdigit/;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw();
    @EXPORT_OK      = qw(expand_url get_item get_posts_from_url get_url get_info get_posts get_amemv_api get_favs);
}
use utf8;
my $private_curl;
#my $cookie = $ENV{HOME} . "/.curl_cookies.dat";
sub get_curl {
	if(not $private_curl) {
		$private_curl = MyPlace::Curl->new(
			'user-agent'=>'Mozilla/5.0 (Android 9.0; Mobile; rv:61.0) Gecko/61.0 Firefox/61.0',
			"location"=>'',
			"silent"=>'',
			"show-error"=>'',
			#"cookie"=>$cookie,
			"max-time"=>180,
			#"progress-bar"=>'',
		);
	}
	return $private_curl;
}
sub get_url {
	my $c = &get_curl;
	my $url = shift;
	print STDERR "[Retriving] $url ..\n";
	my ($ok,$data) = $c->get($url,@_);
	return $data;
}

sub expand_url {
	goto &MyPlace::WWW::Utils::expand_url;
}
#https://www.iesdouyin.com/aweme/v1/aweme/post/?user_id=102673338020&count=21&max_cursor=0&aid=1128&_signature=txNgexAf7JgXgrtArv3yKbcTYG&dytk=f80db17895af6fc4615fa0e1176b2e34

my %p_id_maps = (
	user=>"uid",
	user_id=>"uid",
	userName=>"uname",
	#	authorName=>"uname",
	user_name=>"uname",
	"user-info-id"=>"dyid",
	"user-info-name"=>"uname",
	nickname=>"uname",
	shortid=>"dyid",
);

use Encode qw/find_encoding/;
my $utf8 = find_encoding("utf-8");

sub get_info {
	my $url = shift;
	my %i;
	if($url =~ m{v\.douyin\.com}) {
		$url = expand_url($url);
	}
	if($url =~ m{/v\d+/aweme/post}) {
		%i = get_info_from_posts($url,@_);
	}
	else {
		my $html = get_url($url,@_);
		while($html =~ m/\s+([^'"\s:]+):\s*['"]([^'"]+)['"]/g) {
			$i{$1} = $2;
		}
		while($url =~ m/(?:\/([^\/]+)\/|[&\?]([^&\?=]+)=)(\d+)/g) {
			$1 ? $i{$1} = $3 : $i{$2} = $3;
		}
		while($html =~ m/<(p|span)[^>]+class="(user-[^"]+|nickname|shortid|signature|location)"[^>]*>(.+?)<\/(\1)>/g) {
			my $k = $2;
			my $v = $3;
			$v =~ s/\s+//g;
			$v =~ s/<[^>]+>//g;
			$i{$k} = $v;
		}
		if($html =~ m/<img[^>]+class="avatar[^>]+src="([^"]+)/) {
			$i{avatar} = $1;
		}
		if($html =~ m/<video[^>]+src="([^"]+)/) {
			$i{video} = $1;
		}
		if($html =~ m/<inpu[^>]+value="([^"]+\/large\/[^\/]+\.jpg)/) {
			push @{$i{images}},$1;
		}
		if($i{dyid}) {
			$i{dyid} = &from_xdigit($i{dyid});
		}
		$i{posts} = {%i};
	}
	foreach(keys %p_id_maps) {
		my $id = $p_id_maps{$_};
		next unless($i{$_});
		if(not $i{$id}) {
			$i{$id} = $i{$_};
		}
		delete $i{$_};
	}
	foreach(qw/uname dyid/) {
		next unless($i{$_});
		$i{$_} =~ s/\s+//g;
		$i{$_} =~ s/^\@//;
		$i{$_} = &extract_title($i{$_});
		$i{$_} =~ s/\s+//g;
		$i{$_} =~ s/^\@//;
		$i{$_} = $utf8->decode($i{$_});
	}
	$i{dyid} =~ s/^\s*抖音ID：// if($i{dyid});
	$i{dyid} =~ s/^\s*抖音ID// if($i{dyid});
	if($i{uname} and length($i{uname})<2) {
		$i{uname} = $i{uname} . "_" . $i{dyid} if($i{dyid});
	}
	foreach(qw/uname dyid/) {
		next unless($i{$_});
		$i{$_} = $utf8->encode($i{$_});
	}
	$i{host} = "douyin.com";
	$i{profile} = $i{uid};
	$i{user_id} = $i{uid};
	$i{aweme_id} = $i{itemId};
	$i{uname} = $i{uname} || $i{dyid} || $i{uid};
	$i{id2} = $i{dyid};
	
	return %i;
}
sub get_info_from_posts {
	my $url = shift;
	my %i = get_posts_from_url($url,@_);
	$i{host} = "douyin.com";
	$i{user_id} = $i{uid} if($i{uid});
	$i{profile} = $i{user_id};
	$i{aweme_id} = $i{itemId} if($i{itemId});
	$i{uname} = $i{uname} || $i{dyid} || $i{uid};
	$i{id2} = $i{dyid};
	$i{posts_url} = $url;
	return %i;	
}

sub get_amemv_api {
	my %p;
	my $type = shift;
	$p{user_id} = shift(@_) || "";
	$p{dytk} = shift(@_) || "";
	$p{max_cursor} = shift(@_) || 0;
	$p{count} = shift(@_) || 21;
	#my $base = "https://www.amemv.com/aweme/v1/aweme/$type/?";
	#my $base = "https://crawldata.app/api/douyin/v1/aweme/$type?";
	my $base = "https://jokeai.zongcaihao.com/douyin/v292/aweme/$type?";
	#post?user_id=83774364341&max_cursor=0&count=20
	my @params;
	foreach my $k(keys %p) {
		push @params,"$k=$p{$k}";
	}
	return $base . join("&",@params);
}

sub get_posts {
	#https://www.iesdouyin.com/aweme/v1/aweme/post/?user_id=102673338020&count=21&max_cursor=0&aid=1128&_signature=wohv9RAcmRpiGbTO5.81UMKIb-&dytk=f80db17895af6fc4615fa0e1176b2e34	
	return get_posts_from_url(get_amemv_api("post",@_));
}
sub get_favs {
	#https://www.amemv.com/aweme/v1/aweme/favorite/?user_id=102673338020&count=21&aid=1128&_signature=wohv9RAcmRpiGbTO5.81UMKIb-&dytk=f80db17895af6fc4615fa0e1176b2e34	
	return get_posts_from_url(get_amemv_api("favorite",@_));
}

use JSON qw/decode_json/;
sub safe_decode_json {
	my $json = eval { decode_json($_[0]); };
	if($@) {
		#die(join("\n",@_,$@),"\n");
		print STDERR "Error deocding JSON text:$@\n";
		print STDERR @_,"\n";
		$@ = undef;
		return {};
	}
	else {
		if($json->{reason}) {
			print STDERR "Error: " . $json->{reason},"\n";
		}
		return $json;
	}
}

#_signature
#https://www.iesdouyin.com/web/api/v2/aweme/post/?sec_uid=MS4wLjABAAAAomzoF_WEZi9H_BZ-4dRW5qoRQCbPH62zsvqH-FA7WwCbaI1poAkMmzBUaxp03ktq&count=21&max_cursor=0&aid=1128&_signature=j61rtwAA79rJkDQn2NE-O4-ta6&dytk=
sub get_posts_from_url {
	my $url = shift;
	my $html = get_url($url);
	my $json = safe_decode_json($html);
	if(!$json->{min_cursor}) {
		return (
			error=>"Error decoding JSON text",
		);
	}
	#use Data::Dumper;
	#print STDERR Data::Dumper->Dump([$json->{data}->{aweme_list}->[0]],["\$json"]),"\n";
	my %info;
	if($url =~ m/user_id=(\d+)/) {
		$info{uid} = "$1";
	}
	return %info unless($json->{aweme_list});
	foreach(qw/min_cursor max_cursor has_more/) {
		$info{$_} = $json->{$_};
	}
	my @posts = @{$json->{aweme_list}};
	foreach my $P (@posts) {
		my %v = ();
		foreach my $k (qw/desc author_user_id aweme_id create_time/) {
			$v{$k} = $P->{$k} if($P->{$k});
			$v{$k} = $P->{video}->{$k} if($P->{video}->{$k});
		}
		if($v{desc}) {
			$v{desc} = $utf8->encode($v{desc});
		}
		if($P->{author} and $P->{author}->{uid}) {
			$info{uid} = $P->{author}->{uid};
			$info{uname} = $P->{author}->{nickname};
			$info{dyid} = $P->{author}->{unique_id};
		}
		local $_ = $P->{video};
		foreach my $k (qw/origin_cover cover_hd cover_large cover_medium cover_thumb cover/) {
			if($_->{$k} and $_->{$k}->{url_list}) {
				foreach my $u (@{$_->{$k}->{url_list}}) {
					push @{$v{images}},$u;
				}
				last;
			}
		}
		foreach my $k (qw/play_addr play_addr_lowbr download_addr/) {
			next unless($_->{$k});
			my $u = $_->{$k}->{url_list};
			if($u) {
				$v{video} = $u->[0];
				last;
			}
		}
		push @{$info{posts}},\%v;
	}
	if($info{uname}) {
		$info{uname} = $utf8->encode($info{uname});
	}
	return %info;
}


sub get_item {
	my $url = shift;
	#https://v.douyin.com/eY8pDeD
	if($url =~ m/\/v\.douyin\.com\//) {
		$url = expand_url($url);
		if($url =~ m/\/video\/(\d+)/) {
			$url = 'https://www.iesdouyin.com/web/api/v2/aweme/iteminfo/?item_ids=' . $1;
		}
	}
	#https://www.iesdouyin.com/web/api/v2/aweme/iteminfo/?item_ids=6941305602861796638
	my $html = get_url($url);
	my $json = safe_decode_json($html);
	if(	
		$json and
		(defined $json->{status_code}) and
		($json->{status_code} eq 0) and
		$json->{item_list}
	) {
		my $video = $json->{item_list}->[0];
		if($video->{author}) {
			$video->{uid} = $video->{author}->{uid};
		}
		if($video->{video}) {
			my $v = $video->{video};
			foreach(qw/cover origin_cover dynamic_cover/) {
				if($v->{$_} and $v->{$_}->{url_list}) {
					$video->{images} = $v->{$_}->{url_list};
					last;
				}
			}
			$video->{video} = undef;
			foreach my $k (qw/play_addr play_addr_lowbr download_addr/) {
				if($v->{$k} and $v->{$k}->{url_list}) {
					$video->{video} = $v->{$k}->{url_list}->[0];
					$video->{video} =~ s/\/playwm\//\/play\//;
					last;
				}
			}
			
		}
		return (
			%$video,	
			posts=>[$video],
		);
	}
	return (error=>"JSON error paring page");
}
1;
__END__
