#!/usr/bin/perl -w
use strict;
use warnings;
BEGIN {
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT		    = qw(profile user videos home square likes fans follows video);
    @EXPORT_OK      = qw(profile user videos home square likes fans follows video);
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
my $CURL = MyPlace::Curl->new();

my $utf8 = find_encoding('utf8');


sub _get_url {
	my $url = shift;
	print STDERR "Retriving $url ...\n";
	my($exitval,$data) = $CURL->get($url);
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

sub get_data {
	return decode_json(_get_url(_build_url(@_)));
}

sub profile {
	my $uid = shift;
	return get_data('profile',$uid);
}

sub user {
	my $uid = shift;
	return get_data('user',$uid,1);
}

sub videos {
	my $uid = shift;
	my $days = shift(@_) || 7;
	my $cursor = shift;
	return get_data('user',$uid,$days,$cursor);
}

sub home {
	my $id = shift;
	my $count = shift(@_) || 40;
	my $cursor = shift;
	return get_data('home',$id,$count,$cursor);
}

sub square {
	my $type = shift(@_) || 'top_day';
	my $count = shift(@_) || 120;
	my $cursor = shift;
	return get_data('square',$type,$count,$cursor);
}
sub likes {
	my $id = shift;
	my $count = shift(@_) || 40;
	my $cursor = shift;
	return get_data('likes',$id,$count,$cursor);
}
sub fans {
	my $id = shift;
	my $count = shift(@_) || 40;
	my $cursor = shift;
	return get_data('fans',$id,$count,$cursor);
}
sub follows {
	my $id = shift;
	my $count = shift(@_) || 40;
	my $cursor = shift;
	return get_data('follows',$id,$count,$cursor);
}
sub video {
	my $id = shift;
	return get_data('video',$id);
}

1;
