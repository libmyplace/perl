#!/usr/bin/perl -w
package MyPlace::Weipai;
use strict;
use warnings;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
	#@EXPORT		    = qw(profile user videos home square get_likes fans follows video);
    @EXPORT_OK      = qw(profile user videos home square get_likes fans follows video get_url);
}

our $HOST = 'http://w1.weipai.cn';
our %URLSTPL = (
	profile=>'/get_profile?&weipai_userid=$1',
	user=>'/home_user?relative=after&user_id=$1&day_count=$2&cursor=$3',
	video=>'/user_video_list?blog_id=$1',
	home=>'/my_follow_user_video_list?relative=after&user_id=$1&count=$2&cursor=$3',
	square=>'/top_video?relative=after&type=$1&count=$2&cursor=$3',
	likes=>'/my_favorite_video_list?count=$2&relative=after&user_id=$1&cursor=$3',
	fans=>'/user_fans_list?count=$2&relative=after&uid=$1&cursor=$3',
	follows=>'/user_follow_list?count=$2&relative=after&uid=$1&cursor=$3',
);


use JSON qw/decode_json/;
use Encode qw/find_encoding/;
use MyPlace::Curl;
use utf8;
my $CURL = MyPlace::Curl->new(
	"location"=>'',
	"silent"=>'',
	"show-error"=>'',
#	"retry"=>4,
	"max-time"=>120,
);
my @CURLOPT = (
	'-H','User-Agent: android-async-http/1.4.1 (weipaipro)',
	'-H','Phone-Type: android_VIVO_4.4.2',
	'-H','os: android',
	'-H','Channel: weipai',
	'-H','App-Name: weipai',
	'-H','Api-Version: 8',
	'-H','Client-Version: 0.99.9.1',
	'-H','Device-Uuid: 33fde2c3c6c73344314057197f2710edf3571457',
	'-H','Weipai-Token: 54b8e21c2e8a9',
	'-H','Weipai-UserId: 508775398134943b58000051',
	'-H','Phone-Number: ',
	'-H','Push-Id: com.weipai.weipaipro',
	'-H','Kernel-Version: 15',
	'-H','Com-Id: weipai',
);
my $utf8 = find_encoding('utf8');


sub get_url {
	my $url = shift;
	print STDERR "Retriving $url ...\n";
	my($exitval,$data) = $CURL->get($url,@CURLOPT);
	if($exitval) {
		return undef;
	}
	else {
		return $data;
	}
}

sub _build_url {
	my $tpl = shift;
	my $count = 0;
	my $url = $HOST . $URLSTPL{$tpl};
	foreach(@_) {
		$count++;
		if(defined($_)) {
			$url =~ s/\$$count/$_/g;
		}
		else {
			$url =~ s/[&\?]?[^&=]+=\$$count//g;
		}
	}
	if($count < 10) {
		my $range = "[" . $count . "-9]";
		$url =~ s/[&\?]?[^&=]+=\$$range//g;
	}
	return $url;
}

sub _encode {
	my $data = shift;
	my $type = ref $data;
	if(!$type) {
		return $utf8->encode($data);
	}
	elsif($type eq 'ARRAY') {
		foreach (@$data) {
			$_ = _encode($_);
		}
		return $data;
	}
	elsif($type eq 'HASH') {
		foreach my $key (keys %$data) {
			$data->{$key} = _encode($data->{$key});
		}
		return $data;
	}
}

sub get_json {
	return decode_json(get_url(_build_url(@_)));
}
sub get_data {
	my $what = shift;
	my $cmd = lc($what);
	my $url;
	my $data;
	if($cmd eq 'videoinfo') {
		my $video = decode_json(get_url(_build_url('video',@_)));
		$video = $video->{video_list}->[0] if($video->{video_list});
		delete $video->{defender_list};
		delete $video->{top_reply_list};
		$data = $video;
	}
	elsif($cmd eq 'poster') {
		my $videoid = shift;
		my $video = decode_json(get_url(_build_url('video',$videoid)));
		if($video->{video_list}) {
			my $uid = $video->{video_list}->[0]->{user_id};
			print "USERID => $uid\n"; 
			$data = decode_json(get_url(_build_url('user',$uid,@_)));
			$data->{profile} = get_json('profile',$uid);
			delete $data->{defender_list};
		}
		else {
			$data = $video;
		}
	}
	else {
		$url = _build_url($cmd,@_);
		$data = decode_json(get_url($url));
	}
	return _encode($data);
}


sub get_user {
	my $uid = shift;
	return get_data('user',$uid,1);
}

sub get_videos {
	my $uid = shift;
	my $days = shift(@_) || 7;
	my $cursor = shift;
	return get_data('user',$uid,$days,$cursor);
}

sub get_home {
	my $id = shift;
	my $count = shift(@_) || 40;
	my $cursor = shift;
	return get_data('home',$id,$count,$cursor);
}

sub get_square {
	my $type = shift(@_) || 'top_day';
	my $count = shift(@_) || 120;
	my $cursor = shift;
	return get_data('square',$type,$count,$cursor);
}
sub get_likes {
	my $id = shift;
	my $count = shift(@_) || 40;
	my $cursor = shift;
	return get_data('likes',$id,$count,$cursor);
}
sub get_fans {
	my $id = shift;
	my $count = shift(@_) || 40;
	my $cursor = shift;
	return get_data('fans',$id,$count,$cursor);
}
sub get_follows {
	my $id = shift;
	my $count = shift(@_) || 40;
	my $cursor = shift;
	return get_data('follows',$id,$count,$cursor);
}
sub get_video {
	my $id = shift;
	return get_data('video',$id);
}


sub get_user_videos {
	my $uid = shift;
	my $cursor = shift;
#	my $url = _build_url('user',$uid,undef,$cursor);
	my %r;
	my $info = get_videos($uid,undef,$cursor);
	$r{uid} = $uid;
	$r{next_cursor} = $info->{next_cursor};
	if($info->{"diary_list"}) {
		$r{videos} = [];
		$r{count} = 0;
		my @data;
		foreach(@{$info->{"diary_list"}}) {
#"day": "2014-08-23",
#"city": "\u5e7f\u5dde\u5e02",
#"video_list": [{
#"blog_id": "53f87baea5640bff6b8b4576",
#"video_screenshot": "http:\/\/aliv.weipai.cn\/201408\/23\/19\/3C6C58A6-34DE-4D2B-9145-107BF7B70BB5.2.jpg",
#"video_intro": "\uff0c\u51bb\u6b7b\u4e86\u5728\u8001\u7238\u7684\u5e2e\u52a9\u4e0b\u5b8c\u6210\u4e86\u51b0\u6876\u6311\u6218@\u5fae\u62cd\u5c0f\u79d8\u4e66",
#"city": "\u5e7f\u5dde\u5e02"
#}]
			if($_->{video_list}) {
				foreach my $videoinfo (@{$_->{video_list}}) {
					my $video = {};
					$video->{cover} = $videoinfo->{video_screenshot};
					$video->{video} = $video->{cover};
					$video->{video} =~ s/\.([^\/]+)$//;
#					$video->{title} = $utf8->encode($videoinfo->{video_intro});
					$video->{id} = $videoinfo->{blog_id};
					if($video->{cover} =~ m/\/(\d\d\d\d)(\d\d)\/(\d\d)\/(\d+)\//) {
						@{$video}{qw/year month day hour minute/} = ($1,$2,$3,$4,'');
					}
					push @{$r{videos}},$video;
					$r{count}++;
				}
			}
		}
	}
	return \%r;
}

#####################################################################
#
#                  CLASS IMPLEMENTION
#
#
#####################################################################


use base 'MyPlace::Program';
use Data::Dumper;

sub OPTIONS {
	qw/
	help|h
	manual
	dump|d
	/;
}

sub cmd_get_videos {
	my $opts = shift;
	my $uid = shift;
	my $cursor = shift;
	my $videos = get_user_videos($uid,$cursor);
	print Data::Dumper->Dump([$videos],[qw/$videos/]),"\n" if($opts->{dump});
	return $videos;
}

sub cmd_get_video {
	my $opts = shift;
	my $video = get_video(@_);
	$video = $video->{video_list}->[0] if($video->{video_list});
	delete $video->{defender_list};
	delete $video->{top_reply_list};
	print Data::Dumper->Dump([$video],[qw/$video/]),"\n" if($opts->{dump});
	return $video;
}

sub get_profile {
	my $id = shift;
		$id =~ s/^.*\///;
		$id =~ s/[\/\._].*$//;
		my %pro;
		foreach my $r (get_data('profile',$id),get_data('user',$id)) {
			if($r->{socialList}) {
				foreach my $k (@{$r->{socialList}}) {
					$r->{$k->{socialName} . "_profile"} = $k->{socialUrl};
				}
			}
			foreach my $k (qw/
					videoList hotImg
					socialList defender_list
					diary_list next_cursor
					prev_cursor level_des
					state 
				/) {
				delete $r->{$k};
			}
			foreach my $k (keys %$r) {
				next unless($r->{$k});
				$pro{$k} = $r->{$k};
			}
		}
	return \%pro;
}

sub show_profile {
	my $opt = shift;
	foreach my $id (@_) {
		my $pro = get_profile($id);
		print Data::Dumper->Dump([$pro],[$id]),"\n";
	}
	return 0;
}

sub save_profile {
	my $opt = shift;
	my $id = shift;
	my $pro = get_profile($id);
	if($pro->{avatar}) {
		system("download","--url",$pro->{avatar},"--saveas","$id.jpg");
	}
	if(open FO,'>',"$id.txt") {
		print FO Data::Dumper->Dump([$pro],[$id]),"\n";
		close FO;
	}
	else {
		print STDERR "Error opening $id.txt for writting: $!\n";
		return 1;
	}
	
}

sub show_follows {
	my $opt = shift;
	my $id = shift;
	my $limits = shift;
	my $count = 0;
	my @results;
		my $nc = "";
		while(defined($nc)) {
			my $follows = get_follows($id,40,$nc);
			last unless($follows);
			last unless($follows->{user_list});
			$nc = $follows->{next_cursor} || undef;
			foreach(@{$follows->{user_list}}) {
				$count++;
				if($limits and $limits < $count) {
					return 0;
				}
				print $_->{user_id},"\t",$_->{nickname},"\n";
			}
		}
}

sub extract {
	my $opt = shift;
	my $id = shift;
	my $cursor = shift;
}


sub MAIN {
	my $self = shift;
	my $opts = shift;
	my $command = shift;
	if(!$command) {
		return $self->USAGE;
	}
	$command = uc($command);
	
	if($command eq 'GET_VIDEOS') {
		return cmd_get_videos($opts,@_);
	}
	elsif($command eq 'GET_VIDEO') {
		return cmd_get_video($opts,@_);
	}
	elsif($command eq 'PROFILE') {
		return show_profile($opts,@_);
	}
	elsif($command eq 'FOLLOWS') {
		return show_follows($opts,@_);
	}
	elsif($command eq 'SAVE-PROFILE') {
		return save_profile($opts,@_);
	}
	elsif($command eq 'EXTRACT') {
		return extract($opts,@_);
	}
	elsif($command eq 'DUMP') {
		my $what = shift;
		if($what) {
			my $id = shift;
			$id =~ s/^.*\///;
			$id =~ s/[\/\._].*$//;
			my $r = get_data(lc($what),$id,@_);
			print Data::Dumper->Dump([$r],[$what]),"\n";
			return 0;
		}
		else {
			print STDERR "Usage: $0 dump <user|video|fans|...> ...\n";
			return 1;
		}
	}
}


return 1 if caller;
my $PROGRAM = MyPlace::Weipai->new();
exit $PROGRAM->execute(@ARGV);

1;
