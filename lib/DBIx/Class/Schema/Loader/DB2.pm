package DBIx::Class::Schema::Loader::DB2;

use strict;
use base 'DBIx::Class::Schema::Loader::Generic';
use Carp;

=head1 NAME

DBIx::Class::Schema::Loader::DB2 - DBIx::Class::Schema::Loader DB2 Implementation.

=head1 SYNOPSIS

  use DBIx::Schema::Class::Loader;

  # $loader is a DBIx::Class::Schema::Loader::DB2
  my $loader = DBIx::Class::Schema::Loader->new(
    dsn       => "dbi:DB2:dbname",
    user      => "myuser",
    password  => "",
    namespace => "Data",
    schema    => "MYSCHEMA",
    dropschema  => 0,
  );

=head1 DESCRIPTION

See L<DBIx::Class::Schema::Loader>.

=cut

sub _db_classes {
    return qw/DBIx::Class::PK::Auto::DB2/;
}

sub _tables {
    my $class = shift;
    my %args = @_; 
    my $db_schema = uc $class->loader_data->{_db_schema};
    my $dbh = $class->storage->dbh;

    # this is split out to avoid version parsing errors...
    my $is_dbd_db2_gte_114 = ( $DBD::DB2::VERSION >= 1.14 );
    my @tables = $is_dbd_db2_gte_114 ? 
    $dbh->tables( { TABLE_SCHEM => '%', TABLE_TYPE => 'TABLE,VIEW' } )
        : $dbh->tables;
    # People who use table or schema names that aren't identifiers deserve
    # what they get.  Still, FIXME?
    s/\"//g for @tables;
    @tables = grep {!/^SYSIBM\./ and !/^SYSCAT\./ and !/^SYSSTAT\./} @tables;
    @tables = grep {/^$db_schema\./} @tables if($db_schema);
    return @tables;
}

sub _table_info {
    my ( $class, $table ) = @_;
#    $|=1;
#    print "_table_info($table)\n";
    my ($db_schema, $tabname) = split /\./, $table, 2;
    # print "DB_Schema: $db_schema, Table: $tabname\n";
    
    # FIXME: Horribly inefficient and just plain evil. (JMM)
    my $dbh = $class->storage->dbh;
    $dbh->{RaiseError} = 1;

    my $sth = $dbh->prepare(<<'SQL') or die;
SELECT c.COLNAME
FROM SYSCAT.COLUMNS as c
WHERE c.TABSCHEMA = ? and c.TABNAME = ?
SQL

    $sth->execute($db_schema, $tabname) or die;
    my @cols = map { lc } map { @$_ } @{$sth->fetchall_arrayref};

    $sth->finish;

    $sth = $dbh->prepare(<<'SQL') or die;
SELECT kcu.COLNAME
FROM SYSCAT.TABCONST as tc
JOIN SYSCAT.KEYCOLUSE as kcu ON tc.constname = kcu.constname
WHERE tc.TABSCHEMA = ? and tc.TABNAME = ? and tc.TYPE = 'P'
SQL

    $sth->execute($db_schema, $tabname) or die;

    my @pri = map { lc } map { @$_ } @{$sth->fetchall_arrayref};

    $sth->finish;
    
    return ( \@cols, \@pri );
}

# Find and setup relationships
sub _relationships {
    my $class = shift;

    my $dbh = $class->storage->dbh;

    my $sth = $dbh->prepare(<<'SQL') or die;
SELECT SR.COLCOUNT, SR.REFTBNAME, SR.PKCOLNAMES, SR.FKCOLNAMES
FROM SYSIBM.SYSRELS SR WHERE SR.TBNAME = ?
SQL

    foreach my $table ( $class->tables ) {
        if ($sth->execute(uc $table)) {
            while(my $res = $sth->fetchrow_arrayref()) {
                my ($colcount, $other, $other_column, $column) =
                    map { $_=lc; s/^\s+//; s/\s+$//; $_; } @$res;
                next if $colcount != 1; # XXX no multi-col FK support yet
                eval { $class->_belongs_to_many( $table, $column, $other,
                  $other_column ) };
                warn qq/\# belongs_to_many failed "$@"\n\n/
                  if $@ && $class->debug_loader;
            }
        }
    }

    $sth->finish;
    $dbh->disconnect;
}

=head1 SEE ALSO

L<DBIx::Class::Schema::Loader>

=cut

1;
