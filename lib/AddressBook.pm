package AddressBook;

=head1 NAME

AddressBook - Abstract class for using AddressBooks

=head1 SYNOPSIS

  use AddressBook;
  $a = AddressBook->new(source => "LDAP:localhost");
  $b = AddressBook->new(source => "DBI:CSV:f_dir=/tmp/data");
  $c = AddressBook->new(source => "PDB");

  $a->search(name => "hersh");
  $entry = $a->read;
  $b->add($entry);

  $entry = AddressBook::Entry->new(attr=>{name => "dleigh"});
  $c->write($entry);

  AddressBook::sync(master=>$a,slave=>$c);

=head1 DESCRIPTION

AddressBook provides a unified interface to access various databases
for keeping track of contacts.  Included with this module are several
backends:

  AddressBook::DB::LDAP
  AddressBook::DB::LDIF
  AddressBook::DB::DBI
  AddressBook::DB::PDB
  AddressBook::DB::Text
  AddressBook::DB::HTML

More will be added in the future.  

=cut

use strict;
use Carp;
use Date::Manip;
use AddressBook::Entry;
use AddressBook::Config;

use vars qw($VERSION @ISA);

$VERSION = '0.10';

=head2 new
	   
Create a new AddressBook object.

  AddressBook->new(source=$source,\%args)

See the appropriate backend documentation for constructor details.

=cut

sub new {
  my $class = shift;
  my $self;
  my %args = @_; 
  if ($args{config}) {
    $self->{config} = $args{config};
  } else {
    $self->{config} = AddressBook::Config->new(config_file=>$args{config_file});
  }
  if(defined $args{source}) {
    my ($driverName, $dsn) = split(':', $args{source}, 2);
    $dsn = '' unless $dsn; 
    delete $args{source};
    my (%bedb_args,$k,$v);
    foreach ($self->{config}->{db}->{$driverName}, \%args) {
      next if (ref($_) ne "HASH" || ! %{$_} );
      while (($k,$v) = each %{$_}) {
	$bedb_args{$k} = $v;
      }
    }
    eval qq{
      require AddressBook::DB::$driverName;
      \$self = AddressBook::DB::$driverName->new(dsn => "$dsn",
						 config => \$self->{config},
						 \%bedb_args,
						 );
    };
    croak "Couldn't load backend `$driverName': $@" if $@;
  } else {
    bless ($self,$class);
  }
  return $self;
}

=head2 sync

  AddressBook::sync(master=>$master_db, slave=>$slave_db)

Synchronizes the "master" and "slave" databases.  The "master" database type must be
one that supports random-access methods.  The "slave" database type must
be one that supports sequential-access methods.

=over 4

=item 1

For each record in the slave, look for a corresponding record in the master, using
the key_fields of each.

=over 6

=item Z<>

If no match is found, the entry is added to the master.

=item Z<>

If multiple matches are found, an error occurrs.

=item Z<>

If one match is found, then:

=over 8

=item Z<>

If the records match, nothing is done.

=item Z<>

If the records do not match, then:

=over 10

=item Z<>

If the slave record's timestamp is newer, the master's entry is updated with 
the slave entry's data.

=item Z<>

If the master record's timestamp is newer, nothing is done.

=back

=back

=back

=item 2

The slave database is truncated.

=item 3

Each record of the master is added to the slave

=back

Note that deletions made on the slave database are effectively ignored during
synchronization.

=cut

sub sync {
  my %args = @_;
  my $master = $args{master};
  my $slave = $args{slave};
  unless ($master->{key_fields} && $slave->{key_fields}) {
    croak "Key fields must be defined for both master and slave backends";
  }
  $slave->reset;
  my ($entry,$filter,$key,$count,$slave_type,@non_keys,%slave_keys,$master_entry,$flag);
  foreach $key (split ',', $slave->{key_fields}) {
    $slave_keys{$key} = "";
  }
  ($slave_type) = (ref $slave) =~ /\:\:(\w+)$/;
  while ($entry = $slave->read) {
    @non_keys=();
    $filter = AddressBook::Entry->new(config=>$slave->{config},
                                      attr=>$entry->{attr});
    foreach (grep {! exists $slave_keys{$slave->{config}->{generic2db}->{$_}->{$slave_type}}} 
	     keys %{$filter->{attr}}) {
      push @non_keys, $slave->{config}->{generic2db}->{$_}->{$slave_type};
    }
    $filter->delete(db=>$slave_type,attrs=>\@non_keys);
    $count = $master->search(filter=>$filter->{attr},strict=>1);
    if ($args{debug}) {
      print $filter->dump;
      print "matched: $count\n";
    }
    if ($count == 1) {
      $master_entry = $master->read;
      if (AddressBook::Entry::compare($entry,$master_entry)) {
	if ($args{debug}) { print "entries match\n"}
      } else {
	if ($args{debug}) {
	  print "slave entry timestamp: ",$entry->{timestamp},"\n";
	  print "master entry timestamp: ",$master_entry->{timestamp},"\n";
	}
	$flag = Date_Cmp($entry->{timestamp},$master_entry->{timestamp});
	if ($flag < 0) {
	  if ($args{debug}) {print "master is newer\n"}
	} else {
	  if ($args{debug}) {print "slave is newer - updating master\n"}
	  $master->update(entry=>$entry,filter=>$filter->{attr});
	}
      }
    } elsif ($count == 0) {
      if ($args{debug}) {print "Entry not found in master - adding:\n".$entry->dump."\n"}
      $master->add($entry);
    } else {croak "Error: entry matched multiple entries in master!\n"}
  }
  if ($args{debug}) {print "Truncating slave\n"}
  $slave->truncate;
  $master->reset;
  if ($args{debug}) {print "Adding master's records to slave\n"}
  while ($entry = $master->read) {
    $slave->write($entry);
  }
}

=head2 search

  $abook->search(attr=>\%filter);
  while ($entry=$abook->read) {
    print $entry->dump;
  }

\%filter is a list of cannonical attribute/value pairs. 

=cut

sub search {
  my $self = shift;
  my $class = ref $self || croak "Not a method call.";

  carp "Method not implemented."
}

=head2 read

  $entry=$abook->read;

Returns an AddressBook::Entry object

=cut

sub read {
  my $self = shift;
  my $class = ref $self || croak "Not a method call.";

  carp "Method not implemented"
}

=head2 update

  $abook->update(filter=>\%filter,entry=>$entry)

\%filter is a list of cannonical attriute/value pairs used to identify the entry to
be updated.

$entry is an AddressBook::Entry object

=cut

sub update {
  my $self = shift;
  my $class = ref $self || croak "Not a method call.";

  carp "Method not implemented"
}

=head2 add

  $abook->add($entry)

$entry is an AddressBook::Entry object

=cut

sub add {
  my $self = shift;
  my $class = ref $self || croak "Not a method call.";

  carp "Method not implemented"
}

=head2 delete

  $abook->delete($entry)

$entry is an AddressBook::Entry object

=cut

sub delete {
  my $self = shift;
  my $class = ref $self || croak "Not a method call.";

  carp "Method not implemented"
}

=head2 truncate

  $abook->truncate

Removes all records from the database.

=cut

sub truncate {
  my $self = shift;
  my $class = ref $self || croak "Not a method call.";

  carp "Method not implemented"
}
1;
__END__

=head1 AUTHOR

Mark A. Hershberger, <mah@everybody.org>
David L. Leigh, <dleigh@sameasiteverwas.net>

=head1 SEE ALSO

L<AddressBook::Config>
L<AddressBook::Entry>
    
L<AddressBook::DB::LDAP>
L<AddressBook::DB::LDIF>
L<AddressBook::DB::DBI>
L<AddressBook::DB::PDB>
L<AddressBook::DB::Text>
L<AddressBook::DB::HTML>

=cut
