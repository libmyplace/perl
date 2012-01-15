#!/usr/bin/perl -w
package MyPlace::163::Blog;
use strict;
use warnings;
BEGIN {
#    sub debug_print {
#        return unless($ENV{XR_PERL_MODULE_DEBUG});
#        print STDERR __PACKAGE__," : ",@_;
#    }
#    &debug_print("BEGIN\n");
    require Exporter;
    our ($VERSION,@ISA,@EXPORT,@EXPORT_OK,%EXPORT_TAGS);
    $VERSION        = 1.00;
    @ISA            = qw(Exporter);
    @EXPORT         = qw();
    @EXPORT_OK      = qw();
}
use Encode;
use MyPlace::HTTPGet;
my $HTTP;

sub new {
    my $class = shift;
	my $name = shift;
    my $id = shift;
    return bless {id=>$id,name=>$name},$class;
}
sub _convert_from_html {
    my $html_data = shift;
    if($html_data =~ m/var\s+g_[pa]\$\d+d\s*=\s*(\[\{.+\}\])\s*;/os) {
        $html_data = $1;
        $html_data =~ s/:/=>/og;
        $html_data =~ s/true/"true"/og;
        my $r = eval($html_data);
        if($@) {
            print STDERR $@,"\n";
            return undef;
        }
        elsif((!$r) or (!@{$r})) {
            return undef;
        }
        return $r;
    }
    else {
        return undef;
    }
}

my $pic_host = 'http://img.ph.126.net/';
my $pic_host_1 = 'http://img';
my $pic_host_2 = '.ph.126.net/';
my $blog_host = 'http://img.bimg.126.net/photo/';
my $blog_host_1 = 'http://img';
my $blog_host_2 = '.bimg.126.net/photo/';
sub _convert_pic_url {
    my $url = shift;
    if($url =~ m/^(\d*)\/photo\/(.+)$/o) {
            return $1 ? $blog_host_1 . $1 . $blog_host_2 . $2 : $blog_host . $2;
    }
    elsif($url =~ m/^(\d*)\/(.+)$/o) {
            return $1 ? $pic_host_1 . $1 . $pic_host_2 . $2 : $pic_host . $2;
    }
}

sub get_blogs {
    my $self = shift;
    if(!$self->{id}) {
        $self->{id} = shift;
    }
    if(!$self->{id}) {
        warn "No ID specified.\n";
        return undef;
    }
	if(!$self->{name}) {
		$self->{name} = shift;
	}
    if(!$self->{name}) {
        warn "No name specified.\n";
        return undef;
    }
    my $api_url = 'http://api.blog.163.com/' . $self->{name} . '/dwr/call/plaincall/BlogBeanNew.getBlogs.dwr?';
    my $sess_id = 100+int(rand(1)*100+1);
    $api_url = $api_url . join("&", 
						"callCount=1",
						"scriptSessionId=\${scriptSessionId}$sess_id",
						"c0-scriptName=BlogBeanNew",
						"c0-methodName=getBlogs",
						"c0-id=0",
						"c0-param0=number:$self->{id}"
					);
	my $pos = 0;
	my $length = 100;
    $HTTP = MyPlace::HTTPGet->new() unless($HTTP);
	my @blogs;
	while(1) {
		my $batch_id = 577000 + int(rand(1)*1000+1);
		my $url = join("&",$api_url,
					"c0-param1=number:$pos",
					"c0-param2=number:$length",
					"batchId=$batch_id"
				 );

#	callCount=1
#	scriptSessionId=${scriptSessionId}187
#	c0-scriptName=BlogBeanNew
#	c0-methodName=getBlogs
#	c0-id=0
#	c0-param0=number:188090284
#	c0-param1=number:0
#	c0-param2=number:20
#	batchId=532464
		print STDERR "Retriving $url...";
	    my ($status,$result) = $HTTP->get($url);
		print STDERR "\n\t[$status]\n";
		#print STDERR "$result\n";
		my @matched;
		while($result =~ m/s\d+\.permalink="([^"]+)/g) {
			#print $1,"\n";
			push @matched,"http://$self->{name}.blog.163.com/$1";
		}
		if(@matched) {
			push @blogs,@matched;
			if(@matched < $length) {
				last;
			}
		}
		else {
			last;
		}
		$pos += $length;
	}
	return @blogs ? \@blogs : undef;
}

sub get_user_info {
	my $self = shift;
	if(!$self->{name}) {
		$self->{name} = shift;
	}
	return undef unless($self->{name});
	my $url = "http://$self->{name}.blog.163.com";
    $HTTP = MyPlace::HTTPGet->new() unless($HTTP);
	print STDERR "Retriving USER information for $self->{name} ...";
	my($status,$result) = $HTTP->get($url,'charset:gbk');
	print STDERR "\t[$status]\n";
#userId:188090284
#,userName:'zyayoyo'
#,nickName:'张优'
#,imageUpdateTime:1318437641442
#,baseUrl:'http://zyayoyo.blog.163.com/'
#,gender:'他'
#,email:'1219205481@qq.com'
#,photo163Name:'1219205481@qq.com'
#,photo163HostName:'1219205481@qq.com'
#,TOKEN_HTMLMODULE:''
#,isMultiUserBlog:false
#,isWumiUser:true
#,sRank:-100
	if($status == 200)  {
		while($result =~ m/(userId|userName|nickName|baseUrl|gender|imageUpdateTime|email|photo163Name|photo163HostName)\s*:\s*('?)(\d+|[^']+)\2/g) {
			print "$1 == $3\n";
			$self->{$1} = $3;
		}
	}
	else {
		return undef;
	}
}

sub get_albums_url {
    my $self = shift;
	$self->get_user_info(@_);
    if(!$self->{photo163Name}) {
        warn "No photo163Name specified.\n";
        return undef;
    }
#	URL=http://photo.163.com/photo/1219205481@qq.com/dwr/call/plaincall/UserSpaceBean.getUserSpace.dwr
#	callCount=1
#	scriptSessionId=${scriptSessionId}187
#	c0-scriptName=UserSpaceBean
#	c0-methodName=getUserSpace
#	c0-id=0
#	c0-param0=string:1219205481%40qq.com
#	batchId=125181
    my $api_url = 'http://photo.163.com/photo/' . $self->{photo163Name} . '/dwr/call/plaincall/UserSpaceBean.getUserSpace.dwr?';
    my $sess_id = 100+int(rand(1)*100+1);
    my $batch_id = 577000 + int(rand(1)*1000+1);
    my $request = $api_url . "callCount=1&scriptSessionId=\${scriptSessionId}$sess_id&c0-scriptName=UserSpaceBean&c0-methodName=getUserSpace&c0-id=0&c0-param0=string:$self->{photo163Name}&batchId=$batch_id";
    $HTTP = MyPlace::HTTPGet->new() unless($HTTP);
    my (undef,$result) = $HTTP->get($request);
	print STDERR $result,"\n";
    my $albums_url;
    if($result =~ m/cacheFileUrl:"([^"]+)"/o) {
        $albums_url = 'http://' . $1;
        return $albums_url;
    }
    else {
        warn $result,"\n";
        return undef;
    }
}

sub get_albums_from_js {    
    my $self = shift;
    my $albums_url = shift;
    my @QUERYS = @_;
    $HTTP = MyPlace::HTTPGet->new() unless($HTTP);
	print STDERR "Retriving $albums_url...";
    my ($status,$albums_data) = $HTTP->get($albums_url,'charset:gbk');
	print STDERR "\t[$status]\n";
    my $albums = _convert_from_html($albums_data);
    return undef unless($albums);
    if(@QUERYS) {
        my $UTF8 = find_encoding('utf-8');
        @QUERYS = map {$UTF8->decode($_)} @QUERYS;
        my @new_albums;
        foreach my $id_or_name (@QUERYS) {
            foreach(@{$albums}) {
                if($id_or_name eq $_->{name}) {
                    push @new_albums,$_;
                }
                elsif($id_or_name eq $_->{id}) {
                    push @new_albums,$_;
                }
            }
        }
        $albums = \@new_albums;
    }
    foreach(@{$albums}) {
		if($_->{purl}) {
	        $_->{purl} = 'http://' . $_->{purl} unless($_->{purl} =~ m/^http:/i);
		}
    }
    return $albums;
}
sub get_albums {
    my $self = shift;
    my $url = $self->get_albums_url();
    return $self->get_albums_from_js($url,@_);
}

sub get_pictures_from_js {
    my $self = shift;
    my $url = shift;
    $HTTP = MyPlace::HTTPGet->new() unless($HTTP);
    my (undef,$pictures_data) = $HTTP->get($url,'charset:gbk');
    my $pictures = _convert_from_html($pictures_data);
    return undef unless($pictures);
    foreach(@{$pictures}) {
        $_->{url} = _convert_pic_url($_->{ourl});
    }
    return $pictures;
}

sub get_pictures {
    my ($self,$album) = @_;
    return undef unless($album);
    my $url;
    if(!ref $album) {
        $url = $album;
    }
    else {
        $url = $album->{purl};
    }
#    $url = 'http://' . $url unless($url =~ m/^http:/i);
    return $self->get_pictures_from_js($url);
}

1;
