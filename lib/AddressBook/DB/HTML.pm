package AddressBook::DB::HTML;

=head1 NAME

AddressBook::DB::HTML - Backend for AddressBook to print entries in HTML format

=head1 SYNOPSIS

  use AddressBook;
  $a = AddressBook->new(source => "HTML");
  $a->write($entry);

=head1 DESCRIPTION

AddressBook::DB::HTML currently supports only the sequential write method.  

=cut
use strict;
use AddressBook;
use Carp;
use File::Basename;
use vars qw($VERSION @ISA);

$VERSION = '0.10';

@ISA = qw(AddressBook);

sub write {
  my $self = shift;
  my $class = ref $self || croak "Not a method call";
  my $entry = shift;
  my @keys;
  my @ret;

  $entry = $entry->get(db=>'HTML');
  if (@_) {
    @keys = @_;
  } else {
    @keys = keys %{$entry};
  }

  foreach (sort {$entry->{$a}->{meta}->{order} 
		 <=> $entry->{$b}->{meta}->{order}} 
	   @keys) {
    next unless defined $entry->{$_}->{value}->[0];
    if($entry->{$_}->{meta}->{type} eq "file") {
    } elsif($entry->{$_}->{meta}->{type} eq "labeleduri") {
      push @ret, ("<tr><td><b>" .
		  $_ .
		  "</b></td><td>" .
		  join ("<br>",@{$entry->{$_}->{value}}) . "</td></tr>");
    } elsif($entry->{$_}->{meta}->{type} eq "textlist") {
      push @ret, ("<tr><td><b>" .
		  $_ .
		  "</b></td><td>" .
		  join ("<br>",@{$entry->{$_}->{value}}) . "</td></tr>");
    } elsif($entry->{$_}->{meta}->{type} eq "textbox") {
      push @ret, ("<tr><td><b>" .
		  $_ .
		  "</b></td><td>" .
		  join ("<br>",@{$entry->{$_}->{value}}) . "</td></tr>");
    } else {
      push @ret, ("<tr><td><b>" .
		  $_ .
		  "</b></td><td>" .
		  join ("<br>",@{$entry->{$_}->{value}}) . "</td></tr>");
    }
  }
  return "<table>\n" . join("\n", @ret) . "\n</table>\n";
}

sub entry_form {
  my $self = shift;
  my $class = ref $self || croak "Not a method call";
  my $entry = shift;
  my @keys;
  my @ret;
  $entry = $entry->get(db=>'HTML');
  if (@_) {
    @keys = @_;
  } else {
    @keys = keys %{$entry};
  }
  foreach (sort {$entry->{$a}->{meta}->{order} 
		 <=> $entry->{$b}->{meta}->{order}} 
	   @keys) {
    next unless defined $entry->{$_}->{value}->[0];
    if($entry->{$_}->{meta}->{type} eq "file") {
    } elsif($entry->{$_}->{meta}->{type} eq "labeleduri") {
      push @ret, ("<tr><td>" .
		  $_ .
		  "</td><td>" .
		  $entry->{$_}->{value}->[0] . "</td></tr>");
    } elsif($entry->{$_}->{meta}->{type} eq "textlist") {
      push @ret, ("<tr><td>" .
		  $_ .
		  "</td><td>" .
		  join("<br>\n", $entry->{$_}->{value}) . "</td></tr>");
    } elsif($entry->{$_}->{meta}->{type} eq "textbox") {
      push @ret, ("<tr><td>" .
		  $_ .
		  "</td><td><input type=textarea rows=\"10\" columns=\"30\" name=\"$_\" value=\"" .
		  $entry->{$_}->{value}->[0] . "\"></td></tr>");
    } else {
      push @ret, ("<tr><td>" .
		  $_ .
		  "</td><td><input type=text name=\"$_\" value=\"" .
		  $entry->{$_}->{value}->[0] . "\"></td></tr>");
    }
  }
  return "<table>\n" . join("\n", @ret) . "</table>\n";
}

sub read_from_args {
  my $self = shift;
  my $class = ref $self || croak "Not a method call";
  my $r = shift;
}
1;
__END__

=head1 AUTHOR

Mark A. Hershberger, <mah@everybody.org>
David L. Leigh, <dleigh@sameasiteverwas.net>

=head1 SEE ALSO

L<AddressBook>,
L<AddressBook::Config>,
L<AddressBook::Entry>.

=cut
