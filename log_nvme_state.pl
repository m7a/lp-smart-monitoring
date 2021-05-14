#!/usr/bin/perl
# Ma_Sys.ma Log NVME State 1.0.0, Copyright (c) 2021 Ma_Sys.ma.
# For further info send an e-mail to Ma_Sys.ma@web.de.

# This script can be invoked to collect SMART data from all installed NVME
# drives and store them in an SQLite database at
# /var/lib/smartmontools/attrlog.*.sqlite. It is intended to run from a timer
# and be evaluated by another program like e.g. `mainfobg2.pl`.

use strict;
use warnings FATAL => 'all';
use autodie;

require JSON; # DEP libjson-perl
require DBI;  # DEP libdbd-sqlite3-perl

use Data::Dumper 'Dumper'; # debug only

my $jsons = `nvme list -o json`;
my @nvmes = @{${JSON::decode_json($jsons)}{Devices}};
for my $nvme (@nvmes) {
	my $id = $nvme->{ModelNumber}."-".$nvme->{SerialNumber};
	$id =~ s/\s+/_/g;
	my $fn = "/var/lib/smartmontools/attrlog.$id.nvme.sqlite";
	my $txc = time();
	$jsons = `nvme smart-log -o json $nvme->{DevicePath}`;
	my $smart = JSON::decode_json($jsons);
	$smart->{data_unit_bytes} = $nvme->{SectorSize};

	my @smartkeys = sort keys %{$smart};

	my $hasdb = (-f $fn);
	my $dbh = DBI->connect("dbi:SQLite:dbname=$fn", "", "");
	if(not $hasdb) {
		# Initialize database
		my $sql = "CREATE TABLE attrlog (".
			"  date   INTEGER      NOT NULL PRIMARY KEY,".
			"  device VARCHAR(128) NOT NULL,".
			"  model  VARCHAR(64)  NOT NULL,".
			"  serial VARCHAR(64)  NOT NULL";
		for my $key (@smartkeys) {
			# Not null constraints fail why?
			$sql .= ",  $key INTEGER NOT NULL";
		}
		$sql .= ");";
		$dbh->do($sql) or die("SQL DB initialization failed.");
	}

	my $stmt = $dbh->prepare(
		"INSERT INTO attrlog (date, device, model, serial, ".(join(", ",
		@smartkeys)).") VALUES (?, ?, ?, ? ".
		((", ?") x scalar(@smartkeys)).");"
	);
	my $i = 1;
	$stmt->bind_param($i++, $txc);
	$stmt->bind_param($i++, $nvme->{DevicePath});
	$stmt->bind_param($i++, $nvme->{ModelNumber});
	$stmt->bind_param($i++, $nvme->{SerialNumber});
	for my $key (@smartkeys) {
		$stmt->bind_param($i++, $smart->{$key});
	}
	$stmt->execute or die("SQL statement failed.");

	$dbh->disconnect;
}
