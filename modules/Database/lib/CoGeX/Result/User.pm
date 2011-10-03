package CoGeX::Result::User;

# Created by DBIx::Class::Schema::Loader v0.03009 @ 2006-12-01 18:13:38

use strict;
use warnings;

use base 'DBIx::Class::Core';
use Data::Dumper;
=head1 NAME

CoGeX::User

=head1 SYNOPSIS

This object uses the DBIx::Class to define an interface to the C<user> table in the CoGe database.

=head1 DESCRIPTION

Has columns:
C<user_id> (Primary Key)
Type: INT, Default: undef, Nullable: no, Size: 10

C<user_name>
Type: VARCHAR, Default: "", Nullable: no, Size: 10

C<first_name>
Type: VARCHAR, Default: "", Nullable: no, Size: 10

C<last_name>
Type: VARCHAR, Default: "", Nullable: no, Size: 10

C<email>
Type: VARCHAR, Default: undef, Nullable: yes, Size: 50

C<description>
Type: VARCHAR, Default: undef, Nullable: yes, Size: 255

C<passwd>
Type: VARCHAR, Default: "", Nullable: no, Size: 255


Has many CCoGeX::Result::UserSession> via C<user_id>

=head1 USAGE

  use CoGeX;

=head1 METHODS

=cut

__PACKAGE__->table("user");
__PACKAGE__->add_columns(
  "user_id",
  { data_type => "INT", default_value => undef, is_nullable => 0, size => 10 },
  "user_name",
  { data_type => "VARCHAR", default_value => "", is_nullable => 0, size => 10 },
  "first_name",
  { data_type => "VARCHAR", default_value => "", is_nullable => 0, size => 10 },
  "last_name",
  { data_type => "VARCHAR", default_value => "", is_nullable => 0, size => 10 },
  "email",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 50,
  },
  "description",
  {
    data_type => "VARCHAR",
    default_value => undef,
    is_nullable => 1,
    size => 255,
  },
  "passwd",
  { data_type => "VARCHAR", default_value => "", is_nullable => 0, size => 255 },
);
__PACKAGE__->set_primary_key("user_id");
__PACKAGE__->has_many('sessions'=>"CoGeX::Result::UserSession",'user_id');
__PACKAGE__->has_many('works'=>"CoGeX::Result::Work",'user_id');
__PACKAGE__->has_many('workflows'=>"CoGeX::Result::Workflow",'user_id');
__PACKAGE__->has_many('user_group_connectors'=>"CoGeX::Result::UserGroupConnector",'user_id');


################################################ subroutine header begin ##

=head2 generate_passwd

 Usage     : 
 Purpose   : Generates a password based on a hashed string and a salt value.
 Returns   : Hash of password and salt value.
 Argument  : 'passwd' or 'pwd'
 Throws    : None
 Comments  : 

See Also   : check_passwd()

=cut

################################################## subroutine header end ##

sub generate_passwd
{
	my $self = shift;
	my %opts = @_;
	my $pwd = $opts{passwd} || $opts{pwd};
	my $crypt_pwd = crypt( $pwd, "12" );
}



################################################ subroutine header begin ##

=head2 check_passwd

 Usage     : 
 Purpose   : Checks to see if entered password matches user password.
 Returns   : Result of logic test 'eq' between password has from the database and a hash of the user supplied password.
 Argument  : 'passwd' or 'pwd'
 Throws    : None
 Comments  : 

See Also   : generate_passwd()

=cut

################################################## subroutine header end ##

sub check_passwd
{
	my $self = shift;
	my %opts = @_;
	my $pwd = $opts{passwd} || $opts{pwd};
	return crypt($pwd, $self->passwd) eq $self->passwd;
}

sub name
  {
    my $self = shift;
    return $self->user_name(@_);
  }
1;

################################################ subroutine header begin ##

=head2 user_groups

 Usage     : 
 Purpose   : Returns the set of groups a user belongs to
 Returns   : Array of Groups
 Argument  : None
 Throws    : None
 Comments  : 



=cut

################################################## subroutine header end ##


sub user_groups{
	

	my $self = shift;
	
	
	my @user_groups = ();
	
	foreach my $user_group_connector ($self->user_group_connectors()){
	    push (@user_groups,$user_group_connector->group());
	}
	
	return (@user_groups);
}




################################################ subroutine header begin ##

=head2 add_to_group

 Usage     : 
 Purpose   : 
 Returns   : 
 Argument  : Group Name
 Throws    : None
 Comments  : 



=cut

################################################## subroutine header end ##


sub add_to_group(){


    my $self = shift;

    my %opts = @_;
    my $coge = $opts{coge};
    my $group_name = $opts{group_name};
    
    my $group = $coge->ResultSet('UserGroup')->find({name=>$group_name});

    if($group){
	
	

    }

}

=head1 BUGS




################################################ subroutine header begin ##

=head2 private_genomes

 Usage     : 
 Purpose   : Returns the set of private genomes a user has access to
 Returns   : Array of datasets
 Argument  : None
 Throws    : None
 Comments  : 



=cut

################################################## subroutine header end ##


sub private_genomes{
	
	my $self = shift;
	my @private_genomes= ();
	foreach my $group ($self->groups()){
	    push(@private_genomes,$group->private_genomes());
	}
	
	    return @private_genomes;
}


=head1 SUPPORT





=head1 AUTHORS

 Eric Lyons
 Brent Pedersen

=head1 COPYRIGHT

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.


=head1 SEE ALSO

=cut
