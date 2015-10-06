package CoGe::Builder::SNP::Platypus;

use v5.14;
use warnings;
use strict;

use Carp;
use Data::Dumper;
use File::Spec::Functions qw(catdir catfile);

use CoGe::Accessory::Web;
use CoGe::Accessory::Jex;
use CoGe::Accessory::Utils qw(to_filename);
use CoGe::Core::Storage qw(get_genome_file get_workflow_paths);
use CoGe::Core::Metadata qw(to_annotations);
use CoGe::Builder::CommonTasks;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(build run);
our $CONF = CoGe::Accessory::Web::get_defaults();
our $JEX = CoGe::Accessory::Jex->new( host => $CONF->{JOBSERVER}, port => $CONF->{JOBPORT} );

sub build {
    my $opts = shift;

    # Required arguments
    my $genome = $opts->{genome};
    my $input_file = $opts->{input_file}; # path to bam file
    my $user = $opts->{user};
    my $wid = $opts->{wid};
    my $metadata = $opts->{metadata};
    my $additional_metadata => $opts->{additional_metadata};

    # Setup paths
    my $gid = $genome->id;
    my $FASTA_CACHE_DIR = catdir($CONF->{CACHEDIR}, $gid, "fasta");
    die "ERROR: CACHEDIR not specified in config" unless $FASTA_CACHE_DIR;
    my ($staging_dir, $result_dir) = get_workflow_paths($user->name, $wid);
    my $fasta_file = get_genome_file($gid);
    my $reheader_fasta =  to_filename($fasta_file) . ".reheader.faa";

    my $annotations = generate_additional_metadata();
    my @annotations2 = CoGe::Core::Metadata::to_annotations($additional_metadata);
    push @$annotations, @annotations2;

    my $conf = {
        staging_dir => $staging_dir,
        result_dir  => $result_dir,

        bam         => $input_file,
        fasta       => catfile($FASTA_CACHE_DIR, $reheader_fasta),
        vcf         => catfile($staging_dir, qq[snps.vcf]),

        annotations => $annotations,
        username    => $user->name,
        metadata    => $metadata,
        wid         => $wid,
        gid         => $gid,
        
        method      => 'Platypus'
    };

    # Build the workflow's tasks
    my @tasks;
    push @tasks, create_fasta_reheader_job(
        fasta => $fasta_file,
        reheader_fasta => $reheader_fasta,
        cache_dir => $FASTA_CACHE_DIR
    );

    push @tasks, create_fasta_index_job(
        fasta => catfile($FASTA_CACHE_DIR, $reheader_fasta),
        cache_dir => $FASTA_CACHE_DIR,
    );
    
    push @tasks, create_platypus_job($conf);
    
    my $load_vcf_task = create_load_vcf_job($conf);
    push @tasks, $load_vcf_task;

    return {
        tasks => \@tasks,
        metadata => $annotations,
        done_files => [ $load_vcf_task->{outputs}->[1] ]
    };
}

sub create_platypus_job {
    my $opts = shift;
#    print STDERR "create_platypus_job ", Dumper $opts, "\n";

    # Required arguments
    my $fasta = $opts->{fasta};
    my $bam = $opts->{bam};
    my $vcf = $opts->{vcf};
    my $nCPU = 8; # number of processors to use

    my $fasta_index = qq[$fasta.fai];
    my $PLATYPUS = $CONF->{PLATYPUS} || "Platypus.py";

    return {
        cmd => qq[$PLATYPUS callVariants],
        args =>  [
            ["--bamFiles", $bam, 0],
            ["--refFile", $fasta, 0],
            ["--output", $vcf, 1],
            ["--verbosity", 0, 0],
            ["--nCPU", $nCPU, 0]
        ],
        inputs => [
            $bam,
            $bam . '.bai',
            $fasta,
            $fasta_index,
        ],
        outputs => [
            $vcf,
        ],
        description => "Identifying SNPs using Platypus method ..."
    };
}

sub generate_additional_metadata {
    my @annotations;
    push @annotations, qq{https://genomevolution.org/wiki/index.php/Expression_Analysis_Pipeline||note|Generated by CoGe's RNAseq Analysis Pipeline};
    push @annotations, qq{note|SNPs generated using Platypus method};
    return \@annotations;
}

1;
