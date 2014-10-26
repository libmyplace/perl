#!/usr/bin/perl -w
package MyPlace::Google::Search::HTML;
use strict;
use URI::Escape;
use MyPlace::Search;
use constant {
    APPID=>'BlVF2czV34FVChK2mzsN7SBghcl.NwZ4YayhlbBXiYxPnRScC49U1ja4HnnF',
    IMAGE_SEARCH_REFER=>'http://images.google.com',
    URL_ID=>'url',
    IMAGE_DEFAULT_COUNT=>21,
    IMAGE_DATA_ID=>'results',
};
my @GOOGLE_IP = (
 #   'images.google.com',
    '72.14.204.95',
    '72.14.204.96',
    '72.14.204.98',
    '72.14.204.99',
    '72.14.204.103',
    '72.14.204.104',
    '72.14.204.147',
    '72.14.204.148',
  #  '72.14.213.103',
  # '74.125.71.106',
    '209.85.229.99',
    '209.85.225.105',
    '209.85.227.147',
    '209.85.227.100',
    '209.85.227.104',
    '209.85.227.103',
);
#@GOOGLE_IP = ('images.google.com');
@GOOGLE_IP = (
	'www.google.com.hk',
#	'www.google.com',
#	'www.google.co.jp',
#	'www.google.co.kr',
);
#http://images.google.com/images?hl=en&newwindow=1&safe=off&as_st=y&tbs=isch%3A1%2Cisz%3Alt%2Cislt%3Axga&sa=1&q=%22Michelle+Marsh%22+nude&aq=f&aqi=&aql=&oq=&gs_rfai=
#http://www.google.com/images?q=Jordan+Carver&um=1&hl=en&newwindow=1&safe=off&tbs=isch:1,isz:lt,islt:2mp

#https://www.google.com.hk/search?q=%EC%9D%B4%ED%9A%A8%EC%98%81&newwindow=1&safe=off&sa=X&hl=zh-HK&tbm=isch&ijn=1&ei=gNUqVILoBKLOygOJq4KoAw&start=100

my %DEFAULT_PARAMS = 
(
    www => {},
    images => 
    {
        'safe'=>'off',
        'hl'=>'en',
		'tbm'=>'isch',
		'sa'=>'X',
#		'sout'=>'0',
    },
);

my %IMAGE_DMS_MAP = (
        'any'=>'',
        '>400x300'=>'qsvga',
        '>640x480'=>'vga',
        '>800x600'=>'svga',
        '>1024x768'=>'xga',
        '>1600x1200'=>'2mp',
        '>2272x1704'=>'4mp',
        '>2816x2112'=>'6mp',
        '>3264x2448'=>'8mp',
        '>3648x2736'=>'10mp',
        '>4096x3072'=>'12mp',
        '>4480x3360'=>'15mp',
        '>5120x3840'=>'20mp',
        '>7216x5412'=>'40mp',
        '>9600x7200'=>'70mp',
);


sub get_google_ip {
   return $GOOGLE_IP[int(rand(@GOOGLE_IP))]; 
}

sub import {
#	use Data::Dumper;print Data::Dumper->Dump([\@_],[qw/*_/]),"\n";
	my $self = shift;
	foreach(@_) {
		$main::{"$_"} = $MyPlace::Google::Search::HTML::{"$_"};
	}
#	use Data::Dumper;print Data::Dumper->Dump([\%{main::}, \%MyPlace::Google::Search::HTML::],[qw/*main *self/]),"\n";
}

sub test_google_ip  {
	foreach(@GOOGLE_IP) {
		print STDERR "Testing $_ ...";
		if(system("ping -c 4 \"$_\" 1>/dev/null") == 0) {
			print STDERR "\t\[OK]\n"
		}
		else {
			print STDERR "\t\[Failed]\n"
		}

	}
}

sub get_api_url {
    my ($vertical,$keyword,$page,%params) = @_;
    my %api_params;
	my $action = "search";
    foreach (keys  %params) {
        next if($_ eq 'type');
        next if($_ eq 'dimensions');
        next if($_ eq 'size');
        if($_ eq 'filter') {
            $api_params{safe} = $params{$_} eq 'no' ? 'off' : 'on';
        }
        elsif($_ eq 'lang' or $_ eq 'region') {
            $api_params{hl} = $params{$_};
        }
		elsif($_ eq 'page') {
			$page = $params{$_};
		}
        else {
            $api_params{$_} = $params{$_}; 
        }
    }
    if($vertical eq 'images') {
		%api_params = (%{$DEFAULT_PARAMS{images}},%api_params);
        if($params{dimensions}) {
            $api_params{tbs}='isch:1,isz:lt,islt:' . $params{dimensions};
        }
        elsif($params{size} and $IMAGE_DMS_MAP{$params{size}}) {
            $api_params{tbs}='isch:1,isz:lt,islt:' . $IMAGE_DMS_MAP{$params{size}};
        }
        elsif($params{type}) {
            $api_params{imgsz}=$params{type};
        }
        $api_params{ndsp} = IMAGE_DEFAULT_COUNT;
    }
    if(!$api_params{q}) {
        if($keyword)
        {
            $api_params{q} = build_keyword($keyword);
        }
    }
    if(!$api_params{start}) {
        if($page and $page =~ m/^[0-9]+$/ and $page>1) {
            $api_params{start} = $api_params{ndsp} * ($page - 1);
			$api_params{ijn} = $page;
        }
    }
    $api_params{hl} = 'en' unless($api_params{hl});
    $api_params{safe} = 'off' unless($api_params{safe});
#	$api_params{sout} = '1';
#    my $params = join("&",map ("$_=" . $api_params{$_},keys %api_params));
    return build_url('http://' . &get_google_ip()  . "/$action?",\%api_params);
}

sub new {
    my $class = shift;
    return bless {@_},$class;
}

sub _make_data {
    my $org = shift;
    my @result;
    return unless($org and @{$org});
    foreach(@{$org}) {
        my %cur = (
                "clickurl"=>$_->[0],
                "target"=>$_->[1],
                "id"=>$_->[2],
                "url"=>$_->[3],
                "twidth"=>$_->[4],
                "theight"=>$_->[5],
                "title"=>$_->[6],
                "filetype"=>$_->[10],
                "site"=>$_->[11],
                "thumburl"=>$_->[21],
        );
		if($cur{clickurl} =~ m/imgurl=([^&]+)&imgrefurl=([^&]+)/) {
			$cur{url} = $1;
			$cur{refurl} = $2;
		}
        if($_->[9] =~ /(\d+)\s*\&times;\s*(\d+)\s*-\s*(\d+[kKmM]?)/) {
            $cur{width}=$1;
            $cur{height}=$2;
            $cur{size}=$3;
        }
        push @result,\%cur;
    }
    return \@result;
}
sub search {
    my $self = shift;
    unshift @_,$self unless($self and ref $self);
    my($ajax,$data_id,$refer,$keyword,$page,%args)=@_;
    my ($URL,$BASEURL,$QUERYTEXT);

    my $data;
    my $results;
    my $status;
#    print STDERR "[Google $ajax] $QUERYTEXT\n";
    my $res;
	foreach(4,3,2,1,0) {
		($URL,$BASEURL,$QUERYTEXT)= &get_api_url($ajax,$keyword,$page,%args);
		$res = get_url($URL,$refer,undef,1);
		last if($res->is_success);
		print STDERR "Retry[$_]\n";
	}
    if($res and $res->is_success) {
        my $code = $res->content;
		#print STDERR $code;	
        if($code and $code =~ m/\;\s*dyn\.setResults\((.+?)\)\s*\;\s*/s) {
            $code = $1;
			$data = eval($code);
			$results = _make_data($data);
        }
		else {
#<a href="/imgres?imgurl=http://www.wpclipart.com/toys/blocks/abc_blocks.png&amp;imgrefurl=http://www.wpclipa    rt.com/toys/blocks/abc_blocks.png.html&amp;usg=__g0pgtIFbE5GZX_wJAz9ADvAIo9s=&amp;h=389&amp;w=400&amp;sz=15&amp;hl=en&amp;start=2&amp;zoom=1&amp;tbnid=z9ypytoY8udP6M:&amp;tb    nh=121&amp;tbnw=124&amp;ei=m7boTp2GAqiuiQeo1szpCA&amp;prev=/images%3Fq%3D%2522abc%2522%26hl%3Den%26newwindow%3D1%26safe%3Doff%26ndsp%3D18%26sout%3D1%26tbm%3Disch&amp;itbs=1
			foreach(split('\n',$code)) {
				while(m/href="([^"]+imgurl=[^"]+)"/g) {
					my $link = $1;
					$link =~ s/^[^\?]+\?//;
					my @params = split('&amp;',$link);
					my %cur;
					foreach(@params) {
						if(m/^([^=]+)=(.+)$/) {
							$cur{$1} = $2;
						}
						$cur{$_}='';
					}
					push @{$results},{
							url=>$cur{imgurl},
							refurl=>$cur{imgrefurl},
							height=>$cur{h},
							width=>$cur{w},
							size=>$cur{sz},
							theight=>$cur{tbnh},
							twidth=>$cur{tbnw}
						};
				}
			}
		}
       #use Data::Dumper;print Dumper($data);
        if($results) {
            $status = 1;
        }
        elsif($!) {
            $status = -1;
            $results = $!;
            $data = $code;
        }
        else {
            $status = -2;
            $results = $data;
            $data = $code;
        }
    }
    else {
        $status = undef;
        $results = $res->code . " " . $res->status_line;
    }
#	use Data::Dumper;print Dumper($results);
    if($self and ref $self) {
        $self->{keyword}=$keyword;
        $self->{ajax} = $ajax;
        $self->{refer}=$refer;
        $self->{args} = \%args;
        $self->{status}=$status;
        $self->{data}=$data;
        $self->{results}=$results;
    }
    return $status,$results,$data;
}

sub extract_url {
    my $result = shift;
    return $result->{url};
}

sub search_images {
    my $self = shift;
    if($self and ref $self) {
        return $self->search("images",IMAGE_DATA_ID,IMAGE_SEARCH_REFER,@_);
        
    }
    else {
        unshift @_,$self;
        return &search("images",IMAGE_DATA_ID,IMAGE_SEARCH_REFER,@_);
   } 
}





1;
