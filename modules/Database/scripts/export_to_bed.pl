#!/usr/bin/perl -w

use strict;
use Data::Dumper;
use CoGeX;
use Getopt::Long;

my ($coge, $fasta_name, $name_re, @datasets, $dataset_group);

GetOptions(
	   "fasta_name=s" => \$fasta_name,
	   "name_re=s"=>\$name_re,
	   "dataset_group|dsg=s"=>\$dataset_group,
	   );
  unless ($dataset_group)
  {
    print qq#
Welcome t0 $0

Usage:  $0 -dsg 8120 -fasta_name brachy_v1.fasta > brachy_v1.bed

Options:

 -dataset_group | -dsg                 Datasets to retrieve, either by name or by database id
 -name_re                          -n  OPTIONAL: Regular expression to search for specific feature names
 -fasta_name                           OPTIONAL:  create a fasta file of the sequences

#;
  }

my $connstr = 'dbi:mysql:coge:homer:3306';
$coge = CoGeX->connect($connstr, 'cnssys', 'CnS');

my $DSG = $coge->resultset('DatasetGroup')->resolve($dataset_group);
@datasets = map { $_->dataset_id } $DSG->datasets;

my $chrs = get_locs(\@datasets);
my $schrs = get_sequence(ds=>\@datasets, file_name=>$fasta_name) if $fasta_name;

foreach my $k (keys %$chrs){
    if (! $schrs->{$k}){
        print STDERR "NOTFOUND in seqs:" . $k . "\n";
    }
}
foreach my $k (keys %$schrs){
    if (! $chrs->{$k}){
        print STDERR "NOTFOUND in locs:" . $k . "\n";
    }
}

sub get_sizes {
    my $locs_ref = shift;
    my $n = scalar(@{$locs_ref});
    my $i=0;
    my $s = "";
    for ($i=0;$i<$n; $i += 2){
        $s .= ($locs_ref->[$i + 1] - $locs_ref->[$i]) . ","
    }
    chop $s;
    return $s;
}
sub get_starts {
    my $locs_ref = shift;
    my $start = shift;
    my $s = "";
    for (my $i=0;$i<scalar(@{$locs_ref}); $i += 2){
        $s .= ($locs_ref->[$i] - $start) . ","
    }
    chop $s;
    return $s
}

sub get_locs {

    my $datasets = shift;
    my $SEP = "\t";
    my %chrs;
    foreach my $ds (@$datasets){
        my $dso = $coge->resultset('Dataset')->resolve($ds);
        foreach my $chr ($dso->get_chromosomes){
            $chrs{$chr} = $dso->last_chromosome_position($chr);
        }
    }
    my @chrs = sort { $a cmp $b } keys %chrs;
    my %names = ();
    my %fids = ();
    my $index = 0;

    print "#seqid\tstart\tend\taccn\tscore\tstrand\tthick_start\tthick_end\trgb\tblock_count\tblock_sizes\tblock_starts\n";
    foreach my $chr (@chrs){
        my %seen = ();
        my $gene_rs = $coge->resultset('Feature')->search( {
                  'me.dataset_id' => { 'IN' => $datasets },
                  'me.chromosome' => $chr,
                  'feature_type.name'  =>  'gene' 
                } , { 
                   'prefetch'           => [ 'feature_type', 'feature_names'] 
                  ,'order_by'           => [ 'me.start']
                });

        my %chrs;
        print STDERR "dataset_ids: " . join(",", @$datasets) . ";  chr: $chr\n";
        while(my $g = $gene_rs->next()){
            if ($fids{$g->feature_id}){ next; }
            $fids{$g->feature_id} = 1;
            my @gene_names;
            if($name_re){
                @gene_names = grep { $_->name =~ /$name_re/i } $g->feature_names(); 
            }
            else {
                @gene_names = $g->feature_names(); 
            }
            my $gene_name;
            if (scalar(@gene_names) == 0){
                $gene_name = $g->feature_names()->next()->name;
                print STDERR "not from re:" . $gene_name . "\n";
                print STDERR $name_re . "\n";
            }
            else {
                foreach my $name (@gene_names){
                    $gene_name = $name->name;
                    if (! $names{$gene_name} ){ last; }
                    $gene_name = "";
                }
                
                $gene_name = $gene_names[0]->name;
            }
            if(!$gene_name || $names{$gene_name} ) { next; }
            #if ($index > 100) {print STDERR "breaking at 100\n";return ; }

            $index++;
            my $cds_rs = $coge->resultset('Feature')->search( {
                  'me.dataset_id' => { 'IN' => $datasets },
                  'me.chromosome' => $chr,
                  'feature_names.name' => $gene_name,
                  'feature_type.name'  => 'CDS' 
                } , { 
                    'join' => 'feature_names',
                   'prefetch'           => [ 'feature_type', 'locations'] 
                  ,'order_by'           => [ 'me.start', 'locations.start']
                });


            my $strand = $g->strand == 1 ? '+' : '-';
            my $clean_name = $gene_name;
            $names{$gene_name} = 1;
            $clean_name =~ s/\s+/_/g;


            my $parent = $clean_name;
            my $has_cds = 0;
            my @locs;
            while(my $f = $cds_rs->next()){
                if($fids{$f->feature_id}){ next; }
                $fids{$f->feature_id} = 1;
                $has_cds = 1;
                foreach my $loc ($f->locations()){
                    my $l = scalar(@locs);
                    # dont add exons repeatedly.
                    if ($l > 0 && $locs[$l - 2] == $loc->start && $locs[$l - 1] == $loc->stop){ next; }
                    push(@locs, $loc->start);
                    push(@locs, $loc->stop);
                }
            }


            $chrs{$g->chr} = 1;
            if (scalar(@locs) != 0){
                my @data = ($chr, $g->start, $g->stop, $clean_name, $g->stop - $g->start, $strand, ".", ".", ".", scalar(@locs)/2);
                push(@data, get_sizes(\@locs));
                push(@data, get_starts(\@locs, $g->start));
                my $gstr = join("\t", @data);
                #$gstr .= "\tCDS\t" . join(",", @locs);
                print $gstr . "\n";
                next;
            } 
            my $sub_rs = $coge->resultset('Feature')->search( {
                  'me.dataset_id' => { 'IN' => $datasets },
                  'feature_names.name'  =>  $gene_name
                  , 'feature_type.name'  =>  { 'NOT IN' => ['gene', 'mRNA', 'CDS'] }
                } , { 
                   'join'               => [ 'feature_names'],
                   'prefetch'           => [ 'feature_type', 'locations'] 
                  ,'order_by'           => [ 'me.chromosome', 'me.start']
                });

            undef @locs;
            my $ftype;
            while(my $f = $sub_rs->next()){
                if($fids{$f->feature_id}){ next; }
                $fids{$f->feature_id} = 1;
                $ftype = $f->type->name;
                foreach my $loc ($f->locations()){
                    my $l = scalar(@locs);
                    # dont add exons repeatedly.
                    if ($l > 0 && $locs[$l - 2] == $loc->start && $locs[$l - 1] == $loc->stop){ next; }
                    push(@locs, $loc->start);
                    push(@locs, $loc->stop);
                }
            }
            if ($ftype){
                my @data = ($chr, $g->start, $g->stop, $clean_name, $g->stop - $g->start, $strand, ".", ".", ".", scalar(@locs)/2);
                push(@data, get_sizes(\@locs));
                push(@data, get_starts(\@locs, $g->start));
                my $gstr = join("\t", @data);
                print $gstr . "\n";
                next;
            } 
            # just a gene, no mRNA or CDS
            #print STDERR "BAD $gene_name\t" . $g->type->name . "\t" . $ftype . "\n";
            if (scalar(@locs) > 0){ print STDERR "FIX"; exit(1); }
            my @data = ($chr, $g->start, $g->stop, $clean_name, $g->stop - $g->start, $strand, ".", ".", ".", 1);
            push(@data, get_sizes([$g->start, $g->stop]));
            push(@data, get_starts([$g->start, $g->stop], $g->start));
            my $gstr = join("\t", @data);
            print $gstr . "\n";
        }
    }
    return \%chrs;
}


sub get_sequence {
  my %opts = @_;
  my $datasets = $opts{ds};
  my $file_name = $opts{file_name};
  open(FA, ">", $file_name);
    my %chrs;
    foreach my $ds (@$datasets){
        my $ds = $coge->resultset('Dataset')->resolve($ds);
        my %seen;
        foreach my $chr ($ds->get_chromosomes){
            # TODO: this will break with contigs.
            next if $chr =~ /random/;
            $chrs{$chr} = 1;
            print FA ">$chr\n";
            print FA $ds->get_genomic_sequence(chromosome => $chr) . "\n";
        }
    }
    close FA;
    return \%chrs;
}
