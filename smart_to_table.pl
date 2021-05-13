#!/usr/bin/perl
# Ma_Sys.ma SMARTD Evaluation 2.0.0, Copyright (c) 2021 Ma_Sys.ma.
# For further info send an e-mail to Ma_Sys.ma@web.de.

# Sample invocation
# smart_to_table.pl /var/lib/smartmontools/attrlog.*7V*.ata.csv

use strict;
use warnings FATAL => 'all';
use autodie;

require Text::CSV;   # DEP libtext-csv-perl
require Text::Table; # DEP libtext-table-perl
require List::Util;  # all

use Data::Dumper 'Dumper'; # debug only

my $DEFAULT_SMARTDDAYS = 8;

my $file = $ARGV[0];

# Fill a ring buffer with the last entries
# ----------------------------------------

my $lastday     = "";
my $cursor      = 0;
my $first_round = 1;
my @buf         = ();

my $csv = Text::CSV->new({ binary => 1, sep_char => "\t" });
open my $fd, "<:encoding(UTF-8)", $file;
while(my $row = $csv->getline($fd)) {
	my $curday = substr($row->[0], 0, index($row->[0], " "));
	if($curday eq $lastday) {
		# Update stored data for the day.
		$buf[$cursor] = $row;
	} else {
		$cursor++;
		if($cursor >= $DEFAULT_SMARTDDAYS) {
			$cursor = 0;
			$first_round = 0 if($first_round);
		}
		if($first_round) {
			push @buf, $row;
		} else {
			$buf[$cursor] = $row;
		}
	}
	$lastday = $curday;
}
close $fd;

# Transpose
# ---------

my @all_days = ("Attribute"); # prepare table headings
my %value_series_by_attributes = ();

my $idx_first_entry;
my $idx_last_entry_incl;
if($first_round) {
	$idx_first_entry     = 0;
	$idx_last_entry_incl = $cursor;
} else {
	$idx_first_entry     = $cursor + 1;
	$idx_last_entry_incl = $cursor;
	$idx_first_entry     = 0 if($idx_first_entry >= $DEFAULT_SMARTDDAYS);
}

$csv = Text::CSV->new({ binary => 1, sep_char => ";" });

my $i = $idx_first_entry;
do {
	$i = 0 if($i >= $DEFAULT_SMARTDDAYS);

	my $day_entry = $buf[$i];
	my $day_date = $day_entry->[0];
	$day_date =~ /^\d+-\d+-(\d+) \d+:\d+:\d+;?$/ or
					die("Mismatching date: <$day_date>");
	push @all_days, $1;

	# process attributes
	for(my $j = 1; $j < scalar @{$day_entry}; $j++) {
		$csv->parse($day_entry->[$j]);
		my @values = $csv->fields(); # id, normalized, raw
		my $key = $values[0];
		if(defined($value_series_by_attributes{$key})) {
			push @{$value_series_by_attributes{$key}},
						[$values[1], $values[2]];
		} else {
			$value_series_by_attributes{$key} =
						[[$values[1], $values[2]]];
		}
	}
} while($i++ != $idx_last_entry_incl);

# Clean: Remove all lines of only [100,0], [200,0]
# ------------------------------------------------

for my $key (keys %value_series_by_attributes) {
	my @series = @{$value_series_by_attributes{$key}};
	if(List::Util::all { ($_->[0] == 100 || $_->[0] == 200) and
						$_->[1] == 0 } @series) {
		delete $value_series_by_attributes{$key};
		next;
	}
	my $normuniq = $series[0]->[0];
	my $rawuniq  = $series[0]->[1];
	for my $entry (@series) {
		$normuniq = -1 if($entry->[0] ne $normuniq);
		$rawuniq  = -1 if($entry->[1] ne $rawuniq);

		last unless($normuniq != -1 || $rawuniq != -1);
	}
	my @newseries;
	if(($normuniq != -1 && $rawuniq != -1) ||
					($normuniq == -1 && $rawuniq == -1)) {
		# both values are identical or different, output both
		@newseries = map { $_->[0].":".$_->[1] } @series;
	} elsif($normuniq == -1) {
		# means we output normal values
		@newseries = map { $_->[0] } @series;
	} else {
		# means we output raw values
		@newseries = map { $_->[1] } @series;
	}
	# Now shorten to 7 chars if too long entries exist
	@newseries = map { (length($_) > 6)? substr($_, 0, 2)."~".
						substr($_, -3): $_ } @newseries;
	$value_series_by_attributes{$key} = [@newseries];
}

# Make Table
# ----------

my $tbl_obj = Text::Table->new(@all_days);
for my $key (sort { $a <=> $b } keys %value_series_by_attributes) {
	# TODO ASTAT THE KEY NUMERIC IS NOT VERY GOOD. NEED TO GET A HUMAN READABLE VARIANT. MY IDEA: EITHER GET THE DATA FROM MONIT WHICH HAS REGULAR HUMAN READABLE VALUES OR SUPPLY A .sample file in /var/lib/smartmontools that the user has to create once for the attribute's names to be found? Reading it from the C struct directly seems to be complicated.
	$tbl_obj->add(($key, @{$value_series_by_attributes{$key}}));
}

for my $line ($tbl_obj->table) {
	print $line;
}
