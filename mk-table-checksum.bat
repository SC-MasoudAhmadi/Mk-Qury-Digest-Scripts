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

# This program checksums MySQL tables efficiently on one or more servers.
#
# This program is copyright 2007-2011 Baron Schwartz.
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

our $VERSION = '1.2.23';
our $DISTRIB = '7540';
our $SVN_REV = sprintf("%d", (q$Revision: 7527 $ =~ m/(\d+)/g, 0));

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
# MasterSlave package 7525
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/MasterSlave.pm
#   trunk/common/t/MasterSlave.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package MasterSlave;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use List::Util qw(min max);
use Data::Dumper;
$Data::Dumper::Quotekeys = 0;
$Data::Dumper::Indent    = 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      %args,
      replication_thread => {},
   };
   return bless $self, $class;
}

sub recurse_to_slaves {
   my ( $self, $args, $level ) = @_;
   $level ||= 0;
   my $dp   = $args->{dsn_parser};
   my $dsn  = $args->{dsn};

   my $dbh;
   eval {
      $dbh = $args->{dbh} || $dp->get_dbh(
         $dp->get_cxn_params($dsn), { AutoCommit => 1 });
      MKDEBUG && _d('Connected to', $dp->as_string($dsn));
   };
   if ( $EVAL_ERROR ) {
      print STDERR "Cannot connect to ", $dp->as_string($dsn), "\n"
         or die "Cannot print: $OS_ERROR";
      return;
   }

   my $sql  = 'SELECT @@SERVER_ID';
   MKDEBUG && _d($sql);
   my ($id) = $dbh->selectrow_array($sql);
   MKDEBUG && _d('Working on server ID', $id);
   my $master_thinks_i_am = $dsn->{server_id};
   if ( !defined $id
       || ( defined $master_thinks_i_am && $master_thinks_i_am != $id )
       || $args->{server_ids_seen}->{$id}++
   ) {
      MKDEBUG && _d('Server ID seen, or not what master said');
      if ( $args->{skip_callback} ) {
         $args->{skip_callback}->($dsn, $dbh, $level, $args->{parent});
      }
      return;
   }

   $args->{callback}->($dsn, $dbh, $level, $args->{parent});

   if ( !defined $args->{recurse} || $level < $args->{recurse} ) {

      my @slaves =
         grep { !$_->{master_id} || $_->{master_id} == $id } # Only my slaves.
         $self->find_slave_hosts($dp, $dbh, $dsn, $args->{method});

      foreach my $slave ( @slaves ) {
         MKDEBUG && _d('Recursing from',
            $dp->as_string($dsn), 'to', $dp->as_string($slave));
         $self->recurse_to_slaves(
            { %$args, dsn => $slave, dbh => undef, parent => $dsn }, $level + 1 );
      }
   }
}

sub find_slave_hosts {
   my ( $self, $dsn_parser, $dbh, $dsn, $method ) = @_;

   my @methods = qw(processlist hosts);
   if ( $method ) {
      @methods = grep { $_ ne $method } @methods;
      unshift @methods, $method;
   }
   else {
      if ( ($dsn->{P} || 3306) != 3306 ) {
         MKDEBUG && _d('Port number is non-standard; using only hosts method');
         @methods = qw(hosts);
      }
   }
   MKDEBUG && _d('Looking for slaves on', $dsn_parser->as_string($dsn),
      'using methods', @methods);

   my @slaves;
   METHOD:
   foreach my $method ( @methods ) {
      my $find_slaves = "_find_slaves_by_$method";
      MKDEBUG && _d('Finding slaves with', $find_slaves);
      @slaves = $self->$find_slaves($dsn_parser, $dbh, $dsn);
      last METHOD if @slaves;
   }

   MKDEBUG && _d('Found', scalar(@slaves), 'slaves');
   return @slaves;
}

sub _find_slaves_by_processlist {
   my ( $self, $dsn_parser, $dbh, $dsn ) = @_;

   my @slaves = map  {
      my $slave        = $dsn_parser->parse("h=$_", $dsn);
      $slave->{source} = 'processlist';
      $slave;
   }
   grep { $_ }
   map  {
      my ( $host ) = $_->{host} =~ m/^([^:]+):/;
      if ( $host eq 'localhost' ) {
         $host = '127.0.0.1'; # Replication never uses sockets.
      }
      $host;
   } $self->get_connected_slaves($dbh);

   return @slaves;
}

sub _find_slaves_by_hosts {
   my ( $self, $dsn_parser, $dbh, $dsn ) = @_;

   my @slaves;
   my $sql = 'SHOW SLAVE HOSTS';
   MKDEBUG && _d($dbh, $sql);
   @slaves = @{$dbh->selectall_arrayref($sql, { Slice => {} })};

   if ( @slaves ) {
      MKDEBUG && _d('Found some SHOW SLAVE HOSTS info');
      @slaves = map {
         my %hash;
         @hash{ map { lc $_ } keys %$_ } = values %$_;
         my $spec = "h=$hash{host},P=$hash{port}"
            . ( $hash{user} ? ",u=$hash{user}" : '')
            . ( $hash{password} ? ",p=$hash{password}" : '');
         my $dsn           = $dsn_parser->parse($spec, $dsn);
         $dsn->{server_id} = $hash{server_id};
         $dsn->{master_id} = $hash{master_id};
         $dsn->{source}    = 'hosts';
         $dsn;
      } @slaves;
   }

   return @slaves;
}

sub get_connected_slaves {
   my ( $self, $dbh ) = @_;

   my $show = "SHOW GRANTS FOR ";
   my $user = 'CURRENT_USER()';
   my $vp   = $self->{VersionParser};
   if ( $vp && !$vp->version_ge($dbh, '4.1.2') ) {
      $user = $dbh->selectrow_arrayref('SELECT USER()')->[0];
      $user =~ s/([^@]+)@(.+)/'$1'\@'$2'/;
   }
   my $sql = $show . $user;
   MKDEBUG && _d($dbh, $sql);

   my $proc;
   eval {
      $proc = grep {
         m/ALL PRIVILEGES.*?\*\.\*|PROCESS/
      } @{$dbh->selectcol_arrayref($sql)};
   };
   if ( $EVAL_ERROR ) {

      if ( $EVAL_ERROR =~ m/no such grant defined for user/ ) {
         MKDEBUG && _d('Retrying SHOW GRANTS without host; error:',
            $EVAL_ERROR);
         ($user) = split('@', $user);
         $sql    = $show . $user;
         MKDEBUG && _d($sql);
         eval {
            $proc = grep {
               m/ALL PRIVILEGES.*?\*\.\*|PROCESS/
            } @{$dbh->selectcol_arrayref($sql)};
         };
      }

      die "Failed to $sql: $EVAL_ERROR" if $EVAL_ERROR;
   }
   if ( !$proc ) {
      die "You do not have the PROCESS privilege";
   }

   $sql = 'SHOW PROCESSLIST';
   MKDEBUG && _d($dbh, $sql);
   grep { $_->{command} =~ m/Binlog Dump/i }
   map  { # Lowercase the column names
      my %hash;
      @hash{ map { lc $_ } keys %$_ } = values %$_;
      \%hash;
   }
   @{$dbh->selectall_arrayref($sql, { Slice => {} })};
}

sub is_master_of {
   my ( $self, $master, $slave ) = @_;
   my $master_status = $self->get_master_status($master)
      or die "The server specified as a master is not a master";
   my $slave_status  = $self->get_slave_status($slave)
      or die "The server specified as a slave is not a slave";
   my @connected     = $self->get_connected_slaves($master)
      or die "The server specified as a master has no connected slaves";
   my (undef, $port) = $master->selectrow_array('SHOW VARIABLES LIKE "port"');

   if ( $port != $slave_status->{master_port} ) {
      die "The slave is connected to $slave_status->{master_port} "
         . "but the master's port is $port";
   }

   if ( !grep { $slave_status->{master_user} eq $_->{user} } @connected ) {
      die "I don't see any slave I/O thread connected with user "
         . $slave_status->{master_user};
   }

   if ( ($slave_status->{slave_io_state} || '')
      eq 'Waiting for master to send event' )
   {
      my ( $master_log_name, $master_log_num )
         = $master_status->{file} =~ m/^(.*?)\.0*([1-9][0-9]*)$/;
      my ( $slave_log_name, $slave_log_num )
         = $slave_status->{master_log_file} =~ m/^(.*?)\.0*([1-9][0-9]*)$/;
      if ( $master_log_name ne $slave_log_name
         || abs($master_log_num - $slave_log_num) > 1 )
      {
         die "The slave thinks it is reading from "
            . "$slave_status->{master_log_file},  but the "
            . "master is writing to $master_status->{file}";
      }
   }
   return 1;
}

sub get_master_dsn {
   my ( $self, $dbh, $dsn, $dsn_parser ) = @_;
   my $master = $self->get_slave_status($dbh) or return undef;
   my $spec   = "h=$master->{master_host},P=$master->{master_port}";
   return       $dsn_parser->parse($spec, $dsn);
}

sub get_slave_status {
   my ( $self, $dbh ) = @_;
   if ( !$self->{not_a_slave}->{$dbh} ) {
      my $sth = $self->{sths}->{$dbh}->{SLAVE_STATUS}
            ||= $dbh->prepare('SHOW SLAVE STATUS');
      MKDEBUG && _d($dbh, 'SHOW SLAVE STATUS');
      $sth->execute();
      my ($ss) = @{$sth->fetchall_arrayref({})};

      if ( $ss && %$ss ) {
         $ss = { map { lc($_) => $ss->{$_} } keys %$ss }; # lowercase the keys
         return $ss;
      }

      MKDEBUG && _d('This server returns nothing for SHOW SLAVE STATUS');
      $self->{not_a_slave}->{$dbh}++;
   }
}

sub get_master_status {
   my ( $self, $dbh ) = @_;

   if ( $self->{not_a_master}->{$dbh} ) {
      MKDEBUG && _d('Server on dbh', $dbh, 'is not a master');
      return;
   }

   my $sth = $self->{sths}->{$dbh}->{MASTER_STATUS}
         ||= $dbh->prepare('SHOW MASTER STATUS');
   MKDEBUG && _d($dbh, 'SHOW MASTER STATUS');
   $sth->execute();
   my ($ms) = @{$sth->fetchall_arrayref({})};
   MKDEBUG && _d(Dumper($ms));

   if ( !$ms || scalar keys %$ms < 2 ) {
      MKDEBUG && _d('Server on dbh', $dbh, 'does not seem to be a master');
      $self->{not_a_master}->{$dbh}++;
   }

  return { map { lc($_) => $ms->{$_} } keys %$ms }; # lowercase the keys
}

sub wait_for_master {
   my ( $self, %args ) = @_;
   my @required_args = qw(master_status slave_dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($master_status, $slave_dbh) = @args{@required_args};
   my $timeout       = $args{timeout} || 60;

   my $result;
   my $waited;
   if ( $master_status ) {
      my $sql = "SELECT MASTER_POS_WAIT('$master_status->{file}', "
              . "$master_status->{position}, $timeout)";
      MKDEBUG && _d($slave_dbh, $sql);
      my $start = time;
      ($result) = $slave_dbh->selectrow_array($sql);

      $waited = time - $start;

      MKDEBUG && _d('Result of waiting:', $result);
      MKDEBUG && _d("Waited", $waited, "seconds");
   }
   else {
      MKDEBUG && _d('Not waiting: this server is not a master');
   }

   return {
      result => $result,
      waited => $waited,
   };
}

sub stop_slave {
   my ( $self, $dbh ) = @_;
   my $sth = $self->{sths}->{$dbh}->{STOP_SLAVE}
         ||= $dbh->prepare('STOP SLAVE');
   MKDEBUG && _d($dbh, $sth->{Statement});
   $sth->execute();
}

sub start_slave {
   my ( $self, $dbh, $pos ) = @_;
   if ( $pos ) {
      my $sql = "START SLAVE UNTIL MASTER_LOG_FILE='$pos->{file}', "
              . "MASTER_LOG_POS=$pos->{position}";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   }
   else {
      my $sth = $self->{sths}->{$dbh}->{START_SLAVE}
            ||= $dbh->prepare('START SLAVE');
      MKDEBUG && _d($dbh, $sth->{Statement});
      $sth->execute();
   }
}

sub catchup_to_master {
   my ( $self, $slave, $master, $timeout ) = @_;
   $self->stop_slave($master);
   $self->stop_slave($slave);
   my $slave_status  = $self->get_slave_status($slave);
   my $slave_pos     = $self->repl_posn($slave_status);
   my $master_status = $self->get_master_status($master);
   my $master_pos    = $self->repl_posn($master_status);
   MKDEBUG && _d('Master position:', $self->pos_to_string($master_pos),
      'Slave position:', $self->pos_to_string($slave_pos));

   my $result;
   if ( $self->pos_cmp($slave_pos, $master_pos) < 0 ) {
      MKDEBUG && _d('Waiting for slave to catch up to master');
      $self->start_slave($slave, $master_pos);

      $result = $self->wait_for_master(
            master_status => $master_status,
            slave_dbh     => $slave,
            timeout       => $timeout,
            master_status => $master_status
      );
      if ( !defined $result->{result} ) {
         $slave_status = $self->get_slave_status($slave);
         if ( !$self->slave_is_running($slave_status) ) {
            MKDEBUG && _d('Master position:',
               $self->pos_to_string($master_pos),
               'Slave position:', $self->pos_to_string($slave_pos));
            $slave_pos = $self->repl_posn($slave_status);
            if ( $self->pos_cmp($slave_pos, $master_pos) != 0 ) {
               die "MASTER_POS_WAIT() returned NULL but slave has not "
                  . "caught up to master";
            }
            MKDEBUG && _d('Slave is caught up to master and stopped');
         }
         else {
            die "Slave has not caught up to master and it is still running";
         }
      }
   }
   else {
      MKDEBUG && _d("Slave is already caught up to master");
   }

   return $result;
}

sub catchup_to_same_pos {
   my ( $self, $s1_dbh, $s2_dbh ) = @_;
   $self->stop_slave($s1_dbh);
   $self->stop_slave($s2_dbh);
   my $s1_status = $self->get_slave_status($s1_dbh);
   my $s2_status = $self->get_slave_status($s2_dbh);
   my $s1_pos    = $self->repl_posn($s1_status);
   my $s2_pos    = $self->repl_posn($s2_status);
   if ( $self->pos_cmp($s1_pos, $s2_pos) < 0 ) {
      $self->start_slave($s1_dbh, $s2_pos);
   }
   elsif ( $self->pos_cmp($s2_pos, $s1_pos) < 0 ) {
      $self->start_slave($s2_dbh, $s1_pos);
   }

   $s1_status = $self->get_slave_status($s1_dbh);
   $s2_status = $self->get_slave_status($s2_dbh);
   $s1_pos    = $self->repl_posn($s1_status);
   $s2_pos    = $self->repl_posn($s2_status);

   if ( $self->slave_is_running($s1_status)
     || $self->slave_is_running($s2_status)
     || $self->pos_cmp($s1_pos, $s2_pos) != 0)
   {
      die "The servers aren't both stopped at the same position";
   }

}

sub change_master_to {
   my ( $self, $dbh, $master_dsn, $master_pos ) = @_;
   $self->stop_slave($dbh);
   MKDEBUG && _d(Dumper($master_dsn), Dumper($master_pos));
   my $sql = "CHANGE MASTER TO MASTER_HOST='$master_dsn->{h}', "
      . "MASTER_PORT= $master_dsn->{P}, MASTER_LOG_FILE='$master_pos->{file}', "
      . "MASTER_LOG_POS=$master_pos->{position}";
   MKDEBUG && _d($dbh, $sql);
   $dbh->do($sql);
}

sub make_sibling_of_master {
   my ( $self, $slave_dbh, $slave_dsn, $dsn_parser, $timeout) = @_;

   my $master_dsn  = $self->get_master_dsn($slave_dbh, $slave_dsn, $dsn_parser)
      or die "This server is not a slave";
   my $master_dbh  = $dsn_parser->get_dbh(
      $dsn_parser->get_cxn_params($master_dsn), { AutoCommit => 1 });
   my $gmaster_dsn
      = $self->get_master_dsn($master_dbh, $master_dsn, $dsn_parser)
      or die "This server's master is not a slave";
   my $gmaster_dbh = $dsn_parser->get_dbh(
      $dsn_parser->get_cxn_params($gmaster_dsn), { AutoCommit => 1 });
   if ( $self->short_host($slave_dsn) eq $self->short_host($gmaster_dsn) ) {
      die "The slave's master's master is the slave: master-master replication";
   }

   $self->stop_slave($master_dbh);
   $self->catchup_to_master($slave_dbh, $master_dbh, $timeout);
   $self->stop_slave($slave_dbh);

   my $master_status = $self->get_master_status($master_dbh);
   my $mslave_status = $self->get_slave_status($master_dbh);
   my $slave_status  = $self->get_slave_status($slave_dbh);
   my $master_pos    = $self->repl_posn($master_status);
   my $slave_pos     = $self->repl_posn($slave_status);

   if ( !$self->slave_is_running($mslave_status)
     && !$self->slave_is_running($slave_status)
     && $self->pos_cmp($master_pos, $slave_pos) == 0)
   {
      $self->change_master_to($slave_dbh, $gmaster_dsn,
         $self->repl_posn($mslave_status)); # Note it's not $master_pos!
   }
   else {
      die "The servers aren't both stopped at the same position";
   }

   $mslave_status = $self->get_slave_status($master_dbh);
   $slave_status  = $self->get_slave_status($slave_dbh);
   my $mslave_pos = $self->repl_posn($mslave_status);
   $slave_pos     = $self->repl_posn($slave_status);
   if ( $self->short_host($mslave_status) ne $self->short_host($slave_status)
     || $self->pos_cmp($mslave_pos, $slave_pos) != 0)
   {
      die "The servers don't have the same master/position after the change";
   }
}

sub make_slave_of_sibling {
   my ( $self, $slave_dbh, $slave_dsn, $sib_dbh, $sib_dsn,
        $dsn_parser, $timeout) = @_;

   if ( $self->short_host($slave_dsn) eq $self->short_host($sib_dsn) ) {
      die "You are trying to make the slave a slave of itself";
   }

   my $master_dsn1 = $self->get_master_dsn($slave_dbh, $slave_dsn, $dsn_parser)
      or die "This server is not a slave";
   my $master_dbh1 = $dsn_parser->get_dbh(
      $dsn_parser->get_cxn_params($master_dsn1), { AutoCommit => 1 });
   my $master_dsn2 = $self->get_master_dsn($slave_dbh, $slave_dsn, $dsn_parser)
      or die "The sibling is not a slave";
   if ( $self->short_host($master_dsn1) ne $self->short_host($master_dsn2) ) {
      die "This server isn't a sibling of the slave";
   }
   my $sib_master_stat = $self->get_master_status($sib_dbh)
      or die "Binary logging is not enabled on the sibling";
   die "The log_slave_updates option is not enabled on the sibling"
      unless $self->has_slave_updates($sib_dbh);

   $self->catchup_to_same_pos($slave_dbh, $sib_dbh);

   $sib_master_stat = $self->get_master_status($sib_dbh);
   $self->change_master_to($slave_dbh, $sib_dsn,
         $self->repl_posn($sib_master_stat));

   my $slave_status = $self->get_slave_status($slave_dbh);
   my $slave_pos    = $self->repl_posn($slave_status);
   $sib_master_stat = $self->get_master_status($sib_dbh);
   if ( $self->short_host($slave_status) ne $self->short_host($sib_dsn)
     || $self->pos_cmp($self->repl_posn($sib_master_stat), $slave_pos) != 0)
   {
      die "After changing the slave's master, it isn't a slave of the sibling, "
         . "or it has a different replication position than the sibling";
   }
}

sub make_slave_of_uncle {
   my ( $self, $slave_dbh, $slave_dsn, $unc_dbh, $unc_dsn,
        $dsn_parser, $timeout) = @_;

   if ( $self->short_host($slave_dsn) eq $self->short_host($unc_dsn) ) {
      die "You are trying to make the slave a slave of itself";
   }

   my $master_dsn = $self->get_master_dsn($slave_dbh, $slave_dsn, $dsn_parser)
      or die "This server is not a slave";
   my $master_dbh = $dsn_parser->get_dbh(
      $dsn_parser->get_cxn_params($master_dsn), { AutoCommit => 1 });
   my $gmaster_dsn
      = $self->get_master_dsn($master_dbh, $master_dsn, $dsn_parser)
      or die "The master is not a slave";
   my $unc_master_dsn
      = $self->get_master_dsn($unc_dbh, $unc_dsn, $dsn_parser)
      or die "The uncle is not a slave";
   if ($self->short_host($gmaster_dsn) ne $self->short_host($unc_master_dsn)) {
      die "The uncle isn't really the slave's uncle";
   }

   my $unc_master_stat = $self->get_master_status($unc_dbh)
      or die "Binary logging is not enabled on the uncle";
   die "The log_slave_updates option is not enabled on the uncle"
      unless $self->has_slave_updates($unc_dbh);

   $self->catchup_to_same_pos($master_dbh, $unc_dbh);
   $self->catchup_to_master($slave_dbh, $master_dbh, $timeout);

   my $slave_status  = $self->get_slave_status($slave_dbh);
   my $master_status = $self->get_master_status($master_dbh);
   if ( $self->pos_cmp(
         $self->repl_posn($slave_status),
         $self->repl_posn($master_status)) != 0 )
   {
      die "The slave is not caught up to its master";
   }

   $unc_master_stat = $self->get_master_status($unc_dbh);
   $self->change_master_to($slave_dbh, $unc_dsn,
      $self->repl_posn($unc_master_stat));


   $slave_status    = $self->get_slave_status($slave_dbh);
   my $slave_pos    = $self->repl_posn($slave_status);
   if ( $self->short_host($slave_status) ne $self->short_host($unc_dsn)
     || $self->pos_cmp($self->repl_posn($unc_master_stat), $slave_pos) != 0)
   {
      die "After changing the slave's master, it isn't a slave of the uncle, "
         . "or it has a different replication position than the uncle";
   }
}

sub detach_slave {
   my ( $self, $dbh ) = @_;
   $self->stop_slave($dbh);
   my $stat = $self->get_slave_status($dbh)
      or die "This server is not a slave";
   $dbh->do('CHANGE MASTER TO MASTER_HOST=""');
   $dbh->do('RESET SLAVE'); # Wipes out master.info, etc etc
   return $stat;
}

sub slave_is_running {
   my ( $self, $slave_status ) = @_;
   return ($slave_status->{slave_sql_running} || 'No') eq 'Yes';
}

sub has_slave_updates {
   my ( $self, $dbh ) = @_;
   my $sql = q{SHOW VARIABLES LIKE 'log_slave_updates'};
   MKDEBUG && _d($dbh, $sql);
   my ($name, $value) = $dbh->selectrow_array($sql);
   return $value && $value =~ m/^(1|ON)$/;
}

sub repl_posn {
   my ( $self, $status ) = @_;
   if ( exists $status->{file} && exists $status->{position} ) {
      return {
         file     => $status->{file},
         position => $status->{position},
      };
   }
   else {
      return {
         file     => $status->{relay_master_log_file},
         position => $status->{exec_master_log_pos},
      };
   }
}

sub get_slave_lag {
   my ( $self, $dbh ) = @_;
   my $stat = $self->get_slave_status($dbh);
   return $stat->{seconds_behind_master};
}

sub pos_cmp {
   my ( $self, $a, $b ) = @_;
   return $self->pos_to_string($a) cmp $self->pos_to_string($b);
}

sub short_host {
   my ( $self, $dsn ) = @_;
   my ($host, $port);
   if ( $dsn->{master_host} ) {
      $host = $dsn->{master_host};
      $port = $dsn->{master_port};
   }
   else {
      $host = $dsn->{h};
      $port = $dsn->{P};
   }
   return ($host || '[default]') . ( ($port || 3306) == 3306 ? '' : ":$port" );
}

sub is_replication_thread {
   my ( $self, $query, %args ) = @_; 
   return unless $query;

   my $type = lc $args{type} || 'all';
   die "Invalid type: $type"
      unless $type =~ m/^binlog_dump|slave_io|slave_sql|all$/i;

   my $match = 0;
   if ( $type =~ m/binlog_dump|all/i ) {
      $match = 1
         if ($query->{Command} || $query->{command} || '') eq "Binlog Dump";
   }
   if ( !$match ) {
      if ( ($query->{User} || $query->{user} || '') eq "system user" ) {
         MKDEBUG && _d("Slave replication thread");
         if ( $type ne 'all' ) { 
            my $state = $query->{State} || $query->{state} || '';

            if ( $state =~ m/^init|end$/ ) {
               MKDEBUG && _d("Special state:", $state);
               $match = 1;
            }
            else {
               my ($slave_sql) = $state =~ m/
                  ^(Waiting\sfor\sthe\snext\sevent
                   |Reading\sevent\sfrom\sthe\srelay\slog
                   |Has\sread\sall\srelay\slog;\swaiting
                   |Making\stemp\sfile
                   |Waiting\sfor\sslave\smutex\son\sexit)/xi; 

               $match = $type eq 'slave_sql' &&  $slave_sql ? 1
                      : $type eq 'slave_io'  && !$slave_sql ? 1
                      :                                       0;
            }
         }
         else {
            $match = 1;
         }
      }
      else {
         MKDEBUG && _d('Not system user');
      }

      if ( !defined $args{check_known_ids} || $args{check_known_ids} ) {
         my $id = $query->{Id} || $query->{id};
         if ( $match ) {
            $self->{replication_thread}->{$id} = 1;
         }
         else {
            if ( $self->{replication_thread}->{$id} ) {
               MKDEBUG && _d("Thread ID is a known replication thread ID");
               $match = 1;
            }
         }
      }
   }

   MKDEBUG && _d('Matches', $type, 'replication thread:',
      ($match ? 'yes' : 'no'), '; match:', $match);

   return $match;
}


sub get_replication_filters {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh) = @args{@required_args};

   my %filters = ();

   my $status = $self->get_master_status($dbh);
   if ( $status ) {
      map { $filters{$_} = $status->{$_} }
      grep { defined $status->{$_} && $status->{$_} ne '' }
      qw(
         binlog_do_db
         binlog_ignore_db
      );
   }

   $status = $self->get_slave_status($dbh);
   if ( $status ) {
      map { $filters{$_} = $status->{$_} }
      grep { defined $status->{$_} && $status->{$_} ne '' }
      qw(
         replicate_do_db
         replicate_ignore_db
         replicate_do_table
         replicate_ignore_table 
         replicate_wild_do_table
         replicate_wild_ignore_table
      );

      my $sql = "SHOW VARIABLES LIKE 'slave_skip_errors'";
      MKDEBUG && _d($dbh, $sql);
      my $row = $dbh->selectrow_arrayref($sql);
      $filters{slave_skip_errors} = $row->[1] if $row->[1] && $row->[1] ne 'OFF';
   }

   return \%filters; 
}


sub pos_to_string {
   my ( $self, $pos ) = @_;
   my $fmt  = '%s/%020d';
   return sprintf($fmt, @{$pos}{qw(file position)});
}

sub reset_known_replication_threads {
   my ( $self ) = @_;
   $self->{replication_thread} = {};
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
# End MasterSlave package
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
# SchemaIterator package 7512
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/SchemaIterator.pm
#   trunk/common/t/SchemaIterator.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package SchemaIterator;

{ # package scope
use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $open_comment = qr{/\*!\d{5} };
my $tbl_name     = qr{
   CREATE\s+
   (?:TEMPORARY\s+)?
   TABLE\s+
   (?:IF NOT EXISTS\s+)?
   ([^\(]+)
}x;


sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(OptionParser Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my ($file_itr, $dbh) = @args{qw(file_itr dbh)};
   die "I need either a dbh or file_itr argument"
      if (!$dbh && !$file_itr) || ($dbh && $file_itr);

   my $self = {
      %args,
      filters => _make_filters(%args),
   };

   return bless $self, $class;
}

sub _make_filters {
   my ( %args ) = @_;
   my @required_args = qw(OptionParser Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($o, $q) = @args{@required_args};

   my %filters;


   my @simple_filters = qw(
      databases         tables         engines
      ignore-databases  ignore-tables  ignore-engines);
   FILTER:
   foreach my $filter ( @simple_filters ) {
      if ( $o->has($filter) ) {
         my $objs = $o->get($filter);
         next FILTER unless $objs && scalar keys %$objs;
         my $is_table = $filter =~ m/table/ ? 1 : 0;
         foreach my $obj ( keys %$objs ) {
            die "Undefined value for --$filter" unless $obj;
            $obj = lc $obj;
            if ( $is_table ) {
               my ($db, $tbl) = $q->split_unquote($obj);
               $db ||= '*';
               MKDEBUG && _d('Filter', $filter, 'value:', $db, $tbl);
               $filters{$filter}->{$tbl} = $db;
            }
            else { # database
               MKDEBUG && _d('Filter', $filter, 'value:', $obj);
               $filters{$filter}->{$obj} = 1;
            }
         }
      }
   }

   my @regex_filters = qw(
      databases-regex         tables-regex
      ignore-databases-regex  ignore-tables-regex);
   REGEX_FILTER:
   foreach my $filter ( @regex_filters ) {
      if ( $o->has($filter) ) {
         my $pat = $o->get($filter);
         next REGEX_FILTER unless $pat;
         $filters{$filter} = qr/$pat/;
         MKDEBUG && _d('Filter', $filter, 'value:', $filters{$filter});
      }
   }

   MKDEBUG && _d('Schema object filters:', Dumper(\%filters));
   return \%filters;
}

sub next_schema_object {
   my ( $self ) = @_;

   my %schema_object;
   if ( $self->{file_itr} ) {
      %schema_object = $self->_iterate_files();
   }
   else { # dbh
      %schema_object = $self->_iterate_dbh();
   }

   MKDEBUG && _d('Next schema object:', Dumper(\%schema_object));
   return %schema_object;
}

sub _iterate_files {
   my ( $self ) = @_;

   if ( !$self->{fh} ) {
      my ($fh, $file) = $self->{file_itr}->();
      if ( !$fh ) {
         MKDEBUG && _d('No more files to iterate');
         return;
      }
      $self->{fh}   = $fh;
      $self->{file} = $file;
   }
   my $fh = $self->{fh};
   MKDEBUG && _d('Getting next schema object from', $self->{file});

   local $INPUT_RECORD_SEPARATOR = '';
   CHUNK:
   while (defined(my $chunk = <$fh>)) {
      if ($chunk =~ m/Database: (\S+)/) {
         my $db = $1; # XXX
         $db =~ s/^`//;  # strip leading `
         $db =~ s/`$//;  # and trailing `
         if ( $self->database_is_allowed($db) ) {
            $self->{db} = $db;
         }
      }
      elsif ($self->{db} && $chunk =~ m/CREATE TABLE/) {
         if ($chunk =~ m/DROP VIEW IF EXISTS/) {
            MKDEBUG && _d('Table is a VIEW, skipping');
            next CHUNK;
         }

         my ($tbl) = $chunk =~ m/$tbl_name/;
         $tbl      =~ s/^\s*`//;
         $tbl      =~ s/`\s*$//;
         if ( $self->table_is_allowed($self->{db}, $tbl) ) {
            my ($ddl) = $chunk =~ m/^(?:$open_comment)?(CREATE TABLE.+?;)$/ms;
            if ( !$ddl ) {
               warn "Failed to parse CREATE TABLE from\n" . $chunk;
               next CHUNK;
            }
            $ddl =~ s/ \*\/;\Z/;/;  # remove end of version comment

            my ($engine) = $ddl =~ m/\).*?(?:ENGINE|TYPE)=(\w+)/;   

            if ( !$engine || $self->engine_is_allowed($engine) ) {
               return (
                  db  => $self->{db},
                  tbl => $tbl,
                  ddl => $ddl,
               );
            }
         }
      }
   }  # CHUNK

   MKDEBUG && _d('No more schema objects in', $self->{file});
   close $self->{fh};
   $self->{fh} = undef;

   return $self->_iterate_files();
}

sub _iterate_dbh {
   my ( $self ) = @_;
   my $q   = $self->{Quoter};
   my $dbh = $self->{dbh};
   MKDEBUG && _d('Getting next schema object from dbh', $dbh);

   if ( !defined $self->{dbs} ) {
      my $sql = 'SHOW DATABASES';
      MKDEBUG && _d($sql);
      my @dbs = grep { $self->database_is_allowed($_) }
                @{$dbh->selectcol_arrayref($sql)};
      MKDEBUG && _d('Found', scalar @dbs, 'databases');
      $self->{dbs} = \@dbs;
   }

   if ( !$self->{db} ) {
      $self->{db} = shift @{$self->{dbs}};
      MKDEBUG && _d('Next database:', $self->{db});
      return unless $self->{db};
   }

   if ( !defined $self->{tbls} ) {
      my $sql = 'SHOW /*!50002 FULL*/ TABLES FROM ' . $q->quote($self->{db});
      MKDEBUG && _d($sql);
      my @tbls = map {
         $_->[0];  # (tbl, type)
      }
      grep {
         my ($tbl, $type) = @$_;
         $self->table_is_allowed($self->{db}, $tbl)
            && (!$type || ($type ne 'VIEW'));
      }
      @{$dbh->selectall_arrayref($sql)};
      MKDEBUG && _d('Found', scalar @tbls, 'tables in database', $self->{db});
      $self->{tbls} = \@tbls;
   }

   while ( my $tbl = shift @{$self->{tbls}} ) {
      my $engine;
      if ( $self->{filters}->{'engines'}
           || $self->{filters}->{'ignore-engines'} ) {
         my $sql = "SHOW TABLE STATUS FROM " . $q->quote($self->{db})
                 . " LIKE \'$tbl\'";
         MKDEBUG && _d($sql);
         $engine = $dbh->selectrow_hashref($sql)->{engine};
         MKDEBUG && _d($tbl, 'uses', $engine, 'engine');
      }


      if ( !$engine || $self->engine_is_allowed($engine) ) {
         my $ddl;
         if ( my $du = $self->{MySQLDump} ) {
            $ddl = $du->get_create_table($dbh, $q, $self->{db}, $tbl)->[1];
         }

         return (
            db  => $self->{db},
            tbl => $tbl,
            ddl => $ddl,
         );
      }
   }

   MKDEBUG && _d('No more tables in database', $self->{db});
   $self->{db}   = undef;
   $self->{tbls} = undef;

   return $self->_iterate_dbh();
}

sub database_is_allowed {
   my ( $self, $db ) = @_;
   die "I need a db argument" unless $db;

   $db = lc $db;

   my $filter = $self->{filters};

   if ( $db =~ m/information_schema|performance_schema|lost\+found/ ) {
      MKDEBUG && _d('Database', $db, 'is a system database, ignoring');
      return 0;
   }

   if ( $self->{filters}->{'ignore-databases'}->{$db} ) {
      MKDEBUG && _d('Database', $db, 'is in --ignore-databases list');
      return 0;
   }

   if ( $filter->{'ignore-databases-regex'}
        && $db =~ $filter->{'ignore-databases-regex'} ) {
      MKDEBUG && _d('Database', $db, 'matches --ignore-databases-regex');
      return 0;
   }

   if ( $filter->{'databases'}
        && !$filter->{'databases'}->{$db} ) {
      MKDEBUG && _d('Database', $db, 'is not in --databases list, ignoring');
      return 0;
   }

   if ( $filter->{'databases-regex'}
        && $db !~ $filter->{'databases-regex'} ) {
      MKDEBUG && _d('Database', $db, 'does not match --databases-regex, ignoring');
      return 0;
   }

   return 1;
}

sub table_is_allowed {
   my ( $self, $db, $tbl ) = @_;
   die "I need a db argument"  unless $db;
   die "I need a tbl argument" unless $tbl;

   $db  = lc $db;
   $tbl = lc $tbl;

   my $filter = $self->{filters};

   if ( $filter->{'ignore-tables'}->{$tbl}
        && ($filter->{'ignore-tables'}->{$tbl} eq '*'
            || $filter->{'ignore-tables'}->{$tbl} eq $db) ) {
      MKDEBUG && _d('Table', $tbl, 'is in --ignore-tables list');
      return 0;
   }

   if ( $filter->{'ignore-tables-regex'}
        && $tbl =~ $filter->{'ignore-tables-regex'} ) {
      MKDEBUG && _d('Table', $tbl, 'matches --ignore-tables-regex');
      return 0;
   }

   if ( $filter->{'tables'}
        && !$filter->{'tables'}->{$tbl} ) { 
      MKDEBUG && _d('Table', $tbl, 'is not in --tables list, ignoring');
      return 0;
   }

   if ( $filter->{'tables-regex'}
        && $tbl !~ $filter->{'tables-regex'} ) {
      MKDEBUG && _d('Table', $tbl, 'does not match --tables-regex, ignoring');
      return 0;
   }

   if ( $filter->{'tables'}
        && $filter->{'tables'}->{$tbl}
        && $filter->{'tables'}->{$tbl} ne '*'
        && $filter->{'tables'}->{$tbl} ne $db ) {
      MKDEBUG && _d('Table', $tbl, 'is only allowed in database',
         $filter->{'tables'}->{$tbl});
      return 0;
   }

   return 1;
}

sub engine_is_allowed {
   my ( $self, $engine ) = @_;
   die "I need an engine argument" unless $engine;

   $engine = lc $engine;

   my $filter = $self->{filters};

   if ( $filter->{'ignore-engines'}->{$engine} ) {
      MKDEBUG && _d('Engine', $engine, 'is in --ignore-databases list');
      return 0;
   }

   if ( $filter->{'engines'}
        && !$filter->{'engines'}->{$engine} ) {
      MKDEBUG && _d('Engine', $engine, 'is not in --engines list, ignoring');
      return 0;
   }

   return 1;
}

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

} # package scope
1;

# ###########################################################################
# End SchemaIterator package
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
# Progress package 7096
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Progress.pm
#   trunk/common/t/Progress.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package Progress;

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
   foreach my $arg (qw(jobsize)) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   if ( (!$args{report} || !$args{interval}) ) {
      if ( $args{spec} && @{$args{spec}} == 2 ) {
         @args{qw(report interval)} = @{$args{spec}};
      }
      else {
         die "I need either report and interval arguments, or a spec";
      }
   }

   my $name  = $args{name} || "Progress";
   $args{start} ||= time();
   my $self;
   $self = {
      last_reported => $args{start},
      fraction      => 0,       # How complete the job is
      callback      => sub {
         my ($fraction, $elapsed, $remaining, $eta) = @_;
         printf STDERR "$name: %3d%% %s remain\n",
            $fraction * 100,
            Transformers::secs_to_time($remaining),
            Transformers::ts($eta);
      },
      %args,
   };
   return bless $self, $class;
}

sub validate_spec {
   shift @_ if $_[0] eq 'Progress'; # Permit calling as Progress-> or Progress::
   my ( $spec ) = @_;
   if ( @$spec != 2 ) {
      die "spec array requires a two-part argument\n";
   }
   if ( $spec->[0] !~ m/^(?:percentage|time|iterations)$/ ) {
      die "spec array's first element must be one of "
        . "percentage,time,iterations\n";
   }
   if ( $spec->[1] !~ m/^\d+$/ ) {
      die "spec array's second element must be an integer\n";
   }
}

sub set_callback {
   my ( $self, $callback ) = @_;
   $self->{callback} = $callback;
}

sub start {
   my ( $self, $start ) = @_;
   $self->{start} = $self->{last_reported} = $start || time();
}

sub update {
   my ( $self, $callback, $now ) = @_;
   my $jobsize   = $self->{jobsize};
   $now        ||= time();
   $self->{iterations}++; # How many updates have happened;

   if ( $self->{report} eq 'time'
         && $self->{interval} > $now - $self->{last_reported}
   ) {
      return;
   }
   elsif ( $self->{report} eq 'iterations'
         && ($self->{iterations} - 1) % $self->{interval} > 0
   ) {
      return;
   }
   $self->{last_reported} = $now;

   my $completed = $callback->();
   $self->{updates}++; # How many times we have run the update callback

   return if $completed > $jobsize;

   my $fraction = $completed > 0 ? $completed / $jobsize : 0;

   if ( $self->{report} eq 'percentage'
         && $self->fraction_modulo($self->{fraction})
            >= $self->fraction_modulo($fraction)
   ) {
      $self->{fraction} = $fraction;
      return;
   }
   $self->{fraction} = $fraction;

   my $elapsed   = $now - $self->{start};
   my $remaining = 0;
   my $eta       = $now;
   if ( $completed > 0 && $completed <= $jobsize && $elapsed > 0 ) {
      my $rate = $completed / $elapsed;
      if ( $rate > 0 ) {
         $remaining = ($jobsize - $completed) / $rate;
         $eta       = $now + int($remaining);
      }
   }
   $self->{callback}->($fraction, $elapsed, $remaining, $eta, $completed);
}

sub fraction_modulo {
   my ( $self, $num ) = @_;
   $num *= 100; # Convert from fraction to percentage
   return sprintf('%d',
      sprintf('%d', $num / $self->{interval}) * $self->{interval});
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
# End Progress package
# ###########################################################################

# ###########################################################################
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_table_checksum;

use English qw(-no_match_vars);
use List::Util qw(max maxstr);
use Time::HiRes qw(gettimeofday sleep);
use Data::Dumper;
$Data::Dumper::Indent    = 0;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

$OUTPUT_AUTOFLUSH = 1;

# Global variables.
my $checksum_table_data;
my ( $fetch_sth, $update_sth, $savesince_sth );
my ( $crc_wid, $md5sum_fmt );
my $already_checksummed;
# %tables_to_checksum has the following structure:
#    database => [
#       { table },
#       ...
#    ],
#    ...
my %tables_to_checksum;

sub main {
   @ARGV = @_;  # set global ARGV for this package

   # Reset global vars else tests which run this tool as a module
   # will have strange, overlapping results. 
   $checksum_table_data                        = undef;
   ( $fetch_sth, $update_sth, $savesince_sth ) = (undef, undef, undef);
   ( $crc_wid, $md5sum_fmt )                   = (undef, undef);
   $already_checksummed                        = undef;
   %tables_to_checksum                         = ();

   my $q = new Quoter();
   my $exit_status = 0;

   # ########################################################################
   # Get configuration information.
   # ########################################################################
   # Because of --arg-table, $final_o is the OptionParser obj used to get
   # most options (see my $final_o below).
   my $o = new OptionParser();
   $o->get_specs();
   $o->get_opts();

   my $dp = $o->DSNParser();
   $dp->prop('set-vars', $o->get('set-vars'));

   # This list contains all the command-line arguments that can be overridden
   # by a table that contains arguments for each table to be checksummed.
   # The long form of each argument is given.  The values are read from the
   # POD by finding the magical token.
   my %overridable_args;
   {
      my $para = $o->read_para_after(
         __FILE__, qr/MAGIC_overridable_args/);
      foreach my $arg ( $para =~ m/([\w-]+)/g ) {
         die "Magical argument $arg mentioned in POD is not a "
            . "command-line argument" unless $o->has($arg);
         $overridable_args{$arg} = 1;
      }
   };

   # Post-process command-line options and arguments.
   if ( $o->get('replicate') ) {
      # --replicate says that it disables these options.  We don't
      # check got() because these opts aren't used in do_tbl_replicate()
      # or its caller so they're completely useless with --replicate.
      $o->set('lock',      undef);
      $o->set('wait',      undef);
      $o->set('slave-lag', undef);
   }
   else {
      $o->set('lock', 1)      if $o->get('wait');
      $o->set('slave-lag', 1) if $o->get('lock');
   }

   if ( !@ARGV ) {
      $o->save_error("No hosts specified.");
   }

   my @hosts; 
   my $dsn_defaults = $dp->parse_options($o);
   {
      foreach my $arg ( unique(@ARGV) ) {
         push @hosts, $dp->parse($arg, $hosts[0], $dsn_defaults);
      }
   }

   if ( $o->get('explain-hosts') ) {
      foreach my $host ( @hosts ) {
         print "Server $host->{h}:\n   ", $dp->as_string($host), "\n";
      }
      return 0;
   }

   # Checksumming table data is the normal operation. But if we're only to
   # compare schemas, then we can skip a lot of work, like selecting an algo,
   # replication stuff, etc.
   $checksum_table_data = $o->get('schema') ? 0 : 1;

   if ( $o->get('checksum') ) {
      $o->set('count', 0);
   }

   if ( $o->get('explain') ) {
      @hosts = $hosts[0];
   }

   # --replicate auto-enables --throttle-method slavelag unless user
   # set --throttle-method explicitly.
   $o->set('throttle-method', 'slavelag')
      if $o->get('replicate') && !$o->got('throttle-method');

   # These options are only needed if a --chunk-size is specified.
   if ( !$o->get('chunk-size') ) {
      $o->set('chunk-size-limit', undef);
      $o->set('unchunkable-tables', 1);
   }

   if ( !$o->get('help') ) {
      if ( $o->get('replicate-check') && !$o->get('replicate') ) {
         $o->save_error("--replicate-check requires --replicate.");
      }
      if ( $o->get('save-since') && !$o->get('arg-table') ) {
         $o->save_error("--save-since requires --arg-table.");
      }
      elsif ( $o->get('replicate') && @hosts > 1 ) {
         $o->save_error("You can only specify one host with --replicate.");
      }

      if ( $o->get('resume-replicate') && !$o->get('replicate') ) {
         $o->save_error("--resume-replicate requires --replicate.");
      }
      if ( $o->get('resume') && $o->get('replicate') ) {
         $o->save_error('--resume does not work with --replicate.  '
            . 'Use --resume-replicate instead.');
      }

      if ( my $throttle_method = $o->get('throttle-method') ) {
         $throttle_method = lc $throttle_method;
         if ( !grep { $throttle_method eq $_ } qw(none slavelag) ) {
            $o->save_error("Invalid --throttle-method: $throttle_method");
         }
      }

      if ( $o->get('check-slave-lag') && $o->get('throttle-method') eq 'none') {
         # User specified --check-slave-lag DSN and --throttle-method none.
         # They probably meant just --check-slave-lag DSN.
         $o->save_error('-throttle-method=none contradicts --check-slave-lag '
            . 'because --check-slave-lag implies --throttle-method=slavelag');
      }
      if ( $o->get('throttle-method') ne 'none' && !$o->get('replicate') ) {
         # User did --throttle-method (explicitly) without --replicate.
         $o->save_error('--throttle-method ', $o->get('throttle-method'),
            ' requires --replicate');
      }
   
      # Make sure --replicate has a db. 
      if ( my $replicate_table = $o->get('replicate') ) {
         my ($db, $tbl) = $q->split_unquote($replicate_table);
         if ( !$db ) {
            $o->save_error('The --replicate table must be database-qualified');
         }
      }

      if ( $o->get('chunk-size-limit') ) {
         my $factor = $o->get('chunk-size-limit');
         if ( $factor < 0                        # can't be negative
              || ($factor > 0 && $factor < 1) )  # can't be less than 1
         {
            $o->save_error('--chunk-size-limit must be >= 1 or 0 to disable');
         }
      }

      if ( $o->get('progress') ) {
         eval { Progress->validate_spec($o->get('progress')) };
         if ( $EVAL_ERROR ) {
            chomp $EVAL_ERROR;
            $o->save_error("--progress $EVAL_ERROR");
         }
      }

      if ( my $chunk_range = $o->get('chunk-range') ) {
         $chunk_range = lc $chunk_range;
         my $para = $o->read_para_after(__FILE__, qr/MAGIC_chunk_range/);
         my @vals = $para =~ m/\s+([a-z]+)\s+[A-Z]+/g;
         if ( !grep { $chunk_range eq $_} @vals ) {
            $o->save_error("Invalid value for --chunk-range.  "
               . "Valid values are: " . join(", ", @vals));
         }
      }
   }

   $o->usage_or_errors();

   # ########################################################################
   # If --pid, check it first since we'll die if it already exits.
   # ########################################################################
   my $daemon;
   if ( $o->get('pid') ) {
      # We're not daemoninzing, it just handles PID stuff.  Keep $daemon
      # in the the scope of main() because when it's destroyed it automatically
      # removes the PID file.
      $daemon = new Daemon(o=>$o);
      $daemon->make_PID_file();
   }

   # ########################################################################
   # Ready to work now.
   # ########################################################################
   my $vp = new VersionParser();
   my $tp = new TableParser(Quoter => $q);
   my $tc = new TableChecksum(Quoter=> $q, VersionParser => $vp);
   my $ms = new MasterSlave(VersionParser => $vp);
   my $du = new MySQLDump();
   my $ch = new TableChunker(Quoter => $q, MySQLDump => $du); 
   my %common_modules = (
      ch => $ch,
      dp => $dp,
      du => $du,
      o  => $o,
      ms => $ms,
      q  => $q,
      tc => $tc,
      tp => $tp,
      vp => $vp,
   );

   my $main_dbh = get_cxn($hosts[0], %common_modules);

   # #########################################################################
   # Prepare --throttle-method.
   # #########################################################################
   my $throttle_method = $o->get('throttle-method');
   my @slaves;
   if ( lc($throttle_method) eq 'slavelag' ) {
      if ( $o->get('check-slave-lag') ) {
         MKDEBUG && _d('Using --check-slave-lag DSN for throttle');
         # OptionParser can't auto-copy DSN vals from a cmd line DSN
         # to an opt DSN, so we copy them manually.
         my $dsn = $dp->copy($hosts[0], $o->get('check-slave-lag'));
         push @slaves, { dsn=>$dsn, dbh=>get_cxn($dsn, %common_modules) };
      }
      else {
         MKDEBUG && _d('Recursing to slaves for throttle');
         $ms->recurse_to_slaves(
            {  dbh        => $main_dbh,
               dsn        => $hosts[0],
               dsn_parser => $dp,
               recurse    => $o->get('recurse'),
               method     => $o->get('recursion-method'),
               callback   => sub {
                  my ( $dsn, $dbh, $level, $parent ) = @_;
                  return unless $level;
                  MKDEBUG && _d('throttle slave:', $dp->as_string($dsn));
                  $dbh->{InactiveDestroy}  = 1; # Prevent destroying on fork.
                  $dbh->{FetchHashKeyName} = 'NAME_lc';
                  push @slaves, { dsn=>$dsn, dbh=>$dbh };
                  return;
               },
            }
         );
      }
   }

   # ########################################################################
   # Load --arg-table information.
   # ########################################################################
   my %args_for;
   if ( my $arg_tbl = $o->get('arg-table') ) {
      my %col_in_argtable;
      my $rows = $main_dbh->selectall_arrayref(
         "SELECT * FROM $arg_tbl", { Slice => {} });
      foreach my $row ( @$rows ) {
         die "Invalid entry in --arg-table: db and tbl must be set"
            unless $row->{db} && $row->{tbl};
         $args_for{$row->{db}}->{$row->{tbl}} = {
            map  { $_ => $row->{$_} }
            grep { $overridable_args{$_} && defined $row->{$_} }
            keys %$row
         };
         if ( !%col_in_argtable ) { # do only once
            foreach my $key ( keys %$row ) {
               next if $key =~ m/^(db|tbl|ts)$/;
               die "Column $key (from $arg_tbl given by --arg-table) is not "
                  . "an overridable argument" unless $overridable_args{$key};
               $col_in_argtable{$key} = 1;
            }
         }
      }
      if ( $col_in_argtable{since} ) {
         $savesince_sth = $main_dbh->prepare(
           "UPDATE $arg_tbl SET since=COALESCE(?, NOW()) WHERE db=? AND tbl=?");
      }
   }

   # ########################################################################
   # Check for replication filters.
   # ########################################################################
   if ( $o->get('replicate') && $o->get('check-replication-filters') ) {
      MKDEBUG && _d("Recursing to slaves to check for replication filters");
      my @all_repl_filters;
      $ms->recurse_to_slaves(
         {  dbh        => $main_dbh,
            dsn        => $hosts[0],
            dsn_parser => $dp,
            recurse    => undef,  # check for filters anywhere
            method     => $o->get('recursion-method'),
            callback   => sub {
               my ( $dsn, $dbh, $level, $parent ) = @_;
               my $repl_filters = $ms->get_replication_filters(dbh=>$dbh);
               if ( keys %$repl_filters ) {
                  my $host = $dp->as_string($dsn);
                  push @all_repl_filters,
                     { name    => $host,
                       filters => $repl_filters,
                     };
               }
               return;
            },
         }
      );
      if ( @all_repl_filters ) {
         my $msg = "Cannot checksum with --replicate because replication "
                 . "filters are set on these hosts:\n";
         foreach my $host ( @all_repl_filters ) {
            my $filters = $host->{filters};
            $msg .= "  $host->{name}\n"
                  . join("\n", map { "    $_ = $host->{filters}->{$_}" }
                        keys %{$host->{filters}})
                  . "\n";
         }
         $msg .= "Please read the --check-replication-filters documentation "
               . "to learn how to solve this problem.";
         warn $msg;
         return 1;
      }
   }

   # ########################################################################
   # Check replication slaves if desired.  If only --replicate-check is given,
   # then we will exit here.  If --recheck is also given, then we'll continue
   # through the entire script but checksum only the inconsistent tables found
   # here.
   # ########################################################################
   if ( defined $o->get('replicate-check') ) {
      MKDEBUG && _d("Recursing to slaves for replicate check, depth",
         $o->get('replicate-check'));
      my $callback = $o->get('recheck')
                   ? \&save_inconsistent_tbls
                   : \&print_inconsistent_tbls;
      $ms->recurse_to_slaves(
         {  dbh        => $main_dbh,
            dsn        => $hosts[0],
            dsn_parser => $dp,
            recurse    => $o->get('replicate-check'),
            method     => $o->get('recursion-method'),
            callback   => sub {
               my ( $dsn, $dbh, $level, $parent ) = @_;
               my @tbls = $tc->find_replication_differences(
                  $dbh, $o->get('replicate'));
               return unless @tbls;
               $exit_status = 1;
               # Call the callback that does something useful with
               # the inconsistent tables.
               # o dbh db tbl args_for
               $callback->(
                  dsn      => $dsn,
                  dbh      => $dbh,
                  level    => $level,
                  parent   => $parent,
                  tbls     => \@tbls,
                  args_for => \%args_for,
                  %common_modules
               );
            },
         }
      );
      return $exit_status unless $o->get('recheck');
   }

   # ########################################################################
   # Otherwise get ready to checksum table data, unless we have only to check
   # schemas in which case we can skip all such work, knowing already that we
   # will use CRC32.
   # ########################################################################
   if ( $checksum_table_data ) {
      # Verify that CONCAT_WS is compatible across all servers. On older
      # versions of MySQL it skips both empty strings and NULL; on newer
      # just NULL.
      if ( $o->get('verify') && @hosts > 1 ) {
         verify_checksum_compat(hosts=>\@hosts, %common_modules);
      }

      ($fetch_sth, $update_sth)
         = check_repl_table(dbh=>$main_dbh, %common_modules);
   }
   else {
      $crc_wid = 16; # Wider than the widest CRC32.
   } 

   # ########################################################################
   # If resuming a previous run, figure out what the previous run finished.
   # ######################################################################## 
   if ( $o->get('replicate') && $o->get('resume-replicate') ) {
      $already_checksummed = read_repl_table(
         dbh  => $main_dbh,
         host => $hosts[0]->{h},
         %common_modules,
      );
   } 
   elsif ( $o->get('resume') ) {
      $already_checksummed = parse_resume_file($o->get('resume'));
   }

   # ########################################################################
   # Set transaction isolation level.
   # http://code.google.com/p/maatkit/issues/detail?id=720
   # ########################################################################
   if ( $o->get('replicate') ) {
      my $sql = "SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ";
      eval {
         MKDEBUG && _d($main_dbh, $sql);
         $main_dbh->do($sql);
      };
      if ( $EVAL_ERROR ) {
         die "Failed to $sql: $EVAL_ERROR\n"
            . "If the --replicate table is InnoDB and the default server "
            . "transaction isolation level is not REPEATABLE-READ then "
            . "checksumming may fail with errors like \"Binary logging not "
            . "possible. Message: Transaction level 'READ-COMMITTED' in "
            . "InnoDB is not safe for binlog mode 'STATEMENT'\".  In that "
            . "case you will need to manually set the transaction isolation "
            . "level to REPEATABLE-READ.";
      }
   }

   # ########################################################################
   # Iterate through databases and tables and do the checksums.
   # ########################################################################

   # Get table info for all hosts, all slaves, unless we're in the special
   # "repl-re-check" mode in which case %tables_to_checksum has already the
   # inconsistent tables that we need to re-checksum.
   get_all_tbls_info(
      dbh      => $main_dbh,
      args_for => \%args_for,
      %common_modules,
   ) unless ($o->get('replicate-check') && $o->get('recheck'));

   # Finally, checksum the tables.
   foreach my $database ( keys %tables_to_checksum ) {
      my $tables = $tables_to_checksum{$database};
      $exit_status |= checksum_tables(
         dbh     => $main_dbh,
         db      => $database,
         tbls    => $tables,
         hosts   => \@hosts,
         slaves  => \@slaves, 
         %common_modules
      );
   }

   return $exit_status;
}

# ############################################################################
# Subroutines
# ############################################################################

sub get_all_tbls_info {
   my ( %args ) = @_;
   foreach my $arg ( qw(o dbh q tp du ch args_for) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $dbh    = $args{dbh};
   MKDEBUG && _d('Getting all schema objects');

   my $si = new SchemaIterator(
      dbh          => $dbh,
      OptionParser => $args{o},
      Quoter       => $args{q},
   );
   while ( my %schema_obj = $si->next_schema_object() ) {
      my $final_o = get_final_opts(
         %args,
         %schema_obj,
      );
      save_tbl_to_checksum(
         %args,
         %schema_obj,
         final_o => $final_o,
      );
   }

   return;
}

sub save_tbl_to_checksum {
   my ( %args ) = @_;
   foreach my $arg ( qw(q ch du final_o tp dbh db tbl du tp ch vp) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $du      = $args{du};
   my $tp      = $args{tp};
   my $ch      = $args{ch};
   my $final_o = $args{final_o};
   my $dbh     = $args{dbh};
   my $db      = $args{db};
   my $tbl     = $args{tbl};
   my $q       = $args{q};
   my $vp      = $args{vp};

   # Skip the table in which checksums are stored.
   return if ($final_o->get('replicate')
      && $final_o->get('replicate') eq "$db.$tbl");

   eval { # Catch errors caused by tables being dropped during work.

      # Parse the table and determine a column that's chunkable.  This is
      # used not only for chunking, but also for --since.
      my $create = $du->get_create_table($dbh, $q, $db, $tbl);
      my $struct = $tp->parse($create);

      # If there's a --where clause and the user didn't specify a chunk index
      # a chunk they want, then get MySQL's chosen index for the where clause
      # and make it the preferred index.
      # http://code.google.com/p/maatkit/issues/detail?id=378
      if ( $final_o->get('where')
           && !$final_o->get('chunk-column')
           && !$final_o->get('chunk-index') ) 
      {
         my ($mysql_chosen_index) = $tp->find_possible_keys(
            $dbh, $db, $tbl, $q, $final_o->get('where'));
         MKDEBUG && _d("Index chosen by MySQL for --where:",
            $mysql_chosen_index);
         $final_o->set('chunk-index', $mysql_chosen_index)
            if $mysql_chosen_index;
      }


      # Get the first chunkable column and index, taking into account
      # --chunk-column and --chunk-index.  If either of those options
      # is specified, get_first_chunkable_column() will try to satisfy
      # the request but there's no guarantee either will be selected.
      # http://code.google.com/p/maatkit/issues/detail?id=519
      my ($chunk_col, $chunk_index) = $ch->get_first_chunkable_column(
         %args,
         chunk_column => $final_o->get('chunk-column'),
         chunk_index  => $final_o->get('chunk-index'),
         tbl_struct => $struct,
      );

      my $index_hint;
      if ( $final_o->get('use-index') && $chunk_col ) {
         my $hint    = $vp->version_ge($dbh, '4.0.9') ? 'FORCE' : 'USE';
         $index_hint = "$hint INDEX (" . $q->quote($chunk_index) . ")";
      }
      MKDEBUG && _d('Index hint:', $index_hint);

      my @chunks         = '1=1'; # Default.
      my $rows_per_chunk = undef;
      my $maxval         = undef;
      if ( $final_o->get('chunk-size') ) {
         ($rows_per_chunk) = $ch->size_to_rows(
            dbh        => $dbh,
            db         => $db,
            tbl        => $tbl,
            chunk_size => $final_o->get('chunk-size'),
         );

         if ( $chunk_col ) {
            # Calculate chunks for this table.
            my %params = $ch->get_range_statistics(
               dbh        => $dbh,
               db         => $db,
               tbl        => $tbl,
               chunk_col  => $chunk_col,
               tbl_struct => $struct,
            );
            if ( !grep { !defined $params{$_} } qw(min max rows_in_range) ) {
               @chunks = $ch->calculate_chunks(
                  dbh          => $dbh,
                  db           => $db,
                  tbl          => $tbl,
                  tbl_struct   => $struct,
                  chunk_col    => $chunk_col,
                  chunk_size   => $rows_per_chunk,
                  zero_chunk   => $final_o->get('zero-chunk'),
                  chunk_range  => $final_o->get('chunk-range'),
                  %params,
               );
               $maxval = $params{max};
            }
         }
      }

      push @{ $tables_to_checksum{$db} }, {
         struct      => $struct,
         create      => $create,
         database    => $db,
         table       => $tbl,
         column      => $chunk_col,
         chunk_index => $chunk_index,
         chunk_size  => $rows_per_chunk,
         maxval      => $maxval,
         index       => $index_hint,
         chunks      => \@chunks,
         final_o     => $final_o,
      };
   };
   if ( $EVAL_ERROR ) {
      print_err($final_o, $EVAL_ERROR, $db, $tbl);
   }

   return;
}

# Checksum the tables in the given database.
# A separate report for each database and its tables is printed.
sub checksum_tables {
   my ( %args ) = @_;
   foreach my $arg ( qw(tc du o q db dbh hosts tbls) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $tc    = $args{tc};
   my $du    = $args{du};
   my $o     = $args{o};
   my $db    = $args{db};
   my $dbh   = $args{dbh};
   my $hosts = $args{hosts};
   my $tbls  = $args{tbls};
   my $q     = $args{q};

   my ($hdr, $explain);
   my $exit_status = 0;

   # NOTE: remember, you can't 'next TABLE' inside the eval{}.
   # NOTE: remember to use the final_o embedded within each $table, not $o
   foreach my $table ( @$tbls ) {
      MKDEBUG && _d("Doing", $db, '.', $table->{table});
      MKDEBUG && _d("Table:", Dumper($table));
      my $final_o  = $table->{final_o};

      my $is_chunkable_table = 1;  # table should be chunkable unless...

      # If there's a chunk size but no chunk index and unchunkable tables
      # aren't allowed (they're not by default), then table may still be
      # chunkable if it's small, i.e. total rows in table <= chunk size.
      if ( $table->{chunk_size}
           && !$table->{chunk_index}
           && !$final_o->get('unchunkable-tables') )
      {
         $is_chunkable_table = is_chunkable_table(
            dbh        => $dbh,
            db         => $db,
            tbl        => $table->{table},
            chunk_size => $table->{chunk_size},
            where      => $final_o->{where},
            Quoter     => $q,
         );
         MKDEBUG && _d("Unchunkable table small enough to chunk:",
            $is_chunkable_table ? 'yes' : 'no');
      }

      if ( !$is_chunkable_table ) {
         $exit_status |= 1;
         print "# cannot chunk $table->{database} $table->{table}\n";
      }
      else { 
         eval {
            my $do_table = 1;

            # Determine the checksum strategy for every table because it
            # might change given various --arg-table opts for each table.
            my $strat_ref;
            my ( $strat, $crc_type, $func, $opt_slice );
            if ( $checksum_table_data && $do_table ) {
               $strat_ref = determine_checksum_strat(
                  dbh => $dbh,
                  tc  => $tc,
                  o   => $final_o,
               );
               ( $strat, $crc_wid, $crc_type, $func, $opt_slice )
                  = @$strat_ref{ qw(strat crc_wid crc_type func opt_slice) };
               MKDEBUG && _d("Checksum strat:", Dumper($strat_ref));
            }
            else {
               # --schema doesn't use a checksum strategy, but do_tbl()
               # requires a strat arg.
               $strat = '--schema';
            }
            $md5sum_fmt = "%-${crc_wid}s  %s.%s.%s.%d\n";

            # Design and print header unless we are resuming in which case
            # we should have already re-printed the partial output of the
            # resume file in parse_resume_file().  This only has to be done
            # once and done here because we need $crc_wid which is determined
            # by the checksum strat above.
            if ( !$hdr ) {
               if ( $o->get('tab') ) {
                  $hdr = "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n";
                  $explain = "%s\t%s\t%s\n";
               }
               else {
                  my $max_tbl  = max(5, map { length($_->{table}) } @$tbls);
                  my $max_db   = max(8, length($db));
                  my $max_host = max(4, map { length($_->{h}) } @$hosts);
                  $hdr         = "%-${max_db}s %-${max_tbl}s %5s "
                               . "%-${max_host}s %-6s %10s %${crc_wid}s %4s %4s %4s %4s\n";
                  $explain     = "%-${max_db}s %-${max_tbl}s %s\n";
               }
               my @hdr_args = qw(DATABASE TABLE CHUNK HOST ENGINE
                                 COUNT CHECKSUM TIME WAIT STAT LAG);
               unless ( $o->get('quiet')
                        || $o->get('explain')
                        || $o->get('checksum')
                        || $o->get('resume') )
               {
                  printf($hdr, @hdr_args)
                     or die "Cannot print: $OS_ERROR";
               }
            }

            # Clean out the replication table entry for this table.
            # http://code.google.com/p/maatkit/issues/detail?id=304
            if ( (my $replicate_table = $final_o->get('replicate'))
                 && !$final_o->get('explain') ) {
               use_repl_db(%args);  # USE the proper replicate db
               my $max_chunkno = scalar @{$table->{chunks}} - 1;
               my $del_sql     = "DELETE FROM $replicate_table "
                               . "WHERE db=? AND tbl=? AND chunk > ?";
               MKDEBUG && _d($dbh, $del_sql, $db, $table->{table},$max_chunkno);
               $dbh->do($del_sql, {}, $db, $table->{table}, $max_chunkno);
            }

            # If --since is given, figure out either
            # 1) for temporal sinces, if the table has an update time and that
            #    time is newer than --since, then checksum the whole table,
            #    otherwise skip it; or
            # 2) for "numerical" sinces, which column to use: either the
            #    specified column (--sincecolumn) or the auto-discovered one,
            #    whichever exists in the table, in that order.
            # Then, if --savesince is given, save either 1) the current timestamp
            # or 2) the resulting WHERE clause.
            if ( $final_o->get('since') ) {
               if ( is_temporal($final_o->get('since')) ) {
                  MKDEBUG && _d('--since is temporal');
                  my ( $stat )
                     = $du->get_table_status($dbh, $q, $db, $table->{table});
                  my $time = $stat->{update_time};
                  if ( $time && $time lt $final_o->get('since') ) {
                     MKDEBUG && _d("Skipping table because --since value",
                        $final_o->get('since'), "is newer than", $time);
                     $do_table = 0;
                     $table->{chunks} = [];
                  }
               }
               else {
                  MKDEBUG && _d('--since is numerical');
                  # For numerical sinces, choose the column to apply --since to.
                  # It may not be the column the user said to use! If the user
                  # didn't specify a column that's good to chunk on, we'll use
                  # something else instead.

                  # $table->{column} is the first chunkable column returned from
                  # the call to get_first_chunkable_column() in
                  # save_tbl_to_checksum().
                  my ( $sincecol ) =
                     grep { $_ && $table->{struct}->{is_col}->{$_} }
                        ( $table->{column}, $final_o->get('since-column') );

                  if ( $sincecol ) {
                     MKDEBUG && _d('Column for numerical --since:',
                        $db, '.', $table->{table}, '.', $sincecol);
                     # This ends up being an additional WHERE clause.
                     $table->{since} = $q->quote($sincecol)
                        . '>=' .  $q->quote_val($final_o->get('since'));
                  }
                  else {
                     MKDEBUG && _d('No column for numerical --since for',
                        $db, '.', $table->{table});
                  }
               }
            }

            # ##################################################################
            # The query is independent of the chunk, so I make it once for every
            # one.
            # ##################################################################
            my $query;
            if ( $checksum_table_data && $do_table ) {
               $query = $tc->make_checksum_query(
                  db              => $db,
                  tbl             => $table->{table},
                  tbl_struct      => $table->{struct},
                  algorithm       => $strat,
                  function        => $func,
                  crc_wid         => $crc_wid,
                  crc_type        => $crc_type,
                  opt_slice       => $opt_slice,
                  cols            => $final_o->get('columns'),
                  sep             => $final_o->get('separator'),
                  replicate       => $final_o->get('replicate'),
                  float_precision => $final_o->get('float-precision'),
                  trim            => $final_o->get('trim'),
                  ignorecols      => $final_o->get('ignore-columns'),
               );
            }
            else { # --schema
               $query = undef;
            }

            $exit_status |= checksum_chunks(
               %args,
               tbl     => $table,
               query   => $query,
               hdr     => $hdr,
               explain => $explain,
               final_o => $final_o,
               strat   => $strat,
            );

            # Save the --since value if
            #    1) it's temporal and the tbl had changed since --since; or
            #    2) it's "numerical" and it had a chunkable or nibble-able
            #       column and it wasn't empty
            # See issues 121 and 122.
            if ( $final_o->get('save-since') && $savesince_sth ) {
               if ( is_temporal($final_o->get('since')) ) {
                  MKDEBUG && _d(
                     "Saving temporal --since value: current timestamp for",
                     $db, '.', $table->{table});
                  $savesince_sth->execute(undef,
                     $db, $table->{table});
               }
               elsif ( defined $table->{maxval} ) {
                  MKDEBUG && _d("Saving numerical --since value:",
                     $table->{maxval}, "for", $db, '.', $table->{table});
                  $savesince_sth->execute($table->{maxval},
                     $db, $table->{table});
               }
               else {
                  MKDEBUG && _d("Cannot save --since value:",
                     $table->{maxval}, "for", $db, '.', $table->{table});
               }
            }
         };
         if ( $EVAL_ERROR ) {
            print_err($o, $EVAL_ERROR, $db, $table->{table});
         }
      }  # chunkable table
   }

   return $exit_status;
}

sub checksum_chunks {
   my ( %args ) = @_;
   foreach my $arg ( qw(dp final_o ms o q db tbl hosts hdr explain) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $dp      = $args{dp};
   my $du      = $args{du};
   my $final_o = $args{final_o};
   my $ms      = $args{ms};
   my $o       = $args{o};
   my $q       = $args{q};
   my $db      = $args{db};
   my $dbh     = $args{dbh};
   my @hosts   = @{$args{hosts}};
   my $tbl     = $args{tbl}; 

   my $retry = new Retry();

   # ##################################################################
   # This loop may seem suboptimal, because it causes a new child to be
   # forked for each table, for each host, for each chunk.  It also
   # causes the program to parallelize only within the chunk; that is,
   # no two child processes are running on different chunks at a time.
   # This is by design. It lets me unlock the table on the master
   # between chunks.
   # ##################################################################
   my $exit_status     = 0;
   my $num_chunks      = scalar(@{$tbl->{chunks}});
   my $throttle_method = $o->get('throttle-method');
   MKDEBUG && _d('Checksumming', $num_chunks, 'chunks');
   CHUNK:
   foreach my $chunk_num ( 0 .. $num_chunks - 1 ) {

      if (    $final_o->get('chunk-size-limit')
           && $final_o->get('chunk-size')
           && $tbl->{chunk_size}
           && !$final_o->get('explain') )
      {
         my $is_oversize_chunk = is_oversize_chunk(
            %args,
            db         => $tbl->{database},
            tbl        => $tbl->{table},
            chunk      => $tbl->{chunks}->[$chunk_num],
            chunk_size => $tbl->{chunk_size},
            index_hint => $tbl->{index},
            where      => [$final_o->get('where'), $tbl->{since}],
            limit      => $final_o->get('chunk-size-limit'),
            Quoter     => $q,
         );
         if ( $is_oversize_chunk ) {
            $exit_status |= 1;
            if ( !$final_o->get('quiet') ) {
               if ( $final_o->get('checksum') ) {
                  printf($md5sum_fmt, 'NULL', '',
                     @{$tbl}{qw(database table)}, $chunk_num)
                     or die "Cannot print: $OS_ERROR";
               }
               else {
                  printf($args{hdr},
                     @{$tbl}{qw(database table)}, $chunk_num,
                     $hosts[0]->{h}, $tbl->{struct}->{engine}, 'OVERSIZE',
                     'NULL', 'NULL', 'NULL', 'NULL', 'NULL')
                        or die "Cannot print: $OS_ERROR";
               }
            }
            next CHUNK;
         }
      }

      if ( $throttle_method eq 'slavelag' ) {
         my $pr;
         if ( $o->get('progress') ) {
            $pr = new Progress(
               jobsize => scalar @{$args{slaves}},
               spec    => $o->get('progress'),
               name    => "Wait for slave(s) to catch up",
            );
         }
         wait_for_slaves(
            slaves         => $args{slaves},
            max_lag        => $o->get('max-lag'),
            check_interval => $o->get('check-interval'),
            DSNParser      => $dp,
            MasterSlave    => $ms,
            progress       => $pr,
         );
      }

      if (    ($num_chunks > 1 || $final_o->get('single-chunk'))
           && $checksum_table_data
           && defined $final_o->get('probability')
           && rand(100) >= $final_o->get('probability') ) {
         MKDEBUG && _d('Skipping chunk because of --probability');
         next CHUNK;
      }

      if (    $num_chunks > 1
           && $checksum_table_data
           && $final_o->get('modulo')
           && ($chunk_num % $final_o->get('modulo') != $final_o->get('offset')))
      {
         MKDEBUG && _d('Skipping chunk', $chunk_num, 'because of --modulo');
         next CHUNK;
      }

      my $chunk_start_time = gettimeofday();
      MKDEBUG && _d('Starting chunk', $chunk_num, 'at', $chunk_start_time);

      if ( $final_o->get('replicate') ) {
         # We're in --replicate mode.

         # If resuming, check if this db.tbl.chunk.host can be skipped.
         if ( $o->get('resume-replicate') ) {
            if ( already_checksummed($tbl->{database},
                                     $tbl->{table},
                                     $chunk_num,
                                     $hosts[0]->{h}) ) {
               print "# already checksummed:"
                  . " $tbl->{database}"
                  . " $tbl->{table}"
                  . " $chunk_num "
                  . $hosts[0]->{h} 
                  . "\n"
                  unless $o->get('quiet');
               next CHUNK;
            }
         }

         $hosts[0]->{dbh} ||= $dbh;

         do_tbl_replicate(
            $chunk_num,
            %args,
            host  => $hosts[0],
            retry => $retry,
         );
      }
      else {
         # We're in "normal" mode. Lock table and get position on the master.

         if ( !$final_o->get('explain') ) {
            if ( $final_o->get('lock') ) {
               my $sql = "LOCK TABLES "
                       . $q->quote($db, $tbl->{table}) . " READ";
               MKDEBUG && _d($sql);
               $dbh->do($sql);
            }
            if ( $final_o->get('wait') ) {
               $tbl->{master_status} = $ms->get_master_status($dbh);
            }
         }

         my %children;
         HOST:
         foreach my $i ( 0 .. $#hosts ) {
            my $is_master = $i == 0; # First host is assumed to be master.
            my $host      = $hosts[$i];

            # Open a single connection for each host.  Re-use the
            # connection for the master/single host.
            if ( $is_master ) {
               $dbh->{InactiveDestroy} = 1;  # Ensure that this is set.
               $host->{dbh} ||= $dbh;
            }
            else {
               $host->{dbh} ||= get_cxn($host, %args);
            }

            # If resuming, check if this db.tbl.chunk.host can be skipped.
            if ( $final_o->get('resume') ) {
               next HOST if already_checksummed($tbl->{database},
                                                $tbl->{table},
                                                $chunk_num,
                                                $host->{h});
            }

            # Fork, but only if there's more than one host.
            my $pid = @hosts > 1 ? fork() : undef;

            if ( @hosts == 1 || (defined($pid) && $pid == 0) ) {
               # Do the work (I'm a child, or there's only one host)
               
               eval {
                  do_tbl(
                     $chunk_num,
                     $is_master,
                     %args,
                     dbh  => $host->{dbh},
                     host => $host,
                  );
               };
               if ( $EVAL_ERROR ) {
                  print_err($o, $EVAL_ERROR, $db, $tbl->{table},
                            $dp->as_string($host));
                  exit(1) if @hosts > 1; # exit only if I'm a child
               }
               
               exit(0) if @hosts > 1; # exit only if I'm a child
            }
            elsif ( @hosts > 1 && !defined($pid) ) {
               die("Unable to fork!");
            }
            
            # I already exited if I'm a child, so I'm the parent.
            $children{$host->{h}} = $pid if @hosts > 1;
         }

         # Wait for the children to exit.
         foreach my $host ( keys %children ) {
            my $pid = waitpid($children{$host}, 0);
            MKDEBUG && _d("Child", $pid, "exited with", $CHILD_ERROR);
            $exit_status ||= $CHILD_ERROR >> 8;
         }
         if ( ($final_o->get('lock') && !$final_o->get('explain')) ) {
            my $sql = "UNLOCK TABLES";
            MKDEBUG && _d($dbh, $sql);
            $dbh->do($sql);
         }
      }

      my $chunk_stop_time = gettimeofday();
      MKDEBUG && _d('Finished chunk at', $chunk_stop_time);

      # --sleep between chunks.  Don't sleep if this is the last/only chunk.
      if ( $chunk_num < $num_chunks - 1 ) {
         if ( $final_o->get('sleep') && !$final_o->get('explain') ) {
            MKDEBUG && _d('Sleeping', $final_o->get('sleep'));
            sleep($final_o->get('sleep'));
         }
         elsif ( $final_o->get('sleep-coef') && !$final_o->get('explain') ) {
            my $sleep_time
               = ($chunk_stop_time - $chunk_start_time)
               * $final_o->get('sleep-coef');
            MKDEBUG && _d('Sleeping', $sleep_time);
            if ( $sleep_time < 0 ) {
               warn "Calculated invalid sleep time: "
                  . "$sleep_time = ($chunk_stop_time - $chunk_start_time) * "
                  . $final_o->get('sleep-coef')
                  . ". Sleep time set to 1 second instead.";
               $sleep_time = 1;
            }
            sleep($sleep_time);
         }
      }
   } # End foreach CHUNK

   return $exit_status;
}

# Override the command-line arguments with those from --arg-table
# if necessary.  Returns a cloned OptionParser object ($final_o).
# This clone is only a partial OptionParser object.
sub get_final_opts {
   my ( %args ) = @_;
   foreach my $arg ( qw(o dbh db tbl args_for) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $o        = $args{o};
   my $dbh      = $args{dbh};
   my $db       = $args{db};
   my $tbl      = $args{tbl};
   my $args_for = $args{args_for};

   my $final_o = $o->clone();
   if ( my $override = $args_for->{$db}->{$tbl} ) {
      map { $final_o->set($_, $override->{$_}); } keys %$override;
   }

   # --since and --offset are potentially expressions that should be
   # evaluated by the DB server. This has to be done after the override
   # from the --arg-table table.
   foreach my $opt ( qw(since offset) ) {
      # Don't get MySQL to evaluate if it's temporal, as 2008-08-01 --> 1999
      my $val = $final_o->get($opt);
      if ( $val && !is_temporal($val) ) {
         $final_o->set($opt, eval_expr($opt, $val, $dbh));
      }
   }

   return $final_o;
}

sub is_temporal {
   my ( $val ) = @_;
   return $val && $val =~ m/^\d{4}-\d{2}-\d{2}(?:.[0-9:]+)?/;
}

sub print_inconsistent_tbls {
   my ( %args ) = @_;
   foreach my $arg ( qw(o dp dsn tbls) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $o      = $args{o};
   my $dp     = $args{dp};
   my $dsn    = $args{dsn};
   my $tbls   = $args{tbls};

   return if $o->get('quiet');

   my @headers = qw(db tbl chunk cnt_diff crc_diff boundaries);
   print "Differences on " . $dp->as_string($dsn, [qw(h P F)]) . "\n";
   my $max_db   = max(5, map { length($_->{db})  } @$tbls);
   my $max_tbl  = max(5, map { length($_->{tbl}) } @$tbls);
   my $fmt      = "%-${max_db}s %-${max_tbl}s %5s %8s %8s %s\n";
   printf($fmt, map { uc } @headers) or die "Cannot print: $OS_ERROR";
   foreach my $tbl ( @$tbls ) {
      printf($fmt, @{$tbl}{@headers}) or die "Cannot print: $OS_ERROR";
   }
   print "\n" or die "Cannot print: $OS_ERROR";

   return;
}

sub save_inconsistent_tbls {
   my ( %args ) = @_;
   foreach my $arg ( qw(dbh tbls) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $dbh  = $args{dbh};
   my $tbls = $args{tbls};

   foreach my $tbl ( @$tbls ) {
      MKDEBUG && _d("Will recheck", $tbl->{db}, '.', $tbl->{tbl},
                    "(chunk:", $tbl->{boundaries}, ')');
      my $final_o = get_final_opts(
         %args,
         db  => $tbl->{db},
         tbl => $tbl->{tbl},
      );
      my $chunks = [ $tbl->{boundaries} ];
      save_tbl_to_checksum(
         %args,
         db      => $tbl->{db},
         tbl     => $tbl->{tbl},
         final_o => $final_o,
      );
   }
   return;
}

# The value may be an expression like 'NOW() - INTERVAL 7 DAY'
# and we should evaluate it.
sub eval_expr {
   my ( $name, $val, $dbh ) = @_;
   my $result = $val;
   eval {
      ($result) = $dbh->selectrow_array("SELECT $val");
      MKDEBUG && _d("option", $name, "evaluates to:", $result);
   };
   if ( $EVAL_ERROR && MKDEBUG ) {
      chomp $EVAL_ERROR;
      _d("Error evaluating option", $name, $EVAL_ERROR);
   }
   return $result;
}

sub determine_checksum_strat {
   my ( %args ) = @_;
   foreach my $arg ( qw(o dbh tc) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $o   = $args{o};
   my $dbh = $args{dbh};
   my $tc  = $args{tc};

   my $ret = {  # return vals in easy-to-swallow hash form
      strat      => undef,
      crc_type   => 'varchar',
      crc_wid    => 16,
      func       => undef,
      opt_slice  => undef,
   };

   $ret->{strat} = $tc->best_algorithm(
      algorithm   => $o->get('algorithm'),
      dbh         => $dbh,
      where       => $o->get('where') || $o->get('since'),
      chunk       => $o->get('chunk-size'),
      replicate   => $o->get('replicate'),
      count       => $o->get('count'),
   );

   if ( $o->get('algorithm') && $o->get('algorithm') ne $ret->{strat} ) {
      warn "--algorithm=".$o->get('algorithm')." can't be used; "
         . "falling back to $ret->{strat}\n";
   }

   # If using a cryptographic hash strategy, decide what hash function to use,
   # and if using BIT_XOR whether and which slice to place the user variable in.
   if ( $tc->is_hash_algorithm( $ret->{strat} ) ) {
      $ret->{func} = $tc->choose_hash_func(
         function => $o->get('function'),
         dbh      => $dbh,
      );
      if ( $o->get('function') && $o->get('function') ne $ret->{func} ) {
         warn "Checksum function ".$o->get('function')." cannot be used; "
            . "using $ret->{func}\n";
      }
      $ret->{crc_wid}    = $tc->get_crc_wid($dbh, $ret->{func});
      ($ret->{crc_type}) = $tc->get_crc_type($dbh, $ret->{func});

      if ( $o->get('optimize-xor') && $ret->{strat} eq 'BIT_XOR' ) {
         if ( $ret->{crc_type} !~ m/int$/ ) {
            $ret->{opt_slice}
               = $tc->optimize_xor(dbh => $dbh, function => $ret->{func});
            if ( !defined $ret->{opt_slice} ) {
               warn "Cannot use --optimize-xor, disabling";
               $o->set('optimize-xor', 0);
            }
         }
         else {
            # FNV_64 doesn't need the optimize_xor gizmo.
            $o->get('optimize-xor', 0);
         }
      }
   }

   return $ret;
}

sub verify_checksum_compat {
   my ( %args ) = @_;
   foreach my $arg ( qw(o hosts) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $o     = $args{o};
   my $hosts = $args{hosts};

   my @verify_sums;
   foreach my $host ( @$hosts ) {
      my $dbh = get_cxn($host, %args);
      my $sql = "SELECT MD5(CONCAT_WS(',', '1', ''))";
      MKDEBUG && _d($dbh, $sql);
      my $cks = $dbh->selectall_arrayref($sql)->[0]->[0];
      push @verify_sums, {
         host => $host->{h},
         ver  => $dbh->{mysql_serverinfo},
         sum  => $cks,
      };
   }
   if ( unique(map { $_->{sum} } @verify_sums ) > 1 ) {
      my $max = max(map { length($_->{h}) } @$hosts);
      die "Not all servers have compatible versions.  Some return different\n"
         . "checksum values for the same query, and cannot be compared.  This\n"
         . "behavior changed in MySQL 4.0.14.  Here is info on each host:\n\n"
         . join("\n",
              map { sprintf("%-${max}s %-32s %s", @{$_}{qw(host sum ver)}) }
                 { host => 'HOST', sum => 'CHECKSUM', ver => 'VERSION'},
              @verify_sums
           )
         . "\n\nYou can disable this check with --no-verify.\n";
   }
   return;
}

# Check for existence and privileges on the replication table before
# starting, and prepare the statements that will be used to update it.
# Also clean out the checksum table.  And create it if needed.
# Returns fetch and update statement handles.
sub check_repl_table {
   my ( %args ) = @_;
   foreach my $arg ( qw(o dbh tp q) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $o   = $args{o};
   my $dbh = $args{dbh};
   my $tp  = $args{tp};
   my $q   = $args{q};

   my $replicate_table = $o->get('replicate');
   return unless $replicate_table;

   use_repl_db(%args);  # USE the proper replicate db

   my ($db, $tbl) = $q->split_unquote($replicate_table);
   my $tbl_exists = $tp->check_table(
      dbh => $dbh,
      db  => $db,
      tbl => $tbl,
   );
   if ( !$tbl_exists ) {
      if ( $o->get('create-replicate-table') ) {
         create_repl_table(%args)
            or die "--create-replicate-table failed to create "
               . $replicate_table;
      }
      else {
         die  "--replicate table $replicate_table does not exist; "
            . "read the documentation or use --create-replicate-table "
            . "to create it.";
      }
   }
   else {
      MKDEBUG && _d('--replicate table', $replicate_table, 'already exists');
      # Check it again but this time check the privs.
      my $have_tbl_privs = $tp->check_table(
         dbh       => $dbh,
         db        => $db,
         tbl       => $tbl,
         all_privs => 1,
      );
      die "User does not have all necessary privileges on $replicate_table"
         unless $have_tbl_privs;
   }

   # Clean out the replicate table globally.
   if ( $o->get('empty-replicate-table') ) {
      my $del_sql = "DELETE FROM $replicate_table";
      MKDEBUG && _d($dbh, $del_sql);
      $dbh->do($del_sql);
   }

   my $fetch_sth = $dbh->prepare(
      "SELECT this_crc, this_cnt FROM $replicate_table "
      . "WHERE db = ? AND tbl = ? AND chunk = ?");
   my $update_sth = $dbh->prepare(
      "UPDATE $replicate_table SET master_crc = ?, master_cnt = ? "
      . "WHERE db = ? AND tbl = ? AND chunk = ?");

   return ($fetch_sth, $update_sth);
}

# This sub should be called before any work is done with the
# --replicate table.  It will USE the correct replicate db.
# If there's a tbl arg then its db will be used unless --replicate-database
# was specified.  A tbl arg means we're checksumming that table,
# so we've been called from do_tbl_replicate().  Other callers
# won't pass a tbl arg because they're just doing something to
# the --replicate table.
# See http://code.google.com/p/maatkit/issues/detail?id=982
sub use_repl_db {
   my ( %args ) = @_;
   my @required_args = qw(dbh o q);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $o, $q) = @args{@required_args};

   my $replicate_table = $o->get('replicate');
   return unless $replicate_table;

   # db and tbl from --replicate
   my ($db, $tbl) = $q->split_unquote($replicate_table);
   
   if ( my $tbl = $args{tbl} ) {
      # Caller is checksumming this table, USE its db unless
      # --replicate-database is in effect.
      $db = $o->get('replicate-database') ? $o->get('replicate-database')
          :                                 $tbl->{database};
   }
   else {
      # Caller is doing something just to the --replicate table.
      # Use the db from --replicate db.tbl (gotten earlier) unless
      # --replicate-database is in effect.
      $db = $o->get('replicate-database') if $o->get('replicate-database');
   }

   eval {
      my $sql = "USE " . $q->quote($db);
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   };
   if ( $EVAL_ERROR ) {
      # Report which option db really came from.
      my $opt = $o->get('replicate-database') ? "--replicate-database"
              :                                 "--replicate database";
      if ( $EVAL_ERROR =~ m/unknown database/i ) {
         die "$opt `$db` does not exist: $EVAL_ERROR";
      }
      else {
         die "Error using $opt `$db`: $EVAL_ERROR";
      }
   }

   return;
}

# Returns 1 on successful creation of the replicate table,
# or 0 on failure.
sub create_repl_table {
   my ( %args ) = @_;
   foreach my $arg ( qw(o dbh) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $o   = $args{o};
   my $dbh = $args{dbh};

   my $replicate_table = $o->get('replicate');

   my $sql = $o->read_para_after(
      __FILE__, qr/MAGIC_create_replicate/);
   $sql =~ s/CREATE TABLE checksum/CREATE TABLE $replicate_table/;
   $sql =~ s/;$//;
   MKDEBUG && _d($dbh, $sql);
   eval {
      $dbh->do($sql);
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d('--create-replicate-table failed:', $EVAL_ERROR);
      return 0;
   }

   return 1;
}

sub read_repl_table {
   my ( %args ) = @_;
   foreach my $arg ( qw(o dbh host) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $o    = $args{o};
   my $dbh  = $args{dbh};
   my $host = $args{host};

   my $replicate_table = $o->get('replicate');
   die "Cannot read replicate table because --replicate was not specified"
      unless $replicate_table;

   # Read checksums from replicate table.
   my $already_checksummed;
   my $checksums
      = $dbh->selectall_arrayref("SELECT db, tbl, chunk FROM $replicate_table");

   # Save each finished checksum.
   foreach my $checksum ( @$checksums ) {
      my ( $db, $tbl, $chunk ) = @$checksum[0..2];
      $already_checksummed->{$db}->{$tbl}->{$chunk}->{$host} = 1;
   }

   return $already_checksummed;
}

sub parse_resume_file {
   my ( $resume_file ) = @_;

   open my $resume_fh, '<', $resume_file
      or die "Cannot open resume file $resume_file: $OS_ERROR";

   # The resume file, being the output from a previous run, should
   # have the columns DATABASE TABLE CHUNK HOST ... (in that order).
   # We only need those first 4 columns. We re-print every line of
   # the resume file so the end result will be the whole, finished
   # output: what the previous run got done plus what we are about
   # to resume and finish.
   my $already_checksummed;
   while ( my $line = <$resume_fh> ) {
      # Re-print every line.
      print $line;

      # If the line is a checksum line, parse from it the db, tbl,
      # checksum and host.
      if ( $line =~ m/^\S+\s+\S+\s+\d+\s+/ ) {
         my ( $db, $tbl, $chunk, $host ) = $line =~ m/(\S+)/g;
         $already_checksummed->{$db}->{$tbl}->{$chunk}->{$host} = 1;
      }
   }

   close $resume_fh;
   MKDEBUG && _d("Already checksummed:", Dumper($already_checksummed));

   return $already_checksummed;
}

sub already_checksummed {
   my ( $d, $t, $c, $h ) = @_; # db, tbl, chunk num, host
   if ( exists $already_checksummed->{$d}->{$t}->{$c}->{$h} ) {
      MKDEBUG && _d("Skipping chunk because of --resume:", $d, $t, $c, $h);
      return 1;
   }
   return 0;
}

sub do_tbl_replicate {
   my ( $chunk_num, %args ) = @_;
   foreach my $arg ( qw(q host query tbl hdr explain final_o ch retry) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $ch      = $args{ch};
   my $final_o = $args{final_o};
   my $q       = $args{q};
   my $host    = $args{host};
   my $hdr     = $args{hdr};
   my $explain = $args{explain};
   my $tbl     = $args{tbl};
   my $retry   = $args{retry};

   MKDEBUG && _d('Replicating chunk', $chunk_num,
      'of table', $tbl->{database}, '.', $tbl->{table},
      'on', $host->{h}, ':', $host->{P});

   my $dbh = $host->{dbh};
   my $sql;

   use_repl_db(%args);  # USE the proper replicate db

   my $cnt = 'NULL';
   my $crc = 'NULL';
   my $beg = time();
   $sql    = $ch->inject_chunks(
      query      => $args{query},
      database   => $tbl->{database},
      table      => $tbl->{table},
      chunks     => $tbl->{chunks},
      chunk_num  => $chunk_num,
      where      => [$final_o->get('where'), $tbl->{since}],
      index_hint => $tbl->{index},
   );

   if ( MKDEBUG && $chunk_num == 0 ) {
      _d("SQL for inject chunk 0:", $sql);
   }

   my $where = $tbl->{chunks}->[$chunk_num];
   if ( $final_o->get('explain') ) {
      if ( $chunk_num == 0 ) {
         printf($explain, @{$tbl}{qw(database table)}, $sql)
            or die "Cannot print: $OS_ERROR";
      }
      printf($explain, @{$tbl}{qw(database table)}, $where)
         or die "Cannot print: $OS_ERROR";
      return;
   }

   # Actually run the checksum query
   $retry->retry(
      tries        => 2,
      wait         => sub { return; },
      retry_on_die => 1,
      try          => sub {
         $dbh->do('SET @crc := "", @cnt := 0 /*!50108 , '
                  . '@@binlog_format := "STATEMENT"*/');
         $dbh->do($sql, {}, @{$tbl}{qw(database table)}, $where);
         return 1;
      },
      on_failure   => sub {
         die $EVAL_ERROR;  # caught in checksum_tables()
      },
   );

   # Catch any warnings thrown....
   my $sql_warn = 'SHOW WARNINGS';
   MKDEBUG && _d($sql_warn);
   my $warnings = $dbh->selectall_arrayref($sql_warn, { Slice => {} } );
   foreach my $warning ( @$warnings ) {
      if ( $warning->{message} =~ m/Data truncated for column 'boundaries'/ ) {
         _d("Warning: WHERE clause too large for boundaries column; ",
            "mk-table-sync may fail; value:", $where);
      }
      elsif ( ($warning->{code} || 0) == 1592 ) {
         # Error: 1592 SQLSTATE: HY000  (ER_BINLOG_UNSAFE_STATEMENT)
         # Message: Statement may not be safe to log in statement format. 
         # Ignore this warning because we have purposely set statement-based
         # replication.
         MKDEBUG && _d('Ignoring warning:', $warning->{message});
      }
      else {
         # die doesn't permit extra line breaks so warn then die.
         warn "\nChecksum query caused a warning:\n"
            . join("\n",
                 map { "\t$_: " . $warning->{$_} || '' } qw(level code message)
              )
            . "\n\tquery: $sql\n\n";
         die;
      }
   }

   # Update the master_crc etc columns
   $fetch_sth->execute(@{$tbl}{qw(database table)}, $chunk_num);
   ( $crc, $cnt ) = $fetch_sth->fetchrow_array();
   $update_sth->execute($crc, $cnt, @{$tbl}{qw(database table)}, $chunk_num);

   my $end = time();
   $crc  ||= 'NULL';
   if ( !$final_o->get('quiet') && !$final_o->get('explain') ) {
      if ( $final_o->get('checksum') ) {
         printf($md5sum_fmt, $crc, $host->{h},
            @{$tbl}{qw(database table)}, $chunk_num)
            or die "Cannot print: $OS_ERROR";
      }
      else {
         printf($hdr,
            @{$tbl}{qw(database table)}, $chunk_num,
            $host->{h}, $tbl->{struct}->{engine}, $cnt, $crc,
            $end - $beg, 'NULL', 'NULL', 'NULL')
               or die "Cannot print: $OS_ERROR";
      }
   }

   return;
}

sub do_tbl {
   my ( $chunk_num, $is_master, %args ) = @_;
   foreach my $arg ( qw(du final_o ms q tc dbh host tbl hdr explain strat) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $du      = $args{du};
   my $final_o = $args{final_o};
   my $ms      = $args{ms};
   my $tc      = $args{tc};
   my $tp      = $args{tp};
   my $q       = $args{q};
   my $host    = $args{host};
   my $tbl     = $args{tbl};
   my $explain = $args{explain};
   my $hdr     = $args{hdr};
   my $strat   = $args{strat};

   MKDEBUG && _d('Checksumming chunk', $chunk_num,
      'of table', $tbl->{database}, '.', $tbl->{table},
      'on', $host->{h}, ':', $host->{P},
      'using algorithm', $strat);

   my $dbh = $host->{dbh};
   $dbh->do("USE " . $q->quote($tbl->{database}));

   my $cnt = 'NULL';
   my $crc = 'NULL';
   my $sta = 'NULL';
   my $lag = 'NULL';

   # Begin timing the checksum operation.
   my $beg = time();

   # I'm a slave.  Wait to catch up to the master.  Calculate slave lag.
   if ( !$is_master && !$final_o->get('explain') ) {
      if ( $final_o->get('wait') ) {
         MKDEBUG && _d('Waiting to catch up to master for --wait');
         my $result = $ms->wait_for_master(
            master_status => $tbl->{master_status},
            slave_dbh     => $dbh,
            timeout       => $final_o->get('wait'),
         );
         $sta = $result && defined $result->{result}
              ? $result->{result}
              : 'NULL';
      }

      if ( $final_o->get('slave-lag') ) {
         MKDEBUG && _d('Getting slave lag for --slave-lag');
         my $res = $ms->get_slave_status($dbh);
         $lag = $res && defined $res->{seconds_behind_master}
              ? $res->{seconds_behind_master}
              : 'NULL';
      }
   }

   # Time the checksum operation and the wait-for-master operation separately.
   my $mid = time();

   # Check that table exists on slave.
   my $have_table = 1;
   if ( !$is_master || !$checksum_table_data ) {
      $have_table = $tp->check_table(
         dbh => $dbh,
         db  => $tbl->{database},
         tbl => $tbl->{table},
      );
      warn "$tbl->{database}.$tbl->{table} does not exist on slave"
         . ($host->{h} ? " $host->{h}" : '')
         . ($host->{P} ? ":$host->{P}" : '')
         unless $have_table;
   }

   if ( $have_table ) {
      # Do the checksum operation.
      if ( $checksum_table_data ) {
         if ( $strat eq 'CHECKSUM' ) {
            if ( $final_o->get('crc') ) {
               $crc = do_checksum(%args);
            }
            if ( $final_o->get('count') ) {
               $cnt = do_count($chunk_num, %args);
            }
         }
         elsif ( $final_o->get('crc') ) {
            ( $cnt, $crc ) = do_var_crc($chunk_num, %args);
            $crc ||= 'NULL';
         }
         else {
            $cnt = do_count($chunk_num, %args);
         }
      }
      else { # Checksum SHOW CREATE TABLE for --schema.
         my $create
            = $du->get_create_table($dbh, $q, $tbl->{database}, $tbl->{table});
         $create = $create->[1];
         $create = $tp->remove_auto_increment($create);
         $crc    = $tc->crc32($create);
      }
   }

   my $end = time();

   if ( !$final_o->get('quiet') && !$final_o->get('explain') ) {
      if ( $final_o->get('checksum') ) {
         printf($md5sum_fmt, $crc, $host->{h},
            @{$tbl}{qw(database table)}, $chunk_num)
            or die "Cannot print: $OS_ERROR";
      }
      else {
         printf($hdr,
            @{$tbl}{qw(database table)}, $chunk_num,
            $host->{h}, $tbl->{struct}->{engine}, $cnt, $crc,
            $end - $mid, $mid - $beg, $sta, $lag)
            or die "Cannot print: $OS_ERROR";
      }
   }

   return;
}

sub get_cxn {
   my ( $dsn, %args ) = @_;
   foreach my $arg ( qw(o dp) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $dp  = $args{dp};
   my $o   = $args{o};

   if ( $o->get('ask-pass') && !defined $dsn->{p} ) {
      $dsn->{p} = OptionParser::prompt_noecho("Enter password for $dsn->{h}: ");
   }

   my $ac  = $o->get('lock') ? 0 : 1;
   my $dbh = $dp->get_dbh(
      $dp->get_cxn_params($dsn), { AutoCommit => $ac });
   $dp->fill_in_dsn($dbh, $dsn);
   $dbh->{InactiveDestroy}  = 1; # Prevent destroying on fork.
   $dbh->{FetchHashKeyName} = 'NAME_lc';
   return $dbh;
}

sub do_var_crc {
   my ( $chunk_num, %args ) = @_;
   foreach my $arg ( qw(ch dbh query tbl explain final_o) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $final_o = $args{final_o};
   my $ch      = $args{ch};
   my $tbl     = $args{tbl};
   my $explain = $args{explain};
   my $dbh     = $args{dbh};

   MKDEBUG && _d("do_var_crc for", $tbl->{table});

   my $sql = $ch->inject_chunks(
      query      => $args{query},
      database   => $tbl->{database},
      table      => $tbl->{table},
      chunks     => $tbl->{chunks},
      chunk_num  => $chunk_num,
      where      => [$final_o->get('where'), $tbl->{since}],
      index_hint => $tbl->{index},
   );

   if ( MKDEBUG && $chunk_num == 0 ) {
      _d("SQL for chunk 0:", $sql);
   }

   if ( $final_o->get('explain') ) {
      if ( $chunk_num == 0 ) {
         printf($explain, @{$tbl}{qw(database table)}, $sql)
            or die "Cannot print: $OS_ERROR";
      }
      printf($explain, @{$tbl}{qw(database table)},$tbl->{chunks}->[$chunk_num])
         or die "Cannot print: $OS_ERROR";
      return;
   }

   $dbh->do('set @crc := "", @cnt := 0');
   my $res = $dbh->selectall_arrayref($sql, { Slice => {} })->[0];
   return ($res->{cnt}, $res->{crc});
}

sub do_checksum {
   my ( %args ) = @_;
   foreach my $arg ( qw(dbh query tbl explain final_o) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $dbh     = $args{dbh};
   my $final_o = $args{final_o};
   my $tbl     = $args{tbl};
   my $query   = $args{query};
   my $explain = $args{explain};

   MKDEBUG && _d("do_checksum for", $tbl->{table});

   if ( $final_o->get('explain') ) {
      printf($explain, @{$tbl}{qw(database table)}, $query)
         or die "Cannot print: $OS_ERROR";
   }
   else {
      my $res = $dbh->selectrow_hashref($query);
      if ( $res ) {
         my ($key) = grep { m/checksum/i } keys %$res;
         return defined $res->{$key} ? $res->{$key} : 'NULL';
      }
   }

   return;
}

sub do_count {
   my ( $chunk_num, %args ) = @_;
   foreach my $arg ( qw(q dbh tbl explain final_o) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $final_o = $args{final_o};
   my $tbl     = $args{tbl};
   my $explain = $args{explain};
   my $dbh     = $args{dbh};
   my $q       = $args{q};

   MKDEBUG && _d("do_count for", $tbl->{table});

   my $sql = "SELECT COUNT(*) FROM "
      . $q->quote(@{$tbl}{qw(database table)});
   if ( $final_o->get('where') || $final_o->get('since') ) {
      my $where_since = ($final_o->get('where'), $final_o->get('since'));
      $sql .= " WHERE ("
            . join(" AND ", map { "($_)" } grep { $_ } @$where_since )
            . ")";
   }
   if ( $final_o->get('explain') ) {
      printf($explain, @{$tbl}{qw(database table)}, $sql)
         or die "Cannot print: $OS_ERROR";
   }
   else {
      return $dbh->selectall_arrayref($sql)->[0]->[0];
   }

   return;
}

sub unique {
   my %seen;
   grep { !$seen{$_}++ } @_;
}

# Tries to extract the MySQL error message and print it
sub print_err {
   my ( $o, $msg, $db, $tbl, $host ) = @_;
   return if !defined $msg
      # Honor --quiet in the (common?) event of dropped tables or deadlocks
      or ($o->get('quiet')
         && $EVAL_ERROR =~ m/: Table .*? doesn't exist|Deadlock found/);
   $msg =~ s/^.*?failed: (.*?) at \S+ line (\d+).*$/$1 at line $2/s;
   $msg =~ s/\s+/ /g;
   if ( $db && $tbl ) {
      $msg .= " while doing $db.$tbl";
   }
   if ( $host ) {
      $msg .= " on $host";
   }
   print STDERR $msg, "\n";
}

# Returns when Seconds_Behind_Master on all the given slaves
# is < max_lag, waits check_interval seconds between checks
# if a slave is lagging too much.
sub wait_for_slaves {
   my ( %args ) = @_;
   my $slaves         = $args{slaves};
   my $max_lag        = $args{max_lag};
   my $check_interval = $args{check_interval};
   my $dp             = $args{DSNParser};
   my $ms             = $args{MasterSlave};
   my $pr             = $args{progress};

   return unless scalar @$slaves;
   my $n_slaves = @$slaves;

   my $pr_callback;
   if ( $pr ) {
      # If you use the default Progress report callback, you'll need to
      # to add Transformers.pm to this tool.
      my $reported = 0;
      $pr_callback = sub {
         my ($fraction, $elapsed, $remaining, $eta, $slave_no) = @_;
         if ( !$reported ) {
            print STDERR "Waiting for slave(s) to catchup...\n";
            $reported = 1;
         }
         else {
            print STDERR "Still waiting ($elapsed seconds)...\n";
         }
         return;
      };
      $pr->set_callback($pr_callback);
   }

   for my $slave_no ( 0..($n_slaves-1) ) {
      my $slave = $slaves->[$slave_no];
      MKDEBUG && _d('Checking slave', $dp->as_string($slave->{dsn}),
         'lag for throttle');
      my $lag = $ms->get_slave_lag($slave->{dbh});
      while ( !defined $lag || $lag > $max_lag ) {
         MKDEBUG && _d('Slave lag', $lag, '>', $max_lag,
            '; sleeping', $check_interval);

         # Report what we're waiting for before we wait.
         $pr->update(sub { return $slave_no; }) if $pr;

         sleep $check_interval;
         $lag = $ms->get_slave_lag($slave->{dbh});
      }
      MKDEBUG && _d('Slave ready, lag', $lag, '<=', $max_lag);
   }

   return;
}

# Sub: is_oversize_chunk
#   Determine if the chunk is oversize.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   * dbh        - dbh
#   * db         - db name, not quoted
#   * tbl        - tbl name, not quoted
#   * chunk_size - chunk size in number of rows
#   * chunk      - chunk, e.g. "`a` > 10"
#   * limit      - oversize if rows > factor * chunk_size
#   * Quoter     - <Quoter> object
#
# Optional Arguments:
#   * where      - Arrayref of WHERE clauses added to chunk
#   * index_hint - FORCE INDEX clause
#
# Returns:
#   True if EXPLAIN rows is >= chunk_size * limit, else false
sub is_oversize_chunk {
   my ( %args ) = @_;
   my @required_args = qw(dbh db tbl chunk_size chunk limit Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $where = [$args{chunk}, $args{where} ? @{$args{where}} : ()];
   my $expl;
   eval {
      $expl = _explain(%args, where => $where);
   };
   if ( $EVAL_ERROR ) {
      # This shouldn't happen in production but happens in testing because
      # we chunk tables that don't actually exist.
      MKDEBUG && _d("Failed to EXPLAIN chunk:", $EVAL_ERROR);
      return $args{chunk};
   }
   MKDEBUG && _d("Chunk", $args{chunk}, "covers", ($expl->{rows} || 0), "rows");

   return ($expl->{rows} || 0) >= $args{chunk_size} * $args{limit} ? 1 : 0;
}

# Sub: is_chunkable_table
#   Determine if the table is chunkable.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   * dbh        - dbh
#   * db         - db name, not quoted
#   * tbl        - tbl name, not quoted
#   * chunk_size - chunk size in number of rows
#   * Quoter     - <Quoter> object
#
# Optional Arguments:
#   * where      - Arrayref of WHERE clauses added to chunk
#   * index_hint - FORCE INDEX clause
#
# Returns:
#   True if EXPLAIN rows is <= chunk_size, else false
sub is_chunkable_table {
   my ( %args ) = @_;
   my @required_args = qw(dbh db tbl chunk_size Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $expl;
   eval {
      $expl = _explain(%args);
   };
   if ( $EVAL_ERROR ) {
      # This shouldn't happen in production but happens in testing because
      # we chunk tables that don't actually exist.
      MKDEBUG && _d("Failed to EXPLAIN table:", $EVAL_ERROR);
      return;  # errr on the side of caution: not chunkable if not explainable
   }
   MKDEBUG && _d("Table has", ($expl->{rows} || 0), "rows");

   return ($expl->{rows} || 0) <= $args{chunk_size} ? 1 : 0;
}

# Sub: _explain
#   EXPLAIN a chunk or table.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   * dbh        - dbh
#   * db         - db name, not quoted
#   * tbl        - tbl name, not quoted
#   * Quoter     - <Quoter> object
#
# Optional Arguments:
#   * where      - Arrayref of WHERE clauses added to chunk
#   * index_hint - FORCE INDEX clause
#
# Returns:
#   Hashref of first EXPLAIN row
sub _explain {
   my ( %args ) = @_;
   my @required_args = qw(dbh db tbl Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db, $tbl, $q) = @args{@required_args};

   my $db_tbl = $q->quote($db, $tbl);
   my $where;
   if ( $args{where} && @{$args{where}} ) {
      $where = join(" AND ", map { "($_)" } grep { defined } @{$args{where}});
   }
   my $sql    = "EXPLAIN SELECT * FROM $db_tbl"
              . ($args{index_hint} ? " $args{index_hint}" : "")
              . ($args{where}      ? " WHERE $where"      : "");
   MKDEBUG && _d($dbh, $sql);

   my $expl = $dbh->selectrow_hashref($sql);
   return $expl;
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

# ############################################################################
# Documentation
# ############################################################################
=pod

=head1 NAME

mk-table-checksum - Perform an online replication consistency check, or
checksum MySQL tables efficiently on one or many servers.

=head1 SYNOPSIS

Usage: mk-table-checksum [OPTION...] DSN [DSN...]

mk-table-checksum checksums MySQL tables efficiently on one or more hosts.
Each host is specified as a DSN and missing values are inherited from the
first host.  If you specify multiple hosts, the first is assumed to be the
master.

STOP! Are you checksumming a slave(s) against its master?  Then be sure to learn
what L<"--replicate"> does.  It is probably the option you want to use.

   mk-table-checksum --replicate=mydb.checksum master-host
   ... time passses, replication catches up ...
   mk-table-checksum --replicate=mydb.checksum --replicate-check 2 \
      master-host

Or,

   mk-table-checksum h=host1,u=user,p=password h=host2 ...

Or,

   mk-table-checksum host1 host2 ... hostN | mk-checksum-filter

See L<"SPECIFYING HOSTS"> for more on the syntax of the host arguments.

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

mk-table-checksum executes queries that cause the MySQL server to checksum its
data.  This can cause significant server load.  It is read-only unless you use
the L<"--replicate"> option, in which case it inserts a small amount of data
into the specified table.

At the time of this release, we know of no bugs that could cause serious harm to
users.  There are miscellaneous bugs that might be annoying.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-table-checksum>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

mk-table-checksum generates table checksums for MySQL tables, typically
useful for verifying your slaves are in sync with the master.  The checksums
are generated by a query on the server, and there is very little network
traffic as a result.

Checksums typically take about twice as long as COUNT(*) on very large InnoDB
tables in my tests.  For smaller tables, COUNT(*) is a good bit faster than
the checksums.  See L<"--algorithm"> for more details on performance.

If you specify more than one server, mk-table-checksum assumes the first
server is the master and others are slaves.  Checksums are parallelized for
speed, forking off a child process for each table.  Duplicate server names are
ignored, but if you want to checksum a server against itself you can use two
different forms of the hostname (for example, "localhost 127.0.0.1", or
"h=localhost,P=3306 h=localhost,P=3307").

If you want to compare the tables in one database to those in another database
on the same server, just checksum both databases:

   mk-table-checksum --databases db1,db2

You can then use L<mk-checksum-filter> to compare the results in both databases
easily.

mk-table-checksum examines table structure only on the first host specified,
so if anything differs on the others, it won't notice.  It ignores views.

The checksums work on MySQL version 3.23.58 through 6.0-alpha.  They will not
necessarily produce the same values on all versions.  Differences in
formatting and/or space-padding between 4.1 and 5.0, for example, will cause
the checksums to be different.

=head1 SPECIFYING HOSTS

mk-table-checksum connects to a theoretically unlimited number of MySQL
servers.  You specify a list of one or more host definitions on the command
line, such as "host1 host2".  Each host definition can be just a hostname, or it
can be a complex string that specifies connection options as well.  You can
specify connection options two ways:

=over

=item *

Format a host definition in a key=value,key=value form.  If an argument on the
command line contains the letter '=', mk-table-checksum will parse it into
its component parts.  Examine the L<"--help"> output for details on the allowed
keys.

Specifying a list of simple host definitions "host1 host2" is equivalent to the
more complicated "h=host1 h=host2" format.

=item *

With the command-line options such as L<"--user"> and L<"--password">.  These
options, if given, apply globally to all host definitions.

=back

In addition to specifying connection options this way, mk-table-checksum
allows shortcuts.  Any options specified for the first host definition on the
command line fill in missing values in subsequent ones.  Any options that are
still missing after this are filled in from the command-line options if
possible.

In other words, the places you specify connection options have precedence:
highest precedence is the option specified directly in the host definition, next
is the option specified in the first host definition, and lowest is the
command-line option.

You can mix simple and complex host definitions and/or command-line arguments.
For example, if all your servers except one of your slaves uses a non-standard
port number:

   mk-table-checksum --port 4500 master h=slave1,P=3306 slave2 slave3

If you are confused about how mk-table-checksum will connect to your servers,
give the L<"--explain-hosts"> option and it will tell you.

=head1 HOW FAST IS IT?

Speed and efficiency are important, because the typical use case is checksumming
large amounts of data.

C<mk-table-checksum> is designed to do very little work itself, and generates
very little network traffic aside from inspecting table structures with C<SHOW
CREATE TABLE>.  The results of checksum queries are typically 40-character or
shorter strings.

The MySQL server does the bulk of the work, in the form of the checksum queries.
The following benchmarks show the checksum query times for various checksum
algorithms.  The first two results are simply running C<COUNT(col8)> and
C<CHECKSUM TABLE> on the table.  C<CHECKSUM TABLE> is just C<CRC32> under the
hood, but it's implemented inside the storage engine layer instead of at the
MySQL layer.

 ALGORITHM       HASH FUNCTION  EXTRA           TIME
 ==============  =============  ==============  =====
 COUNT(col8)                                    2.3
 CHECKSUM TABLE                                 5.3
 BIT_XOR         FNV_64                         12.7
 ACCUM           FNV_64                         42.4
 BIT_XOR         MD5            --optimize-xor  80.0
 ACCUM           MD5                            87.4
 BIT_XOR         SHA1           --optimize-xor  90.1
 ACCUM           SHA1                           101.3
 BIT_XOR         MD5                            172.0
 BIT_XOR         SHA1                           197.3

The tests are entirely CPU-bound.  The sample data is an InnoDB table with the
following structure:

 CREATE TABLE test (
   col1 int NOT NULL,
   col2 date NOT NULL,
   col3 int NOT NULL,
   col4 int NOT NULL,
   col5 int,
   col6 decimal(3,1),
   col7 smallint unsigned NOT NULL,
   col8 timestamp NOT NULL,
   PRIMARY KEY  (col2, col1),
   KEY (col7),
   KEY (col1)
 ) ENGINE=InnoDB

The table has 4303585 rows, 365969408 bytes of data and 173457408 bytes of
indexes.  The server is a Dell PowerEdge 1800 with dual 32-bit Xeon 2.8GHz
processors and 2GB of RAM.  The tests are fully CPU-bound, and the server is
otherwise idle.  The results are generally consistent to within a tenth of a
second on repeated runs.

C<CRC32> is the default checksum function to use, and should be enough for most
cases.  If you need stronger guarantees that your data is identical, you should
use one of the other functions.

=head1 ALGORITHM SELECTION

The L<"--algorithm"> option allows you to specify which algorithm you would
like to use, but it does not guarantee that mk-table-checksum will use this
algorithm.  mk-table-checksum will ultimately select the best algorithm possible
given various factors such as the MySQL version and other command line options.

The three basic algorithms in descending order of preference are CHECKSUM,
BIT_XOR and ACCUM.  CHECKSUM cannot be used if any one of these criteria
is true:

  * L<"--where"> is used.
  * L<"--since"> is used.
  * L<"--chunk-size"> is used.
  * L<"--replicate"> is used.
  * L<"--count"> is used.
  * MySQL version less than 4.1.1.

The BIT_XOR algorithm also requires MySQL version 4.1.1 or later.

After checking these criteria, if the requested L<"--algorithm"> remains then it
is used, otherwise the first remaining algorithm with the highest preference
is used.

=head1 CONSISTENT CHECKSUMS

If you are using this tool to verify your slaves still have the same data as the
master, which is why I wrote it, you should read this section.

The best way to do this with replication is to use the L<"--replicate"> option.
When the queries are finished running on the master and its slaves, you can go
to the slaves and issue SQL queries to see if any tables are different from the
master.  Try the following:

  SELECT db, tbl, chunk, this_cnt-master_cnt AS cnt_diff,
     this_crc <> master_crc OR ISNULL(master_crc) <> ISNULL(this_crc)
        AS crc_diff
  FROM checksum
  WHERE master_cnt <> this_cnt OR master_crc <> this_crc
     OR ISNULL(master_crc) <> ISNULL(this_crc);

The L<"--replicate-check"> option can do this query for you.  If you can't use
this method, try the following:

=over

=item *

If your servers are not being written to, you can just run the tool with no
further ado:

  mk-table-checksum server1 server2 ... serverN

=item *

If the servers are being written to, you need some way to make sure they are
consistent at the moment you run the checksums.  For situations other than
master-slave replication, you will have to figure this out yourself.  You may be
able to use the L<"--where"> option with a date or time column to only checksum
data that's not recent.

=item *

If you are checksumming a master and slaves, you can do a fast parallel
checksum and assume the slaves are caught up to the master.  In practice, this
tends to work well except for tables which are constantly updated.  You can
use the L<"--slave-lag"> option to see how far behind each slave was when it
checksummed a given table.  This can help you decide whether to investigate
further.

=item *

The next most disruptive technique is to lock the table on the master, then take
checksums.  This should prevent changes from propagating to the slaves.  You can
just lock on the master (with L<"--lock">), or you can both lock on the master
and wait on the slaves till they reach that point in the master's binlog
(L<"--wait">).  Which is better depends on your workload; only you know that.

=item *

If you decide to make the checksums on the slaves wait until they're guaranteed
to be caught up to the master, the algorithm looks like this:

 For each table,
   Master: lock table
   Master: get pos
   In parallel,
     Master: checksum
     Slave(s): wait for pos, then checksum
   End
   Master: unlock table
 End

=back

What I typically do when I'm not using the L<"--replicate"> option is simply run
the tool on all servers with no further options.  This runs fast, parallel,
non-blocking checksums simultaneously.  If there are tables that look different,
I re-run with L<"--wait">=600 on the tables in question.  This makes the tool
lock on the master as explained above.

=head1 OUTPUT

Output is to STDOUT, one line per server and table, with header lines for each
database.  I tried to make the output easy to process with awk.  For this reason
columns are always present.  If there's no value, mk-table-checksum prints
'NULL'.

The default is column-aligned output for human readability, but you can change
it to tab-separated if you want.  Use the L<"--tab"> option for this.

Output is unsorted, though all lines for one table should be output together.
For speed, all checksums are done in parallel (as much as possible) and may
complete out of the order in which they were started.  You might want to run
them through another script or command-line utility to make sure they are in the
order you want.  If you pipe the output through L<mk-checksum-filter>, you
can sort the output and/or avoid seeing output about tables that have no
differences.

The columns in the output are as follows.  The database, table, and chunk come
first so you can sort by them easily (they are the "primary key").

Output from L<"--replicate-check"> and L<"--checksum"> are different.

=over

=item DATABASE

The database the table is in.

=item TABLE

The table name.

=item CHUNK

The chunk (see L<"--chunk-size">).  Zero if you are not doing chunked checksums.

=item HOST

The server's hostname.

=item ENGINE

The table's storage engine.

=item COUNT

The table's row count, unless you specified to skip it.  If C<OVERSIZE> is
printed, the chunk was skipped because the actual number of rows was greater
than L<"--chunk-size"> times L<"--chunk-size-limit">.

=item CHECKSUM

The table's checksum, unless you specified to skip it or the table has no rows.
some types of checksums will be 0 if there are no rows; others will print NULL.

=item TIME

How long it took to checksum the C<CHUNK>, not including C<WAIT> time.
Total checksum time is C<WAIT + TIME>.

=item WAIT

How long the slave waited to catch up to its master before beginning to
checksum.  C<WAIT> is always 0 for the master.  See L<"--wait">.

=item STAT

The return value of MASTER_POS_WAIT().  C<STAT> is always C<NULL> for the
master.

=item LAG

How far the slave lags the master, as reported by SHOW SLAVE STATUS.
C<LAG> is always C<NULL> for the master.

=back

=head1 REPLICATE TABLE MAINTENANCE

If you use L<"--replicate"> to store and replicate checksums, you may need to
perform maintenance on the replicate table from time to time to remove old
checksums.  This section describes when checksums in the replicate table are
deleted automatically by mk-table-checksum and when you must manually delete
them.

Before starting, mk-table-checksum calculates chunks for each table, even
if L<"--chunk-size"> is not specified (in that case there is one chunk: "1=1").
Then, before checksumming each table, the tool deletes checksum chunks in the
replicate table greater than the current number of chunks.  For example,
if a table is chunked into 100 chunks, 0-99, then mk-table-checksum does:

  DELETE FROM replicate table WHERE db=? AND tbl=? AND chunk > 99

That removes any high-end chunks from previous runs which no longer exist.
Currently, this operation cannot be disabled.

If you use L<"--resume">, L<"--resume-replicate">, or L<"--modulo">, then
you need to be careful that the number of rows in a table does not decrease
so much that the number of chunks decreases too, else some checksum chunks may
be deleted.  The one exception is if only rows at the high end of the range
are deleted.  In that case, the high-end chunks are deleted and lower chunks
remain unchanged.  An increasing number of rows or chunks should not cause
any adverse affects.

Changing the L<"--chunk-size"> between runs with L<"--resume">,
L<"--resume-replicate">, or L<"--modulo"> can cause odd or invalid checksums.
You should not do this.  It won't work with the resume options.  With
L<"--modulo">, the safest thing to do is manually delete all the rows in
the replicate table for the table in question and start over.

If the replicate table becomes cluttered with old or invalid checksums
and the auto-delete operation is not deleting them, then you will need to
manually clean up the replicate table.  Alternatively, if you specify
L<"--empty-replicate-table">, then the tool deletes every row in the
replicate table.

=head1 EXIT STATUS

An exit status of 0 (sometimes also called a return value or return code)
indicates success.  If there is an error checksumming any table, the exit status
is 1.

When running L<"--replicate-check">, if any slave has chunks that differ from
the master, the exit status is 1.

=head1 QUERIES

If you are using innotop (see L<http://code.google.com/p/innotop>),
mytop, or another tool to watch currently running MySQL queries, you may see
the checksum queries.  They look similar to this:

  REPLACE /*test.test_tbl:'2'/'5'*/ INTO test.checksum(db, ...

Since mk-table-checksum's queries run for a long time and tend to be
textually very long, and thus won't fit on one screen of these monitoring
tools, I've been careful to place a comment at the beginning of the query so
you can see what it is and what it's doing.  The comment contains the name of
the table that's being checksummed, the chunk it is currently checksumming,
and how many chunks will be checksummed.  In the case above, it is
checksumming chunk 2 of 5 in table test.test_tbl.

=head1 OPTIONS

L<"--schema"> is restricted to option groups Connection, Filter, Output, Help, Config, Safety.

L<"--empty-replicate-table">, L<"--resume"> and L<"--resume-replicate"> are mutually exclusive.

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --algorithm

type: string

Checksum algorithm (ACCUM|CHECKSUM|BIT_XOR).

Specifies which checksum algorithm to use.  Valid arguments are CHECKSUM,
BIT_XOR and ACCUM.  The latter two do cryptographic hash checksums.
See also L<"ALGORITHM SELECTION">.

CHECKSUM is built into MySQL, but has some disadvantages.  BIT_XOR and ACCUM are
implemented by SQL queries.  They use a cryptographic hash of all columns
concatenated together with a separator, followed by a bitmap of each nullable
column that is NULL (necessary because CONCAT_WS() skips NULL columns).

CHECKSUM is the default.  This method uses MySQL's built-in CHECKSUM TABLE
command, which is a CRC32 behind the scenes.  It cannot be used before MySQL
4.1.1, and various options disable it as well.  It does not simultaneously count
rows; that requires an extra COUNT(*) query.  This is a good option when you are
using MyISAM tables with live checksums enabled; in this case both the COUNT(*)
and CHECKSUM queries will run very quickly.

The BIT_XOR algorithm is available for MySQL 4.1.1 and newer.  It uses
BIT_XOR(), which is order-independent, to reduce all the rows to a single
checksum.

ACCUM uses a user variable as an accumulator.  It reduces each row to a single
checksum, which is concatenated with the accumulator and re-checksummed.  This
technique is order-dependent.  If the table has a primary key, it will be used
to order the results for consistency; otherwise it's up to chance.

The pathological worst case is where identical rows will cancel each other out
in the BIT_XOR.  In this case you will not be able to distinguish a table full
of one value from a table full of another value.  The ACCUM algorithm will
distinguish them.

However, the ACCUM algorithm is order-dependent, so if you have two tables
with identical data but the rows are out of order, you'll get different
checksums with ACCUM.

If a given algorithm won't work for some reason, mk-table-checksum falls back to
another.  The least common denominator is ACCUM, which works on MySQL 3.23.2 and
newer.

=item --arg-table

type: string

The database.table with arguments for each table to checksum.

This table may be named anything you wish.  It must contain at least the
following columns:

  CREATE TABLE checksum_args (
     db         char(64)     NOT NULL,
     tbl        char(64)     NOT NULL,
     -- other columns as desired
     PRIMARY KEY (db, tbl)
  );

In addition to the columns shown, it may contain any of the other columns listed
here (Note: this list is used by the code, MAGIC_overridable_args):

  algorithm chunk-column chunk-index chunk-size columns count crc function lock
  modulo use-index offset optimize-xor chunk-size-limit probability separator
  save-since single-chunk since since-column sleep sleep-coef trim wait where

Each of these columns corresponds to the long form of a command-line option.
Each column should be NULL-able.  Column names with hyphens should be enclosed
in backticks (e.g. `chunk-size`) when the table is created.  The data type does
not matter, but it's suggested you use a sensible data type to prevent garbage
data.

When C<mk-table-checksum> checksums a table, it will look for a matching entry
in this table.  Any column that has a defined value will override the
corresponding command-line argument for the table being currently processed.
In this way it is possible to specify custom command-line arguments for any
table.

If you add columns to the table that aren't in the above list of allowable
columns, it's an error.  The exceptions are C<db>, C<tbl>, and C<ts>.  The C<ts>
column can be used as a timestamp for easy visibility into the last time the
C<since> column was updated with L<"--save-since">.

This table is assumed to be located on the first server given on the
command-line.

=item --ask-pass

group: Connection

Prompt for a password when connecting to MySQL.

=item --check-interval

type: time; group: Throttle; default: 1s

How often to check for slave lag if L<"--check-slave-lag"> is given.

=item --[no]check-replication-filters

default: yes; group: Safety

Do not L<"--replicate"> if any replication filters are set.  When
--replicate is specified, mk-table-checksum tries to detect slaves and look
for options that filter replication, such as binlog_ignore_db and
replicate_do_db.  If it finds any such filters, it aborts with an error.
Replication filtering makes it impossible to be sure that the checksum
queries won't break replication or simply fail to replicate.  If you are sure
that it's OK to run the checksum queries, you can negate this option to
disable the checks.  See also L<"--replicate-database">.

=item --check-slave-lag

type: DSN; group: Throttle

Pause checksumming until the specified slave's lag is less than L<"--max-lag">.

If this option is specified and L<"--throttle-method"> is set to C<slavelag>
then L<"--throttle-method"> only checks this slave.

=item --checksum

group: Output

Print checksums and table names in the style of md5sum (disables
L<"--[no]count">).

Makes the output behave more like the output of C<md5sum>.  The checksum is
first on the line, followed by the host, database, table, and chunk number,
concatenated with dots.

=item --chunk-column

type: string

Prefer this column for dividing tables into chunks.  By default,
mk-table-checksum chooses the first suitable column for each table, preferring
to use the primary key.  This option lets you specify a preferred column, which
mk-table-checksum uses if it exists in the table and is chunkable.  If not, then
mk-table-checksum will revert to its default behavior.  Be careful when using
this option; a poor choice could cause bad performance.  This is probably best
to use when you are checksumming only a single table, not an entire server.  See
also L<"--chunk-index">.

=item --chunk-index

type: string

Prefer this index for chunking tables.  By default, mk-table-checksum chooses an
appropriate index for the L<"--chunk-column"> (even if it chooses the chunk
column automatically).  This option lets you specify the index you prefer.  If
the index doesn't exist, then mk-table-checksum will fall back to its default
behavior.  mk-table-checksum adds the index to the checksum SQL statements in a
C<FORCE INDEX> clause.  Be careful when using this option; a poor choice of
index could cause bad performance.  This is probably best to use when you are
checksumming only a single table, not an entire server.

=item --chunk-range

type: string; default: open

Set which ends of the chunk range are open or closed.  Possible values are
one of MAGIC_chunk_range:

   VALUE       OPENS/CLOSES
   ==========  ======================
   open        Both ends are open
   openclosed  Low end open, high end closed

By default mk-table-checksum uses an open range of chunks like:

  `id` <  '10'
  `id` >= '10' AND < '20'
  `id` >= '20'

That range is open because the last chunk selects any row with id greater than
(or equal to) 20.  An open range can be a problem in cases where a lot of new
rows are inserted with IDs greater than 20 while mk-table-checksumming is
running because the final open-ended chunk will select all the newly inserted
rows.  (The less common case of inserting rows with IDs less than 10 would
require a C<closedopen> range but that is not currently implemented.)
Specifying C<openclosed> will cause the final chunk to be closed like:

  `id` >= '20' AND `id` <= N

N is the C<MAX(`id`)> that mk-table-checksum used when it first chunked
the rows.  Therefore, it will only chunk the range of rows that existed when
the tool started and not any newly inserted rows (unless those rows happen
to be inserted with IDs less than N).

See also L<"--chunk-size-limit">.

=item --chunk-size

type: string

Approximate number of rows or size of data to checksum at a time.  Allowable
suffixes are k, M, G. Disallows C<--algorithm CHECKSUM>.

If you specify a chunk size, mk-table-checksum will try to find an index that
will let it split the table into ranges of approximately L<"--chunk-size">
rows, based on the table's index statistics.  Currently only numeric and date
types can be chunked.

If the table is chunkable, mk-table-checksum will checksum each range separately
with parameters in the checksum query's WHERE clause.  If mk-table-checksum
cannot find a suitable index, it will do the entire table in one chunk as though
you had not specified L<"--chunk-size"> at all.  Each table is handled
individually, so some tables may be chunked and others not.

The chunks will be approximately sized, and depending on the distribution of
values in the indexed column, some chunks may be larger than the value you
specify.

If you specify a suffix (one of k, M or G), the parameter is treated as a data
size rather than a number of rows.  The output of SHOW TABLE STATUS is then used
to estimate the amount of data the table contains, and convert that to a number
of rows.

=item --chunk-size-limit

type: float; default: 2.0; group: Safety

Do not checksum chunks with this many times more rows than L<"--chunk-size">.

When L<"--chunk-size"> is given it specifies an ideal size for each chunk
of a chunkable table (in rows; size values are converted to rows).  Before
checksumming each chunk, mk-table-checksum checks how many rows are in the
chunk with EXPLAIN.  If the number of rows reported by EXPLAIN is this many
times greater than L<"--chunk-size">, then the chunk is skipped and C<OVERSIZE>
is printed for the C<COUNT> column of the L<"OUTPUT">.

For example, if you specify L<"--chunk-size"> 100 and a chunk has 150 rows,
then it is checksummed with the default L<"--chunk-size-limit"> value 2.0
because 150 is less than 100 * 2.0.  But if the chunk has 205 rows, then it
is not checksummed because 205 is greater than 100 * 2.0.

The minimum value for this option is 1 which means that no chunk can be any
larger than L<"--chunk-size">.  You probably don't want to specify 1 because
rows reported by EXPLAIN are estimates which can be greater than or less than
the real number of rows in the chunk.  If too many chunks are skipped because
they are oversize, you might want to specify a value larger than 2.

You can disable oversize chunk checking by specifying L<"--chunk-size-limit"> 0.

See also L<"--unchunkable-tables">.

=item --columns

short form: -c; type: array; group: Filter

Checksum only this comma-separated list of columns.

=item --config

type: Array; group: Config

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --[no]count

Count rows in tables.  This is built into ACCUM and BIT_XOR, but requires an
extra query for CHECKSUM.

This is disabled by default to avoid an extra COUNT(*) query when
L<"--algorithm"> is CHECKSUM.  If you have only MyISAM tables and live checksums
are enabled, both CHECKSUM and COUNT will be very fast, but otherwise you may
want to use one of the other algorithms.

=item --[no]crc

default: yes

Do a CRC (checksum) of tables.

Take the checksum of the rows as well as their count.  This is enabled by
default.  If you disable it, you'll just get COUNT(*) queries.

=item --create-replicate-table

Create the replicate table given by L<"--replicate"> if it does not exist.

Normally, if the replicate table given by L<"--replicate"> does not exist,
C<mk-table-checksum> will die. With this option, however, C<mk-table-checksum>
will create the replicate table for you, using the database.table name given to
L<"--replicate">.

The structure of the replicate table is the same as the suggested table
mentioned in L<"--replicate">. Note that since ENGINE is not specified, the
replicate table will use the server's default storage engine.  If you want to
use a different engine, you need to create the table yourself.

=item --databases

short form: -d; type: hash; group: Filter

Only checksum this comma-separated list of databases.

=item --databases-regex

type: string

Only checksum databases whose names match this Perl regex.

=item --defaults-file

short form: -F; type: string; group: Connection

Only read mysql options from the given file.  You must give an absolute
pathname.

=item --empty-replicate-table

DELETE all rows in the L<"--replicate"> table before starting.

Issues a DELETE against the table given by L<"--replicate"> before beginning
work.  Ignored if L<"--replicate"> is not specified.  This can be useful to
remove entries related to tables that no longer exist, or just to clean out the
results of a previous run.

If you want to delete entries for specific databases or tables you must
do this manually.

=item --engines

short form: -e; type: hash; group: Filter

Do only this comma-separated list of storage engines.

=item --explain

group: Output

Show, but do not execute, checksum queries (disables L<"--empty-replicate-table">).

=item --explain-hosts

group: Help

Print connection information and exit.

Print out a list of hosts to which mk-table-checksum will connect, with all
the various connection options, and exit.  See L<"SPECIFYING HOSTS">.

=item --float-precision

type: int

Precision for C<FLOAT> and C<DOUBLE> number-to-string conversion.  Causes FLOAT
and DOUBLE values to be rounded to the specified number of digits after the
decimal point, with the ROUND() function in MySQL.  This can help avoid
checksum mismatches due to different floating-point representations of the same
values on different MySQL versions and hardware.  The default is no rounding;
the values are converted to strings by the CONCAT() function, and MySQL chooses
the string representation.  If you specify a value of 2, for example, then the
values 1.008 and 1.009 will be rounded to 1.01, and will checksum as equal.

=item --function

type: string

Hash function for checksums (FNV1A_64, MURMUR_HASH, SHA1, MD5, CRC32, etc).

You can use this option to choose the cryptographic hash function used for
L<"--algorithm">=ACCUM or L<"--algorithm">=BIT_XOR.  The default is to use
C<CRC32>, but C<MD5> and C<SHA1> also work, and you can use your own function,
such as a compiled UDF, if you wish.  Whatever function you specify is run in
SQL, not in Perl, so it must be available to MySQL.

The C<FNV1A_64> UDF mentioned in the benchmarks is much faster than C<MD5>.  The
C++ source code is distributed with Maatkit.  It is very simple to compile and
install; look at the header in the source code for instructions.  If it is
installed, it is preferred over C<MD5>.  You can also use the MURMUR_HASH
function if you compile and install that as a UDF; the source is also
distributed with Maatkit, and it is faster and has better distribution
than FNV1A_64.

=item --help

group: Help

Show help and exit.

=item --ignore-columns

type: Hash; group: Filter

Ignore this comma-separated list of columns when calculating the checksum.

This option only affects the checksum when using the ACCUM or BIT_XOR
L<"--algorithm">.

=item --ignore-databases

type: Hash; group: Filter

Ignore this comma-separated list of databases.

=item --ignore-databases-regex

type: string

Ignore databases whose names match this Perl regex.

=item --ignore-engines

type: Hash; default: FEDERATED,MRG_MyISAM; group: Filter

Ignore this comma-separated list of storage engines.

=item --ignore-tables

type: Hash; group: Filter

Ignore this comma-separated list of tables.

Table names may be qualified with the database name.

=item --ignore-tables-regex

type: string

Ignore tables whose names match the Perl regex.

=item --lock

Lock on master until done on slaves (implies L<"--slave-lag">).

This option can help you to get a consistent read on a master and many slaves.
If you specify this option, mk-table-checksum will lock the table on the
first server on the command line, which it assumes to be the master.  It will
keep this lock until the checksums complete on the other servers.

This option isn't very useful by itself, so you probably want to use L<"--wait">
instead.

Note: if you're checksumming a slave against its master, you should use
L<"--replicate">.  In that case, there's no need for locking, waiting, or any of
that.

=item --max-lag

type: time; group: Throttle; default: 1s

Suspend checksumming if the slave given by L<"--check-slave-lag"> lags.

This option causes mk-table-checksum to look at the slave every time it's about
to checksum a chunk.  If the slave's lag is greater than the option's value, or
if the slave isn't running (so its lag is NULL), mk-table-checksum sleeps for
L<"--check-interval"> seconds and then looks at the lag again.  It repeats until
the slave is caught up, then proceeds to checksum the chunk.

This option is useful to let you checksum data as fast as the slaves can handle
it, assuming the slave you directed mk-table-checksum to monitor is
representative of all the slaves that may be replicating from this server.  It
should eliminate the need for L<"--sleep"> or L<"--sleep-coef">.

=item --modulo

type: int

Do only every Nth chunk on chunked tables.

This option lets you checksum only some chunks of the table.  This is a useful
alternative to L<"--probability"> when you want to be sure you get full coverage
in some specified number of runs; for example, you can do only every 7th chunk,
and then use L<"--offset"> to rotate the modulo every day of the week.

Just like with L<"--probability">, a table that cannot be chunked is done every
time.

=item --offset

type: string; default: 0

Modulo offset expression for use with L<"--modulo">.

The argument may be an SQL expression, such as C<WEEKDAY(NOW())> (which returns
a number from 0 through 6).  The argument is evaluated by MySQL.  The result is
used as follows: if chunk_num % L<"--modulo"> == L<"--offset">, the chunk will
be checksummed.

=item --[no]optimize-xor

default: yes

Optimize BIT_XOR with user variables.

This option specifies to use user variables to reduce the number of times each
row must be passed through the cryptographic hash function when you are using
the BIT_XOR algorithm.

With the optimization, the queries look like this in pseudo-code:

  SELECT CONCAT(
     BIT_XOR(SLICE_OF(@user_variable)),
     BIT_XOR(SLICE_OF(@user_variable)),
     ...
     BIT_XOR(SLICE_OF(@user_variable := HASH(col1, col2... colN))));

The exact positioning of user variables and calls to the hash function is
determined dynamically, and will vary between MySQL versions.  Without the
optimization, it looks like this:

  SELECT CONCAT(
     BIT_XOR(SLICE_OF(MD5(col1, col2... colN))),
     BIT_XOR(SLICE_OF(MD5(col1, col2... colN))),
     ...
     BIT_XOR(SLICE_OF(MD5(col1, col2... colN))));

The difference is the number of times all the columns must be mashed together
and fed through the hash function.  If you are checksumming really large
columns, such as BLOB or TEXT columns, this might make a big difference.

=item --password

short form: -p; type: string; group: Connection

Password to use when connecting.

=item --pid

type: string

Create the given PID file.  The file contains the process ID of the script.
The PID file is removed when the script exits.  Before starting, the script
checks if the PID file already exists.  If it does not, then the script creates
and writes its own PID to it.  If it does, then the script checks the following:
if the file contains a PID and a process is running with that PID, then
the script dies; or, if there is no process running with that PID, then the
script overwrites the file with its own PID and starts; else, if the file
contains no PID, then the script dies.

=item --port

short form: -P; type: int; group: Connection

Port number to use for connection.

=item --probability

type: int; default: 100

Checksums will be run with this percent probability.

This is an integer between 1 and 100.  If 100, every chunk of every table will
certainly be checksummed.  If less than that, there is a chance that some chunks
of some tables will be skipped.  This is useful for routine jobs designed to
randomly sample bits of tables without checksumming the whole server.  By
default, if a table is not chunkable, it will be checksummed every time even
when the probability is less than 100.  You can override this with
L<"--single-chunk">.

See also L<"--modulo">.

=item --progress

type: array; default: time,30

Print progress reports to STDERR.  Currently, this feature is only for when
L<"--throttle-method"> waits for slaves to catch up.

The value is a comma-separated list with two parts.  The first part can be
percentage, time, or iterations; the second part specifies how often an update
should be printed, in percentage, seconds, or number of iterations.

=item --quiet

short form: -q; group: Output

Do not print checksum results.

=item --recheck

Re-checksum chunks that L<"--replicate-check"> found to be different.

=item --recurse

type: int; group: Throttle

Number of levels to recurse in the hierarchy when discovering slaves.
Default is infinite.

See L<"--recursion-method">.

=item --recursion-method

type: string

Preferred recursion method for discovering slaves.

Possible methods are:

  METHOD       USES
  ===========  ================
  processlist  SHOW PROCESSLIST
  hosts        SHOW SLAVE HOSTS

The processlist method is preferred because SHOW SLAVE HOSTS is not reliable.
However, the hosts method is required if the server uses a non-standard
port (not 3306).  Usually mk-table-checksum does the right thing and finds
the slaves, but you may give a preferred method and it will be used first.
If it doesn't find any slaves, the other methods will be tried.

=item --replicate

type: string

Replicate checksums to slaves (disallows --algorithm CHECKSUM).

This option enables a completely different checksum strategy for a consistent,
lock-free checksum across a master and its slaves.  Instead of running the
checksum queries on each server, you run them only on the master.  You specify a
table, fully qualified in db.table format, to insert the results into.  The
checksum queries will insert directly into the table, so they will be replicated
through the binlog to the slaves.

When the queries are finished replicating, you can run a simple query on each
slave to see which tables have differences from the master.  With the
L<"--replicate-check"> option, mk-table-checksum can run the query for you to
make it even easier.  See L<"CONSISTENT CHECKSUMS"> for details.  

If you find tables that have differences, you can use the chunk boundaries in a
WHERE clause with L<mk-table-sync> to help repair them more efficiently.  See
L<mk-table-sync> for details.

The table must have at least these columns: db, tbl, chunk, boundaries,
this_crc, master_crc, this_cnt, master_cnt.  The table may be named anything you
wish.  Here is a suggested table structure, which is automatically used for
L<"--create-replicate-table"> (MAGIC_create_replicate):

  CREATE TABLE checksum (
     db         char(64)     NOT NULL,
     tbl        char(64)     NOT NULL,
     chunk      int          NOT NULL,
     boundaries char(100)    NOT NULL,
     this_crc   char(40)     NOT NULL,
     this_cnt   int          NOT NULL,
     master_crc char(40)         NULL,
     master_cnt int              NULL,
     ts         timestamp    NOT NULL,
     PRIMARY KEY (db, tbl, chunk)
  );

Be sure to choose an appropriate storage engine for the checksum table.  If you
are checksumming InnoDB tables, for instance, a deadlock will break replication
if the checksum table is non-transactional, because the transaction will still
be written to the binlog.  It will then replay without a deadlock on the
slave and break replication with "different error on master and slave."  This
is not a problem with mk-table-checksum, it's a problem with MySQL
replication, and you can read more about it in the MySQL manual.

This works only with statement-based replication (mk-table-checksum will switch
the binlog format to STATEMENT for the duration of the session if your server
uses row-based replication).  

In contrast to running the tool against multiple servers at once, using this
option eliminates the complexities of synchronizing checksum queries across
multiple servers, which normally requires locking and unlocking, waiting for
master binlog positions, and so on.  Thus, it disables L<"--lock">, L<"--wait">,
and L<"--slave-lag"> (but not L<"--check-slave-lag">, which is a way to throttle
the execution speed).

The checksum queries actually do a REPLACE into this table, so existing rows
need not be removed before running.  However, you may wish to do this anyway to
remove rows related to tables that don't exist anymore.  The
L<"--empty-replicate-table"> option does this for you.

Since the table must be qualified with a database (e.g. C<db.checksums>),
mk-table-checksum will only USE this database.  This may be important if any
replication options are set because it could affect whether or not changes
to the table are replicated.

If the slaves have any --replicate-do-X or --replicate-ignore-X options, you
should be careful not to checksum any databases or tables that exist on the
master and not the slaves.  Changes to such tables may not normally be executed
on the slaves because of the --replicate options, but the checksum queries
modify the contents of the table that stores the checksums, not the tables whose
data you are checksumming.  Therefore, these queries will be executed on the
slave, and if the table or database you're checksumming does not exist, the
queries will cause replication to fail.  For more information on replication
rules, see L<http://dev.mysql.com/doc/en/replication-rules.html>.

The table specified by L<"--replicate"> will never be checksummed itself.

=item --replicate-check

type: int

Check results in L<"--replicate"> table, to the specified depth.  You must use
this after you run the tool normally; it skips the checksum step and only checks
results.

It recursively finds differences recorded in the table given by
L<"--replicate">.  It recurses to the depth you specify: 0 is no recursion
(check only the server you specify), 1 is check the server and its slaves, 2 is
check the slaves of its slaves, and so on.

It finds differences by running the query shown in L<"CONSISTENT CHECKSUMS">,
and prints results, then exits after printing.  This is just a convenient way of
running the query so you don't have to do it manually.

The output is one informational line per slave host, followed by the results
of the query, if any.  If L<"--quiet"> is specified, there is no output.  If
there are no differences between the master and any slave, there is no output.
If any slave has chunks that differ from the master, mk-table-checksum's
exit status is 1; otherwise it is 0.

This option makes C<mk-table-checksum> look for slaves by running C<SHOW
PROCESSLIST>.  If it finds connections that appear to be from slaves, it derives
connection information for each slave with the same default-and-override method
described in L<"SPECIFYING HOSTS">.

If C<SHOW PROCESSLIST> doesn't return any rows, C<mk-table-checksum> looks at
C<SHOW SLAVE HOSTS> instead.  The host and port, and user and password if
available, from C<SHOW SLAVE HOSTS> are combined into a DSN and used as the
argument.  This requires slaves to be configured with C<report-host>,
C<report-port> and so on.

This requires the @@SERVER_ID system variable, so it works only on MySQL
3.23.26 or newer.

=item --replicate-database

type: string

C<USE> only this database with L<"--replicate">.  By default, mk-table-checksum
executes USE to set its default database to the database that contains the table
it's currently working on.  It changes its default database as it works on
different tables.  This is is a best effort to avoid problems with replication
filters such as binlog_ignore_db and replicate_ignore_db.  However, replication
filters can create a situation where there simply is no one right way to do
things.  Some statements might not be replicated, and others might cause
replication to fail on the slaves.  In such cases, it is up to the user to
specify a safe default database.  This option specifies a default database that
mk-table-checksum selects with USE, and never changes afterwards.  See also
<L"--[no]check-replication-filters">.

=item --resume

type: string

Resume checksum using given output file from a previously interrupted run.

The given output file should be the literal output from a previous run of
C<mk-table-checksum>.  For example:

   mk-table-checksum host1 host2 -C 100 > checksum_results.txt
   mk-table-checksum host1 host2 -C 100 --resume checksum_results.txt

The command line options given to the first run and the resumed run must
be identical (except, of course, for --resume).  If they are not, the result
will be unpredictable and probably wrong.

L<"--resume"> does not work with L<"--replicate">; for that, use
L<"--resume-replicate">.

=item --resume-replicate

Resume L<"--replicate">.

This option resumes a previous checksum operation using L<"--replicate">.
It is like L<"--resume"> but does not require an output file.  Instead,
it uses the checksum table given to L<"--replicate"> to determine where to
resume the checksum operation.

=item --save-since

When L<"--arg-table"> and L<"--since"> are given, save the current L<"--since">
value into that table's C<since> column after checksumming.  In this way you can
incrementally checksum tables by starting where the last one finished.

The value to be saved could be the current timestamp, or it could be the maximum
existing value of the column given by L<"--since-column">.  It depends on what
options are in effect.  See the description of L<"--since"> to see how
timestamps are different from ordinary values.

=item --schema

Checksum C<SHOW CREATE TABLE> instead of table data.

=item --separator

type: string; default: #

The separator character used for CONCAT_WS().

This character is used to join the values of columns when checksumming with
L<"--algorithm"> of BIT_XOR or ACCUM.

=item --set-vars

type: string; default: wait_timeout=10000; group: Connection

Set these MySQL variables.  Immediately after connecting to MySQL, this
string will be appended to SET and executed.

=item --since

type: string

Checksum only data newer than this value.

If the table is chunk-able or nibble-able, this value will apply to the first
column of the chunked or nibbled index.

This is not too different to L<"--where">, but instead of universally applying a
WHERE clause to every table, it selectively finds the right column to use and
applies it only if such a column is found.  See also L<"--since-column">.

The argument may be an expression, which is evaluated by MySQL.  For example,
you can specify C<CURRENT_DATE - INTERVAL 7 DAY> to get the date of one week
ago.

A special bit of extra magic: if the value is temporal (looks like a date or
datetime), then the table is checksummed only if the create time (or last
modified time, for tables that report the last modified time, such as MyISAM
tables) is newer than the value.  In this sense it's not applied as a WHERE
clause at all.

=item --since-column

type: string

The column name to be used for L<"--since">.

The default is for the tool to choose the best one automatically.  If you
specify a value, that will be used if possible; otherwise the best
auto-determined one; otherwise none.  If the column doesn't exist in the table,
it is just ignored.

=item --single-chunk

Permit skipping with L<"--probability"> if there is only one chunk.

Normally, if a table isn't split into many chunks, it will always be
checksummed regardless of L<"--probability">.  This setting lets the
probabilistic behavior apply to tables that aren't divided into chunks.

=item --slave-lag

group: Output

Report replication delay on the slaves.

If this option is enabled, the output will show how many seconds behind the
master each slave is.  This can be useful when you want a fast, parallel,
non-blocking checksum, and you know your slaves might be delayed relative to the
master.  You can inspect the results and make an educated guess whether any
discrepancies on the slave are due to replication delay instead of corrupt data.

If you're using L<"--replicate">, a slave that is delayed relative to the master
does not invalidate the correctness of the results, so this option is disabled.

=item --sleep

type: int; group: Throttle 

Sleep time between checksums.

If this option is specified, mk-table-checksum will sleep the specified
number of seconds between checksums.  That is, it will sleep between every
table, and if you specify L<"--chunk-size">, it will also sleep between chunks.

This is a very crude way to throttle checksumming; see L<"--sleep-coef"> and
L<"--check-slave-lag"> for techniques that permit greater control.

=item --sleep-coef

type: float; group: Throttle

Calculate L<"--sleep"> as a multiple of the last checksum time.

If this option is specified, mk-table-checksum will sleep the amount of
time elapsed during the previous checksum, multiplied by the specified
coefficient.  This option is ignored if L<"--sleep"> is specified.

This is a slightly more sophisticated way to throttle checksum speed: sleep a
varying amount of time between chunks, depending on how long the chunks are
taking.  Even better is to use L<"--check-slave-lag"> if you're checksumming
master/slave replication.

=item --socket

short form: -S; type: string; group: Connection

Socket file to use for connection.

=item --tab

group: Output

Print tab-separated output, not column-aligned output.

=item --tables

short form: -t; type: hash; group: Filter

Do only this comma-separated list of tables.

Table names may be qualified with the database name.

=item --tables-regex

type: string

Only checksum tables whose names match this Perl regex.

=item --throttle-method

type: string; default: none; group: Throttle

Throttle checksumming when doing L<"--replicate">.

At present there is only one method: C<slavelag>.  When L<"--replicate"> is
used, mk-table-checksum automatically sets L<"--throttle-method"> to
C<slavelag> and discovers every slave and throttles checksumming if any slave
lags more than L<"--max-lag">.  Specify C<-throttle-method none> to disable
this behavior completely, or specify L<"--check-slave-lag"> and
mk-table-checksum will only check that slave.

See also L<"--recurse"> and L<"--recursion-method">.

=item --trim

Trim C<VARCHAR> columns (helps when comparing 4.1 to >= 5.0).

This option adds a C<TRIM()> to C<VARCHAR> columns in C<BIT_XOR> and C<ACCUM>
modes.

This is useful when you don't care about the trailing space differences between
MySQL versions which vary in their handling of trailing spaces. MySQL 5.0 and 
later all retain trailing spaces in C<VARCHAR>, while previous versions would 
remove them.

=item --unchunkable-tables

group: Safety

Checksum tables that cannot be chunked when L<"--chunk-size"> is specified.

By default mk-table-checksum will not checksum a table that cannot be chunked
when L<"--chunk-size"> is specified because this might result in a huge,
non-chunkable table being checksummed in one huge, memory-intensive chunk.

Specifying this option allows checksumming tables that cannot be chunked.
Be careful when using this option!  Make sure any non-chunkable tables
are not so large that they will cause the tool to consume too much memory
or CPU.

See also L<"--chunk-size-limit">.

=item --[no]use-index

default: yes

Add FORCE INDEX hints to SQL statements.

By default C<mk-table-checksum> adds an index hint (C<FORCE INDEX> for MySQL
v4.0.9 and newer, C<USE INDEX> for older MySQL versions) to each SQL statement
to coerce MySQL into using the L<"--chunk-index"> (whether the index is
specified by the option or auto-detected).  Specifying C<--no-use-index> causes
C<mk-table-checksum> to omit index hints.

=item --user

short form: -u; type: string; group: Connection

User for login if not current user.

=item --[no]verify

default: yes

Verify checksum compatibility across servers.

This option runs a trivial checksum on all servers to ensure they have
compatible CONCAT_WS() and cryptographic hash functions.

Versions of MySQL before 4.0.14 will skip empty strings and NULLs in
CONCAT_WS, and others will only skip NULLs.  The two kinds of behavior will
produce different results if you have any columns containing the empty string
in your table.  If you know you don't (for instance, all columns are
integers), you can safely disable this check and you will get a reliable
checksum even on servers with different behavior.

=item --version

group: Help

Show version and exit.

=item --wait

short form: -w; type: time

Wait this long for slaves to catch up to their master (implies L<"--lock">
L<"--slave-lag">).

Note: the best way to verify that a slave is in sync with its master is to use
L<"--replicate"> instead.  The L<"--wait"> option is really only useful if
you're trying to compare masters and slaves without using L<"--replicate">,
which is possible but complex and less efficient in some ways.

This option helps you get a consistent checksum across a master server and its
slaves.  It combines locking and waiting to accomplish this.  First it locks the
table on the master (the first server on the command line).  Then it finds the
master's binlog position.  Checksums on slaves will be deferred until they reach
the same binlog position.

The argument to the option is the number of seconds to wait for the slaves to
catch up to the master.  It is actually the argument to MASTER_POS_WAIT().  If
the slaves don't catch up to the master within this time, they will unblock
and go ahead with the checksum.  You can tell whether this happened by
examining the STAT column in the output, which is the return value of
MASTER_POS_WAIT().

=item --where

type: string

Do only rows matching this C<WHERE> clause (disallows L<"--algorithm"> CHECKSUM).

You can use this option to limit the checksum to only part of the table.  This
is particularly useful if you have append-only tables and don't want to
constantly re-check all rows; you could run a daily job to just check
yesterday's rows, for instance.

This option is much like the -w option to mysqldump.  Do not specify the WHERE
keyword.  You may need to quote the value.  Here is an example:

  mk-table-checksum --where "foo=bar"

=item --[no]zero-chunk

default: yes

Add a chunk for rows with zero or zero-equivalent values.  The only has an
effect when L<"--chunk-size"> is specified.  The purpose of the zero chunk
is to capture a potentially large number of zero values that would imbalance
the size of the first chunk.  For example, if a lot of negative numbers were
inserted into an unsigned integer column causing them to be stored as zeros,
then these zero values are captured by the zero chunk instead of the first
chunk and all its non-zero values.

=back

=head1 DSN OPTIONS

These DSN options are used to create a DSN.  Each option is given like
C<option=value>.  The options are case-sensitive, so P and p are not the
same option.  There cannot be whitespace before or after the C<=> and
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

You need Perl, DBI, DBD::mysql, and some core packages that ought to be
installed in any reasonably new version of Perl.

=head1 BUGS

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-table-checksum>.

Please use Google Code Issues and Groups to report bugs or request support:
L<http://code.google.com/p/maatkit/>.  You can also join #maatkit on Freenode to
discuss Maatkit.

Please include the complete command-line used to reproduce the problem you are
seeing, the version of all MySQL servers involved, the complete output of the
tool when run with L<"--version">, and if possible, debugging output produced by
running with the C<MKDEBUG=1> environment variable.

=head1 COPYRIGHT, LICENSE AND WARRANTY

This program is copyright 2007-2011 Baron Schwartz.
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

=head1 SEE ALSO

See also L<mk-checksum-filter> and L<mk-table-sync>.

=head1 AUTHOR

Baron "Xaprb" Schwartz

=head1 ABOUT MAATKIT

This tool is part of Maatkit, a toolkit for power users of MySQL.  Maatkit
was created by Baron Schwartz; Baron and Daniel Nichter are the primary
code contributors.  Both are employed by Percona.  Financial support for
Maatkit development is primarily provided by Percona and its clients. 

=head1 ACKNOWLEDGMENTS

This is an incomplete list.  My apologies for omissions or misspellings.

Claus Jeppesen,
Francois Saint-Jacques,
Giuseppe Maxia,
Heikki Tuuri,
James Briggs,
Martin Friebe,
Sergey Zhuravlev,

=head1 VERSION

This manual page documents Ver 1.2.23 Distrib 7540 $Revision: 7527 $.

=cut

__END__
:endofperl
