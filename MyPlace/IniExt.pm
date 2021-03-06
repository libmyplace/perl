#!/usr/bin/perl -w
# $Id$
package MyPlace::IniExt;
use strict;
require v5.8.0;
our $VERSION = 'v1.0';
our $DEFAULT_SECTION = undef;
our $DEFINITION = '#define#';
our $COMMENT_EXP = '^\s*(?:#|;)';
our $SECTION_EXP = '^\s*\[(.+?)\]\s*$';
our $SECTION_SEP = '\.';
our $NAMEVALUE_EXP = '^\s*([^=]+?)\s*=\s*(.+?)\s*$';
our $SECTION_SEP_EXP = '\s*([^' . $SECTION_SEP . ']+)\s*';
our $LIST_START_EXP = '^\s*{\s*$';
our $LIST_END_EXP = '^\s*}\s*$';
our $LINE_START_EXP = '^\s*\(\s*$';
our $LINE_END_EXP = '^\s*\)\s*$';
our $ARRAY_NAME_EXP = '^([^\[\]]+)\s*\[(\s*\d+\s*)\]$';
our $HASH_NAME_EXP = '^([^\{\}]+)\s*\{\s*(.+)?\s*\}$';


sub parse_file {
	my @STRINGS;
	foreach(@_) {
		open FI,"<",$_[0] or next;
		push @STRINGS,<FI>;
		close FI;
	}
	return parse_strings(@STRINGS);
}

sub parse_strings {
	my %DATA;
	my %MACRO;
	my $current_section = $DEFAULT_SECTION;
	my $in_list = undef;
	my $in_line = undef;
	my $name = undef;
	my $value = undef;

PROCESS_LINE:
    while(@_) {
		my $line = shift;
        $_ = $line;
        chomp;
		
		#Execute macros
        foreach my $v_name (keys %MACRO) {
#			my $save = $line;
            if(s/#$v_name#/$MACRO{$v_name}/g) {
#				print STDERR "\t$save=>\n$_\n";
				if(m/\n/) {
					unshift @_,split("\n",$_);
					redo PROCESS_LINE;
				}
			}
        }

		#Ignore comments
		if(m/$COMMENT_EXP/) {
			next;
		}

		if(m/$SECTION_EXP/) {
			$current_section = $1;
			$DATA{$current_section} = {} unless($DATA{$current_section});
			next;
		}

		if($in_line && m/$LINE_END_EXP/) {
				$in_line = undef;
				$value = join("\n",@{$value});
				goto SAVE_VALUE;
				next;
		}

		if($in_list && m/$LIST_END_EXP/) {
			$in_list = undef;
			goto SAVE_VALUE;
			next;
		}
		
		if($in_list || $in_line) {
			$_ =~ s/^\s+//;
			$_ =~ s/\s+$//;
			if($value) {
				push @{$value},$_;
			}
			else {
				$value = [$_];
			}
			next;
		}

		if(m/$NAMEVALUE_EXP/) {
			$name = $1;
			$value = $2;
			if((!$in_line) && $value =~ m/$LIST_START_EXP/) {
				$value = [];
				$in_list = 1;
				next;
			}
			elsif((!$in_list) && $value =~ m/$LINE_START_EXP/) {
				$value = [];
				$in_line = 1;
				next;
			}
			elsif($name =~ $ARRAY_NAME_EXP) {
				$name = $1;
				my $array_index = $2;
				if(!$DATA{$current_section}->{$name}) {
					$DATA{$current_section}->{$name} = [];
				}
				$DATA{$current_section}->{$name}->[$array_index] = $value;;
				next;
			}
			elsif($name =~ $HASH_NAME_EXP) {
				$name = $1;
				my $key = $2;
				if(!$DATA{$current_section}->{$name}) {
					$DATA{$current_section}->{$name} = {};
				}
				$DATA{$current_section}->{$name}->{$key}= $value;
				next;
			}
		}
		elsif(m/^\s*(.+?)\s*$/) {
			$name = $1;
			$value = undef;
		}
		else {
			next;
		}

SAVE_VALUE:		
		if($name) {
			my $SE = $SECTION_SEP;
			my $SSE = $SECTION_SEP_EXP;
			if($name =~ m/^$SSE$SE$SSE$SE$SSE(?:$SE*)$/) {
				$DATA{$current_section}->{$1}->{$2}->{$3} = $value;
			}
			elsif($name =~ m/^$SSE$SE$SSE(?:$SE*)$/) {
				$DATA{$current_section}->{$1}->{$2} = $value;
			}
			else {
				$DATA{$current_section}->{$name} = $value;
			}
			if($current_section eq $DEFINITION) {
				$MACRO{$name} = $value;
		#		print STDERR "\t$name=>$value\n";
			}
		}
    }
	if($in_line || $in_list) {
		goto SAVE_VALUE;
	}
	return %DATA;
}
1;
