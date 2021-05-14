#!/usr/bin/perl
# Ma_Sys.ma SMARTD Evaluation 2.0.0, Copyright (c) 2021 Ma_Sys.ma.
# For further info send an e-mail to Ma_Sys.ma@web.de.

# Sample invocation
# smart_to_table.pl /var/lib/smartmontools/attrlog.*12*.sqlite

use strict;
use warnings FATAL => 'all';
use autodie;

require Text::Table; # DEP libtext-table-perl
require DBI;         # DEP libdbd-sqlite3-perl
require List::Util;  # all

use Data::Dumper 'Dumper'; # debug only

my $DEFAULT_SMARTDDAYS = 7;
my $dbf = $ARGV[0];

my $dbh = DBI->connect("dbi:SQLite:dbname=$dbf", "", "");

# Read Data
my $sql_results = $dbh->selectall_hashref(<<~EOF, "day_of_month");
	SELECT *, strftime("%d", datetime(`date`, 'unixepoch')) AS day_of_month
	FROM   attrlog
	WHERE  date IN (SELECT MAX(`date`) AS maxdate
			FROM   attrlog
			GROUP BY strftime("%d", datetime(`date`, 'unixepoch'))
			ORDER BY maxdate DESC LIMIT $DEFAULT_SMARTDDAYS)
	ORDER BY date ASC;
	EOF

# Get Constant Data
my $anentry = (values %{$sql_results})[0]; # get any entry

# deliberately hide the serial number to avoid privacy issues with shared
# screenshots.
my $devdesc = $anentry->{model}." at ".$anentry->{device};
my $dub = $anentry->{data_unit_bytes};

# Transpose
my @all_days = ({ title => "Attribute", align => "left" });
my %series = ();
for my $key (sort keys %{$sql_results}) {
	push @all_days, { title => sprintf("%02d", $key), align => "left" };
	for my $subkey (keys %{$sql_results->{$key}}) {
		next if(($subkey eq "date")  || ($subkey eq "device") ||
			($subkey eq "model") || ($subkey eq "serial") ||
			($subkey eq "data_unit_bytes"));

		my $value = $sql_results->{$key}->{$subkey};
		if(($subkey eq "data_units_read") ||
					($subkey eq "data_units_written")) {
			$subkey .= " [TiB]";
			$value = sprintf("%.2f", $value/1024/1024/1024 * $dub);
		} elsif($value >= 1_000_000) {
			# switch to scientific notation if it gets too much
			$value = sprintf("%.1e", $value);
			$value =~ tr/+//d;
		}
		$subkey =~ tr/_/ /;
		$series{$subkey} = [] unless defined($series{$subkey});
		push @{$series{$subkey}}, $value;
	}
}

$dbh->disconnect;

# Remove all-zero lines
for my $subkey (keys %series) {
	if(List::Util::all { $_ == 0 } @{$series{$subkey}}) {
		delete $series{$subkey};
	}
}

# Make Table
my $tbl_obj = Text::Table->new(@all_days);
for my $subkey (sort keys %series) {
	$tbl_obj->add(($subkey, @{$series{$subkey}}));
}
print $devdesc."\n";
for my $line ($tbl_obj->table) {
	print $line;
}
