#!/usr/bin/perl

use strict;
use Text::CSV;
use Data::Dumper;

# ---------------------------------------------------------------------------------------
my %nameReplacement = (
    trigger => 'ctrigger',
    type => 'ctype',
    date => 'cdate',
);

my %typeLookup = (
    timestamp => 'TIMESTAMP',
    dayofweek => 'INT',
);

my %bareType = (
    'TIMESTAMP' => 1,
    'INT' => 1,
);

my @indexes = (
    'srcnick',
    'ctype',
);
# ---------------------------------------------------------------------------------------

my $logfile = "log.csv";
my $sqlfile = "log.sql";

my $fh;
open($fh, '<:utf8', $logfile) or die "cannot open $logfile for read\n";

my $sqlfh;
open($sqlfh, '>:utf8', $sqlfile) or die "cannot open $sqlfile for write";

my $csv = new Text::CSV;

my $headers = $csv->getline($fh);
$csv->column_names(@$headers);

my @columns;
for my $header (@$headers)
{
    my $type = $typeLookup{$header} // "VARCHAR(1024)";
    my $colname = $nameReplacement{$header} // $header;
    push(@columns, "$colname $type");
}

print $sqlfh "DROP TABLE facts;\n";

my $sqlCreateTable = "CREATE TABLE facts (\n    " . join(",\n    ", @columns) . "\n) TYPE=innodb;\n";
print $sqlfh $sqlCreateTable;

while(my $row = $csv->getline_hr($fh))
{
    my @vals;
    for my $key (@$headers)
    {
        my $type = $typeLookup{$key};
        my $quote = 1;
        if($type and $bareType{$type})
        {
            $quote = 0;
        }

        my $val = $row->{$key};
        if($quote)
        {
            $val = quote($val);
        }
        push(@vals, $val);
    }

    my $sqlInsert = "INSERT INTO facts VALUES (" . join(",", @vals) . ");\n";
    print $sqlfh $sqlInsert;
}

print $sqlfh "ALTER TABLE facts ADD COLUMN id INT NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST;\n";

for my $index (@indexes)
{
    my $indexName = $index;
    $indexName =~ s/,/_/g;
    my $sqlIndex = "CREATE INDEX $indexName ON facts ($index);\n";
    print $sqlfh $sqlIndex;
}

close($fh);
close($sqlfh);

print "Generated $sqlfile\n";

# ---------------------------------------------------------------------------------------

sub quote
{
    # I am a horrible person for not using DBI::quote

    my($str) = @_;
    $str =~ s/'/''/g;
    $str =~ s/\\/\\\\/g;
    return "'$str'";
}
