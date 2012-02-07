#!/usr/bin/perl -w

use strict;
use Data::Dumper;
use Getopt::Long;
use CoGeX;
use Text::Wrap;
use CGI;
use CoGe::Accessory::Web;
use CoGe::Accessory::SynMap_report;
use IO::Compress::Gzip;
use File::Path;

use vars qw($synfile $coge $DEBUG $join $FORM $P $GZIP $GUNZIP $TAR $conffile $link);


GetOptions (
	    "debug"=>\$DEBUG,
	    "file|f=s"=>\$synfile, # file_name.aligncoords from SynMap
	    "join=i"=>\$join, #is the output sequence going to be joined together using "N"s for gaps.  Set to a number to be true, and whatever number it is will be the number of N's used to join sequence.  
	   "config_file|cf=s"=>\$conffile,
	    "link|l=s"=>\$link,
	   );
$FORM = new CGI;
$synfile = $FORM->param('f') if $FORM->param('f');
$conffile = $FORM->param('cf') if $FORM->param('cf');
$link = $FORM->param('l') if $FORM->param('l');
$join = 100 unless defined $join;
$conffile = $ENV{HOME}."coge.conf" unless -r $conffile;

$P = CoGe::Accessory::Web::get_defaults($conffile);
$GZIP = $P->{GZIP};
$GUNZIP = $P->{GUNZIP};
$TAR = $P->{TAR};

my $DBNAME = $P->{DBNAME};
my $DBHOST = $P->{DBHOST};
my $DBPORT = $P->{DBPORT};
my $DBUSER = $P->{DBUSER};
my $DBPASS = $P->{DBPASS};
my $connstr = "dbi:mysql:dbname=".$DBNAME.";host=".$DBHOST.";port=".$DBPORT;
$coge = CoGeX->connect($connstr, $DBUSER, $DBPASS );

my $synmap_report = new CoGe::Accessory::SynMap_report;
$synfile = gunzip($synfile);
my ($chr1, $chr2, $dsgid1, $dsgid2) = $synmap_report->parse_syn_blocks(file=>$synfile);
gzip($synfile);
($chr1, $chr2, $dsgid1, $dsgid2) = ($chr2, $chr1, $dsgid2, $dsgid1) if scalar keys %{$chr1->[0]} < scalar keys %{$chr2->[0]};
my $dsg1 = $coge->resultset('DatasetGroup')->find($dsgid1);
unless ($dsg1)
  {
    print $FORM->header;
    print "Unable to get genome object for $dsgid1.\n";
    exit;
  }

my $dsg2 = $coge->resultset('DatasetGroup')->find($dsgid2);
unless ($dsg2)
  {
    print $FORM->header;
    print "Unable to get genome object for $dsgid2.\n";
    exit;
  }

my $TEMPDIR = $P->{TEMPDIR}."order_contigs";
$TEMPDIR = $TEMPDIR."/$dsgid1-$dsgid2/";
mkpath($TEMPDIR, 0, 0777);
my $logfile = $TEMPDIR."log.txt";
open (LOG, ">".$logfile);
my $org1 = "Pseudoassembled genome: ". $dsg1->organism->name. "v".$dsg1->version." ".$dsg1->source->[0]->name." ";
$org1 .= $dsg1->name if $dsg1->name;
$org1 .= " (dsgid".$dsg1->id. "): ". $dsg1->genomic_sequence_type->name;
my $org2 .= "Reference genome: ". $dsg2->organism->name. "v".$dsg2->version." ".$dsg2->source->[0]->name." ";
$org2 .= $dsg2->name if $dsg2->name;
$org2 .= " (dsgid".$dsg2->id. "): ". $dsg2->genomic_sequence_type->name;
print LOG $org1,"\n";
print LOG $org2,"\n";
print LOG "Syntenic file: $synfile\n";
print LOG "CoGe configuration file: $conffile\n";
print LOG "Regenerate results: $link\n" if $link;

my $fafile = $TEMPDIR."pseudoassembly.faa";
open (FAA, ">$fafile");
my $AGPfile = $TEMPDIR."agp.txt";
open (AGP, ">$AGPfile");
print AGP qq{# Generated by the comparative genomics platform CoGe
# http://genomevolution.org
# Created by SynMap
};
print AGP "# Regenerate results: $link\n" if $link;

print AGP "# ".$org1,"\n";
print AGP "# ".$org2,"\n";
#my $fn = "pseudoassembly.tar.gz";
#print $FORM->header;
#print qq{Content-Type: text/plain
#print qq{Content-Type: application/force-download
#Content-Disposition: attachemet; filename="$fn"
#};

#print "<pre>";
process_sequence($chr1);
#print "</pre>";
close FAA;
close AGP;

chdir $TEMPDIR;
chdir "..";
my $tarfile .= "$dsgid1-$dsgid2.tar.gz";
my $cmd = $TAR ." -czf " . $tarfile ." ". "$dsgid1-$dsgid2";
print LOG "Compressing directory: $cmd\n";
close LOG;
`$cmd`;
#print $FORM->header;
#print qq{Content-Type: text/plain};
print qq{Content-Type: application/force-download
Content-Disposition: attachment; filename="$tarfile"

};
open (IN, $tarfile);
while (<IN>)
  {
    print $_;
  }
close IN;

sub process_sequence
  {
    my $chrs = shift;
    my %dsg; #store CoGe dataset group objects so we don't have to create them multiple times
    my $count = 0; #number of blocks processed per matched chromosome
    my %out_chrs; #seen chromosomes for printing, let's me know when to start a new fasta sequence
    my %in_chrs; #seen chromosomes coming in, need to use this to identify those pieces that weren't used and to be lumped under "unknown"
    my $seq; #sequence to process and dump
    my $header; #header for sequence;
    my $agp_file; #store the assembly information in an AGP file: http://www.ncbi.nlm.nih.gov/projects/genome/assembly/agp/AGP_Specification.shtml
    my $pos =1;
    my $part_num =1;
    foreach my $item (@$chrs)
      {
	my $chr = $item->{chr};
	my $out_chr = $item->{match};
	my $dsgid = $item->{dsgid};
	unless ($dsgid)
	 {
	  print "Error!  Problem generating sequence.  No genome id specified!";
          return;
         }
	my $dsg = $dsg{$dsgid};
	$dsg = $coge->resultset('DatasetGroup')->find($dsgid) unless $dsg;
	$dsg{$dsg->id} = $dsg;
	my $strand = $item->{rev} ? -1 : 1;
	if ($seq && !$out_chrs{$out_chr})
	  {
	    #we have a new chromosome.  Dump the old and get ready for the new;
	    print_sequence(header=>$header, seq=>$seq);
	    $count=0;
	    $seq=undef;
	    $part_num=1;
	  }
	if ($join)
	  {
	    if ($count)
	      {
		$seq .= "N"x$join;
		print AGP join ("\t", $out_chr, $pos, $pos+$join-1, $part_num, "N", $join, "contig", "no", ""),"\n";
		$pos += $join;
		$part_num++;
	      }
	    else#need to print fasta header
	      {
		$header = "$out_chr";
	      }
	    my $tmp_seq = $dsg->genomic_sequence(chr=>$chr, strand=>$strand);
	    $seq .= $tmp_seq;
	    my $seq_len = length($tmp_seq);
	    my $ori = $strand eq "1" ? "+" : "-";
	    print AGP join ("\t", $out_chr, $pos, $pos+$seq_len-1, $part_num, "W", $chr, 1, $seq_len, $ori),"\n";
	    $part_num++;
	    $pos += $seq_len;
	    $count++;
	    $out_chrs{$out_chr}++;
	    $in_chrs{uc($chr)}++;
	  }
	else
	  {
	    print FAA $dsg->fasta(chr=>$chr);
	  }
      }
    if ($seq)
      {
	print_sequence(header=>$header,seq=>$seq);
      }
    #need to get all the pieces that didn't fit
    $header = "Unknown";
    $seq = undef;
    $count=0;
    $part_num =1;
    $pos =1;
    foreach my $dsg (values %dsg)
      {
	foreach my $chr ($dsg->chromosomes)
	  {
	    next if $in_chrs{uc($chr)};
	    if ($count)
	      {
		$seq .= "N"x$join;
		print AGP join ("\t", $header, $pos, $pos+$join-1, $part_num, "N", $join, "contig", "no", ""),"\n";
		$pos += $join;
		$part_num++;
	      }
	    my $tmp_seq = $dsg->genomic_sequence(chr=>$chr);
	    $seq .= $tmp_seq;
	    my $seq_len = length($tmp_seq);
	    $seq .= $dsg->genomic_sequence(chr=>$chr);
	    print AGP join ("\t", $header, $pos, $pos+$seq_len-1, $part_num, "W", $chr, 1, $seq_len, "+"),"\n";
	    $part_num++;
	    $pos += $seq_len;
	    $count++;
	  }
      }
    print_sequence(header=>$header, seq=>$seq);
  }


sub print_sequence
    {
      my %opts = @_;
      my $header = $opts{header};
      my $seq = $opts{seq};
      $Text::Wrap::columns=80;
      print FAA ">".$header,"\n";
      print FAA wrap('','',$seq),"\n";
    }

sub gzip
    {
      my $file = shift;
      return $file unless $file;
      return $file if $file =~ /\.gz$/;
      return $file.".gz" if -r "$file.gz";
      `$GZIP $file` if -r $file;
      my $tmp = $file.".gz";
      return -r $tmp ? $tmp : $file;
    }

sub gunzip
    {
      my $file = shift;
      return $file unless $file;
      return $file unless $file =~ /\.gz$/;
      `$GUNZIP $file` if -r $file;
      my $tmp = $file;
      $tmp =~ s/\.gz$//;
      return -r $tmp ? $tmp : $file;
    }
