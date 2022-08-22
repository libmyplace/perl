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
    @EXPORT_OK      = qw(m_get_weibo m_get_user m_get_page m_get_data m_get_mblog m_check_page m_get_all_page extract_post_title m_get_object m_get_info);
}
1;
use MyPlace::JSON;
use Encode qw/find_encoding encode decode/;
use MyPlace::WWW::Utils qw/get_url get_url_wait create_title expand_url html2text strnum/;
use utf8;

#m.weibo.cn/api/container/...

sub get_json_url {
	my $url = shift;
	my $wait = shift;
	my $html = get_url_wait($wait,$url);
	my $json = MyPlace::JSON::decode_json($html);
	#use Data::Dumper;print Dumper($json),"\n";
	#die();
	if(!$json) {
		return 0,"Error parsing content";
	}
	if($json->{errno}) {
		my %r =  (error=>"Error $json->{errno}" . ($json->{msg} ? ": $json->{msg}" : ""));
		print STDERR $r{error},"\n";
		return 0,$json->{msg},$json->{errno};
	}
	if((defined $json->{ok}) && ($json->{ok} == 0)) {
		return 0,"No this page";
	}
	if((defined $json->{code})) {
		if($json->{code} == 100000) {
			return 1,$json;
		}
		else {
			return 0,$json->{msg},$json->{code};
		}
	}
	return 1,$json;	
}

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
	if((defined $json->{ok}) && ($json->{ok} == 0)) {
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
				$mblog->{original_pic} = ($mblog->{pic_big} || $mblog->{pic_ori});
				push @mblogs,$mblog;
			}
		}
	}
	return $info,@mblogs;
}
sub extract_post_title {
	my $text = shift;
	my $decode = shift;
	my $utf8 = find_encoding('utf-8');
	my $limits = 80;
	$text = $utf8->decode($text) if($decode);
	$text =~ s/https?:\/\/[^\s]+//;
	$text =~ s/\s+//g;
	if($text =~ m/\\n/ or length(${text})>$limits) {
		$text =~ s/\\n/\n/g;
		my @lines = split(/\s*[\n\r'";。…！\!.；‘‘’？\?]+\s*/,${text});
		foreach(@lines) {
			next unless($_);
			if(length($_)>$limits) {
				my @p = split(/\s*[，－,、'~_-]+\s*/,$_);
				$_ = shift(@p);
				foreach my $p(@p) {
					$p = $_ . "_" . $p;
					last if(length($p)>$limits);
					$_ = $p;
				}
				$_ = substr($_,0,$limits) if(length($_)>$limits)
			}
			$text = create_title($utf8->encode($_));
			last;
		}
	}
	else {
		$text = create_title($utf8->encode(${text}));
	}
	return $text;
}

sub m_get_mblog {
	my $url = shift;
	if(index($url,'/')<0) {
		$url = 'https://m.weibo.cn/detail/' . $url;
	}
	my $html = get_url($url,"-v");
	$html =~ s/[\n\r]//g;
	my $json;
	if($html =~ m/\$render_data\s*=\s*\[\{(.+)\}\]\[0\]/) {
		$json = MyPlace::JSON::decode_json('{' . $1 . '}');
		if($json->{status}) {
			my ($id,@data) = m_extract_mblog($json->{status});
			if(@data) {
				return (
					json=>$json->{status},
					data=>\@data,
					count=>scalar(@data),
				);
			}
		}
	}
	return (
		'error'=>'Decode page failed',
	);
}
sub m_extract_mblog {
	my $mblog = shift;
	my $no_video = shift;
	my $photoall = shift;
	my @data;
	my %dup;
	my @srcs;
	my $picn = 0;
	my $id =  undef;
	my $created = undef;
	my $text = undef;
	my $utf8 = find_encoding('utf-8');
	if($photoall) {
		my $filename;
		if($mblog->{id} and $mblog->{pic_id}) {
			$filename = $mblog->{id} . "_" . $mblog->{pic_id};
		}
		elsif($mblog->{id}) {
			$filename=  $mblog->{id};
		}
		elsif($mblog->{pic_id}) {
			$filename = $mblog->{pic_id};
		}
		if($mblog->{text}) {
			$text = extract_post_title($mblog->{text});
			$filename = $filename ? $filename . "_" . $text : $text;
		}
		my $url;
		foreach(qw/original_pic pic_ori pic_big pic_mw2000/) {
			if($mblog->{$_}) {
				$url = $mblog->{$_};
				last;
			}
		}
		if($url) {
			if(!$filename) {
				return $url,$url;
			}
			elsif($url =~ m/\.([^\.]+)$/) {
				return $filename,$url . "\t" . $filename . ".$1";
			}
			else {
				return $filename,$url;
			}
		}
		return undef;
	}
	if(${mblog}->{retweeted_status}) {
		return m_extract_mblog($mblog->{retweeted_status},$no_video,$photoall);
	}
	$id = $mblog->{id};
	use MyPlace::String::Utils qw/strtime2/;
	$created = strtime2($mblog->{created_at},5);
	if(!$id) {
		$id = $mblog->{scheme};
		if($id) {
			$id =~ s/^.*mblogid=([^&"]+).*$/$1/;
		}
	}
	my $orig = $mblog->{original_pic};
	my $mext = ".jpg";
	if($orig) {
		if($orig =~ m/\.([^\.]+)$/) {
			$mext = ".$1";
		}
		push @srcs,$orig;
	}
	my $bpics = $mblog->{pic_ids};
	my $rt = ref $bpics;
	if($bpics and ($rt eq "ARRAY")) {
		foreach my $bpid (@{$bpics}) {
			push @srcs,'https://ww1.sinaimg.cn/large/' . $bpid . $mext;
		}
	}
	$bpics = $mblog->{pics};
	$rt = ref $bpics;
	if($bpics and ($rt eq 'ARRAY')) {
		foreach my $bpic(@{$bpics}) {
			next unless($bpic->{large});
			next unless($bpic->{large}->{url});
			push @srcs,$bpic->{large}->{url};
		}
	}
	$id = $id || "";
	my $id_text = $id ? $id . "_" : "";
	$id_text = $created . "_" . $id_text if($created);
	if($mblog->{text}) {
		$mblog->{text} = html2text($mblog->{text});
		$text = extract_post_title($mblog->{text});
	}
	if($mblog->{page_info}) {
		my $page = $mblog->{page_info};
		foreach(qw/content2 content1 page_title title/) {
			if($page->{$_}) {
				$text = extract_post_title($page->{$_});
				last if($text);
			}
		}
		my $filename = $text ? ($id_text . $text) : $id_text;
		if((!$no_video)) {
			if($page->{type} eq 'video') {
				my $video_ok = undef;
				my %a = %{$page->{media_info}} if($page->{media_info});
				%a = (%{$page->{urls}},%a) if($page->{urls});
				foreach("_1080p","_720p","_hd","","_ld") {
					foreach my $pret(qw/h265 h265_mp4 mp4 stream dash/) {
						foreach my $suft("","_mp4","_url") {
							my $vt = $pret . $_ . $suft;
							#print STDERR $vt,"\n";
							next unless($a{$vt});
							push @data,$a{$vt} . "\t$filename.mp4";
							$video_ok = 1;
						}
					}
				}
				if((!$video_ok) and $page->{object_id}) {

					my $dash_url = 'https://weibo.com/aj/video/getdashinfo?ajwvr=6&media_ids='
						. $page->{object_id} . '&__rnd=' . scalar(time) 
						. '&display=0&retcode=6102';

					my ($dash_ok,$dash) = get_json_url($dash_url);
					if($dash_ok) {
						print STDERR "\tJSON ok\n";
						my $dash_data = $dash->{data};	
						my $rt = ref $dash_data;
						if($rt and ($rt eq 'HASH') and $dash_data->{list} && $dash_data->{list}->[0]) {
							my $dash_list = $dash_data->{list}->[0]->{details};
							foreach my $dash_item(@$dash_list) {
								next unless($dash_item->{play_info});
								if($dash_item->{play_info}->{mime} and $dash_item->{play_info}->{mime} =~ /audio/) {
								next;
								}
								push @data,$dash_item->{play_info}->{url} . "\t$filename.mp4" ;
								$video_ok = 1;
							}
						}
						else {
							print STDERR "\t[getdashinfo return empty\n";
						}
					}
					else {
						print STDERR "\tJSON error\n";
					}
				}
			}
			else {
				my %info = m_get_object($page->{page_url});
				if($info{object} && $info{object}->{media}) {
					foreach(@{$info{object}->{media}}) {
						if(m/\.(?:jpg|gif|png|jpeg)$/) {
							push @srcs,$_;
						}
						else {
							push @data,$_ . "\t$filename.mp4";
						}
					}
				}
			}
		}
		foreach(qw/page_pic slide_cover/) {
			if($page->{$_}) {
				if((ref $page->{$_}) eq 'ARRAY') {
					foreach(@{$page->{$_}}) {
						push @srcs,$_->{url} || $_->{pic};
					}
				}
				else {
					push @srcs,($page->{$_}->{url} || $page->{$_}->{pic});
				}
			}
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
			$ext =~ s/\?.*$//;
			if($ndx>1) {
				$ext = "_$suf$ext";
			}
			my $name = $text ? ($id_text . $text . $ext) : ($id_text . $img);
			push @data,"$_\t$name";
		}
		else{
			push @data,$_;
		}
		$dup{$_} = 1;
	}
	return ($text ? $id_text . $text : $id_text),@data;
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
	#use Data::Dumper;die(Data::Dumper::Dumper([$json]));
	if((defined $json->{ok}) and ($json->{ok} == 0)) {
		return (error=>"No this page");
	}
	if($url =~ m/_-_(?:photoall|photolike)/) {
		$json->{photoall} = 1;
	}
    my @data;
	my ($info,@mblogs) = m_extract_blogs($json);
	while(@mblogs) {
		my $mblog = shift(@mblogs);
		if(${mblog}->{retweeted_status}) {
			unshift @mblogs,$mblog->{retweeted_status};
			delete $mblog->{retweeted_status};
		}
		my($id,@downloads) = m_extract_mblog($mblog,1,$json->{photoall});
		next unless(defined $id);
		if($mblog->{page_info}) {
			my $page = $mblog->{page_info};
			if(($page->{type} eq 'video') || ($page->{type} eq 'story') || ($page->{type} eq 'webpage')) {
				my $mid = $mblog->{mid} || $mblog->{id};
				if($mid) {
					push @data,"urlrule:https://m.weibo.cn/detail/$mid\t$id.mp4";
				}
				elsif($page->{object_id}) {
					push @data,'urlrule:https://video.weibo.com/show?fid=' . $page->{object_id} . "&title=$id";
				}
				elsif($page->{page_url}) {
					push @data,'urlrule:' . $page->{page_url};
				}
			}
		}
		push @data,@downloads;
	}
    return (
        count=>scalar(@data),
        data=>\@data,
        base=>$url,
		json=>$json,
    );
}

sub m_get_object {
	my $object = shift;
	$object =~ s/^.*[&\?](?:object_id|fid)=([^&]+).*$/$1/;
	my $url = 'https://m.weibo.cn/s/video/object?object_id=' . $object;
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
	if((defined $json->{ok}) && ($json->{ok} == 0)) {
		return (error=>"No this page");
	}
	return (error=>"No data found") if(!$json->{data});
	return (error=>"Object not found") if(!$json->{data}->{object_id});
	my $mblog = $json->{data}->{object};
	return (error=>"No object found") if(!$mblog);
	return (error=>"No media found") if(!$mblog->{created_at});

	
	my $id = $mblog->{author}->{id} ? $mblog->{author}->{id} . "_" : "";
	my $created = $mblog->{created_at};
	$created =~ s/\s*\d+:\d+:\d+\s*//;
	$created = strtime2($created,5);
	$id = $created . "_" . $id if($created);
	my	$text = extract_post_title($mblog->{summary});
	if($text) {
		$id = $id . $text;
	}
	my @data;
	foreach(qw/stream/) {
		next unless($mblog->{$_});
		foreach my $url (qw/hd_url  mp4_hd_url stream_url_hd url stream_url/) {
			next unless($mblog->{$_}->{$url});
			push @{$mblog->{media}},$mblog->{$_}->{$url};
			push @data,$mblog->{$_}->{$url} . "\t$id.mp4";
		}
	}
	foreach(qw/image/) {
		next unless($mblog->{$_});
		my $url = $mblog->{$_}->{url};
		push @{$mblog->{media}},$url;
		my $ext = $url;
		$ext =~ s/^.*\./\./;
		push @data,$url . "\t$id$ext" if($url);
	}
	return (data=>\@data,object=>$mblog);
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
	if((defined $json->{ok}) && ($json->{ok} == 0)) {
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
	$r{wait} = 10;
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
			$r{next_page} = $i;
			$np =~ s/page=\d+/page=$i/;
		}
		else {
			$np = $url . "&page=2";
		}
	}
	elsif($r{json} 
			&& $r{json}->{ok}
			&& ref $r{json}->{data}
			&& ref $r{json}->{data}->{cardlistInfo}
			&& defined $r{json}->{data}->{cardlistInfo}->{total}
			&& ($r{json}->{data}->{cardlistInfo}->{total} == 0)
	){
		$r{blocked} = 1;
	}
	if($np){
		if($r{next_page} and (!$r{count}) and $r{next_page}>400) {
			print STDERR "Empty page, and page number >400, stop here\n";
		}
		else {
			$r{pass_data} = [$np];
			$r{pass_count} = 1;
			$r{same_level} = 1;
		}
	}
	elsif($r{blocked}) {
		print STDERR "No data found, user maybe blocked!\n";
		$r{wait} = 3;
	}
	else {
		print STDERR "No next page found\n";
		$r{wait} = 5;
	}
	delete $r{info};
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
		qr/^(\d+)$/,
		qr/^u\/(\d+)$/,
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
	my $html = get_url($nurl,'-v');
	my $json = decode_json($html);
	my $utf8 = find_encoding('utf-8');
	if(!$json) {
		return ("error","Parsing page failed");
	}
	elsif(!$json->{ok}) {
		my $msg = "Parsing page failed";
		if($json->{msg}) {
			$msg = $utf8->encode($json->{msg});
			print STDERR $msg,"\n";
		}
		return("error"=>$msg);
	}
	$json = $json->{data} if($json->{data});
	$json = $json->{userInfo} if($json->{userInfo});
	return (
		uid=>$json->{id},
		profile=> "u/" . $json->{id},
		host=>'weibo.com',
		uname=>$utf8->encode($json->{screen_name}),
		info=>$json,
	);
}

#NOT WORK,TOKEN NEED
sub m_get_info {
	my %info = m_get_user(@_);
	use Data::Dumper;print STDERR Dumper(\%info),"\n";
	return %info;

	my $query = shift;
	my $data = get_url(
		'https://m.weibo.cn/profile/info?' . $query,
		'--referer','https://m.weibo.cn/profile/2838312893',
		@_);
	if($data =~ m/<p[^>]+class="h5-4con"[^>]*>([^<]+)</) {
		print STDERR $1,"\n";
		return undef;
	}
	my $json = decode_json($data);
	use Data::Dumper;print Dumper($data,$json),"\n";
	return $json;
}

1;
