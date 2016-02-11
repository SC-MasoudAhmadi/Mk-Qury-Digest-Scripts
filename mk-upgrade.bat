@rem = '--*-Perl-*--
@echo off
if "%OS%" == "Windows_NT" goto WinNT
perl -x -S "%0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofperl
:WinNT
perl -x -S %0 %*
if NOT "%COMSPEC%" == "%SystemRoot%\system32\cmd.exe" goto endofperl
if %errorlevel% == 9009 echo You do not have Perl in your PATH.
if errorlevel 1 goto script_failed_so_exit_with_non_zero_val 2>nul
goto endofperl
@rem ';
#!/usr/bin/env perl
#line 15

# This program is copyright 2009-2011 Percona Inc.
# Feedback and improvements are welcome.
#
# THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
# WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
# systems, you can issue `man perlgpl' or `man perlartistic' to read these
# licenses.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 59 Temple
# Place, Suite 330, Boston, MA  02111-1307  USA.

use strict;
use warnings FATAL => 'all';

our $VERSION = '0.9.8';
our $DISTRIB = '7540';
our $SVN_REV = sprintf("%d", (q$Revision: 7531 $ =~ m/(\d+)/g, 0));

# ###########################################################################
# DSNParser package 7388
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/DSNParser.pm
#   trunk/common/t/DSNParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package DSNParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 0;
$Data::Dumper::Quotekeys = 0;

eval {
   require DBI;
};
my $have_dbi = $EVAL_ERROR ? 0 : 1;


sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(opts) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      opts => {}  # h, P, u, etc.  Should come from DSN OPTIONS section in POD.
   };
   foreach my $opt ( @{$args{opts}} ) {
      if ( !$opt->{key} || !$opt->{desc} ) {
         die "Invalid DSN option: ", Dumper($opt);
      }
      MKDEBUG && _d('DSN option:',
         join(', ',
            map { "$_=" . (defined $opt->{$_} ? ($opt->{$_} || '') : 'undef') }
               keys %$opt
         )
      );
      $self->{opts}->{$opt->{key}} = {
         dsn  => $opt->{dsn},
         desc => $opt->{desc},
         copy => $opt->{copy} || 0,
      };
   }
   return bless $self, $class;
}

sub prop {
   my ( $self, $prop, $value ) = @_;
   if ( @_ > 2 ) {
      MKDEBUG && _d('Setting', $prop, 'property');
      $self->{$prop} = $value;
   }
   return $self->{$prop};
}

sub parse {
   my ( $self, $dsn, $prev, $defaults ) = @_;
   if ( !$dsn ) {
      MKDEBUG && _d('No DSN to parse');
      return;
   }
   MKDEBUG && _d('Parsing', $dsn);
   $prev     ||= {};
   $defaults ||= {};
   my %given_props;
   my %final_props;
   my $opts = $self->{opts};

   foreach my $dsn_part ( split(/,/, $dsn) ) {
      if ( my ($prop_key, $prop_val) = $dsn_part =~  m/^(.)=(.*)$/ ) {
         $given_props{$prop_key} = $prop_val;
      }
      else {
         MKDEBUG && _d('Interpreting', $dsn_part, 'as h=', $dsn_part);
         $given_props{h} = $dsn_part;
      }
   }

   foreach my $key ( keys %$opts ) {
      MKDEBUG && _d('Finding value for', $key);
      $final_props{$key} = $given_props{$key};
      if (   !defined $final_props{$key}
           && defined $prev->{$key} && $opts->{$key}->{copy} )
      {
         $final_props{$key} = $prev->{$key};
         MKDEBUG && _d('Copying value for', $key, 'from previous DSN');
      }
      if ( !defined $final_props{$key} ) {
         $final_props{$key} = $defaults->{$key};
         MKDEBUG && _d('Copying value for', $key, 'from defaults');
      }
   }

   foreach my $key ( keys %given_props ) {
      die "Unknown DSN option '$key' in '$dsn'.  For more details, "
            . "please use the --help option, or try 'perldoc $PROGRAM_NAME' "
            . "for complete documentation."
         unless exists $opts->{$key};
   }
   if ( (my $required = $self->prop('required')) ) {
      foreach my $key ( keys %$required ) {
         die "Missing required DSN option '$key' in '$dsn'.  For more details, "
               . "please use the --help option, or try 'perldoc $PROGRAM_NAME' "
               . "for complete documentation."
            unless $final_props{$key};
      }
   }

   return \%final_props;
}

sub parse_options {
   my ( $self, $o ) = @_;
   die 'I need an OptionParser object' unless ref $o eq 'OptionParser';
   my $dsn_string
      = join(',',
          map  { "$_=".$o->get($_); }
          grep { $o->has($_) && $o->get($_) }
          keys %{$self->{opts}}
        );
   MKDEBUG && _d('DSN string made from options:', $dsn_string);
   return $self->parse($dsn_string);
}

sub as_string {
   my ( $self, $dsn, $props ) = @_;
   return $dsn unless ref $dsn;
   my %allowed = $props ? map { $_=>1 } @$props : ();
   return join(',',
      map  { "$_=" . ($_ eq 'p' ? '...' : $dsn->{$_})  }
      grep { defined $dsn->{$_} && $self->{opts}->{$_} }
      grep { !$props || $allowed{$_}                   }
      sort keys %$dsn );
}

sub usage {
   my ( $self ) = @_;
   my $usage
      = "DSN syntax is key=value[,key=value...]  Allowable DSN keys:\n\n"
      . "  KEY  COPY  MEANING\n"
      . "  ===  ====  =============================================\n";
   my %opts = %{$self->{opts}};
   foreach my $key ( sort keys %opts ) {
      $usage .= "  $key    "
             .  ($opts{$key}->{copy} ? 'yes   ' : 'no    ')
             .  ($opts{$key}->{desc} || '[No description]')
             . "\n";
   }
   $usage .= "\n  If the DSN is a bareword, the word is treated as the 'h' key.\n";
   return $usage;
}

sub get_cxn_params {
   my ( $self, $info ) = @_;
   my $dsn;
   my %opts = %{$self->{opts}};
   my $driver = $self->prop('dbidriver') || '';
   if ( $driver eq 'Pg' ) {
      $dsn = 'DBI:Pg:dbname=' . ( $info->{D} || '' ) . ';'
         . join(';', map  { "$opts{$_}->{dsn}=$info->{$_}" }
                     grep { defined $info->{$_} }
                     qw(h P));
   }
   else {
      $dsn = 'DBI:mysql:' . ( $info->{D} || '' ) . ';'
         . join(';', map  { "$opts{$_}->{dsn}=$info->{$_}" }
                     grep { defined $info->{$_} }
                     qw(F h P S A))
         . ';mysql_read_default_group=client';
   }
   MKDEBUG && _d($dsn);
   return ($dsn, $info->{u}, $info->{p});
}

sub fill_in_dsn {
   my ( $self, $dbh, $dsn ) = @_;
   my $vars = $dbh->selectall_hashref('SHOW VARIABLES', 'Variable_name');
   my ($user, $db) = $dbh->selectrow_array('SELECT USER(), DATABASE()');
   $user =~ s/@.*//;
   $dsn->{h} ||= $vars->{hostname}->{Value};
   $dsn->{S} ||= $vars->{'socket'}->{Value};
   $dsn->{P} ||= $vars->{port}->{Value};
   $dsn->{u} ||= $user;
   $dsn->{D} ||= $db;
}

sub get_dbh {
   my ( $self, $cxn_string, $user, $pass, $opts ) = @_;
   $opts ||= {};
   my $defaults = {
      AutoCommit         => 0,
      RaiseError         => 1,
      PrintError         => 0,
      ShowErrorStatement => 1,
      mysql_enable_utf8 => ($cxn_string =~ m/charset=utf8/i ? 1 : 0),
   };
   @{$defaults}{ keys %$opts } = values %$opts;

   if ( $opts->{mysql_use_result} ) {
      $defaults->{mysql_use_result} = 1;
   }

   if ( !$have_dbi ) {
      die "Cannot connect to MySQL because the Perl DBI module is not "
         . "installed or not found.  Run 'perl -MDBI' to see the directories "
         . "that Perl searches for DBI.  If DBI is not installed, try:\n"
         . "  Debian/Ubuntu  apt-get install libdbi-perl\n"
         . "  RHEL/CentOS    yum install perl-DBI\n"
         . "  OpenSolaris    pgk install pkg:/SUNWpmdbi\n";

   }

   my $dbh;
   my $tries = 2;
   while ( !$dbh && $tries-- ) {
      MKDEBUG && _d($cxn_string, ' ', $user, ' ', $pass, ' {',
         join(', ', map { "$_=>$defaults->{$_}" } keys %$defaults ), '}');

      eval {
         $dbh = DBI->connect($cxn_string, $user, $pass, $defaults);

         if ( $cxn_string =~ m/mysql/i ) {
            my $sql;

            $sql = 'SELECT @@SQL_MODE';
            MKDEBUG && _d($dbh, $sql);
            my ($sql_mode) = $dbh->selectrow_array($sql);

            $sql = 'SET @@SQL_QUOTE_SHOW_CREATE = 1'
                 . '/*!40101, @@SQL_MODE=\'NO_AUTO_VALUE_ON_ZERO'
                 . ($sql_mode ? ",$sql_mode" : '')
                 . '\'*/';
            MKDEBUG && _d($dbh, $sql);
            $dbh->do($sql);

            if ( my ($charset) = $cxn_string =~ m/charset=(\w+)/ ) {
               $sql = "/*!40101 SET NAMES $charset*/";
               MKDEBUG && _d($dbh, ':', $sql);
               $dbh->do($sql);
               MKDEBUG && _d('Enabling charset for STDOUT');
               if ( $charset eq 'utf8' ) {
                  binmode(STDOUT, ':utf8')
                     or die "Can't binmode(STDOUT, ':utf8'): $OS_ERROR";
               }
               else {
                  binmode(STDOUT) or die "Can't binmode(STDOUT): $OS_ERROR";
               }
            }

            if ( $self->prop('set-vars') ) {
               $sql = "SET " . $self->prop('set-vars');
               MKDEBUG && _d($dbh, ':', $sql);
               $dbh->do($sql);
            }
         }
      };
      if ( !$dbh && $EVAL_ERROR ) {
         MKDEBUG && _d($EVAL_ERROR);
         if ( $EVAL_ERROR =~ m/not a compiled character set|character set utf8/ ) {
            MKDEBUG && _d('Going to try again without utf8 support');
            delete $defaults->{mysql_enable_utf8};
         }
         elsif ( $EVAL_ERROR =~ m/locate DBD\/mysql/i ) {
            die "Cannot connect to MySQL because the Perl DBD::mysql module is "
               . "not installed or not found.  Run 'perl -MDBD::mysql' to see "
               . "the directories that Perl searches for DBD::mysql.  If "
               . "DBD::mysql is not installed, try:\n"
               . "  Debian/Ubuntu  apt-get install libdbd-mysql-perl\n"
               . "  RHEL/CentOS    yum install perl-DBD-MySQL\n"
               . "  OpenSolaris    pgk install pkg:/SUNWapu13dbd-mysql\n";
         }
         if ( !$tries ) {
            die $EVAL_ERROR;
         }
      }
   }

   MKDEBUG && _d('DBH info: ',
      $dbh,
      Dumper($dbh->selectrow_hashref(
         'SELECT DATABASE(), CONNECTION_ID(), VERSION()/*!50038 , @@hostname*/')),
      'Connection info:',      $dbh->{mysql_hostinfo},
      'Character set info:',   Dumper($dbh->selectall_arrayref(
                     'SHOW VARIABLES LIKE "character_set%"', { Slice => {}})),
      '$DBD::mysql::VERSION:', $DBD::mysql::VERSION,
      '$DBI::VERSION:',        $DBI::VERSION,
   );

   return $dbh;
}

sub get_hostname {
   my ( $self, $dbh ) = @_;
   if ( my ($host) = ($dbh->{mysql_hostinfo} || '') =~ m/^(\w+) via/ ) {
      return $host;
   }
   my ( $hostname, $one ) = $dbh->selectrow_array(
      'SELECT /*!50038 @@hostname, */ 1');
   return $hostname;
}

sub disconnect {
   my ( $self, $dbh ) = @_;
   MKDEBUG && $self->print_active_handles($dbh);
   $dbh->disconnect;
}

sub print_active_handles {
   my ( $self, $thing, $level ) = @_;
   $level ||= 0;
   printf("# Active %sh: %s %s %s\n", ($thing->{Type} || 'undef'), "\t" x $level,
      $thing, (($thing->{Type} || '') eq 'st' ? $thing->{Statement} || '' : ''))
      or die "Cannot print: $OS_ERROR";
   foreach my $handle ( grep {defined} @{ $thing->{ChildHandles} } ) {
      $self->print_active_handles( $handle, $level + 1 );
   }
}

sub copy {
   my ( $self, $dsn_1, $dsn_2, %args ) = @_;
   die 'I need a dsn_1 argument' unless $dsn_1;
   die 'I need a dsn_2 argument' unless $dsn_2;
   my %new_dsn = map {
      my $key = $_;
      my $val;
      if ( $args{overwrite} ) {
         $val = defined $dsn_1->{$key} ? $dsn_1->{$key} : $dsn_2->{$key};
      }
      else {
         $val = defined $dsn_2->{$key} ? $dsn_2->{$key} : $dsn_1->{$key};
      }
      $key => $val;
   } keys %{$self->{opts}};
   return \%new_dsn;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End DSNParser package
# ###########################################################################

# ###########################################################################
# MySQLDump package 6345
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/MySQLDump.pm
#   trunk/common/t/MySQLDump.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package MySQLDump;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

( our $before = <<'EOF') =~ s/^   //gm;
   /*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
   /*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
   /*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
   /*!40101 SET NAMES utf8 */;
   /*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
   /*!40103 SET TIME_ZONE='+00:00' */;
   /*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
   /*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
   /*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
   /*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
EOF

( our $after = <<'EOF') =~ s/^   //gm;
   /*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;
   /*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
   /*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
   /*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
   /*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
   /*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
   /*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
   /*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;
EOF

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      cache => 0,  # Afaik no script uses this cache any longer because
   };
   return bless $self, $class;
}

sub dump {
   my ( $self, $dbh, $quoter, $db, $tbl, $what ) = @_;

   if ( $what eq 'table' ) {
      my $ddl = $self->get_create_table($dbh, $quoter, $db, $tbl);
      return unless $ddl;
      if ( $ddl->[0] eq 'table' ) {
         return $before
            . 'DROP TABLE IF EXISTS ' . $quoter->quote($tbl) . ";\n"
            . $ddl->[1] . ";\n";
      }
      else {
         return 'DROP TABLE IF EXISTS ' . $quoter->quote($tbl) . ";\n"
            . '/*!50001 DROP VIEW IF EXISTS '
            . $quoter->quote($tbl) . "*/;\n/*!50001 "
            . $self->get_tmp_table($dbh, $quoter, $db, $tbl) . "*/;\n";
      }
   }
   elsif ( $what eq 'triggers' ) {
      my $trgs = $self->get_triggers($dbh, $quoter, $db, $tbl);
      if ( $trgs && @$trgs ) {
         my $result = $before . "\nDELIMITER ;;\n";
         foreach my $trg ( @$trgs ) {
            if ( $trg->{sql_mode} ) {
               $result .= qq{/*!50003 SET SESSION SQL_MODE='$trg->{sql_mode}' */;;\n};
            }
            $result .= "/*!50003 CREATE */ ";
            if ( $trg->{definer} ) {
               my ( $user, $host )
                  = map { s/'/''/g; "'$_'"; }
                    split('@', $trg->{definer}, 2);
               $result .= "/*!50017 DEFINER=$user\@$host */ ";
            }
            $result .= sprintf("/*!50003 TRIGGER %s %s %s ON %s\nFOR EACH ROW %s */;;\n\n",
               $quoter->quote($trg->{trigger}),
               @{$trg}{qw(timing event)},
               $quoter->quote($trg->{table}),
               $trg->{statement});
         }
         $result .= "DELIMITER ;\n\n/*!50003 SET SESSION SQL_MODE=\@OLD_SQL_MODE */;\n\n";
         return $result;
      }
      else {
         return undef;
      }
   }
   elsif ( $what eq 'view' ) {
      my $ddl = $self->get_create_table($dbh, $quoter, $db, $tbl);
      return '/*!50001 DROP TABLE IF EXISTS ' . $quoter->quote($tbl) . "*/;\n"
         . '/*!50001 DROP VIEW IF EXISTS ' . $quoter->quote($tbl) . "*/;\n"
         . '/*!50001 ' . $ddl->[1] . "*/;\n";
   }
   else {
      die "You didn't say what to dump.";
   }
}

sub _use_db {
   my ( $self, $dbh, $quoter, $new ) = @_;
   if ( !$new ) {
      MKDEBUG && _d('No new DB to use');
      return;
   }
   my $sql = 'USE ' . $quoter->quote($new);
   MKDEBUG && _d($dbh, $sql);
   $dbh->do($sql);
   return;
}

sub get_create_table {
   my ( $self, $dbh, $quoter, $db, $tbl ) = @_;
   if ( !$self->{cache} || !$self->{tables}->{$db}->{$tbl} ) {
      my $sql = '/*!40101 SET @OLD_SQL_MODE := @@SQL_MODE, '
         . q{@@SQL_MODE := REPLACE(REPLACE(@@SQL_MODE, 'ANSI_QUOTES', ''), ',,', ','), }
         . '@OLD_QUOTE := @@SQL_QUOTE_SHOW_CREATE, '
         . '@@SQL_QUOTE_SHOW_CREATE := 1 */';
      MKDEBUG && _d($sql);
      eval { $dbh->do($sql); };
      MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
      $self->_use_db($dbh, $quoter, $db);
      $sql = "SHOW CREATE TABLE " . $quoter->quote($db, $tbl);
      MKDEBUG && _d($sql);
      my $href;
      eval { $href = $dbh->selectrow_hashref($sql); };
      if ( $EVAL_ERROR ) {
         warn "Failed to $sql.  The table may be damaged.\nError: $EVAL_ERROR";
         return;
      }

      $sql = '/*!40101 SET @@SQL_MODE := @OLD_SQL_MODE, '
         . '@@SQL_QUOTE_SHOW_CREATE := @OLD_QUOTE */';
      MKDEBUG && _d($sql);
      $dbh->do($sql);
      my ($key) = grep { m/create table/i } keys %$href;
      if ( $key ) {
         MKDEBUG && _d('This table is a base table');
         $self->{tables}->{$db}->{$tbl} = [ 'table', $href->{$key} ];
      }
      else {
         MKDEBUG && _d('This table is a view');
         ($key) = grep { m/create view/i } keys %$href;
         $self->{tables}->{$db}->{$tbl} = [ 'view', $href->{$key} ];
      }
   }
   return $self->{tables}->{$db}->{$tbl};
}

sub get_columns {
   my ( $self, $dbh, $quoter, $db, $tbl ) = @_;
   MKDEBUG && _d('Get columns for', $db, $tbl);
   if ( !$self->{cache} || !$self->{columns}->{$db}->{$tbl} ) {
      $self->_use_db($dbh, $quoter, $db);
      my $sql = "SHOW COLUMNS FROM " . $quoter->quote($db, $tbl);
      MKDEBUG && _d($sql);
      my $cols = $dbh->selectall_arrayref($sql, { Slice => {} });

      $self->{columns}->{$db}->{$tbl} = [
         map {
            my %row;
            @row{ map { lc $_ } keys %$_ } = values %$_;
            \%row;
         } @$cols
      ];
   }
   return $self->{columns}->{$db}->{$tbl};
}

sub get_tmp_table {
   my ( $self, $dbh, $quoter, $db, $tbl ) = @_;
   my $result = 'CREATE TABLE ' . $quoter->quote($tbl) . " (\n";
   $result .= join(",\n",
      map { '  ' . $quoter->quote($_->{field}) . ' ' . $_->{type} }
      @{$self->get_columns($dbh, $quoter, $db, $tbl)});
   $result .= "\n)";
   MKDEBUG && _d($result);
   return $result;
}

sub get_triggers {
   my ( $self, $dbh, $quoter, $db, $tbl ) = @_;
   if ( !$self->{cache} || !$self->{triggers}->{$db} ) {
      $self->{triggers}->{$db} = {};
      my $sql = '/*!40101 SET @OLD_SQL_MODE := @@SQL_MODE, '
         . q{@@SQL_MODE := REPLACE(REPLACE(@@SQL_MODE, 'ANSI_QUOTES', ''), ',,', ','), }
         . '@OLD_QUOTE := @@SQL_QUOTE_SHOW_CREATE, '
         . '@@SQL_QUOTE_SHOW_CREATE := 1 */';
      MKDEBUG && _d($sql);
      eval { $dbh->do($sql); };
      MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
      $sql = "SHOW TRIGGERS FROM " . $quoter->quote($db);
      MKDEBUG && _d($sql);
      my $sth = $dbh->prepare($sql);
      $sth->execute();
      if ( $sth->rows ) {
         my $trgs = $sth->fetchall_arrayref({});
         foreach my $trg (@$trgs) {
            my %trg;
            @trg{ map { lc $_ } keys %$trg } = values %$trg;
            push @{ $self->{triggers}->{$db}->{ $trg{table} } }, \%trg;
         }
      }
      $sql = '/*!40101 SET @@SQL_MODE := @OLD_SQL_MODE, '
         . '@@SQL_QUOTE_SHOW_CREATE := @OLD_QUOTE */';
      MKDEBUG && _d($sql);
      $dbh->do($sql);
   }
   if ( $tbl ) {
      return $self->{triggers}->{$db}->{$tbl};
   }
   return values %{$self->{triggers}->{$db}};
}

sub get_databases {
   my ( $self, $dbh, $quoter, $like ) = @_;
   if ( !$self->{cache} || !$self->{databases} || $like ) {
      my $sql = 'SHOW DATABASES';
      my @params;
      if ( $like ) {
         $sql .= ' LIKE ?';
         push @params, $like;
      }
      my $sth = $dbh->prepare($sql);
      MKDEBUG && _d($sql, @params);
      $sth->execute( @params );
      my @dbs = map { $_->[0] } @{$sth->fetchall_arrayref()};
      $self->{databases} = \@dbs unless $like;
      return @dbs;
   }
   return @{$self->{databases}};
}

sub get_table_status {
   my ( $self, $dbh, $quoter, $db, $like ) = @_;
   if ( !$self->{cache} || !$self->{table_status}->{$db} || $like ) {
      my $sql = "SHOW TABLE STATUS FROM " . $quoter->quote($db);
      my @params;
      if ( $like ) {
         $sql .= ' LIKE ?';
         push @params, $like;
      }
      MKDEBUG && _d($sql, @params);
      my $sth = $dbh->prepare($sql);
      $sth->execute(@params);
      my @tables = @{$sth->fetchall_arrayref({})};
      @tables = map {
         my %tbl; # Make a copy with lowercased keys
         @tbl{ map { lc $_ } keys %$_ } = values %$_;
         $tbl{engine} ||= $tbl{type} || $tbl{comment};
         delete $tbl{type};
         \%tbl;
      } @tables;
      $self->{table_status}->{$db} = \@tables unless $like;
      return @tables;
   }
   return @{$self->{table_status}->{$db}};
}

sub get_table_list {
   my ( $self, $dbh, $quoter, $db, $like ) = @_;
   if ( !$self->{cache} || !$self->{table_list}->{$db} || $like ) {
      my $sql = "SHOW /*!50002 FULL*/ TABLES FROM " . $quoter->quote($db);
      my @params;
      if ( $like ) {
         $sql .= ' LIKE ?';
         push @params, $like;
      }
      MKDEBUG && _d($sql, @params);
      my $sth = $dbh->prepare($sql);
      $sth->execute(@params);
      my @tables = @{$sth->fetchall_arrayref()};
      @tables = map {
         my %tbl = (
            name   => $_->[0],
            engine => ($_->[1] || '') eq 'VIEW' ? 'VIEW' : '',
         );
         \%tbl;
      } @tables;
      $self->{table_list}->{$db} = \@tables unless $like;
      return @tables;
   }
   return @{$self->{table_list}->{$db}};
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End MySQLDump package
# ###########################################################################

# ###########################################################################
# TableParser package 7156
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TableParser.pm
#   trunk/common/t/TableParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package TableParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

sub parse {
   my ( $self, $ddl, $opts ) = @_;
   return unless $ddl;
   if ( ref $ddl eq 'ARRAY' ) {
      if ( lc $ddl->[0] eq 'table' ) {
         $ddl = $ddl->[1];
      }
      else {
         return {
            engine => 'VIEW',
         };
      }
   }

   if ( $ddl !~ m/CREATE (?:TEMPORARY )?TABLE `/ ) {
      die "Cannot parse table definition; is ANSI quoting "
         . "enabled or SQL_QUOTE_SHOW_CREATE disabled?";
   }

   my ($name)     = $ddl =~ m/CREATE (?:TEMPORARY )?TABLE\s+(`.+?`)/;
   (undef, $name) = $self->{Quoter}->split_unquote($name) if $name;

   $ddl =~ s/(`[^`]+`)/\L$1/g;

   my $engine = $self->get_engine($ddl);

   my @defs   = $ddl =~ m/^(\s+`.*?),?$/gm;
   my @cols   = map { $_ =~ m/`([^`]+)`/ } @defs;
   MKDEBUG && _d('Table cols:', join(', ', map { "`$_`" } @cols));

   my %def_for;
   @def_for{@cols} = @defs;

   my (@nums, @null);
   my (%type_for, %is_nullable, %is_numeric, %is_autoinc);
   foreach my $col ( @cols ) {
      my $def = $def_for{$col};
      my ( $type ) = $def =~ m/`[^`]+`\s([a-z]+)/;
      die "Can't determine column type for $def" unless $type;
      $type_for{$col} = $type;
      if ( $type =~ m/(?:(?:tiny|big|medium|small)?int|float|double|decimal|year)/ ) {
         push @nums, $col;
         $is_numeric{$col} = 1;
      }
      if ( $def !~ m/NOT NULL/ ) {
         push @null, $col;
         $is_nullable{$col} = 1;
      }
      $is_autoinc{$col} = $def =~ m/AUTO_INCREMENT/i ? 1 : 0;
   }

   my ($keys, $clustered_key) = $self->get_keys($ddl, $opts, \%is_nullable);

   my ($charset) = $ddl =~ m/DEFAULT CHARSET=(\w+)/;

   return {
      name           => $name,
      cols           => \@cols,
      col_posn       => { map { $cols[$_] => $_ } 0..$#cols },
      is_col         => { map { $_ => 1 } @cols },
      null_cols      => \@null,
      is_nullable    => \%is_nullable,
      is_autoinc     => \%is_autoinc,
      clustered_key  => $clustered_key,
      keys           => $keys,
      defs           => \%def_for,
      numeric_cols   => \@nums,
      is_numeric     => \%is_numeric,
      engine         => $engine,
      type_for       => \%type_for,
      charset        => $charset,
   };
}

sub sort_indexes {
   my ( $self, $tbl ) = @_;

   my @indexes
      = sort {
         (($a ne 'PRIMARY') <=> ($b ne 'PRIMARY'))
         || ( !$tbl->{keys}->{$a}->{is_unique} <=> !$tbl->{keys}->{$b}->{is_unique} )
         || ( $tbl->{keys}->{$a}->{is_nullable} <=> $tbl->{keys}->{$b}->{is_nullable} )
         || ( scalar(@{$tbl->{keys}->{$a}->{cols}}) <=> scalar(@{$tbl->{keys}->{$b}->{cols}}) )
      }
      grep {
         $tbl->{keys}->{$_}->{type} eq 'BTREE'
      }
      sort keys %{$tbl->{keys}};

   MKDEBUG && _d('Indexes sorted best-first:', join(', ', @indexes));
   return @indexes;
}

sub find_best_index {
   my ( $self, $tbl, $index ) = @_;
   my $best;
   if ( $index ) {
      ($best) = grep { uc $_ eq uc $index } keys %{$tbl->{keys}};
   }
   if ( !$best ) {
      if ( $index ) {
         die "Index '$index' does not exist in table";
      }
      else {
         ($best) = $self->sort_indexes($tbl);
      }
   }
   MKDEBUG && _d('Best index found is', $best);
   return $best;
}

sub find_possible_keys {
   my ( $self, $dbh, $database, $table, $quoter, $where ) = @_;
   return () unless $where;
   my $sql = 'EXPLAIN SELECT * FROM ' . $quoter->quote($database, $table)
      . ' WHERE ' . $where;
   MKDEBUG && _d($sql);
   my $expl = $dbh->selectrow_hashref($sql);
   $expl = { map { lc($_) => $expl->{$_} } keys %$expl };
   if ( $expl->{possible_keys} ) {
      MKDEBUG && _d('possible_keys =', $expl->{possible_keys});
      my @candidates = split(',', $expl->{possible_keys});
      my %possible   = map { $_ => 1 } @candidates;
      if ( $expl->{key} ) {
         MKDEBUG && _d('MySQL chose', $expl->{key});
         unshift @candidates, grep { $possible{$_} } split(',', $expl->{key});
         MKDEBUG && _d('Before deduping:', join(', ', @candidates));
         my %seen;
         @candidates = grep { !$seen{$_}++ } @candidates;
      }
      MKDEBUG && _d('Final list:', join(', ', @candidates));
      return @candidates;
   }
   else {
      MKDEBUG && _d('No keys in possible_keys');
      return ();
   }
}

sub check_table {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db, $tbl) = @args{@required_args};
   my $q      = $self->{Quoter};
   my $db_tbl = $q->quote($db, $tbl);
   MKDEBUG && _d('Checking', $db_tbl);

   my $sql = "SHOW TABLES FROM " . $q->quote($db)
           . ' LIKE ' . $q->literal_like($tbl);
   MKDEBUG && _d($sql);
   my $row;
   eval {
      $row = $dbh->selectrow_arrayref($sql);
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($EVAL_ERROR);
      return 0;
   }
   if ( !$row->[0] || $row->[0] ne $tbl ) {
      MKDEBUG && _d('Table does not exist');
      return 0;
   }

   MKDEBUG && _d('Table exists; no privs to check');
   return 1 unless $args{all_privs};

   $sql = "SHOW FULL COLUMNS FROM $db_tbl";
   MKDEBUG && _d($sql);
   eval {
      $row = $dbh->selectrow_hashref($sql);
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($EVAL_ERROR);
      return 0;
   }
   if ( !scalar keys %$row ) {
      MKDEBUG && _d('Table has no columns:', Dumper($row));
      return 0;
   }
   my $privs = $row->{privileges} || $row->{Privileges};

   $sql = "DELETE FROM $db_tbl LIMIT 0";
   MKDEBUG && _d($sql);
   eval {
      $dbh->do($sql);
   };
   my $can_delete = $EVAL_ERROR ? 0 : 1;

   MKDEBUG && _d('User privs on', $db_tbl, ':', $privs,
      ($can_delete ? 'delete' : ''));

   if ( !($privs =~ m/select/ && $privs =~ m/insert/ && $privs =~ m/update/
          && $can_delete) ) {
      MKDEBUG && _d('User does not have all privs');
      return 0;
   }

   MKDEBUG && _d('User has all privs');
   return 1;
}

sub get_engine {
   my ( $self, $ddl, $opts ) = @_;
   my ( $engine ) = $ddl =~ m/\).*?(?:ENGINE|TYPE)=(\w+)/;
   MKDEBUG && _d('Storage engine:', $engine);
   return $engine || undef;
}

sub get_keys {
   my ( $self, $ddl, $opts, $is_nullable ) = @_;
   my $engine        = $self->get_engine($ddl);
   my $keys          = {};
   my $clustered_key = undef;

   KEY:
   foreach my $key ( $ddl =~ m/^  ((?:[A-Z]+ )?KEY .*)$/gm ) {

      next KEY if $key =~ m/FOREIGN/;

      my $key_ddl = $key;
      MKDEBUG && _d('Parsed key:', $key_ddl);

      if ( $engine !~ m/MEMORY|HEAP/ ) {
         $key =~ s/USING HASH/USING BTREE/;
      }

      my ( $type, $cols ) = $key =~ m/(?:USING (\w+))? \((.+)\)/;
      my ( $special ) = $key =~ m/(FULLTEXT|SPATIAL)/;
      $type = $type || $special || 'BTREE';
      if ( $opts->{mysql_version} && $opts->{mysql_version} lt '004001000'
         && $engine =~ m/HEAP|MEMORY/i )
      {
         $type = 'HASH'; # MySQL pre-4.1 supports only HASH indexes on HEAP
      }

      my ($name) = $key =~ m/(PRIMARY|`[^`]*`)/;
      my $unique = $key =~ m/PRIMARY|UNIQUE/ ? 1 : 0;
      my @cols;
      my @col_prefixes;
      foreach my $col_def ( $cols =~ m/`[^`]+`(?:\(\d+\))?/g ) {
         my ($name, $prefix) = $col_def =~ m/`([^`]+)`(?:\((\d+)\))?/;
         push @cols, $name;
         push @col_prefixes, $prefix;
      }
      $name =~ s/`//g;

      MKDEBUG && _d( $name, 'key cols:', join(', ', map { "`$_`" } @cols));

      $keys->{$name} = {
         name         => $name,
         type         => $type,
         colnames     => $cols,
         cols         => \@cols,
         col_prefixes => \@col_prefixes,
         is_unique    => $unique,
         is_nullable  => scalar(grep { $is_nullable->{$_} } @cols),
         is_col       => { map { $_ => 1 } @cols },
         ddl          => $key_ddl,
      };

      if ( $engine =~ m/InnoDB/i && !$clustered_key ) {
         my $this_key = $keys->{$name};
         if ( $this_key->{name} eq 'PRIMARY' ) {
            $clustered_key = 'PRIMARY';
         }
         elsif ( $this_key->{is_unique} && !$this_key->{is_nullable} ) {
            $clustered_key = $this_key->{name};
         }
         MKDEBUG && $clustered_key && _d('This key is the clustered key');
      }
   }

   return $keys, $clustered_key;
}

sub get_fks {
   my ( $self, $ddl, $opts ) = @_;
   my $fks = {};

   foreach my $fk (
      $ddl =~ m/CONSTRAINT .* FOREIGN KEY .* REFERENCES [^\)]*\)/mg )
   {
      my ( $name ) = $fk =~ m/CONSTRAINT `(.*?)`/;
      my ( $cols ) = $fk =~ m/FOREIGN KEY \(([^\)]+)\)/;
      my ( $parent, $parent_cols ) = $fk =~ m/REFERENCES (\S+) \(([^\)]+)\)/;

      if ( $parent !~ m/\./ && $opts->{database} ) {
         $parent = "`$opts->{database}`.$parent";
      }

      $fks->{$name} = {
         name           => $name,
         colnames       => $cols,
         cols           => [ map { s/[ `]+//g; $_; } split(',', $cols) ],
         parent_tbl     => $parent,
         parent_colnames=> $parent_cols,
         parent_cols    => [ map { s/[ `]+//g; $_; } split(',', $parent_cols) ],
         ddl            => $fk,
      };
   }

   return $fks;
}

sub remove_auto_increment {
   my ( $self, $ddl ) = @_;
   $ddl =~ s/(^\).*?) AUTO_INCREMENT=\d+\b/$1/m;
   return $ddl;
}

sub remove_secondary_indexes {
   my ( $self, $ddl ) = @_;
   my $sec_indexes_ddl;
   my $tbl_struct = $self->parse($ddl);

   if ( ($tbl_struct->{engine} || '') =~ m/InnoDB/i ) {
      my $clustered_key = $tbl_struct->{clustered_key};
      $clustered_key  ||= '';

      my @sec_indexes   = map {
         my $key_def = $_->{ddl};
         $key_def =~ s/([\(\)])/\\$1/g;
         $ddl =~ s/\s+$key_def//i;

         my $key_ddl = "ADD $_->{ddl}";
         $key_ddl   .= ',' unless $key_ddl =~ m/,$/;
         $key_ddl;
      }
      grep { $_->{name} ne $clustered_key }
      values %{$tbl_struct->{keys}};
      MKDEBUG && _d('Secondary indexes:', Dumper(\@sec_indexes));

      if ( @sec_indexes ) {
         $sec_indexes_ddl = join(' ', @sec_indexes);
         $sec_indexes_ddl =~ s/,$//;
      }

      $ddl =~ s/,(\n\) )/$1/s;
   }
   else {
      MKDEBUG && _d('Not removing secondary indexes from',
         $tbl_struct->{engine}, 'table');
   }

   return $ddl, $sec_indexes_ddl, $tbl_struct;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End TableParser package
# ###########################################################################

# ###########################################################################
# Quoter package 6850
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Quoter.pm
#   trunk/common/t/Quoter.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package Quoter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   return bless {}, $class;
}

sub quote {
   my ( $self, @vals ) = @_;
   foreach my $val ( @vals ) {
      $val =~ s/`/``/g;
   }
   return join('.', map { '`' . $_ . '`' } @vals);
}

sub quote_val {
   my ( $self, $val ) = @_;

   return 'NULL' unless defined $val;          # undef = NULL
   return "''" if $val eq '';                  # blank string = ''
   return $val if $val =~ m/^0x[0-9a-fA-F]+$/;  # hex data

   $val =~ s/(['\\])/\\$1/g;
   return "'$val'";
}

sub split_unquote {
   my ( $self, $db_tbl, $default_db ) = @_;
   $db_tbl =~ s/`//g;
   my ( $db, $tbl ) = split(/[.]/, $db_tbl);
   if ( !$tbl ) {
      $tbl = $db;
      $db  = $default_db;
   }
   return ($db, $tbl);
}

sub literal_like {
   my ( $self, $like ) = @_;
   return unless $like;
   $like =~ s/([%_])/\\$1/g;
   return "'$like'";
}

sub join_quote {
   my ( $self, $default_db, $db_tbl ) = @_;
   return unless $db_tbl;
   my ($db, $tbl) = split(/[.]/, $db_tbl);
   if ( !$tbl ) {
      $tbl = $db;
      $db  = $default_db;
   }
   $db  = "`$db`"  if $db  && $db  !~ m/^`/;
   $tbl = "`$tbl`" if $tbl && $tbl !~ m/^`/;
   return $db ? "$db.$tbl" : $tbl;
}

1;

# ###########################################################################
# End Quoter package
# ###########################################################################

# ###########################################################################
# OptionParser package 7102
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/OptionParser.pm
#   trunk/common/t/OptionParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package OptionParser;

use strict;
use warnings FATAL => 'all';
use List::Util qw(max);
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Getopt::Long;

my $POD_link_re = '[LC]<"?([^">]+)"?>';

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my ($program_name) = $PROGRAM_NAME =~ m/([.A-Za-z-]+)$/;
   $program_name ||= $PROGRAM_NAME;
   my $home = $ENV{HOME} || $ENV{HOMEPATH} || $ENV{USERPROFILE} || '.';

   my %attributes = (
      'type'       => 1,
      'short form' => 1,
      'group'      => 1,
      'default'    => 1,
      'cumulative' => 1,
      'negatable'  => 1,
   );

   my $self = {
      head1             => 'OPTIONS',        # These args are used internally
      skip_rules        => 0,                # to instantiate another Option-
      item              => '--(.*)',         # Parser obj that parses the
      attributes        => \%attributes,     # DSN OPTIONS section.  Tools
      parse_attributes  => \&_parse_attribs, # don't tinker with these args.

      %args,

      strict            => 1,  # disabled by a special rule
      program_name      => $program_name,
      opts              => {},
      got_opts          => 0,
      short_opts        => {},
      defaults          => {},
      groups            => {},
      allowed_groups    => {},
      errors            => [],
      rules             => [],  # desc of rules for --help
      mutex             => [],  # rule: opts are mutually exclusive
      atleast1          => [],  # rule: at least one opt is required
      disables          => {},  # rule: opt disables other opts 
      defaults_to       => {},  # rule: opt defaults to value of other opt
      DSNParser         => undef,
      default_files     => [
         "/etc/maatkit/maatkit.conf",
         "/etc/maatkit/$program_name.conf",
         "$home/.maatkit.conf",
         "$home/.$program_name.conf",
      ],
      types             => {
         string => 's', # standard Getopt type
         int    => 'i', # standard Getopt type
         float  => 'f', # standard Getopt type
         Hash   => 'H', # hash, formed from a comma-separated list
         hash   => 'h', # hash as above, but only if a value is given
         Array  => 'A', # array, similar to Hash
         array  => 'a', # array, similar to hash
         DSN    => 'd', # DSN
         size   => 'z', # size with kMG suffix (powers of 2^10)
         time   => 'm', # time, with an optional suffix of s/h/m/d
      },
   };

   return bless $self, $class;
}

sub get_specs {
   my ( $self, $file ) = @_;
   $file ||= $self->{file} || __FILE__;
   my @specs = $self->_pod_to_specs($file);
   $self->_parse_specs(@specs);

   open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
   my $contents = do { local $/ = undef; <$fh> };
   close $fh;
   if ( $contents =~ m/^=head1 DSN OPTIONS/m ) {
      MKDEBUG && _d('Parsing DSN OPTIONS');
      my $dsn_attribs = {
         dsn  => 1,
         copy => 1,
      };
      my $parse_dsn_attribs = sub {
         my ( $self, $option, $attribs ) = @_;
         map {
            my $val = $attribs->{$_};
            if ( $val ) {
               $val    = $val eq 'yes' ? 1
                       : $val eq 'no'  ? 0
                       :                 $val;
               $attribs->{$_} = $val;
            }
         } keys %$attribs;
         return {
            key => $option,
            %$attribs,
         };
      };
      my $dsn_o = new OptionParser(
         description       => 'DSN OPTIONS',
         head1             => 'DSN OPTIONS',
         dsn               => 0,         # XXX don't infinitely recurse!
         item              => '\* (.)',  # key opts are a single character
         skip_rules        => 1,         # no rules before opts
         attributes        => $dsn_attribs,
         parse_attributes  => $parse_dsn_attribs,
      );
      my @dsn_opts = map {
         my $opts = {
            key  => $_->{spec}->{key},
            dsn  => $_->{spec}->{dsn},
            copy => $_->{spec}->{copy},
            desc => $_->{desc},
         };
         $opts;
      } $dsn_o->_pod_to_specs($file);
      $self->{DSNParser} = DSNParser->new(opts => \@dsn_opts);
   }

   return;
}

sub DSNParser {
   my ( $self ) = @_;
   return $self->{DSNParser};
};

sub get_defaults_files {
   my ( $self ) = @_;
   return @{$self->{default_files}};
}

sub _pod_to_specs {
   my ( $self, $file ) = @_;
   $file ||= $self->{file} || __FILE__;
   open my $fh, '<', $file or die "Cannot open $file: $OS_ERROR";

   my @specs = ();
   my @rules = ();
   my $para;

   local $INPUT_RECORD_SEPARATOR = '';
   while ( $para = <$fh> ) {
      next unless $para =~ m/^=head1 $self->{head1}/;
      last;
   }

   while ( $para = <$fh> ) {
      last if $para =~ m/^=over/;
      next if $self->{skip_rules};
      chomp $para;
      $para =~ s/\s+/ /g;
      $para =~ s/$POD_link_re/$1/go;
      MKDEBUG && _d('Option rule:', $para);
      push @rules, $para;
   }

   die "POD has no $self->{head1} section" unless $para;

   do {
      if ( my ($option) = $para =~ m/^=item $self->{item}/ ) {
         chomp $para;
         MKDEBUG && _d($para);
         my %attribs;

         $para = <$fh>; # read next paragraph, possibly attributes

         if ( $para =~ m/: / ) { # attributes
            $para =~ s/\s+\Z//g;
            %attribs = map {
                  my ( $attrib, $val) = split(/: /, $_);
                  die "Unrecognized attribute for --$option: $attrib"
                     unless $self->{attributes}->{$attrib};
                  ($attrib, $val);
               } split(/; /, $para);
            if ( $attribs{'short form'} ) {
               $attribs{'short form'} =~ s/-//;
            }
            $para = <$fh>; # read next paragraph, probably short help desc
         }
         else {
            MKDEBUG && _d('Option has no attributes');
         }

         $para =~ s/\s+\Z//g;
         $para =~ s/\s+/ /g;
         $para =~ s/$POD_link_re/$1/go;

         $para =~ s/\.(?:\n.*| [A-Z].*|\Z)//s;
         MKDEBUG && _d('Short help:', $para);

         die "No description after option spec $option" if $para =~ m/^=item/;

         if ( my ($base_option) =  $option =~ m/^\[no\](.*)/ ) {
            $option = $base_option;
            $attribs{'negatable'} = 1;
         }

         push @specs, {
            spec  => $self->{parse_attributes}->($self, $option, \%attribs), 
            desc  => $para
               . (defined $attribs{default} ? " (default $attribs{default})" : ''),
            group => ($attribs{'group'} ? $attribs{'group'} : 'default'),
         };
      }
      while ( $para = <$fh> ) {
         last unless $para;
         if ( $para =~ m/^=head1/ ) {
            $para = undef; # Can't 'last' out of a do {} block.
            last;
         }
         last if $para =~ m/^=item /;
      }
   } while ( $para );

   die "No valid specs in $self->{head1}" unless @specs;

   close $fh;
   return @specs, @rules;
}

sub _parse_specs {
   my ( $self, @specs ) = @_;
   my %disables; # special rule that requires deferred checking

   foreach my $opt ( @specs ) {
      if ( ref $opt ) { # It's an option spec, not a rule.
         MKDEBUG && _d('Parsing opt spec:',
            map { ($_, '=>', $opt->{$_}) } keys %$opt);

         my ( $long, $short ) = $opt->{spec} =~ m/^([\w-]+)(?:\|([^!+=]*))?/;
         if ( !$long ) {
            die "Cannot parse long option from spec $opt->{spec}";
         }
         $opt->{long} = $long;

         die "Duplicate long option --$long" if exists $self->{opts}->{$long};
         $self->{opts}->{$long} = $opt;

         if ( length $long == 1 ) {
            MKDEBUG && _d('Long opt', $long, 'looks like short opt');
            $self->{short_opts}->{$long} = $long;
         }

         if ( $short ) {
            die "Duplicate short option -$short"
               if exists $self->{short_opts}->{$short};
            $self->{short_opts}->{$short} = $long;
            $opt->{short} = $short;
         }
         else {
            $opt->{short} = undef;
         }

         $opt->{is_negatable}  = $opt->{spec} =~ m/!/        ? 1 : 0;
         $opt->{is_cumulative} = $opt->{spec} =~ m/\+/       ? 1 : 0;
         $opt->{is_required}   = $opt->{desc} =~ m/required/ ? 1 : 0;

         $opt->{group} ||= 'default';
         $self->{groups}->{ $opt->{group} }->{$long} = 1;

         $opt->{value} = undef;
         $opt->{got}   = 0;

         my ( $type ) = $opt->{spec} =~ m/=(.)/;
         $opt->{type} = $type;
         MKDEBUG && _d($long, 'type:', $type);


         $opt->{spec} =~ s/=./=s/ if ( $type && $type =~ m/[HhAadzm]/ );

         if ( (my ($def) = $opt->{desc} =~ m/default\b(?: ([^)]+))?/) ) {
            $self->{defaults}->{$long} = defined $def ? $def : 1;
            MKDEBUG && _d($long, 'default:', $def);
         }

         if ( $long eq 'config' ) {
            $self->{defaults}->{$long} = join(',', $self->get_defaults_files());
         }

         if ( (my ($dis) = $opt->{desc} =~ m/(disables .*)/) ) {
            $disables{$long} = $dis;
            MKDEBUG && _d('Deferring check of disables rule for', $opt, $dis);
         }

         $self->{opts}->{$long} = $opt;
      }
      else { # It's an option rule, not a spec.
         MKDEBUG && _d('Parsing rule:', $opt); 
         push @{$self->{rules}}, $opt;
         my @participants = $self->_get_participants($opt);
         my $rule_ok = 0;

         if ( $opt =~ m/mutually exclusive|one and only one/ ) {
            $rule_ok = 1;
            push @{$self->{mutex}}, \@participants;
            MKDEBUG && _d(@participants, 'are mutually exclusive');
         }
         if ( $opt =~ m/at least one|one and only one/ ) {
            $rule_ok = 1;
            push @{$self->{atleast1}}, \@participants;
            MKDEBUG && _d(@participants, 'require at least one');
         }
         if ( $opt =~ m/default to/ ) {
            $rule_ok = 1;
            $self->{defaults_to}->{$participants[0]} = $participants[1];
            MKDEBUG && _d($participants[0], 'defaults to', $participants[1]);
         }
         if ( $opt =~ m/restricted to option groups/ ) {
            $rule_ok = 1;
            my ($groups) = $opt =~ m/groups ([\w\s\,]+)/;
            my @groups = split(',', $groups);
            %{$self->{allowed_groups}->{$participants[0]}} = map {
               s/\s+//;
               $_ => 1;
            } @groups;
         }
         if( $opt =~ m/accepts additional command-line arguments/ ) {
            $rule_ok = 1;
            $self->{strict} = 0;
            MKDEBUG && _d("Strict mode disabled by rule");
         }

         die "Unrecognized option rule: $opt" unless $rule_ok;
      }
   }

   foreach my $long ( keys %disables ) {
      my @participants = $self->_get_participants($disables{$long});
      $self->{disables}->{$long} = \@participants;
      MKDEBUG && _d('Option', $long, 'disables', @participants);
   }

   return; 
}

sub _get_participants {
   my ( $self, $str ) = @_;
   my @participants;
   foreach my $long ( $str =~ m/--(?:\[no\])?([\w-]+)/g ) {
      die "Option --$long does not exist while processing rule $str"
         unless exists $self->{opts}->{$long};
      push @participants, $long;
   }
   MKDEBUG && _d('Participants for', $str, ':', @participants);
   return @participants;
}

sub opts {
   my ( $self ) = @_;
   my %opts = %{$self->{opts}};
   return %opts;
}

sub short_opts {
   my ( $self ) = @_;
   my %short_opts = %{$self->{short_opts}};
   return %short_opts;
}

sub set_defaults {
   my ( $self, %defaults ) = @_;
   $self->{defaults} = {};
   foreach my $long ( keys %defaults ) {
      die "Cannot set default for nonexistent option $long"
         unless exists $self->{opts}->{$long};
      $self->{defaults}->{$long} = $defaults{$long};
      MKDEBUG && _d('Default val for', $long, ':', $defaults{$long});
   }
   return;
}

sub get_defaults {
   my ( $self ) = @_;
   return $self->{defaults};
}

sub get_groups {
   my ( $self ) = @_;
   return $self->{groups};
}

sub _set_option {
   my ( $self, $opt, $val ) = @_;
   my $long = exists $self->{opts}->{$opt}       ? $opt
            : exists $self->{short_opts}->{$opt} ? $self->{short_opts}->{$opt}
            : die "Getopt::Long gave a nonexistent option: $opt";

   $opt = $self->{opts}->{$long};
   if ( $opt->{is_cumulative} ) {
      $opt->{value}++;
   }
   else {
      $opt->{value} = $val;
   }
   $opt->{got} = 1;
   MKDEBUG && _d('Got option', $long, '=', $val);
}

sub get_opts {
   my ( $self ) = @_; 

   foreach my $long ( keys %{$self->{opts}} ) {
      $self->{opts}->{$long}->{got} = 0;
      $self->{opts}->{$long}->{value}
         = exists $self->{defaults}->{$long}       ? $self->{defaults}->{$long}
         : $self->{opts}->{$long}->{is_cumulative} ? 0
         : undef;
   }
   $self->{got_opts} = 0;

   $self->{errors} = [];

   if ( @ARGV && $ARGV[0] eq "--config" ) {
      shift @ARGV;
      $self->_set_option('config', shift @ARGV);
   }
   if ( $self->has('config') ) {
      my @extra_args;
      foreach my $filename ( split(',', $self->get('config')) ) {
         eval {
            push @extra_args, $self->_read_config_file($filename);
         };
         if ( $EVAL_ERROR ) {
            if ( $self->got('config') ) {
               die $EVAL_ERROR;
            }
            elsif ( MKDEBUG ) {
               _d($EVAL_ERROR);
            }
         }
      }
      unshift @ARGV, @extra_args;
   }

   Getopt::Long::Configure('no_ignore_case', 'bundling');
   GetOptions(
      map    { $_->{spec} => sub { $self->_set_option(@_); } }
      grep   { $_->{long} ne 'config' } # --config is handled specially above.
      values %{$self->{opts}}
   ) or $self->save_error('Error parsing options');

   if ( exists $self->{opts}->{version} && $self->{opts}->{version}->{got} ) {
      printf("%s  Ver %s Distrib %s Changeset %s\n",
         $self->{program_name}, $main::VERSION, $main::DISTRIB, $main::SVN_REV)
            or die "Cannot print: $OS_ERROR";
      exit 0;
   }

   if ( @ARGV && $self->{strict} ) {
      $self->save_error("Unrecognized command-line options @ARGV");
   }

   foreach my $mutex ( @{$self->{mutex}} ) {
      my @set = grep { $self->{opts}->{$_}->{got} } @$mutex;
      if ( @set > 1 ) {
         my $err = join(', ', map { "--$self->{opts}->{$_}->{long}" }
                      @{$mutex}[ 0 .. scalar(@$mutex) - 2] )
                 . ' and --'.$self->{opts}->{$mutex->[-1]}->{long}
                 . ' are mutually exclusive.';
         $self->save_error($err);
      }
   }

   foreach my $required ( @{$self->{atleast1}} ) {
      my @set = grep { $self->{opts}->{$_}->{got} } @$required;
      if ( @set == 0 ) {
         my $err = join(', ', map { "--$self->{opts}->{$_}->{long}" }
                      @{$required}[ 0 .. scalar(@$required) - 2] )
                 .' or --'.$self->{opts}->{$required->[-1]}->{long};
         $self->save_error("Specify at least one of $err");
      }
   }

   $self->_check_opts( keys %{$self->{opts}} );
   $self->{got_opts} = 1;
   return;
}

sub _check_opts {
   my ( $self, @long ) = @_;
   my $long_last = scalar @long;
   while ( @long ) {
      foreach my $i ( 0..$#long ) {
         my $long = $long[$i];
         next unless $long;
         my $opt  = $self->{opts}->{$long};
         if ( $opt->{got} ) {
            if ( exists $self->{disables}->{$long} ) {
               my @disable_opts = @{$self->{disables}->{$long}};
               map { $self->{opts}->{$_}->{value} = undef; } @disable_opts;
               MKDEBUG && _d('Unset options', @disable_opts,
                  'because', $long,'disables them');
            }

            if ( exists $self->{allowed_groups}->{$long} ) {

               my @restricted_groups = grep {
                  !exists $self->{allowed_groups}->{$long}->{$_}
               } keys %{$self->{groups}};

               my @restricted_opts;
               foreach my $restricted_group ( @restricted_groups ) {
                  RESTRICTED_OPT:
                  foreach my $restricted_opt (
                     keys %{$self->{groups}->{$restricted_group}} )
                  {
                     next RESTRICTED_OPT if $restricted_opt eq $long;
                     push @restricted_opts, $restricted_opt
                        if $self->{opts}->{$restricted_opt}->{got};
                  }
               }

               if ( @restricted_opts ) {
                  my $err;
                  if ( @restricted_opts == 1 ) {
                     $err = "--$restricted_opts[0]";
                  }
                  else {
                     $err = join(', ',
                               map { "--$self->{opts}->{$_}->{long}" }
                               grep { $_ } 
                               @restricted_opts[0..scalar(@restricted_opts) - 2]
                            )
                          . ' or --'.$self->{opts}->{$restricted_opts[-1]}->{long};
                  }
                  $self->save_error("--$long is not allowed with $err");
               }
            }

         }
         elsif ( $opt->{is_required} ) { 
            $self->save_error("Required option --$long must be specified");
         }

         $self->_validate_type($opt);
         if ( $opt->{parsed} ) {
            delete $long[$i];
         }
         else {
            MKDEBUG && _d('Temporarily failed to parse', $long);
         }
      }

      die "Failed to parse options, possibly due to circular dependencies"
         if @long == $long_last;
      $long_last = @long;
   }

   return;
}

sub _validate_type {
   my ( $self, $opt ) = @_;
   return unless $opt;

   if ( !$opt->{type} ) {
      $opt->{parsed} = 1;
      return;
   }

   my $val = $opt->{value};

   if ( $val && $opt->{type} eq 'm' ) {  # type time
      MKDEBUG && _d('Parsing option', $opt->{long}, 'as a time value');
      my ( $prefix, $num, $suffix ) = $val =~ m/([+-]?)(\d+)([a-z])?$/;
      if ( !$suffix ) {
         my ( $s ) = $opt->{desc} =~ m/\(suffix (.)\)/;
         $suffix = $s || 's';
         MKDEBUG && _d('No suffix given; using', $suffix, 'for',
            $opt->{long}, '(value:', $val, ')');
      }
      if ( $suffix =~ m/[smhd]/ ) {
         $val = $suffix eq 's' ? $num            # Seconds
              : $suffix eq 'm' ? $num * 60       # Minutes
              : $suffix eq 'h' ? $num * 3600     # Hours
              :                  $num * 86400;   # Days
         $opt->{value} = ($prefix || '') . $val;
         MKDEBUG && _d('Setting option', $opt->{long}, 'to', $val);
      }
      else {
         $self->save_error("Invalid time suffix for --$opt->{long}");
      }
   }
   elsif ( $val && $opt->{type} eq 'd' ) {  # type DSN
      MKDEBUG && _d('Parsing option', $opt->{long}, 'as a DSN');
      my $prev = {};
      my $from_key = $self->{defaults_to}->{ $opt->{long} };
      if ( $from_key ) {
         MKDEBUG && _d($opt->{long}, 'DSN copies from', $from_key, 'DSN');
         if ( $self->{opts}->{$from_key}->{parsed} ) {
            $prev = $self->{opts}->{$from_key}->{value};
         }
         else {
            MKDEBUG && _d('Cannot parse', $opt->{long}, 'until',
               $from_key, 'parsed');
            return;
         }
      }
      my $defaults = $self->{DSNParser}->parse_options($self);
      $opt->{value} = $self->{DSNParser}->parse($val, $prev, $defaults);
   }
   elsif ( $val && $opt->{type} eq 'z' ) {  # type size
      MKDEBUG && _d('Parsing option', $opt->{long}, 'as a size value');
      $self->_parse_size($opt, $val);
   }
   elsif ( $opt->{type} eq 'H' || (defined $val && $opt->{type} eq 'h') ) {
      $opt->{value} = { map { $_ => 1 } split(/(?<!\\),\s*/, ($val || '')) };
   }
   elsif ( $opt->{type} eq 'A' || (defined $val && $opt->{type} eq 'a') ) {
      $opt->{value} = [ split(/(?<!\\),\s*/, ($val || '')) ];
   }
   else {
      MKDEBUG && _d('Nothing to validate for option',
         $opt->{long}, 'type', $opt->{type}, 'value', $val);
   }

   $opt->{parsed} = 1;
   return;
}

sub get {
   my ( $self, $opt ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   die "Option $opt does not exist"
      unless $long && exists $self->{opts}->{$long};
   return $self->{opts}->{$long}->{value};
}

sub got {
   my ( $self, $opt ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   die "Option $opt does not exist"
      unless $long && exists $self->{opts}->{$long};
   return $self->{opts}->{$long}->{got};
}

sub has {
   my ( $self, $opt ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   return defined $long ? exists $self->{opts}->{$long} : 0;
}

sub set {
   my ( $self, $opt, $val ) = @_;
   my $long = (length $opt == 1 ? $self->{short_opts}->{$opt} : $opt);
   die "Option $opt does not exist"
      unless $long && exists $self->{opts}->{$long};
   $self->{opts}->{$long}->{value} = $val;
   return;
}

sub save_error {
   my ( $self, $error ) = @_;
   push @{$self->{errors}}, $error;
   return;
}

sub errors {
   my ( $self ) = @_;
   return $self->{errors};
}

sub usage {
   my ( $self ) = @_;
   warn "No usage string is set" unless $self->{usage}; # XXX
   return "Usage: " . ($self->{usage} || '') . "\n";
}

sub descr {
   my ( $self ) = @_;
   warn "No description string is set" unless $self->{description}; # XXX
   my $descr  = ($self->{description} || $self->{program_name} || '')
              . "  For more details, please use the --help option, "
              . "or try 'perldoc $PROGRAM_NAME' "
              . "for complete documentation.";
   $descr = join("\n", $descr =~ m/(.{0,80})(?:\s+|$)/g)
      unless $ENV{DONT_BREAK_LINES};
   $descr =~ s/ +$//mg;
   return $descr;
}

sub usage_or_errors {
   my ( $self, $file, $return ) = @_;
   $file ||= $self->{file} || __FILE__;

   if ( !$self->{description} || !$self->{usage} ) {
      MKDEBUG && _d("Getting description and usage from SYNOPSIS in", $file);
      my %synop = $self->_parse_synopsis($file);
      $self->{description} ||= $synop{description};
      $self->{usage}       ||= $synop{usage};
      MKDEBUG && _d("Description:", $self->{description},
         "\nUsage:", $self->{usage});
   }

   if ( $self->{opts}->{help}->{got} ) {
      print $self->print_usage() or die "Cannot print usage: $OS_ERROR";
      exit 0 unless $return;
   }
   elsif ( scalar @{$self->{errors}} ) {
      print $self->print_errors() or die "Cannot print errors: $OS_ERROR";
      exit 0 unless $return;
   }

   return;
}

sub print_errors {
   my ( $self ) = @_;
   my $usage = $self->usage() . "\n";
   if ( (my @errors = @{$self->{errors}}) ) {
      $usage .= join("\n  * ", 'Errors in command-line arguments:', @errors)
              . "\n";
   }
   return $usage . "\n" . $self->descr();
}

sub print_usage {
   my ( $self ) = @_;
   die "Run get_opts() before print_usage()" unless $self->{got_opts};
   my @opts = values %{$self->{opts}};

   my $maxl = max(
      map {
         length($_->{long})               # option long name
         + ($_->{is_negatable} ? 4 : 0)   # "[no]" if opt is negatable
         + ($_->{type} ? 2 : 0)           # "=x" where x is the opt type
      }
      @opts);

   my $maxs = max(0,
      map {
         length($_)
         + ($self->{opts}->{$_}->{is_negatable} ? 4 : 0)
         + ($self->{opts}->{$_}->{type} ? 2 : 0)
      }
      values %{$self->{short_opts}});

   my $lcol = max($maxl, ($maxs + 3));
   my $rcol = 80 - $lcol - 6;
   my $rpad = ' ' x ( 80 - $rcol );

   $maxs = max($lcol - 3, $maxs);

   my $usage = $self->descr() . "\n" . $self->usage();

   my @groups = reverse sort grep { $_ ne 'default'; } keys %{$self->{groups}};
   push @groups, 'default';

   foreach my $group ( reverse @groups ) {
      $usage .= "\n".($group eq 'default' ? 'Options' : $group).":\n\n";
      foreach my $opt (
         sort { $a->{long} cmp $b->{long} }
         grep { $_->{group} eq $group }
         @opts )
      {
         my $long  = $opt->{is_negatable} ? "[no]$opt->{long}" : $opt->{long};
         my $short = $opt->{short};
         my $desc  = $opt->{desc};

         $long .= $opt->{type} ? "=$opt->{type}" : "";

         if ( $opt->{type} && $opt->{type} eq 'm' ) {
            my ($s) = $desc =~ m/\(suffix (.)\)/;
            $s    ||= 's';
            $desc =~ s/\s+\(suffix .\)//;
            $desc .= ".  Optional suffix s=seconds, m=minutes, h=hours, "
                   . "d=days; if no suffix, $s is used.";
         }
         $desc = join("\n$rpad", grep { $_ } $desc =~ m/(.{0,$rcol})(?:\s+|$)/g);
         $desc =~ s/ +$//mg;
         if ( $short ) {
            $usage .= sprintf("  --%-${maxs}s -%s  %s\n", $long, $short, $desc);
         }
         else {
            $usage .= sprintf("  --%-${lcol}s  %s\n", $long, $desc);
         }
      }
   }

   $usage .= "\nOption types: s=string, i=integer, f=float, h/H/a/A=comma-separated list, d=DSN, z=size, m=time\n";

   if ( (my @rules = @{$self->{rules}}) ) {
      $usage .= "\nRules:\n\n";
      $usage .= join("\n", map { "  $_" } @rules) . "\n";
   }
   if ( $self->{DSNParser} ) {
      $usage .= "\n" . $self->{DSNParser}->usage();
   }
   $usage .= "\nOptions and values after processing arguments:\n\n";
   foreach my $opt ( sort { $a->{long} cmp $b->{long} } @opts ) {
      my $val   = $opt->{value};
      my $type  = $opt->{type} || '';
      my $bool  = $opt->{spec} =~ m/^[\w-]+(?:\|[\w-])?!?$/;
      $val      = $bool              ? ( $val ? 'TRUE' : 'FALSE' )
                : !defined $val      ? '(No value)'
                : $type eq 'd'       ? $self->{DSNParser}->as_string($val)
                : $type =~ m/H|h/    ? join(',', sort keys %$val)
                : $type =~ m/A|a/    ? join(',', @$val)
                :                    $val;
      $usage .= sprintf("  --%-${lcol}s  %s\n", $opt->{long}, $val);
   }
   return $usage;
}

sub prompt_noecho {
   shift @_ if ref $_[0] eq __PACKAGE__;
   my ( $prompt ) = @_;
   local $OUTPUT_AUTOFLUSH = 1;
   print $prompt
      or die "Cannot print: $OS_ERROR";
   my $response;
   eval {
      require Term::ReadKey;
      Term::ReadKey::ReadMode('noecho');
      chomp($response = <STDIN>);
      Term::ReadKey::ReadMode('normal');
      print "\n"
         or die "Cannot print: $OS_ERROR";
   };
   if ( $EVAL_ERROR ) {
      die "Cannot read response; is Term::ReadKey installed? $EVAL_ERROR";
   }
   return $response;
}

if ( MKDEBUG ) {
   print '# ', $^X, ' ', $], "\n";
   my $uname = `uname -a`;
   if ( $uname ) {
      $uname =~ s/\s+/ /g;
      print "# $uname\n";
   }
   printf("# %s  Ver %s Distrib %s Changeset %s line %d\n",
      $PROGRAM_NAME, ($main::VERSION || ''), ($main::DISTRIB || ''),
      ($main::SVN_REV || ''), __LINE__);
   print('# Arguments: ',
      join(' ', map { my $a = "_[$_]_"; $a =~ s/\n/\n# /g; $a; } @ARGV), "\n");
}

sub _read_config_file {
   my ( $self, $filename ) = @_;
   open my $fh, "<", $filename or die "Cannot open $filename: $OS_ERROR\n";
   my @args;
   my $prefix = '--';
   my $parse  = 1;

   LINE:
   while ( my $line = <$fh> ) {
      chomp $line;
      next LINE if $line =~ m/^\s*(?:\#|\;|$)/;
      $line =~ s/\s+#.*$//g;
      $line =~ s/^\s+|\s+$//g;
      if ( $line eq '--' ) {
         $prefix = '';
         $parse  = 0;
         next LINE;
      }
      if ( $parse
         && (my($opt, $arg) = $line =~ m/^\s*([^=\s]+?)(?:\s*=\s*(.*?)\s*)?$/)
      ) {
         push @args, grep { defined $_ } ("$prefix$opt", $arg);
      }
      elsif ( $line =~ m/./ ) {
         push @args, $line;
      }
      else {
         die "Syntax error in file $filename at line $INPUT_LINE_NUMBER";
      }
   }
   close $fh;
   return @args;
}

sub read_para_after {
   my ( $self, $file, $regex ) = @_;
   open my $fh, "<", $file or die "Can't open $file: $OS_ERROR";
   local $INPUT_RECORD_SEPARATOR = '';
   my $para;
   while ( $para = <$fh> ) {
      next unless $para =~ m/^=pod$/m;
      last;
   }
   while ( $para = <$fh> ) {
      next unless $para =~ m/$regex/;
      last;
   }
   $para = <$fh>;
   chomp($para);
   close $fh or die "Can't close $file: $OS_ERROR";
   return $para;
}

sub clone {
   my ( $self ) = @_;

   my %clone = map {
      my $hashref  = $self->{$_};
      my $val_copy = {};
      foreach my $key ( keys %$hashref ) {
         my $ref = ref $hashref->{$key};
         $val_copy->{$key} = !$ref           ? $hashref->{$key}
                           : $ref eq 'HASH'  ? { %{$hashref->{$key}} }
                           : $ref eq 'ARRAY' ? [ @{$hashref->{$key}} ]
                           : $hashref->{$key};
      }
      $_ => $val_copy;
   } qw(opts short_opts defaults);

   foreach my $scalar ( qw(got_opts) ) {
      $clone{$scalar} = $self->{$scalar};
   }

   return bless \%clone;     
}

sub _parse_size {
   my ( $self, $opt, $val ) = @_;

   if ( lc($val || '') eq 'null' ) {
      MKDEBUG && _d('NULL size for', $opt->{long});
      $opt->{value} = 'null';
      return;
   }

   my %factor_for = (k => 1_024, M => 1_048_576, G => 1_073_741_824);
   my ($pre, $num, $factor) = $val =~ m/^([+-])?(\d+)([kMG])?$/;
   if ( defined $num ) {
      if ( $factor ) {
         $num *= $factor_for{$factor};
         MKDEBUG && _d('Setting option', $opt->{y},
            'to num', $num, '* factor', $factor);
      }
      $opt->{value} = ($pre || '') . $num;
   }
   else {
      $self->save_error("Invalid size for --$opt->{long}");
   }
   return;
}

sub _parse_attribs {
   my ( $self, $option, $attribs ) = @_;
   my $types = $self->{types};
   return $option
      . ($attribs->{'short form'} ? '|' . $attribs->{'short form'}   : '' )
      . ($attribs->{'negatable'}  ? '!'                              : '' )
      . ($attribs->{'cumulative'} ? '+'                              : '' )
      . ($attribs->{'type'}       ? '=' . $types->{$attribs->{type}} : '' );
}

sub _parse_synopsis {
   my ( $self, $file ) = @_;
   $file ||= $self->{file} || __FILE__;
   MKDEBUG && _d("Parsing SYNOPSIS in", $file);

   local $INPUT_RECORD_SEPARATOR = '';  # read paragraphs
   open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
   my $para;
   1 while defined($para = <$fh>) && $para !~ m/^=head1 SYNOPSIS/;
   die "$file does not contain a SYNOPSIS section" unless $para;
   my @synop;
   for ( 1..2 ) {  # 1 for the usage, 2 for the description
      my $para = <$fh>;
      push @synop, $para;
   }
   close $fh;
   MKDEBUG && _d("Raw SYNOPSIS text:", @synop);
   my ($usage, $desc) = @synop;
   die "The SYNOPSIS section in $file is not formatted properly"
      unless $usage && $desc;

   $usage =~ s/^\s*Usage:\s+(.+)/$1/;
   chomp $usage;

   $desc =~ s/\n/ /g;
   $desc =~ s/\s{2,}/ /g;
   $desc =~ s/\. ([A-Z][a-z])/.  $1/g;
   $desc =~ s/\s+$//;

   return (
      description => $desc,
      usage       => $usage,
   );
};

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End OptionParser package
# ###########################################################################

# ###########################################################################
# Transformers package 7226
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Transformers.pm
#   trunk/common/t/Transformers.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package Transformers;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Time::Local qw(timegm timelocal);
use Digest::MD5 qw(md5_hex);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

require Exporter;
our @ISA         = qw(Exporter);
our %EXPORT_TAGS = ();
our @EXPORT      = ();
our @EXPORT_OK   = qw(
   micro_t
   percentage_of
   secs_to_time
   time_to_secs
   shorten
   ts
   parse_timestamp
   unix_timestamp
   any_unix_timestamp
   make_checksum
   crc32
);

our $mysql_ts  = qr/(\d\d)(\d\d)(\d\d) +(\d+):(\d+):(\d+)(\.\d+)?/;
our $proper_ts = qr/(\d\d\d\d)-(\d\d)-(\d\d)[T ](\d\d):(\d\d):(\d\d)(\.\d+)?/;
our $n_ts      = qr/(\d{1,5})([shmd]?)/; # Limit \d{1,5} because \d{6} looks

sub micro_t {
   my ( $t, %args ) = @_;
   my $p_ms = defined $args{p_ms} ? $args{p_ms} : 0;  # precision for ms vals
   my $p_s  = defined $args{p_s}  ? $args{p_s}  : 0;  # precision for s vals
   my $f;

   $t = 0 if $t < 0;

   $t = sprintf('%.17f', $t) if $t =~ /e/;

   $t =~ s/\.(\d{1,6})\d*/\.$1/;

   if ($t > 0 && $t <= 0.000999) {
      $f = ($t * 1000000) . 'us';
   }
   elsif ($t >= 0.001000 && $t <= 0.999999) {
      $f = sprintf("%.${p_ms}f", $t * 1000);
      $f = ($f * 1) . 'ms'; # * 1 to remove insignificant zeros
   }
   elsif ($t >= 1) {
      $f = sprintf("%.${p_s}f", $t);
      $f = ($f * 1) . 's'; # * 1 to remove insignificant zeros
   }
   else {
      $f = 0;  # $t should = 0 at this point
   }

   return $f;
}

sub percentage_of {
   my ( $is, $of, %args ) = @_;
   my $p   = $args{p} || 0; # float precision
   my $fmt = $p ? "%.${p}f" : "%d";
   return sprintf $fmt, ($is * 100) / ($of ||= 1);
}

sub secs_to_time {
   my ( $secs, $fmt ) = @_;
   $secs ||= 0;
   return '00:00' unless $secs;

   $fmt ||= $secs >= 86_400 ? 'd'
          : $secs >= 3_600  ? 'h'
          :                   'm';

   return
      $fmt eq 'd' ? sprintf(
         "%d+%02d:%02d:%02d",
         int($secs / 86_400),
         int(($secs % 86_400) / 3_600),
         int(($secs % 3_600) / 60),
         $secs % 60)
      : $fmt eq 'h' ? sprintf(
         "%02d:%02d:%02d",
         int(($secs % 86_400) / 3_600),
         int(($secs % 3_600) / 60),
         $secs % 60)
      : sprintf(
         "%02d:%02d",
         int(($secs % 3_600) / 60),
         $secs % 60);
}

sub time_to_secs {
   my ( $val, $default_suffix ) = @_;
   die "I need a val argument" unless defined $val;
   my $t = 0;
   my ( $prefix, $num, $suffix ) = $val =~ m/([+-]?)(\d+)([a-z])?$/;
   $suffix = $suffix || $default_suffix || 's';
   if ( $suffix =~ m/[smhd]/ ) {
      $t = $suffix eq 's' ? $num * 1        # Seconds
         : $suffix eq 'm' ? $num * 60       # Minutes
         : $suffix eq 'h' ? $num * 3600     # Hours
         :                  $num * 86400;   # Days

      $t *= -1 if $prefix && $prefix eq '-';
   }
   else {
      die "Invalid suffix for $val: $suffix";
   }
   return $t;
}

sub shorten {
   my ( $num, %args ) = @_;
   my $p = defined $args{p} ? $args{p} : 2;     # float precision
   my $d = defined $args{d} ? $args{d} : 1_024; # divisor
   my $n = 0;
   my @units = ('', qw(k M G T P E Z Y));
   while ( $num >= $d && $n < @units - 1 ) {
      $num /= $d;
      ++$n;
   }
   return sprintf(
      $num =~ m/\./ || $n
         ? "%.${p}f%s"
         : '%d',
      $num, $units[$n]);
}

sub ts {
   my ( $time, $gmt ) = @_;
   my ( $sec, $min, $hour, $mday, $mon, $year )
      = $gmt ? gmtime($time) : localtime($time);
   $mon  += 1;
   $year += 1900;
   my $val = sprintf("%d-%02d-%02dT%02d:%02d:%02d",
      $year, $mon, $mday, $hour, $min, $sec);
   if ( my ($us) = $time =~ m/(\.\d+)$/ ) {
      $us = sprintf("%.6f", $us);
      $us =~ s/^0\././;
      $val .= $us;
   }
   return $val;
}

sub parse_timestamp {
   my ( $val ) = @_;
   if ( my($y, $m, $d, $h, $i, $s, $f)
         = $val =~ m/^$mysql_ts$/ )
   {
      return sprintf "%d-%02d-%02d %02d:%02d:"
                     . (defined $f ? '%09.6f' : '%02d'),
                     $y + 2000, $m, $d, $h, $i, (defined $f ? $s + $f : $s);
   }
   return $val;
}

sub unix_timestamp {
   my ( $val, $gmt ) = @_;
   if ( my($y, $m, $d, $h, $i, $s, $us) = $val =~ m/^$proper_ts$/ ) {
      $val = $gmt
         ? timegm($s, $i, $h, $d, $m - 1, $y)
         : timelocal($s, $i, $h, $d, $m - 1, $y);
      if ( defined $us ) {
         $us = sprintf('%.6f', $us);
         $us =~ s/^0\././;
         $val .= $us;
      }
   }
   return $val;
}

sub any_unix_timestamp {
   my ( $val, $callback ) = @_;

   if ( my ($n, $suffix) = $val =~ m/^$n_ts$/ ) {
      $n = $suffix eq 's' ? $n            # Seconds
         : $suffix eq 'm' ? $n * 60       # Minutes
         : $suffix eq 'h' ? $n * 3600     # Hours
         : $suffix eq 'd' ? $n * 86400    # Days
         :                  $n;           # default: Seconds
      MKDEBUG && _d('ts is now - N[shmd]:', $n);
      return time - $n;
   }
   elsif ( $val =~ m/^\d{9,}/ ) {
      MKDEBUG && _d('ts is already a unix timestamp');
      return $val;
   }
   elsif ( my ($ymd, $hms) = $val =~ m/^(\d{6})(?:\s+(\d+:\d+:\d+))?/ ) {
      MKDEBUG && _d('ts is MySQL slow log timestamp');
      $val .= ' 00:00:00' unless $hms;
      return unix_timestamp(parse_timestamp($val));
   }
   elsif ( ($ymd, $hms) = $val =~ m/^(\d{4}-\d\d-\d\d)(?:[T ](\d+:\d+:\d+))?/) {
      MKDEBUG && _d('ts is properly formatted timestamp');
      $val .= ' 00:00:00' unless $hms;
      return unix_timestamp($val);
   }
   else {
      MKDEBUG && _d('ts is MySQL expression');
      return $callback->($val) if $callback && ref $callback eq 'CODE';
   }

   MKDEBUG && _d('Unknown ts type:', $val);
   return;
}

sub make_checksum {
   my ( $val ) = @_;
   my $checksum = uc substr(md5_hex($val), -16);
   MKDEBUG && _d($checksum, 'checksum for', $val);
   return $checksum;
}

sub crc32 {
   my ( $string ) = @_;
   return unless $string;
   my $poly = 0xEDB88320;
   my $crc  = 0xFFFFFFFF;
   foreach my $char ( split(//, $string) ) {
      my $comp = ($crc ^ ord($char)) & 0xFF;
      for ( 1 .. 8 ) {
         $comp = $comp & 1 ? $poly ^ ($comp >> 1) : $comp >> 1;
      }
      $crc = (($crc >> 8) & 0x00FFFFFF) ^ $comp;
   }
   return $crc ^ 0xFFFFFFFF;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End Transformers package
# ###########################################################################

# ###########################################################################
# SlowLogParser package 7522
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/SlowLogParser.pm
#   trunk/common/t/SlowLogParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package SlowLogParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Data::Dumper;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class ) = @_;
   my $self = {
      pending => [],
   };
   return bless $self, $class;
}

my $slow_log_ts_line = qr/^# Time: ([0-9: ]{15})/;
my $slow_log_uh_line = qr/# User\@Host: ([^\[]+|\[[^[]+\]).*?@ (\S*) \[(.*)\]/;
my $slow_log_hd_line = qr{
      ^(?:
      T[cC][pP]\s[pP]ort:\s+\d+ # case differs on windows/unix
      |
      [/A-Z].*mysqld,\sVersion.*(?:started\swith:|embedded\slibrary)
      |
      Time\s+Id\s+Command
      ).*\n
   }xm;

sub parse_event {
   my ( $self, %args ) = @_;
   my @required_args = qw(next_event tell);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($next_event, $tell) = @args{@required_args};

   my $pending = $self->{pending};
   local $INPUT_RECORD_SEPARATOR = ";\n#";
   my $trimlen    = length($INPUT_RECORD_SEPARATOR);
   my $pos_in_log = $tell->();
   my $stmt;

   EVENT:
   while (
         defined($stmt = shift @$pending)
      or defined($stmt = $next_event->())
   ) {
      my @properties = ('cmd', 'Query', 'pos_in_log', $pos_in_log);
      $pos_in_log = $tell->();

      if ( $stmt =~ s/$slow_log_hd_line//go ){ # Throw away header lines in log
         my @chunks = split(/$INPUT_RECORD_SEPARATOR/o, $stmt);
         if ( @chunks > 1 ) {
            MKDEBUG && _d("Found multiple chunks");
            $stmt = shift @chunks;
            unshift @$pending, @chunks;
         }
      }

      $stmt = '#' . $stmt unless $stmt =~ m/\A#/;
      $stmt =~ s/;\n#?\Z//;


      my ($got_ts, $got_uh, $got_ac, $got_db, $got_set, $got_embed);
      my $pos = 0;
      my $len = length($stmt);
      my $found_arg = 0;
      LINE:
      while ( $stmt =~ m/^(.*)$/mg ) { # /g is important, requires scalar match.
         $pos     = pos($stmt);  # Be careful not to mess this up!
         my $line = $1;          # Necessary for /g and pos() to work.
         MKDEBUG && _d($line);

         if ($line =~ m/^(?:#|use |SET (?:last_insert_id|insert_id|timestamp))/o) {

            if ( !$got_ts && (my ( $time ) = $line =~ m/$slow_log_ts_line/o)) {
               MKDEBUG && _d("Got ts", $time);
               push @properties, 'ts', $time;
               ++$got_ts;
               if ( !$got_uh
                  && ( my ( $user, $host, $ip ) = $line =~ m/$slow_log_uh_line/o )
               ) {
                  MKDEBUG && _d("Got user, host, ip", $user, $host, $ip);
                  push @properties, 'user', $user, 'host', $host, 'ip', $ip;
                  ++$got_uh;
               }
            }

            elsif ( !$got_uh
                  && ( my ( $user, $host, $ip ) = $line =~ m/$slow_log_uh_line/o )
            ) {
               MKDEBUG && _d("Got user, host, ip", $user, $host, $ip);
               push @properties, 'user', $user, 'host', $host, 'ip', $ip;
               ++$got_uh;
            }

            elsif (!$got_ac && $line =~ m/^# (?:administrator command:.*)$/) {
               MKDEBUG && _d("Got admin command");
               $line =~ s/^#\s+//;  # string leading "# ".
               push @properties, 'cmd', 'Admin', 'arg', $line;
               push @properties, 'bytes', length($properties[-1]);
               ++$found_arg;
               ++$got_ac;
            }

            elsif ( $line =~ m/^# +[A-Z][A-Za-z_]+: \S+/ ) { # Make the test cheap!
               MKDEBUG && _d("Got some line with properties");

               if ( $line =~ m/Schema:\s+\w+: / ) {
                  MKDEBUG && _d('Removing empty Schema attrib');
                  $line =~ s/Schema:\s+//;
                  MKDEBUG && _d($line);
               }

               my @temp = $line =~ m/(\w+):\s+(\S+|\Z)/g;
               push @properties, @temp;
            }

            elsif ( !$got_db && (my ( $db ) = $line =~ m/^use ([^;]+)/ ) ) {
               MKDEBUG && _d("Got a default database:", $db);
               push @properties, 'db', $db;
               ++$got_db;
            }

            elsif (!$got_set && (my ($setting) = $line =~ m/^SET\s+([^;]*)/)) {
               MKDEBUG && _d("Got some setting:", $setting);
               push @properties, split(/,|\s*=\s*/, $setting);
               ++$got_set;
            }

            if ( !$found_arg && $pos == $len ) {
               MKDEBUG && _d("Did not find arg, looking for special cases");
               local $INPUT_RECORD_SEPARATOR = ";\n";
               if ( defined(my $l = $next_event->()) ) {
                  chomp $l;
                  $l =~ s/^\s+//;
                  MKDEBUG && _d("Found admin statement", $l);
                  push @properties, 'cmd', 'Admin', 'arg', $l;
                  push @properties, 'bytes', length($properties[-1]);
                  $found_arg++;
               }
               else {
                  MKDEBUG && _d("I can't figure out what to do with this line");
                  next EVENT;
               }
            }
         }
         else {
            MKDEBUG && _d("Got the query/arg line");
            my $arg = substr($stmt, $pos - length($line));
            push @properties, 'arg', $arg, 'bytes', length($arg);
            if ( $args{misc} && $args{misc}->{embed}
               && ( my ($e) = $arg =~ m/($args{misc}->{embed})/)
            ) {
               push @properties, $e =~ m/$args{misc}->{capture}/g;
            }
            last LINE;
         }
      }

      MKDEBUG && _d('Properties of event:', Dumper(\@properties));
      my $event = { @properties };
      if ( $args{stats} ) {
         $args{stats}->{events_read}++;
         $args{stats}->{events_parsed}++;
      }
      return $event;
   } # EVENT

   @$pending = ();
   $args{oktorun}->(0) if $args{oktorun};
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End SlowLogParser package
# ###########################################################################

# ###########################################################################
# EventAggregator package 7272
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/EventAggregator.pm
#   trunk/common/t/EventAggregator.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package EventAggregator;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use List::Util qw(min max);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG         => $ENV{MKDEBUG} || 0;
use constant BUCK_SIZE       => 1.05;
use constant BASE_LOG        => log(BUCK_SIZE);
use constant BASE_OFFSET     => abs(1 - log(0.000001) / BASE_LOG); # 284.1617969
use constant NUM_BUCK        => 1000;
use constant MIN_BUCK        => .000001;
use constant MAX_UNQ_STRINGS => 1_000;

my @buck_vals = map { bucket_value($_); } (0..NUM_BUCK-1);

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(groupby worst) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $attributes = $args{attributes} || {};
   my $self = {
      groupby        => $args{groupby},
      detect_attribs => scalar keys %$attributes == 0 ? 1 : 0,
      all_attribs    => [ keys %$attributes ],
      ignore_attribs => {
         map  { $_ => $args{attributes}->{$_} }
         grep { $_ ne $args{groupby} }
         @{$args{ignore_attributes}}
      },
      attributes     => {
         map  { $_ => $args{attributes}->{$_} }
         grep { $_ ne $args{groupby} }
         keys %$attributes
      },
      alt_attribs    => {
         map  { $_ => make_alt_attrib(@{$args{attributes}->{$_}}) }
         grep { $_ ne $args{groupby} }
         keys %$attributes
      },
      worst          => $args{worst},
      unroll_limit   => $args{unroll_limit} || 1000,
      attrib_limit   => $args{attrib_limit},
      result_classes => {},
      result_globals => {},
      result_samples => {},
      class_metrics  => {},
      global_metrics => {},
      n_events       => 0,
      unrolled_loops => undef,
      type_for       => { %{$args{type_for} || { Query_time => 'num' }} },
   };
   return bless $self, $class;
}

sub reset_aggregated_data {
   my ( $self ) = @_;
   foreach my $class ( values %{$self->{result_classes}} ) {
      foreach my $attrib ( values %$class ) {
         delete @{$attrib}{keys %$attrib};
      }
   }
   foreach my $class ( values %{$self->{result_globals}} ) {
      delete @{$class}{keys %$class};
   }
   delete @{$self->{result_samples}}{keys %{$self->{result_samples}}};
   $self->{n_events} = 0;
}

sub aggregate {
   my ( $self, $event ) = @_;

   my $group_by = $event->{$self->{groupby}};
   return unless defined $group_by;

   $self->{n_events}++;
   MKDEBUG && _d('Event', $self->{n_events});

   return $self->{unrolled_loops}->($self, $event, $group_by)
      if $self->{unrolled_loops};

   if ( $self->{n_events} <= $self->{unroll_limit} ) {

      $self->add_new_attributes($event) if $self->{detect_attribs};

      ATTRIB:
      foreach my $attrib ( keys %{$self->{attributes}} ) {

         if ( !exists $event->{$attrib} ) {
            MKDEBUG && _d("attrib doesn't exist in event:", $attrib);
            my $alt_attrib = $self->{alt_attribs}->{$attrib}->($event);
            MKDEBUG && _d('alt attrib:', $alt_attrib);
            next ATTRIB unless $alt_attrib;
         }

         GROUPBY:
         foreach my $val ( ref $group_by ? @$group_by : ($group_by) ) {
            my $class_attrib  = $self->{result_classes}->{$val}->{$attrib} ||= {};
            my $global_attrib = $self->{result_globals}->{$attrib} ||= {};
            my $samples       = $self->{result_samples};
            my $handler = $self->{handlers}->{ $attrib };
            if ( !$handler ) {
               $handler = $self->make_handler(
                  event      => $event,
                  attribute  => $attrib,
                  alternates => $self->{attributes}->{$attrib},
                  worst      => $self->{worst} eq $attrib,
               );
               $self->{handlers}->{$attrib} = $handler;
            }
            next GROUPBY unless $handler;
            $samples->{$val} ||= $event; # Initialize to the first event.
            $handler->($event, $class_attrib, $global_attrib, $samples, $group_by);
         }
      }
   }
   else {
      $self->_make_unrolled_loops($event);
      $self->{unrolled_loops}->($self, $event, $group_by);
   }

   return;
}

sub _make_unrolled_loops {
   my ( $self, $event ) = @_;

   my $group_by = $event->{$self->{groupby}};

   my @attrs   = grep { $self->{handlers}->{$_} } keys %{$self->{attributes}};
   my $globs   = $self->{result_globals}; # Global stats for each
   my $samples = $self->{result_samples};

   my @lines = (
      'my ( $self, $event, $group_by ) = @_;',
      'my ($val, $class, $global, $idx);',
      (ref $group_by ? ('foreach my $group_by ( @$group_by ) {') : ()),
      'my $temp = $self->{result_classes}->{ $group_by }
         ||= { map { $_ => { } } @attrs };',
      '$samples->{$group_by} ||= $event;', # Always start with the first.
   );
   foreach my $i ( 0 .. $#attrs ) {
      push @lines, (
         '$class  = $temp->{\''  . $attrs[$i] . '\'};',
         '$global = $globs->{\'' . $attrs[$i] . '\'};',
         $self->{unrolled_for}->{$attrs[$i]},
      );
   }
   if ( ref $group_by ) {
      push @lines, '}'; # Close the loop opened above
   }
   @lines = map { s/^/   /gm; $_ } @lines; # Indent for debugging
   unshift @lines, 'sub {';
   push @lines, '}';

   my $code = join("\n", @lines);
   MKDEBUG && _d('Unrolled subroutine:', @lines);
   my $sub = eval $code;
   die $EVAL_ERROR if $EVAL_ERROR;
   $self->{unrolled_loops} = $sub;

   return;
}

sub results {
   my ( $self ) = @_;
   return {
      classes => $self->{result_classes},
      globals => $self->{result_globals},
      samples => $self->{result_samples},
   };
}

sub set_results {
   my ( $self, $results ) = @_;
   $self->{result_classes} = $results->{classes};
   $self->{result_globals} = $results->{globals};
   $self->{result_samples} = $results->{samples};
   return;
}

sub stats {
   my ( $self ) = @_;
   return {
      classes => $self->{class_metrics},
      globals => $self->{global_metrics},
   };
}

sub attributes {
   my ( $self ) = @_;
   return $self->{type_for};
}

sub set_attribute_types {
   my ( $self, $attrib_types ) = @_;
   $self->{type_for} = $attrib_types;
   return;
}

sub type_for {
   my ( $self, $attrib ) = @_;
   return $self->{type_for}->{$attrib};
}

sub make_handler {
   my ( $self, %args ) = @_;
   my @required_args = qw(event attribute);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $attrib) = @args{@required_args};

   my $val;
   eval { $val= $self->_get_value(%args); };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d("Cannot make", $attrib, "handler:", $EVAL_ERROR);
      return;
   }
   return unless defined $val; # can't determine type if it's undef

   my $float_re = qr{[+-]?(?:(?=\d|[.])\d+(?:[.])\d{0,})(?:E[+-]?\d+)?}i;
   my $type = $self->type_for($attrib)           ? $self->type_for($attrib)
            : $attrib =~ m/_crc$/                ? 'string'
            : $val    =~ m/^(?:\d+|$float_re)$/o ? 'num'
            : $val    =~ m/^(?:Yes|No)$/         ? 'bool'
            :                                      'string';
   MKDEBUG && _d('Type for', $attrib, 'is', $type, '(sample:', $val, ')');
   $self->{type_for}->{$attrib} = $type;

   my @lines;

   my %track = (
      sum => $type =~ m/num|bool/    ? 1 : 0,  # sum of values
      unq => $type =~ m/bool|string/ ? 1 : 0,  # count of unique values seen
      all => $type eq 'num'          ? 1 : 0,  # all values in bucketed list
   );

   my $trf = ($type eq 'bool') ? q{(($val || '') eq 'Yes') ? 1 : 0}
           :                     undef;
   if ( $trf ) {
      push @lines, q{$val = } . $trf . ';';
   }

   if ( $attrib eq 'Query_time' ) {
      push @lines, (
         '$val =~ s/^(\d+(?:\.\d+)?).*/$1/;',
         '$event->{\''.$attrib.'\'} = $val;',
      );
   }

   if ( $type eq 'num' && $self->{attrib_limit} ) {
      push @lines, (
         "if ( \$val > $self->{attrib_limit} ) {",
         '   $val = $class->{last} ||= 0;',
         '}',
         '$class->{last} = $val;',
      );
   }

   my $lt = $type eq 'num' ? '<' : 'lt';
   my $gt = $type eq 'num' ? '>' : 'gt';
   foreach my $place ( qw($class $global) ) {
      my @tmp;  # hold lines until PLACE placeholder is replaced

      push @tmp, '++PLACE->{cnt};';  # count of all values seen

      if ( $attrib =~ m/_crc$/ ) {
         push @tmp, '$val = $val % 1_000;';
      }

      push @tmp, (
         'PLACE->{min} = $val if !defined PLACE->{min} || $val '
            . $lt . ' PLACE->{min};',
      );
      push @tmp, (
         'PLACE->{max} = $val if !defined PLACE->{max} || $val '
         . $gt . ' PLACE->{max};',
      );
      if ( $track{sum} ) {
         push @tmp, 'PLACE->{sum} += $val;';
      }

      if ( $track{all} ) {
         push @tmp, (
            'exists PLACE->{all} or PLACE->{all} = {};',
            '++PLACE->{all}->{ EventAggregator::bucket_idx($val) };',
         );
      }

      push @lines, map { s/PLACE/$place/g; $_ } @tmp;
   }

   if ( $track{unq} ) {
      push @lines, '++$class->{unq}->{$val}';
   }

   if ( $args{worst} ) {
      my $op = $type eq 'num' ? '>=' : 'ge';
      push @lines, (
         'if ( $val ' . $op . ' ($class->{max} || 0) ) {',
         '   $samples->{$group_by} = $event;',
         '}',
      );
   }

   my @unrolled = (
      "\$val = \$event->{'$attrib'};", 
      
      ( map  { "\$val = \$event->{'$_'} unless defined \$val;" }
        grep { $_ ne $attrib } @{$args{alternates}}
      ),
      
      'defined $val && do {',
         @lines,
      '};',
   );
   $self->{unrolled_for}->{$attrib} = join("\n", @unrolled);

   my @code = (
      'sub {',
         'my ( $event, $class, $global, $samples, $group_by ) = @_;',
         'my ($val, $idx);',

         $self->{unrolled_for}->{$attrib},

         'return;',
      '}',
   );
   $self->{code_for}->{$attrib} = join("\n", @code);
   MKDEBUG && _d($attrib, 'handler code:', $self->{code_for}->{$attrib});
   my $sub = eval $self->{code_for}->{$attrib};
   if ( $EVAL_ERROR ) {
      die "Failed to compile $attrib handler code: $EVAL_ERROR";
   }

   return $sub;
}

sub bucket_idx {
   my ( $val ) = @_;
   return 0 if $val < MIN_BUCK;
   my $idx = int(BASE_OFFSET + log($val)/BASE_LOG);
   return $idx > (NUM_BUCK-1) ? (NUM_BUCK-1) : $idx;
}

sub bucket_value {
   my ( $bucket ) = @_;
   return 0 if $bucket == 0;
   die "Invalid bucket: $bucket" if $bucket < 0 || $bucket > (NUM_BUCK-1);
   return (BUCK_SIZE**($bucket-1)) * MIN_BUCK;
}

{
   my @buck_tens;
   sub buckets_of {
      return @buck_tens if @buck_tens;

      my $start_bucket  = 0;
      my @base10_starts = (0);
      map { push @base10_starts, (10**$_)*MIN_BUCK } (1..7);

      for my $base10_bucket ( 0..($#base10_starts-1) ) {
         my $next_bucket = bucket_idx( $base10_starts[$base10_bucket+1] );
         MKDEBUG && _d('Base 10 bucket', $base10_bucket, 'maps to',
            'base 1.05 buckets', $start_bucket, '..', $next_bucket-1);
         for my $base1_05_bucket ($start_bucket..($next_bucket-1)) {
            $buck_tens[$base1_05_bucket] = $base10_bucket;
         }
         $start_bucket = $next_bucket;
      }

      map { $buck_tens[$_] = 7 } ($start_bucket..(NUM_BUCK-1));

      return @buck_tens;
   }
}

sub calculate_statistical_metrics {
   my ( $self, %args ) = @_;
   my $classes        = $self->{result_classes};
   my $globals        = $self->{result_globals};
   my $class_metrics  = $self->{class_metrics};
   my $global_metrics = $self->{global_metrics};
   MKDEBUG && _d('Calculating statistical_metrics');
   foreach my $attrib ( keys %$globals ) {
      if ( exists $globals->{$attrib}->{all} ) {
         $global_metrics->{$attrib}
            = $self->_calc_metrics(
               $globals->{$attrib}->{all},
               $globals->{$attrib},
            );
      }

      foreach my $class ( keys %$classes ) {
         if ( exists $classes->{$class}->{$attrib}->{all} ) {
            $class_metrics->{$class}->{$attrib}
               = $self->_calc_metrics(
                  $classes->{$class}->{$attrib}->{all},
                  $classes->{$class}->{$attrib}
               );

            if ( $args{apdex_t} && $attrib eq 'Query_time' ) {
               $class_metrics->{$class}->{$attrib}->{apdex_t} = $args{apdex_t};
               $class_metrics->{$class}->{$attrib}->{apdex}
                  = $self->calculate_apdex(
                     t       => $args{apdex_t},
                     samples => $classes->{$class}->{$attrib}->{all},
                  );
            }
         }
      }
   }

   return;
}

sub _calc_metrics {
   my ( $self, $vals, $args ) = @_;
   my $statistical_metrics = {
      pct_95    => 0,
      stddev    => 0,
      median    => 0,
      cutoff    => undef,
   };

   return $statistical_metrics
      unless defined $vals && %$vals && $args->{cnt};

   my $n_vals = $args->{cnt};
   if ( $n_vals == 1 || $args->{max} == $args->{min} ) {
      my $v      = $args->{max} || 0;
      my $bucket = int(6 + ( log($v > 0 ? $v : MIN_BUCK) / log(10)));
      $bucket    = $bucket > 7 ? 7 : $bucket < 0 ? 0 : $bucket;
      return {
         pct_95 => $v,
         stddev => 0,
         median => $v,
         cutoff => $n_vals,
      };
   }
   elsif ( $n_vals == 2 ) {
      foreach my $v ( $args->{min}, $args->{max} ) {
         my $bucket = int(6 + ( log($v && $v > 0 ? $v : MIN_BUCK) / log(10)));
         $bucket = $bucket > 7 ? 7 : $bucket < 0 ? 0 : $bucket;
      }
      my $v      = $args->{max} || 0;
      my $mean = (($args->{min} || 0) + $v) / 2;
      return {
         pct_95 => $v,
         stddev => sqrt((($v - $mean) ** 2) *2),
         median => $mean,
         cutoff => $n_vals,
      };
   }

   my $cutoff = $n_vals >= 10 ? int ( $n_vals * 0.95 ) : $n_vals;
   $statistical_metrics->{cutoff} = $cutoff;

   my $total_left = $n_vals;
   my $top_vals   = $n_vals - $cutoff; # vals > 95th
   my $sum_excl   = 0;
   my $sum        = 0;
   my $sumsq      = 0;
   my $mid        = int($n_vals / 2);
   my $median     = 0;
   my $prev       = NUM_BUCK-1; # Used for getting median when $cutoff is odd
   my $bucket_95  = 0; # top bucket in 95th

   MKDEBUG && _d('total vals:', $total_left, 'top vals:', $top_vals, 'mid:', $mid);

   my @buckets = map { 0 } (0..NUM_BUCK-1);
   map { $buckets[$_] = $vals->{$_} } keys %$vals;
   $vals = \@buckets;  # repoint vals from given hashref to our array

   BUCKET:
   for my $bucket ( reverse 0..(NUM_BUCK-1) ) {
      my $val = $vals->[$bucket];
      next BUCKET unless $val; 

      $total_left -= $val;
      $sum_excl   += $val;
      $bucket_95   = $bucket if !$bucket_95 && $sum_excl > $top_vals;

      if ( !$median && $total_left <= $mid ) {
         $median = (($cutoff % 2) || ($val > 1)) ? $buck_vals[$bucket]
                 : ($buck_vals[$bucket] + $buck_vals[$prev]) / 2;
      }

      $sum    += $val * $buck_vals[$bucket];
      $sumsq  += $val * ($buck_vals[$bucket]**2);
      $prev   =  $bucket;
   }

   my $var      = $sumsq/$n_vals - ( ($sum/$n_vals) ** 2 );
   my $stddev   = $var > 0 ? sqrt($var) : 0;
   my $maxstdev = (($args->{max} || 0) - ($args->{min} || 0)) / 2;
   $stddev      = $stddev > $maxstdev ? $maxstdev : $stddev;

   MKDEBUG && _d('sum:', $sum, 'sumsq:', $sumsq, 'stddev:', $stddev,
      'median:', $median, 'prev bucket:', $prev,
      'total left:', $total_left, 'sum excl', $sum_excl,
      'bucket 95:', $bucket_95, $buck_vals[$bucket_95]);

   $statistical_metrics->{stddev} = $stddev;
   $statistical_metrics->{pct_95} = $buck_vals[$bucket_95];
   $statistical_metrics->{median} = $median;

   return $statistical_metrics;
}

sub metrics {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(attrib where) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $attrib = $args{attrib};
   my $where   = $args{where};

   my $stats      = $self->results();
   my $metrics    = $self->stats();
   my $store      = $stats->{classes}->{$where}->{$attrib};
   my $global_cnt = $stats->{globals}->{$attrib}->{cnt};

   return {
      cnt    => $store->{cnt},
      pct    => $global_cnt && $store->{cnt} ? $store->{cnt} / $global_cnt : 0,
      sum    => $store->{sum},
      min    => $store->{min},
      max    => $store->{max},
      avg    => $store->{sum} && $store->{cnt} ? $store->{sum} / $store->{cnt} : 0,
      median => $metrics->{classes}->{$where}->{$attrib}->{median} || 0,
      pct_95 => $metrics->{classes}->{$where}->{$attrib}->{pct_95} || 0,
      stddev => $metrics->{classes}->{$where}->{$attrib}->{stddev} || 0,

      apdex_t => $metrics->{classes}->{$where}->{$attrib}->{apdex_t},
      apdex   => $metrics->{classes}->{$where}->{$attrib}->{apdex},
   };
}

sub top_events {
   my ( $self, %args ) = @_;
   my $classes = $self->{result_classes};
   my @sorted = reverse sort { # Sorted list of $groupby values
      $classes->{$a}->{$args{attrib}}->{$args{orderby}}
         <=> $classes->{$b}->{$args{attrib}}->{$args{orderby}}
      } grep {
         defined $classes->{$_}->{$args{attrib}}->{$args{orderby}}
      } keys %$classes;
   my @chosen;  # top events
   my @other;   # other events (< top)
   my ($total, $count) = (0, 0);
   foreach my $groupby ( @sorted ) {
      if ( 
         (!$args{total} || $total < $args{total} )
         && ( !$args{count} || $count < $args{count} )
      ) {
         push @chosen, [$groupby, 'top', $count+1];
      }

      elsif ( $args{ol_attrib} && (!$args{ol_freq}
         || $classes->{$groupby}->{$args{ol_attrib}}->{cnt} >= $args{ol_freq})
      ) {
         my $stats = $self->{class_metrics}->{$groupby}->{$args{ol_attrib}};
         if ( ($stats->{pct_95} || 0) >= $args{ol_limit} ) {
            push @chosen, [$groupby, 'outlier', $count+1];
         }
         else {
            push @other, [$groupby, 'misc', $count+1];
         }
      }

      else {
         push @other, [$groupby, 'misc', $count+1];
      }

      $total += $classes->{$groupby}->{$args{attrib}}->{$args{orderby}};
      $count++;
   }
   return \@chosen, \@other;
}

sub add_new_attributes {
   my ( $self, $event ) = @_;
   return unless $event;

   map {
      my $attrib = $_;
      $self->{attributes}->{$attrib}  = [$attrib];
      $self->{alt_attribs}->{$attrib} = make_alt_attrib($attrib);
      push @{$self->{all_attribs}}, $attrib;
      MKDEBUG && _d('Added new attribute:', $attrib);
   }
   grep {
      $_ ne $self->{groupby}
      && !exists $self->{attributes}->{$_}
      && !exists $self->{ignore_attribs}->{$_}
   }
   keys %$event;

   return;
}

sub get_attributes {
   my ( $self ) = @_;
   return $self->{all_attribs};
}

sub events_processed {
   my ( $self ) = @_;
   return $self->{n_events};
}

sub make_alt_attrib {
   my ( @attribs ) = @_;

   my $attrib = shift @attribs;  # Primary attribute.
   return sub {} unless @attribs;  # No alternates.

   my @lines;
   push @lines, 'sub { my ( $event ) = @_; my $alt_attrib;';
   push @lines, map  {
         "\$alt_attrib = '$_' if !defined \$alt_attrib "
         . "&& exists \$event->{'$_'};"
      } @attribs;
   push @lines, 'return $alt_attrib; }';
   MKDEBUG && _d('alt attrib sub for', $attrib, ':', @lines);
   my $sub = eval join("\n", @lines);
   die if $EVAL_ERROR;
   return $sub;
}

sub merge {
   my ( @ea_objs ) = @_;
   MKDEBUG && _d('Merging', scalar @ea_objs, 'ea');
   return unless scalar @ea_objs;

   my $ea1   = shift @ea_objs;
   my $r1    = $ea1->results;
   my $worst = $ea1->{worst};  # for merging, finding worst sample

   my %attrib_types = %{ $ea1->attributes() };

   foreach my $ea ( @ea_objs ) {
      die "EventAggregator objects have different groupby: "
         . "$ea1->{groupby} and $ea->{groupby}"
         unless $ea1->{groupby} eq $ea->{groupby};
      die "EventAggregator objects have different worst: "
         . "$ea1->{worst} and $ea->{worst}"
         unless $ea1->{worst} eq $ea->{worst};
      
      my $attrib_types = $ea->attributes();
      map {
         $attrib_types{$_} = $attrib_types->{$_}
            unless exists $attrib_types{$_};
      } keys %$attrib_types;
   }

   my $r_merged = {
      classes => {},
      globals => _deep_copy_attribs($r1->{globals}),
      samples => {},
   };
   map {
      $r_merged->{classes}->{$_}
         = _deep_copy_attribs($r1->{classes}->{$_});

      @{$r_merged->{samples}->{$_}}{keys %{$r1->{samples}->{$_}}}
         = values %{$r1->{samples}->{$_}};
   } keys %{$r1->{classes}};

   for my $i ( 0..$#ea_objs ) {
      MKDEBUG && _d('Merging ea obj', ($i + 1));
      my $r2 = $ea_objs[$i]->results;

      eval {
         CLASS:
         foreach my $class ( keys %{$r2->{classes}} ) {
            my $r1_class = $r_merged->{classes}->{$class};
            my $r2_class = $r2->{classes}->{$class};

            if ( $r1_class && $r2_class ) {
               CLASS_ATTRIB:
               foreach my $attrib ( keys %$r2_class ) {
                  MKDEBUG && _d('merge', $attrib);
                  if ( $r1_class->{$attrib} && $r2_class->{$attrib} ) {
                     _add_attrib_vals($r1_class->{$attrib}, $r2_class->{$attrib});
                  }
                  elsif ( !$r1_class->{$attrib} ) {
                  MKDEBUG && _d('copy', $attrib);
                     $r1_class->{$attrib} =
                        _deep_copy_attrib_vals($r2_class->{$attrib})
                  }
               }
            }
            elsif ( !$r1_class ) {
               MKDEBUG && _d('copy class');
               $r_merged->{classes}->{$class} = _deep_copy_attribs($r2_class);
            }

            my $new_worst_sample;
            if ( $r_merged->{samples}->{$class} && $r2->{samples}->{$class} ) {
               if (   $r2->{samples}->{$class}->{$worst}
                    > $r_merged->{samples}->{$class}->{$worst} ) {
                  $new_worst_sample = $r2->{samples}->{$class}
               }
            }
            elsif ( !$r_merged->{samples}->{$class} ) {
               $new_worst_sample = $r2->{samples}->{$class};
            }
            if ( $new_worst_sample ) {
               MKDEBUG && _d('New worst sample:', $worst, '=',
                  $new_worst_sample->{$worst}, 'item:', substr($class, 0, 100));
               my %new_sample;
               @new_sample{keys %$new_worst_sample}
                  = values %$new_worst_sample;
               $r_merged->{samples}->{$class} = \%new_sample;
            }
         }
      };
      if ( $EVAL_ERROR ) {
         warn "Error merging class/sample: $EVAL_ERROR";
      }

      eval {
         GLOBAL_ATTRIB:
         MKDEBUG && _d('Merging global attributes');
         foreach my $attrib ( keys %{$r2->{globals}} ) {
            my $r1_global = $r_merged->{globals}->{$attrib};
            my $r2_global = $r2->{globals}->{$attrib};

            if ( $r1_global && $r2_global ) {
               MKDEBUG && _d('merge', $attrib);
               _add_attrib_vals($r1_global, $r2_global);
            }
            elsif ( !$r1_global ) {
               MKDEBUG && _d('copy', $attrib);
               $r_merged->{globals}->{$attrib}
                  = _deep_copy_attrib_vals($r2_global);
            }
         }
      };
      if ( $EVAL_ERROR ) {
         warn "Error merging globals: $EVAL_ERROR";
      }
   }

   my $ea_merged = new EventAggregator(
      groupby    => $ea1->{groupby},
      worst      => $ea1->{worst},
      attributes => { map { $_=>[$_] } keys %attrib_types },
   );
   $ea_merged->set_results($r_merged);
   $ea_merged->set_attribute_types(\%attrib_types);
   return $ea_merged;
}

sub _add_attrib_vals {
   my ( $vals1, $vals2 ) = @_;

   foreach my $val ( keys %$vals1 ) {
      my $val1 = $vals1->{$val};
      my $val2 = $vals2->{$val};

      if ( (!ref $val1) && (!ref $val2) ) {
         die "undefined $val value" unless defined $val1 && defined $val2;

         my $is_num = exists $vals1->{sum} ? 1 : 0;
         if ( $val eq 'max' ) {
            if ( $is_num ) {
               $vals1->{$val} = $val1 > $val2  ? $val1 : $val2;
            }
            else {
               $vals1->{$val} = $val1 gt $val2 ? $val1 : $val2;
            }
         }
         elsif ( $val eq 'min' ) {
            if ( $is_num ) {
               $vals1->{$val} = $val1 < $val2  ? $val1 : $val2;
            }
            else {
               $vals1->{$val} = $val1 lt $val2 ? $val1 : $val2;
            }
         }
         else {
            $vals1->{$val} += $val2;
         }
      }
      elsif ( (ref $val1 eq 'ARRAY') && (ref $val2 eq 'ARRAY') ) {
         die "Empty $val arrayref" unless @$val1 && @$val2;
         my $n_buckets = (scalar @$val1) - 1;
         for my $i ( 0..$n_buckets ) {
            $vals1->{$val}->[$i] += $val2->[$i];
         }
      }
      elsif ( (ref $val1 eq 'HASH')  && (ref $val2 eq 'HASH')  ) {
         die "Empty $val hashref" unless %$val1 and %$val2;
         map { $vals1->{$val}->{$_} += $val2->{$_} } keys %$val2;
      }
      else {
         MKDEBUG && _d('vals1:', Dumper($vals1));
         MKDEBUG && _d('vals2:', Dumper($vals2));
         die "$val type mismatch";
      }
   }

   return;
}

sub _deep_copy_attribs {
   my ( $attribs ) = @_;
   my $copy = {};
   foreach my $attrib ( keys %$attribs ) {
      $copy->{$attrib} = _deep_copy_attrib_vals($attribs->{$attrib});
   }
   return $copy;
}

sub _deep_copy_attrib_vals {
   my ( $vals ) = @_;
   my $copy;
   if ( ref $vals eq 'HASH' ) {
      $copy = {};
      foreach my $val ( keys %$vals ) {
         if ( my $ref_type = ref $val ) {
            if ( $ref_type eq 'ARRAY' ) {
               my $n_elems = (scalar @$val) - 1;
               $copy->{$val} = [ map { undef } ( 0..$n_elems ) ];
               for my $i ( 0..$n_elems ) {
                  $copy->{$val}->[$i] = $vals->{$val}->[$i];
               }
            }
            elsif ( $ref_type eq 'HASH' ) {
               $copy->{$val} = {};
               map { $copy->{$val}->{$_} += $vals->{$val}->{$_} }
                  keys %{$vals->{$val}}
            }
            else {
               die "I don't know how to deep copy a $ref_type reference";
            }
         }
         else {
            $copy->{$val} = $vals->{$val};
         }
      }
   }
   else {
      $copy = $vals;
   }
   return $copy;
}

sub calculate_apdex {
   my ( $self, %args ) = @_;
   my @required_args = qw(t samples);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($t, $samples) = @args{@required_args};

   if ( $t <= 0 ) {
      die "Invalid target threshold (T): $t.  T must be greater than zero";
   }

   my $f = 4 * $t;
   MKDEBUG && _d("Apdex T =", $t, "F =", $f);

   my $satisfied  = 0;
   my $tolerating = 0;
   my $frustrated = 0;  # just for debug output
   my $n_samples  = 0;
   BUCKET:
   for my $bucket ( keys %$samples ) {
      my $n_responses   = $samples->{$bucket};
      my $response_time = $buck_vals[$bucket];

      if ( $response_time <= $t ) {
         $satisfied += $n_responses;
      }
      elsif ( $response_time <= $f ) {
         $tolerating += $n_responses;
      }
      else {
         $frustrated += $n_responses;
      }

      $n_samples += $n_responses;
   }

   my $apdex = sprintf('%.2f', ($satisfied + ($tolerating / 2)) / $n_samples);
   MKDEBUG && _d($n_samples, "samples,", $satisfied, "satisfied,",
      $tolerating, "tolerating,", $frustrated, "frustrated, Apdex score:",
      $apdex);

   return $apdex;
}

sub _get_value {
   my ( $self, %args ) = @_;
   my ($event, $attrib, $alts) = @args{qw(event attribute alternates)};
   return unless $event && $attrib;

   my $value;
   if ( exists $event->{$attrib} ) {
      $value = $event->{$attrib};
   }
   elsif ( $alts ) {
      my $found_value = 0;
      foreach my $alt_attrib( @$alts ) {
         if ( exists $event->{$alt_attrib} ) {
            $value       = $event->{$alt_attrib};
            $found_value = 1;
            last;
         }
      }
      die "Event does not have attribute $attrib or any of its alternates"
         unless $found_value;
   }
   else {
      die "Event does not have attribute $attrib and there are no alterantes";
   }

   return $value;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End EventAggregator package
# ###########################################################################

# ###########################################################################
# QueryParser package 7452
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/QueryParser.pm
#   trunk/common/t/QueryParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package QueryParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;
our $tbl_ident = qr/(?:`[^`]+`|\w+)(?:\.(?:`[^`]+`|\w+))?/;
our $tbl_regex = qr{
         \b(?:FROM|JOIN|(?<!KEY\s)UPDATE|INTO) # Words that precede table names
         \b\s*
         \(?                                   # Optional paren around tables
         ($tbl_ident
            (?: (?:\s+ (?:AS\s+)? \w+)?, \s*$tbl_ident )*
         )
      }xio;
our $has_derived = qr{
      \b(?:FROM|JOIN|,)
      \s*\(\s*SELECT
   }xi;

our $data_def_stmts = qr/(?:CREATE|ALTER|TRUNCATE|DROP|RENAME)/i;

our $data_manip_stmts = qr/(?:INSERT|UPDATE|DELETE|REPLACE)/i;

sub new {
   my ( $class ) = @_;
   bless {}, $class;
}

sub get_tables {
   my ( $self, $query ) = @_;
   return unless $query;
   MKDEBUG && _d('Getting tables for', $query);

   my ( $ddl_stmt ) = $query =~ m/^\s*($data_def_stmts)\b/i;
   if ( $ddl_stmt ) {
      MKDEBUG && _d('Special table type:', $ddl_stmt);
      $query =~ s/IF\s+(?:NOT\s+)?EXISTS//i;
      if ( $query =~ m/$ddl_stmt DATABASE\b/i ) {
         MKDEBUG && _d('Query alters a database, not a table');
         return ();
      }
      if ( $ddl_stmt =~ m/CREATE/i && $query =~ m/$ddl_stmt\b.+?\bSELECT\b/i ) {
         my ($select) = $query =~ m/\b(SELECT\b.+)/is;
         MKDEBUG && _d('CREATE TABLE ... SELECT:', $select);
         return $self->get_tables($select);
      }
      my ($tbl) = $query =~ m/TABLE\s+($tbl_ident)(\s+.*)?/i;
      MKDEBUG && _d('Matches table:', $tbl);
      return ($tbl);
   }

   $query =~ s/ (?:LOW_PRIORITY|IGNORE|STRAIGHT_JOIN)//ig;

   if ( $query =~ /^\s*LOCK TABLES/i ) {
      MKDEBUG && _d('Special table type: LOCK TABLES');
      $query =~ s/^(\s*LOCK TABLES\s+)//;
      $query =~ s/\s+(?:READ|WRITE|LOCAL)+\s*//g;
      MKDEBUG && _d('Locked tables:', $query);
      $query = "FROM $query";
   }

   $query =~ s/\\["']//g;                # quoted strings
   $query =~ s/".*?"/?/sg;               # quoted strings
   $query =~ s/'.*?'/?/sg;               # quoted strings

   my @tables;
   foreach my $tbls ( $query =~ m/$tbl_regex/gio ) {
      MKDEBUG && _d('Match tables:', $tbls);

      next if $tbls =~ m/\ASELECT\b/i;

      foreach my $tbl ( split(',', $tbls) ) {
         $tbl =~ s/\s*($tbl_ident)(\s+.*)?/$1/gio;

         if ( $tbl !~ m/[a-zA-Z]/ ) {
            MKDEBUG && _d('Skipping suspicious table name:', $tbl);
            next;
         }

         push @tables, $tbl;
      }
   }
   return @tables;
}

sub has_derived_table {
   my ( $self, $query ) = @_;
   my $match = $query =~ m/$has_derived/;
   MKDEBUG && _d($query, 'has ' . ($match ? 'a' : 'no') . ' derived table');
   return $match;
}

sub get_aliases {
   my ( $self, $query, $list ) = @_;

   my $result = {
      DATABASE => {},
      TABLE    => {},
   };
   return $result unless $query;

   $query =~ s/ (?:LOW_PRIORITY|IGNORE|STRAIGHT_JOIN)//ig;

   $query =~ s/ (?:INNER|OUTER|CROSS|LEFT|RIGHT|NATURAL)//ig;

   my @tbl_refs;
   my ($tbl_refs, $from) = $query =~ m{
      (
         (FROM|INTO|UPDATE)\b\s*   # Keyword before table refs
         .+?                       # Table refs
      )
      (?:\s+|\z)                   # If the query does not end with the table
      (?:WHERE|ORDER|LIMIT|HAVING|SET|VALUES|\z) # Keyword after table refs
   }ix;

   if ( $tbl_refs ) {

      if ( $query =~ m/^(?:INSERT|REPLACE)/i ) {
         $tbl_refs =~ s/\([^\)]+\)\s*//;
      }

      MKDEBUG && _d('tbl refs:', $tbl_refs);

      my $before_tbl = qr/(?:,|JOIN|\s|$from)+/i;

      my $after_tbl  = qr/(?:,|JOIN|ON|USING|\z)/i;

      $tbl_refs =~ s/ = /=/g;

      while (
         $tbl_refs =~ m{
            $before_tbl\b\s*
               ( ($tbl_ident) (?:\s+ (?:AS\s+)? (\w+))? )
            \s*$after_tbl
         }xgio )
      {
         my ( $tbl_ref, $db_tbl, $alias ) = ($1, $2, $3);
         MKDEBUG && _d('Match table:', $tbl_ref);
         push @tbl_refs, $tbl_ref;
         $alias = $self->trim_identifier($alias);

         if ( $tbl_ref =~ m/^AS\s+\w+/i ) {
            MKDEBUG && _d('Subquery', $tbl_ref);
            $result->{TABLE}->{$alias} = undef;
            next;
         }

         my ( $db, $tbl ) = $db_tbl =~ m/^(?:(.*?)\.)?(.*)/;
         $db  = $self->trim_identifier($db);
         $tbl = $self->trim_identifier($tbl);
         $result->{TABLE}->{$alias || $tbl} = $tbl;
         $result->{DATABASE}->{$tbl}        = $db if $db;
      }
   }
   else {
      MKDEBUG && _d("No tables ref in", $query);
   }

   if ( $list ) {
      return \@tbl_refs;
   }
   else {
      return $result;
   }
}

sub split {
   my ( $self, $query ) = @_;
   return unless $query;
   $query = $self->clean_query($query);
   MKDEBUG && _d('Splitting', $query);

   my $verbs = qr{SELECT|INSERT|UPDATE|DELETE|REPLACE|UNION|CREATE}i;

   my @split_statements = grep { $_ } split(m/\b($verbs\b(?!(?:\s*\()))/io, $query);

   my @statements;
   if ( @split_statements == 1 ) {
      push @statements, $query;
   }
   else {
      for ( my $i = 0; $i <= $#split_statements; $i += 2 ) {
         push @statements, $split_statements[$i].$split_statements[$i+1];

         if ( $statements[-2] && $statements[-2] =~ m/on duplicate key\s+$/i ) {
            $statements[-2] .= pop @statements;
         }
      }
   }

   MKDEBUG && _d('statements:', map { $_ ? "<$_>" : 'none' } @statements);
   return @statements;
}

sub clean_query {
   my ( $self, $query ) = @_;
   return unless $query;
   $query =~ s!/\*.*?\*/! !g;  # Remove /* comment blocks */
   $query =~ s/^\s+//;         # Remove leading spaces
   $query =~ s/\s+$//;         # Remove trailing spaces
   $query =~ s/\s{2,}/ /g;     # Remove extra spaces
   return $query;
}

sub split_subquery {
   my ( $self, $query ) = @_;
   return unless $query;
   $query = $self->clean_query($query);
   $query =~ s/;$//;

   my @subqueries;
   my $sqno = 0;  # subquery number
   my $pos  = 0;
   while ( $query =~ m/(\S+)(?:\s+|\Z)/g ) {
      $pos = pos($query);
      my $word = $1;
      MKDEBUG && _d($word, $sqno);
      if ( $word =~ m/^\(?SELECT\b/i ) {
         my $start_pos = $pos - length($word) - 1;
         if ( $start_pos ) {
            $sqno++;
            MKDEBUG && _d('Subquery', $sqno, 'starts at', $start_pos);
            $subqueries[$sqno] = {
               start_pos => $start_pos,
               end_pos   => 0,
               len       => 0,
               words     => [$word],
               lp        => 1, # left parentheses
               rp        => 0, # right parentheses
               done      => 0,
            };
         }
         else {
            MKDEBUG && _d('Main SELECT at pos 0');
         }
      }
      else {
         next unless $sqno;  # next unless we're in a subquery
         MKDEBUG && _d('In subquery', $sqno);
         my $sq = $subqueries[$sqno];
         if ( $sq->{done} ) {
            MKDEBUG && _d('This subquery is done; SQL is for',
               ($sqno - 1 ? "subquery $sqno" : "the main SELECT"));
            next;
         }
         push @{$sq->{words}}, $word;
         my $lp = ($word =~ tr/\(//) || 0;
         my $rp = ($word =~ tr/\)//) || 0;
         MKDEBUG && _d('parentheses left', $lp, 'right', $rp);
         if ( ($sq->{lp} + $lp) - ($sq->{rp} + $rp) == 0 ) {
            my $end_pos = $pos - 1;
            MKDEBUG && _d('Subquery', $sqno, 'ends at', $end_pos);
            $sq->{end_pos} = $end_pos;
            $sq->{len}     = $end_pos - $sq->{start_pos};
         }
      }
   }

   for my $i ( 1..$#subqueries ) {
      my $sq = $subqueries[$i];
      next unless $sq;
      $sq->{sql} = join(' ', @{$sq->{words}});
      substr $query,
         $sq->{start_pos} + 1,  # +1 for (
         $sq->{len} - 1,        # -1 for )
         "__subquery_$i";
   }

   return $query, map { $_->{sql} } grep { defined $_ } @subqueries;
}

sub query_type {
   my ( $self, $query, $qr ) = @_;
   my ($type, undef) = $qr->distill_verbs($query);
   my $rw;
   if ( $type =~ m/^SELECT\b/ ) {
      $rw = 'read';
   }
   elsif ( $type =~ m/^$data_manip_stmts\b/
           || $type =~ m/^$data_def_stmts\b/  ) {
      $rw = 'write'
   }

   return {
      type => $type,
      rw   => $rw,
   }
}

sub get_columns {
   my ( $self, $query ) = @_;
   my $cols = [];
   return $cols unless $query;
   my $cols_def;

   if ( $query =~ m/^SELECT/i ) {
      $query =~ s/
         ^SELECT\s+
           (?:ALL
              |DISTINCT
              |DISTINCTROW
              |HIGH_PRIORITY
              |STRAIGHT_JOIN
              |SQL_SMALL_RESULT
              |SQL_BIG_RESULT
              |SQL_BUFFER_RESULT
              |SQL_CACHE
              |SQL_NO_CACHE
              |SQL_CALC_FOUND_ROWS
           )\s+
      /SELECT /xgi;
      ($cols_def) = $query =~ m/^SELECT\s+(.+?)\s+FROM/i;
   }
   elsif ( $query =~ m/^(?:INSERT|REPLACE)/i ) {
      ($cols_def) = $query =~ m/\(([^\)]+)\)\s*VALUE/i;
   }

   MKDEBUG && _d('Columns:', $cols_def);
   if ( $cols_def ) {
      @$cols = split(',', $cols_def);
      map {
         my $col = $_;
         $col = s/^\s+//g;
         $col = s/\s+$//g;
         $col;
      } @$cols;
   }

   return $cols;
}

sub parse {
   my ( $self, $query ) = @_;
   return unless $query;
   my $parsed = {};

   $query =~ s/\n/ /g;
   $query = $self->clean_query($query);

   $parsed->{query}   = $query,
   $parsed->{tables}  = $self->get_aliases($query, 1);
   $parsed->{columns} = $self->get_columns($query);

   my ($type) = $query =~ m/^(\w+)/;
   $parsed->{type} = lc $type;


   $parsed->{sub_queries} = [];

   return $parsed;
}

sub extract_tables {
   my ( $self, %args ) = @_;
   my $query      = $args{query};
   my $default_db = $args{default_db};
   my $q          = $self->{Quoter} || $args{Quoter};
   return unless $query;
   MKDEBUG && _d('Extracting tables');
   my @tables;
   my %seen;
   foreach my $db_tbl ( $self->get_tables($query) ) {
      next unless $db_tbl;
      next if $seen{$db_tbl}++; # Unique-ify for issue 337.
      my ( $db, $tbl ) = $q->split_unquote($db_tbl);
      push @tables, [ $db || $default_db, $tbl ];
   }
   return @tables;
}

sub trim_identifier {
   my ($self, $str) = @_;
   return unless defined $str;
   $str =~ s/`//g;
   $str =~ s/^\s+//;
   $str =~ s/\s+$//;
   return $str;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End QueryParser package
# ###########################################################################

# ###########################################################################
# QueryRewriter package 7473
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/QueryRewriter.pm
#   trunk/common/t/QueryRewriter.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
use strict;
use warnings FATAL => 'all';

package QueryRewriter;

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

our $verbs   = qr{^SHOW|^FLUSH|^COMMIT|^ROLLBACK|^BEGIN|SELECT|INSERT
                  |UPDATE|DELETE|REPLACE|^SET|UNION|^START|^LOCK}xi;
my $quote_re = qr/"(?:(?!(?<!\\)").)*"|'(?:(?!(?<!\\)').)*'/; # Costly!
my $bal;
$bal         = qr/
                  \(
                  (?:
                     (?> [^()]+ )    # Non-parens without backtracking
                     |
                     (??{ $bal })    # Group with matching parens
                  )*
                  \)
                 /x;

my $olc_re = qr/(?:--|#)[^'"\r\n]*(?=[\r\n]|\Z)/;  # One-line comments
my $mlc_re = qr#/\*[^!].*?\*/#sm;                  # But not /*!version */
my $vlc_re = qr#/\*.*?[0-9+].*?\*/#sm;             # For SHOW + /*!version */
my $vlc_rf = qr#^(SHOW).*?/\*![0-9+].*?\*/#sm;     # Variation for SHOW


sub new {
   my ( $class, %args ) = @_;
   my $self = { %args };
   return bless $self, $class;
}

sub strip_comments {
   my ( $self, $query ) = @_;
   return unless $query;
   $query =~ s/$olc_re//go;
   $query =~ s/$mlc_re//go;
   if ( $query =~ m/$vlc_rf/i ) { # contains show + version
      $query =~ s/$vlc_re//go;
   }
   return $query;
}

sub shorten {
   my ( $self, $query, $length ) = @_;
   $query =~ s{
      \A(
         (?:INSERT|REPLACE)
         (?:\s+LOW_PRIORITY|DELAYED|HIGH_PRIORITY|IGNORE)?
         (?:\s\w+)*\s+\S+\s+VALUES\s*\(.*?\)
      )
      \s*,\s*\(.*?(ON\s+DUPLICATE|\Z)}
      {$1 /*... omitted ...*/$2}xsi;

   return $query unless $query =~ m/IN\s*\(\s*(?!select)/i;

   my $last_length  = 0;
   my $query_length = length($query);
   while (
      $length          > 0
      && $query_length > $length
      && $query_length < ( $last_length || $query_length + 1 )
   ) {
      $last_length = $query_length;
      $query =~ s{
         (\bIN\s*\()    # The opening of an IN list
         ([^\)]+)       # Contents of the list, assuming no item contains paren
         (?=\))           # Close of the list
      }
      {
         $1 . __shorten($2)
      }gexsi;
   }

   return $query;
}

sub __shorten {
   my ( $snippet ) = @_;
   my @vals = split(/,/, $snippet);
   return $snippet unless @vals > 20;
   my @keep = splice(@vals, 0, 20);  # Remove and save the first 20 items
   return
      join(',', @keep)
      . "/*... omitted "
      . scalar(@vals)
      . " items ...*/";
}

sub fingerprint {
   my ( $self, $query ) = @_;

   $query =~ m#\ASELECT /\*!40001 SQL_NO_CACHE \*/ \* FROM `# # mysqldump query
      && return 'mysqldump';
   $query =~ m#/\*\w+\.\w+:[0-9]/[0-9]\*/#     # mk-table-checksum, etc query
      && return 'maatkit';
   $query =~ m/\Aadministrator command: /
      && return $query;
   $query =~ m/\A\s*(call\s+\S+)\(/i
      && return lc($1); # Warning! $1 used, be careful.
   if ( my ($beginning) = $query =~ m/\A((?:INSERT|REPLACE)(?: IGNORE)?\s+INTO.+?VALUES\s*\(.*?\))\s*,\s*\(/is ) {
      $query = $beginning; # Shorten multi-value INSERT statements ASAP
   }
  
   $query =~ s/$olc_re//go;
   $query =~ s/$mlc_re//go;
   $query =~ s/\Ause \S+\Z/use ?/i       # Abstract the DB in USE
      && return $query;

   $query =~ s/\\["']//g;                # quoted strings
   $query =~ s/".*?"/?/sg;               # quoted strings
   $query =~ s/'.*?'/?/sg;               # quoted strings
   $query =~ s/[0-9+-][0-9a-f.xb+-]*/?/g;# Anything vaguely resembling numbers
   $query =~ s/[xb.+-]\?/?/g;            # Clean up leftovers
   $query =~ s/\A\s+//;                  # Chop off leading whitespace
   chomp $query;                         # Kill trailing whitespace
   $query =~ tr[ \n\t\r\f][ ]s;          # Collapse whitespace
   $query = lc $query;
   $query =~ s/\bnull\b/?/g;             # Get rid of NULLs
   $query =~ s{                          # Collapse IN and VALUES lists
               \b(in|values?)(?:[\s,]*\([\s?,]*\))+
              }
              {$1(?+)}gx;
   $query =~ s{                          # Collapse UNION
               \b(select\s.*?)(?:(\sunion(?:\sall)?)\s\1)+
              }
              {$1 /*repeat$2*/}xg;
   $query =~ s/\blimit \?(?:, ?\?| offset \?)?/limit ?/; # LIMIT

   if ( $query =~ m/\bORDER BY /gi ) {  # Find, anchor on ORDER BY clause
      1 while $query =~ s/\G(.+?)\s+ASC/$1/gi && pos $query;
   }

   return $query;
}

sub distill_verbs {
   my ( $self, $query ) = @_;

   $query =~ m/\A\s*call\s+(\S+)\(/i && return "CALL $1";
   $query =~ m/\A\s*use\s+/          && return "USE";
   $query =~ m/\A\s*UNLOCK TABLES/i  && return "UNLOCK";
   $query =~ m/\A\s*xa\s+(\S+)/i     && return "XA_$1";

   if ( $query =~ m/\Aadministrator command:/ ) {
      $query =~ s/administrator command:/ADMIN/;
      $query = uc $query;
      return $query;
   }

   $query = $self->strip_comments($query);

   if ( $query =~ m/\A\s*SHOW\s+/i ) {
      MKDEBUG && _d($query);

      $query = uc $query;
      $query =~ s/\s+(?:GLOBAL|SESSION|FULL|STORAGE|ENGINE)\b/ /g;
      $query =~ s/\s+COUNT[^)]+\)//g;

      $query =~ s/\s+(?:FOR|FROM|LIKE|WHERE|LIMIT|IN)\b.+//ms;

      $query =~ s/\A(SHOW(?:\s+\S+){1,2}).*\Z/$1/s;
      $query =~ s/\s+/ /g;
      MKDEBUG && _d($query);
      return $query;
   }

   eval $QueryParser::data_def_stmts;
   eval $QueryParser::tbl_ident;
   my ( $dds ) = $query =~ /^\s*($QueryParser::data_def_stmts)\b/i;
   if ( $dds) {
      my ( $obj ) = $query =~ m/$dds.+(DATABASE|TABLE)\b/i;
      $obj = uc $obj if $obj;
      MKDEBUG && _d('Data def statment:', $dds, 'obj:', $obj);
      my ($db_or_tbl)
         = $query =~ m/(?:TABLE|DATABASE)\s+($QueryParser::tbl_ident)(\s+.*)?/i;
      MKDEBUG && _d('Matches db or table:', $db_or_tbl);
      return uc($dds . ($obj ? " $obj" : '')), $db_or_tbl;
   }

   my @verbs = $query =~ m/\b($verbs)\b/gio;
   @verbs    = do {
      my $last = '';
      grep { my $pass = $_ ne $last; $last = $_; $pass } map { uc } @verbs;
   };

   if ( ($verbs[0] || '') eq 'SELECT' && @verbs > 1 ) {
      MKDEBUG && _d("False-positive verbs after SELECT:", @verbs[1..$#verbs]);
      my $union = grep { $_ eq 'UNION' } @verbs;
      @verbs    = $union ? qw(SELECT UNION) : qw(SELECT);
   }

   my $verb_str = join(q{ }, @verbs);
   return $verb_str;
}

sub __distill_tables {
   my ( $self, $query, $table, %args ) = @_;
   my $qp = $args{QueryParser} || $self->{QueryParser};
   die "I need a QueryParser argument" unless $qp;

   my @tables = map {
      $_ =~ s/`//g;
      $_ =~ s/(_?)[0-9]+/$1?/g;
      $_;
   } grep { defined $_ } $qp->get_tables($query);

   push @tables, $table if $table;

   @tables = do {
      my $last = '';
      grep { my $pass = $_ ne $last; $last = $_; $pass } @tables;
   };

   return @tables;
}

sub distill {
   my ( $self, $query, %args ) = @_;

   if ( $args{generic} ) {
      my ($cmd, $arg) = $query =~ m/^(\S+)\s+(\S+)/;
      return '' unless $cmd;
      $query = (uc $cmd) . ($arg ? " $arg" : '');
   }
   else {
      my ($verbs, $table)  = $self->distill_verbs($query, %args);

      if ( $verbs && $verbs =~ m/^SHOW/ ) {
         my %alias_for = qw(
            SCHEMA   DATABASE
            KEYS     INDEX
            INDEXES  INDEX
         );
         map { $verbs =~ s/$_/$alias_for{$_}/ } keys %alias_for;
         $query = $verbs;
      }
      else {
         my @tables = $self->__distill_tables($query, $table, %args);
         $query     = join(q{ }, $verbs, @tables); 
      } 
   }

   if ( $args{trf} ) {
      $query = $args{trf}->($query, %args);
   }

   return $query;
}

sub convert_to_select {
   my ( $self, $query ) = @_;
   return unless $query;

   return if $query =~ m/=\s*\(\s*SELECT /i;

   $query =~ s{
                 \A.*?
                 update(?:\s+(?:low_priority|ignore))?\s+(.*?)
                 \s+set\b(.*?)
                 (?:\s*where\b(.*?))?
                 (limit\s*[0-9]+(?:\s*,\s*[0-9]+)?)?
                 \Z
              }
              {__update_to_select($1, $2, $3, $4)}exsi
      || $query =~ s{
                    \A.*?
                    (?:insert(?:\s+ignore)?|replace)\s+
                    .*?\binto\b(.*?)\(([^\)]+)\)\s*
                    values?\s*(\(.*?\))\s*
                    (?:\blimit\b|on\s+duplicate\s+key.*)?\s*
                    \Z
                 }
                 {__insert_to_select($1, $2, $3)}exsi
      || $query =~ s{
                    \A.*?
                    (?:insert(?:\s+ignore)?|replace)\s+
                    (?:.*?\binto)\b(.*?)\s*
                    set\s+(.*?)\s*
                    (?:\blimit\b|on\s+duplicate\s+key.*)?\s*
                    \Z
                 }
                 {__insert_to_select_with_set($1, $2)}exsi
      || $query =~ s{
                    \A.*?
                    delete\s+(.*?)
                    \bfrom\b(.*)
                    \Z
                 }
                 {__delete_to_select($1, $2)}exsi;
   $query =~ s/\s*on\s+duplicate\s+key\s+update.*\Z//si;
   $query =~ s/\A.*?(?=\bSELECT\s*\b)//ism;
   return $query;
}

sub convert_select_list {
   my ( $self, $query ) = @_;
   $query =~ s{
               \A\s*select(.*?)\bfrom\b
              }
              {$1 =~ m/\*/ ? "select 1 from" : "select isnull(coalesce($1)) from"}exi;
   return $query;
}

sub __delete_to_select {
   my ( $delete, $join ) = @_;
   if ( $join =~ m/\bjoin\b/ ) {
      return "select 1 from $join";
   }
   return "select * from $join";
}

sub __insert_to_select {
   my ( $tbl, $cols, $vals ) = @_;
   MKDEBUG && _d('Args:', @_);
   my @cols = split(/,/, $cols);
   MKDEBUG && _d('Cols:', @cols);
   $vals =~ s/^\(|\)$//g; # Strip leading/trailing parens
   my @vals = $vals =~ m/($quote_re|[^,]*${bal}[^,]*|[^,]+)/g;
   MKDEBUG && _d('Vals:', @vals);
   if ( @cols == @vals ) {
      return "select * from $tbl where "
         . join(' and ', map { "$cols[$_]=$vals[$_]" } (0..$#cols));
   }
   else {
      return "select * from $tbl limit 1";
   }
}

sub __insert_to_select_with_set {
   my ( $from, $set ) = @_;
   $set =~ s/,/ and /g;
   return "select * from $from where $set ";
}

sub __update_to_select {
   my ( $from, $set, $where, $limit ) = @_;
   return "select $set from $from "
      . ( $where ? "where $where" : '' )
      . ( $limit ? " $limit "      : '' );
}

sub wrap_in_derived {
   my ( $self, $query ) = @_;
   return unless $query;
   return $query =~ m/\A\s*select/i
      ? "select 1 from ($query) as x limit 1"
      : $query;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End QueryRewriter package
# ###########################################################################

# ###########################################################################
# Daemon package 6255
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Daemon.pm
#   trunk/common/t/Daemon.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package Daemon;

use strict;
use warnings FATAL => 'all';

use POSIX qw(setsid);
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(o) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $o = $args{o};
   my $self = {
      o        => $o,
      log_file => $o->has('log') ? $o->get('log') : undef,
      PID_file => $o->has('pid') ? $o->get('pid') : undef,
   };

   check_PID_file(undef, $self->{PID_file});

   MKDEBUG && _d('Daemonized child will log to', $self->{log_file});
   return bless $self, $class;
}

sub daemonize {
   my ( $self ) = @_;

   MKDEBUG && _d('About to fork and daemonize');
   defined (my $pid = fork()) or die "Cannot fork: $OS_ERROR";
   if ( $pid ) {
      MKDEBUG && _d('I am the parent and now I die');
      exit;
   }

   $self->{PID_owner} = $PID;
   $self->{child}     = 1;

   POSIX::setsid() or die "Cannot start a new session: $OS_ERROR";
   chdir '/'       or die "Cannot chdir to /: $OS_ERROR";

   $self->_make_PID_file();

   $OUTPUT_AUTOFLUSH = 1;

   if ( -t STDIN ) {
      close STDIN;
      open  STDIN, '/dev/null'
         or die "Cannot reopen STDIN to /dev/null: $OS_ERROR";
   }

   if ( $self->{log_file} ) {
      close STDOUT;
      open  STDOUT, '>>', $self->{log_file}
         or die "Cannot open log file $self->{log_file}: $OS_ERROR";

      close STDERR;
      open  STDERR, ">&STDOUT"
         or die "Cannot dupe STDERR to STDOUT: $OS_ERROR"; 
   }
   else {
      if ( -t STDOUT ) {
         close STDOUT;
         open  STDOUT, '>', '/dev/null'
            or die "Cannot reopen STDOUT to /dev/null: $OS_ERROR";
      }
      if ( -t STDERR ) {
         close STDERR;
         open  STDERR, '>', '/dev/null'
            or die "Cannot reopen STDERR to /dev/null: $OS_ERROR";
      }
   }

   MKDEBUG && _d('I am the child and now I live daemonized');
   return;
}

sub check_PID_file {
   my ( $self, $file ) = @_;
   my $PID_file = $self ? $self->{PID_file} : $file;
   MKDEBUG && _d('Checking PID file', $PID_file);
   if ( $PID_file && -f $PID_file ) {
      my $pid;
      eval { chomp($pid = `cat $PID_file`); };
      die "Cannot cat $PID_file: $OS_ERROR" if $EVAL_ERROR;
      MKDEBUG && _d('PID file exists; it contains PID', $pid);
      if ( $pid ) {
         my $pid_is_alive = kill 0, $pid;
         if ( $pid_is_alive ) {
            die "The PID file $PID_file already exists "
               . " and the PID that it contains, $pid, is running";
         }
         else {
            warn "Overwriting PID file $PID_file because the PID that it "
               . "contains, $pid, is not running";
         }
      }
      else {
         die "The PID file $PID_file already exists but it does not "
            . "contain a PID";
      }
   }
   else {
      MKDEBUG && _d('No PID file');
   }
   return;
}

sub make_PID_file {
   my ( $self ) = @_;
   if ( exists $self->{child} ) {
      die "Do not call Daemon::make_PID_file() for daemonized scripts";
   }
   $self->_make_PID_file();
   $self->{PID_owner} = $PID;
   return;
}

sub _make_PID_file {
   my ( $self ) = @_;

   my $PID_file = $self->{PID_file};
   if ( !$PID_file ) {
      MKDEBUG && _d('No PID file to create');
      return;
   }

   $self->check_PID_file();

   open my $PID_FH, '>', $PID_file
      or die "Cannot open PID file $PID_file: $OS_ERROR";
   print $PID_FH $PID
      or die "Cannot print to PID file $PID_file: $OS_ERROR";
   close $PID_FH
      or die "Cannot close PID file $PID_file: $OS_ERROR";

   MKDEBUG && _d('Created PID file:', $self->{PID_file});
   return;
}

sub _remove_PID_file {
   my ( $self ) = @_;
   if ( $self->{PID_file} && -f $self->{PID_file} ) {
      unlink $self->{PID_file}
         or warn "Cannot remove PID file $self->{PID_file}: $OS_ERROR";
      MKDEBUG && _d('Removed PID file');
   }
   else {
      MKDEBUG && _d('No PID to remove');
   }
   return;
}

sub DESTROY {
   my ( $self ) = @_;

   $self->_remove_PID_file() if ($self->{PID_owner} || 0) == $PID;

   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End Daemon package
# ###########################################################################

# ###########################################################################
# ChangeHandler package 6785
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/ChangeHandler.pm
#   trunk/common/t/ChangeHandler.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package ChangeHandler;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

my $DUPE_KEY  = qr/Duplicate entry/;
our @ACTIONS  = qw(DELETE REPLACE INSERT UPDATE);

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(Quoter left_db left_tbl right_db right_tbl
                        replace queue) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $q = $args{Quoter};

   my $self = {
      hex_blob     => 1,
      %args,
      left_db_tbl  => $q->quote(@args{qw(left_db left_tbl)}),
      right_db_tbl => $q->quote(@args{qw(right_db right_tbl)}),
   };

   $self->{src_db_tbl} = $self->{left_db_tbl};
   $self->{dst_db_tbl} = $self->{right_db_tbl};

   map { $self->{$_} = [] } @ACTIONS;
   $self->{changes} = { map { $_ => 0 } @ACTIONS };

   return bless $self, $class;
}

sub fetch_back {
   my ( $self, $dbh ) = @_;
   $self->{fetch_back} = $dbh;
   MKDEBUG && _d('Set fetch back dbh', $dbh);
   return;
}

sub set_src {
   my ( $self, $src, $dbh ) = @_;
   die "I need a src argument" unless $src;
   if ( lc $src eq 'left' ) {
      $self->{src_db_tbl} = $self->{left_db_tbl};
      $self->{dst_db_tbl} = $self->{right_db_tbl};
   }
   elsif ( lc $src eq 'right' ) {
      $self->{src_db_tbl} = $self->{right_db_tbl};
      $self->{dst_db_tbl} = $self->{left_db_tbl}; 
   }
   else {
      die "src argument must be either 'left' or 'right'"
   }
   MKDEBUG && _d('Set src to', $src);
   $self->fetch_back($dbh) if $dbh;
   return;
}

sub src {
   my ( $self ) = @_;
   return $self->{src_db_tbl};
}

sub dst {
   my ( $self ) = @_;
   return $self->{dst_db_tbl};
}

sub _take_action {
   my ( $self, $sql, $dbh ) = @_;
   MKDEBUG && _d('Calling subroutines on', $dbh, $sql);
   foreach my $action ( @{$self->{actions}} ) {
      $action->($sql, $dbh);
   }
   return;
}

sub change {
   my ( $self, $action, $row, $cols, $dbh ) = @_;
   MKDEBUG && _d($dbh, $action, 'where', $self->make_where_clause($row, $cols));

   return unless $action;

   $self->{changes}->{
      $self->{replace} && $action ne 'DELETE' ? 'REPLACE' : $action
   }++;
   if ( $self->{queue} ) {
      $self->__queue($action, $row, $cols, $dbh);
   }
   else {
      eval {
         my $func = "make_$action";
         $self->_take_action($self->$func($row, $cols), $dbh);
      };
      if ( $EVAL_ERROR =~ m/$DUPE_KEY/ ) {
         MKDEBUG && _d('Duplicate key violation; will queue and rewrite');
         $self->{queue}++;
         $self->{replace} = 1;
         $self->__queue($action, $row, $cols, $dbh);
      }
      elsif ( $EVAL_ERROR ) {
         die $EVAL_ERROR;
      }
   }
   return;
}

sub __queue {
   my ( $self, $action, $row, $cols, $dbh ) = @_;
   MKDEBUG && _d('Queueing change for later');
   if ( $self->{replace} ) {
      $action = $action eq 'DELETE' ? $action : 'REPLACE';
   }
   push @{$self->{$action}}, [ $row, $cols, $dbh ];
}

sub process_rows {
   my ( $self, $queue_level, $trace_msg ) = @_;
   my $error_count = 0;
   TRY: {
      if ( $queue_level && $queue_level < $self->{queue} ) { # see redo below!
         MKDEBUG && _d('Not processing now', $queue_level, '<', $self->{queue});
         return;
      }
      MKDEBUG && _d('Processing rows:');
      my ($row, $cur_act);
      eval {
         foreach my $action ( @ACTIONS ) {
            my $func = "make_$action";
            my $rows = $self->{$action};
            MKDEBUG && _d(scalar(@$rows), 'to', $action);
            $cur_act = $action;
            while ( @$rows ) {
               $row    = shift @$rows;
               my $sql = $self->$func(@$row);
               $sql   .= " /*maatkit $trace_msg*/" if $trace_msg;
               $self->_take_action($sql, $row->[2]);
            }
         }
         $error_count = 0;
      };
      if ( !$error_count++ && $EVAL_ERROR =~ m/$DUPE_KEY/ ) {
         MKDEBUG && _d('Duplicate key violation; re-queueing and rewriting');
         $self->{queue}++; # Defer rows to the very end
         $self->{replace} = 1;
         $self->__queue($cur_act, @$row);
         redo TRY;
      }
      elsif ( $EVAL_ERROR ) {
         die $EVAL_ERROR;
      }
   }
}

sub make_DELETE {
   my ( $self, $row, $cols ) = @_;
   MKDEBUG && _d('Make DELETE');
   return "DELETE FROM $self->{dst_db_tbl} WHERE "
      . $self->make_where_clause($row, $cols)
      . ' LIMIT 1';
}

sub make_UPDATE {
   my ( $self, $row, $cols ) = @_;
   MKDEBUG && _d('Make UPDATE');
   if ( $self->{replace} ) {
      return $self->make_row('REPLACE', $row, $cols);
   }
   my %in_where = map { $_ => 1 } @$cols;
   my $where = $self->make_where_clause($row, $cols);
   my @cols;
   if ( my $dbh = $self->{fetch_back} ) {
      my $sql = $self->make_fetch_back_query($where);
      MKDEBUG && _d('Fetching data on dbh', $dbh, 'for UPDATE:', $sql);
      my $res = $dbh->selectrow_hashref($sql);
      @{$row}{keys %$res} = values %$res;
      @cols = $self->sort_cols($res);
   }
   else {
      @cols = $self->sort_cols($row);
   }
   return "UPDATE $self->{dst_db_tbl} SET "
      . join(', ', map {
            $self->{Quoter}->quote($_)
            . '=' .  $self->{Quoter}->quote_val($row->{$_})
         } grep { !$in_where{$_} } @cols)
      . " WHERE $where LIMIT 1";
}

sub make_INSERT {
   my ( $self, $row, $cols ) = @_;
   MKDEBUG && _d('Make INSERT');
   if ( $self->{replace} ) {
      return $self->make_row('REPLACE', $row, $cols);
   }
   return $self->make_row('INSERT', $row, $cols);
}

sub make_REPLACE {
   my ( $self, $row, $cols ) = @_;
   MKDEBUG && _d('Make REPLACE');
   return $self->make_row('REPLACE', $row, $cols);
}

sub make_row {
   my ( $self, $verb, $row, $cols ) = @_;
   my @cols; 
   if ( my $dbh = $self->{fetch_back} ) {
      my $where = $self->make_where_clause($row, $cols);
      my $sql   = $self->make_fetch_back_query($where);
      MKDEBUG && _d('Fetching data on dbh', $dbh, 'for', $verb, ':', $sql);
      my $res = $dbh->selectrow_hashref($sql);
      @{$row}{keys %$res} = values %$res;
      @cols = $self->sort_cols($res);
   }
   else {
      @cols = $self->sort_cols($row);
   }
   my $q = $self->{Quoter};
   return "$verb INTO $self->{dst_db_tbl}("
      . join(', ', map { $q->quote($_) } @cols)
      . ') VALUES ('
      . join(', ', map { $q->quote_val($_) } @{$row}{@cols} )
      . ')';
}

sub make_where_clause {
   my ( $self, $row, $cols ) = @_;
   my @clauses = map {
      my $val = $row->{$_};
      my $sep = defined $val ? '=' : ' IS ';
      $self->{Quoter}->quote($_) . $sep . $self->{Quoter}->quote_val($val);
   } @$cols;
   return join(' AND ', @clauses);
}


sub get_changes {
   my ( $self ) = @_;
   return %{$self->{changes}};
}


sub sort_cols {
   my ( $self, $row ) = @_;
   my @cols;
   if ( $self->{tbl_struct} ) { 
      my $pos = $self->{tbl_struct}->{col_posn};
      my @not_in_tbl;
      @cols = sort {
            $pos->{$a} <=> $pos->{$b}
         }
         grep {
            if ( !defined $pos->{$_} ) {
               push @not_in_tbl, $_;
               0;
            }
            else {
               1;
            }
         }
         keys %$row;
      push @cols, @not_in_tbl if @not_in_tbl;
   }
   else {
      @cols = sort keys %$row;
   }
   return @cols;
}

sub make_fetch_back_query {
   my ( $self, $where ) = @_;
   die "I need a where argument" unless $where;
   my $cols       = '*';
   my $tbl_struct = $self->{tbl_struct};
   if ( $tbl_struct ) {
      $cols = join(', ',
         map {
            my $col = $_;
            if (    $self->{hex_blob}
                 && $tbl_struct->{type_for}->{$col} =~ m/blob|text|binary/ ) {
               $col = "IF(`$col`='', '', CONCAT('0x', HEX(`$col`))) AS `$col`";
            }
            else {
               $col = "`$col`";
            }
            $col;
         } @{ $tbl_struct->{cols} }
      );

      if ( !$cols ) {
         MKDEBUG && _d('Failed to make explicit columns list from tbl struct');
         $cols = '*';
      }
   }
   return "SELECT $cols FROM $self->{src_db_tbl} WHERE $where LIMIT 1";
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End ChangeHandler package
# ###########################################################################

# ###########################################################################
# RowDiff package 5697
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/RowDiff.pm
#   trunk/common/t/RowDiff.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package RowDiff;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   die "I need a dbh" unless $args{dbh};
   my $self = { %args };
   return bless $self, $class;
}

sub compare_sets {
   my ( $self, %args ) = @_;
   my @required_args = qw(left_sth right_sth syncer tbl_struct);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $left_sth   = $args{left_sth};
   my $right_sth  = $args{right_sth};
   my $syncer     = $args{syncer};
   my $tbl_struct = $args{tbl_struct};

   my ($lr, $rr);    # Current row from the left/right sths.
   $args{key_cols} = $syncer->key_cols();  # for key_cmp()

   my $left_done  = 0;
   my $right_done = 0;
   my $done       = $self->{done};

   do {
      if ( !$lr && !$left_done ) {
         MKDEBUG && _d('Fetching row from left');
         eval { $lr = $left_sth->fetchrow_hashref(); };
         MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
         $left_done = !$lr || $EVAL_ERROR ? 1 : 0;
      }
      elsif ( MKDEBUG ) {
         _d('Left still has rows');
      }

      if ( !$rr && !$right_done ) {
         MKDEBUG && _d('Fetching row from right');
         eval { $rr = $right_sth->fetchrow_hashref(); };
         MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
         $right_done = !$rr || $EVAL_ERROR ? 1 : 0;
      }
      elsif ( MKDEBUG ) {
         _d('Right still has rows');
      }

      my $cmp;
      if ( $lr && $rr ) {
         $cmp = $self->key_cmp(%args, lr => $lr, rr => $rr);
         MKDEBUG && _d('Key comparison on left and right:', $cmp);
      }
      if ( $lr || $rr ) {
         if ( $lr && $rr && defined $cmp && $cmp == 0 ) {
            MKDEBUG && _d('Left and right have the same key');
            $syncer->same_row(%args, lr => $lr, rr => $rr);
            $self->{same_row}->(%args, lr => $lr, rr => $rr)
               if $self->{same_row};
            $lr = $rr = undef; # Fetch another row from each side.
         }
         elsif ( !$rr || ( defined $cmp && $cmp < 0 ) ) {
            MKDEBUG && _d('Left is not in right');
            $syncer->not_in_right(%args, lr => $lr, rr => $rr);
            $self->{not_in_right}->(%args, lr => $lr, rr => $rr)
               if $self->{not_in_right};
            $lr = undef;
         }
         else {
            MKDEBUG && _d('Right is not in left');
            $syncer->not_in_left(%args, lr => $lr, rr => $rr);
            $self->{not_in_left}->(%args, lr => $lr, rr => $rr)
               if $self->{not_in_left};
            $rr = undef;
         }
      }
      $left_done = $right_done = 1 if $done && $done->(%args);
   } while ( !($left_done && $right_done) );
   MKDEBUG && _d('No more rows');
   $syncer->done_with_rows();
}

sub key_cmp {
   my ( $self, %args ) = @_;
   my @required_args = qw(lr rr key_cols tbl_struct);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless exists $args{$arg};
   }
   my ($lr, $rr, $key_cols, $tbl_struct) = @args{@required_args};
   MKDEBUG && _d('Comparing keys using columns:', join(',', @$key_cols));

   my $callback = $self->{key_cmp};
   my $trf      = $self->{trf};

   foreach my $col ( @$key_cols ) {
      my $l = $lr->{$col};
      my $r = $rr->{$col};
      if ( !defined $l || !defined $r ) {
         MKDEBUG && _d($col, 'is not defined in both rows');
         return defined $l ? 1 : defined $r ? -1 : 0;
      }
      else {
         if ( $tbl_struct->{is_numeric}->{$col} ) {   # Numeric column
            MKDEBUG && _d($col, 'is numeric');
            ($l, $r) = $trf->($l, $r, $tbl_struct, $col) if $trf;
            my $cmp = $l <=> $r;
            if ( $cmp ) {
               MKDEBUG && _d('Column', $col, 'differs:', $l, '!=', $r);
               $callback->($col, $l, $r) if $callback;
               return $cmp;
            }
         }
         elsif ( $l ne $r ) {
            my $cmp;
            my $coll = $tbl_struct->{collation_for}->{$col};
            if ( $coll && ( $coll ne 'latin1_swedish_ci'
                           || $l =~ m/[^\040-\177]/ || $r =~ m/[^\040-\177]/) )
            {
               MKDEBUG && _d('Comparing', $col, 'via MySQL');
               $cmp = $self->db_cmp($coll, $l, $r);
            }
            else {
               MKDEBUG && _d('Comparing', $col, 'in lowercase');
               $cmp = lc $l cmp lc $r;
            }
            if ( $cmp ) {
               MKDEBUG && _d('Column', $col, 'differs:', $l, 'ne', $r);
               $callback->($col, $l, $r) if $callback;
               return $cmp;
            }
         }
      }
   }
   return 0;
}

sub db_cmp {
   my ( $self, $collation, $l, $r ) = @_;
   if ( !$self->{sth}->{$collation} ) {
      if ( !$self->{charset_for} ) {
         MKDEBUG && _d('Fetching collations from MySQL');
         my @collations = @{$self->{dbh}->selectall_arrayref(
            'SHOW COLLATION', {Slice => { collation => 1, charset => 1 }})};
         foreach my $collation ( @collations ) {
            $self->{charset_for}->{$collation->{collation}}
               = $collation->{charset};
         }
      }
      my $sql = "SELECT STRCMP(_$self->{charset_for}->{$collation}? COLLATE $collation, "
         . "_$self->{charset_for}->{$collation}? COLLATE $collation) AS res";
      MKDEBUG && _d($sql);
      $self->{sth}->{$collation} = $self->{dbh}->prepare($sql);
   }
   my $sth = $self->{sth}->{$collation};
   $sth->execute($l, $r);
   return $sth->fetchall_arrayref()->[0]->[0];
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End RowDiff package
# ###########################################################################

# ###########################################################################
# TableChunker package 7169
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TableChunker.pm
#   trunk/common/t/TableChunker.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package TableChunker;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use POSIX qw(floor ceil);
use List::Util qw(min max);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(Quoter MySQLDump) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my %int_types  = map { $_ => 1 } qw(bigint date datetime int mediumint smallint time timestamp tinyint year);
   my %real_types = map { $_ => 1 } qw(decimal double float);

   my $self = {
      %args,
      int_types  => \%int_types,
      real_types => \%real_types,
      EPOCH      => '1970-01-01',
   };

   return bless $self, $class;
}

sub find_chunk_columns {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(tbl_struct) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $tbl_struct = $args{tbl_struct};

   my @possible_indexes;
   foreach my $index ( values %{ $tbl_struct->{keys} } ) {

      next unless $index->{type} eq 'BTREE';

      next if grep { defined } @{$index->{col_prefixes}};

      if ( $args{exact} ) {
         next unless $index->{is_unique} && @{$index->{cols}} == 1;
      }

      push @possible_indexes, $index;
   }
   MKDEBUG && _d('Possible chunk indexes in order:',
      join(', ', map { $_->{name} } @possible_indexes));

   my $can_chunk_exact = 0;
   my @candidate_cols;
   foreach my $index ( @possible_indexes ) { 
      my $col = $index->{cols}->[0];

      my $col_type = $tbl_struct->{type_for}->{$col};
      next unless $self->{int_types}->{$col_type}
               || $self->{real_types}->{$col_type}
               || $col_type =~ m/char/;

      push @candidate_cols, { column => $col, index => $index->{name} };
   }

   $can_chunk_exact = 1 if $args{exact} && scalar @candidate_cols;

   if ( MKDEBUG ) {
      my $chunk_type = $args{exact} ? 'Exact' : 'Inexact';
      _d($chunk_type, 'chunkable:',
         join(', ', map { "$_->{column} on $_->{index}" } @candidate_cols));
   }

   my @result;
   MKDEBUG && _d('Ordering columns by order in tbl, PK first');
   if ( $tbl_struct->{keys}->{PRIMARY} ) {
      my $pk_first_col = $tbl_struct->{keys}->{PRIMARY}->{cols}->[0];
      @result          = grep { $_->{column} eq $pk_first_col } @candidate_cols;
      @candidate_cols  = grep { $_->{column} ne $pk_first_col } @candidate_cols;
   }
   my $i = 0;
   my %col_pos = map { $_ => $i++ } @{$tbl_struct->{cols}};
   push @result, sort { $col_pos{$a->{column}} <=> $col_pos{$b->{column}} }
                    @candidate_cols;

   if ( MKDEBUG ) {
      _d('Chunkable columns:',
         join(', ', map { "$_->{column} on $_->{index}" } @result));
      _d('Can chunk exactly:', $can_chunk_exact);
   }

   return ($can_chunk_exact, @result);
}

sub calculate_chunks {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl tbl_struct chunk_col rows_in_range chunk_size);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   MKDEBUG && _d('Calculate chunks for',
      join(", ", map {"$_=".(defined $args{$_} ? $args{$_} : "undef")}
         qw(db tbl chunk_col min max rows_in_range chunk_size zero_chunk exact)
      ));

   if ( !$args{rows_in_range} ) {
      MKDEBUG && _d("Empty table");
      return '1=1';
   }

   if ( $args{rows_in_range} < $args{chunk_size} ) {
      MKDEBUG && _d("Chunk size larger than rows in range");
      return '1=1';
   }

   my $q          = $self->{Quoter};
   my $dbh        = $args{dbh};
   my $chunk_col  = $args{chunk_col};
   my $tbl_struct = $args{tbl_struct};
   my $col_type   = $tbl_struct->{type_for}->{$chunk_col};
   MKDEBUG && _d('chunk col type:', $col_type);

   my %chunker;
   if ( $tbl_struct->{is_numeric}->{$chunk_col} || $col_type =~ /date|time/ ) {
      %chunker = $self->_chunk_numeric(%args);
   }
   elsif ( $col_type =~ m/char/ ) {
      %chunker = $self->_chunk_char(%args);
   }
   else {
      die "Cannot chunk $col_type columns";
   }
   MKDEBUG && _d("Chunker:", Dumper(\%chunker));
   my ($col, $start_point, $end_point, $interval, $range_func)
      = @chunker{qw(col start_point end_point interval range_func)};

   my @chunks;
   if ( $start_point < $end_point ) {

      push @chunks, "$col = 0" if $chunker{have_zero_chunk};

      my ($beg, $end);
      my $iter = 0;
      for ( my $i = $start_point; $i < $end_point; $i += $interval ) {
         ($beg, $end) = $self->$range_func($dbh, $i, $interval, $end_point);

         if ( $iter++ == 0 ) {
            push @chunks,
               ($chunker{have_zero_chunk} ? "$col > 0 AND " : "")
               ."$col < " . $q->quote_val($end);
         }
         else {
            push @chunks, "$col >= " . $q->quote_val($beg) . " AND $col < " . $q->quote_val($end);
         }
      }

      my $chunk_range = lc $args{chunk_range} || 'open';
      my $nullable    = $args{tbl_struct}->{is_nullable}->{$args{chunk_col}};
      pop @chunks;
      if ( @chunks ) {
         push @chunks, "$col >= " . $q->quote_val($beg)
            . ($chunk_range eq 'openclosed'
               ? " AND $col <= " . $q->quote_val($args{max}) : "");
      }
      else {
         push @chunks, $nullable ? "$col IS NOT NULL" : '1=1';
      }
      if ( $nullable ) {
         push @chunks, "$col IS NULL";
      }
   }
   else {
      MKDEBUG && _d('No chunks; using single chunk 1=1');
      push @chunks, '1=1';
   }

   return @chunks;
}

sub _chunk_numeric {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl tbl_struct chunk_col rows_in_range chunk_size);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $q        = $self->{Quoter};
   my $db_tbl   = $q->quote($args{db}, $args{tbl});
   my $col_type = $args{tbl_struct}->{type_for}->{$args{chunk_col}};

   my $range_func;
   if ( $col_type =~ m/(?:int|year|float|double|decimal)$/ ) {
      $range_func  = 'range_num';
   }
   elsif ( $col_type =~ m/^(?:timestamp|date|time)$/ ) {
      $range_func  = "range_$col_type";
   }
   elsif ( $col_type eq 'datetime' ) {
      $range_func  = 'range_datetime';
   }

   my ($start_point, $end_point);
   eval {
      $start_point = $self->value_to_number(
         value       => $args{min},
         column_type => $col_type,
         dbh         => $args{dbh},
      );
      $end_point  = $self->value_to_number(
         value       => $args{max},
         column_type => $col_type,
         dbh         => $args{dbh},
      );
   };
   if ( $EVAL_ERROR ) {
      if ( $EVAL_ERROR =~ m/don't know how to chunk/ ) {
         die $EVAL_ERROR;
      }
      else {
         die "Error calculating chunk start and end points for table "
            . "`$args{tbl_struct}->{name}` on column `$args{chunk_col}` "
            . "with min/max values "
            . join('/',
                  map { defined $args{$_} ? $args{$_} : 'undef' } qw(min max))
            . ":\n\n"
            . $EVAL_ERROR
            . "\nVerify that the min and max values are valid for the column.  "
            . "If they are valid, this error could be caused by a bug in the "
            . "tool.";
      }
   }

   if ( !defined $start_point ) {
      MKDEBUG && _d('Start point is undefined');
      $start_point = 0;
   }
   if ( !defined $end_point || $end_point < $start_point ) {
      MKDEBUG && _d('End point is undefined or before start point');
      $end_point = 0;
   }
   MKDEBUG && _d("Actual chunk range:", $start_point, "to", $end_point);

   my $have_zero_chunk = 0;
   if ( $args{zero_chunk} ) {
      if ( $start_point != $end_point && $start_point >= 0 ) {
         MKDEBUG && _d('Zero chunking');
         my $nonzero_val = $self->get_nonzero_value(
            %args,
            db_tbl   => $db_tbl,
            col      => $args{chunk_col},
            col_type => $col_type,
            val      => $args{min}
         );
         $start_point = $self->value_to_number(
            value       => $nonzero_val,
            column_type => $col_type,
            dbh         => $args{dbh},
         );
         $have_zero_chunk = 1;
      }
      else {
         MKDEBUG && _d("Cannot zero chunk");
      }
   }
   MKDEBUG && _d("Using chunk range:", $start_point, "to", $end_point);

   my $interval = $args{chunk_size}
                * ($end_point - $start_point)
                / $args{rows_in_range};
   if ( $self->{int_types}->{$col_type} ) {
      $interval = ceil($interval);
   }
   $interval ||= $args{chunk_size};
   if ( $args{exact} ) {
      $interval = $args{chunk_size};
   }
   MKDEBUG && _d('Chunk interval:', $interval, 'units');

   return (
      col             => $q->quote($args{chunk_col}),
      start_point     => $start_point,
      end_point       => $end_point,
      interval        => $interval,
      range_func      => $range_func,
      have_zero_chunk => $have_zero_chunk,
   );
}

sub _chunk_char {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl tbl_struct chunk_col rows_in_range chunk_size);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $q         = $self->{Quoter};
   my $db_tbl    = $q->quote($args{db}, $args{tbl});
   my $dbh       = $args{dbh};
   my $chunk_col = $args{chunk_col};
   my $row;
   my $sql;

   $sql = "SELECT MIN($chunk_col), MAX($chunk_col) FROM $db_tbl "
        . "ORDER BY `$chunk_col`";
   MKDEBUG && _d($dbh, $sql);
   $row = $dbh->selectrow_arrayref($sql);
   my ($min_col, $max_col) = ($row->[0], $row->[1]);

   $sql = "SELECT ORD(?) AS min_col_ord, ORD(?) AS max_col_ord";
   MKDEBUG && _d($dbh, $sql);
   my $ord_sth = $dbh->prepare($sql);  # avoid quoting issues
   $ord_sth->execute($min_col, $max_col);
   $row = $ord_sth->fetchrow_arrayref();
   my ($min_col_ord, $max_col_ord) = ($row->[0], $row->[1]);
   MKDEBUG && _d("Min/max col char code:", $min_col_ord, $max_col_ord);

   my $base;
   my @chars;
   MKDEBUG && _d("Table charset:", $args{tbl_struct}->{charset});
   if ( ($args{tbl_struct}->{charset} || "") eq "latin1" ) {
      my @sorted_latin1_chars = (
          32,  33,  34,  35,  36,  37,  38,  39,  40,  41,  42,  43,  44,  45,
          46,  47,  48,  49,  50,  51,  52,  53,  54,  55,  56,  57,  58,  59,
          60,  61,  62,  63,  64,  65,  66,  67,  68,  69,  70,  71,  72,  73,
          74,  75,  76,  77,  78,  79,  80,  81,  82,  83,  84,  85,  86,  87,
          88,  89,  90,  91,  92,  93,  94,  95,  96, 123, 124, 125, 126, 161,
         162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175,
         176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 189,
         190, 191, 215, 216, 222, 223, 247, 255);

      my ($first_char, $last_char);
      for my $i ( 0..$#sorted_latin1_chars ) {
         $first_char = $i and last if $sorted_latin1_chars[$i] >= $min_col_ord;
      }
      for my $i ( $first_char..$#sorted_latin1_chars ) {
         $last_char = $i and last if $sorted_latin1_chars[$i] >= $max_col_ord;
      };

      @chars = map { chr $_; } @sorted_latin1_chars[$first_char..$last_char];
      $base  = scalar @chars;
   }
   else {

      my $tmp_tbl    = '__maatkit_char_chunking_map';
      my $tmp_db_tbl = $q->quote($args{db}, $tmp_tbl);
      $sql = "DROP TABLE IF EXISTS $tmp_db_tbl";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
      my $col_def = $args{tbl_struct}->{defs}->{$chunk_col};
      $sql        = "CREATE TEMPORARY TABLE $tmp_db_tbl ($col_def) "
                  . "ENGINE=MEMORY";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);

      $sql = "INSERT INTO $tmp_db_tbl VALUE (CHAR(?))";
      MKDEBUG && _d($dbh, $sql);
      my $ins_char_sth = $dbh->prepare($sql);  # avoid quoting issues
      for my $char_code ( $min_col_ord..$max_col_ord ) {
         $ins_char_sth->execute($char_code);
      }

      $sql = "SELECT `$chunk_col` FROM $tmp_db_tbl "
           . "WHERE `$chunk_col` BETWEEN ? AND ? "
           . "ORDER BY `$chunk_col`";
      MKDEBUG && _d($dbh, $sql);
      my $sel_char_sth = $dbh->prepare($sql);
      $sel_char_sth->execute($min_col, $max_col);

      @chars = map { $_->[0] } @{ $sel_char_sth->fetchall_arrayref() };
      $base  = scalar @chars;

      $sql = "DROP TABLE $tmp_db_tbl";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   }
   MKDEBUG && _d("Base", $base, "chars:", @chars);


   $sql = "SELECT MAX(LENGTH($chunk_col)) FROM $db_tbl ORDER BY `$chunk_col`";
   MKDEBUG && _d($dbh, $sql);
   $row = $dbh->selectrow_arrayref($sql);
   my $max_col_len = $row->[0];
   MKDEBUG && _d("Max column value:", $max_col, $max_col_len);
   my $n_values;
   for my $n_chars ( 1..$max_col_len ) {
      $n_values = $base**$n_chars;
      if ( $n_values >= $args{chunk_size} ) {
         MKDEBUG && _d($n_chars, "chars in base", $base, "expresses",
            $n_values, "values");
         last;
      }
   }

   my $n_chunks = $args{rows_in_range} / $args{chunk_size};
   my $interval = floor($n_values / $n_chunks) || 1;

   my $range_func = sub {
      my ( $self, $dbh, $start, $interval, $max ) = @_;
      my $start_char = $self->base_count(
         count_to => $start,
         base     => $base,
         symbols  => \@chars,
      );
      my $end_char = $self->base_count(
         count_to => min($max, $start + $interval),
         base     => $base,
         symbols  => \@chars,
      );
      return $start_char, $end_char;
   };

   return (
      col         => $q->quote($chunk_col),
      start_point => 0,
      end_point   => $n_values,
      interval    => $interval,
      range_func  => $range_func,
   );
}

sub get_first_chunkable_column {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(tbl_struct) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my ($exact, @cols) = $self->find_chunk_columns(%args);
   my $col = $cols[0]->{column};
   my $idx = $cols[0]->{index};

   my $wanted_col = $args{chunk_column};
   my $wanted_idx = $args{chunk_index};
   MKDEBUG && _d("Preferred chunk col/idx:", $wanted_col, $wanted_idx);

   if ( $wanted_col && $wanted_idx ) {
      foreach my $chunkable_col ( @cols ) {
         if (    $wanted_col eq $chunkable_col->{column}
              && $wanted_idx eq $chunkable_col->{index} ) {
            $col = $wanted_col;
            $idx = $wanted_idx;
            last;
         }
      }
   }
   elsif ( $wanted_col ) {
      foreach my $chunkable_col ( @cols ) {
         if ( $wanted_col eq $chunkable_col->{column} ) {
            $col = $wanted_col;
            $idx = $chunkable_col->{index};
            last;
         }
      }
   }
   elsif ( $wanted_idx ) {
      foreach my $chunkable_col ( @cols ) {
         if ( $wanted_idx eq $chunkable_col->{index} ) {
            $col = $chunkable_col->{column};
            $idx = $wanted_idx;
            last;
         }
      }
   }

   MKDEBUG && _d('First chunkable col/index:', $col, $idx);
   return $col, $idx;
}

sub size_to_rows {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl chunk_size);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db, $tbl, $chunk_size) = @args{@required_args};
   my $q  = $self->{Quoter};
   my $du = $self->{MySQLDump};

   my ($n_rows, $avg_row_length);

   my ( $num, $suffix ) = $chunk_size =~ m/^(\d+)([MGk])?$/;
   if ( $suffix ) { # Convert to bytes.
      $chunk_size = $suffix eq 'k' ? $num * 1_024
                  : $suffix eq 'M' ? $num * 1_024 * 1_024
                  :                  $num * 1_024 * 1_024 * 1_024;
   }
   elsif ( $num ) {
      $n_rows = $num;
   }
   else {
      die "Invalid chunk size $chunk_size; must be an integer "
         . "with optional suffix kMG";
   }

   if ( $suffix || $args{avg_row_length} ) {
      my ($status) = $du->get_table_status($dbh, $q, $db, $tbl);
      $avg_row_length = $status->{avg_row_length};
      if ( !defined $n_rows ) {
         $n_rows = $avg_row_length ? ceil($chunk_size / $avg_row_length) : undef;
      }
   }

   return $n_rows, $avg_row_length;
}

sub get_range_statistics {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl chunk_col tbl_struct);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db, $tbl, $col) = @args{@required_args};
   my $where = $args{where};
   my $q     = $self->{Quoter};

   my $col_type       = $args{tbl_struct}->{type_for}->{$col};
   my $col_is_numeric = $args{tbl_struct}->{is_numeric}->{$col};

   my $db_tbl = $q->quote($db, $tbl);
   $col       = $q->quote($col);

   my ($min, $max);
   eval {
      my $sql = "SELECT MIN($col), MAX($col) FROM $db_tbl"
              . ($args{index_hint} ? " $args{index_hint}" : "")
              . ($where ? " WHERE ($where)" : '');
      MKDEBUG && _d($dbh, $sql);
      ($min, $max) = $dbh->selectrow_array($sql);
      MKDEBUG && _d("Actual end points:", $min, $max);

      ($min, $max) = $self->get_valid_end_points(
         %args,
         dbh      => $dbh,
         db_tbl   => $db_tbl,
         col      => $col,
         col_type => $col_type,
         min      => $min,
         max      => $max,
      );
      MKDEBUG && _d("Valid end points:", $min, $max);
   };
   if ( $EVAL_ERROR ) {
      die "Error getting min and max values for table $db_tbl "
         . "on column $col: $EVAL_ERROR";
   }

   my $sql = "EXPLAIN SELECT * FROM $db_tbl"
           . ($args{index_hint} ? " $args{index_hint}" : "")
           . ($where ? " WHERE $where" : '');
   MKDEBUG && _d($sql);
   my $expl = $dbh->selectrow_hashref($sql);

   return (
      min           => $min,
      max           => $max,
      rows_in_range => $expl->{rows},
   );
}

sub inject_chunks {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(database table chunks chunk_num query) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   MKDEBUG && _d('Injecting chunk', $args{chunk_num});
   my $query   = $args{query};
   my $comment = sprintf("/*%s.%s:%d/%d*/",
      $args{database}, $args{table},
      $args{chunk_num} + 1, scalar @{$args{chunks}});
   $query =~ s!/\*PROGRESS_COMMENT\*/!$comment!;
   my $where = "WHERE (" . $args{chunks}->[$args{chunk_num}] . ')';
   if ( $args{where} && grep { $_ } @{$args{where}} ) {
      $where .= " AND ("
         . join(" AND ", map { "($_)" } grep { $_ } @{$args{where}} )
         . ")";
   }
   my $db_tbl     = $self->{Quoter}->quote(@args{qw(database table)});
   my $index_hint = $args{index_hint} || '';

   MKDEBUG && _d('Parameters:',
      Dumper({WHERE => $where, DB_TBL => $db_tbl, INDEX_HINT => $index_hint}));
   $query =~ s!/\*WHERE\*/! $where!;
   $query =~ s!/\*DB_TBL\*/!$db_tbl!;
   $query =~ s!/\*INDEX_HINT\*/! $index_hint!;
   $query =~ s!/\*CHUNK_NUM\*/! $args{chunk_num} AS chunk_num,!;

   return $query;
}


sub value_to_number {
   my ( $self, %args ) = @_;
   my @required_args = qw(column_type dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $val = $args{value};
   my ($col_type, $dbh) = @args{@required_args};
   MKDEBUG && _d('Converting MySQL', $col_type, $val);

   return unless defined $val;  # value is NULL

   my %mysql_conv_func_for = (
      timestamp => 'UNIX_TIMESTAMP',
      date      => 'TO_DAYS',
      time      => 'TIME_TO_SEC',
      datetime  => 'TO_DAYS',
   );

   my $num;
   if ( $col_type =~ m/(?:int|year|float|double|decimal)$/ ) {
      $num = $val;
   }
   elsif ( $col_type =~ m/^(?:timestamp|date|time)$/ ) {
      my $func = $mysql_conv_func_for{$col_type};
      my $sql = "SELECT $func(?)";
      MKDEBUG && _d($dbh, $sql, $val);
      my $sth = $dbh->prepare($sql);
      $sth->execute($val);
      ($num) = $sth->fetchrow_array();
   }
   elsif ( $col_type eq 'datetime' ) {
      $num = $self->timestampdiff($dbh, $val);
   }
   else {
      die "I don't know how to chunk $col_type\n";
   }
   MKDEBUG && _d('Converts to', $num);
   return $num;
}

sub range_num {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $end = min($max, $start + $interval);


   $start = sprintf('%.17f', $start) if $start =~ /e/;
   $end   = sprintf('%.17f', $end)   if $end   =~ /e/;

   $start =~ s/\.(\d{5}).*$/.$1/;
   $end   =~ s/\.(\d{5}).*$/.$1/;

   if ( $end > $start ) {
      return ( $start, $end );
   }
   else {
      die "Chunk size is too small: $end !> $start\n";
   }
}

sub range_time {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $sql = "SELECT SEC_TO_TIME($start), SEC_TO_TIME(LEAST($max, $start + $interval))";
   MKDEBUG && _d($sql);
   return $dbh->selectrow_array($sql);
}

sub range_date {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $sql = "SELECT FROM_DAYS($start), FROM_DAYS(LEAST($max, $start + $interval))";
   MKDEBUG && _d($sql);
   return $dbh->selectrow_array($sql);
}

sub range_datetime {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $sql = "SELECT DATE_ADD('$self->{EPOCH}', INTERVAL $start SECOND), "
       . "DATE_ADD('$self->{EPOCH}', INTERVAL LEAST($max, $start + $interval) SECOND)";
   MKDEBUG && _d($sql);
   return $dbh->selectrow_array($sql);
}

sub range_timestamp {
   my ( $self, $dbh, $start, $interval, $max ) = @_;
   my $sql = "SELECT FROM_UNIXTIME($start), FROM_UNIXTIME(LEAST($max, $start + $interval))";
   MKDEBUG && _d($sql);
   return $dbh->selectrow_array($sql);
}

sub timestampdiff {
   my ( $self, $dbh, $time ) = @_;
   my $sql = "SELECT (COALESCE(TO_DAYS('$time'), 0) * 86400 + TIME_TO_SEC('$time')) "
      . "- TO_DAYS('$self->{EPOCH} 00:00:00') * 86400";
   MKDEBUG && _d($sql);
   my ( $diff ) = $dbh->selectrow_array($sql);
   $sql = "SELECT DATE_ADD('$self->{EPOCH}', INTERVAL $diff SECOND)";
   MKDEBUG && _d($sql);
   my ( $check ) = $dbh->selectrow_array($sql);
   die <<"   EOF"
   Incorrect datetime math: given $time, calculated $diff but checked to $check.
   This could be due to a version of MySQL that overflows on large interval
   values to DATE_ADD(), or the given datetime is not a valid date.  If not,
   please report this as a bug.
   EOF
      unless $check eq $time;
   return $diff;
}




sub get_valid_end_points {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db_tbl col col_type);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db_tbl, $col, $col_type) = @args{@required_args};
   my ($real_min, $real_max)           = @args{qw(min max)};

   my $err_fmt = "Error finding a valid %s value for table $db_tbl on "
               . "column $col. The real %s value %s is invalid and "
               . "no other valid values were found.  Verify that the table "
               . "has at least one valid value for this column"
               . ($args{where} ? " where $args{where}." : ".");

   my $valid_min = $real_min;
   if ( defined $valid_min ) {
      MKDEBUG && _d("Validating min end point:", $real_min);
      $valid_min = $self->_get_valid_end_point(
         %args,
         val      => $real_min,
         endpoint => 'min',
      );
      die sprintf($err_fmt, 'minimum', 'minimum',
         (defined $real_min ? $real_min : "NULL"))
         unless defined $valid_min;
   }

   my $valid_max = $real_max;
   if ( defined $valid_max ) {
      MKDEBUG && _d("Validating max end point:", $real_min);
      $valid_max = $self->_get_valid_end_point(
         %args,
         val      => $real_max,
         endpoint => 'max',
      );
      die sprintf($err_fmt, 'maximum', 'maximum',
         (defined $real_max ? $real_max : "NULL"))
         unless defined $valid_max;
   }

   return $valid_min, $valid_max;
}

sub _get_valid_end_point {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db_tbl col col_type);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db_tbl, $col, $col_type) = @args{@required_args};
   my $val = $args{val};

   return $val unless defined $val;

   my $validate = $col_type =~ m/time|date/ ? \&_validate_temporal_value
                :                             undef;

   if ( !$validate ) {
      MKDEBUG && _d("No validator for", $col_type, "values");
      return $val;
   }

   return $val if defined $validate->($dbh, $val);

   MKDEBUG && _d("Value is invalid, getting first valid value");
   $val = $self->get_first_valid_value(
      %args,
      val      => $val,
      validate => $validate,
   );

   return $val;
}

sub get_first_valid_value {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db_tbl col validate endpoint);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db_tbl, $col, $validate, $endpoint) = @args{@required_args};
   my $tries = defined $args{tries} ? $args{tries} : 5;
   my $val   = $args{val};

   return unless defined $val;

   my $cmp = $endpoint =~ m/min/i ? '>'
           : $endpoint =~ m/max/i ? '<'
           :                        die "Invalid endpoint arg: $endpoint";
   my $sql = "SELECT $col FROM $db_tbl "
           . ($args{index_hint} ? "$args{index_hint} " : "")
           . "WHERE $col $cmp ? AND $col IS NOT NULL "
           . ($args{where} ? "AND ($args{where}) " : "")
           . "ORDER BY $col LIMIT 1";
   MKDEBUG && _d($dbh, $sql);
   my $sth = $dbh->prepare($sql);

   my $last_val = $val;
   while ( $tries-- ) {
      $sth->execute($last_val);
      my ($next_val) = $sth->fetchrow_array();
      MKDEBUG && _d('Next value:', $next_val, '; tries left:', $tries);
      if ( !defined $next_val ) {
         MKDEBUG && _d('No more rows in table');
         last;
      }
      if ( defined $validate->($dbh, $next_val) ) {
         MKDEBUG && _d('First valid value:', $next_val);
         $sth->finish();
         return $next_val;
      }
      $last_val = $next_val;
   }
   $sth->finish();
   $val = undef;  # no valid value found

   return $val;
}

sub _validate_temporal_value {
   my ( $dbh, $val ) = @_;
   my $sql = "SELECT IF(TIME_FORMAT(?,'%H:%i:%s')=?, TIME_TO_SEC(?), TO_DAYS(?))";
   my $res;
   eval {
      MKDEBUG && _d($dbh, $sql, $val);
      my $sth = $dbh->prepare($sql);
      $sth->execute($val, $val, $val, $val);
      ($res) = $sth->fetchrow_array();
      $sth->finish();
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($EVAL_ERROR);
   }
   return $res;
}

sub get_nonzero_value {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db_tbl col col_type);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db_tbl, $col, $col_type) = @args{@required_args};
   my $tries = defined $args{tries} ? $args{tries} : 5;
   my $val   = $args{val};

   my $is_nonzero = $col_type =~ m/time|date/ ? \&_validate_temporal_value
                  :                             sub { return $_[1]; };

   if ( !$is_nonzero->($dbh, $val) ) {  # quasi-double-negative, sorry
      MKDEBUG && _d('Discarding zero value:', $val);
      my $sql = "SELECT $col FROM $db_tbl "
              . ($args{index_hint} ? "$args{index_hint} " : "")
              . "WHERE $col > ? AND $col IS NOT NULL "
              . ($args{where} ? "AND ($args{where}) " : '')
              . "ORDER BY $col LIMIT 1";
      MKDEBUG && _d($sql);
      my $sth = $dbh->prepare($sql);

      my $last_val = $val;
      while ( $tries-- ) {
         $sth->execute($last_val);
         my ($next_val) = $sth->fetchrow_array();
         if ( $is_nonzero->($dbh, $next_val) ) {
            MKDEBUG && _d('First non-zero value:', $next_val);
            $sth->finish();
            return $next_val;
         }
         $last_val = $next_val;
      }
      $sth->finish();
      $val = undef;  # no non-zero value found
   }

   return $val;
}

sub base_count {
   my ( $self, %args ) = @_;
   my @required_args = qw(count_to base symbols);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($n, $base, $symbols) = @args{@required_args};

   return $symbols->[0] if $n == 0;

   my $highest_power = floor(log($n)/log($base));
   if ( $highest_power == 0 ){
      return $symbols->[$n];
   }

   my @base_powers;
   for my $power ( 0..$highest_power ) {
      push @base_powers, ($base**$power) || 1;  
   }

   my @base_multiples;
   foreach my $base_power ( reverse @base_powers ) {
      my $multiples = floor($n / $base_power);
      push @base_multiples, $multiples;
      $n -= $multiples * $base_power;
   }

   return join('', map { $symbols->[$_] } @base_multiples);
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End TableChunker package
# ###########################################################################

# ###########################################################################
# TableNibbler package 5266
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TableNibbler.pm
#   trunk/common/t/TableNibbler.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package TableNibbler;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(TableParser Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

sub generate_asc_stmt {
   my ( $self, %args ) = @_;
   my @required_args = qw(tbl_struct index);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($tbl_struct, $index) = @args{@required_args};
   my @cols = $args{cols}  ? @{$args{cols}} : @{$tbl_struct->{cols}};
   my $q    = $self->{Quoter};

   die "Index '$index' does not exist in table"
      unless exists $tbl_struct->{keys}->{$index};

   my @asc_cols = @{$tbl_struct->{keys}->{$index}->{cols}};
   my @asc_slice;

   @asc_cols = @{$tbl_struct->{keys}->{$index}->{cols}};
   MKDEBUG && _d('Will ascend index', $index);
   MKDEBUG && _d('Will ascend columns', join(', ', @asc_cols));
   if ( $args{asc_first} ) {
      @asc_cols = $asc_cols[0];
      MKDEBUG && _d('Ascending only first column');
   }

   my %col_posn = do { my $i = 0; map { $_ => $i++ } @cols };
   foreach my $col ( @asc_cols ) {
      if ( !exists $col_posn{$col} ) {
         push @cols, $col;
         $col_posn{$col} = $#cols;
      }
      push @asc_slice, $col_posn{$col};
   }
   MKDEBUG && _d('Will ascend, in ordinal position:', join(', ', @asc_slice));

   my $asc_stmt = {
      cols  => \@cols,
      index => $index,
      where => '',
      slice => [],
      scols => [],
   };

   if ( @asc_slice ) {
      my $cmp_where;
      foreach my $cmp ( qw(< <= >= >) ) {
         $cmp_where = $self->generate_cmp_where(
            type        => $cmp,
            slice       => \@asc_slice,
            cols        => \@cols,
            quoter      => $q,
            is_nullable => $tbl_struct->{is_nullable},
         );
         $asc_stmt->{boundaries}->{$cmp} = $cmp_where->{where};
      }
      my $cmp = $args{asc_only} ? '>' : '>=';
      $asc_stmt->{where} = $asc_stmt->{boundaries}->{$cmp};
      $asc_stmt->{slice} = $cmp_where->{slice};
      $asc_stmt->{scols} = $cmp_where->{scols};
   }

   return $asc_stmt;
}

sub generate_cmp_where {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(type slice cols is_nullable) ) {
      die "I need a $arg arg" unless defined $args{$arg};
   }
   my @slice       = @{$args{slice}};
   my @cols        = @{$args{cols}};
   my $is_nullable = $args{is_nullable};
   my $type        = $args{type};
   my $q           = $self->{Quoter};

   (my $cmp = $type) =~ s/=//;

   my @r_slice;    # Resulting slice columns, by ordinal
   my @r_scols;    # Ditto, by name

   my @clauses;
   foreach my $i ( 0 .. $#slice ) {
      my @clause;

      foreach my $j ( 0 .. $i - 1 ) {
         my $ord = $slice[$j];
         my $col = $cols[$ord];
         my $quo = $q->quote($col);
         if ( $is_nullable->{$col} ) {
            push @clause, "((? IS NULL AND $quo IS NULL) OR ($quo = ?))";
            push @r_slice, $ord, $ord;
            push @r_scols, $col, $col;
         }
         else {
            push @clause, "$quo = ?";
            push @r_slice, $ord;
            push @r_scols, $col;
         }
      }

      my $ord = $slice[$i];
      my $col = $cols[$ord];
      my $quo = $q->quote($col);
      my $end = $i == $#slice; # Last clause of the whole group.
      if ( $is_nullable->{$col} ) {
         if ( $type =~ m/=/ && $end ) {
            push @clause, "(? IS NULL OR $quo $type ?)";
         }
         elsif ( $type =~ m/>/ ) {
            push @clause, "((? IS NULL AND $quo IS NOT NULL) OR ($quo $cmp ?))";
         }
         else { # If $type =~ m/</ ) {
            push @clause, "((? IS NOT NULL AND $quo IS NULL) OR ($quo $cmp ?))";
         }
         push @r_slice, $ord, $ord;
         push @r_scols, $col, $col;
      }
      else {
         push @r_slice, $ord;
         push @r_scols, $col;
         push @clause, ($type =~ m/=/ && $end ? "$quo $type ?" : "$quo $cmp ?");
      }

      push @clauses, '(' . join(' AND ', @clause) . ')';
   }
   my $result = '(' . join(' OR ', @clauses) . ')';
   my $where = {
      slice => \@r_slice,
      scols => \@r_scols,
      where => $result,
   };
   return $where;
}

sub generate_del_stmt {
   my ( $self, %args ) = @_;

   my $tbl  = $args{tbl_struct};
   my @cols = $args{cols} ? @{$args{cols}} : ();
   my $tp   = $self->{TableParser};
   my $q    = $self->{Quoter};

   my @del_cols;
   my @del_slice;

   my $index = $tp->find_best_index($tbl, $args{index});
   die "Cannot find an ascendable index in table" unless $index;

   if ( $index ) {
      @del_cols = @{$tbl->{keys}->{$index}->{cols}};
   }
   else {
      @del_cols = @{$tbl->{cols}};
   }
   MKDEBUG && _d('Columns needed for DELETE:', join(', ', @del_cols));

   my %col_posn = do { my $i = 0; map { $_ => $i++ } @cols };
   foreach my $col ( @del_cols ) {
      if ( !exists $col_posn{$col} ) {
         push @cols, $col;
         $col_posn{$col} = $#cols;
      }
      push @del_slice, $col_posn{$col};
   }
   MKDEBUG && _d('Ordinals needed for DELETE:', join(', ', @del_slice));

   my $del_stmt = {
      cols  => \@cols,
      index => $index,
      where => '',
      slice => [],
      scols => [],
   };

   my @clauses;
   foreach my $i ( 0 .. $#del_slice ) {
      my $ord = $del_slice[$i];
      my $col = $cols[$ord];
      my $quo = $q->quote($col);
      if ( $tbl->{is_nullable}->{$col} ) {
         push @clauses, "((? IS NULL AND $quo IS NULL) OR ($quo = ?))";
         push @{$del_stmt->{slice}}, $ord, $ord;
         push @{$del_stmt->{scols}}, $col, $col;
      }
      else {
         push @clauses, "$quo = ?";
         push @{$del_stmt->{slice}}, $ord;
         push @{$del_stmt->{scols}}, $col;
      }
   }

   $del_stmt->{where} = '(' . join(' AND ', @clauses) . ')';

   return $del_stmt;
}

sub generate_ins_stmt {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ins_tbl sel_cols) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $ins_tbl  = $args{ins_tbl};
   my @sel_cols = @{$args{sel_cols}};

   die "You didn't specify any SELECT columns" unless @sel_cols;

   my @ins_cols;
   my @ins_slice;
   for my $i ( 0..$#sel_cols ) {
      next unless $ins_tbl->{is_col}->{$sel_cols[$i]};
      push @ins_cols, $sel_cols[$i];
      push @ins_slice, $i;
   }

   return {
      cols  => \@ins_cols,
      slice => \@ins_slice,
   };
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End TableNibbler package
# ###########################################################################

# ###########################################################################
# TableChecksum package 7080
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TableChecksum.pm
#   trunk/common/t/TableChecksum.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package TableChecksum;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use List::Util qw(max);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

our %ALGOS = (
   CHECKSUM => { pref => 0, hash => 0 },
   BIT_XOR  => { pref => 2, hash => 1 },
   ACCUM    => { pref => 3, hash => 1 },
);

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(Quoter VersionParser) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

sub crc32 {
   my ( $self, $string ) = @_;
   my $poly = 0xEDB88320;
   my $crc  = 0xFFFFFFFF;
   foreach my $char ( split(//, $string) ) {
      my $comp = ($crc ^ ord($char)) & 0xFF;
      for ( 1 .. 8 ) {
         $comp = $comp & 1 ? $poly ^ ($comp >> 1) : $comp >> 1;
      }
      $crc = (($crc >> 8) & 0x00FFFFFF) ^ $comp;
   }
   return $crc ^ 0xFFFFFFFF;
}

sub get_crc_wid {
   my ( $self, $dbh, $func ) = @_;
   my $crc_wid = 16;
   if ( uc $func ne 'FNV_64' && uc $func ne 'FNV1A_64' ) {
      eval {
         my ($val) = $dbh->selectrow_array("SELECT $func('a')");
         $crc_wid = max(16, length($val));
      };
   }
   return $crc_wid;
}

sub get_crc_type {
   my ( $self, $dbh, $func ) = @_;
   my $type   = '';
   my $length = 0;
   my $sql    = "SELECT $func('a')";
   my $sth    = $dbh->prepare($sql);
   eval {
      $sth->execute();
      $type   = $sth->{mysql_type_name}->[0];
      $length = $sth->{mysql_length}->[0];
      MKDEBUG && _d($sql, $type, $length);
      if ( $type eq 'bigint' && $length < 20 ) {
         $type = 'int';
      }
   };
   $sth->finish;
   MKDEBUG && _d('crc_type:', $type, 'length:', $length);
   return ($type, $length);
}

sub best_algorithm {
   my ( $self, %args ) = @_;
   my ( $alg, $dbh ) = @args{ qw(algorithm dbh) };
   my $vp = $self->{VersionParser};
   my @choices = sort { $ALGOS{$a}->{pref} <=> $ALGOS{$b}->{pref} } keys %ALGOS;
   die "Invalid checksum algorithm $alg"
      if $alg && !$ALGOS{$alg};

   if (
      $args{where} || $args{chunk}        # CHECKSUM does whole table
      || $args{replicate}                 # CHECKSUM can't do INSERT.. SELECT
      || !$vp->version_ge($dbh, '4.1.1')) # CHECKSUM doesn't exist
   {
      MKDEBUG && _d('Cannot use CHECKSUM algorithm');
      @choices = grep { $_ ne 'CHECKSUM' } @choices;
   }

   if ( !$vp->version_ge($dbh, '4.1.1') ) {
      MKDEBUG && _d('Cannot use BIT_XOR algorithm because MySQL < 4.1.1');
      @choices = grep { $_ ne 'BIT_XOR' } @choices;
   }

   if ( $alg && grep { $_ eq $alg } @choices ) {
      MKDEBUG && _d('User requested', $alg, 'algorithm');
      return $alg;
   }

   if ( $args{count} && grep { $_ ne 'CHECKSUM' } @choices ) {
      MKDEBUG && _d('Not using CHECKSUM algorithm because COUNT desired');
      @choices = grep { $_ ne 'CHECKSUM' } @choices;
   }

   MKDEBUG && _d('Algorithms, in order:', @choices);
   return $choices[0];
}

sub is_hash_algorithm {
   my ( $self, $algorithm ) = @_;
   return $ALGOS{$algorithm} && $ALGOS{$algorithm}->{hash};
}

sub choose_hash_func {
   my ( $self, %args ) = @_;
   my @funcs = qw(CRC32 FNV1A_64 FNV_64 MD5 SHA1);
   if ( $args{function} ) {
      unshift @funcs, $args{function};
   }
   my ($result, $error);
   do {
      my $func;
      eval {
         $func = shift(@funcs);
         my $sql = "SELECT $func('test-string')";
         MKDEBUG && _d($sql);
         $args{dbh}->do($sql);
         $result = $func;
      };
      if ( $EVAL_ERROR && $EVAL_ERROR =~ m/failed: (.*?) at \S+ line/ ) {
         $error .= qq{$func cannot be used because "$1"\n};
         MKDEBUG && _d($func, 'cannot be used because', $1);
      }
   } while ( @funcs && !$result );

   die $error unless $result;
   MKDEBUG && _d('Chosen hash func:', $result);
   return $result;
}

sub optimize_xor {
   my ( $self, %args ) = @_;
   my ($dbh, $func) = @args{qw(dbh function)};

   die "$func never needs the BIT_XOR optimization"
      if $func =~ m/^(?:FNV1A_64|FNV_64|CRC32)$/i;

   my $opt_slice = 0;
   my $unsliced  = uc $dbh->selectall_arrayref("SELECT $func('a')")->[0]->[0];
   my $sliced    = '';
   my $start     = 1;
   my $crc_wid   = length($unsliced) < 16 ? 16 : length($unsliced);

   do { # Try different positions till sliced result equals non-sliced.
      MKDEBUG && _d('Trying slice', $opt_slice);
      $dbh->do('SET @crc := "", @cnt := 0');
      my $slices = $self->make_xor_slices(
         query     => "\@crc := $func('a')",
         crc_wid   => $crc_wid,
         opt_slice => $opt_slice,
      );

      my $sql = "SELECT CONCAT($slices) AS TEST FROM (SELECT NULL) AS x";
      $sliced = ($dbh->selectrow_array($sql))[0];
      if ( $sliced ne $unsliced ) {
         MKDEBUG && _d('Slice', $opt_slice, 'does not work');
         $start += 16;
         ++$opt_slice;
      }
   } while ( $start < $crc_wid && $sliced ne $unsliced );

   if ( $sliced eq $unsliced ) {
      MKDEBUG && _d('Slice', $opt_slice, 'works');
      return $opt_slice;
   }
   else {
      MKDEBUG && _d('No slice works');
      return undef;
   }
}

sub make_xor_slices {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(query crc_wid) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ( $query, $crc_wid, $opt_slice ) = @args{qw(query crc_wid opt_slice)};

   my @slices;
   for ( my $start = 1; $start <= $crc_wid; $start += 16 ) {
      my $len = $crc_wid - $start + 1;
      if ( $len > 16 ) {
         $len = 16;
      }
      push @slices,
         "LPAD(CONV(BIT_XOR("
         . "CAST(CONV(SUBSTRING(\@crc, $start, $len), 16, 10) AS UNSIGNED))"
         . ", 10, 16), $len, '0')";
   }

   if ( defined $opt_slice && $opt_slice < @slices ) {
      $slices[$opt_slice] =~ s/\@crc/\@crc := $query/;
   }
   else {
      map { s/\@crc/$query/ } @slices;
   }

   return join(', ', @slices);
}

sub make_row_checksum {
   my ( $self, %args ) = @_;
   my ( $tbl_struct, $func ) = @args{ qw(tbl_struct function) };
   my $q = $self->{Quoter};

   my $sep = $args{sep} || '#';
   $sep =~ s/'//g;
   $sep ||= '#';

   my $ignorecols = $args{ignorecols} || {};

   my %cols = map { lc($_) => 1 }
              grep { !exists $ignorecols->{$_} }
              ($args{cols} ? @{$args{cols}} : @{$tbl_struct->{cols}});
   my %seen;
   my @cols =
      map {
         my $type = $tbl_struct->{type_for}->{$_};
         my $result = $q->quote($_);
         if ( $type eq 'timestamp' ) {
            $result .= ' + 0';
         }
         elsif ( $args{float_precision} && $type =~ m/float|double/ ) {
            $result = "ROUND($result, $args{float_precision})";
         }
         elsif ( $args{trim} && $type =~ m/varchar/ ) {
            $result = "TRIM($result)";
         }
         $result;
      }
      grep {
         $cols{$_} && !$seen{$_}++
      }
      @{$tbl_struct->{cols}};

   my $query;
   if ( !$args{no_cols} ) {
      $query = join(', ',
                  map { 
                     my $col = $_;
                     if ( $col =~ m/\+ 0/ ) {
                        my ($real_col) = /^(\S+)/;
                        $col .= " AS $real_col";
                     }
                     elsif ( $col =~ m/TRIM/ ) {
                        my ($real_col) = m/TRIM\(([^\)]+)\)/;
                        $col .= " AS $real_col";
                     }
                     $col;
                  } @cols)
             . ', ';
   }

   if ( uc $func ne 'FNV_64' && uc $func ne 'FNV1A_64' ) {
      my @nulls = grep { $cols{$_} } @{$tbl_struct->{null_cols}};
      if ( @nulls ) {
         my $bitmap = "CONCAT("
            . join(', ', map { 'ISNULL(' . $q->quote($_) . ')' } @nulls)
            . ")";
         push @cols, $bitmap;
      }

      $query .= @cols > 1
              ? "$func(CONCAT_WS('$sep', " . join(', ', @cols) . '))'
              : "$func($cols[0])";
   }
   else {
      my $fnv_func = uc $func;
      $query .= "$fnv_func(" . join(', ', @cols) . ')';
   }

   return $query;
}

sub make_checksum_query {
   my ( $self, %args ) = @_;
   my @required_args = qw(db tbl tbl_struct algorithm crc_wid crc_type);
   foreach my $arg( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ( $db, $tbl, $tbl_struct, $algorithm,
        $crc_wid, $crc_type) = @args{@required_args};
   my $func = $args{function};
   my $q = $self->{Quoter};
   my $result;

   die "Invalid or missing checksum algorithm"
      unless $algorithm && $ALGOS{$algorithm};

   if ( $algorithm eq 'CHECKSUM' ) {
      return "CHECKSUM TABLE " . $q->quote($db, $tbl);
   }

   my $expr = $self->make_row_checksum(%args, no_cols=>1);

   if ( $algorithm eq 'BIT_XOR' ) {
      if ( $crc_type =~ m/int$/ ) {
         $result = "COALESCE(LOWER(CONV(BIT_XOR(CAST($expr AS UNSIGNED)), 10, 16)), 0) AS crc ";
      }
      else {
         my $slices = $self->make_xor_slices( query => $expr, %args );
         $result = "COALESCE(LOWER(CONCAT($slices)), 0) AS crc ";
      }
   }
   else {
      if ( $crc_type =~ m/int$/ ) {
         $result = "COALESCE(RIGHT(MAX("
            . "\@crc := CONCAT(LPAD(\@cnt := \@cnt + 1, 16, '0'), "
            . "CONV(CAST($func(CONCAT(\@crc, $expr)) AS UNSIGNED), 10, 16))"
            . "), $crc_wid), 0) AS crc ";
      }
      else {
         $result = "COALESCE(RIGHT(MAX("
            . "\@crc := CONCAT(LPAD(\@cnt := \@cnt + 1, 16, '0'), "
            . "$func(CONCAT(\@crc, $expr)))"
            . "), $crc_wid), 0) AS crc ";
      }
   }
   if ( $args{replicate} ) {
      $result = "REPLACE /*PROGRESS_COMMENT*/ INTO $args{replicate} "
         . "(db, tbl, chunk, boundaries, this_cnt, this_crc) "
         . "SELECT ?, ?, /*CHUNK_NUM*/ ?, COUNT(*) AS cnt, $result";
   }
   else {
      $result = "SELECT "
         . ($args{buffer} ? 'SQL_BUFFER_RESULT ' : '')
         . "/*PROGRESS_COMMENT*//*CHUNK_NUM*/ COUNT(*) AS cnt, $result";
   }
   return $result . "FROM /*DB_TBL*//*INDEX_HINT*//*WHERE*/";
}

sub find_replication_differences {
   my ( $self, $dbh, $table ) = @_;

   (my $sql = <<"   EOF") =~ s/\s+/ /gm;
      SELECT db, tbl, chunk, boundaries,
         COALESCE(this_cnt-master_cnt, 0) AS cnt_diff,
         COALESCE(
            this_crc <> master_crc OR ISNULL(master_crc) <> ISNULL(this_crc),
            0
         ) AS crc_diff,
         this_cnt, master_cnt, this_crc, master_crc
      FROM $table
      WHERE master_cnt <> this_cnt OR master_crc <> this_crc
      OR ISNULL(master_crc) <> ISNULL(this_crc)
   EOF

   MKDEBUG && _d($sql);
   my $diffs = $dbh->selectall_arrayref($sql, { Slice => {} });
   return @$diffs;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End TableChecksum package
# ###########################################################################

# ###########################################################################
# TableSyncer package 6810
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TableSyncer.pm
#   trunk/common/t/TableSyncer.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package TableSyncer;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(MasterSlave Quoter VersionParser TableChecksum Retry);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

sub get_best_plugin {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(plugins tbl_struct) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   MKDEBUG && _d('Getting best plugin');
   foreach my $plugin ( @{$args{plugins}} ) {
      MKDEBUG && _d('Trying plugin', $plugin->name);
      my ($can_sync, %plugin_args) = $plugin->can_sync(%args);
      if ( $can_sync ) {
        MKDEBUG && _d('Can sync with', $plugin->name, Dumper(\%plugin_args));
        return $plugin, %plugin_args;
      }
   }
   MKDEBUG && _d('No plugin can sync the table');
   return;
}

sub sync_table {
   my ( $self, %args ) = @_;
   my @required_args = qw(plugins src dst tbl_struct cols chunk_size
                          RowDiff ChangeHandler);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   MKDEBUG && _d('Syncing table with args:',
      map { "$_: " . Dumper($args{$_}) }
      qw(plugins src dst tbl_struct cols chunk_size));

   my ($plugins, $src, $dst, $tbl_struct, $cols, $chunk_size, $rd, $ch)
      = @args{@required_args};
   my $dp = $self->{DSNParser};
   $args{trace} = 1 unless defined $args{trace};

   if ( $args{bidirectional} && $args{ChangeHandler}->{queue} ) {
      die "Queueing does not work with bidirectional syncing";
   }

   $args{index_hint}    = 1 unless defined $args{index_hint};
   $args{lock}        ||= 0;
   $args{wait}        ||= 0;
   $args{transaction} ||= 0;
   $args{timeout_ok}  ||= 0;

   my $q  = $self->{Quoter};
   my $vp = $self->{VersionParser};

   my ($plugin, %plugin_args) = $self->get_best_plugin(%args);
   die "No plugin can sync $src->{db}.$src->{tbl}" unless $plugin;

   my $crc_col = '__crc';
   while ( $tbl_struct->{is_col}->{$crc_col} ) {
      $crc_col = "_$crc_col"; # Prepend more _ until not a column.
   }
   MKDEBUG && _d('CRC column:', $crc_col);

   my $index_hint;
   my $hint = ($vp->version_ge($src->{dbh}, '4.0.9')
               && $vp->version_ge($dst->{dbh}, '4.0.9') ? 'FORCE' : 'USE')
            . ' INDEX';
   if ( $args{chunk_index} ) {
      MKDEBUG && _d('Using given chunk index for index hint');
      $index_hint = "$hint (" . $q->quote($args{chunk_index}) . ")";
   }
   elsif ( $plugin_args{chunk_index} && $args{index_hint} ) {
      MKDEBUG && _d('Using chunk index chosen by plugin for index hint');
      $index_hint = "$hint (" . $q->quote($plugin_args{chunk_index}) . ")";
   }
   MKDEBUG && _d('Index hint:', $index_hint);

   eval {
      $plugin->prepare_to_sync(
         %args,
         %plugin_args,
         dbh        => $src->{dbh},
         db         => $src->{db},
         tbl        => $src->{tbl},
         crc_col    => $crc_col,
         index_hint => $index_hint,
      );
   };
   if ( $EVAL_ERROR ) {
      die 'Failed to prepare TableSync', $plugin->name, ' plugin: ',
         $EVAL_ERROR;
   }

   if ( $plugin->uses_checksum() ) {
      eval {
         my ($chunk_sql, $row_sql) = $self->make_checksum_queries(%args);
         $plugin->set_checksum_queries($chunk_sql, $row_sql);
      };
      if ( $EVAL_ERROR ) {
         die "Failed to make checksum queries: $EVAL_ERROR";
      }
   } 

   if ( $args{dry_run} ) {
      return $ch->get_changes(), ALGORITHM => $plugin->name;
   }


   eval {
      $src->{dbh}->do("USE `$src->{db}`");
      $dst->{dbh}->do("USE `$dst->{db}`");
   };
   if ( $EVAL_ERROR ) {
      die "Failed to USE database on source or destination: $EVAL_ERROR";
   }

   MKDEBUG && _d('left dbh', $src->{dbh});
   MKDEBUG && _d('right dbh', $dst->{dbh});

   chomp(my $hostname = `hostname`);
   my $trace_msg
      = $args{trace} ? "src_db:$src->{db} src_tbl:$src->{tbl} "
         . ($dp && $src->{dsn} ? "src_dsn:".$dp->as_string($src->{dsn}) : "")
         . " dst_db:$dst->{db} dst_tbl:$dst->{tbl} "
         . ($dp && $dst->{dsn} ? "dst_dsn:".$dp->as_string($dst->{dsn}) : "")
         . " " . join(" ", map { "$_:" . ($args{$_} || 0) }
                     qw(lock transaction changing_src replicate bidirectional))
         . " pid:$PID "
         . ($ENV{USER} ? "user:$ENV{USER} " : "")
         . ($hostname  ? "host:$hostname"   : "")
      :                "";
   MKDEBUG && _d("Binlog trace message:", $trace_msg);

   $self->lock_and_wait(%args, lock_level => 2);  # per-table lock

   my $callback = $args{callback};
   my $cycle    = 0;
   while ( !$plugin->done() ) {

      MKDEBUG && _d('Beginning sync cycle', $cycle);
      my $src_sql = $plugin->get_sql(
         database => $src->{db},
         table    => $src->{tbl},
         where    => $args{where},
      );
      my $dst_sql = $plugin->get_sql(
         database => $dst->{db},
         table    => $dst->{tbl},
         where    => $args{where},
      );

      if ( $args{transaction} ) {
         if ( $args{bidirectional} ) {
            $src_sql .= ' FOR UPDATE';
            $dst_sql .= ' FOR UPDATE';
         }
         elsif ( $args{changing_src} ) {
            $src_sql .= ' FOR UPDATE';
            $dst_sql .= ' LOCK IN SHARE MODE';
         }
         else {
            $src_sql .= ' LOCK IN SHARE MODE';
            $dst_sql .= ' FOR UPDATE';
         }
      }
      MKDEBUG && _d('src:', $src_sql);
      MKDEBUG && _d('dst:', $dst_sql);

      $callback->($src_sql, $dst_sql) if $callback;

      $plugin->prepare_sync_cycle($src);
      $plugin->prepare_sync_cycle($dst);

      my $src_sth = $src->{dbh}->prepare($src_sql);
      my $dst_sth = $dst->{dbh}->prepare($dst_sql);
      if ( $args{buffer_to_client} ) {
         $src_sth->{mysql_use_result} = 1;
         $dst_sth->{mysql_use_result} = 1;
      }

      my $executed_src = 0;
      if ( !$cycle || !$plugin->pending_changes() ) {
         $executed_src
            = $self->lock_and_wait(%args, src_sth => $src_sth, lock_level => 1);
      }

      $src_sth->execute() unless $executed_src;
      $dst_sth->execute();

      $rd->compare_sets(
         left_sth   => $src_sth,
         right_sth  => $dst_sth,
         left_dbh   => $src->{dbh},
         right_dbh  => $dst->{dbh},
         syncer     => $plugin,
         tbl_struct => $tbl_struct,
      );
      $ch->process_rows(1, $trace_msg);

      MKDEBUG && _d('Finished sync cycle', $cycle);
      $cycle++;
   }

   $ch->process_rows(0, $trace_msg);

   $self->unlock(%args, lock_level => 2);

   return $ch->get_changes(), ALGORITHM => $plugin->name;
}

sub make_checksum_queries {
   my ( $self, %args ) = @_;
   my @required_args = qw(src dst tbl_struct);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($src, $dst, $tbl_struct) = @args{@required_args};
   my $checksum = $self->{TableChecksum};

   my $src_algo = $checksum->best_algorithm(
      algorithm => 'BIT_XOR',
      dbh       => $src->{dbh},
      where     => 1,
      chunk     => 1,
      count     => 1,
   );
   my $dst_algo = $checksum->best_algorithm(
      algorithm => 'BIT_XOR',
      dbh       => $dst->{dbh},
      where     => 1,
      chunk     => 1,
      count     => 1,
   );
   if ( $src_algo ne $dst_algo ) {
      die "Source and destination checksum algorithms are different: ",
         "$src_algo on source, $dst_algo on destination"
   }
   MKDEBUG && _d('Chosen algo:', $src_algo);

   my $src_func = $checksum->choose_hash_func(dbh => $src->{dbh}, %args);
   my $dst_func = $checksum->choose_hash_func(dbh => $dst->{dbh}, %args);
   if ( $src_func ne $dst_func ) {
      die "Source and destination hash functions are different: ",
      "$src_func on source, $dst_func on destination";
   }
   MKDEBUG && _d('Chosen hash func:', $src_func);


   my $crc_wid    = $checksum->get_crc_wid($src->{dbh}, $src_func);
   my ($crc_type) = $checksum->get_crc_type($src->{dbh}, $src_func);
   my $opt_slice;
   if ( $src_algo eq 'BIT_XOR' && $crc_type !~ m/int$/ ) {
      $opt_slice = $checksum->optimize_xor(
         dbh      => $src->{dbh},
         function => $src_func
      );
   }

   my $chunk_sql = $checksum->make_checksum_query(
      %args,
      db        => $src->{db},
      tbl       => $src->{tbl},
      algorithm => $src_algo,
      function  => $src_func,
      crc_wid   => $crc_wid,
      crc_type  => $crc_type,
      opt_slice => $opt_slice,
      replicate => undef, # replicate means something different to this sub
   );                     # than what we use it for; do not pass it!
   MKDEBUG && _d('Chunk sql:', $chunk_sql);
   my $row_sql = $checksum->make_row_checksum(
      %args,
      function => $src_func,
   );
   MKDEBUG && _d('Row sql:', $row_sql);
   return $chunk_sql, $row_sql;
}

sub lock_table {
   my ( $self, $dbh, $where, $db_tbl, $mode ) = @_;
   my $query = "LOCK TABLES $db_tbl $mode";
   MKDEBUG && _d($query);
   $dbh->do($query);
   MKDEBUG && _d('Acquired table lock on', $where, 'in', $mode, 'mode');
}

sub unlock {
   my ( $self, %args ) = @_;

   foreach my $arg ( qw(src dst lock transaction lock_level) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $src = $args{src};
   my $dst = $args{dst};

   return unless $args{lock} && $args{lock} <= $args{lock_level};

   foreach my $dbh ( $src->{dbh}, $dst->{dbh} ) {
      if ( $args{transaction} ) {
         MKDEBUG && _d('Committing', $dbh);
         $dbh->commit();
      }
      else {
         my $sql = 'UNLOCK TABLES';
         MKDEBUG && _d($dbh, $sql);
         $dbh->do($sql);
      }
   }

   return;
}

sub lock_and_wait {
   my ( $self, %args ) = @_;
   my $result = 0;

   foreach my $arg ( qw(src dst lock lock_level) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $src = $args{src};
   my $dst = $args{dst};

   return unless $args{lock} && $args{lock} == $args{lock_level};
   MKDEBUG && _d('lock and wait, lock level', $args{lock});

   foreach my $dbh ( $src->{dbh}, $dst->{dbh} ) {
      if ( $args{transaction} ) {
         MKDEBUG && _d('Committing', $dbh);
         $dbh->commit();
      }
      else {
         my $sql = 'UNLOCK TABLES';
         MKDEBUG && _d($dbh, $sql);
         $dbh->do($sql);
      }
   }

   if ( $args{lock} == 3 ) {
      my $sql = 'FLUSH TABLES WITH READ LOCK';
      MKDEBUG && _d($src->{dbh}, $sql);
      $src->{dbh}->do($sql);
   }
   else {
      if ( $args{transaction} ) {
         if ( $args{src_sth} ) {
            MKDEBUG && _d('Executing statement on source to lock rows');

            my $sql = "START TRANSACTION /*!40108 WITH CONSISTENT SNAPSHOT */";
            MKDEBUG && _d($src->{dbh}, $sql);
            $src->{dbh}->do($sql);

            $args{src_sth}->execute();
            $result = 1;
         }
      }
      else {
         $self->lock_table($src->{dbh}, 'source',
            $self->{Quoter}->quote($src->{db}, $src->{tbl}),
            $args{changing_src} ? 'WRITE' : 'READ');
      }
   }

   eval {
      if ( my $timeout = $args{wait} ) {
         my $wait  = $args{wait_retry_args}->{wait}  || 10;
         my $tries = $args{wait_retry_args}->{tries} || 3;
         $self->{Retry}->retry(
            wait  => sub { sleep $wait; },
            tries => $tries,
            try   => sub {
               my ( %args ) = @_;

               if ( $args{tryno} > 1 ) {
                  warn "Retrying MASTER_POS_WAIT() for --wait $timeout...";
               }

               my $wait = $self->{MasterSlave}->wait_for_master(
                  master_dbh => $src->{misc_dbh},
                  slave_dbh  => $dst->{dbh},
                  timeout    => $timeout,
               );
               if ( !defined $wait->{result} ) {
                  my $msg;
                  if ( $wait->{waited}  ) {
                     $msg = "The slave was stopped while waiting with "
                          . "MASTER_POS_WAIT().";
                  }
                  else {
                     $msg = "MASTER_POS_WAIT() returned NULL.  Verify that "
                          . "the slave is running.";
                  }
                  if ( $tries - $args{tryno} ) {
                     $msg .= "  Sleeping $wait seconds then retrying "
                           . ($tries - $args{tryno}) . " more times.";
                  }
                  warn $msg;
                  return;
               }
               elsif ( $wait->{result} == -1 ) {
                  die "Slave did not catch up to its master after waiting "
                     . "$timeout seconds with MASTER_POS_WAIT.  Try inceasing "
                     . "the --wait time, or disable this feature by specifying "
                     . "--wait 0.";
               }
               else {
                  return $result;  # slave caught up
               }
            },
            on_failure => sub {
               die "Slave did not catch up to its master after $tries attempts "
                  . "of waiting $timeout seconds with MASTER_POS_WAIT.  "
                  . "Check that the slave is running, increase the --wait "
                  . "time, or disable this feature by specifying --wait 0.";
            },
         );  # retry MasterSlave::wait_for_master()
      }

      if ( $args{changing_src} ) {
         MKDEBUG && _d('Not locking destination because changing source ',
            '(syncing via replication or sync-to-master)');
      }
      else {
         if ( $args{lock} == 3 ) {
            my $sql = 'FLUSH TABLES WITH READ LOCK';
            MKDEBUG && _d($dst->{dbh}, ',', $sql);
            $dst->{dbh}->do($sql);
         }
         elsif ( !$args{transaction} ) {
            $self->lock_table($dst->{dbh}, 'dest',
               $self->{Quoter}->quote($dst->{db}, $dst->{tbl}),
               $args{execute} ? 'WRITE' : 'READ');
         }
      }
   };
   if ( $EVAL_ERROR ) {
      if ( $args{src_sth}->{Active} ) {
         $args{src_sth}->finish();
      }
      foreach my $dbh ( $src->{dbh}, $dst->{dbh}, $src->{misc_dbh} ) {
         next unless $dbh;
         MKDEBUG && _d('Caught error, unlocking/committing on', $dbh);
         $dbh->do('UNLOCK TABLES');
         $dbh->commit() unless $dbh->{AutoCommit};
      }
      die $EVAL_ERROR;
   }

   return $result;
}

sub have_all_privs {
   my ( $self, $dbh, $db, $tbl ) = @_;
   my $db_tbl = $self->{Quoter}->quote($db, $tbl);
   my $sql    = "SHOW FULL COLUMNS FROM $db_tbl";
   MKDEBUG && _d('Permissions check:', $sql);
   my $cols       = $dbh->selectall_arrayref($sql, {Slice => {}});
   my ($hdr_name) = grep { m/privileges/i } keys %{$cols->[0]};
   my $privs      = $cols->[0]->{$hdr_name};
   $sql = "DELETE FROM $db_tbl LIMIT 0"; # FULL COLUMNS doesn't show all privs
   MKDEBUG && _d('Permissions check:', $sql);
   eval { $dbh->do($sql); };
   my $can_delete = $EVAL_ERROR ? 0 : 1;

   MKDEBUG && _d('User privs on', $db_tbl, ':', $privs,
      ($can_delete ? 'delete' : ''));
   if ( $privs =~ m/select/ && $privs =~ m/insert/ && $privs =~ m/update/ 
        && $can_delete ) {
      MKDEBUG && _d('User has all privs');
      return 1;
   }
   MKDEBUG && _d('User does not have all privs');
   return 0;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End TableSyncer package
# ###########################################################################

# ###########################################################################
# TableSyncChunk package 6389
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TableSyncChunk.pm
#   trunk/common/t/TableSyncChunk.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package TableSyncChunk;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);
use List::Util qw(max);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(TableChunker Quoter) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

sub name {
   return 'Chunk';
}

sub set_callback {
   my ( $self, $callback, $code ) = @_;
   $self->{$callback} = $code;
   return;
}

sub can_sync {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(tbl_struct) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my ($exact, @chunkable_cols) = $self->{TableChunker}->find_chunk_columns(
      %args,
      exact => 1,
   );
   return unless $exact;

   my $colno;
   if ( $args{chunk_col} || $args{chunk_index} ) {
      MKDEBUG && _d('Checking requested col', $args{chunk_col},
         'and/or index', $args{chunk_index});
      for my $i ( 0..$#chunkable_cols ) {
         if ( $args{chunk_col} ) {
            next unless $chunkable_cols[$i]->{column} eq $args{chunk_col};
         }
         if ( $args{chunk_index} ) {
            next unless $chunkable_cols[$i]->{index} eq $args{chunk_index};
         }
         $colno = $i;
         last;
      }

      if ( !$colno ) {
         MKDEBUG && _d('Cannot chunk on column', $args{chunk_col},
            'and/or using index', $args{chunk_index});
         return;
      }
   }
   else {
      $colno = 0;  # First, best chunkable column/index.
   }

   MKDEBUG && _d('Can chunk on column', $chunkable_cols[$colno]->{column},
      'using index', $chunkable_cols[$colno]->{index});
   return (
      1,
      chunk_col   => $chunkable_cols[$colno]->{column},
      chunk_index => $chunkable_cols[$colno]->{index},
   ),
}

sub prepare_to_sync {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl tbl_struct cols chunk_col
                          chunk_size crc_col ChangeHandler);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $chunker  = $self->{TableChunker};

   $self->{chunk_col}       = $args{chunk_col};
   $self->{crc_col}         = $args{crc_col};
   $self->{index_hint}      = $args{index_hint};
   $self->{buffer_in_mysql} = $args{buffer_in_mysql};
   $self->{ChangeHandler}   = $args{ChangeHandler};

   $self->{ChangeHandler}->fetch_back($args{dbh});

   push @{$args{cols}}, $args{chunk_col};

   my @chunks;
   my %range_params = $chunker->get_range_statistics(%args);
   if ( !grep { !defined $range_params{$_} } qw(min max rows_in_range) ) {
      ($args{chunk_size}) = $chunker->size_to_rows(%args);
      @chunks = $chunker->calculate_chunks(%args, %range_params);
   }
   else {
      MKDEBUG && _d('No range statistics; using single chunk 1=1');
      @chunks = '1=1';
   }

   $self->{chunks}    = \@chunks;
   $self->{chunk_num} = 0;
   $self->{state}     = 0;

   return;
}

sub uses_checksum {
   return 1;
}

sub set_checksum_queries {
   my ( $self, $chunk_sql, $row_sql ) = @_;
   die "I need a chunk_sql argument" unless $chunk_sql;
   die "I need a row_sql argument" unless $row_sql;
   $self->{chunk_sql} = $chunk_sql;
   $self->{row_sql}   = $row_sql;
   return;
}

sub prepare_sync_cycle {
   my ( $self, $host ) = @_;
   my $sql = 'SET @crc := "", @cnt := 0';
   MKDEBUG && _d($sql);
   $host->{dbh}->do($sql);
   return;
}

sub get_sql {
   my ( $self, %args ) = @_;
   if ( $self->{state} ) {  # select rows in a chunk
      my $q = $self->{Quoter};
      return 'SELECT /*rows in chunk*/ '
         . ($self->{buffer_in_mysql} ? 'SQL_BUFFER_RESULT ' : '')
         . $self->{row_sql} . " AS $self->{crc_col}"
         . ' FROM ' . $self->{Quoter}->quote(@args{qw(database table)})
         . ' '. ($self->{index_hint} || '')
         . ' WHERE (' . $self->{chunks}->[$self->{chunk_num}] . ')'
         . ($args{where} ? " AND ($args{where})" : '')
         . ' ORDER BY ' . join(', ', map {$q->quote($_) } @{$self->key_cols()});
   }
   else {  # select a chunk of rows
      return $self->{TableChunker}->inject_chunks(
         database   => $args{database},
         table      => $args{table},
         chunks     => $self->{chunks},
         chunk_num  => $self->{chunk_num},
         query      => $self->{chunk_sql},
         index_hint => $self->{index_hint},
         where      => [ $args{where} ],
      );
   }
}

sub same_row {
   my ( $self, %args ) = @_;
   my ($lr, $rr) = @args{qw(lr rr)};

   if ( $self->{state} ) {  # checksumming rows
      if ( $lr->{$self->{crc_col}} ne $rr->{$self->{crc_col}} ) {
         my $action   = 'UPDATE';
         my $auth_row = $lr;
         my $change_dbh;

         if ( $self->{same_row} ) {
            ($action, $auth_row, $change_dbh) = $self->{same_row}->(%args);
         }

         $self->{ChangeHandler}->change(
            $action,            # Execute the action
            $auth_row,          # with these row values
            $self->key_cols(),  # identified by these key cols
            $change_dbh,        # on this dbh
         );
      }
   }
   elsif ( $lr->{cnt} != $rr->{cnt} || $lr->{crc} ne $rr->{crc} ) {
      MKDEBUG && _d('Rows:', Dumper($lr, $rr));
      MKDEBUG && _d('Will examine this chunk before moving to next');
      $self->{state} = 1; # Must examine this chunk row-by-row
   }
}

sub not_in_right {
   my ( $self, %args ) = @_;
   die "Called not_in_right in state 0" unless $self->{state};

   my $action   = 'INSERT';
   my $auth_row = $args{lr};
   my $change_dbh;

   if ( $self->{not_in_right} ) {
      ($action, $auth_row, $change_dbh) = $self->{not_in_right}->(%args);
   }

   $self->{ChangeHandler}->change(
      $action,            # Execute the action
      $auth_row,          # with these row values
      $self->key_cols(),  # identified by these key cols
      $change_dbh,        # on this dbh
   );
   return;
}

sub not_in_left {
   my ( $self, %args ) = @_;
   die "Called not_in_left in state 0" unless $self->{state};

   my $action   = 'DELETE';
   my $auth_row = $args{rr};
   my $change_dbh;

   if ( $self->{not_in_left} ) {
      ($action, $auth_row, $change_dbh) = $self->{not_in_left}->(%args);
   }

   $self->{ChangeHandler}->change(
      $action,            # Execute the action
      $auth_row,          # with these row values
      $self->key_cols(),  # identified by these key cols
      $change_dbh,        # on this dbh
   );
   return;
}

sub done_with_rows {
   my ( $self ) = @_;
   if ( $self->{state} == 1 ) {
      $self->{state} = 2;
      MKDEBUG && _d('Setting state =', $self->{state});
   }
   else {
      $self->{state} = 0;
      $self->{chunk_num}++;
      MKDEBUG && _d('Setting state =', $self->{state},
         'chunk_num =', $self->{chunk_num});
   }
   return;
}

sub done {
   my ( $self ) = @_;
   MKDEBUG && _d('Done with', $self->{chunk_num}, 'of',
      scalar(@{$self->{chunks}}), 'chunks');
   MKDEBUG && $self->{state} && _d('Chunk differs; must examine rows');
   return $self->{state} == 0
      && $self->{chunk_num} >= scalar(@{$self->{chunks}})
}

sub pending_changes {
   my ( $self ) = @_;
   if ( $self->{state} ) {
      MKDEBUG && _d('There are pending changes');
      return 1;
   }
   else {
      MKDEBUG && _d('No pending changes');
      return 0;
   }
}

sub key_cols {
   my ( $self ) = @_;
   my @cols;
   if ( $self->{state} == 0 ) {
      @cols = qw(chunk_num);
   }
   else {
      @cols = $self->{chunk_col};
   }
   MKDEBUG && _d('State', $self->{state},',', 'key cols', join(', ', @cols));
   return \@cols;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End TableSyncChunk package
# ###########################################################################

# ###########################################################################
# TableSyncNibble package 6511
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TableSyncNibble.pm
#   trunk/common/t/TableSyncNibble.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package TableSyncNibble;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);
use List::Util qw(max);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(TableNibbler TableChunker TableParser Quoter) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

sub name {
   return 'Nibble';
}

sub can_sync {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(tbl_struct) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my $nibble_index = $self->{TableParser}->find_best_index($args{tbl_struct});
   if ( $nibble_index ) {
      MKDEBUG && _d('Best nibble index:', Dumper($nibble_index));
      if ( !$args{tbl_struct}->{keys}->{$nibble_index}->{is_unique} ) {
         MKDEBUG && _d('Best nibble index is not unique');
         return;
      }
      if ( $args{chunk_index} && $args{chunk_index} ne $nibble_index ) {
         MKDEBUG && _d('Best nibble index is not requested index',
            $args{chunk_index});
         return;
      }
   }
   else {
      MKDEBUG && _d('No best nibble index returned');
      return;
   }

   my $small_table = 0;
   if ( $args{src} && $args{src}->{dbh} ) {
      my $dbh = $args{src}->{dbh};
      my $db  = $args{src}->{db};
      my $tbl = $args{src}->{tbl};
      my $table_status;
      eval {
         my $sql = "SHOW TABLE STATUS FROM `$db` LIKE "
                 . $self->{Quoter}->literal_like($tbl);
         MKDEBUG && _d($sql);
         $table_status = $dbh->selectrow_hashref($sql);
      };
      MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
      if ( $table_status ) {
         my $n_rows   = defined $table_status->{Rows} ? $table_status->{Rows}
                      : defined $table_status->{rows} ? $table_status->{rows}
                      : undef;
         $small_table = 1 if defined $n_rows && $n_rows <= 100;
      }
   }
   MKDEBUG && _d('Small table:', $small_table);

   MKDEBUG && _d('Can nibble using index', $nibble_index);
   return (
      1,
      chunk_index => $nibble_index,
      key_cols    => $args{tbl_struct}->{keys}->{$nibble_index}->{cols},
      small_table => $small_table,
   );
}

sub prepare_to_sync {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db tbl tbl_struct chunk_index key_cols chunk_size
                          crc_col ChangeHandler);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   $self->{dbh}             = $args{dbh};
   $self->{tbl_struct}      = $args{tbl_struct};
   $self->{crc_col}         = $args{crc_col};
   $self->{index_hint}      = $args{index_hint};
   $self->{key_cols}        = $args{key_cols};
   ($self->{chunk_size})    = $self->{TableChunker}->size_to_rows(%args);
   $self->{buffer_in_mysql} = $args{buffer_in_mysql};
   $self->{small_table}     = $args{small_table};
   $self->{ChangeHandler}   = $args{ChangeHandler};

   $self->{ChangeHandler}->fetch_back($args{dbh});

   my %seen;
   my @ucols = grep { !$seen{$_}++ } @{$args{cols}}, @{$args{key_cols}};
   $args{cols} = \@ucols;

   $self->{sel_stmt} = $self->{TableNibbler}->generate_asc_stmt(
      %args,
      index    => $args{chunk_index}, # expects an index arg, not chunk_index
      asc_only => 1,
   );

   $self->{nibble}            = 0;
   $self->{cached_row}        = undef;
   $self->{cached_nibble}     = undef;
   $self->{cached_boundaries} = undef;
   $self->{state}             = 0;

   return;
}

sub uses_checksum {
   return 1;
}

sub set_checksum_queries {
   my ( $self, $nibble_sql, $row_sql ) = @_;
   die "I need a nibble_sql argument" unless $nibble_sql;
   die "I need a row_sql argument" unless $row_sql;
   $self->{nibble_sql} = $nibble_sql;
   $self->{row_sql} = $row_sql;
   return;
}

sub prepare_sync_cycle {
   my ( $self, $host ) = @_;
   my $sql = 'SET @crc := "", @cnt := 0';
   MKDEBUG && _d($sql);
   $host->{dbh}->do($sql);
   return;
}

sub get_sql {
   my ( $self, %args ) = @_;
   if ( $self->{state} ) {
      my $q = $self->{Quoter};
      return 'SELECT /*rows in nibble*/ '
         . ($self->{buffer_in_mysql} ? 'SQL_BUFFER_RESULT ' : '')
         . $self->{row_sql} . " AS $self->{crc_col}"
         . ' FROM ' . $q->quote(@args{qw(database table)})
         . ' ' . ($self->{index_hint} ? $self->{index_hint} : '')
         . ' WHERE (' . $self->__get_boundaries(%args) . ')'
         . ($args{where} ? " AND ($args{where})" : '')
         . ' ORDER BY ' . join(', ', map {$q->quote($_) } @{$self->key_cols()});
   }
   else {
      my $where = $self->__get_boundaries(%args);
      return $self->{TableChunker}->inject_chunks(
         database   => $args{database},
         table      => $args{table},
         chunks     => [ $where ],
         chunk_num  => 0,
         query      => $self->{nibble_sql},
         index_hint => $self->{index_hint},
         where      => [ $args{where} ],
      );
   }
}

sub __get_boundaries {
   my ( $self, %args ) = @_;
   my $q = $self->{Quoter};
   my $s = $self->{sel_stmt};

   my $lb;   # Lower boundary part of WHERE
   my $ub;   # Upper boundary part of WHERE
   my $row;  # Next upper boundary row or cached_row

   if ( $self->{cached_boundaries} ) {
      MKDEBUG && _d('Using cached boundaries');
      return $self->{cached_boundaries};
   }

   if ( $self->{cached_row} && $self->{cached_nibble} == $self->{nibble} ) {
      MKDEBUG && _d('Using cached row for boundaries');
      $row = $self->{cached_row};
   }
   else {
      MKDEBUG && _d('Getting next upper boundary row');
      my $sql;
      ($sql, $lb) = $self->__make_boundary_sql(%args);  # $lb from outer scope!

      if ( $self->{nibble} == 0 && !$self->{small_table} ) {
         my $explain_index = $self->__get_explain_index($sql);
         if ( lc($explain_index || '') ne lc($s->{index}) ) {
            die 'Cannot nibble table '.$q->quote($args{database}, $args{table})
               . " because MySQL chose "
               . ($explain_index ? "the `$explain_index`" : 'no') . ' index'
               . " instead of the `$s->{index}` index";
         }
      }

      $row = $self->{dbh}->selectrow_hashref($sql);
      MKDEBUG && _d($row ? 'Got a row' : "Didn't get a row");
   }

   if ( $row ) {
      my $i = 0;
      $ub   = $s->{boundaries}->{'<='};
      $ub   =~ s/\?/$q->quote_val($row->{$s->{scols}->[$i]}, $self->{tbl_struct}->{is_numeric}->{$s->{scols}->[$i++]} || 0)/eg;
   }
   else {
      MKDEBUG && _d('No upper boundary');
      $ub = '1=1';
   }

   my $where = $lb ? "($lb AND $ub)" : $ub;

   $self->{cached_row}        = $row;
   $self->{cached_nibble}     = $self->{nibble};
   $self->{cached_boundaries} = $where;

   MKDEBUG && _d('WHERE clause:', $where);
   return $where;
}

sub __make_boundary_sql {
   my ( $self, %args ) = @_;
   my $lb;
   my $q   = $self->{Quoter};
   my $s   = $self->{sel_stmt};
   my $sql = "SELECT /*nibble boundary $self->{nibble}*/ "
      . join(',', map { $q->quote($_) } @{$s->{cols}})
      . " FROM " . $q->quote($args{database}, $args{table})
      . ' ' . ($self->{index_hint} || '')
      . ($args{where} ? " WHERE ($args{where})" : "");

   if ( $self->{nibble} ) {
      my $tmp = $self->{cached_row};
      my $i   = 0;
      $lb     = $s->{boundaries}->{'>'};
      $lb     =~ s/\?/$q->quote_val($tmp->{$s->{scols}->[$i]}, $self->{tbl_struct}->{is_numeric}->{$s->{scols}->[$i++]} || 0)/eg;
      $sql   .= $args{where} ? " AND $lb" : " WHERE $lb";
   }
   $sql .= " ORDER BY " . join(',', map { $q->quote($_) } @{$self->{key_cols}})
         . ' LIMIT ' . ($self->{chunk_size} - 1) . ', 1';
   MKDEBUG && _d('Lower boundary:', $lb);
   MKDEBUG && _d('Next boundary sql:', $sql);
   return $sql, $lb;
}

sub __get_explain_index {
   my ( $self, $sql ) = @_;
   return unless $sql;
   my $explain;
   eval {
      $explain = $self->{dbh}->selectall_arrayref("EXPLAIN $sql",{Slice => {}});
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($EVAL_ERROR);
      return;
   }
   MKDEBUG && _d('EXPLAIN key:', $explain->[0]->{key}); 
   return $explain->[0]->{key};
}

sub same_row {
   my ( $self, %args ) = @_;
   my ($lr, $rr) = @args{qw(lr rr)};
   if ( $self->{state} ) {
      if ( $lr->{$self->{crc_col}} ne $rr->{$self->{crc_col}} ) {
         $self->{ChangeHandler}->change('UPDATE', $lr, $self->key_cols());
      }
   }
   elsif ( $lr->{cnt} != $rr->{cnt} || $lr->{crc} ne $rr->{crc} ) {
      MKDEBUG && _d('Rows:', Dumper($lr, $rr));
      MKDEBUG && _d('Will examine this nibble before moving to next');
      $self->{state} = 1; # Must examine this nibble row-by-row
   }
}

sub not_in_right {
   my ( $self, %args ) = @_;
   die "Called not_in_right in state 0" unless $self->{state};
   $self->{ChangeHandler}->change('INSERT', $args{lr}, $self->key_cols());
}

sub not_in_left {
   my ( $self, %args ) = @_;
   die "Called not_in_left in state 0" unless $self->{state};
   $self->{ChangeHandler}->change('DELETE', $args{rr}, $self->key_cols());
}

sub done_with_rows {
   my ( $self ) = @_;
   if ( $self->{state} == 1 ) {
      $self->{state} = 2;
      MKDEBUG && _d('Setting state =', $self->{state});
   }
   else {
      $self->{state} = 0;
      $self->{nibble}++;
      delete $self->{cached_boundaries};
      MKDEBUG && _d('Setting state =', $self->{state},
         ', nibble =', $self->{nibble});
   }
}

sub done {
   my ( $self ) = @_;
   MKDEBUG && _d('Done with nibble', $self->{nibble});
   MKDEBUG && $self->{state} && _d('Nibble differs; must examine rows');
   return $self->{state} == 0 && $self->{nibble} && !$self->{cached_row};
}

sub pending_changes {
   my ( $self ) = @_;
   if ( $self->{state} ) {
      MKDEBUG && _d('There are pending changes');
      return 1;
   }
   else {
      MKDEBUG && _d('No pending changes');
      return 0;
   }
}

sub key_cols {
   my ( $self ) = @_;
   my @cols;
   if ( $self->{state} == 0 ) {
      @cols = qw(chunk_num);
   }
   else {
      @cols = @{$self->{key_cols}};
   }
   MKDEBUG && _d('State', $self->{state},',', 'key cols', join(', ', @cols));
   return \@cols;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End TableSyncNibble package
# ###########################################################################

# ###########################################################################
# TableSyncGroupBy package 5697
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TableSyncGroupBy.pm
#   trunk/common/t/TableSyncGroupBy.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package TableSyncGroupBy;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(Quoter) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = { %args };
   return bless $self, $class;
}

sub name {
   return 'GroupBy';
}

sub can_sync {
   return 1;  # We can sync anything.
}

sub prepare_to_sync {
   my ( $self, %args ) = @_;
   my @required_args = qw(tbl_struct cols ChangeHandler);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   $self->{cols}            = $args{cols};
   $self->{buffer_in_mysql} = $args{buffer_in_mysql};
   $self->{ChangeHandler}   = $args{ChangeHandler};

   $self->{count_col} = '__maatkit_count';
   while ( $args{tbl_struct}->{is_col}->{$self->{count_col}} ) {
      $self->{count_col} = "_$self->{count_col}";
   }
   MKDEBUG && _d('COUNT column will be named', $self->{count_col});

   $self->{done} = 0;

   return;
}

sub uses_checksum {
   return 0;  # We don't need checksum queries.
}

sub set_checksum_queries {
   return;  # This shouldn't be called, but just in case.
}

sub prepare_sync_cycle {
   my ( $self, $host ) = @_;
   return;
}

sub get_sql {
   my ( $self, %args ) = @_;
   my $cols = join(', ', map { $self->{Quoter}->quote($_) } @{$self->{cols}});
   return "SELECT"
      . ($self->{buffer_in_mysql} ? ' SQL_BUFFER_RESULT' : '')
      . " $cols, COUNT(*) AS $self->{count_col}"
      . ' FROM ' . $self->{Quoter}->quote(@args{qw(database table)})
      . ' WHERE ' . ( $args{where} || '1=1' )
      . " GROUP BY $cols ORDER BY $cols";
}

sub same_row {
   my ( $self, %args ) = @_;
   my ($lr, $rr) = @args{qw(lr rr)};
   my $cc   = $self->{count_col};
   my $lc   = $lr->{$cc};
   my $rc   = $rr->{$cc};
   my $diff = abs($lc - $rc);
   return unless $diff;
   $lr = { %$lr };
   delete $lr->{$cc};
   $rr = { %$rr };
   delete $rr->{$cc};
   foreach my $i ( 1 .. $diff ) {
      if ( $lc > $rc ) {
         $self->{ChangeHandler}->change('INSERT', $lr, $self->key_cols());
      }
      else {
         $self->{ChangeHandler}->change('DELETE', $rr, $self->key_cols());
      }
   }
}

sub not_in_right {
   my ( $self, %args ) = @_;
   my $lr = $args{lr};
   $lr = { %$lr };
   my $cnt = delete $lr->{$self->{count_col}};
   foreach my $i ( 1 .. $cnt ) {
      $self->{ChangeHandler}->change('INSERT', $lr, $self->key_cols());
   }
}

sub not_in_left {
   my ( $self, %args ) = @_;
   my $rr = $args{rr};
   $rr = { %$rr };
   my $cnt = delete $rr->{$self->{count_col}};
   foreach my $i ( 1 .. $cnt ) {
      $self->{ChangeHandler}->change('DELETE', $rr, $self->key_cols());
   }
}

sub done_with_rows {
   my ( $self ) = @_;
   $self->{done} = 1;
}

sub done {
   my ( $self ) = @_;
   return $self->{done};
}

sub key_cols {
   my ( $self ) = @_;
   return $self->{cols};
}

sub pending_changes {
   my ( $self ) = @_;
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End TableSyncGroupBy package
# ###########################################################################

# ###########################################################################
# Outfile package 5266
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Outfile.pm
#   trunk/common/t/Outfile.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package Outfile;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use List::Util qw(min);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = {};
   return bless $self, $class;
}

sub write {
   my ( $self, $fh, $rows ) = @_;
   foreach my $row ( @$rows ) {
      print $fh escape($row), "\n"
         or die "Cannot write to outfile: $OS_ERROR\n";
   }
   return;
}

sub escape {
   my ( $row ) = @_;
   return join("\t", map {
      s/([\t\n\\])/\\$1/g if defined $_;  # Escape tabs etc
      defined $_ ? $_ : '\N';             # NULL = \N
   } @$row);
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;
# ###########################################################################
# End Outfile package
# ###########################################################################

# ###########################################################################
# MockSyncStream package 5697
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/MockSyncStream.pm
#   trunk/common/t/MockSyncStream.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package MockSyncStream;


use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(query cols same_row not_in_left not_in_right) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   return bless { %args }, $class;
}

sub get_sql {
   my ( $self ) = @_;
   return $self->{query};
}

sub same_row {
   my ( $self, %args ) = @_;
   return $self->{same_row}->($args{lr}, $args{rr});
}

sub not_in_right {
   my ( $self, %args ) = @_;
   return $self->{not_in_right}->($args{lr});
}

sub not_in_left {
   my ( $self, %args ) = @_;
   return $self->{not_in_left}->($args{rr});
}

sub done_with_rows {
   my ( $self ) = @_;
   $self->{done} = 1;
}

sub done {
   my ( $self ) = @_;
   return $self->{done};
}

sub key_cols {
   my ( $self ) = @_;
   return $self->{cols};
}

sub prepare {
   my ( $self, $dbh ) = @_;
   return;
}

sub pending_changes {
   my ( $self ) = @_;
   return;
}

sub get_result_set_struct {
   my ( $dbh, $sth ) = @_;
   my @cols     = @{$sth->{NAME}};
   my @types    = map { $dbh->type_info($_)->{TYPE_NAME} } @{$sth->{TYPE}};
   my @nullable = map { $dbh->type_info($_)->{NULLABLE} == 1 ? 1 : 0 } @{$sth->{TYPE}};
   my @p = @{$sth->{PRECISION}};
   my @s = @{$sth->{SCALE}};

   my $struct   = {
      cols => \@cols, 
   };

   for my $i ( 0..$#cols ) {
      my $col  = $cols[$i];
      my $type = $types[$i];
      $struct->{is_col}->{$col}      = 1;
      $struct->{col_posn}->{$col}    = $i;
      $struct->{type_for}->{$col}    = $type;
      $struct->{is_nullable}->{$col} = $nullable[$i];
      $struct->{is_numeric}->{$col} 
         = ($type =~ m/(?:(?:tiny|big|medium|small)?int|float|double|decimal|year)/ ? 1 : 0);
      $struct->{size}->{$col}
         = ($type =~ m/(?:float|double)/)           ? "($s[$i],$p[$i])"
         : ($type =~ m/(?:decimal)/)                ? "($p[$i],$s[$i])"
         : ($type =~ m/(?:char|varchar)/ && $p[$i]) ? "($p[$i])"
         :                                            undef;
   }

   return $struct;
}

sub as_arrayref {
   my ( $sth, $row ) = @_;
   my @cols = @{$sth->{NAME}};
   my @row  = @{$row}{@cols};
   return \@row;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End MockSyncStream package
# ###########################################################################

# ###########################################################################
# MockSth package 5266
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/MockSth.pm
#   trunk/common/t/MockSth.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package MockSth;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, @rows ) = @_;
   my $n_rows = scalar @rows;
   my $self = {
      cursor => 0,
      Active => $n_rows,
      rows   => \@rows,
      n_rows => $n_rows,
      NAME   => [],
   };
   return bless $self, $class;
}

sub reset {
   my ( $self ) = @_;
   $self->{cursor} = 0;
   $self->{Active} = $self->{n_rows};
   return;
}

sub fetchrow_hashref {
   my ( $self ) = @_;
   my $row;
   if ( $self->{cursor} < $self->{n_rows} ) {
      $row = $self->{rows}->[$self->{cursor}++];
   }
   $self->{Active} = $self->{cursor} < $self->{n_rows};
   return $row;
}

sub fetchall_arrayref {
   my ( $self ) = @_;
   my @rows;
   if ( $self->{cursor} < $self->{n_rows} ) {
      my @cols = @{$self->{NAME}};
      die "Cannot fetchall_arrayref() unless NAME is set" unless @cols;
      @rows =  map { [ @{$_}{@cols} ] }
         @{$self->{rows}}[ $self->{cursor}..($self->{n_rows} - 1) ];
      $self->{cursor} = $self->{n_rows};
   }
   $self->{Active} = $self->{cursor} < $self->{n_rows};
   return \@rows;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End MockSth package
# ###########################################################################

# ###########################################################################
# VersionParser package 6667
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/VersionParser.pm
#   trunk/common/t/VersionParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package VersionParser;

use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class ) = @_;
   bless {}, $class;
}

sub parse {
   my ( $self, $str ) = @_;
   my $result = sprintf('%03d%03d%03d', $str =~ m/(\d+)/g);
   MKDEBUG && _d($str, 'parses to', $result);
   return $result;
}

sub version_ge {
   my ( $self, $dbh, $target ) = @_;
   if ( !$self->{$dbh} ) {
      $self->{$dbh} = $self->parse(
         $dbh->selectrow_array('SELECT VERSION()'));
   }
   my $result = $self->{$dbh} ge $self->parse($target) ? 1 : 0;
   MKDEBUG && _d($self->{$dbh}, 'ge', $target, ':', $result);
   return $result;
}

sub innodb_version {
   my ( $self, $dbh ) = @_;
   return unless $dbh;
   my $innodb_version = "NO";

   my ($innodb) =
      grep { $_->{engine} =~ m/InnoDB/i }
      map  {
         my %hash;
         @hash{ map { lc $_ } keys %$_ } = values %$_;
         \%hash;
      }
      @{ $dbh->selectall_arrayref("SHOW ENGINES", {Slice=>{}}) };
   if ( $innodb ) {
      MKDEBUG && _d("InnoDB support:", $innodb->{support});
      if ( $innodb->{support} =~ m/YES|DEFAULT/i ) {
         my $vars = $dbh->selectrow_hashref(
            "SHOW VARIABLES LIKE 'innodb_version'");
         $innodb_version = !$vars ? "BUILTIN"
                         :          ($vars->{Value} || $vars->{value});
      }
      else {
         $innodb_version = $innodb->{support};  # probably DISABLED or NO
      }
   }

   MKDEBUG && _d("InnoDB version:", $innodb_version);
   return $innodb_version;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End VersionParser package
# ###########################################################################

# ###########################################################################
# ReportFormatter package 7473
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/ReportFormatter.pm
#   trunk/common/t/ReportFormatter.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package ReportFormatter;


use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use List::Util qw(min max);
use POSIX qw(ceil);

eval { require Term::ReadKey };
my $have_term = $EVAL_ERROR ? 0 : 1;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      underline_header     => 1,
      line_prefix          => '# ',
      line_width           => 78,
      column_spacing       => ' ',
      extend_right         => 0,
      truncate_line_mark   => '...',
      column_errors        => 'warn',
      truncate_header_side => 'left',
      strip_whitespace     => 1,
      %args,              # args above can be overriden, args below cannot
      n_cols              => 0,
   };

   if ( ($self->{line_width} || '') eq 'auto' ) {
      die "Cannot auto-detect line width because the Term::ReadKey module "
         . "is not installed" unless $have_term;
      ($self->{line_width}) = GetTerminalSize();
   }
   MKDEBUG && _d('Line width:', $self->{line_width});

   return bless $self, $class;
}

sub set_title {
   my ( $self, $title ) = @_;
   $self->{title} = $title;
   return;
}

sub set_columns {
   my ( $self, @cols ) = @_;
   my $min_hdr_wid = 0;  # check that header fits on line
   my $used_width  = 0;
   my @auto_width_cols;

   for my $i ( 0..$#cols ) {
      my $col      = $cols[$i];
      my $col_name = $col->{name};
      my $col_len  = length $col_name;
      die "Column does not have a name" unless defined $col_name;

      if ( $col->{width} ) {
         $col->{width_pct} = ceil(($col->{width} * 100) / $self->{line_width});
         MKDEBUG && _d('col:', $col_name, 'width:', $col->{width}, 'chars =',
            $col->{width_pct}, '%');
      }

      if ( $col->{width_pct} ) {
         $used_width += $col->{width_pct};
      }
      else {
         MKDEBUG && _d('Auto width col:', $col_name);
         $col->{auto_width} = 1;
         push @auto_width_cols, $i;
      }

      $col->{truncate}        = 1 unless defined $col->{truncate};
      $col->{truncate_mark}   = '...' unless defined $col->{truncate_mark};
      $col->{truncate_side} ||= 'right';
      $col->{undef_value}     = '' unless defined $col->{undef_value};

      $col->{min_val} = 0;
      $col->{max_val} = 0;

      $min_hdr_wid        += $col_len;
      $col->{header_width} = $col_len;

      $col->{right_most} = 1 if $i == $#cols;

      push @{$self->{cols}}, $col;
   }

   $self->{n_cols} = scalar @cols;

   if ( ($used_width || 0) > 100 ) {
      die "Total width_pct for all columns is >100%";
   }

   if ( @auto_width_cols ) {
      my $wid_per_col = int((100 - $used_width) / scalar @auto_width_cols);
      MKDEBUG && _d('Line width left:', (100-$used_width), '%;',
         'each auto width col:', $wid_per_col, '%');
      map { $self->{cols}->[$_]->{width_pct} = $wid_per_col } @auto_width_cols;
   }

   $min_hdr_wid += ($self->{n_cols} - 1) * length $self->{column_spacing};
   MKDEBUG && _d('min header width:', $min_hdr_wid);
   if ( $min_hdr_wid > $self->{line_width} ) {
      MKDEBUG && _d('Will truncate headers because min header width',
         $min_hdr_wid, '> line width', $self->{line_width});
      $self->{truncate_headers} = 1;
   }

   return;
}

sub add_line {
   my ( $self, @vals ) = @_;
   my $n_vals = scalar @vals;
   if ( $n_vals != $self->{n_cols} ) {
      $self->_column_error("Number of values $n_vals does not match "
         . "number of columns $self->{n_cols}");
   }
   for my $i ( 0..($n_vals-1) ) {
      my $col   = $self->{cols}->[$i];
      my $val   = defined $vals[$i] ? $vals[$i] : $col->{undef_value};
      if ( $self->{strip_whitespace} ) {
         $val =~ s/^\s+//g;
         $val =~ s/\s+$//;
         $vals[$i] = $val;
      }
      my $width = length $val;
      $col->{min_val} = min($width, ($col->{min_val} || $width));
      $col->{max_val} = max($width, ($col->{max_val} || $width));
   }
   push @{$self->{lines}}, \@vals;
   return;
}

sub get_report {
   my ( $self, %args ) = @_;

   $self->_calculate_column_widths();
   $self->_truncate_headers() if $self->{truncate_headers};
   $self->_truncate_line_values(%args);

   my @col_fmts = $self->_make_column_formats();
   my $fmt      = ($self->{line_prefix} || '')
                . join($self->{column_spacing}, @col_fmts);
   MKDEBUG && _d('Format:', $fmt);

   (my $hdr_fmt = $fmt) =~ s/%([^-])/%-$1/g;

   my @lines;
   push @lines, sprintf "$self->{line_prefix}$self->{title}" if $self->{title};
   push @lines, $self->_truncate_line(
         sprintf($hdr_fmt, map { $_->{name} } @{$self->{cols}}),
         strip => 1,
         mark  => '',
   );

   if ( $self->{underline_header} ) {
      my @underlines = map { '=' x $_->{print_width} } @{$self->{cols}};
      push @lines, $self->_truncate_line(
         sprintf($fmt, @underlines),
         mark  => '',
      );
   }

   push @lines, map {
      my $vals = $_;
      my $i    = 0;
      my @vals = map {
            defined $_ ? $_ : $self->{cols}->[$i++]->{undef_value}
      } @$vals;
      my $line = sprintf($fmt, @vals);
      if ( $self->{extend_right} ) {
         $line;
      }
      else {
         $self->_truncate_line($line);
      }
   } @{$self->{lines}};

   return join("\n", @lines) . "\n";
}

sub truncate_value {
   my ( $self, $col, $val, $width, $side ) = @_;
   return $val if length $val <= $width;
   return $val if $col->{right_most} && $self->{extend_right};
   $side  ||= $col->{truncate_side};
   my $mark = $col->{truncate_mark};
   if ( $side eq 'right' ) {
      $val  = substr($val, 0, $width - length $mark);
      $val .= $mark;
   }
   elsif ( $side eq 'left') {
      $val = $mark . substr($val, -1 * $width + length $mark);
   }
   else {
      MKDEBUG && _d("I don't know how to", $side, "truncate values");
   }
   return $val;
}

sub _calculate_column_widths {
   my ( $self ) = @_;

   my $extra_space = 0;
   foreach my $col ( @{$self->{cols}} ) {
      my $print_width = int($self->{line_width} * ($col->{width_pct} / 100));

      MKDEBUG && _d('col:', $col->{name}, 'width pct:', $col->{width_pct},
         'char width:', $print_width,
         'min val:', $col->{min_val}, 'max val:', $col->{max_val});

      if ( $col->{auto_width} ) {
         if ( $col->{min_val} && $print_width < $col->{min_val} ) {
            MKDEBUG && _d('Increased to min val width:', $col->{min_val});
            $print_width = $col->{min_val};
         }
         elsif ( $col->{max_val} &&  $print_width > $col->{max_val} ) {
            MKDEBUG && _d('Reduced to max val width:', $col->{max_val});
            $extra_space += $print_width - $col->{max_val};
            $print_width  = $col->{max_val};
         }
      }

      $col->{print_width} = $print_width;
      MKDEBUG && _d('print width:', $col->{print_width});
   }

   MKDEBUG && _d('Extra space:', $extra_space);
   while ( $extra_space-- ) {
      foreach my $col ( @{$self->{cols}} ) {
         if (    $col->{auto_width}
              && (    $col->{print_width} < $col->{max_val}
                   || $col->{print_width} < $col->{header_width})
         ) {
            $col->{print_width}++;
         }
      }
   }

   return;
}

sub _truncate_headers {
   my ( $self, $col ) = @_;
   my $side = $self->{truncate_header_side};
   foreach my $col ( @{$self->{cols}} ) {
      my $col_name    = $col->{name};
      my $print_width = $col->{print_width};
      next if length $col_name <= $print_width;
      $col->{name}  = $self->truncate_value($col, $col_name, $print_width, $side);
      MKDEBUG && _d('Truncated hdr', $col_name, 'to', $col->{name},
         'max width:', $print_width);
   }
   return;
}

sub _truncate_line_values {
   my ( $self, %args ) = @_;
   my $n_vals = $self->{n_cols} - 1;
   foreach my $vals ( @{$self->{lines}} ) {
      for my $i ( 0..$n_vals ) {
         my $col   = $self->{cols}->[$i];
         my $val   = defined $vals->[$i] ? $vals->[$i] : $col->{undef_value};
         my $width = length $val;

         if ( $col->{print_width} && $width > $col->{print_width} ) {
            if ( !$col->{truncate} ) {
               $self->_column_error("Value '$val' is too wide for column "
                  . $col->{name});
            }

            my $callback    = $args{truncate_callback};
            my $print_width = $col->{print_width};
            $val = $callback ? $callback->($col, $val, $print_width)
                 :             $self->truncate_value($col, $val, $print_width);
            MKDEBUG && _d('Truncated val', $vals->[$i], 'to', $val,
               '; max width:', $print_width);
            $vals->[$i] = $val;
         }
      }
   }
   return;
}

sub _make_column_formats {
   my ( $self ) = @_;
   my @col_fmts;
   my $n_cols = $self->{n_cols} - 1;
   for my $i ( 0..$n_cols ) {
      my $col = $self->{cols}->[$i];

      my $width = $col->{right_most} && !$col->{right_justify} ? ''
                : $col->{print_width};

      my $col_fmt  = '%' . ($col->{right_justify} ? '' : '-') . $width . 's';
      push @col_fmts, $col_fmt;
   }
   return @col_fmts;
}

sub _truncate_line {
   my ( $self, $line, %args ) = @_;
   my $mark = defined $args{mark} ? $args{mark} : $self->{truncate_line_mark};
   if ( $line ) {
      $line =~ s/\s+$// if $args{strip};
      my $len  = length($line);
      if ( $len > $self->{line_width} ) {
         $line  = substr($line, 0, $self->{line_width} - length $mark);
         $line .= $mark if $mark;
      }
   }
   return $line;
}

sub _column_error {
   my ( $self, $err ) = @_;
   my $msg = "Column error: $err";
   $self->{column_errors} eq 'die' ? die $msg : warn $msg;
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End ReportFormatter package
# ###########################################################################

# ###########################################################################
# UpgradeReportFormatter package 7193
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/UpgradeReportFormatter.pm
#   trunk/common/t/UpgradeReportFormatter.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################


package UpgradeReportFormatter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
Transformers->import(qw(make_checksum percentage_of shorten micro_t));

use constant MKDEBUG           => $ENV{MKDEBUG};
use constant LINE_LENGTH       => 74;
use constant MAX_STRING_LENGTH => 10;

my %formatting_function = (
   ts => sub {
      my ( $stats ) = @_;
      my $min = parse_timestamp($stats->{min} || '');
      my $max = parse_timestamp($stats->{max} || '');
      return $min && $max ? "$min to $max" : '';
   },
);

my $bool_format = '# %3s%% %-6s %s';

sub new {
   my ( $class, %args ) = @_;
   return bless { }, $class;
}

sub event_report {
   my ( $self, %args ) = @_;
   my @required_args = qw(where rank worst meta_ea hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($where, $rank, $worst, $meta_ea, $hosts) = @args{@required_args};
   my $meta_stats = $meta_ea->results;
   my @result;


   my $line = sprintf(
      '# Query %d: ID 0x%s at byte %d ',
      $rank || 0,
      make_checksum($where),
      0, # $sample->{pos_in_log} || 0
   );
   $line .= ('_' x (LINE_LENGTH - length($line)));
   push @result, $line;

   my $class = $meta_stats->{classes}->{$where};
   push @result,
      '# Found ' . ($class->{differences}->{sum} || 0)
      . ' differences in ' . $class->{sampleno}->{cnt} . " samples:\n";

   my $fmt = "# %-17s %d\n";
   my @diffs = grep { $_ =~ m/^different_/ } keys %$class;
   foreach my $diff ( sort @diffs ) {
      push @result,
         sprintf $fmt, '  ' . make_label($diff), $class->{$diff}->{sum};
   }

   my $report = new ReportFormatter(
      underline_header => 0,
      strip_whitespace => 0,
   );
   $report->set_columns(
      { name => '' },
      map { { name => $_->{name}, right_justify => 1 } } @$hosts,
   );
   foreach my $thing ( qw(Errors Warnings) ) {
      my @vals = $thing;
      foreach my $host ( @$hosts ) {
         my $ea    = $host->{ea};
         my $stats = $ea->results->{classes}->{$where};
         if ( $stats && $stats->{$thing} ) {
            push @vals, shorten($stats->{$thing}->{sum}, d=>1_000, p=>0)
         }
         else {
            push @vals, 0;
         }
      }
      $report->add_line(@vals);
   }
   foreach my $thing ( qw(Query_time row_count) ) {
      my @vals;

      foreach my $host ( @$hosts ) {
         my $ea    = $host->{ea};
         my $stats = $ea->results->{classes}->{$where};
         if ( $stats && $stats->{$thing} ) {
            my $vals = $stats->{$thing};
            my $func = $thing =~ m/time$/ ? \&micro_t : \&shorten;
            my $metrics = $host->{ea}->metrics(attrib=>$thing, where=>$where);
            my @n = (
               @{$vals}{qw(sum min max)},
               ($vals->{sum} || 0) / ($vals->{cnt} || 1),
               @{$metrics}{qw(pct_95 stddev median)},
            );
            @n = map { defined $_ ? $func->($_) : '' } @n;
            push @vals, \@n;
         }
         else {
            push @vals, undef;
         }
      }

      if ( scalar @vals && grep { defined } @vals ) {
         $report->add_line($thing, map { '' } @$hosts);
         my @metrics = qw(sum min max avg pct_95 stddev median);
         for my $i ( 0..$#metrics ) {
            my @n = '  ' . $metrics[$i];
            push @n, map { $_ && defined $_->[$i] ? $_->[$i] : '' } @vals;
            $report->add_line(@n);
         }
      }
   }

   push @result, $report->get_report();

   return join("\n", map { s/\s+$//; $_ } @result) . "\n";
}

sub make_label {
   my ( $val ) = @_;

   $val =~ s/^different_//;
   $val =~ s/_/ /g;

   return $val;
}

sub format_string_list {
   my ( $stats ) = @_;
   if ( exists $stats->{unq} ) {
      my $cnt_for = $stats->{unq};
      if ( 1 == keys %$cnt_for ) {
         my ($str) = keys %$cnt_for;
         $str = substr($str, 0, LINE_LENGTH - 30) . '...'
            if length $str > LINE_LENGTH - 30;
         return (1, $str);
      }
      my $line = '';
      my @top = sort { $cnt_for->{$b} <=> $cnt_for->{$a} || $a cmp $b }
                     keys %$cnt_for;
      my $i = 0;
      foreach my $str ( @top ) {
         my $print_str;
         if ( length $str > MAX_STRING_LENGTH ) {
            $print_str = substr($str, 0, MAX_STRING_LENGTH) . '...';
         }
         else {
            $print_str = $str;
         }
         last if (length $line) + (length $print_str)  > LINE_LENGTH - 27;
         $line .= "$print_str ($cnt_for->{$str}), ";
         $i++;
      }
      $line =~ s/, $//;
      if ( $i < @top ) {
         $line .= "... " . (@top - $i) . " more";
      }
      return (scalar keys %$cnt_for, $line);
   }
   else {
      return ($stats->{cnt});
   }
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End UpgradeReportFormatter package
# ###########################################################################

# ###########################################################################
# CompareResults package 7096
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/CompareResults.pm
#   trunk/common/t/CompareResults.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package CompareResults;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Time::HiRes qw(time);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(method base-dir plugins get_id
                          QueryParser MySQLDump TableParser TableSyncer Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
      diffs   => {},
      samples => {},
   };
   return bless $self, $class;
}

sub before_execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $dbh) = @args{@required_args};
   my $sql;

   if ( $self->{method} eq 'checksum' ) {
      my ($db, $tmp_tbl) = @args{qw(db temp-table)};
      $db = $args{'temp-database'} if $args{'temp-database'};
      die "Cannot checksum results without a database"
         unless $db;

      $tmp_tbl = $self->{Quoter}->quote($db, $tmp_tbl);
      eval {
         $sql = "DROP TABLE IF EXISTS $tmp_tbl";
         MKDEBUG && _d($sql);
         $dbh->do($sql);

         $sql = "SET storage_engine=MyISAM";
         MKDEBUG && _d($sql);
         $dbh->do($sql);
      };
      die "Failed to drop temporary table $tmp_tbl: $EVAL_ERROR"
         if $EVAL_ERROR;

      $event->{tmp_tbl} = $tmp_tbl; 

      $event->{wrapped_query}
         = "CREATE TEMPORARY TABLE $tmp_tbl AS $event->{arg}";
      MKDEBUG && _d('Wrapped query:', $event->{wrapped_query});
   }

   return $event;
}

sub execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $dbh) = @args{@required_args};
   my ( $start, $end, $query_time );


   MKDEBUG && _d('Executing query');
   $event->{Query_time} = 0;
   if ( $self->{method} eq 'rows' ) {
      my $query = $event->{arg};
      my $sth;
      eval {
         $sth = $dbh->prepare($query);
      };
      die "Failed to prepare query: $EVAL_ERROR" if $EVAL_ERROR;

      eval {
         $start = time();
         $sth->execute();
         $end   = time();
         $query_time = sprintf '%.6f', $end - $start;
      };
      die "Failed to execute query: $EVAL_ERROR" if $EVAL_ERROR;

      $event->{results_sth} = $sth;
   }
   else {
      die "No wrapped query" unless $event->{wrapped_query};
      my $query = $event->{wrapped_query};
      eval {
         $start = time();
         $dbh->do($query);
         $end   = time();
         $query_time = sprintf '%.6f', $end - $start;
      };
      if ( $EVAL_ERROR ) {
         delete $event->{wrapped_query};
         delete $event->{tmp_tbl};
         die "Failed to execute query: $EVAL_ERROR";
      }
   }

   $event->{Query_time} = $query_time;

   return $event;
}

sub after_execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   return $args{event};
}

sub compare {
   my ( $self, %args ) = @_;
   my @required_args = qw(events hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($events, $hosts) = @args{@required_args};
   return $self->{method} eq 'rows' ? $self->_compare_rows(%args)
                                    : $self->_compare_checksums(%args);
}

sub _compare_checksums {
   my ( $self, %args ) = @_;
   my @required_args = qw(events hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($events, $hosts) = @args{@required_args};

   my $different_row_counts    = 0;
   my $different_column_counts = 0; # TODO
   my $different_column_types  = 0; # TODO
   my $different_checksums     = 0;

   my $n_events = scalar @$events;
   foreach my $i ( 0..($n_events-1) ) {
      $events->[$i] = $self->_checksum_results(
         event => $events->[$i],
         dbh   => $hosts->[$i]->{dbh},
      );
      if ( $i ) {
         if ( ($events->[0]->{checksum} || 0)
              != ($events->[$i]->{checksum}||0) ) {
            $different_checksums++;
         }
         if ( ($events->[0]->{row_count} || 0)
              != ($events->[$i]->{row_count} || 0) ) {
            $different_row_counts++
         }

         delete $events->[$i]->{wrapped_query};
      }
   }
   delete $events->[0]->{wrapped_query};

   my $item     = $events->[0]->{fingerprint} || $events->[0]->{arg};
   my $sampleno = $events->[0]->{sampleno} || 0;
   if ( $different_checksums ) {
      $self->{diffs}->{checksums}->{$item}->{$sampleno}
         = [ map { $_->{checksum} } @$events ];
      $self->{samples}->{$item}->{$sampleno} = $events->[0]->{arg};
   }
   if ( $different_row_counts ) {
      $self->{diffs}->{row_counts}->{$item}->{$sampleno}
         = [ map { $_->{row_count} } @$events ];
      $self->{samples}->{$item}->{$sampleno} = $events->[0]->{arg};
   }

   return (
      different_row_counts    => $different_row_counts,
      different_checksums     => $different_checksums,
      different_column_counts => $different_column_counts,
      different_column_types  => $different_column_types,
   );
}

sub _checksum_results {
   my ( $self, %args ) = @_;
   my @required_args = qw(event dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $dbh) = @args{@required_args};

   my $sql;
   my $n_rows       = 0;
   my $tbl_checksum = 0;
   if ( $event->{wrapped_query} && $event->{tmp_tbl} ) {
      my $tmp_tbl = $event->{tmp_tbl};
      eval {
         $sql = "SELECT COUNT(*) FROM $tmp_tbl";
         MKDEBUG && _d($sql);
         ($n_rows) = @{ $dbh->selectcol_arrayref($sql) };

         $sql = "CHECKSUM TABLE $tmp_tbl";
         MKDEBUG && _d($sql);
         $tbl_checksum = $dbh->selectrow_arrayref($sql)->[1];
      };
      die "Failed to checksum table: $EVAL_ERROR"
         if $EVAL_ERROR;
   
      $sql = "DROP TABLE IF EXISTS $tmp_tbl";
      MKDEBUG && _d($sql);
     eval {
         $dbh->do($sql);
      };
      MKDEBUG && $EVAL_ERROR && _d('Error:', $EVAL_ERROR);
   }
   else {
      MKDEBUG && _d("Event doesn't have wrapped query or tmp tbl");
   }

   $event->{row_count} = $n_rows;
   $event->{checksum}  = $tbl_checksum;
   MKDEBUG && _d('row count:', $n_rows, 'checksum:', $tbl_checksum);

   return $event;
}

sub _compare_rows {
   my ( $self, %args ) = @_;
   my @required_args = qw(events hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($events, $hosts) = @args{@required_args};

   my $different_row_counts    = 0;
   my $different_column_counts = 0; # TODO
   my $different_column_types  = 0; # TODO
   my $different_column_values = 0;

   my $n_events = scalar @$events;
   my $event0   = $events->[0]; 
   my $item     = $event0->{fingerprint} || $event0->{arg};
   my $sampleno = $event0->{sampleno} || 0;
   my $dbh      = $hosts->[0]->{dbh};  # doesn't matter which one

   if ( !$event0->{results_sth} ) {
      MKDEBUG && _d("Event 0 doesn't have a results sth");
      return (
         different_row_counts    => $different_row_counts,
         different_column_values => $different_column_values,
         different_column_counts => $different_column_counts,
         different_column_types  => $different_column_types,
      );
   }

   my $res_struct = MockSyncStream::get_result_set_struct($dbh,
      $event0->{results_sth});
   MKDEBUG && _d('Result set struct:', Dumper($res_struct));

   my @event0_rows      = @{ $event0->{results_sth}->fetchall_arrayref({}) };
   $event0->{row_count} = scalar @event0_rows;
   my $left = new MockSth(@event0_rows);
   $left->{NAME} = [ @{$event0->{results_sth}->{NAME}} ];

   EVENT:
   foreach my $i ( 1..($n_events-1) ) {
      my $event = $events->[$i];
      my $right = $event->{results_sth};

      $event->{row_count} = 0;

      my $no_diff      = 1;  # results are identical; this catches 0 row results
      my $outfile      = new Outfile();
      my ($left_outfile, $right_outfile, $n_rows);
      my $same_row     = sub {
            $event->{row_count}++;  # Keep track of this event's row_count.
            return;
      };
      my $not_in_left  = sub {
         my ( $rr ) = @_;
         $no_diff = 0;
         ($right_outfile, $n_rows) = $self->write_to_outfile(
            side    => 'right',
            sth     => $right,
            row     => $rr,
            Outfile => $outfile,
         );
         return;
      };
      my $not_in_right = sub {
         my ( $lr ) = @_;
         $no_diff = 0;
         ($left_outfile, undef) = $self->write_to_outfile(
            side    => 'left',
            sth     => $left,
            row     => $lr,
            Outfile => $outfile,
         ); 
         return;
      };

      my $rd       = new RowDiff(dbh => $dbh);
      my $mocksync = new MockSyncStream(
         query        => $event0->{arg},
         cols         => $res_struct->{cols},
         same_row     => $same_row,
         not_in_left  => $not_in_left,
         not_in_right => $not_in_right,
      );

      MKDEBUG && _d('Comparing result sets with MockSyncStream');
      $rd->compare_sets(
         left_sth   => $left,
         right_sth  => $right,
         syncer     => $mocksync,
         tbl_struct => $res_struct,
      );

      $event->{row_count} += $n_rows || 0;

      MKDEBUG && _d('Left has', $event0->{row_count}, 'rows, right has',
         $event->{row_count});

      $different_row_counts++ if $event0->{row_count} != $event->{row_count};
      if ( $different_row_counts ) {
         $self->{diffs}->{row_counts}->{$item}->{$sampleno}
            = [ $event0->{row_count}, $event->{row_count} ];
         $self->{samples}->{$item}->{$sampleno} = $event0->{arg};
      }

      $left->reset();
      if ( $no_diff ) {
         delete $event->{results_sth};
         next EVENT;
      }

      MKDEBUG && _d('Result sets are different');


      if ( !$left_outfile ) {
         MKDEBUG && _d('Right has extra rows not in left');
         (undef, $left_outfile) = $self->open_outfile(side => 'left');
      }
      if ( !$right_outfile ) {
         MKDEBUG && _d('Left has extra rows not in right');
         (undef, $right_outfile) = $self->open_outfile(side => 'right');
      }

      my @diff_rows = $self->diff_rows(
         %args,             # for options like max-different-rows
         left_dbh        => $hosts->[0]->{dbh},
         left_outfile    => $left_outfile,
         right_dbh       => $hosts->[$i]->{dbh},
         right_outfile   => $right_outfile,
         res_struct      => $res_struct,
         query           => $event0->{arg},
         db              => $args{'temp-database'} || $event0->{db},
      );

      if ( scalar @diff_rows ) { 
         $different_column_values++; 
         $self->{diffs}->{col_vals}->{$item}->{$sampleno} = \@diff_rows;
         $self->{samples}->{$item}->{$sampleno} = $event0->{arg};
      }

      delete $event->{results_sth};
   }
   delete $event0->{results_sth};

   return (
      different_row_counts    => $different_row_counts,
      different_column_values => $different_column_values,
      different_column_counts => $different_column_counts,
      different_column_types  => $different_column_types,
   );
}

sub diff_rows {
   my ( $self, %args ) = @_;
   my @required_args = qw(left_dbh left_outfile right_dbh right_outfile
                          res_struct db query);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($left_dbh, $left_outfile, $right_dbh, $right_outfile, $res_struct,
       $db, $query)
      = @args{@required_args};

   my $orig_left_db  = $self->_use_db($left_dbh, $db);
   my $orig_right_db = $self->_use_db($right_dbh, $db);

   my $left_tbl  = "`$db`.`mk_upgrade_left`";
   my $right_tbl = "`$db`.`mk_upgrade_right`";
   my $table_ddl = $self->make_table_ddl($res_struct);

   $left_dbh->do("DROP TABLE IF EXISTS $left_tbl");
   $left_dbh->do("CREATE TABLE $left_tbl $table_ddl");
   $left_dbh->do("LOAD DATA LOCAL INFILE '$left_outfile' "
      . "INTO TABLE $left_tbl");

   $right_dbh->do("DROP TABLE IF EXISTS $right_tbl");
   $right_dbh->do("CREATE TABLE $right_tbl $table_ddl");
   $right_dbh->do("LOAD DATA LOCAL INFILE '$right_outfile' "
      . "INTO TABLE $right_tbl");

   MKDEBUG && _d('Loaded', $left_outfile, 'into table', $left_tbl, 'and',
      $right_outfile, 'into table', $right_tbl);

   if ( $args{'add-indexes'} ) {
      $self->add_indexes(
         %args,
         dsts      => [
            { dbh => $left_dbh,  tbl => $left_tbl  },
            { dbh => $right_dbh, tbl => $right_tbl },
         ],
      );
   }

   my $max_diff = $args{'max-different-rows'} || 1_000;  # 1k=sanity/safety
   my $n_diff   = 0;
   my @missing_rows;  # not currently saved; row counts show missing rows
   my @different_rows;
   use constant LEFT  => 0;
   use constant RIGHT => 1;
   my @l_r = (undef, undef);
   my @last_diff_col;
   my $last_diff = 0;
   my $key_cmp      = sub {
      push @last_diff_col, [@_];
      $last_diff--;
      return;
   };
   my $same_row = sub {
      my ( %args ) = @_;
      my ($lr, $rr) = @args{qw(lr rr)};
      if ( $l_r[LEFT] && $l_r[RIGHT] ) {
         MKDEBUG && _d('Saving different row');
         push @different_rows, $last_diff_col[$last_diff];
         $n_diff++;
      }
      elsif ( $l_r[LEFT] ) {
         MKDEBUG && _d('Saving not in right row');
         $n_diff++;
      }
      elsif ( $l_r[RIGHT] ) {
         MKDEBUG && _d('Saving not in left row');
         $n_diff++;
      }
      else {
         MKDEBUG && _d('No missing or different rows in queue');
      }
      @l_r           = (undef, undef);
      @last_diff_col = ();
      $last_diff     = 0;
      return;
   };
   my $not_in_left  = sub {
      my ( %args ) = @_;
      my ($lr, $rr) = @args{qw(lr rr)};
      $same_row->() if $l_r[RIGHT];  # last missing row
      $l_r[RIGHT] = $rr;
      $same_row->(@l_r) if $l_r[LEFT] && $l_r[RIGHT];
      return;
   };
   my $not_in_right = sub {
      my ( %args ) = @_;
      my ($lr, $rr) = @args{qw(lr rr)};
      $same_row->() if $l_r[LEFT];  # last missing row
      $l_r[LEFT] = $lr;
      $same_row->(@l_r) if $l_r[LEFT] && $l_r[RIGHT];
      return;
   };
   my $done = sub {
      my ( %args ) = @_;
      my ($left, $right) = @args{qw(left_sth right_sth)};
      MKDEBUG && _d('Found', $n_diff, 'of', $max_diff, 'max differences');
      if ( $n_diff >= $max_diff ) {
         MKDEBUG && _d('Done comparing rows, got --max-differences', $max_diff);
         $left->finish();
         $right->finish();
         return 1;
      }
      return 0;
   };
   my $trf;
   if ( my $n = $args{'float-precision'} ) {
      $trf = sub {
         my ( $l, $r, $tbl, $col ) = @_;
         return $l, $r
            unless $tbl->{type_for}->{$col} =~ m/(?:float|double|decimal)/;
         my $l_rounded = sprintf "%.${n}f", $l;
         my $r_rounded = sprintf "%.${n}f", $r;
         MKDEBUG && _d('Rounded', $l, 'to', $l_rounded,
            'and', $r, 'to', $r_rounded);
         return $l_rounded, $r_rounded;
      };
   };

   my $rd = new RowDiff(
      dbh          => $left_dbh,
      key_cmp      => $key_cmp,
      same_row     => $same_row,
      not_in_left  => $not_in_left,
      not_in_right => $not_in_right,
      done         => $done,
      trf          => $trf,
   );
   my $ch = new ChangeHandler(
      left_db    => $db,
      left_tbl   => 'mk_upgrade_left',
      right_db   => $db,
      right_tbl  => 'mk_upgrade_right',
      tbl_struct => $res_struct,
      queue      => 0,
      replace    => 0,
      actions    => [],
      Quoter     => $self->{Quoter},
   );

   $self->{TableSyncer}->sync_table(
      plugins       => $self->{plugins},
      src           => {
         dbh => $left_dbh,
         db  => $db,
         tbl => 'mk_upgrade_left',
      },
      dst           => {
         dbh => $right_dbh,
         db  => $db,
         tbl => 'mk_upgrade_right',
      },
      tbl_struct    => $res_struct,
      cols          => $res_struct->{cols},
      chunk_size    => 1_000,
      RowDiff       => $rd,
      ChangeHandler => $ch,
   );

   if ( $n_diff < $max_diff ) {
      $same_row->() if $l_r[LEFT] || $l_r[RIGHT];  # save remaining rows
   }

   $self->_use_db($left_dbh,  $orig_left_db);
   $self->_use_db($right_dbh, $orig_right_db);

   return @different_rows;
}

sub write_to_outfile {
   my ( $self, %args ) = @_;
   my @required_args = qw(side row sth Outfile);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ( $side, $row, $sth, $outfile ) = @args{@required_args};
   my ( $fh, $file ) = $self->open_outfile(%args);

   $outfile->write($fh, [ MockSyncStream::as_arrayref($sth, $row) ]);

   my $remaining_rows = $sth->fetchall_arrayref();
   $outfile->write($fh, $remaining_rows);

   my $n_rows = 1 + @$remaining_rows;
   MKDEBUG && _d('Wrote', $n_rows, 'rows');

   close $fh or warn "Cannot close $file: $OS_ERROR";
   return $file, $n_rows;
}

sub open_outfile {
   my ( $self, %args ) = @_;
   my $outfile = $self->{'base-dir'} . "/$args{side}-outfile.txt";
   open my $fh, '>', $outfile or die "Cannot open $outfile: $OS_ERROR";
   MKDEBUG && _d('Opened outfile', $outfile);
   return $fh, $outfile;
}

sub make_table_ddl {
   my ( $self, $struct ) = @_;
   my $sql = "(\n"
           . (join("\n",
                 map {
                    my $name = $_;
                    my $type = $struct->{type_for}->{$_};
                    my $size = $struct->{size}->{$_} || '';
                    "  `$name` $type$size,";
                 } @{$struct->{cols}}))
           . ')';
   $sql =~ s/,\)$/\n)/;
   MKDEBUG && _d('Table ddl:', $sql);
   return $sql;
}

sub add_indexes {
   my ( $self, %args ) = @_;
   my @required_args = qw(query dsts db);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($query, $dsts) = @args{@required_args};

   my $qp = $self->{QueryParser};
   my $tp = $self->{TableParser};
   my $q  = $self->{Quoter};
   my $du = $self->{MySQLDump};

   my @src_tbls = $qp->get_tables($query);
   my @keys;
   foreach my $db_tbl ( @src_tbls ) {
      my ($db, $tbl) = $q->split_unquote($db_tbl, $args{db});
      if ( $db ) {
         my $tbl_struct;
         eval {
            $tbl_struct = $tp->parse(
               $du->get_create_table($dsts->[0]->{dbh}, $q, $db, $tbl)
            );
         };
         if ( $EVAL_ERROR ) {
            MKDEBUG && _d('Error parsing', $db, '.', $tbl, ':', $EVAL_ERROR);
            next;
         }
         push @keys, map {
            my $def = ($_->{is_unique} ? 'UNIQUE ' : '')
                    . "KEY ($_->{colnames})";
            [$def, $_];
         } grep { $_->{type} eq 'BTREE' } values %{$tbl_struct->{keys}};
      }
      else {
         MKDEBUG && _d('Cannot get indexes from', $db_tbl, 'because its '
            . 'database is unknown');
      }
   }
   MKDEBUG && _d('Source keys:', Dumper(\@keys));
   return unless @keys;

   for my $dst ( @$dsts ) {
      foreach my $key ( @keys ) {
         my $def = $key->[0];
         my $sql = "ALTER TABLE $dst->{tbl} ADD $key->[0]";
         MKDEBUG && _d($sql);
         eval {
            $dst->{dbh}->do($sql);
         };
         if ( $EVAL_ERROR ) {
            MKDEBUG && _d($EVAL_ERROR);
         }
         else {
         }
      }
   }

   return;
}

sub report {
   my ( $self, %args ) = @_;
   my @required_args = qw(hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($hosts) = @args{@required_args};

   return unless keys %{$self->{diffs}};

   my $query_id_col = {
      name        => 'Query ID',
   };
   my @host_cols = map {
      my $col = { name => $_->{name} };
      $col;
   } @$hosts;

   my @reports;
   foreach my $diff ( qw(checksums col_vals row_counts) ) {
      my $report = "_report_diff_$diff";
      push @reports, $self->$report(
         query_id_col => $query_id_col,
         host_cols    => \@host_cols,
         %args
      );
   }

   return join("\n", @reports);
}

sub _report_diff_checksums {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col host_cols);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{checksums}};

   my $report = new ReportFormatter();
   $report->set_title('Checksum differences');
   $report->set_columns(
      $args{query_id_col},
      @{$args{host_cols}},
   );

   my $diff_checksums = $self->{diffs}->{checksums};
   foreach my $item ( sort keys %$diff_checksums ) {
      map {
         $report->add_line(
            $get_id->($item) . '-' . $_,
            @{$diff_checksums->{$item}->{$_}},
         );
      } sort { $a <=> $b } keys %{$diff_checksums->{$item}};
   }

   return $report->get_report();
}

sub _report_diff_col_vals {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col host_cols);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{col_vals}};

   my $report = new ReportFormatter();
   $report->set_title('Column value differences');
   $report->set_columns(
      $args{query_id_col},
      {
         name => 'Column'
      },
      @{$args{host_cols}},
   );
   my $diff_col_vals = $self->{diffs}->{col_vals};
   foreach my $item ( sort keys %$diff_col_vals ) {
      foreach my $sampleno (sort {$a <=> $b} keys %{$diff_col_vals->{$item}}) {
         map {
            $report->add_line(
               $get_id->($item) . '-' . $sampleno,
               @$_,
            );
         } @{$diff_col_vals->{$item}->{$sampleno}};
      }
   }

   return $report->get_report();
}

sub _report_diff_row_counts {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{row_counts}};

   my $report = new ReportFormatter();
   $report->set_title('Row count differences');
   $report->set_columns(
      $args{query_id_col},
      map {
         my $col = { name => $_->{name}, right_justify => 1  };
         $col;
      } @{$args{hosts}},
   );

   my $diff_row_counts = $self->{diffs}->{row_counts};
   foreach my $item ( sort keys %$diff_row_counts ) {
      map {
         $report->add_line(
            $get_id->($item) . '-' . $_,
            @{$diff_row_counts->{$item}->{$_}},
         );
      } sort { $a <=> $b } keys %{$diff_row_counts->{$item}};
   }

   return $report->get_report();
}

sub samples {
   my ( $self, $item ) = @_;
   return unless $item;
   my @samples;
   foreach my $sampleno ( keys %{$self->{samples}->{$item}} ) {
      push @samples, $sampleno, $self->{samples}->{$item}->{$sampleno};
   }
   return @samples;
}

sub reset {
   my ( $self ) = @_;
   $self->{diffs}   = {};
   $self->{samples} = {};
   return;
}

sub _use_db {
   my ( $self, $dbh, $new_db ) = @_;
   return unless $new_db;
   my $sql = 'SELECT DATABASE()';
   MKDEBUG && _d($sql);
   my $curr = $dbh->selectrow_array($sql);
   if ( $curr && $new_db && $curr eq $new_db ) {
      MKDEBUG && _d('Current and new DB are the same');
      return $curr;
   }
   $sql = "USE `$new_db`";
   MKDEBUG && _d($sql);
   $dbh->do($sql);
   return $curr;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End CompareResults package
# ###########################################################################

# ###########################################################################
# CompareQueryTimes package 6785
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/CompareQueryTimes.pm
#   trunk/common/t/CompareQueryTimes.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package CompareQueryTimes;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

Transformers->import(qw(micro_t));
use POSIX qw(floor);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my @bucket_threshold = qw(500 100  100   500 50   50    20 1   );

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(get_id);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
      diffs   => {},
      samples => {},
   };
   return bless $self, $class;
}

sub before_execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   return $args{event};
}

sub execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $dbh) = @args{@required_args};

   if ( exists $event->{Query_time} ) {
      MKDEBUG && _d('Query already executed');
      return $event;
   }

   MKDEBUG && _d('Executing query');
   my $query = $event->{arg};
   my ( $start, $end, $query_time );

   $event->{Query_time} = 0;
   eval {
      $start = time();
      $dbh->do($query);
      $end   = time();
      $query_time = sprintf '%.6f', $end - $start;
   };
   die "Failed to execute query: $EVAL_ERROR" if $EVAL_ERROR;

   $event->{Query_time} = $query_time;

   return $event;
}

sub after_execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   return $args{event};
}

sub compare {
   my ( $self, %args ) = @_;
   my @required_args = qw(events);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($events) = @args{@required_args};

   my $different_query_times = 0;

   my $event0   = $events->[0];
   my $item     = $event0->{fingerprint} || $event0->{arg};
   my $sampleno = $event0->{sampleno}    || 0;
   my $t0       = $event0->{Query_time}  || 0;
   my $b0       = bucket_for($t0);

   my $n_events = scalar @$events;
   foreach my $i ( 1..($n_events-1) ) {
      my $event = $events->[$i];
      my $t     = $event->{Query_time};
      my $b     = bucket_for($t);

      if ( $b0 != $b ) {
         my $diff = abs($t0 - $t);
         $different_query_times++;
         $self->{diffs}->{big}->{$item}->{$sampleno}
            = [ micro_t($t0), micro_t($t), micro_t($diff) ];
         $self->{samples}->{$item}->{$sampleno} = $event0->{arg};
      }
      else {
         my $inc = percentage_increase($t0, $t);
         if ( $inc >= $bucket_threshold[$b0] ) {
            $different_query_times++;
            $self->{diffs}->{in_bucket}->{$item}->{$sampleno}
               = [ micro_t($t0), micro_t($t), $inc, $bucket_threshold[$b0] ];
            $self->{samples}->{$item}->{$sampleno} = $event0->{arg};
         }
      }
   }

   return (
      different_query_times => $different_query_times,
   );
}

sub bucket_for {
   my ( $val ) = @_;
   die "I need a val" unless defined $val;
   return 0 if $val == 0;
   my $bucket = floor(log($val) / log(10)) + 6;
   $bucket = $bucket > 7 ? 7 : $bucket < 0 ? 0 : $bucket;
   return $bucket;
}

sub percentage_increase {
   my ( $x, $y ) = @_;
   return 0 if $x == $y;

   if ( $x > $y ) {
      my $z = $y;
         $y = $x;
         $x = $z;
   }

   if ( $x == 0 ) {
      return 1000;  # This should trigger all buckets' thresholds.
   }

   return sprintf '%.2f', (($y - $x) / $x) * 100;
}


sub report {
   my ( $self, %args ) = @_;
   my @required_args = qw(hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($hosts) = @args{@required_args};

   return unless keys %{$self->{diffs}};

   my $query_id_col = {
      name        => 'Query ID',
   };
   my @host_cols = map {
      my $col = { name => $_->{name} };
      $col;
   } @$hosts;

   my @reports;
   foreach my $diff ( qw(big in_bucket) ) {
      my $report = "_report_diff_$diff";
      push @reports, $self->$report(
         query_id_col => $query_id_col,
         host_cols    => \@host_cols,
         %args
      );
   }

   return join("\n", @reports);
}

sub _report_diff_big {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{big}};

   my $report = new ReportFormatter();
   $report->set_title('Big query time differences');
   $report->set_columns(
      $args{query_id_col},
      map {
         my $col = { name => $_->{name}, right_justify => 1  };
         $col;
      } @{$args{hosts}},
      { name => 'Difference', right_justify => 1 },
   );

   my $diff_big = $self->{diffs}->{big};
   foreach my $item ( sort keys %$diff_big ) {
      map {
         $report->add_line(
            $get_id->($item) . '-' . $_,
            @{$diff_big->{$item}->{$_}},
         );
      } sort { $a <=> $b } keys %{$diff_big->{$item}};
   }

   return $report->get_report();
}

sub _report_diff_in_bucket {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{in_bucket}};

   my $report = new ReportFormatter();
   $report->set_title('Significant query time differences');
   $report->set_columns(
      $args{query_id_col},
      map {
         my $col = { name => $_->{name}, right_justify => 1  };
         $col;
      } @{$args{hosts}},
      { name => '%Increase',  right_justify => 1 },
      { name => '%Threshold', right_justify => 1 },
   );

   my $diff_in_bucket = $self->{diffs}->{in_bucket};
   foreach my $item ( sort keys %$diff_in_bucket ) {
      map {
         $report->add_line(
            $get_id->($item) . '-' . $_,
            @{$diff_in_bucket->{$item}->{$_}},
         );
      } sort { $a <=> $b } keys %{$diff_in_bucket->{$item}};
   }

   return $report->get_report();
}

sub samples {
   my ( $self, $item ) = @_;
   return unless $item;
   my @samples;
   foreach my $sampleno ( keys %{$self->{samples}->{$item}} ) {
      push @samples, $sampleno, $self->{samples}->{$item}->{$sampleno};
   }
   return @samples;
}


sub reset {
   my ( $self ) = @_;
   $self->{diffs}   = {};
   $self->{samples} = {};
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End CompareQueryTimes package
# ###########################################################################

# ###########################################################################
# CompareWarnings package 7096
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/CompareWarnings.pm
#   trunk/common/t/CompareWarnings.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package CompareWarnings;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(get_id Quoter QueryParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
      diffs   => {},
      samples => {},
   };
   return bless $self, $class;
}

sub before_execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $dbh) = @args{@required_args};
   my $sql;

   return $event unless $self->{'clear-warnings'};

   if ( my $tbl = $self->{'clear-warnings-table'} ) {
      $sql = "SELECT * FROM $tbl LIMIT 1";
      MKDEBUG && _d($sql);
      eval {
         $dbh->do($sql);
      };
      die "Failed to SELECT from clear warnings table: $EVAL_ERROR"
         if $EVAL_ERROR;
   }
   else {
      my $q    = $self->{Quoter};
      my $qp   = $self->{QueryParser};
      my @tbls = $qp->get_tables($event->{arg});
      my $ok   = 0;
      TABLE:
      foreach my $tbl ( @tbls ) {
         $sql = "SELECT * FROM $tbl LIMIT 1";
         MKDEBUG && _d($sql);
         eval {
            $dbh->do($sql);
         };
         if ( $EVAL_ERROR ) {
            MKDEBUG && _d('Failed to clear warnings');
         }
         else {
            MKDEBUG && _d('Cleared warnings');
            $ok = 1;
            last TABLE;
         }
      }
      die "Failed to clear warnings"
         unless $ok;
   }

   return $event;
}

sub execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $dbh) = @args{@required_args};

   if ( exists $event->{Query_time} ) {
      MKDEBUG && _d('Query already executed');
      return $event;
   }

   MKDEBUG && _d('Executing query');
   my $query = $event->{arg};
   my ( $start, $end, $query_time );

   $event->{Query_time} = 0;
   eval {
      $start = time();
      $dbh->do($query);
      $end   = time();
      $query_time = sprintf '%.6f', $end - $start;
   };
   die "Failed to execute query: $EVAL_ERROR" if $EVAL_ERROR;

   $event->{Query_time} = $query_time;

   return $event;
}

sub after_execute {
   my ( $self, %args ) = @_;
   my @required_args = qw(event dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($event, $dbh) = @args{@required_args};

   my $warnings;
   my $warning_count;
   eval {
      $warnings      = $dbh->selectall_hashref('SHOW WARNINGS', 'Code');
      $warning_count = $dbh->selectcol_arrayref('SELECT @@warning_count')->[0];
   };
   die "Failed to SHOW WARNINGS: $EVAL_ERROR"
      if $EVAL_ERROR;

   map {
      $_->{Message} =~ s/Out of range value adjusted/Out of range value/;
   } values %$warnings;
   $event->{warning_count} = $warning_count || 0;
   $event->{warnings}      = $warnings;

   return $event;
}

sub compare {
   my ( $self, %args ) = @_;
   my @required_args = qw(events);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($events) = @args{@required_args};

   my $different_warning_counts = 0;
   my $different_warnings       = 0;
   my $different_warning_levels = 0;

   my $event0   = $events->[0];
   my $item     = $event0->{fingerprint} || $event0->{arg};
   my $sampleno = $event0->{sampleno} || 0;
   my $w0       = $event0->{warnings};

   my $n_events = scalar @$events;
   foreach my $i ( 1..($n_events-1) ) {
      my $event = $events->[$i];

      if ( ($event0->{warning_count} || 0) != ($event->{warning_count} || 0) ) {
         MKDEBUG && _d('Warning counts differ:',
            $event0->{warning_count}, $event->{warning_count});
         $different_warning_counts++;
         $self->{diffs}->{warning_counts}->{$item}->{$sampleno}
            = [ $event0->{warning_count} || 0, $event->{warning_count} || 0 ];
         $self->{samples}->{$item}->{$sampleno} = $event0->{arg};
      }

      my $w = $event->{warnings};

      next if !$w0 && !$w;

      my %new_warnings;
      foreach my $code ( keys %$w0 ) {
         if ( exists $w->{$code} ) {
            if ( $w->{$code}->{Level} ne $w0->{$code}->{Level} ) {
               MKDEBUG && _d('Warning levels differ:',
                  $w0->{$code}->{Level}, $w->{$code}->{Level});
               $different_warning_levels++;
               $self->{diffs}->{levels}->{$item}->{$sampleno}
                  = [ $code, $w0->{$code}->{Level}, $w->{$code}->{Level},
                      $w->{$code}->{Message} ];
               $self->{samples}->{$item}->{$sampleno} = $event0->{arg};
            }
            delete $w->{$code};
         }
         else {
            MKDEBUG && _d('Warning gone:', $w0->{$code}->{Message});
            $different_warnings++;
            $self->{diffs}->{warnings}->{$item}->{$sampleno}
               = [ 0, $code, $w0->{$code}->{Message} ];
            $self->{samples}->{$item}->{$sampleno} = $event0->{arg};
         }
      }

      foreach my $code ( keys %$w ) {
         MKDEBUG && _d('Warning new:', $w->{$code}->{Message});
         $different_warnings++;
         $self->{diffs}->{warnings}->{$item}->{$sampleno}
            = [ $i, $code, $w->{$code}->{Message} ];
         $self->{samples}->{$item}->{$sampleno} = $event0->{arg};
      }

      delete $event->{warnings};
   }
   delete $event0->{warnings};

   return (
      different_warning_counts => $different_warning_counts,
      different_warnings       => $different_warnings,
      different_warning_levels => $different_warning_levels,
   );
}

sub report {
   my ( $self, %args ) = @_;
   my @required_args = qw(hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($hosts) = @args{@required_args};

   return unless keys %{$self->{diffs}};

   my $query_id_col = {
      name        => 'Query ID',
   };
   my @host_cols = map {
      my $col = { name => $_->{name} };
      $col;
   } @$hosts;

   my @reports;
   foreach my $diff ( qw(warnings levels warning_counts) ) {
      my $report = "_report_diff_$diff";
      push @reports, $self->$report(
         query_id_col => $query_id_col,
         host_cols    => \@host_cols,
         %args
      );
   }

   return join("\n", @reports);
}

sub _report_diff_warnings {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{warnings}};

   my $report = new ReportFormatter(extend_right => 1);
   $report->set_title('New warnings');
   $report->set_columns(
      $args{query_id_col},
      { name => 'Host', },
      { name => 'Code', right_justify => 1 },
      { name => 'Message' },
   );

   my $diff_warnings = $self->{diffs}->{warnings};
   foreach my $item ( sort keys %$diff_warnings ) {
      map {
         my ($hostno, $code, $message) = @{$diff_warnings->{$item}->{$_}};
         $report->add_line(
            $get_id->($item) . '-' . $_,
            $args{hosts}->[$hostno]->{name}, $code, $message,
         );
      } sort { $a <=> $b } keys %{$diff_warnings->{$item}};
   }

   return $report->get_report();
}

sub _report_diff_levels {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{levels}};

   my $report = new ReportFormatter(extend_right => 1);
   $report->set_title('Warning level differences');
   $report->set_columns(
      $args{query_id_col},
      { name => 'Code', right_justify => 1 },
      map {
         my $col = { name => $_->{name}, right_justify => 1  };
         $col;
      } @{$args{hosts}},
      { name => 'Message' },
   );

   my $diff_levels = $self->{diffs}->{levels};
   foreach my $item ( sort keys %$diff_levels ) {
      map {
         $report->add_line(
            $get_id->($item) . '-' . $_,
            @{$diff_levels->{$item}->{$_}},
         );
      } sort { $a <=> $b } keys %{$diff_levels->{$item}};
   }

   return $report->get_report();
}

sub _report_diff_warning_counts {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id_col hosts);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $get_id = $self->{get_id};

   return unless keys %{$self->{diffs}->{warning_counts}};

   my $report = new ReportFormatter();
   $report->set_title('Warning count differences');
   $report->set_columns(
      $args{query_id_col},
      map {
         my $col = { name => $_->{name}, right_justify => 1  };
         $col;
      } @{$args{hosts}},
   );

   my $diff_warning_counts = $self->{diffs}->{warning_counts};
   foreach my $item ( sort keys %$diff_warning_counts ) {
      map {
         $report->add_line(
            $get_id->($item) . '-' . $_,
            @{$diff_warning_counts->{$item}->{$_}},
         );
      } sort { $a <=> $b } keys %{$diff_warning_counts->{$item}};
   }

   return $report->get_report();
}

sub samples {
   my ( $self, $item ) = @_;
   return unless $item;
   my @samples;
   foreach my $sampleno ( keys %{$self->{samples}->{$item}} ) {
      push @samples, $sampleno, $self->{samples}->{$item}->{$sampleno};
   }
   return @samples;
}

sub reset {
   my ( $self ) = @_;
   $self->{diffs}   = {};
   $self->{samples} = {};
   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End CompareWarnings package
# ###########################################################################

# ###########################################################################
# Retry package 7473
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Retry.pm
#   trunk/common/t/Retry.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package Retry;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      %args,
   };
   return bless $self, $class;
}

sub retry {
   my ( $self, %args ) = @_;
   my @required_args = qw(try wait);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   };
   my ($try, $wait) = @args{@required_args};
   my $tries = $args{tries} || 3;

   my $tryno = 0;
   while ( ++$tryno <= $tries ) {
      MKDEBUG && _d("Retry", $tryno, "of", $tries);
      my $result;
      eval {
         $result = $try->(tryno=>$tryno);
      };

      if ( defined $result ) {
         MKDEBUG && _d("Try code succeeded");
         if ( my $on_success = $args{on_success} ) {
            MKDEBUG && _d("Calling on_success code");
            $on_success->(tryno=>$tryno, result=>$result);
         }
         return $result;
      }

      if ( $EVAL_ERROR ) {
         MKDEBUG && _d("Try code died:", $EVAL_ERROR);
         die $EVAL_ERROR unless $args{retry_on_die};
      }

      if ( $tryno < $tries ) {
         MKDEBUG && _d("Try code failed, calling wait code");
         $wait->(tryno=>$tryno);
      }
   }

   MKDEBUG && _d("Try code did not succeed");
   if ( my $on_failure = $args{on_failure} ) {
      MKDEBUG && _d("Calling on_failure code");
      $on_failure->();
   }

   return;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

1;

# ###########################################################################
# End Retry package
# ###########################################################################

# ###########################################################################
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_upgrade;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

Transformers->import(qw(make_checksum));

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use sigtrap 'handler', \&sig_int, 'normal-signals';

# Global variables.  Only really essential variables should be here.
my $oktorun = 1;

sub main {
   @ARGV = @_;  # set global ARGV for this package

   # ##########################################################################
   # Get configuration information.
   # ##########################################################################
   my $o  = new OptionParser();
   $o->get_specs();
   $o->get_opts();

   my $dp = $o->DSNParser();
   $dp->prop('set-vars', $o->get('set-vars'));

   if ( !$o->get('help') ) {
      if ( @ARGV < 1 ) {
         $o->save_error('Specify at least one host DSN');
      }
      if ( my $compare_method = $o->get('compare-results-method') ) {
         my %valid_method = qw(checksum 1 rows 1);
         $o->save_error("Invalid --compare-results-method: $compare_method")
            unless $valid_method{lc $compare_method};
      }
   }

   my @files;
   my $hosts        = [];
   my $dsn_defaults = $dp->parse_options($o);
   while ( my $arg = shift @ARGV ) {
      if ( !-f $arg ) {
         MKDEBUG && _d($arg, 'is a DSN');
         my $dsn = $dp->parse(
            $arg,
            ($hosts->[-1] ? $hosts->[-1]->{dsn} : undef),
            $dsn_defaults
         );
         push @$hosts, { dsn  => $dsn, };
      }
      else {
         MKDEBUG && _d($arg, 'is a file');
         push @files, $arg;
      }
   }
   if ( @files == 0 ) {
      push @files, '-'; # Magical STDIN filename.
   }

   if ( @$hosts == 0 ) {
      $o->save_error('Specify at least one host DSN');
   }

   $o->usage_or_errors();

   if ( $o->get('explain-hosts') ) {
      foreach my $host ( @$hosts ) {
         print "# DSN: ", $dp->as_string($host->{dsn}), "\n";
      }
      return 0;
   }

   # ########################################################################
   # Connect to the hosts.
   # ########################################################################
   foreach my $host ( @$hosts ) {
      $host->{dbh} = get_cxn($dp, $o, $host->{dsn});
      $dp->fill_in_dsn($host->{dbh}, $host->{dsn});
      my $name       = $host->{dsn}->{h} || $host->{dsn}->{F};
      $name         .= ":$host->{dsn}->{P}" if $host && $host->{dsn}->{P};
      $host->{name}  = $name || 'unknown host';
   }

   # ########################################################################
   # Make some common modules.
   # ########################################################################
   my $q        = new Quoter();
   my $vp       = new VersionParser();
   my $qp       = new QueryParser();
   my $qr       = new QueryRewriter();
   my $du       = new MySQLDump(cache => 0);
   my $rr       = new Retry();
   my $tp       = new TableParser(Quoter => $q);
   my $chunker  = new TableChunker(Quoter => $q, MySQLDump => $du );
   my $nibbler  = new TableNibbler(Quoter => $q, TableParser => $tp );
   my $checksum = new TableChecksum(Quoter => $q, VersionParser => $vp);
   my $syncer   = new TableSyncer(
      MasterSlave   => 1,  # I don't think we need this.
      Quoter        => $q,
      VersionParser => $vp,
      TableChecksum => $checksum,
      Retry         => $rr,
   );
   my %common_modules  = (
      DSNParser     => $dp,
      OptionParser  => $o,
      QueryParser   => $qp,
      QueryRewriter => $qr,
      MySQLDump     => $du,
      TableParser   => $tp,
      Quoter        => $q,
      VersionParser => $vp,
      TableChunker  => $chunker,
      TableNibbler  => $nibbler,
      TableChecksum => $checksum,
      TableSyncer   => $syncer,
   );

   # ########################################################################
   # Make compare modules in order.
   # ########################################################################
   my $compare = $o->get('compare');
   my @compare_modules;
   if ( $compare->{results} ) {
      my $method  = lc $o->get('compare-results-method');
      MKDEBUG && _d('Compare results method:', $method);

      my $plugins = [];
      if ( $method eq 'rows' ) {
         push @$plugins, new TableSyncChunk(%common_modules);
         push @$plugins, new TableSyncNibble(%common_modules);
         push @$plugins, new TableSyncGroupBy(%common_modules);
      }

      push @compare_modules, new CompareResults(
         method     => $method,
         plugins    => $plugins,
         get_id     => sub { return make_checksum(@_); },
         'base-dir' => $o->get('base-dir'),
         %common_modules,
      );
   }

   if ( $compare->{query_times} ) {
      push @compare_modules, new CompareQueryTimes(
         get_id     => sub { return make_checksum(@_); },
         %common_modules,
      );
   }

   if ( $compare->{warnings} ) {
      # SHOW WARNINGS requires MySQL 4.1.
      my $have_warnings = 1;
      foreach my $host ( @$hosts ) {
         if ( !$vp->version_ge($host->{dbh}, '4.1.0') ) {
            warn "Compare warnings DISABLED because host ", $host->{name},
               " MySQL version is less than 4.1";
            $have_warnings = 0;
            last;
         }
      }
      if ( $have_warnings ) {
         push @compare_modules, new CompareWarnings(
            'clear-warnings'       => $o->get('clear-warnings'),
            'clear-warnings-table' => $o->get('clear-warnings-table'),
            get_id => sub { return make_checksum(@_); },
            %common_modules,
         );
      }
   }

   # ########################################################################
   # Make an EventAggregator for each host and a "meta-aggregator" for all.
   # ########################################################################
   my $groupby = 'fingerprint';
   map {
      my $ea = new EventAggregator(
         groupby => 'fingerprint',
         worst   => 'Query_time',
      );
      $_->{ea} = $ea;
   } @$hosts;

   my $meta_ea = new  EventAggregator(
      groupby => 'fingerprint',
      worst   => 'differences'
   );

   # ########################################################################
   # Create the event pipeline.
   # ########################################################################
   my @callbacks;
   my $stats  = {};
   my $errors = {};
   my $current_db;
   my $tmp_db  = $o->get('temp-database');
   my $tmp_tbl = $o->get('temp-table');

   if ( my $query = $o->get('query') ) {
      push @callbacks, sub {
         my ( $event, %args ) = @_;
         MKDEBUG && _d('callback: query:', $query);
         $args{oktorun}->(0) if $args{oktorun};
         return {
            cmd        => 'Query',
            arg        => $query,
            pos_in_log => 0,  # for compatibility
         };
      };
   }
   else {
      my $parser = new SlowLogParser();
      push @callbacks, sub {
         my ( $event, %args ) = @_;
         return $parser->parse_event(%args);
      };
   }

   push @callbacks, sub {
      my ( $event ) = @_;
      MKDEBUG && _d('callback: check cmd and arg');
      $stats->{events}++;
      if ( ($event->{cmd} || '') ne 'Query' ) {
         MKDEBUG && _d('Skipping non-Query cmd');
         $stats->{not_query}++;
         return;
      }
      if ( !$event->{arg} ) {
         MKDEBUG && _d('Skipping empty arg');
         $stats->{empty_query}++;
         return;
      }
      return $event;
   };

   # User-defined filter.
   if ( $o->get('filter') ) {
      my $filter = $o->get('filter');
      if ( -f $filter && -r $filter ) {
         MKDEBUG && _d('Reading file', $filter, 'for --filter code');
         open my $fh, "<", $filter or die "Cannot open $filter: $OS_ERROR";
         $filter = do { local $/ = undef; <$fh> };
         close $fh;
      }
      else {
         $filter = "( $filter )";  # issue 565
      }
      my $code   = "sub { MKDEBUG && _d('callback: filter');  my(\$event) = shift; $filter && return \$event; };";
      MKDEBUG && _d('--filter code:', $code);
      my $sub = eval $code
         or die "Error compiling --filter code: $code\n$EVAL_ERROR";
      push @callbacks, $sub;
   }

   if ( $o->get('convert-to-select') ) {
      push @callbacks, sub {
         my ( $event ) = @_;
         MKDEBUG && _d('callback: convert to select');
         return $event if $event->{arg} =~ m/(?:^SELECT|(?:\*\/\s*SELECT))/i;
         my $new_arg = $qr->convert_to_select($event->{arg});
         if ( $new_arg =~ m/^SELECT/i ) {
            $stats->{convert_to_select_ok}++;
            $event->{original_arg} = $event->{arg};
            $event->{arg}          = $new_arg;
            return $event;
         }
         MKDEBUG && _d('Convert to SELECT failed:', $event->{arg});
         $stats->{convert_to_select_failed}++;
         return;
      };
   }
   else {
      push @callbacks, sub {
         my ( $event ) = @_;
         MKDEBUG && _d('callback: filter non-select');
         if ( $event->{arg} !~ m/(?:^SELECT|(?:\*\/\s*SELECT))/i ) {
            MKDEBUG && _d('Skipping non-SELECT query');
            $stats->{not_select}++;
            return;
         }
         return $event;
      };
   }

   # Do this callback before the fingerprint and sampleno attribs are added.
   my %allowed_attribs = qw(arg 1 db 1 sampleno 1 pos_in_log 1 original_arg 1);
   push @callbacks, sub {
      my ( $event ) = @_;
      MKDEBUG && _d('callback: remove not-allowed attributes');
      # Events will have a lot of attribs from the log that we want
      # to remove because 1) we don't need them and 2) we want to avoid
      # attrib conflicts (e.g. there's probably a Query_time from the
      # log but the compare modules add a Query_time attrib, too).
      map { delete $event->{$_} unless $allowed_attribs{$_} } keys %$event;
      return $event;
   };

   push @callbacks, sub {
      my ( $event ) = @_;
      MKDEBUG && _d('callback: fingerprint');
      $event->{fingerprint} = $qr->fingerprint($event->{arg});
      return $event;
   };

   my %samples;
   my %samplenos;
   push @callbacks, sub {
      my ( $event ) = @_;
      MKDEBUG && _d('callback: sampleno');
      $event->{sampleno} = ++$samplenos{$event->{$groupby}};
      MKDEBUG && _d('Event sampleno', $event->{sampleno});
      return $event;
   };

   # Keep the default database update-to-date.  This helps when queries
   # don't use db-qualified tables.
   push @callbacks, sub {
      my ( $event ) = @_;
      MKDEBUG && _d('callback: current db');
      my $db = $event->{db} || $event->{Schema} || $hosts->[0]->{dsn}->{D};
      if ( $db && (!$current_db || $db ne $current_db) ) {
         my $sql = "USE `$db`";
         MKDEBUG && _d($sql);
         eval {
            map { $_->{dbh}->do($sql); } @$hosts;
         };
         if ( $EVAL_ERROR ) {
            MKDEBUG && _d('Error:', $EVAL_ERROR);
            $EVAL_ERROR =~ m/Unknown database/ ? $stats->{unknown_database}++
                        :                        $stats->{use_database_error}++;
            return;
         }
         $event->{db} = $current_db = $db;
      }
      $stats->{no_database}++ unless $current_db;
      return $event;
   };

   # ########################################################################
   # Short version: do it!  Long version: this callback does the main work.
   # The big picture is:
   #   [event] -> exec on hosts -> compare -> aggregate -> [meta-event]
   # The single input [event] is duplicated into "host events" which are
   # executed on each host.  Each host event goes through three processing,
   # or "action", steps for each compare module: before_execute, execute,
   # and after_execute.  Each compare module modifies and returns the event.
   # (e.g. CompareResults checksum method adds a checksum attribute).  When
   # all host events are done, they are collectively passed to each compare
   # module which look for differences in the attributes they added.
   # (e.g. CompareResults looks for different checksum attribute values.)
   # The compare modules return difference attributes that this callback
   # aggregates in a meta-event.  The meta-event captures the varying
   # differences for this event across all hosts.  The specific difference
   # details are reported later when report() is called for compare module.
   # ########################################################################
   push @callbacks, sub {
      my ( $event ) = @_;
      MKDEBUG && _d('callback: execute event on hosts');

      my @host_events;
      HOST:
      foreach my $host ( @$hosts ) { 
         my $dbh        = $host->{dbh};
         my $host_name  = $host->{name};
         my $host_event = { %$event };
         my %bad_module;
         $host_event->{Errors} = 'No';
         ACTION:
         foreach my $action ( qw(before_execute execute after_execute) ) {
            MODULE:
            foreach my $c ( @compare_modules ) {
               my $module = ref $c;
               if ( $bad_module{$module} ) {
                  MKDEBUG && _d('Skipping bad module', $module, $action,
                     'on', $host_name);
                  $stats->{"${module}_${action}_skipped"}++;
                  next MODULE;
               }
               MKDEBUG && _d('Doing', $module, $action, 'on', $host_name);
               eval {
                  $host_event = $c->$action(
                     event           => $host_event,
                     dbh             => $dbh,
                     db              => $current_db,
                     'temp-database' => $tmp_db,
                     'temp-table'    => $tmp_tbl,
                  );
               };
               if ( $EVAL_ERROR ) {
                  chomp $EVAL_ERROR;
                  MKDEBUG && _d('Error:', $EVAL_ERROR);
                  $errors->{$event->{fingerprint}}->{$event->{sampleno} || 0}
                     = [$host->{name}, $EVAL_ERROR];
                  $samples{$event->{fingerprint}}->{$event->{sampleno} || 0}
                     = $event->{arg};
                  $host_event->{Errors} = 'Yes';
                  $bad_module{$module}++;
                  $stats->{"${module}_${action}_error"}++;
                  next MODULE;
               }
            } 
         }

         $host_event->{Warnings}
            = $host_event->{warning_count}
              && $host_event->{warning_count} > 0 ? 'Yes' : 'No';

         push @host_events, $host_event;
      }

      # Compare host events for differences, then aggregate those differences.
      my $n_diffs = 0;
      foreach my $c ( @compare_modules ) {
         MKDEBUG && _d('Doing', ref $c, 'compare');
         my %diffs = $c->compare(
            events               => \@host_events,
            hosts                => $hosts,
            'temp-database'      => $tmp_db,
            'temp-table'         => $tmp_tbl,
            'float-precision'    => $o->get('float-precision'),
            'max-different-rows' => $o->get('max-different-rows'),
         );
         @{$event}{keys %diffs} = values %diffs;
         map { $n_diffs += $_ } values %diffs;
      }
      $event->{differences} = $n_diffs;
      $meta_ea->aggregate($event);


      # Per-host aggregates must be done after compare() because
      # some attributes can only be added to the host events during
      # compare(), like row_count for the rows method.
      for my $i ( 0..$#host_events ) {

         # Zero query times.  Do this after compare() but before
         # per-host aggregation so that the modules can compare/use
         # the query times but the per-host aggregated reports will
         # show zeros.
         if ( exists $host_events[$i]->{Query_time}
              && $o->get('zero-query-times') ) {
            $host_events[$i]->{Query_time} = 0;
         }

         $hosts->[$i]->{ea}->aggregate($host_events[$i]);
      }

      return $event;  # the meta-event
   };

   # ########################################################################
   # Daemonize now that everything is setup and ready to work.
   # ########################################################################
   my $daemon;
   if ( $o->get('daemonize') ) {
      $daemon = new Daemon(o=>$o);
      $daemon->daemonize();
      MKDEBUG && _d('I am a daemon now');
   }
   elsif ( $o->get('pid') ) {
      # We're not daemoninzing, it just handles PID stuff.
      $daemon = new Daemon(o=>$o);
      $daemon->make_PID_file();
   }

   # ##########################################################################
   # Parse the input.
   # ##########################################################################
   my $fh;
   my $next_event = sub { return <$fh>; };
   my $tell       = sub { return tell $fh; };
   my $start = time();
   my $end   = $start + ($o->get('run-time') || 0); # When we should exit
   my $now   = $start;
   my $iters = 0;
   ITERATION:
   while (  # Quit if instructed to, or if iterations are exceeded.
      $oktorun
      && (!$o->get('iterations') || $iters++ < $o->get('iterations') )
   ) {

      EVENT:
      while (                                 # Quit if:
         $oktorun                             # instructed to quit
         && ($start == $end || $now < $end) ) # or time is exceeded
      {
         if ( !$fh ) {
            my $file = shift @files;
            if ( !$file ) {
               MKDEBUG && _d('No more files to parse');
               last EVENT;
            }

            if ( $file eq '-' ) {
               $fh = *STDIN;
               MKDEBUG && _d('Reading STDIN');
            }
            else {
               if ( !open $fh, "<", $file ) {
                  $fh = undef;
                  warn "Cannot open $file: $OS_ERROR\n";
                  next EVENT;
               }
               MKDEBUG && _d('Reading', $file);
            }
         }

         my $event       = {};
         my $more_events = 1;
         my $oktorun_sub = sub { $more_events = $_[0]; };
         eval {
            foreach my $callback ( @callbacks ) {
               last unless $oktorun;  # the global oktorun var
               $event = $callback->(
                  $event,
                  event      => $event,  # new interface
                  fh         => $fh,
                  next_event => $next_event,
                  tell       => $tell,
                  oktorun    => $oktorun_sub,
               );
               last unless $event;
            }
         };
         $now = time();
         if ( $EVAL_ERROR ) {
            _d($EVAL_ERROR);
            # Don't ignore failure to open a file, else we'll get
            # "tell() on closed filehandle" errors.
            last EVENT if $EVAL_ERROR =~ m/Cannot open/;
            last EVENT unless $o->get('continue-on-error');
         }
         if ( !$more_events ) {
            MKDEBUG && _d('No more events');
            close $fh if $fh;
            $fh = undef;
            last EVENT;
         }
      }  # EVENT

      # ######################################################################
      # Done parsing events, now do the report.
      # #####################################################################
      if ( !$meta_ea->events_processed() ) {
         print "# No events processed.\n";
      }
      foreach my $host ( @$hosts ) {
         $host->{ea}->calculate_statistical_metrics();
      }

      my $urf = new UpgradeReportFormatter();
      my ($orderby_attrib, $orderby_func) = split(/:/, $o->get('order-by'));

      # We don't report on all queries, just the worst, i.e. the top
      # however many.
      my $limit = $o->get('limit');
      my ($total, $count);
      if ( $limit =~ m/^\d+$/ ) {
         $count = $limit;
      }
      else {
         # It's a percentage, so grab as many as needed to get to
         # that % of the file.
         ($total, $count) = $limit =~ m/(\d+)/g;
         $total *= ($meta_ea->results->{globals}->{$orderby_attrib}->{sum} || 0)
                 / 100;
      }
      my %top_spec = (
         attrib  => $orderby_attrib,
         orderby => $orderby_func,
         total   => $total,
         count   => $count,
      );
      # The queries that will be reported.
      my ($worst, $other) = $meta_ea->top_events(%top_spec);

      # ##################################################################
      # Do the report for each query.
      # ##################################################################
      if ( $o->get('reports')->{queries} ) {
         my $n_worst = scalar @$worst;
         ITEM:
         foreach my $rank ( 1..$n_worst ) {
            my $item       = $worst->[$rank - 1]->[0];
            my $sample     = $meta_ea->results->{samples}->{$item};
            my $samp_query = $sample->{arg} || '';

            print "\n";
            print $urf->event_report(
               meta_ea => $meta_ea,
               hosts   => $hosts,
               where   => $item,
               rank    => $rank,
               worst   => 'differences',
            );

            if ( $sample->{original_arg} ) {
               my $orig = $sample->{original_arg};
               if ( $o->get('shorten') ) {
                  $orig = $qr->shorten($orig, $o->get('shorten'));
               }
               print "# Converted non-SELECT:\n#   $orig\n";
            }
            if ( $o->get('fingerprints') ) {
               print "# Fingerprint\n#   $item\n";
            }
            print "use `$sample->{db}`;\n" if $sample->{db};
            $samp_query = $qr->shorten($samp_query, $o->get('shorten'))
               if $o->get('shorten');
            print "$samp_query\n";

            my $query_id = make_checksum($item);
            foreach my $c ( @compare_modules ) {
               my %compare_samples = $c->samples($item);
               @{$samples{$item}}{keys %compare_samples}
                  = values %compare_samples;
            }
            map {
                  print "/* $query_id-$_ */ $samples{$item}->{$_}\n";
            } sort { $a <=> $b } keys %{$samples{$item}};
         } # Each worst ITEM
      }

      # ##################################################################
      # Print the other, summary-like reports.
      # ##################################################################
      if ( $o->get('reports')->{differences} ) {
         foreach my $c ( @compare_modules ) {
            my $report = $c->report(hosts => $hosts);
            print "\n$report" if $report;
         }
      }

      if ( $o->get('reports')->{errors} ) {
         report_errors(errors => $errors);
      }

      if ( $o->get('reports')->{statistics} ) {
         my $fmt = "# %-30s %d\n";
         print "\n# Statistics\n";
         map { printf $fmt, $_, $stats->{$_} } sort keys %$stats;
      }

      # ##################################################################
      # Reset for the next iteration.
      # ##################################################################

      # Reset the start/end/now times so the next iteration will run for the
      # same amount of time.
      $start = time();
      $end   = $start + ($o->get('run-time') || 0); # When we should exit
      $now   = $start;

      foreach my $ea ( $meta_ea, map { $_->{ea} } @$hosts ) {
         $ea->reset_aggregated_data();
      }
      %samples   = ();
      %samplenos = ();
      $errors    = {};

      foreach my $c ( @compare_modules ) {
         $c->reset();
      }
   } # ITERATION


   foreach my $host ( @$hosts ) {
      $host->{dbh}->disconnect() if $host->{dbh};
   }

   return 0;

} # End main().

# ############################################################################
# Subroutines.
# ############################################################################
sub report_errors {
   my ( %args ) = @_;
   my @required_args = qw(errors);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($errors) = @args{@required_args};

   return unless keys %$errors;

   my $rf = new ReportFormatter(extend_right=>1);
   $rf->set_title('Errors');
   $rf->set_columns(
      { name => 'Query ID' },
      { name => 'Host',    },
      { name => 'Error',   },
   );

   foreach my $item ( sort keys %$errors ) {
      map {
         my ($host, $error) =  @{$errors->{$item}->{$_}};
         chomp $error;
         $rf->add_line(
            make_checksum($item) . '-' . $_,
            $host,
            $error,
         );
      } sort { $a <=> $b } keys %{$errors->{$item}};
   }

   my $report = $rf->get_report();
   print "\n$report" if $report;

   return;
}

sub get_cxn {
   my ( $dp, $o, $dsn ) = @_;
   if ( $o->get('ask-pass') ) {
      $dsn->{p} = OptionParser::prompt_noecho("Enter password: ");
   }
   my $dbh = $dp->get_dbh($dp->get_cxn_params($dsn), {AutoCommit => 1});
   return $dbh;
}

# Catches signals so we can exit gracefully.
sub sig_int {
   my ( $signal ) = @_;
   if ( $oktorun ) {
      print STDERR "# Caught SIG$signal.\n";
      $oktorun = 0;
   }
   else {
      print STDERR "# Exiting on SIG$signal.\n";
      exit 1;
   }
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

# ############################################################################
# Run the program.
# ############################################################################
if ( !caller ) { exit main(@ARGV); }

1; # Because this is a module as well as a script.

# #############################################################################
# Documentation.
# #############################################################################

=pod

=head1 NAME

mk-upgrade - Execute queries on multiple servers and check for differences.

=head1 SYNOPSIS

Usage: mk-upgrade [OPTION...] DSN [DSN...] [FILE]

mk-upgrade compares query execution on two hosts by executing queries in the
given file (or STDIN if no file given) and examining the results, errors,
warnings, etc.produced on each.

Execute and compare all queries in slow.log on host1 to host2:

  mk-upgrade slow.log h=host1 h=host2

Use mk-query-digest to get, execute and compare queries from tcpdump:

  tcpdump -i eth0 port 3306 -s 65535  -x -n -q -tttt     \
    | mk-query-digest --type tcpdump --no-report --print \
    | mk-upgrade h=host1 h=host2

Compare only query times on host1 to host2 and host3:

  mk-upgrade slow.log h=host1 h=host2 h=host3 --compare query_times

Compare a single query, no slowlog needed:

  mk-upgrade h=host1 h=host2 --query 'SELECT * FROM db.tbl'

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

mk-upgrade is a read-only tool that is meant to be used on non-production
servers.  It executes the SQL that you give it as input, which could cause
undesired load on a production server.

At the time of this release, there is a bug that causes the tool to crash,
and a bug that causes a deadlock.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-upgrade>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

mk-upgrade executes queries from slowlogs on one or more MySQL server to find
differences in query time, warnings, results, and other aspects of the querys'
execution.  This helps evaluate upgrades, migrations and configuration
changes.  The comparisons specified by L<"--compare"> determine what
differences can be found.  A report is printed which outlines all the
differences found; see L<"OUTPUT"> below.

The first DSN (host) specified on the command line is authoritative; it defines
the results to which the other DSNs are compared.  You can "compare" only one
host, in which case there will be no differences but the output can be saved
to be diffed later against the output of another single host "comparison".

At present, mk-upgrade only reads slowlogs.  Use C<mk-query-digest --print> to
transform other log formats to slowlog.

DSNs and slowlog files can be specified in any order.  mk-upgrade will
automatically determine if an argument is a DSN or a slowlog file.  If no
slowlog files are given and L<"--query"> is not specified then mk-upgrade
will read from C<STDIN>.

=head1 OUTPUT

TODO

=head1 OPTIONS

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --ask-pass

Prompt for a password when connecting to MySQL.

=item --base-dir

type: string; default: /tmp

Save outfiles for the C<rows> comparison method in this directory.

See the C<rows> L<"--compare-results-method">.

=item --charset

short form: -A; type: string

Default character set.  If the value is utf8, sets Perl's binmode on
STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and
runs SET NAMES UTF8 after connecting to MySQL.  Any other value sets
binmode on STDOUT without the utf8 layer, and runs SET NAMES after
connecting to MySQL.

=item --[no]clear-warnings

default: yes

Clear warnings before each warnings comparison.

If comparing warnings (L<"--compare"> includes C<warnings>), this option
causes mk-upgrade to execute a successful C<SELECT> statement which clears
any warnings left over from previous queries.  This requires a current
database that mk-upgrade usually detects automatically, but in some cases
it might be necessary to specify L<"--temp-database">.  If mk-upgrade can't
auto-detect the current database, it will create a temporary table in the
L<"--temp-database"> called C<mk_upgrade_clear_warnings>.

=item --clear-warnings-table

type: string

Execute C<SELECT * FROM ... LIMIT 1> from this table to clear warnings.

=item --compare

type: Hash; default: query_times,results,warnings

What to compare for each query executed on each host.

Comparisons determine differences when the queries are executed on the hosts.
More comparisons enable more differences to be detected.  The following
comparisons are available:

=over

=item query_times

Compare query execution times.  If this comparison is disabled, the queries
are still executed so that other comparisons will work, but the query time
attributes are removed from the events.

=item results

Compare result sets to find differences in rows, columns, etc.

What differences can be found depends on the L<"--compare-results-method"> used.

=item warnings

Compare warnings from C<SHOW WARNINGS>.  Requires at least MySQL 4.1.

=back

=item --compare-results-method

type: string; default: CHECKSUM; group: Comparisons

Method to use for L<"--compare"> C<results>.  This option has no effect
if C<--no-compare-results> is given.

Available compare methods (case-insensitive):

=over

=item CHECKSUM

Do C<CREATE TEMPORARY TABLE `mk_upgrade` AS query> then
C<CHECKSUM TABLE `mk_upgrade`>.  This method is fast and simple but in
rare cases might it be inaccurate because the MySQL manual says:

  [The] fact that two tables produce the same checksum does I<not> mean that
  the tables are identical.

Requires at least MySQL 4.1.

=item rows

Compare rows one-by-one to find differences.  This method has advantages
and disadvantages.  Its disadvantages are that it may be slower and it
requires writing and reading outfiles from disk.  Its advantages are that
it is universal (works for all versions of MySQL), it doesn't alter the query
in any way, and it can find column value differences.

The C<rows> method works as follows:

  1. Rows from each host are compared one-by-one.
  2. If no differences are found, comparison stops, else...
  3. All remain rows (after the point where they begin to differ)
     are written to outfiles.
  4. The outfiles are loaded into temporary tables with
     C<LOAD DATA LOCAL INFILE>.
  5. The temporary tables are analyzed to determine the differences.

The outfiles are written to the L<"--base-dir">.

=back

=item --config

type: Array

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --continue-on-error

Continue working even if there is an error.

=item --convert-to-select

Convert non-SELECT statements to SELECTs and compare.

By default non-SELECT statements are not allowed.  This option causes
non-SELECT statments (like UPDATE, INSERT and DELETE) to be converted
to SELECT statements, executed and compared.

For example, C<DELETE col FROM tbl WHERE id=1> is converted to
C<SELECT col FROM tbl WHERE id=1>.

=item --daemonize

Fork to the background and detach from the shell.  POSIX
operating systems only.

=item --explain-hosts

Print connection information and exit.

=item --filter

type: string

Discard events for which this Perl code doesn't return true.

This option is a string of Perl code or a file containing Perl code that gets
compiled into a subroutine with one argument: $event.  This is a hashref.
If the given value is a readable file, then mk-upgrade reads the entire
file and uses its contents as the code.  The file should not contain
a shebang (#!/usr/bin/perl) line.

If the code returns true, the chain of callbacks continues; otherwise it ends.
The code is the last statement in the subroutine other than C<return $event>. 
The subroutine template is:

  sub { $event = shift; filter && return $event; }

Filters given on the command line are wrapped inside parentheses like like
C<( filter )>.  For complex, multi-line filters, you must put the code inside
a file so it will not be wrapped inside parentheses.  Either way, the filter
must produce syntactically valid code given the template.  For example, an
if-else branch given on the command line would not be valid:

  --filter 'if () { } else { }'  # WRONG

Since it's given on the command line, the if-else branch would be wrapped inside
parentheses which is not syntactically valid.  So to accomplish something more
complex like this would require putting the code in a file, for example
filter.txt:

  my $event_ok; if (...) { $event_ok=1; } else { $event_ok=0; } $event_ok

Then specify C<--filter filter.txt> to read the code from filter.txt.

If the filter code won't compile, mk-upgrade will die with an error.
If the filter code does compile, an error may still occur at runtime if the
code tries to do something wrong (like pattern match an undefined value).
mk-upgrade does not provide any safeguards so code carefully!

An example filter that discards everything but SELECT statements:

  --filter '$event->{arg} =~ m/^select/i'

This is compiled into a subroutine like the following:

  sub { $event = shift; ( $event->{arg} =~ m/^select/i ) && return $event; }

It is permissible for the code to have side effects (to alter $event).

You can find an explanation of the structure of $event at
L<http://code.google.com/p/maatkit/wiki/EventAttributes>.

=item --fingerprints

Add query fingerprints to the standard query analysis report.  This is mostly
useful for debugging purposes.

=item --float-precision

type: int

Round float, double and decimal values to this many places.

This option helps eliminate false-positives caused by floating-point
imprecision.

=item --help

Show help and exit.

=item --host

short form: -h; type: string

Connect to host.

=item --iterations

type: int; default: 1

How many times to iterate through the collect-and-report cycle.  If 0, iterate
to infinity.  See also L<--run-time>.

=item --limit

type: string; default: 95%:20

Limit output to the given percentage or count.

If the argument is an integer, report only the top N worst queries.  If the
argument is an integer followed by the C<%> sign, report that percentage of the
worst queries.  If the percentage is followed by a colon and another integer,
report the top percentage or the number specified by that integer, whichever
comes first.

=item --log

type: string

Print all output to this file when daemonized.

=item --max-different-rows

type: int; default: 10

Stop comparing rows for C<--compare-results-method rows> after this many
differences are found.

=item --order-by

type: string; default: differences:sum

Sort events by this attribute and aggregate function.

=item --password

short form: -p; type: string

Password to use when connecting.

=item --pid

type: string

Create the given PID file when daemonized.  The file contains the process
ID of the daemonized instance.  The PID file is removed when the
daemonized instance exits.  The program checks for the existence of the
PID file when starting; if it exists and the process with the matching PID
exists, the program exits.

=item --port

short form: -P; type: int

Port number to use for connection.

=item --query

type: string

Execute and compare this single query; ignores files on command line.

This option allows you to supply a single query on the command line.  Any
slowlogs also specified on the command line are ignored.

=item --[no]report

default: yes

Print the L<"--reports">.

=item --reports

type: Hash; default: queries,differences,errors,statistics

Print these reports.  Valid reports are queries, differences, errors, and
statistics.

See L<"OUTPUT"> for more information on the various parts of the report.

=item --run-time

type: time

How long to run before exiting.  The default is to run forever (you can
interrupt with CTRL-C).

=item --set-vars

type: string; default: wait_timeout=10000,query_cache_type=0

Set these MySQL variables.  Immediately after connecting to MySQL, this
string will be appended to SET and executed.

=item --shorten

type: int; default: 1024

Shorten long statements in reports.

Shortens long statements, replacing the omitted portion with a C</*... omitted
...*/> comment.  This applies only to the output in reports.  It prevents a
large statement from causing difficulty in a report.  The argument is the
preferred length of the shortened statement.  Not all statements can be
shortened, but very large INSERT and similar statements often can; and so
can IN() lists, although only the first such list in the statement will be
shortened.

If it shortens something beyond recognition, you can find the original statement
in the log, at the offset shown in the report header (see L<"OUTPUT">).

=item --socket

short form: -S; type: string

Socket file to use for connection.

=item --temp-database

type: string

Use this database for creating temporary tables.

If given, this database is used for creating temporary tables for the
results comparison (see L<"--compare">).  Otherwise, the current
database (from the last event that specified its database) is used.

=item --temp-table

type: string; default: mk_upgrade

Use this table for checksumming results.

=item --user

short form: -u; type: string

User for login if not current user.

=item --version

Show version and exit.

=item --zero-query-times

Zero the query times in the report.

=back

=head1 DSN OPTIONS

These DSN options are used to create a DSN.  Each option is given like
C<option=value>.  The options are case-sensitive, so P and p are not the
same option.  There cannot be whitespace before or after the C<=>, and
if the value contains whitespace it must be quoted.  DSN options are
comma-separated.  See the L<maatkit> manpage for full details.

=over

=item * A

dsn: charset; copy: yes

Default character set.

=item * D

dsn: database; copy: yes

Default database.

=item * F

dsn: mysql_read_default_file; copy: yes

Only read default options from the given file

=item * h

dsn: host; copy: yes

Connect to host.

=item * p

dsn: password; copy: yes

Password to use when connecting.

=item * P

dsn: port; copy: yes

Port number to use for connection.

=item * S

dsn: mysql_socket; copy: yes

Socket file to use for connection.

=item * u

dsn: user; copy: yes

User for login if not current user.

=back

=head1 DOWNLOADING

You can download Maatkit from Google Code at
L<http://code.google.com/p/maatkit/>, or you can get any of the tools
easily with a command like the following:

   wget http://www.maatkit.org/get/toolname
   or
   wget http://www.maatkit.org/trunk/toolname

Where C<toolname> can be replaced with the name (or fragment of a name) of any
of the Maatkit tools.  Once downloaded, they're ready to run; no installation is
needed.  The first URL gets the latest released version of the tool, and the
second gets the latest trunk code from Subversion.

=head1 ENVIRONMENT

The environment variable C<MKDEBUG> enables verbose debugging output in all of
the Maatkit tools:

   MKDEBUG=1 mk-....

=head1 SYSTEM REQUIREMENTS

You need Perl and some core packages that ought to be installed in any
reasonably new version of Perl.

=head1 BUGS

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-upgrade>.

Please use Google Code Issues and Groups to report bugs or request support:
L<http://code.google.com/p/maatkit/>.  You can also join #maatkit on Freenode to
discuss Maatkit.

Please include the complete command-line used to reproduce the problem you are
seeing, the version of all MySQL servers involved, the complete output of the
tool when run with L<"--version">, and if possible, debugging output produced by
running with the C<MKDEBUG=1> environment variable.

=head1 COPYRIGHT, LICENSE AND WARRANTY

This program is copyright 2009-2011 Percona, Inc.
Feedback and improvements are welcome.

THIS PROGRAM IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, version 2; OR the Perl Artistic License.  On UNIX and similar
systems, you can issue `man perlgpl' or `man perlartistic' to read these
licenses.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 59 Temple
Place, Suite 330, Boston, MA  02111-1307  USA.

=head1 AUTHOR

Baron Schwartz, Daniel Nichter

=head1 ABOUT MAATKIT

This tool is part of Maatkit, a toolkit for power users of MySQL.  Maatkit
was created by Baron Schwartz; Baron and Daniel Nichter are the primary
code contributors.  Both are employed by Percona.  Financial support for
Maatkit development is primarily provided by Percona and its clients. 

=head1 VERSION

This manual page documents Ver 0.9.8 Distrib 7540 $Revision: 7531 $.

=cut

__END__
:endofperl
