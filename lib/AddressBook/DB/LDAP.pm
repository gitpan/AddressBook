package AddressBook::DB::LDAP;

=head1 NAME

AddressBook::DB::LDAP - Backend for AddressBook to use LDAP.

=head1 SYNOPSIS

  use AddressBook;
  $a = AddressBook->new(source => "LDAP:hostname/ou=People,dc=example,dc=com",
                        username => "user", password => "pass");

=head1 DESCRIPTION

AddressBook::DB::LDAP supports random access backend database methods.

AddressBook::DB::LDAP behavior can be modified using the following options:

=over 4

=item key_fields

A list of LDAP attribute names (not cannonical names) which can be used to
uniquely identify an entry.

=item hostname

The LDAP host to which to connect.

=item base

The base for LDAP queries.

=item objectclass

The objectclass for AddressBook entries.

=item username

An LDAP dn to use for accessing the server.

=item password

=item dn_calculate

A perl expression which, when eval'd returns a valid LDAP "dn" 
(omitting the "base" part of the dn).  Other attributes may be referenced as "$<attr>".  

For example, if LDAP entries have a dn like: "cn=John Doe,mail=jdoe@mail.com", then use
the following:

  dn_calculate="'cn=' . $cn . ',mail=' . $mail"

=back

Any of these options can be specified in the constructor, or in the configuration file.

=cut

use strict;
use Net::LDAP;
use Net::LDAP::Util qw(ldap_error_text);
use AddressBook;
use Date::Manip;
use Carp;
use vars qw(@ISA $VERSION);

$VERSION = '0.10';

@ISA = qw(AddressBook);

=head2 new

The ldap server and hostname may be specified in the constructor in 
in one of two ways: 

=over 4

=item 1

As part of the "source" parameter, for example:

  $a = AddressBook->new(source => "LDAP:localhost/ou=People,dc=example,dc=com");

=item 2

Using the "hostname" and "base" named parameters:

  $a = AddressBook->new(source => "LDAP",
			hostname=>"localhost",
			base=>"o=test"
			);

Like all AddressBook database constructor parameters, the "dsn" and "table" may 
also be specified in the configuration file.

=back

Any of these options can be specified in the constructor, or in the configuration file.

=cut

sub new {
  my $class = shift;
  my $self = {};
  bless ($self,$class);
  my %args = @_;
  foreach (keys %args) {
    $self->{$_} = $args{$_};
  }
  my ($hostname,$base);
  if ($self->{dsn}) {
    ($hostname,$base) = split "/", $self->{dsn};
  }
  $self->{hostname} = $hostname || $self->{hostname};
  $self->{base} = $base || $self->{base};
  if(defined $self->{hostname}) {
    $self->{ldap} = Net::LDAP->new($self->{hostname}, async => 1 || croak $@);
    $self->{ldap}->bind($self->{username}, password => $self->{password});
  }
  return $self;
}

sub search {
  my $self = shift;
  my $class = ref $self || croak "Not a method call.";
  my @ret;
  my %arg = @_;
  my $max_size = $arg{entries} || 0;
  my $max_time = $arg{time} || 0;
  my $strict = $arg{strict} || 0;
  delete $arg{entries};
  delete $arg{time};

  if(defined $arg{filter}) {
    # We have stuff to look for;
    my $entry = AddressBook::Entry->new(attr=>$arg{filter},
					config => $self->{config},
					);
    $entry->calculate;
    $entry = $entry->get(db=>'LDAP',values_only=>'1');
    my ($filter,$value);
    my $evalstring = $strict ? "=" : "~=";
    foreach (keys %{$entry}) { 
      $value = $entry->{$_}->[0];
      $value =~ s/\(/\\(/g;
      $value =~ s/\)/\\)/g;
      $filter .= "(" . $_ . $evalstring . $value . ")";
    }
    $self->{so} = $self->{ldap}->search(base => $self->{base} || '',
				      async => 1,
				      sizelimit => $max_size,
				      timelimit => $max_time,
				      filter => "(&(objectclass=" .
				      $self->{objectclass} .')' .
				      $filter . ')');
    croak ldap_error_text($self->{so}->code) if $self->{so}->code;
  } else {
    # We need to return everything;
    $self->{so} = $self->{ldap}->search(base => $self->{base} || '',
				      async => 1,
				      filter => "objectclass=" . $self->{objectclass});
    croak ldap_error_text($self->{so}->code) if $self->{so}->code;
  }
  return $self->{so}->count;
}

sub read {
  my $self = shift;
  my $class = ref $self || croak "Not a method call";
  if (! defined $self->{so}) {
    $self->reset;  
  } 
  if (defined (my $entry = $self->{so}->shift_entry)) {
    my $attr;
    my $ret = AddressBook::Entry->new(config=>$self->{config});
    foreach $attr ($entry->attributes) {
      if (exists $self->{config}->{db2generic}->{'LDAP'}->{$attr}) {
	$ret->add(db=>'LDAP',attr=>{$attr=>[$entry->get_value($attr)]});
      }
    }
    $ret->{timestamp} = _get_timestamp($entry);
    return $ret;
  }
  return undef;
}

sub _get_timestamp {
  my $entry=shift;
  my $timestamp;
  if ($entry->exists("modifytimestamp")) {
    ($timestamp) = $entry->get_value("modifytimestamp");
  } elsif ($entry->exists("createtimestamp")) {
    ($timestamp) =  $entry->get_value("createtimestamp");
  } else {
    $timestamp="today";
  }
  return ParseDate($timestamp);
}

sub reset {
  my $self = shift;
  my $class = ref $self || croak "Not a method call";
  $self->search;
}

sub update {
  my $self = shift;
  my $class = ref $self || croak "Not a method call";
  my %args = @_;
  my $count = $self->search(filter=>$args{filter},strict=>1);
  if ($count == 0){
    croak "Update Error: filter did not match any entries";
  } elsif ($count > 1) {
    croak "Update Error: filter matched multiple entries";
  }
  my $entry = $args{entry};
  $entry->calculate;
  my $old_entry=$self->read;
  my $dn = $self->_dn_from_entry($entry);
  my $old_dn = $self->_dn_from_entry($old_entry);
  my $result;
  if ($dn ne $old_dn) {
    $result=$self->{ldap}->moddn($old_dn,deleteoldrdn=>1,newrdn=>$dn);
    croak ldap_error_text($result->code) if $result->code;
  }
  my %attr = %{$entry->get(db=>'LDAP',values_only=>'1')};
  $result=$self->{ldap}->modify($dn,replace=>[%attr]);
  croak ldap_error_text($result->code) if $result->code;
}

sub add {
  my $self = shift;
  my $class = ref $self || croak "Not a method call";
  my $entry = shift;

  $entry->calculate;
  my $dn = $self->_dn_from_entry($entry);
  my %attr = %{$entry->get(db=>'LDAP',values_only=>'1')};
  $attr{objectclass} = [$self->{objectclass}];
  my $result = $self->{ldap}->add($dn, attrs => [%attr]);
  croak ldap_error_text($result->code) if $result->code;
  return 1;
}

sub write {
  my $self = shift;
  my $class = ref $self || croak "Not a method call";
  return $self->add(@_);
}

sub delete {
  my $self = shift;
  my $class = ref $self || croak "Not a method call.";
  my $entry=shift;
  $entry->calculate;
  my $dn = $self->_dn_from_entry($entry);
  my $result = $self->{ldap}->delete($dn);
  croak ldap_error_text($result->code) if $result->code;
  return 1;
}

sub _dn_from_entry {
  my $self = shift;
  my $class = ref $self || croak "Not a method call";
  my $entry = shift || croak "Need an entry";
  my ($dn,$dn_calculate);
  my %attr = %{$entry->get(db=>'LDAP',values_only=>'1')};
  ($dn_calculate=$self->{dn_calculate}) =~ s/\$(\w*)/\$attr{$1}->[0]/g;
  eval qq{\$dn = $dn_calculate};
  $dn .= "," . $self->{base};
  return $dn;
}

1;
__END__

=head2 Timestamps

For syncronization purposes, all records are timestamped using the "modifytimestamp"
LDAP attribute.  If the record has no "modifytimestamp", "createtimestamp" is used.
If there is no "createtimestamp", the current time is used.

=head1 AUTHOR

Mark A. Hershberger, <mah@everybody.org>
David L. Leigh, <dleigh@sameasiteverwas.net>

=head1 SEE ALSO

L<AddressBook>,
L<AddressBook::Config>,
L<AddressBook::Entry>.

Net::LDAP

=cut
