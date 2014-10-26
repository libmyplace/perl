

package MyPlace::SimpleQuery;
use strict;
use File::Spec::Functions qw/catfile catdir/;

sub new {
	my $class = shift;
	my $self = bless {},$class;
	$self->{OUTPUT} = [];
	if(@_) {
		push @{$self->{OUTPUT}},@_;
	}
	$self->{database} = "TEXT INPUT";
	return $self;
}

sub set_options {
	my $self = shift;
	$self->{options}->{$_} = 1 foreach(@_);
	return $self;
}

sub _parse_from_file {
	my $self = shift;
	my $input = shift;
	my @lines;
	open FI,'<',$input or return undef,"$!, while opening $input";
	@lines = <FI>;
	close FI;
	return $self->_parse_from_text(@lines);
}

sub _parse_from_text {
	my $self = shift;
	my %info;
	my @sortedId;
	foreach(@_) {
		chomp;
		next unless($_);
		next if(m/^\s*$/);
		#print STDERR "TEXT:[$_]\n";
		if(m/^\s*\#OUTPUT\s*:\s*(.+?)\s*$/) {
			push @{$self->{OUTPUT}},$1;
		}
		elsif(m/^\s*([^\s]+)\s+([^\s]+)\s*$/) {
			push @sortedId,$1 unless(defined $info{$1});
			$info{$1} = $2;
		}
		elsif(m/^\s*([^\s]+)\s*$/) {
			push @sortedId,$1 unless(defined $info{$1});
			$info{$1} = "";
		}
		else {
			push @sortedId,$_;
		}
	}
	#die();
	if(!@sortedId) {
		return undef,"Invalid data feed";
	}
	return {
		info=>\%info,
		sortedId=>\@sortedId,
	};
}

sub item {
	my $self = shift;
	my $idName = shift;
	my %table = %{$self->{info}};
	foreach my $id(keys %table) {
		if($id eq $idName) {
			return ($id,$table{$id});
		}
	}
	foreach my $id(keys %table) {
		if($table{$id} eq $idName) {
			return ($id,$table{$id});
		}
	}
	return undef,"[$idName] match no item";
}

sub additem {
	my $self = shift;
	my $key = shift;
	my $value = shift(@_) || "";
	if(!$key) {
		return undef,"Empty key not allowed";
	}
	if(!$value) {
		foreach(keys %{$self->{info}}) {
			if($self->{info}->{$_} eq $key) {
				return undef,"Value <$key> already exists in KEY: $_";
			}
		}
	}
	return $self->_add({
			info=>{$key=>$value},
			sortedId=>[$key]
	});
}

sub add {
	my $self = shift;
	my ($r,$msg) = $self->_parse_from_text(@_);
	if(!$r) {
		return undef,"Invalid input: $msg";
	}
	return $self->_add($r);
}

sub _add {
	my $self = shift;
	my $r = shift;

	my %info = ();
	my @sorted = ();
	if($self->{info}) {
		%info = %{$self->{info}};
		@sorted = @{$self->{sortedId}};
	};
	my %incoming = %{$r->{info}};
	my @id = @{$r->{sortedId}};
	my $count;
	foreach my $id(@id) {
		if($id =~ m/^\s*$/) {
			next;
		}
		elsif($id =~ m/^#/) {
			next;
		}
		elsif(defined $info{$id}) {
			if($self->{options}->{overwrite}) {
				$count++;
				$info{$id} = $incoming{$id};
				push @sorted,$id;
				print STDERR "Add $id => $incoming{$id}\n";
			}
			else {
				print STDERR "\tKey <$id> already defined as : " . ($info{$id} || "[EMPTY]") . "\n";
			}
			next;
		}
		elsif(defined $info{"#$id"}) {
			next;
		}
		elsif(defined $incoming{$id}) {
			$count++;
			$info{$id} = $incoming{$id};
			push @sorted,$id;
			print STDERR "Add $id => $incoming{$id}\n";
		}
		else {
			$count++;
			print STDERR "Add $id\n";
			push @sorted,$id;
		}
	}
	$self->{info} = \%info;
	$self->{sortedId} = \@sorted;
	return $count,'ID already exist in database';
}

sub saveTo {
	my $self = shift;
	my $output = shift;
	my $comment = shift;
	if(!$self->{info}) {
		return undef,"No id to save";
	}
	open FO,">",$output or return undef,"$!, while writting $output";
	foreach my $fmt (@{$self->{OUTPUT}}) {
		print FO "#OUTPUT: $fmt\n";
	}
	foreach my $id (@{$self->{sortedId}}) {
		#	my $value = $self->{info}->{$id};
		#next unless($value);
		#if($value eq 'TRUE') {
		#	print FO $id,"\n";
		#}
		if($self->{info}->{$id}) {
			print FO $id,"\t",$self->{info}->{$id},"\n";
		}
		else {
			print FO $id,"\n";
		}
	}
	print FO "#$comment\n" if($comment);
	close FO;
	return 1;
}


sub feed {
	my $self = shift;
	my $data = shift;
	my $type = shift(@_) || "";
	if(!$data) {
		if($self->{data}) {
			$data = $self->{data};
		}
		else {
			return undef,"No data supplied";
		}
	}
	my ($r,$msg);
	if(ref $data && $data->{info} && $data->{sortedId}) {
		$r = $data;
	}
	elsif($type eq 'file' or -f $data) {
		$self->{database} = $data;
		($r,$msg) = $self->_parse_from_file($data);
	}
	else {
		($r,$msg) = $self->_parse_from_text($data);
	}
	#use Data::Dumper;die(Data::Dumper->Dump([$r],[qw/$r/]));
	if($r) {
		$self->{info} = $r->{info};
		$self->{sortedId} = $r->{sortedId};
	}
	return undef,$msg unless($self->{info} && $self->{sortedId});
	return $r;
}

sub all {
	my $self = shift;
	return $self->query();
}

sub query {
	my $self = shift;
	my %target;
	my @Id;
	my %info = ();
	my @sortedId = ();
	if($self->{info}) {
		%info = %{$self->{info}};
		@sortedId = @{$self->{sortedId}};
	}
	if(@_) {
	#my $utf8 = find_encoding("utf-8");
	#map $_=$utf8->decode($_),@_;
		my @keys = grep(!/^\s*#/,keys %info);
		QUERY:foreach my $r(@_) {
			foreach my $key (@keys) {
				if($r eq $key) {
					push @Id,$key unless($target{$key});
					$target{$key} = $info{$key};
					next QUERY;
				}
			}
			foreach my $key (@keys) {
				if($r eq $info{$key}) {
					push @Id,$key unless($target{$key});
					$target{$key} = $info{$key};
					next QUERY;
				}
			}
			my $matched = 0;
			foreach my $key (@keys) {
				if($key =~ m/$r/) {
					push @Id,$key unless($target{$key});
					$target{$key} = $info{$key};
					$matched = 1;
				}
			}
			foreach my $key (@keys) {
				if($info{$key} =~ m/$r/) {
					push @Id,$key unless($target{$key});
					$target{$key} = $info{$key};
					$matched = 1;
				}
			}
			foreach my $key (@keys) {
				next if($target{$key});
				if($r =~ m/^(?:$key|$info{$key})\s+/ or $r =~ m/\s+(?:$key|$info{$key})$/) {
					push @Id,$key;
					$target{$key} = $info{$key};
					$matched = 1;
					next QUERY;
				}
			}
			if(!$matched) {
				return undef,"Query [$r] match nothing in database ($self->{database})";
			}
		}
	}
	else {
		%target = %info;
		@Id = grep(!/^\s*#/,@sortedId);
	}
	my @result;
	my @formats = @{$self->{OUTPUT}};
	@formats = ('${KEY}','${VALUE}') unless(@formats);
	foreach my $key (@Id) {
		my $value = $target{$key};
		my @item = ($key,$value);
		foreach my $fmt (@formats) {
			my $output = $fmt;
			$output =~ s/\$\{(?:KEY|ID)\}/$key/g;
			$output =~ s/\$\{(?:VALUE|NAME)\}/$value/g;
			push @item,$output;
		}
		push @result,\@item;
	}
	return 1,@result;
}

1;

__END__
