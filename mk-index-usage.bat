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

# This program is copyright 2010-2011 Percona Inc.
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

our $VERSION = '0.9.4';
our $DISTRIB = '7540';
our $SVN_REV = sprintf("%d", (q$Revision: 7477 $ =~ m/(\d+)/g, 0));

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
# PodParser package 7053
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/PodParser.pm
#   trunk/common/t/PodParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package PodParser;


use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

my %parse_items_from = (
   'OPTIONS'     => 1,
   'DSN OPTIONS' => 1,
   'RULES'       => 1,
);

my %item_pattern_for = (
   'OPTIONS'     => qr/--(.*)/,
   'DSN OPTIONS' => qr/\* (.)/,
   'RULES'       => qr/(.*)/,
);

my %section_has_rules = (
   'OPTIONS'     => 1,
   'DSN OPTIONS' => 0,
   'RULES'       => 0,
);

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      current_section => '',
      current_item    => '',
      in_list         => 0,
      items           => {},  # keyed off SECTION
      magic           => {},  # keyed off SECTION->magic ident (without MAGIC_)
      magic_ident     => '',  # set when next para is a magic para
   };
   return bless $self, $class;
}
 
sub get_items {
   my ( $self, $section ) = @_;
   return $section ? $self->{items}->{$section} : $self->{items};
}

sub get_magic {
   my ( $self, $section ) = @_;
   return $section ? $self->{magic}->{$section} : $self->{magic};
}

sub parse_from_file {
   my ( $self, $file ) = @_;
   return unless $file;

   open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
   local $INPUT_RECORD_SEPARATOR = '';  # read paragraphs
   my $para;

   1 while defined($para = <$fh>) && $para !~ m/^=pod/;
   die "$file does not contain =pod" unless $para;

   while ( defined($para = <$fh>) && $para !~ m/^=cut/ ) {
      if ( $para =~ m/^=(head|item|over|back)/ ) {
         my ($cmd, $name) = $para =~ m/^=(\w+)(?:\s+(.+))?/;
         $name ||= '';
         MKDEBUG && _d('cmd:', $cmd, 'name:', $name);
         $self->command($cmd, $name);
      }
      else {
         $self->textblock($para);
      }
   }

   close $fh;
}

sub command {
   my ( $self, $cmd, $name ) = @_;
   
   $name =~ s/\s+\Z//m;  # Remove \n and blank line after name.
   
   if  ( $cmd eq 'head1' && $parse_items_from{$name} ) {
      MKDEBUG && _d('In section', $name);
      $self->{current_section} = $name;
      $self->{items}->{$name}  = {};
   }
   elsif ( $cmd eq 'over' ) {
      MKDEBUG && _d('Start items in', $self->{current_section});
      $self->{in_list} = 1;
   }
   elsif ( $cmd eq 'item' ) {
      my $pat = $item_pattern_for{ $self->{current_section} };
      my ($item) = $name =~ m/$pat/;
      if ( $item ) {
         MKDEBUG && _d($self->{current_section}, 'item:', $item);
         $self->{items}->{ $self->{current_section} }->{$item} = {
            desc => '',  # every item should have a desc
         };
         $self->{current_item} = $item;
      }
      else {
         warn "Item $name does not match $pat";
      }
   }
   elsif ( $cmd eq '=back' ) {
      MKDEBUG && _d('End items');
      $self->{in_list} = 0;
   }
   else {
      $self->{current_section} = '';
      $self->{in_list}         = 0;
   }
   
   return;
}

sub textblock {
   my ( $self, $para ) = @_;

   return unless $self->{current_section} && $self->{current_item};

   my $section = $self->{current_section};
   my $item    = $self->{items}->{$section}->{ $self->{current_item} };

   $para =~ s/\s+\Z//;

   if ( $para =~ m/^[a-z]\w+[:;] / ) {
      MKDEBUG && _d('Item attributes:', $para);
      map {
         my ($attrib, $val) = split(/: /, $_);
         $item->{$attrib} = defined $val ? $val : 1;
      } split(/; /, $para);
   }
   else {
      if ( $self->{magic_ident} ) {

         my ($leading_space) = $para =~ m/^(\s+)/;
         my $indent          = length($leading_space || '');
         if ( $indent ) {
            $para =~ s/^\s{$indent}//mg;
            $para =~ s/\s+$//;
            MKDEBUG && _d("MAGIC", $self->{magic_ident}, "para:", $para);
            $self->{magic}->{$self->{current_section}}->{$self->{magic_ident}}
               = $para;
         }
         else {
            MKDEBUG && _d("MAGIC", $self->{magic_ident},
               "para is not indented; treating as normal para");
         }

         $self->{magic_ident} = '';  # must unset this!
      }

      MKDEBUG && _d('Item desc:', substr($para, 0, 40),
         length($para) > 40 ? '...' : '');
      $para =~ s/\n+/ /g;
      $item->{desc} .= $para;

      if ( $para =~ m/MAGIC_(\w+)/ ) {
         $self->{magic_ident} = $1;  # XXX
         MKDEBUG && _d("MAGIC", $self->{magic_ident}, "follows");
      }
   }

   return;
}

sub verbatim {
   my ( $self, $para ) = @_;
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
# End PodParser package
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
# SlowLogParser package 7096
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
# SchemaIterator package 7141
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/SchemaIterator.pm
#   trunk/common/t/SchemaIterator.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package SchemaIterator;

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
   foreach my $arg ( qw(Quoter) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
      filter => undef,
      dbs    => [],
   };
   return bless $self, $class;
}

sub make_filter {
   my ( $self, $o ) = @_;
   my @lines = (
      'sub {',
      '   my ( $dbh, $db, $tbl ) = @_;',
      '   my $engine = undef;',
   );


   my @permit_dbs = _make_filter('unless', '$db', $o->get('databases'))
      if $o->has('databases');
   my @reject_dbs = _make_filter('if', '$db', $o->get('ignore-databases'))
      if $o->has('ignore-databases');
   my @dbs_regex;
   if ( $o->has('databases-regex') && (my $p = $o->get('databases-regex')) ) {
      push @dbs_regex, "      return 0 unless \$db && (\$db =~ m/$p/o);";
   }
   my @reject_dbs_regex;
   if ( $o->has('ignore-databases-regex')
        && (my $p = $o->get('ignore-databases-regex')) ) {
      push @reject_dbs_regex, "      return 0 if \$db && (\$db =~ m/$p/o);";
   }
   if ( @permit_dbs || @reject_dbs || @dbs_regex || @reject_dbs_regex ) {
      push @lines,
         '   if ( $db ) {',
            (@permit_dbs        ? @permit_dbs       : ()),
            (@reject_dbs        ? @reject_dbs       : ()),
            (@dbs_regex         ? @dbs_regex        : ()),
            (@reject_dbs_regex  ? @reject_dbs_regex : ()),
         '   }';
   }

   if ( $o->has('tables') || $o->has('ignore-tables')
        || $o->has('ignore-tables-regex') ) {

      my $have_qtbl       = 0;
      my $have_only_qtbls = 0;
      my %qtbls;

      my @permit_tbls;
      my @permit_qtbls;
      my %permit_qtbls;
      if ( $o->get('tables') ) {
         my %tbls;
         map {
            if ( $_ =~ m/\./ ) {
               $permit_qtbls{$_} = 1;
            }
            else {
               $tbls{$_} = 1;
            }
         } keys %{ $o->get('tables') };
         @permit_tbls  = _make_filter('unless', '$tbl', \%tbls);
         @permit_qtbls = _make_filter('unless', '$qtbl', \%permit_qtbls);

         if ( @permit_qtbls ) {
            push @lines,
               '   my $qtbl   = ($db ? "$db." : "") . ($tbl ? $tbl : "");';
            $have_qtbl = 1;
         }
      }

      my @reject_tbls;
      my @reject_qtbls;
      my %reject_qtbls;
      if ( $o->get('ignore-tables') ) {
         my %tbls;
         map {
            if ( $_ =~ m/\./ ) {
               $reject_qtbls{$_} = 1;
            }
            else {
               $tbls{$_} = 1;
            }
         } keys %{ $o->get('ignore-tables') };
         @reject_tbls= _make_filter('if', '$tbl', \%tbls);
         @reject_qtbls = _make_filter('if', '$qtbl', \%reject_qtbls);

         if ( @reject_qtbls && !$have_qtbl ) {
            push @lines,
               '   my $qtbl   = ($db ? "$db." : "") . ($tbl ? $tbl : "");';
         }
      }

      if ( keys %permit_qtbls  && !@permit_dbs ) {
         my $dbs = {};
         map {
            my ($db, undef) = split(/\./, $_);
            $dbs->{$db} = 1;
         } keys %permit_qtbls;
         MKDEBUG && _d('Adding restriction "--databases',
               (join(',', keys %$dbs) . '"'));
         if ( keys %$dbs ) {
            $o->set('databases', $dbs);
            return $self->make_filter($o);
         }
      }

      my @tbls_regex;
      if ( $o->has('tables-regex') && (my $p = $o->get('tables-regex')) ) {
         push @tbls_regex, "      return 0 unless \$tbl && (\$tbl =~ m/$p/o);";
      }
      my @reject_tbls_regex;
      if ( $o->has('ignore-tables-regex')
           && (my $p = $o->get('ignore-tables-regex')) ) {
         push @reject_tbls_regex,
            "      return 0 if \$tbl && (\$tbl =~ m/$p/o);";
      }

      my @get_eng;
      my @permit_engs;
      my @reject_engs;
      if ( ($o->has('engines') && $o->get('engines'))
           || ($o->has('ignore-engines') && $o->get('ignore-engines')) ) {
         push @get_eng,
            '      my $sql = "SHOW TABLE STATUS "',
            '              . ($db ? "FROM `$db`" : "")',
            '              . " LIKE \'$tbl\'";',
            '      MKDEBUG && _d($sql);',
            '      eval {',
            '         $engine = $dbh->selectrow_hashref($sql)->{engine};',
            '      };',
            '      MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);',
            '      MKDEBUG && _d($tbl, "uses engine", $engine);',
            '      $engine = lc $engine if $engine;',
         @permit_engs
            = _make_filter('unless', '$engine', $o->get('engines'), 1);
         @reject_engs
            = _make_filter('if', '$engine', $o->get('ignore-engines'), 1)
      }

      if ( @permit_tbls || @permit_qtbls || @reject_tbls || @tbls_regex
           || @reject_tbls_regex || @permit_engs || @reject_engs ) {
         push @lines,
            '   if ( $tbl ) {',
               (@permit_tbls       ? @permit_tbls        : ()),
               (@reject_tbls       ? @reject_tbls        : ()),
               (@tbls_regex        ? @tbls_regex         : ()),
               (@reject_tbls_regex ? @reject_tbls_regex  : ()),
               (@permit_qtbls      ? @permit_qtbls       : ()),
               (@reject_qtbls      ? @reject_qtbls       : ()),
               (@get_eng           ? @get_eng            : ()),
               (@permit_engs       ? @permit_engs        : ()),
               (@reject_engs       ? @reject_engs        : ()),
            '   }';
      }
   }

   push @lines,
      '   MKDEBUG && _d(\'Passes filters:\', $db, $tbl, $engine, $dbh);',
      '   return 1;',  '}';

   my $code = join("\n", @lines);
   MKDEBUG && _d('filter sub:', $code);
   my $filter_sub= eval $code
      or die "Error compiling subroutine code:\n$code\n$EVAL_ERROR";

   return $filter_sub;
}

sub set_filter {
   my ( $self, $filter_sub ) = @_;
   $self->{filter} = $filter_sub;
   MKDEBUG && _d('Set filter sub');
   return;
}

sub get_db_itr {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh) = @args{@required_args};

   my $filter = $self->{filter};
   my @dbs;
   eval {
      my $sql = 'SHOW DATABASES';
      MKDEBUG && _d($sql);
      @dbs =  grep {
         my $ok = $filter ? $filter->($dbh, $_, undef) : 1;
         $ok = 0 if $_ =~ m/information_schema|performance_schema|lost\+found/;
         $ok;
      } @{ $dbh->selectcol_arrayref($sql) };
      MKDEBUG && _d('Found', scalar @dbs, 'databases');
   };

   MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
   my $iterator = sub {
      return shift @dbs;
   };

   if (wantarray) {
      return ($iterator, scalar @dbs);
   }
   else {
      return $iterator;
   }
}

sub get_tbl_itr {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dbh, $db, $views) = @args{@required_args, 'views'};

   my $filter = $self->{filter};
   my @tbls;
   if ( $db ) {
      eval {
         my $sql = 'SHOW /*!50002 FULL*/ TABLES FROM '
                 . $self->{Quoter}->quote($db);
         MKDEBUG && _d($sql);
         @tbls = map {
            $_->[0]
         }
         grep {
            my ($tbl, $type) = @$_;
            my $ok = $filter ? $filter->($dbh, $db, $tbl) : 1;
            if ( !$views ) {
               $ok = 0 if ($type || '') eq 'VIEW';
            }
            $ok;
         }
         @{ $dbh->selectall_arrayref($sql) };
         MKDEBUG && _d('Found', scalar @tbls, 'tables in', $db);
      };
      MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
   }
   else {
      MKDEBUG && _d('No db given so no tables');
   }

   my $iterator = sub {
      return shift @tbls;
   };

   if ( wantarray ) {
      return ($iterator, scalar @tbls);
   }
   else {
      return $iterator;
   }
}

sub _make_filter {
   my ( $cond, $var_name, $objs, $lc ) = @_;
   my @lines;
   if ( scalar keys %$objs ) {
      my $test = join(' || ',
         map { "$var_name eq '" . ($lc ? lc $_ : $_) ."'" } keys %$objs);
      push @lines, "      return 0 $cond $var_name && ($test);",
   }
   return @lines;
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
# End SchemaIterator package
# ###########################################################################

# ###########################################################################
# FileIterator package 7096
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/FileIterator.pm
#   trunk/common/t/FileIterator.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package FileIterator;

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
   my $self = {
      %args,
   };
   return bless $self, $class;
}

sub get_file_itr {
   my ( $self, @filenames ) = @_;

   my @final_filenames;
   FILENAME:
   foreach my $fn ( @filenames ) {
      if ( !defined $fn ) {
         warn "Skipping undefined filename";
         next FILENAME;
      }
      if ( $fn ne '-' ) {
         if ( !-e $fn || !-r $fn ) {
            warn "$fn does not exist or is not readable";
            next FILENAME;
         }
      }
      push @final_filenames, $fn;
   }

   if ( !@filenames ) {
      push @final_filenames, '-';
      MKDEBUG && _d('Auto-adding "-" to the list of filenames');
   }

   MKDEBUG && _d('Final filenames:', @final_filenames);
   return sub {
      while ( @final_filenames ) {
         my $fn = shift @final_filenames;
         MKDEBUG && _d('Filename:', $fn);
         if ( $fn eq '-' ) { # Magical STDIN filename.
            return (*STDIN, undef, undef);
         }
         open my $fh, '<', $fn or warn "Cannot open $fn: $OS_ERROR";
         if ( $fh ) {
            return ( $fh, $fn, -s $fn );
         }
      }
      return (); # Avoids $f being set to 0 in list context.
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
# End FileIterator package
# ###########################################################################

# ###########################################################################
# ExplainAnalyzer package 7096
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/ExplainAnalyzer.pm
#   trunk/common/t/ExplainAnalyzer.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package ExplainAnalyzer;

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
   foreach my $arg ( qw(QueryRewriter QueryParser) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my $self = {
      %args,
   };
   return bless $self, $class;
}

sub explain_query {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(dbh query) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($query, $dbh) = @args{qw(query dbh)};
   $query = $self->{QueryRewriter}->convert_to_select($query);
   if ( $query !~ m/^\s*select/i ) {
      MKDEBUG && _d("Cannot EXPLAIN non-SELECT query:",
         (length $query <= 100 ? $query : substr($query, 0, 100) . "..."));
      return;
   }
   my $sql = "EXPLAIN $query";
   MKDEBUG && _d($dbh, $sql);
   my $explain = $dbh->selectall_arrayref($sql, { Slice => {} });
   MKDEBUG && _d("Result of EXPLAIN:", Dumper($explain));
   return $explain;
}

sub normalize {
   my ( $self, $explain ) = @_;
   my @result; # Don't modify the input.

   foreach my $row ( @$explain ) {
      $row = { %$row }; # Make a copy -- don't modify the input.

      foreach my $col ( qw(key possible_keys key_len ref) ) {
         $row->{$col} = [ split(/,/, $row->{$col} || '') ];
      }

      $row->{Extra} = {
         map {
            my $var = $_;

            if ( my ($key, $vals) = $var =~ m/(Using union)\(([^)]+)\)/ ) {
               $key => [ split(/,/, $vals) ];
            }

            else {
               $var => 1;
            }
         }
         split(/; /, $row->{Extra} || '') # Split on semicolons.
      };

      push @result, $row;
   }

   return \@result;
}

sub get_alternate_indexes {
   my ( $self, $keys, $possible_keys ) = @_;
   my %used = map { $_ => 1 } @$keys;
   return [ grep { !$used{$_} } @$possible_keys ];
}

sub get_index_usage {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(query explain) ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($query, $explain) = @args{qw(query explain)};
   my @result;

   my $lookup = $self->{QueryParser}->get_aliases($query);

   foreach my $row ( @$explain ) {

      next if !defined $row->{table}
         || $row->{table} =~ m/^<(derived|union)\d/;

      my $table = $lookup->{TABLE}->{$row->{table}} || $row->{table};
      my $db    = $lookup->{DATABASE}->{$table}     || $args{db};
      push @result, {
         db  => $db,
         tbl => $table,
         idx => $row->{key},
         alt => $self->get_alternate_indexes(
                  $row->{key}, $row->{possible_keys}),
      };
   }

   MKDEBUG && _d("Index usage for",
      (length $query <= 100 ? $query : substr($query, 0, 100) . "..."),
      ":", Dumper(\@result));
   return \@result;
}

sub get_usage_for {
   my ( $self, $checksum, $db ) = @_;
   die "I need a checksum and db" unless defined $checksum && defined $db;
   my $usage;
   if ( exists $self->{usage}->{$db} # Don't auto-vivify
     && exists $self->{usage}->{$db}->{$checksum} )
   {
      $usage = $self->{usage}->{$db}->{$checksum};
   }
   MKDEBUG && _d("Usage for",
      (length $checksum <= 100 ? $checksum : substr($checksum, 0, 100) . "..."),
      "on", $db, ":", Dumper($usage));
   return $usage;
}

sub save_usage_for {
   my ( $self, $checksum, $db, $usage ) = @_;
   die "I need a checksum and db" unless defined $checksum && defined $db;
   $self->{usage}->{$db}->{$checksum} = $usage;
}

sub fingerprint {
   my ( $self, %args ) = @_;
   my @required_args = qw(explain);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($explain) = @args{@required_args};
}

sub sparkline {
   my ( $self, %args ) = @_;
   my @required_args = qw(explain);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($explain) = @args{@required_args};
   MKDEBUG && _d("Making sparkline for", Dumper($explain));

   my $access_code = {
      'ALL'             => 'a',
      'const'           => 'c',
      'eq_ref'          => 'e',
      'fulltext'        => 'f',
      'index'           => 'i',
      'index_merge'     => 'm',
      'range'           => 'n',
      'ref_or_null'     => 'o',
      'ref'             => 'r',
      'system'          => 's',
      'unique_subquery' => 'u',
   };

   my $sparkline = '';
   my ($T, $F);  # Using temporary, Using filesort

   foreach my $tbl ( @$explain ) {
      my $code;
      if ( defined $tbl->{type} ) {
         $code = $access_code->{$tbl->{type}} || "?";
         $code = uc $code if $tbl->{Extra}->{'Using index'};
      }
      else {
         $code = '-'
      };
      $sparkline .= $code;

      $T = 1 if $tbl->{Extra}->{'Using temporary'};
      $F = 1 if $tbl->{Extra}->{'Using filesort'};
   }

   if ( $T || $F ) {
      if (    $explain->[-1]->{Extra}->{'Using temporary'}
           || $explain->[-1]->{Extra}->{'Using filesort'} ) {
         $sparkline .= ">" . ($T ? "T" : "") . ($F ? "F" : "");
      }
      else {
         $sparkline = ($T ? "T" : "") . ($F ? "F" : "") . ">$sparkline";
      }
   }

   MKDEBUG && _d("sparkline:", $sparkline);
   return $sparkline;
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
# End ExplainAnalyzer package
# ###########################################################################

# ###########################################################################
# IndexUsage package 7096
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/IndexUsage.pm
#   trunk/common/t/IndexUsage.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package IndexUsage;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
 
   my $self = {
      %args,
      tables_for      => {}, # Keyed off db
      indexes_for     => {}, # Keyed off db->tbl
      queries         => {}, # Keyed off query id
      index_usage     => {}, # Keyed off query id->db->tbl
      alt_index_usage => {}, # Keyed off query id->db->tbl->index
   };

   return bless $self, $class;
}

sub add_indexes {
   my ( $self, %args ) = @_;
   my @required_args = qw(db tbl indexes);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($db, $tbl, $indexes) = @args{@required_args};

   $self->{tables_for}->{$db}->{$tbl}  = 0;  # usage cnt, zero until used
   $self->{indexes_for}->{$db}->{$tbl} = $indexes;
   foreach my $index ( keys %$indexes ) {
      $indexes->{$index}->{cnt} = 0;
   }

   return;
}

sub add_query {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_id fingerprint sample);
   foreach my $arg ( @required_args  ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($query_id, $fingerprint, $sample) = @args{@required_args};

   $self->{queries}->{$query_id} = {
      fingerprint => $fingerprint,
      sample      => $sample,
   };

   return;
}

sub add_table_usage {
   my ( $self, $db, $tbl ) = @_;
   die "I need a db and table" unless defined $db && defined $tbl;
   ++$self->{tables_for}->{$db}->{$tbl};
   return;
}

sub add_index_usage {
   my ( $self, %args ) = @_;
   my @required_args = qw(usage);
   foreach my $arg ( @required_args  ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($usage) = @args{@required_args};

   foreach my $access ( @$usage ) {
      my ($db, $tbl, $idx, $alt) = @{$access}{qw(db tbl idx alt)};
      foreach my $index ( @$idx ) {
         $self->{indexes_for}->{$db}->{$tbl}->{$index}->{cnt}++;

         if ( my $query_id = $args{query_id} ) {
            $self->{index_usage}->{$query_id}->{$db}->{$tbl}->{$index}++;
            foreach my $alt_index ( @$alt ) {
               $self->{alt_index_usage}->{$query_id}->{$db}->{$tbl}->{$index}->{$alt_index}++;
            }
         }

      } # INDEX
   } # ACCESS

   return;
}

sub find_unused_indexes {
   my ( $self, $callback ) = @_;
   die "I need a callback" unless $callback;
   MKDEBUG && _d("Finding unused indexes");

   DATABASE:
   foreach my $db ( sort keys %{$self->{indexes_for}} ) {
      TABLE:
      foreach my $tbl ( sort keys %{$self->{indexes_for}->{$db}} ) {
         next TABLE unless $self->{tables_for}->{$db}->{$tbl}; # Skip unused
         my $indexes = $self->{indexes_for}->{$db}->{$tbl};
         my @unused_indexes;
         foreach my $index ( sort keys %$indexes ) {
            if ( !$indexes->{$index}->{cnt} ) { # count of times accessed/used
               push @unused_indexes, $indexes->{$index};
            }
         }

         if ( @unused_indexes ) {
            $callback->(
               {  db  => $db,
                  tbl => $tbl,
                  idx => \@unused_indexes,
               }
            );
         }
      } # TABLE
   } # DATABASE

   return;
}

sub save_results {
   my ( $self, %args ) = @_;
   my @required_args = qw(dbh db);
   foreach my $arg ( @required_args  ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($dbh, $db) = @args{@required_args};
   MKDEBUG && _d("Saving results to tables in database", $db);

   MKDEBUG && _d("Saving index data");
   my $insert_index_sth = $dbh->prepare(
      "INSERT INTO `$db`.`indexes` (db, tbl, idx, cnt) VALUES (?, ?, ?, ?) "
      . "ON DUPLICATE KEY UPDATE cnt = cnt + ?");
   foreach my $db ( keys %{$self->{indexes_for}} ) {
      foreach my $tbl ( keys %{$self->{indexes_for}->{$db}} ) {
         foreach my $index ( keys %{$self->{indexes_for}->{$db}->{$tbl}} ) {
            my $cnt = $self->{indexes_for}->{$db}->{$tbl}->{$index}->{cnt};
            $insert_index_sth->execute($db, $tbl, $index, $cnt, $cnt);
         }
      }
   }

   MKDEBUG && _d("Saving table data");
   my $insert_tbl_sth = $dbh->prepare(
      "INSERT INTO `$db`.`tables` (db, tbl, cnt) VALUES (?, ?, ?) "
      . "ON DUPLICATE KEY UPDATE cnt = cnt + ?");
   foreach my $db ( keys %{$self->{tables_for}} ) {
      foreach my $tbl ( keys %{$self->{tables_for}->{$db}} ) {
         my $cnt = $self->{tables_for}->{$db}->{$tbl};
         $insert_tbl_sth->execute($db, $tbl, $cnt, $cnt);
      }
   }

   MKDEBUG && _d("Save query data");
   my $insert_query_sth = $dbh->prepare(
      "INSERT IGNORE INTO `$db`.`queries` (query_id, fingerprint, sample) "
      . " VALUES (CONV(?, 16, 10), ?, ?)");
   foreach my $query_id ( keys %{$self->{queries}} ) {
      my $query = $self->{queries}->{$query_id};
      $insert_query_sth->execute(
         $query_id, $query->{fingerprint}, $query->{sample});
   }

   MKDEBUG && _d("Saving index usage data");
   my $insert_index_usage_sth = $dbh->prepare(
      "INSERT INTO `$db`.`index_usage` (query_id, db, tbl, idx, cnt) "
      . "VALUES (CONV(?, 16, 10), ?, ?, ?, ?) "
      . "ON DUPLICATE KEY UPDATE cnt = cnt + ?");
   foreach my $query_id ( keys %{$self->{index_usage}} ) {
      foreach my $db ( keys %{$self->{index_usage}->{$query_id}} ) {
         foreach my $tbl ( keys %{$self->{index_usage}->{$query_id}->{$db}} ) {
            my $indexes = $self->{index_usage}->{$query_id}->{$db}->{$tbl};
            foreach my $index ( keys %$indexes ) {
               my $cnt = $indexes->{$index};
               $insert_index_usage_sth->execute(
                  $query_id, $db, $tbl, $index, $cnt, $cnt);
            }
         }
      }
   }

   MKDEBUG && _d("Saving alternate index usage data");
   my $insert_index_alt_sth = $dbh->prepare(
      "INSERT INTO `$db`.`index_alternatives` "
      . "(query_id, db, tbl, idx, alt_idx, cnt) "
      . "VALUES (CONV(?, 16, 10), ?, ?, ?, ?, ?) "
      . "ON DUPLICATE KEY UPDATE cnt = cnt + ?");
   foreach my $query_id ( keys %{$self->{alt_index_usage}} ) {
      foreach my $db ( keys %{$self->{alt_index_usage}->{$query_id}} ) {
         foreach my $tbl ( keys %{$self->{alt_index_usage}->{$query_id}->{$db}} ) {
            foreach my $index ( keys %{$self->{alt_index_usage}->{$query_id}->{$db}->{$tbl}} ){
               my $alt_indexes = $self->{alt_index_usage}->{$query_id}->{$db}->{$tbl}->{$index};
               foreach my $alt_index ( keys %$alt_indexes ) {
                  my $cnt = $alt_indexes->{$alt_index};
                  $insert_index_alt_sth->execute(
                     $query_id, $db, $tbl, $index, $alt_index, $cnt, $cnt);
               }
            }
         }
      }
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
# End IndexUsage package
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
# Check just above main() for the call to main() which actually runs the
# program.
# ###########################################################################
package mk_index_usage;

use English qw(-no_match_vars);
use Data::Dumper;
$Data::Dumper::Indent = 1;
$OUTPUT_AUTOFLUSH     = 1;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

Transformers->import(qw(make_checksum));

# Global variables.  Only really essential variables should be here.
my $oktorun = 1;

if ( !caller ) { exit main(@ARGV); } # Run the program.
sub main {
   @ARGV = @_;  # set global ARGV for this package

   $oktorun = 1;

   # ##########################################################################
   # Get configuration information.
   # ##########################################################################
   my $o = new OptionParser();
   $o->get_specs();
   $o->get_opts();
   my $dp = $o->DSNParser();
   $dp->prop('set-vars', $o->get('set-vars'));
   $o->set('progress', undef) if $o->get('q');

   if ( !$o->got('help') ) {
      if ( $o->get('progress') ) {
         eval { Progress->validate_spec($o->get('progress')) };
         if ( $EVAL_ERROR ) {
            chomp $EVAL_ERROR;
            $o->save_error("--progress $EVAL_ERROR");
         }
      }

      if ( my $dsn = $o->get('save-results-database') ) {
         if ( !$dsn->{D} ) {
            $o->save_error("You must specify a D (database) part for the "
               . "--save-results-database DSN");
         }
      }
   }

   $o->usage_or_errors();

   # ##########################################################################
   # Open the database connections.  If no connection opts (-h, -P, etc.)
   # are given on the cmd line then parse_options() will return undef,
   # but get_cxn() required a defined dsn arg so use an empty hashref.
   # ########################################################################## 
   my ($dbh, $si_dbh, $res_dbh);
   my $res_db;
   eval {
      my $dsn = $dp->parse_options($o) || {};

      # dbh for EXPLAIN-ing.
      $dbh = get_cxn(
         dsn          => $dsn,
         OptionParser => $o,
         DSNParser    => $dp,
      );

      # dbh for SchemaIterator
      # http://code.google.com/p/maatkit/issues/detail?id=1140 
      $si_dbh = get_cxn(
         dsn          => $dsn,
         OptionParser => $o,
         DSNParser    => $dp,
      );

      # dbh for --save-results-database
      if ( my $res_dsn = $o->get('save-results-database') ) {
         
         # To make --create-save-results-database work we have to
         # temporarily remove the D from the DSN to avoid the error
         # "DBI connect failed: Unknown database".  It's restored
         # to the DSN after connecting.
         $res_db       = $res_dsn->{D};
         $res_dsn->{D} = undef if $o->get('create-save-results-database');

         $res_dbh = get_cxn(
            dsn          => $res_dsn,
            OptionParser => $o,
            DSNParser    => $dp,
         );

         $res_dsn->{D} = $res_db;
      }
   };
   if ( $EVAL_ERROR ) {
      # Avoid "Issuing rollback() for database handle being DESTROY'd
      # without explicit disconnect()" errors.
      $dbh->disconnect if $dbh;
      $si_dbh->disconnect if $si_dbh;
      $res_dbh->disconnect if $res_dbh;
      die $EVAL_ERROR;
   }

   # ##########################################################################
   # Make common modules.
   # ##########################################################################
   my $q      = new Quoter();
   my $qp     = new QueryParser();
   my $qr     = new QueryRewriter(QueryParser => $qp);
   my $tp     = new TableParser(Quoter => $q);
   my $vp     = new VersionParser();
   my $parser = new SlowLogParser();
   my $fi     = new FileIterator();
   my $du     = new MySQLDump();
   my $si     = new SchemaIterator(Quoter => $q);
   my $iu     = new IndexUsage(
      QueryRewriter => $qr,
   );
   my $exa    = new ExplainAnalyzer(
      QueryRewriter => $qr,
      QueryParser   => $qp
   );
   my %common_modules = (
      OptionParser    => $o,
      DSNParser       => $dp,
      Quoter          => $q,
      QueryParser     => $qp,
      QueryRewriter   => $qr,
      TableParser     => $tp,
      VersionParser   => $vp,
      MySQLDump       => $du,
      IndexUsage      => $iu,
      ExplainAnalyzer => $exa,
   );


   # ########################################################################
   # Ready the save results database and its tables.
   # ########################################################################
   if ( $res_dbh ) {
      my $db = $o->get('save-results-database')->{D};  # checked earlier

      # Create the database (if it doesn't already exist).
      if ( $o->get('create-save-results-database') ) {
         create_save_results_database(
            dbh => $res_dbh,
            db  => $db,
            %common_modules,
         );
      }

      # Parse the CREATE TABLE defs from the POD.
      my @tables = get_save_results_tables(%common_modules);

      # Empty the tables.  This is actually done via DROP TABLE IF EXISTS.
      if ( $o->get('empty-save-results-tables') ) {
         empty_save_results_tables(
            dbh  => $res_dbh,
            db   => $db,
            tbls => \@tables,
            %common_modules,
         );
      }

      # Create the tables if necessary.  If they were dropped above, now
      # they'll be recreated.  If they never existed (e.g. new db), they'll
      # be recreated.  Or if they already exist, each def has "IF NOT EXISTS"
      # so existing tables will remain untouched.
      create_save_results_tables(
         dbh  => $res_dbh,
         db   => $db,
         tbls => \@tables,
         %common_modules,
      );

      # Create views for the canned/example queries.
      # http://code.google.com/p/maatkit/issues/detail?id=1184
      if ( $o->get('create-views') ) {
         eval {
            create_views(
               dbh => $res_dbh,
               db  => $db,
               %common_modules,
            );
         };
         if ( $EVAL_ERROR ) {
            warn "Failed to create views: $EVAL_ERROR";
         }
      }
   }

   # ########################################################################
   # Populate the IndexUsage object with indexes.  Also get a list of all
   # databases and tables before going on to parse the queries.  This will be
   # important when we see a query without any default database, and we have to
   # guess which database to USE for EXPLAIN-ing it.  This code block doesn't
   # read query logs, it's just inventorying the tables and indexes.
   # ########################################################################
   $si->set_filter($si->make_filter($o));
   my $version = $vp->parse($dbh->selectrow_array('SELECT VERSION()'));
   my ($next_db, $db_count) = $si->get_db_itr(dbh => $si_dbh);
   my ($db_pr, $dbs_done);
   if ( $o->get('progress') ) {
      $db_pr = new Progress(
         jobsize => $db_count,
         spec    => $o->get('progress'),
         name    => 'schema inventory',
      );
   }
   DATABASE:
   while ( my $database = $next_db->() ) {
      MKDEBUG && _d('Getting tables from', $database);
      my ($next_tbl, $tbl_count) = $si->get_tbl_itr(
         dbh   => $si_dbh,
         db    => $database,
         views => 0,
      );
      my ($tbl_pr, $tbls_done);
      if ( $o->get('progress') ) {
         $tbl_pr = new Progress(
            jobsize => $tbl_count,
            spec    => $o->get('progress'),
            name    => "table inventory for $database",
         );
      }
      TABLE:
      while ( my $table = $next_tbl->() ) {
         MKDEBUG && _d('Got table', $table);
         eval {
            my $ddl       = $du->get_create_table(
                            $si_dbh, $q, $database, $table)->[1];
            my ($indexes) = $tp->get_keys($ddl, {version => $version });
            $iu->add_indexes(db=>$database, tbl=>$table, indexes=>$indexes);
         };
         if ( $EVAL_ERROR ) {
            warn $EVAL_ERROR unless $o->get('q');
            MKDEBUG && _d($EVAL_ERROR);
         }
         $tbl_pr->update(sub { ++$tbls_done }) if $tbl_pr;
      }
      $db_pr->update(sub { ++$dbs_done }) if $db_pr;
   }
   $si_dbh->disconnect();

   # ########################################################################
   # This keeps track of the $dbh's current DB, so we know when to USE a
   # different database.
   # ########################################################################
   my $cur_db = $o->get('database') || '';

   # ########################################################################
   # This keeps track of statements that can't be EXPLAINed for some reason, so
   # they are not tried again.
   # ########################################################################
   my %err_for = ();

   # ########################################################################
   # This is the main loop over the input filenames.
   # ########################################################################
   my $next_file = $fi->get_file_itr(@ARGV);
   my ( $fh, $filename, $filesize ) = $next_file->();
   FILE:
   while ( defined $fh ) {

      # Create a callback to get events from the slow query log file.
      my $next_event = sub { return <$fh>; };
      my $tell = sub { return tell $fh; };
      my $event;
      my $get_event = sub {
         return $parser->parse_event(
            event      => $event,
            next_event => $next_event,
            tell       => $tell,
            oktorun    => sub { return 1 },
            misc       => {},
            stats      => {},
         );
      };

      # #####################################################################
      # Set up a progress reporter.  For right now, we just do one per file.
      # Maybe someday we can do a global progress report?
      # #####################################################################
      my $pr;
      if ( $o->get('progress') && $filename && -e $filename ) {
         $pr = new Progress(
            jobsize => -s $filename,
            spec    => $o->get('progress'),
            name    => $filename,
         );
      }

      # #####################################################################
      # This is the main loop over the queries in the log.  For each query we
      # are going to store what we learn about that query's EXPLAIN plan, keyed
      # off its fingerprint.
      # #####################################################################
      EVENT:
      while ( $event = $get_event->() ) {
         my $arg = $event->{arg} or next EVENT; # The arg is the SQL.
         my $fingerprint = $event->{fingerprint} = $qr->fingerprint($arg);

         # Skip events that previously had an error.
         next if $err_for{$fingerprint};

         eval {

            # Checksum the query and get the query's ID.
            my $chk = make_checksum($arg);
            my $id  = make_checksum($fingerprint);

            # Do we need to USE a new database before we EXPLAIN the query?
            my $new_db = $event->{db} || $event->{Schema};
            if ( $new_db && $new_db ne $cur_db ) {
               my $sql = 'USE ' . $q->quote($new_db);
               MKDEBUG && _d($sql);
               $dbh->do($sql);
               $cur_db = $new_db;
            }

            # See if we've EXPLAINed this checksum before.  If so, just
            # increment counters with the saved info from $exa.  If not, EXPLAIN
            # and increment counters, then save to $exa.
            my $access = $exa->get_usage_for($chk, $cur_db);
            if ( !$access ) {

               # The query might not be explain-able.  If that is so, it will
               # die, and we want that to happen so it gets blacklisted.  We
               # don't want it to return an error or something like that, and we
               # don't want to filter it out and skip it in the first place,
               # because then we will keep burning cycles on it trying to
               # explain it over and over.
               my $explain = $exa->explain_query(
                  dbh   => $dbh,
                  query => $arg,
               );
               $access = $exa->get_index_usage(
                  query   => $arg,
                  db      => $cur_db,
                  explain => $exa->normalize($explain),
               );
               $exa->save_usage_for($chk, $cur_db, $access);
               $iu->add_query(
                  query_id    => $id,
                  fingerprint => $fingerprint,
                  sample      => $arg,
               );
            }
            foreach my $row ( @$access ) {
               $iu->add_table_usage($row->{db}, $row->{tbl});
               $iu->add_index_usage(
                  usage    => $access,
                  query_id => $id,
               );
            }

         };
         if ( $EVAL_ERROR ) {
            # Skip statements with this fingerprint in the future (blacklist).
            $err_for{$fingerprint} = { event => $event, error => $EVAL_ERROR };

            # Log the error.
            MKDEBUG && _d('Problem on query', $event, $EVAL_ERROR);
            warn $EVAL_ERROR unless $o->get('q');
         }
         $pr->update($tell) if $pr;
      } # EVENT

      ( $fh, $filename, $filesize ) = $next_file->();
   } # FILE

   # ########################################################################
   # All done!  Now print the reports, maybe.
   # ########################################################################
   if ( $res_dbh ) {
      $iu->save_results(
         dbh => $res_dbh,
         db  => $res_db,
      );
   }

   if ( $o->get('report') ) {
      print_reports(
         dbh     => $dbh,
         err_for => \%err_for,
         %common_modules
      );
   }

   $dbh->disconnect;
   $res_dbh->disconnect if $res_dbh;
   return 0;
} # End main().

# ############################################################################
# Subroutines.
# ############################################################################
sub print_reports {
   my ( %args ) = @_;
   my $iu      = $args{IndexUsage};
   my $o       = $args{OptionParser};
   my @reports = @{$o->get('report-format')};
   MKDEBUG && _d("Printing reports");

   if ( grep { $_ eq 'drop_unused_indexes' } @reports ) {
      $iu->find_unused_indexes(
         sub {
            my ( $unused ) = @_;
            print_unused_indexes(
               unused => $unused,
               drop   => $o->get('drop'),
               %args,
            );
         }
      );
   }

   return;
}

sub print_unused_indexes {
   my ( %args ) = @_;
   my @required_args = qw(unused drop Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($unused, $drop, $q) = @args{@required_args};

   my $db_tbl = $q->quote($unused->{db}, $unused->{tbl});

   # We must ignore the types that we're not dropping, then group
   # indexes of the remaining types together and print them together.
   my (@primary, @unique, @nonunique);
   foreach my $idx ( @{$unused->{idx}} ) {
      if ($idx->{name} =~ m/PRIMARY/i ) {
         push @primary, $idx;
      }
      elsif ( $idx->{is_unique} ) {
         push @unique, $idx;
      }
      else {
         push @nonunique, $idx;
      }
   }

   print_alter_drop_key(
      db_tbl => $db_tbl,
      idx    => \@primary,
      type   => 'primary key',
      %args
   ) if $drop->{primary} || $drop->{all};

   print_alter_drop_key(
      db_tbl => $db_tbl,
      idx    => \@unique,
      type   => 'unique',
      %args
   ) if $drop->{unique} || $drop->{all};

   print_alter_drop_key(
      db_tbl => $db_tbl,
      idx    => \@nonunique,
      type   => 'non-unique',
      %args
   ) if $drop->{"non-unique"} || $drop->{all};

   return;
}

sub print_alter_drop_key {
   my ( %args ) = @_;
   my @required_args = qw(db_tbl idx Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($db_tbl, $idx, $q) = @args{@required_args};

   return unless @$idx;

   print "\nALTER TABLE $db_tbl "
      . join(', ', map { "DROP KEY " . $q->quote($_->{name}) } @$idx)
      . ";"
      . ($args{type} ? " -- type:$args{type}" : "")
      . "\n";

   return;
}

sub get_cxn {
   my ( %args ) = @_;
   my @required_args = qw(dsn OptionParser DSNParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dsn, $o, $dp) = @args{@required_args};

   if ( $o->get('ask-pass') ) {
      $dsn->{p} = OptionParser::prompt_noecho("Enter password "
         . ($args{for} ? "for $args{for}: " : ": "));
   }

   my $dbh = $dp->get_dbh($dp->get_cxn_params($dsn), $args{opts});
   MKDEBUG && _d('Connected dbh', $dbh);
   return $dbh;
}

sub create_save_results_database {
   my ( %args ) = @_;
   my @required_args = qw(dbh db Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($dbh, $db, $q) = @args{@required_args};
   my $sql;

   $db = $q->quote($db);

   eval {
      MKDEBUG && _d("Checking if", $db, "database already exists");
      $sql = "USE $db";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($db, "does not exist:", $EVAL_ERROR);
      $sql = "CREATE DATABASE $db";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);

      # Now USE the newly created db (the first attempt failed obviously).
      $sql = "USE $db";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   }
   else {
      MKDEBUG && _d($db, "already exists");
   }

   return;
}

sub get_save_results_tables {
   my ( %args ) = @_;
   my @required_args = qw(OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($o)  = @args{@required_args};
   my $file = $args{file} || __FILE__;
   MKDEBUG && _d("Getting CREATE TABLE defs from POD");

   my @table_defs = qw(indexes tables queries index_usage index_alternatives);
   my @tables;
   foreach my $tbl ( @table_defs ) {
      my $magic = "MAGIC_create_$tbl";
      my $sql   = $o->read_para_after($file, qr/$magic/);
      push @tables, {
         name => $tbl,
         def  => $sql,
      };
   }

   return @tables;
}

sub empty_save_results_tables {
   my ( %args ) = @_;
   my @required_args = qw(dbh db tbls Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($dbh, $db, $tbls, $q) = @args{@required_args};

   foreach my $tbl ( @$tbls ) {
      # Nothing is more "empty" than non-existence.  The tables
      # will be recreated later by calling create_save_results_tables().
      # Dropping and recreating has an advantage over truncating/deleting:
      # if the CREATE TABLE def is changed, this will auto-upgrade.
      my $sql = "DROP TABLE IF EXISTS " . $q->quote($db, $tbl->{name});
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   }

   return;
}

sub create_save_results_tables {
   my ( %args ) = @_;
   my @required_args = qw(dbh db tbls);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($dbh, $db, $tbls) = @args{@required_args};

   foreach my $tbl ( @$tbls ) {
      my $sql = $tbl->{def};
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   }

   return;
}

sub create_views {
   my ( %args ) = @_;
   my @required_args = qw(dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg arugment" unless $args{$arg};
   }
   my ($dbh) = @args{@required_args};
   MKDEBUG && _d("Creating views");

   my $pod_parser = new PodParser();
   $pod_parser->parse_from_file(__FILE__);

   my $magic = $pod_parser->get_magic('OPTIONS');
   foreach my $ident ( keys %$magic ) {
      next unless $ident =~ m/^view/;
      my $sql = "CREATE VIEW `$ident` AS $magic->{$ident}";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
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

1; # Because this is a module as well as a script.

# #############################################################################
# Documentation.
# #############################################################################

=pod

=head1 NAME

mk-index-usage - Read queries from a log and analyze how they use indexes.

=head1 SYNOPSIS

Usage: mk-index-usage [OPTION...] [FILE...]

mk-index-usage reads queries from logs and analyzes how they use indexes.

Analyze queries in slow.log and print reports:

  mk-index-usage /path/to/slow.log --host localhost

Disable reports and save results to mk database for later analysis:

  mk-index-usage slow.log --no-report --save-results-database mk

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

This tool is read-only unless you use L<"--save-results-database">.  It reads a
log of queries and EXPLAIN them.  It also gathers information about all tables
in all databases.  It should be very low-risk.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-index-usage>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

This tool connects to a MySQL database server, reads through a query log, and
uses EXPLAIN to ask MySQL how it will use each query.  When it is finished, it
prints out a report on indexes that the queries didn't use.

The query log needs to be in MySQL's slow query log format.  If you need to
input a different format, you can use L<mk-query-digest> to translate the
formats.  If you don't specify a filename, the tool reads from STDIN.

The tool runs two stages.  In the first stage, the tool takes inventory of all
the tables and indexes in your database, so it can compare the existing indexes
to those that were actually used by the queries in the log.  In the second
stage, it runs EXPLAIN on each query in the query log.  It uses separate
database connections to inventory the tables and run EXPLAIN, so it opens two
connections to the database.

If a query is not a SELECT, it tries to transform it to a roughly equivalent
SELECT query so it can be EXPLAINed.  This is not a perfect process, but it is
good enough to be useful.

The tool skips the EXPLAIN step for queries that are exact duplicates of those
seen before.  It assumes that the same query will generate the same EXPLAIN plan
as it did previously (usually a safe assumption, and generally good for
performance), and simply increments the count of times that the indexes were
used.  However, queries that have the same fingerprint but different checksums
will be re-EXPLAINed.  Queries that have different literal constants can have
different execution plans, and this is important to measure.

After EXPLAIN-ing the query, it is necessary to try to map aliases in the query
back to the original table names.  For example, consider the EXPLAIN plan for
the following query:

  SELECT * FROM tbl1 AS foo;

The EXPLAIN output will show access to table C<foo>, and that must be translated
back to C<tbl1>.  This process involves complex parsing.  It is generally very
accurate, but there is some chance that it might not work right.  If you find
cases where it fails, submit a bug report and a reproducible test case.

Queries that cannot be EXPLAINed will cause all subsequent queries with the
same fingerprint to be blacklisted.  This is to reduce the work they cause, and
prevent them from continuing to print error messages.  However, at least in
this stage of the tool's development, it is my opinion that it's not a good
idea to preemptively silence these, or prevent them from being EXPLAINed at
all.  I am looking for lots of feedback on how to improve things like the
query parsing.  So please submit your test cases based on the errors the tool
prints!

=head1 OUTPUT

After it reads all the events in the log, the tool prints out DROP statements
for every index that was not used.  It skips indexes for tables that were never
accessed by any queries in the log, to avoid false-positive results.

If you don't specify L<"--quiet">, the tool also outputs warnings about
statements that cannot be EXPLAINed and similar.  These go to standard error.

Progress reports are enabled by default (see L<"--progress">).  These also go to
standard error.

=head1 OPTIONS

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --ask-pass

Prompt for a password when connecting to MySQL.

=item --charset

short form: -A; type: string

Default character set.  If the value is utf8, sets Perl's binmode on
STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and
runs SET NAMES UTF8 after connecting to MySQL.  Any other value sets
binmode on STDOUT without the utf8 layer, and runs SET NAMES after
connecting to MySQL.

=item --config

type: Array

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --create-save-results-database

Create the L<"--save-results-database"> if it does not exist.

If the L<"--save-results-database"> already exists and this option is
specified, the database is used and the necessary tables are created if
they do not already exist.

=item --[no]create-views

Create views for L<"--save-results-database"> example queries.

Several example queries are given for querying the tables in the
L<"--save-results-database">.  These example queries are, by default, created
as views.  Specifying C<--no-create-views> prevents these views from being
created.

=item --database

short form: -D; type: string

The database to use for the connection.

=item --databases

short form: -d; type: hash

Only get tables and indexes from this comma-separated list of databases.

=item --databases-regex

type: string

Only get tables and indexes from database whose names match this Perl regex.

=item --defaults-file

short form: -F; type: string

Only read mysql options from the given file.  You must give an absolute pathname.

=item --drop

type: Hash; default: non-unique

Suggest dropping only these types of unused indexes.

By default mk-index-usage will only suggest to drop unused secondary indexes,
not primary or unique indexes.  You can specify which types of unused indexes
the tool suggests to drop: primary, unique, non-unique, all.

A separate C<ALTER TABLE> statement for each type is printed.  So if you
specify C<--drop all> and there is a primary key and a non-unique index,
the C<ALTER TABLE ... DROP> for each will be printed on separate lines.

=item --empty-save-results-tables

Drop and re-create all pre-existing tables in the L<"--save-results-database">.
This allows information from previous runs to be removed before the current run.

=item --help

Show help and exit.

=item --host

short form: -h; type: string

Connect to host.

=item --ignore-databases

type: Hash

Ignore this comma-separated list of databases.

=item --ignore-databases-regex

type: string

Ignore databases whose names match this Perl regex.

=item --ignore-tables

type: Hash

Ignore this comma-separated list of table names.

Table names may be qualified with the database name.

=item --ignore-tables-regex

type: string

Ignore tables whose names match the Perl regex.

=item --password

short form: -p; type: string

Password to use when connecting.

=item --port

short form: -P; type: int

Port number to use for connection.

=item --progress

type: array; default: time,30

Print progress reports to STDERR.  The value is a comma-separated list with two
parts.  The first part can be percentage, time, or iterations; the second part
specifies how often an update should be printed, in percentage, seconds, or
number of iterations.

=item --quiet

short form: -q

Do not print any warnings.  Also disables L<"--progress">.

=item --[no]report

default: yes

Print the reports for L<"--report-format">.

You may want to disable the reports by specifying C<--no-report> if, for
example, you also specify L<"--save-results-database"> and you only want
to query the results tables later.

=item --report-format

type: Array; default: drop_unused_indexes

Right now there is only one report: drop_unused_indexes.  This report prints
SQL statements for dropping any unused indexes.  See also L<"--drop">.

See also L<"--[no]report">.

=item --save-results-database

type: DSN

Save results to tables in this database.  Information about indexes, queries,
tables and their usage is stored in several tables in the specified database.
The tables are auto-created if they do not exist.  If the database doesn't
exist, it can be auto-created with L<"--create-save-results-database">.  In this
case the connection is initially created with no default database, then after
the database is created, it is USE'ed.

mk-index-usage executes INSERT statements to save the results.  Therefore, you
should be careful if you use this feature on a production server.  It might
increase load, or cause trouble if you don't want the server to be written to,
or so on.

This is a new feature.  It may change in future releases.  

After a run, you can query the usage tables to answer various questions about
index usage.  The tables have the following CREATE TABLE definitions:

MAGIC_create_indexes:

  CREATE TABLE IF NOT EXISTS indexes (
    db           VARCHAR(64) NOT NULL,
    tbl          VARCHAR(64) NOT NULL,
    idx          VARCHAR(64) NOT NULL,
    cnt          BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY  (db, tbl, idx)
  )

MAGIC_create_queries:

  CREATE TABLE IF NOT EXISTS queries (
    query_id     BIGINT UNSIGNED NOT NULL,
    fingerprint  TEXT NOT NULL,
    sample       TEXT NOT NULL,
    PRIMARY KEY  (query_id)
  )

MAGIC_create_tables:

  CREATE TABLE IF NOT EXISTS tables (
    db           VARCHAR(64) NOT NULL,
    tbl          VARCHAR(64) NOT NULL,
    cnt          BIGINT UNSIGNED NOT NULL DEFAULT 0,
    PRIMARY KEY  (db, tbl)
  )

MAGIC_create_index_usage:

  CREATE TABLE IF NOT EXISTS index_usage (
    query_id      BIGINT UNSIGNED NOT NULL,
    db            VARCHAR(64) NOT NULL,
    tbl           VARCHAR(64) NOT NULL,
    idx           VARCHAR(64) NOT NULL,
    cnt           BIGINT UNSIGNED NOT NULL DEFAULT 1,
    UNIQUE INDEX  (query_id, db, tbl, idx)
  )

MAGIC_create_index_alternatives:

  CREATE TABLE IF NOT EXISTS index_alternatives (
    query_id      BIGINT UNSIGNED NOT NULL, -- This query used
    db            VARCHAR(64) NOT NULL,     -- this index, but...
    tbl           VARCHAR(64) NOT NULL,     --
    idx           VARCHAR(64) NOT NULL,     --
    alt_idx       VARCHAR(64) NOT NULL,     -- was an alternative
    cnt           BIGINT UNSIGNED NOT NULL DEFAULT 1,
    UNIQUE INDEX  (query_id, db, tbl, idx, alt_idx),
    INDEX         (db, tbl, idx),
    INDEX         (db, tbl, alt_idx)
  )

The following are some queries you can run against these tables to answer common
questions you might have.  Each query is also created as a view (with MySQL
v5.0 and newer) if C<"--[no]create-views"> is true (it is by default).
The view names are the strings after the C<MAGIC_view_> prefix.

Question: which queries sometimes use different indexes, and what fraction of
the time is each index chosen?  MAGIC_view_query_uses_several_indexes:

 SELECT iu.query_id, CONCAT_WS('.', iu.db, iu.tbl, iu.idx) AS idx,
    variations, iu.cnt, iu.cnt / total_cnt * 100 AS pct
 FROM index_usage AS iu
    INNER JOIN (
       SELECT query_id, db, tbl, SUM(cnt) AS total_cnt,
         COUNT(*) AS variations
       FROM index_usage
       GROUP BY query_id, db, tbl
       HAVING COUNT(*) > 1
    ) AS qv USING(query_id, db, tbl);

Question: which indexes have lots of alternatives, i.e. are chosen instead of
other indexes, and for what queries?  MAGIC_view_index_has_alternates:

 SELECT CONCAT_WS('.', db, tbl, idx) AS idx_chosen,
    GROUP_CONCAT(DISTINCT alt_idx) AS alternatives,
    GROUP_CONCAT(DISTINCT query_id) AS queries, SUM(cnt) AS cnt
 FROM index_alternatives
 GROUP BY db, tbl, idx
 HAVING COUNT(*) > 1;

Question: which indexes are considered as alternates for other indexes, and for
what queries?  MAGIC_view_index_alternates:

 SELECT CONCAT_WS('.', db, tbl, alt_idx) AS idx_considered,
    GROUP_CONCAT(DISTINCT idx) AS alternative_to,
    GROUP_CONCAT(DISTINCT query_id) AS queries, SUM(cnt) AS cnt
 FROM index_alternatives
 GROUP BY db, tbl, alt_idx
 HAVING COUNT(*) > 1;

Question: which of those are never chosen by any queries, and are therefore
superfluous?  MAGIC_view_unused_index_alternates:

 SELECT CONCAT_WS('.', i.db, i.tbl, i.idx) AS idx,
    alt.alternative_to, alt.queries, alt.cnt
 FROM indexes AS i
    INNER JOIN (
       SELECT db, tbl, alt_idx, GROUP_CONCAT(DISTINCT idx) AS alternative_to,
          GROUP_CONCAT(DISTINCT query_id) AS queries, SUM(cnt) AS cnt
       FROM index_alternatives
       GROUP BY db, tbl, alt_idx
       HAVING COUNT(*) > 1
    ) AS alt ON i.db = alt.db AND i.tbl = alt.tbl
      AND i.idx = alt.alt_idx
 WHERE i.cnt = 0;

Question: given a table, which indexes were used, by how many queries, with how
many distinct fingerprints?  Were there alternatives?  Which indexes were not
used?  You can edit the following query's SELECT list to also see the query IDs
in question.  MAGIC_view_index_usage:

 SELECT i.idx, iu.usage_cnt, iu.usage_total,
    ia.alt_cnt, ia.alt_total
 FROM indexes AS i
    LEFT OUTER JOIN (
       SELECT db, tbl, idx, COUNT(*) AS usage_cnt,
          SUM(cnt) AS usage_total, GROUP_CONCAT(query_id) AS used_by
       FROM index_usage
       GROUP BY db, tbl, idx
    ) AS iu ON i.db=iu.db AND i.tbl=iu.tbl AND i.idx = iu.idx
    LEFT OUTER JOIN (
       SELECT db, tbl, idx, COUNT(*) AS alt_cnt,
          SUM(cnt) AS alt_total,
          GROUP_CONCAT(query_id) AS alt_queries
       FROM index_alternatives
       GROUP BY db, tbl, idx
    ) AS ia ON i.db=ia.db AND i.tbl=ia.tbl AND i.idx = ia.idx;

Question: which indexes on a given table are vital for at least one query (there
is no alternative)?  MAGIC_view_required_indexes:

   SELECT i.db, i.tbl, i.idx, no_alt.queries
   FROM indexes AS i
      INNER JOIN (
         SELECT iu.db, iu.tbl, iu.idx,
            GROUP_CONCAT(iu.query_id) AS queries
         FROM index_usage AS iu
            LEFT OUTER JOIN index_alternatives AS ia
               USING(db, tbl, idx)
         WHERE ia.db IS NULL
         GROUP BY iu.db, iu.tbl, iu.idx
      ) AS no_alt ON no_alt.db = i.db AND no_alt.tbl = i.tbl
         AND no_alt.idx = i.idx
   ORDER BY i.db, i.tbl, i.idx, no_alt.queries;

=item --set-vars

type: string; default: wait_timeout=10000

Set these MySQL variables.  Immediately after connecting to MySQL, this
string will be appended to SET and executed.

=item --socket

short form: -S; type: string

Socket file to use for connection.

=item --tables

short form: -t; type: hash

Only get indexes from this comma-separated list of tables.

=item --tables-regex

type: string

Only get indexes from tables whose names match this Perl regex.

=item --user

short form: -u; type: string

User for login if not current user.

=item --version

Show version and exit.

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

Database to connect to.

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

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-index-usage>.

Please use Google Code Issues and Groups to report bugs or request support:
L<http://code.google.com/p/maatkit/>.  You can also join #maatkit on Freenode to
discuss Maatkit.

Please include the complete command-line used to reproduce the problem you are
seeing, the version of all MySQL servers involved, the complete output of the
tool when run with L<"--version">, and if possible, debugging output produced by
running with the C<MKDEBUG=1> environment variable.

=head1 COPYRIGHT, LICENSE AND WARRANTY

This program is copyright 2010-2011 Baron Schwartz.
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

This manual page documents Ver 0.9.4 Distrib 7540 $Revision: 7477 $.

=cut

__END__
:endofperl
