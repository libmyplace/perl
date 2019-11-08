#!/usr/bin/perl -w
use strict;
use warnings;
package MyPlace::Weibo;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw();
    @EXPORT_OK      = qw(m_get_weibo m_get_user m_get_page m_get_data m_check_page m_get_all_page);
}
1;
use MyPlace::JSON;
use Encode qw/find_encoding encode decode/;
use MyPlace::WWW::Utils qw/get_url get_url_wait create_title expand_url html2text strnum/;
use utf8;

#m.weibo.cn/api/container/...

sub m_get_weibo {
	my $oid = shift;
	my $page = shift;
	my $wait = shift;
	my $url = 'https://m.weibo.cn/api/container/getIndex?containerid=230413' . 
			$oid . '_-_WEIBO_SECOND_PROFILE_WEIBO&page_type=03&page=' . $page;
	
	my $html = get_url_wait($wait,$url);
	my $json = MyPlace::JSON::decode_json($html);
	if(!$json) {
		return 0,"Error parsing content";
	}
	if($json->{errno}) {
		my %r =  (error=>"Error $json->{errno}" . ($json->{msg} ? ": $json->{msg}" : ""));
		print STDERR $r{error},"\n";
		return 0,$json->{msg},$json->{errno};
	}
	if((defined $json->{ok}) && $json->{ok} == 0) {
		return 0,"No this page";
	}
	if(!m_check_page($url,$json)) {
		return 0,"NO this page";
	}
	my ($info,@mblogs) = m_extract_blogs($json);
	return 1,@mblogs;
}

sub m_extract_blogs {
	my $json = shift;
	my $info = $json;
	$info = $json->{data} if($json->{data});
	my $cards = $info->{cards} || [];
	foreach(qw/containerid title_top total page/) {
		$info->{$_} = $info->{cardlistInfo}->{$_};
	}
	my $idx = 0;
	my @cards;
	foreach my $card (@$cards) {
		if($card->{card_group}) {
			push @cards,@{$card->{card_group}};
		}
		else {
			push @cards,$card;
		}
	};
	my @mblogs;
	foreach my $card(@cards) {
		if($card->{mblog} && ref $card->{mblog}) {
			#if($card->{mblog}->{retweeted_status}) {
			#	push @mblogs,$card->{mblog}->{retweeted_status};
			#}
			#else {
				push @mblogs,$card->{mblog};
			#}
		}
		elsif($card->{pics}) {
			foreach my $pic(@{$card->{pics}}) {
				my $mblog = $pic;
				if($pic->{mblog}) {
					$mblog = {%$mblog,%{$pic->{mblog}}};
					delete $mblog->{mblog};
				}
				$mblog->{original_pic} = $mblog->{pic_big};
				push @mblogs,$mblog;
			}
		}
	}
	return $info,@mblogs;
}
sub m_get_data {
    my ($url,$rule) = @_;
	$url =~ s/(\d+)u\/(\d+)/$1$2/;
	my $html = get_url($url,"-v");
	my $json = MyPlace::JSON::decode_json($html);
	if(!$json) {
		return (error=>"Error parsing content\n");
	}
	if($json->{errno}) {
		my %r =  (error=>"Error $json->{errno}" . ($json->{msg} ? ": $json->{msg}" : ""));
		print STDERR $r{error},"\n";
		return %r;
	}
	if((defined $json->{ok}) && $json->{ok} == 0) {
		return (error=>"No this page");
	}
    my $title = undef;
	my %dup;
    my @data;
    my @pass_data;
	my ($info,@mblogs) = m_extract_blogs($json);
	my @srcs;
	my $utf8 = find_encoding('utf-8');
	while(@mblogs) {
		my $mblog = shift(@mblogs);
		if(${mblog}->{retweeted_status}) {
			unshift @mblogs,$mblog->{retweeted_status};
		}
		my $picn = 0;
		my $id =  undef;
		my $created = undef;
		my $text = undef;
		$id = $mblog->{id};
		use MyPlace::String::Utils qw/strtime2/;
		$created = strtime2($mblog->{created_at},5);
		if(!$id) {
			$id = $mblog->{scheme};
			$id =~ s/^.*mblogid=([^&"]+).*$/$1/;
		}
		my $orig = $mblog->{original_pic};
		my $mext = ".jpg";
		if($orig) {
			if($orig =~ m/\.([^\.]+)$/) {
				$mext = ".$1";
			}
		}
		my $bpics = $mblog->{pic_ids};
		if($bpics and @{$bpics}) {
			foreach my $bpid (@{$bpics}) {
				push @srcs,'https://ww1.sinaimg.cn/large/' . $bpid . $mext;
			}
		}
		$bpics = $mblog->{pics};
		if($bpics and @{$bpics}) {
			foreach my $bpic(@{$bpics}) {
				next unless($bpic->{large});
				next unless($bpic->{large}->{url});
				push @srcs,$bpic->{large}->{url};
			}
		}
		push @srcs,$orig if($orig);
		$id = $id ? "$id\_" : "";
		$id = $created . "_" . $id if($created);
		if($mblog->{text}) {
			$mblog->{text} = html2text($mblog->{text});
			if(length($mblog->{text})>40) {
				my @lines = split(/\s*[\n\r'";。！\!.；‘‘’？\?]+\s*/,$mblog->{text});
				foreach(@lines) {
					s/\s+//g;
					next unless($_);
					$text = create_title($utf8->encode($_));
					last;
				}
			}
			else {
				$text = create_title($utf8->encode($mblog->{text}));
			}
			if($text) {
				$id = $id . $text;
			}
		}
		if($mblog->{page_info}) {
			my $page = $mblog->{page_info};
			if($page->{type} eq 'video') {
				if($page->{object_id}) {
					push @data,'urlrule:https://video.weibo.com/show?fid=' . $page->{object_id} . "&title=$id";
				}
				if($page->{media_info}) {
					foreach(qw/h265_mp4_hd h265_mp4_ld mp4_hd_url mp4_sd_url stream_url_hd stream_url/) {
						next unless($page->{media_info}->{$_});
						push @data,$page->{media_info}->{$_} . "\t$id.mp4";
					}
				}
			}
			if($page->{page_pic}) {
				push @srcs,$page->{page_pic}->{url};
			}
		}
		my $ndx = 0;
		foreach(@srcs) {
			next unless($_);
			next if($dup{$_});
			s/:\/\/wx(\d+)/:\/\/ww$1/;
			next if($dup{$_});
			if(m/\/([^\/]+)$/) {
				my $img = $1;
				next if($dup{$img});
				$dup{$img} = 1;
				$ndx++;
				my $suf = strnum($ndx,2);
				my $ext = $img;
				$ext =~ s/\.+$//;
				$ext =~ s/.*\./\./;
				if($ndx>1) {
					$ext = "_$suf$ext";
				}
				my $name = $id ? $id . $ext : $img;
				push @data,"$_\t$name";
			}
			else{
				push @data,$_;
			}
			$dup{$_} = 1;
		}
	}
    return (
        count=>scalar(@data),
        data=>\@data,
        base=>$url,
		json=>$json,
    );
}

sub m_check_page {
	my $url = shift;
	my $json = shift;
	if(!$json) {
		my $html = get_url_wait(10,$url);
		$json = decode_json($html);
	}
	return 0 unless($json);

	my $info = {};
	if((defined $json->{ok}) && $json->{ok} == 0) {
		print STDERR "NO [data] for " . $url . "\n";
		return 0;
	}
	$json = $json->{data} if($json->{data});
	foreach(qw/containerid title_top total page since_id/) {
		$info->{$_} = $json->{cardlistInfo}->{$_};
	}
	#if((!$json->{cards}) or (@{$json->{cards}}<1)) {
	#	print STDERR "NO [cards] for " . $url . "\n";
	#	return 0;
	#}
	if($info->{since_id}) {
		return $info->{since_id};
	}
	elsif((!$info->{page}) or ($info->{page} eq "null")) {
		#print STDERR "NO next page for " . $url . "\n";
		return 0;
	}
	elsif($info->{total}) {
		#print "Total: " . $info->{total} . "\n";
		return int($info->{total} / 12)+1;
	}
	else {
		return 1;
	}
}

sub m_get_page {
    my ($url,$rule) = @_;
	$url =~ s/(\d+)u\/(\d+)/$1$2/;
	my %r = m_get_data($url,$rule);
	if($r{error}) {
		return %r;
	}
	my $np;
	if( $r{json} &&
		$r{json}->{data} &&
		$r{json}->{data}->{cardlistInfo} &&
		$r{json}->{data}->{cardlistInfo}->{since_id}
	) {
		my $since_id = $r{json}->{data}->{cardlistInfo}->{since_id};
		$np = $url;
		if($np =~ m/since_id=\d+/) {
			$np =~ s/since_id=\d+/since_id=$since_id/;
		}
		else {
			$np = $np . "&since_id=" . ${since_id};
		}
	}
	elsif(m_check_page($url,$r{json})) {
		$np = $url;
		if($np =~ m/page=(\d+)/) {
			my $i = int($1)+1;
			$np =~ s/page=\d+/page=$i/;
		}
		else {
			$np = $url . "&page=2";
		}
	}
	if($np){
		$r{pass_data} = [$np];
		$r{pass_count} = 1;
		$r{same_level} = 1;
	}
	else {
		print STDERR "No next page found\n";
	}
	delete $r{info};
	$r{wait} = 10;
	return %r;
}

sub m_get_all_page {
	my $url = shift;
	my $pages = m_check_page($url);
	if(!defined $pages) {
		return (error=>"Error parsing content")
	}
	elsif(!$pages) {
		return (error=>"No next pages");
	}
	my $purl = $url;
	$purl =~ s/#[^#]+$//;
	$purl =~ s/page=\d+&?//;
	$purl =~ s/&+$//;
	my @pass_data;
	my $p = $pages;
	if($p<10) {
		$p = 10;
	}
	my $step = int($pages/50);
	$step = 10000 if($pages == 1);
	$step = 20 if($step<20);
	while($step>1) {
		if(!check_url($purl . "&page=" . ($p+$step))) {
			$step = int($step/2);
		}
		else {
			$p = $p + $step;
		}
	}
	for(1 .. $p) {
		push @pass_data,$purl . "&page=" . $_;
	}
    return (
        pass_count=>scalar(@pass_data),
        pass_data=>\@pass_data,
        base=>$url,
		# title=>$title,
    );
}

#https://m.weibo.cn/api/container/getIndex?type=uid&value=2866875962&containerid=1005052866875962
sub m_get_user {
	my $url = shift;
	my $oid;
	foreach(
		qr/m\.weibo\.cn\/(\d+)/,
		qr/weibo\.com\/(\d+)/,
		qr/m\.weibo\.cn\/(?:u|profile)\/(\d+)/,
		qr/weibo\.com\/(?:u|profile)\/(\d+)/,
		qr/containerid=\d\d\d\d\d\d(\d+)/,
		qr/m\.weibo\.cn\/p\/230413(\d+)/,
	) {
		if($url =~ $_) {
			$oid = $1;
			last;
		}
	}
	my $nurl = $url;
	if($oid) {
		$nurl = "https://m.weibo.cn/api/container/getIndex?type=uid&value=" . $oid ."&containerid=100505" . $oid;
	}
	my $html = get_url($nurl);
	my $json = decode_json($html);
	if(!($json && $json->{ok})) {
		return ("error","Parsing page failed");
	}
	$json = $json->{data} if($json->{data});
	$json = $json->{userInfo} if($json->{userInfo});
	my $utf8 = find_encoding('utf-8');
	return (
		uid=>$json->{id},
		profile=> "u/" . $json->{id},
		host=>'weibo.com',
		uname=>$utf8->encode($json->{screen_name}),
		info=>$json,
	);
}

1;
