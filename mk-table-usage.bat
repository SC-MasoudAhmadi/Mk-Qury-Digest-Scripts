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

our $VERSION = '1.0.1';
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
# SQLParser package 7497
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/SQLParser.pm
#   trunk/common/t/SQLParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package SQLParser;

{ # package scope
use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $quoted_ident   = qr/`[^`]+`/;
my $unquoted_ident = qr/
   \@{0,2}         # optional @ or @@ for variables
   \w+             # the ident name
   (?:\([^\)]*\))? # optional function params
/x;

my $ident_alias = qr/
  \s+                                 # space before alias
  (?:(AS)\s+)?                        # optional AS keyword
  ((?>$quoted_ident|$unquoted_ident)) # alais
/xi;

my $table_ident = qr/(?:
   ((?:(?>$quoted_ident|$unquoted_ident)\.?){1,2}) # table
   (?:$ident_alias)?                               # optional alias
)/xo;

my $column_ident = qr/(?:
   ((?:(?>$quoted_ident|$unquoted_ident|\*)\.?){1,3}) # column
   (?:$ident_alias)?                                  # optional alias
)/xo;

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      %args,
   };
   return bless $self, $class;
}

sub parse {
   my ( $self, $query ) = @_;
   return unless $query;

   my $allowed_types = qr/(?:
       DELETE
      |INSERT
      |REPLACE
      |SELECT
      |UPDATE
   )/xi;

   $query = $self->clean_query($query);

   my $type;
   if ( $query =~ s/^(\w+)\s+// ) {
      $type = lc $1;
      MKDEBUG && _d('Query type:', $type);
      die "Cannot parse " . uc($type) . " queries"
         unless $type =~ m/$allowed_types/i;
   }
   else {
      die "Query does not begin with a word";  # shouldn't happen
   }

   $query = $self->normalize_keyword_spaces($query);

   my @subqueries;
   if ( $query =~ m/(\(SELECT )/i ) {
      MKDEBUG && _d('Removing subqueries');
      @subqueries = $self->remove_subqueries($query);
      $query      = shift @subqueries;
   }

   my $parse_func = "parse_$type";
   my $struct     = $self->$parse_func($query);
   if ( !$struct ) {
      MKDEBUG && _d($parse_func, 'failed to parse query');
      return;
   }
   $struct->{type} = $type;
   $self->_parse_clauses($struct);

   if ( @subqueries ) {
      MKDEBUG && _d('Parsing subqueries');
      foreach my $subquery ( @subqueries ) {
         my $subquery_struct = $self->parse($subquery->{query});
         @{$subquery_struct}{keys %$subquery} = values %$subquery;
         push @{$struct->{subqueries}}, $subquery_struct;
      }
   }

   MKDEBUG && _d('Query struct:', Dumper($struct));
   return $struct;
}


sub _parse_clauses {
   my ( $self, $struct ) = @_;
   foreach my $clause ( keys %{$struct->{clauses}} ) {
      if ( $clause =~ m/ / ) {
         (my $clause_no_space = $clause) =~ s/ /_/g;
         $struct->{clauses}->{$clause_no_space} = $struct->{clauses}->{$clause};
         delete $struct->{clauses}->{$clause};
         $clause = $clause_no_space;
      }

      my $parse_func     = "parse_$clause";
      $struct->{$clause} = $self->$parse_func($struct->{clauses}->{$clause});

      if ( $clause eq 'select' ) {
         MKDEBUG && _d('Parsing subquery clauses');
         $struct->{select}->{type} = 'select';
         $self->_parse_clauses($struct->{select});
      }
   }
   return;
}

sub clean_query {
   my ( $self, $query ) = @_;
   return unless $query;

   $query =~ s/^\s*--.*$//gm;  # -- comments
   $query =~ s/\s+/ /g;        # extra spaces/flatten
   $query =~ s!/\*.*?\*/!!g;   # /* comments */
   $query =~ s/^\s+//;         # leading spaces
   $query =~ s/\s+$//;         # trailing spaces

   return $query;
}

sub normalize_keyword_spaces {
   my ( $self, $query ) = @_;

   $query =~ s/\b(VALUE(?:S)?)\(/$1 (/i;
   $query =~ s/\bON\(/on (/gi;
   $query =~ s/\bUSING\(/using (/gi;

   $query =~ s/\(\s+SELECT\s+/(SELECT /gi;

   return $query;
}

sub _parse_query {
   my ( $self, $query, $keywords, $first_clause, $clauses ) = @_;
   return unless $query;
   my $struct = {};

   1 while $query =~ s/$keywords\s+/$struct->{keywords}->{lc $1}=1, ''/gie;

   my @clause = grep { defined $_ }
      ($query =~ m/\G(.+?)(?:$clauses\s+|\Z)/gci);

   my $clause = $first_clause,
   my $value  = shift @clause;
   $struct->{clauses}->{$clause} = $value;
   MKDEBUG && _d('Clause:', $clause, $value);

   while ( @clause ) {
      $clause = shift @clause;
      $value  = shift @clause;
      $struct->{clauses}->{lc $clause} = $value;
      MKDEBUG && _d('Clause:', $clause, $value);
   }

   ($struct->{unknown}) = ($query =~ m/\G(.+)/);

   return $struct;
}

sub parse_delete {
   my ( $self, $query ) = @_;
   if ( $query =~ s/FROM\s+//i ) {
      my $keywords = qr/(LOW_PRIORITY|QUICK|IGNORE)/i;
      my $clauses  = qr/(FROM|WHERE|ORDER BY|LIMIT)/i;
      return $self->_parse_query($query, $keywords, 'from', $clauses);
   }
   else {
      die "DELETE without FROM: $query";
   }
}

sub parse_insert {
   my ( $self, $query ) = @_;
   return unless $query;
   my $struct = {};

   my $keywords   = qr/(LOW_PRIORITY|DELAYED|HIGH_PRIORITY|IGNORE)/i;
   1 while $query =~ s/$keywords\s+/$struct->{keywords}->{lc $1}=1, ''/gie;

   if ( $query =~ m/ON DUPLICATE KEY UPDATE (.+)/i ) {
      my $values = $1;
      die "No values after ON DUPLICATE KEY UPDATE: $query" unless $values;
      $struct->{clauses}->{on_duplicate} = $values;
      MKDEBUG && _d('Clause: on duplicate key update', $values);

      $query =~ s/\s+ON DUPLICATE KEY UPDATE.+//;
   }

   if ( my @into = ($query =~ m/
            (?:INTO\s+)?            # INTO, optional
            (.+?)\s+                # table ref
            (\([^\)]+\)\s+)?        # column list, optional
            (VALUE.?|SET|SELECT)\s+ # start of next caluse
         /xgci)
   ) {
      my $tbl  = shift @into;  # table ref
      $struct->{clauses}->{into} = $tbl;
      MKDEBUG && _d('Clause: into', $tbl);

      my $cols = shift @into;  # columns, maybe
      if ( $cols ) {
         $cols =~ s/[\(\)]//g;
         $struct->{clauses}->{columns} = $cols;
         MKDEBUG && _d('Clause: columns', $cols);
      }

      my $next_clause = lc(shift @into);  # VALUES, SET or SELECT
      die "INSERT/REPLACE without clause after table: $query"
         unless $next_clause;
      $next_clause = 'values' if $next_clause eq 'value';
      my ($values) = ($query =~ m/\G(.+)/gci);
      die "INSERT/REPLACE without values: $query" unless $values;
      $struct->{clauses}->{$next_clause} = $values;
      MKDEBUG && _d('Clause:', $next_clause, $values);
   }

   ($struct->{unknown}) = ($query =~ m/\G(.+)/);

   return $struct;
}
{
   no warnings;
   *parse_replace = \&parse_insert;
}

sub parse_select {
   my ( $self, $query ) = @_;

   my @keywords;
   my $final_keywords = qr/(FOR UPDATE|LOCK IN SHARE MODE)/i; 
   1 while $query =~ s/\s+$final_keywords/(push @keywords, $1), ''/gie;

   my $keywords = qr/(
       ALL
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
   )/xi;
   my $clauses = qr/(
       FROM
      |WHERE
      |GROUP\sBY
      |HAVING
      |ORDER\sBY
      |LIMIT
      |PROCEDURE
      |INTO OUTFILE
   )/xi;
   my $struct = $self->_parse_query($query, $keywords, 'columns', $clauses);

   map { s/ /_/g; $struct->{keywords}->{lc $_} = 1; } @keywords;

   return $struct;
}

sub parse_update {
   my $keywords = qr/(LOW_PRIORITY|IGNORE)/i;
   my $clauses  = qr/(SET|WHERE|ORDER BY|LIMIT)/i;
   return _parse_query(@_, $keywords, 'tables', $clauses);

}

sub parse_from {
   my ( $self, $from ) = @_;
   return unless $from;
   MKDEBUG && _d('Parsing FROM', $from);

   my $comma_join = qr/(?>\s*,\s*)/;
   my $ansi_join  = qr/(?>
     \s+
     (?:(?:INNER|CROSS|STRAIGHT_JOIN|LEFT|RIGHT|OUTER|NATURAL)\s+)*
     JOIN
     \s+
   )/xi;

   my @tbls;     # all table refs, a hashref for each
   my $tbl_ref;  # current table ref hashref
   my $join;     # join info hahsref for current table ref
   foreach my $thing ( split /($comma_join|$ansi_join)/io, $from ) {
      die "Error parsing FROM clause" unless $thing;

      $thing =~ s/^\s+//;
      $thing =~ s/\s+$//;
      MKDEBUG && _d('Table thing:', $thing);

      if ( $thing =~ m/\s+(?:ON|USING)\s+/i ) {
         MKDEBUG && _d("JOIN condition");
         my ($tbl_ref_txt, $join_condition_verb, $join_condition_value)
            = $thing =~ m/^(.+?)\s+(ON|USING)\s+(.+)/i;

         $tbl_ref = $self->parse_table_reference($tbl_ref_txt);

         $join->{condition} = lc $join_condition_verb;
         if ( $join->{condition} eq 'on' ) {
            my $where      = $self->parse_where($join_condition_value);
            $join->{where} = $where; 
         }
         else { # USING
            $join_condition_value =~ s/^\s*\(//;
            $join_condition_value =~ s/\)\s*$//;
            $join->{columns} = $self->_parse_csv($join_condition_value);
         }
      }
      elsif ( $thing =~ m/(?:,|JOIN)/i ) {
         if ( $join ) {
            $tbl_ref->{join} = $join;
         }
         push @tbls, $tbl_ref;
         MKDEBUG && _d("Complete table reference:", Dumper($tbl_ref));

         $tbl_ref = undef;
         $join    = {};

         $join->{to} = $tbls[-1]->{tbl};
         if ( $thing eq ',' ) {
            $join->{type} = 'inner';
            $join->{ansi} = 0;
         }
         else { # ansi join
            my $type = $thing =~ m/^(.+?)\s+JOIN$/i ? lc $1 : 'inner';
            $join->{type} = $type;
            $join->{ansi} = 1;
         }
      }
      else {
         $tbl_ref = $self->parse_table_reference($thing);
         MKDEBUG && _d('Table reference:', Dumper($tbl_ref));
      }
   }

   if ( $tbl_ref ) {
      if ( $join ) {
         $tbl_ref->{join} = $join;
      }
      push @tbls, $tbl_ref;
      MKDEBUG && _d("Complete table reference:", Dumper($tbl_ref));
   }

   return \@tbls;
}

sub parse_table_reference {
   my ( $self, $tbl_ref ) = @_;
   return unless $tbl_ref;
   MKDEBUG && _d('Parsing table reference:', $tbl_ref);
   my %tbl;

   if ( $tbl_ref =~ s/
         \s+(
            (?:FORCE|USE|INGORE)\s
            (?:INDEX|KEY)
            \s*\([^\)]+\)\s*
         )//xi)
   {
      $tbl{index_hint} = $1;
      MKDEBUG && _d('Index hint:', $tbl{index_hint});
   }

   if ( $tbl_ref =~ m/$table_ident/ ) {
      my ($db_tbl, $as, $alias) = ($1, $2, $3); # XXX
      my $ident_struct = $self->parse_identifier('table', $db_tbl);
      $alias =~ s/`//g if $alias;
      @tbl{keys %$ident_struct} = values %$ident_struct;
      $tbl{explicit_alias} = 1 if $as;
      $tbl{alias}          = $alias if $alias;
   }
   else {
      die "Table ident match failed";  # shouldn't happen
   }

   return \%tbl;
}
{
   no warnings;  # Why? See same line above.
   *parse_into   = \&parse_from;
   *parse_tables = \&parse_from;
}

sub parse_where {
   my ( $self, $where ) = @_;
   return unless $where;
   MKDEBUG && _d("Parsing WHERE", $where);

   my $op_symbol = qr/
      (?:
       <=
      |>=
      |<>
      |!=
      |<
      |>
      |=
   )/xi;
   my $op_verb = qr/
      (?:
          (?:(?:NOT\s)?LIKE)
         |(?:IS(?:\sNOT\s)?)
         |(?:(?:\sNOT\s)?BETWEEN)
         |(?:(?:NOT\s)?IN)
      )
   /xi;
   my $op_pat = qr/
   (
      (?>
          (?:$op_symbol)  # don't need spaces around the symbols, e.g.: col=1
         |(?:\s+$op_verb) # must have space before verb op, e.g.: col LIKE ...
      )
   )/x;

   my $offset = 0;
   my $pred   = "";
   my @pred;
   my @has_op;
   while ( $where =~ m/\b(and|or)\b/gi ) {
      my $pos = (pos $where) - (length $1);  # pos at and|or, not after

      $pred = substr $where, $offset, ($pos-$offset);
      push @pred, $pred;
      push @has_op, $pred =~ m/$op_pat/o ? 1 : 0;

      $offset = $pos;
   }
   $pred = substr $where, $offset;
   push @pred, $pred;
   push @has_op, $pred =~ m/$op_pat/o ? 1 : 0;
   MKDEBUG && _d("Predicate fragments:", Dumper(\@pred));
   MKDEBUG && _d("Predicate frags with operators:", @has_op);

   my $n = scalar @pred - 1;
   for my $i ( 1..$n ) {
      $i   *= -1;
      my $j = $i - 1;  # preceding pred frag

      next if $pred[$j] !~ m/\s+between\s+/i  && $self->_is_constant($pred[$i]);

      if ( !$has_op[$i] ) {
         $pred[$j] .= $pred[$i];
         $pred[$i]  = undef;
      }
   }
   MKDEBUG && _d("Predicate fragments joined:", Dumper(\@pred));

   for my $i ( 0..@pred ) {
      $pred = $pred[$i];
      next unless defined $pred;
      my $n_single_quotes = ($pred =~ tr/'//);
      my $n_double_quotes = ($pred =~ tr/"//);
      if ( ($n_single_quotes % 2) || ($n_double_quotes % 2) ) {
         $pred[$i]     .= $pred[$i + 1];
         $pred[$i + 1]  = undef;
      }
   }
   MKDEBUG && _d("Predicate fragments balanced:", Dumper(\@pred));

   my @predicates;
   foreach my $pred ( @pred ) {
      next unless defined $pred;
      $pred =~ s/^\s+//;
      $pred =~ s/\s+$//;
      my $conj;
      if ( $pred =~ s/^(and|or)\s+//i ) {
         $conj = lc $1;
      }
      my ($col, $op, $val) = $pred =~ m/^(.+?)$op_pat(.+)$/o;
      if ( !$col || !$op ) {
         if ( $self->_is_constant($pred) ) {
            $val = lc $pred;
         }
         else {
            die "Failed to parse WHERE condition: $pred";
         }
      }

      if ( $col ) {
         $col =~ s/\s+$//;
         $col =~ s/^\(+//;  # no unquoted column name begins with (
      }
      if ( $op ) {
         $op  =  lc $op;
         $op  =~ s/^\s+//;
         $op  =~ s/\s+$//;
      }
      $val =~ s/^\s+//;
      
      if ( ($op || '') !~ m/IN/i && $val !~ m/^\w+\([^\)]+\)$/ ) {
         $val =~ s/\)+$//;
      }

      if ( $val =~ m/NULL|TRUE|FALSE/i ) {
         $val = lc $val;
      }

      push @predicates, {
         predicate => $conj,
         left_arg  => $col,
         operator  => $op,
         right_arg => $val,
      };
   }

   return \@predicates;
}

sub _is_constant {
   my ( $self, $val ) = @_;
   return 0 unless defined $val;
   $val =~ s/^\s*(?:and|or)\s+//;
   return
      $val =~ m/^\s*(?:TRUE|FALSE)\s*$/i || $val =~ m/^\s*-?\d+\s*$/ ? 1 : 0;
}

sub parse_having {
   my ( $self, $having ) = @_;
   return $having;
}

sub parse_group_by {
   my ( $self, $group_by ) = @_;
   return unless $group_by;
   MKDEBUG && _d('Parsing GROUP BY', $group_by);

   my $with_rollup = $group_by =~ s/\s+WITH ROLLUP\s*//i;

   my $idents = $self->parse_identifiers( $self->_parse_csv($group_by) );

   $idents->{with_rollup} = 1 if $with_rollup;

   return $idents;
}

sub parse_order_by {
   my ( $self, $order_by ) = @_;
   return unless $order_by;
   MKDEBUG && _d('Parsing ORDER BY', $order_by);
   my $idents = $self->parse_identifiers( $self->_parse_csv($order_by) );
   return $idents;
}

sub parse_limit {
   my ( $self, $limit ) = @_;
   return unless $limit;
   my $struct = {
      row_count => undef,
   };
   if ( $limit =~ m/(\S+)\s+OFFSET\s+(\S+)/i ) {
      $struct->{explicit_offset} = 1;
      $struct->{row_count}       = $1;
      $struct->{offset}          = $2;
   }
   else {
      my ($offset, $cnt) = $limit =~ m/(?:(\S+),\s+)?(\S+)/i;
      $struct->{row_count} = $cnt;
      $struct->{offset}    = $offset if defined $offset;
   }
   return $struct;
}

sub parse_values {
   my ( $self, $values ) = @_;
   return unless $values;
   $values =~ s/^\s*\(//;
   $values =~ s/\s*\)//;
   my $vals = $self->_parse_csv(
      $values,
      quoted_values => 1,
      remove_quotes => 0,
   );
   return $vals;
}

sub parse_set {
   my ( $self, $set ) = @_;
   MKDEBUG && _d("Parse SET", $set);
   return unless $set;
   my $vals = $self->_parse_csv($set);
   return unless $vals && @$vals;

   my @set;
   foreach my $col_val ( @$vals ) {
      my ($col, $val)  = $col_val =~ m/^([^=]+)\s*=\s*(.+)/;
      my $ident_struct = $self->parse_identifier('column', $col);
      my $set_struct   = {
         %$ident_struct,
         value => $val,
      };
      MKDEBUG && _d("SET:", Dumper($set_struct));
      push @set, $set_struct;
   }
   return \@set;
}

sub _parse_csv {
   my ( $self, $vals, %args ) = @_;
   return unless $vals;

   my @vals;
   if ( $args{quoted_values} ) {
      my $quote_char   = '';
      VAL:
      foreach my $val ( split(',', $vals) ) {
         MKDEBUG && _d("Next value:", $val);
         if ( $quote_char ) {
            MKDEBUG && _d("Value is part of previous quoted value");
            $vals[-1] .= ",$val";

            if ( $val =~ m/[^\\]*$quote_char$/ ) {
               if ( $args{remove_quotes} ) {
                  $vals[-1] =~ s/^\s*$quote_char//;
                  $vals[-1] =~ s/$quote_char\s*$//;
               }
               MKDEBUG && _d("Previous quoted value is complete:", $vals[-1]);
               $quote_char = '';
            }

            next VAL;
         }

         $val =~ s/^\s+//;

         if ( $val =~ m/^(['"])/ ) {
            MKDEBUG && _d("Value is quoted");
            $quote_char = $1;  # XXX
            if ( $val =~ m/.$quote_char$/ ) {
               MKDEBUG && _d("Value is complete");
               $quote_char = '';
               if ( $args{remove_quotes} ) {
                  $vals[-1] =~ s/^\s*$quote_char//;
                  $vals[-1] =~ s/$quote_char\s*$//;
               }
            }
            else {
               MKDEBUG && _d("Quoted value is not complete");
            }
         }
         else {
            $val =~ s/\s+$//;
         }

         MKDEBUG && _d("Saving value", ($quote_char ? "fragment" : ""));
         push @vals, $val;
      }
   }
   else {
      @vals = map { s/^\s+//; s/\s+$//; $_ } split(',', $vals);
   }

   return \@vals;
}
{
   no warnings;  # Why? See same line above.
   *parse_on_duplicate = \&_parse_csv;
}

sub parse_columns {
   my ( $self, $cols ) = @_;
   MKDEBUG && _d('Parsing columns list:', $cols);

   my @cols;
   pos $cols = 0;
   while (pos $cols < length $cols) {
      if ($cols =~ m/\G\s*$column_ident\s*(?>,|\Z)/gcxo) {
         my ($db_tbl_col, $as, $alias) = ($1, $2, $3); # XXX
         my $ident_struct = $self->parse_identifier('column', $db_tbl_col);
         $alias =~ s/`//g if $alias;
         my $col_struct = {
            %$ident_struct,
            ($as    ? (explicit_alias => 1)      : ()),
            ($alias ? (alias          => $alias) : ()),
         };
         push @cols, $col_struct;
      }
      else {
         die "Column ident match failed";  # shouldn't happen
      }
   }

   return \@cols;
}

sub remove_subqueries {
   my ( $self, $query ) = @_;

   my @start_pos;
   while ( $query =~ m/(\(SELECT )/gi ) {
      my $pos = (pos $query) - (length $1);
      push @start_pos, $pos;
   }

   @start_pos = reverse @start_pos;
   my @end_pos;
   for my $i ( 0..$#start_pos ) {
      my $closed = 0;
      pos $query = $start_pos[$i];
      while ( $query =~ m/([\(\)])/cg ) {
         my $c = $1;
         $closed += ($c eq '(' ? 1 : -1);
         last unless $closed;
      }
      push @end_pos, pos $query;
   }

   my @subqueries;
   my $len_adj = 0;
   my $n    = 0;
   for my $i ( 0..$#start_pos ) {
      MKDEBUG && _d('Query:', $query);
      my $offset = $start_pos[$i];
      my $len    = $end_pos[$i] - $start_pos[$i] - $len_adj;
      MKDEBUG && _d("Subquery $n start", $start_pos[$i],
            'orig end', $end_pos[$i], 'adj', $len_adj, 'adj end',
            $offset + $len, 'len', $len);

      my $struct   = {};
      my $token    = '__SQ' . $n . '__';
      my $subquery = substr($query, $offset, $len, $token);
      MKDEBUG && _d("Subquery $n:", $subquery);

      my $outer_start = $start_pos[$i + 1];
      my $outer_end   = $end_pos[$i + 1];
      if (    $outer_start && ($outer_start < $start_pos[$i])
           && $outer_end   && ($outer_end   > $end_pos[$i]) ) {
         MKDEBUG && _d("Subquery $n nested in next subquery");
         $len_adj += $len - length $token;
         $struct->{nested} = $i + 1;
      }
      else {
         MKDEBUG && _d("Subquery $n not nested");
         $len_adj = 0;
         if ( $subqueries[-1] && $subqueries[-1]->{nested} ) {
            MKDEBUG && _d("Outermost subquery");
         }
      }

      if ( $query =~ m/(?:=|>|<|>=|<=|<>|!=|<=>)\s*$token/ ) {
         $struct->{context} = 'scalar';
      }
      elsif ( $query =~ m/\b(?:IN|ANY|SOME|ALL|EXISTS)\s*$token/i ) {
         if ( $query !~ m/\($token\)/ ) {
            $query =~ s/$token/\($token\)/;
            $len_adj -= 2 if $struct->{nested};
         }
         $struct->{context} = 'list';
      }
      else {
         $struct->{context} = 'identifier';
      }
      MKDEBUG && _d("Subquery $n context:", $struct->{context});

      $subquery =~ s/^\s*\(//;
      $subquery =~ s/\s*\)\s*$//;

      $struct->{query} = $subquery;
      push @subqueries, $struct;
      $n++;
   }

   return $query, @subqueries;
}

sub parse_identifiers {
   my ( $self, $idents ) = @_;
   return unless $idents;
   MKDEBUG && _d("Parsing identifiers");

   my @ident_parts;
   foreach my $ident ( @$idents ) {
      MKDEBUG && _d("Identifier:", $ident);
      my $parts = {};

      if ( $ident =~ s/\s+(ASC|DESC)\s*$//i ) {
         $parts->{sort} = uc $1;  # XXX
      }

      if ( $ident =~ m/^\d+$/ ) {      # Position like 5
         MKDEBUG && _d("Positional ident");
         $parts->{position} = $ident;
      }
      elsif ( $ident =~ m/^\w+\(/ ) {  # Function like MIN(col)
         MKDEBUG && _d("Expression ident");
         my ($func, $expr) = $ident =~ m/^(\w+)\(([^\)]*)\)/;
         $parts->{function}   = uc $func;
         $parts->{expression} = $expr if $expr;
      }
      else {                           # Ref like (table.)column
         MKDEBUG && _d("Table/column ident");
         my ($tbl, $col)  = $self->split_unquote($ident);
         $parts->{table}  = $tbl if $tbl;
         $parts->{column} = $col;
      }
      push @ident_parts, $parts;
   }

   return \@ident_parts;
}

sub parse_identifier {
   my ( $self, $type, $ident ) = @_;
   return unless $type && $ident;
   MKDEBUG && _d("Parsing", $type, "identifier:", $ident);

   my %ident_struct;
   my @ident_parts = map { s/`//g; $_; } split /[.]/, $ident;
   if ( @ident_parts == 3 ) {
      @ident_struct{qw(db tbl col)} = @ident_parts;
   }
   elsif ( @ident_parts == 2 ) {
      my @parts_for_type = $type eq 'column' ? qw(tbl col)
                         : $type eq 'table'  ? qw(db  tbl)
                         : die "Invalid identifier type: $type";
      @ident_struct{@parts_for_type} = @ident_parts;
   }
   elsif ( @ident_parts == 1 ) {
      my $part = $type eq 'column' ? 'col' : 'tbl';
      @ident_struct{($part)} = @ident_parts;
   }
   else {
      die "Invalid number of parts in $type reference: $ident";
   }
   
   if ( $self->{SchemaQualifier} ) {
      if ( $type eq 'column' && !$ident_struct{tbl} ) {
         my $qcol = $self->{SchemaQualifier}->qualify_column(
            column => $ident_struct{col},
         );
         $ident_struct{db}  = $qcol->{db}  if $qcol->{db};
         $ident_struct{tbl} = $qcol->{tbl} if $qcol->{tbl};
      }
      elsif ( $type eq 'table' && !$ident_struct{db} ) {
         my $db = $self->{SchemaQualifier}->get_database_for_table(
            table => $ident_struct{tbl},
         );
         $ident_struct{db} = $db if $db;
      }
   }

   MKDEBUG && _d($type, "identifier struct:", Dumper(\%ident_struct));
   return \%ident_struct;
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

sub is_identifier {
   my ( $self, $thing ) = @_;

   return 0 unless $thing;

   return 0 if $thing =~ m/\s*['"]/;

   return 0 if $thing =~ m/^\s*\d+(?:\.\d+)?\s*$/;

   return 0 if $thing =~ m/^\s*(?>
       NULL
      |DUAL
   )\s*$/xi;

   return 1 if $thing =~ m/^\s*$column_ident\s*$/;

   return 0;
}

sub set_SchemaQualifier {
   my ( $self, $sq ) = @_;
   $self->{SchemaQualifier} = $sq;
   return;
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
# End SQLParser package
# ###########################################################################

# ###########################################################################
# TableUsage package 7498
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TableUsage.pm
#   trunk/common/t/TableUsage.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package TableUsage;

{ # package scope
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
   my @required_args = qw(QueryParser SQLParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $self = {
      constant_data_value => 'DUAL',

      %args,
   };

   return bless $self, $class;
}

sub get_table_usage {
   my ( $self, %args ) = @_;
   my @required_args = qw(query);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($query)   = @args{@required_args};
   MKDEBUG && _d('Getting table access for',
      substr($query, 0, 100), (length $query > 100 ? '...' : ''));

   my $cats;  # arrayref of CAT hashrefs for each table

   my $query_struct;
   eval {
      $query_struct = $self->{SQLParser}->parse($query);
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d('Failed to parse query with SQLParser:', $EVAL_ERROR);
      if ( $EVAL_ERROR =~ m/Cannot parse/ ) {
         $cats = $self->_get_tables_used_from_query_parser(%args);
      }
      else {
         die $EVAL_ERROR;
      }
   }
   else {
      $cats = $self->_get_tables_used_from_query_struct(
         query_struct => $query_struct,
         %args,
      );
   }

   MKDEBUG && _d('Query table access:', Dumper($cats));
   return $cats;
}

sub _get_tables_used_from_query_parser {
   my ( $self, %args ) = @_;
   my @required_args = qw(query);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($query) = @args{@required_args};
   MKDEBUG && _d('Getting tables used from query parser');

   $query = $self->{QueryParser}->clean_query($query);
   my ($query_type) = $query =~ m/^\s*(\w+)\s+/;
   $query_type = uc $query_type;
   die "Query does not begin with a word" unless $query_type; # shouldn't happen

   if ( $query_type eq 'DROP' ) {
      my ($drop_what) = $query =~ m/^\s*DROP\s+(\w+)\s+/i;
      die "Invalid DROP query: $query" unless $drop_what;
      $query_type .= '_' . uc($drop_what);
   }

   my @tables_used;
   foreach my $table ( $self->{QueryParser}->get_tables($query) ) {
      $table =~ s/`//g;
      push @{$tables_used[0]}, {
         table   => $table,
         context => $query_type,
      };
   }

   return \@tables_used;
}

sub _get_tables_used_from_query_struct {
   my ( $self, %args ) = @_;
   my @required_args = qw(query_struct);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($query_struct) = @args{@required_args};
   my $sp             = $self->{SQLParser};

   MKDEBUG && _d('Getting table used from query struct');

   my $query_type = uc $query_struct->{type};
   my $tbl_refs   = $query_type =~ m/(?:SELECT|DELETE)/  ? 'from'
                  : $query_type =~ m/(?:INSERT|REPLACE)/ ? 'into'
                  : $query_type =~ m/UPDATE/             ? 'tables'
                  : die "Cannot find table references for $query_type queries";
   my $tables     = $query_struct->{$tbl_refs};

   if ( !$tables || @$tables == 0 ) {
      MKDEBUG && _d("Query does not use any tables");
      return [
         [ { context => $query_type, table => $self->{constant_data_value} } ]
      ];
   }

   my $where;
   if ( $query_struct->{where} ) {
      $where = $self->_get_tables_used_in_where(
         %args,
         tables  => $tables,
         where   => $query_struct->{where},
      );
   }

   my @tables_used;
   if ( $query_type eq 'UPDATE' && @{$query_struct->{tables}} > 1 ) {
      MKDEBUG && _d("Multi-table UPDATE");

      my @join_tables;
      foreach my $table ( @$tables ) {
         my $table = $self->_qualify_table_name(
            %args,
            tables => $tables,
            db     => $table->{db},
            tbl    => $table->{tbl},
         );
         my $table_usage = {
            context => 'JOIN',
            table   => $table,
         };
         MKDEBUG && _d("Table usage from TLIST:", Dumper($table_usage));
         push @join_tables, $table_usage;
      }
      if ( $where && $where->{joined_tables} ) {
         foreach my $table ( @{$where->{joined_tables}} ) {
            my $table_usage = {
               context => $query_type,
               table   => $table,
            };
            MKDEBUG && _d("Table usage from WHERE (implicit join):",
               Dumper($table_usage));
            push @join_tables, $table_usage;
         }
      }

      my @where_tables;
      if ( $where && $where->{filter_tables} ) {
         foreach my $table ( @{$where->{filter_tables}} ) {
            my $table_usage = {
               context => 'WHERE',
               table   => $table,
            };
            MKDEBUG && _d("Table usage from WHERE:", Dumper($table_usage));
            push @where_tables, $table_usage;
         }
      }

      my $set_tables = $self->_get_tables_used_in_set(
         %args,
         tables  => $tables,
         set     => $query_struct->{set},
      );
      foreach my $table ( @$set_tables ) {
         my @table_usage = (
            {  # the written table
               context => 'UPDATE',
               table   => $table->{table},
            },
            {  # source of data written to the written table
               context => 'SELECT',
               table   => $table->{value},
            },
         );
         MKDEBUG && _d("Table usage from UPDATE SET:", Dumper(\@table_usage));
         push @tables_used, [
            @table_usage,
            @join_tables,
            @where_tables,
         ];
      }
   } # multi-table UPDATE
   else {
      if ( $query_type eq 'SELECT' ) {
         my $clist_tables = $self->_get_tables_used_in_columns(
            %args,
            tables  => $tables,
            columns => $query_struct->{columns},
         );
         foreach my $table ( @$clist_tables ) {
            my $table_usage = {
               context => 'SELECT',
               table   => $table,
            };
            MKDEBUG && _d("Table usage from CLIST:", Dumper($table_usage));
            push @{$tables_used[0]}, $table_usage;
         }
      }

      if ( @$tables > 1 || $query_type ne 'SELECT' ) {
         my $default_context = @$tables > 1 ? 'TLIST' : $query_type;
         foreach my $table ( @$tables ) {
            my $qualified_table = $self->_qualify_table_name(
               %args,
               tables => $tables,
               db     => $table->{db},
               tbl    => $table->{tbl},
            );

            my $context = $default_context;
            if ( $table->{join} && $table->{join}->{condition} ) {
                $context = 'JOIN';
               if ( $table->{join}->{condition} eq 'using' ) {
                  MKDEBUG && _d("Table joined with USING condition");
                  my $joined_table  = $self->_qualify_table_name(
                     %args,
                     tables => $tables,
                     tbl    => $table->{join}->{to},
                  );
                  $self->_change_context(
                     tables      => $tables,
                     table       => $joined_table,
                     tables_used => $tables_used[0],
                     old_context => 'TLIST',
                     new_context => 'JOIN',
                  );
               }
               elsif ( $table->{join}->{condition} eq 'on' ) {
                  MKDEBUG && _d("Table joined with ON condition");
                  my $on_tables = $self->_get_tables_used_in_where(
                     %args,
                     tables => $tables,
                     where  => $table->{join}->{where},
                     clause => 'JOIN condition',  # just for debugging
                  );
                  MKDEBUG && _d("JOIN ON tables:", Dumper($on_tables));
                  foreach my $joined_table ( @{$on_tables->{joined_tables}} ) {
                     $self->_change_context(
                        tables      => $tables,
                        table       => $joined_table,
                        tables_used => $tables_used[0],
                        old_context => 'TLIST',
                        new_context => 'JOIN',
                     );
                  }
               }
               else {
                  warn "Unknown JOIN condition: $table->{join}->{condition}";
               }
            }

            my $table_usage = {
               context => $context,
               table   => $qualified_table,
            };
            MKDEBUG && _d("Table usage from TLIST:", Dumper($table_usage));
            push @{$tables_used[0]}, $table_usage;
         }
      }

      if ( $where && $where->{joined_tables} ) {
         foreach my $joined_table ( @{$where->{joined_tables}} ) {
            MKDEBUG && _d("Table joined implicitly in WHERE:", $joined_table);
            $self->_change_context(
               tables      => $tables,
               table       => $joined_table,
               tables_used => $tables_used[0],
               old_context => 'TLIST',
               new_context => 'JOIN',
            );
         }
      }

      if ( $query_type =~ m/(?:INSERT|REPLACE)/ ) {
         if ( $query_struct->{select} ) {
            MKDEBUG && _d("Getting tables used in INSERT-SELECT");
            my $select_tables = $self->_get_tables_used_from_query_struct(
               %args,
               query_struct => $query_struct->{select},
            );
            push @{$tables_used[0]}, @{$select_tables->[0]};
         }
         else {
            my $table_usage = {
               context => 'SELECT',
               table   => $self->{constant_data_value},
            };
            MKDEBUG && _d("Table usage from SET/VALUES:", Dumper($table_usage));
            push @{$tables_used[0]}, $table_usage;
         }
      }
      elsif ( $query_type eq 'UPDATE' ) {
         my $set_tables = $self->_get_tables_used_in_set(
            %args,
            tables => $tables,
            set    => $query_struct->{set},
         );
         foreach my $table ( @$set_tables ) {
            my $table_usage = {
               context => 'SELECT',
               table   => $table->{value_is_table} ? $table->{table}
                        :                            $self->{constant_data_value},
            };
            MKDEBUG && _d("Table usage from SET:", Dumper($table_usage));
            push @{$tables_used[0]}, $table_usage;
         }
      }

      if ( $where && $where->{filter_tables} ) {
         foreach my $table ( @{$where->{filter_tables}} ) {
            my $table_usage = {
               context => 'WHERE',
               table   => $table,
            };
            MKDEBUG && _d("Table usage from WHERE:", Dumper($table_usage));
            push @{$tables_used[0]}, $table_usage;
         }
      }
   }

   return \@tables_used;
}

sub _get_tables_used_in_columns {
   my ( $self, %args ) = @_;
   my @required_args = qw(tables columns);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tables, $columns) = @args{@required_args};

   MKDEBUG && _d("Getting tables used in CLIST");
   my @tables;

   if ( @$tables == 1 ) {
      MKDEBUG && _d("Single table SELECT:", $tables->[0]->{tbl});
      my $table = $self->_qualify_table_name(
         %args,
         db  => $tables->[0]->{db},
         tbl => $tables->[0]->{tbl},
      );
      @tables = ($table);
   }
   elsif ( @$columns == 1 && $columns->[0]->{col} eq '*' ) {
      if ( $columns->[0]->{tbl} ) {
         MKDEBUG && _d("SELECT all columns from one table");
         my $table = $self->_qualify_table_name(
            %args,
            db  => $columns->[0]->{db},
            tbl => $columns->[0]->{tbl},
         );
         @tables = ($table);
      }
      else {
         MKDEBUG && _d("SELECT all columns from all tables");
         foreach my $table ( @$tables ) {
            my $table = $self->_qualify_table_name(
               %args,
               tables => $tables,
               db     => $table->{db},
               tbl    => $table->{tbl},
            );
            push @tables, $table;
         }
      }
   }
   else {
      MKDEBUG && _d(scalar @$tables, "table SELECT");
      my %seen;
      COLUMN:
      foreach my $column ( @$columns ) {
         next COLUMN unless $column->{tbl};
         my $table = $self->_qualify_table_name(
            %args,
            db  => $column->{db},
            tbl => $column->{tbl},
         );
         push @tables, $table if $table && !$seen{$table}++;
      }
   }

   return \@tables;
}

sub _get_tables_used_in_where {
   my ( $self, %args ) = @_;
   my @required_args = qw(tables where);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tables, $where) = @args{@required_args};
   my $sql_parser = $self->{SQLParser};

   MKDEBUG && _d("Getting tables used in", $args{clause} || 'WHERE');

   my %filter_tables;
   my %join_tables;
   CONDITION:
   foreach my $cond ( @$where ) {
      MKDEBUG && _d("Condition:", Dumper($cond));
      my @tables;  # tables used in this condition
      my $n_vals        = 0;
      my $is_constant   = 0;
      my $unknown_table = 0;
      ARG:
      foreach my $arg ( qw(left_arg right_arg) ) {
         if ( !defined $cond->{$arg} ) {
            MKDEBUG && _d($arg, "is a constant value");
            $is_constant = 1;
            next ARG;
         }

         if ( $sql_parser->is_identifier($cond->{$arg}) ) {
            MKDEBUG && _d($arg, "is an identifier");
            my $ident_struct = $sql_parser->parse_identifier(
               'column',
               $cond->{$arg}
            );

            if ( !$ident_struct->{tbl} ) {
               if ( @$tables == 1 ) {
                  MKDEBUG && _d("Condition column is not table-qualified; ",
                     "using query's only table:", $tables->[0]->{tbl});
                  $ident_struct->{tbl} = $tables->[0]->{tbl};
               }
               else {
                  MKDEBUG && _d("Condition column is not table-qualified and",
                     "query has multiple tables; cannot determine its table");
                  if (  $cond->{$arg} !~ m/\w+\(/       # not a function
                     && $cond->{$arg} !~ m/^[\d.]+$/) { # not a number
                     $unknown_table = 1;
                  }
                  next ARG;
               }
            }

            if ( !$ident_struct->{db} && @$tables == 1 && $tables->[0]->{db} ) {
               MKDEBUG && _d("Condition column is not database-qualified; ",
                  "using its table's database:", $tables->[0]->{db});
               $ident_struct->{db} = $tables->[0]->{db};
            }

            my $table = $self->_qualify_table_name(
               %args,
               %$ident_struct,
            );
            if ( $table ) {
               push @tables, $table;
            }
         }
         else {
            MKDEBUG && _d($arg, "is a value");
            $n_vals++;
         }
      }  # ARG

      if ( $is_constant || $n_vals == 2 ) {
         MKDEBUG && _d("Condition is a constant or two values");
         $filter_tables{$self->{constant_data_value}} = undef;
      }
      else {
         if ( @tables == 1 ) {
            if ( $unknown_table ) {
               MKDEBUG && _d("Condition joins table",
                  $tables[0], "to column from unknown table");
               $join_tables{$tables[0]} = undef;
            }
            else {
               MKDEBUG && _d("Condition filters table", $tables[0]);
               $filter_tables{$tables[0]} = undef;
            }
         }
         elsif ( @tables == 2 ) {
            MKDEBUG && _d("Condition joins tables",
               $tables[0], "and", $tables[1]);
            $join_tables{$tables[0]} = undef;
            $join_tables{$tables[1]} = undef;
         }
      }
   }  # CONDITION

   return {
      filter_tables => [ sort keys %filter_tables ],
      joined_tables => [ sort keys %join_tables   ],
   };
}

sub _get_tables_used_in_set {
   my ( $self, %args ) = @_;
   my @required_args = qw(tables set);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tables, $set) = @args{@required_args};
   my $sql_parser = $self->{SQLParser};

   MKDEBUG && _d("Getting tables used in SET");

   my @tables;
   if ( @$tables == 1 ) {
      my $table = $self->_qualify_table_name(
         %args,
         db  => $tables->[0]->{db},
         tbl => $tables->[0]->{tbl},
      );
      $tables[0] = {
         table => $table,
         value => $self->{constant_data_value}
      };
   }
   else {
      foreach my $cond ( @$set ) {
         next unless $cond->{tbl};
         my $table = $self->_qualify_table_name(
            %args,
            db  => $cond->{db},
            tbl => $cond->{tbl},
         );

         my $value          = $self->{constant_data_value};
         my $value_is_table = 0;
         if ( $sql_parser->is_identifier($cond->{value}) ) {
            my $ident_struct = $sql_parser->parse_identifier(
               'column',
               $cond->{value},
            );
            $value_is_table = 1;
            $value          = $self->_qualify_table_name(
               %args,
               db  => $ident_struct->{db},
               tbl => $ident_struct->{tbl},
            );
         }

         push @tables, {
            table          => $table,
            value          => $value,
            value_is_table => $value_is_table,
         };
      }
   }

   return \@tables;
}

sub _get_real_table_name {
   my ( $self, %args ) = @_;
   my @required_args = qw(tables name);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tables, $name) = @args{@required_args};

   foreach my $table ( @$tables ) {
      if ( $table->{tbl} eq $name
           || ($table->{alias} || "") eq $name ) {
         MKDEBUG && _d("Real table name for", $name, "is", $table->{tbl});
         return $table->{tbl};
      }
   }
   MKDEBUG && _d("Table", $name, "does not exist in query");
   return;
}

sub _qualify_table_name {
   my ( $self, %args) = @_;
   my @required_args = qw(tables tbl);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tables, $table) = @args{@required_args};

   MKDEBUG && _d("Qualifying table with database:", $table);

   my ($tbl, $db) = reverse split /[.]/, $table;

   $tbl = $self->_get_real_table_name(%args, name => $tbl);
   return unless $tbl;  # shouldn't happen

   my $db_tbl;

   if ( $db ) {
      $db_tbl = "$db.$tbl";
   }
   elsif ( $args{db} ) {
      $db_tbl = "$args{db}.$tbl";
   }
   else {
      foreach my $tbl_info ( @$tables ) {
         if ( ($tbl_info->{tbl} eq $tbl) && $tbl_info->{db} ) {
            $db_tbl = "$tbl_info->{db}.$tbl";
            last;
         }
      }

      if ( !$db_tbl && $args{default_db} ) { 
         $db_tbl = "$args{default_db}.$tbl";
      }

      if ( !$db_tbl ) {
         MKDEBUG && _d("Cannot determine database for table", $tbl);
         $db_tbl = $tbl;
      }
   }

   MKDEBUG && _d("Table qualified with database:", $db_tbl);
   return $db_tbl;
}

sub _change_context {
   my ( $self, %args) = @_;
   my @required_args = qw(tables_used table old_context new_context tables);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tables_used, $table, $old_context, $new_context) = @args{@required_args};
   MKDEBUG && _d("Change context of table", $table, "from", $old_context,
      "to", $new_context);
   foreach my $used_table ( @$tables_used ) {
      if (    $used_table->{table}   eq $table
           && $used_table->{context} eq $old_context ) {
         $used_table->{context} = $new_context;
         return;
      }
   }
   MKDEBUG && _d("Table", $table, "is not used; cannot set its context");
   return;
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
# End TableUsage package
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
# Runtime package 7221
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Runtime.pm
#   trunk/common/t/Runtime.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package Runtime;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw(now);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   if ( ($args{runtime} || 0) < 0 ) {
      die "runtime argument must be greater than zero"
   }

   my $self = {
      %args,
      start_time => undef,
      end_time   => undef,
      time_left  => undef,
      stop       => 0,
   };

   return bless $self, $class;
}

sub time_left {
   my ( $self, %args ) = @_;

   if ( $self->{stop} ) {
      MKDEBUG && _d("No time left because stop was called");
      return 0;
   }

   my $now = $self->{now}->(%args);
   MKDEBUG && _d("Current time:", $now);

   if ( !defined $self->{start_time} ) {
      $self->{start_time} = $now;
   }

   return unless defined $now;

   my $runtime = $self->{runtime};
   return unless defined $runtime;

   if ( !$self->{end_time} ) {
      $self->{end_time} = $now + $runtime;
      MKDEBUG && _d("End time:", $self->{end_time});
   }

   $self->{time_left} = $self->{end_time} - $now;
   MKDEBUG && _d("Time left:", $self->{time_left});
   return $self->{time_left};
}

sub have_time {
   my ( $self, %args ) = @_;
   my $time_left = $self->time_left(%args);
   return 1 if !defined $time_left;  # run forever
   return $time_left <= 0 ? 0 : 1;   # <=0s means runtime has elapsed
}

sub time_elapsed {
   my ( $self, %args ) = @_;

   my $start_time = $self->{start_time};
   return 0 unless $start_time;

   my $now = $self->{now}->(%args);
   MKDEBUG && _d("Current time:", $now);

   my $time_elapsed = $now - $start_time;
   MKDEBUG && _d("Time elapsed:", $time_elapsed);
   if ( $time_elapsed < 0 ) {
      warn "Current time $now is earlier than start time $start_time";
   }
   return $time_elapsed;
}

sub reset {
   my ( $self ) = @_;
   $self->{start_time} = undef;
   $self->{end_time}   = undef;
   $self->{time_left}  = undef;
   $self->{stop}       = 0;
   MKDEBUG && _d("Reset runtime");
   return;
}

sub stop {
   my ( $self ) = @_;
   $self->{stop} = 1;
   return;
}

sub start {
   my ( $self ) = @_;
   $self->{stop} = 0;
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
# End Runtime package
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
# Pipeline package 7509
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Pipeline.pm
#   trunk/common/t/Pipeline.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package Pipeline;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;
use Time::HiRes qw(time);

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }

   my $self = {
      instrument        => 0,
      continue_on_error => 0,

      %args,

      procs           => [],  # coderefs for pipeline processes
      names           => [],  # names for each ^ pipeline proc
      instrumentation => {    # keyed on proc index in procs
         Pipeline => {
            time  => 0,
            calls => 0,
         },
      },
   };
   return bless $self, $class;
}

sub add {
   my ( $self, %args ) = @_;
   my @required_args = qw(process name);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless defined $args{$arg};
   }
   my ($process, $name) = @args{@required_args};

   push @{$self->{procs}}, $process;
   push @{$self->{names}}, $name;
   if ( $self->{instrument} ) {
      $self->{instrumentation}->{$name} = { time => 0, calls => 0 };
   }
   MKDEBUG && _d("Added pipeline process", $name);

   return;
}

sub processes {
   my ( $self ) = @_;
   return @{$self->{names}};
}

sub execute {
   my ( $self, %args ) = @_;

   die "Cannot execute pipeline because no process have been added"
      unless scalar @{$self->{procs}};

   my $oktorun = $args{oktorun};
   die "I need an oktorun argument" unless $oktorun;
   die '$oktorun argument must be a reference' unless ref $oktorun;

   my $pipeline_data = $args{pipeline_data} || {};
   $pipeline_data->{oktorun} = $oktorun;

   my $stats = $args{stats};  # optional

   MKDEBUG && _d("Pipeline starting at", time);
   my $instrument = $self->{instrument};
   my $processes  = $self->{procs};
   EVENT:
   while ( $$oktorun ) {
      my $procno  = 0;  # so we can see which proc if one causes an error
      my $output;
      eval {
         PIPELINE_PROCESS:
         while ( $procno < scalar @{$self->{procs}} ) {
            my $call_start = $instrument ? time : 0;

            MKDEBUG && _d("Pipeline process", $self->{names}->[$procno]);
            $output = $processes->[$procno]->($pipeline_data);

            if ( $instrument ) {
               my $call_end = time;
               my $call_t   = $call_end - $call_start;
               $self->{instrumentation}->{$self->{names}->[$procno]}->{time} += $call_t;
               $self->{instrumentation}->{$self->{names}->[$procno]}->{count}++;
               $self->{instrumentation}->{Pipeline}->{time} += $call_t;
               $self->{instrumentation}->{Pipeline}->{count}++;
            }
            if ( !$output ) {
               MKDEBUG && _d("Pipeline restarting early after",
                  $self->{names}->[$procno]);
               if ( $stats ) {
                  $stats->{"pipeline_restarted_after_"
                     .$self->{names}->[$procno]}++;
               }
               last PIPELINE_PROCESS;
            }
            $procno++;
         }
      };
      if ( $EVAL_ERROR ) {
         warn "Pipeline process $procno ("
            . ($self->{names}->[$procno] || "")
            . ") caused an error: $EVAL_ERROR";
         die $EVAL_ERROR unless $self->{continue_on_error};
      }
   }

   MKDEBUG && _d("Pipeline stopped at", time);
   return;
}

sub instrumentation {
   my ( $self ) = @_;
   return $self->{instrumentation};
}

sub reset {
   my ( $self ) = @_;
   foreach my $proc_name ( @{$self->{names}} ) {
      if ( exists $self->{instrumentation}->{$proc_name} ) {
         $self->{instrumentation}->{$proc_name}->{calls} = 0;
         $self->{instrumentation}->{$proc_name}->{time}  = 0;
      }
   }
   $self->{instrumentation}->{Pipeline}->{calls} = 0;
   $self->{instrumentation}->{Pipeline}->{time}  = 0;
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
# End Pipeline package
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
# MysqldumpParser package 7500
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/MysqldumpParser.pm
#   trunk/common/t/MysqldumpParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package MysqldumpParser;

{ # package scope
use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

my $open_comment = qr{/\*!\d{5} };

sub new {
   my ( $class, %args ) = @_;
   my @required_args = qw();
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
   };
   return bless $self, $class;
}

sub parse_create_tables {
   my ( $self, %args ) = @_;
   my @required_args = qw(file);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($file) = @args{@required_args};

   MKDEBUG && _d('Parsing CREATE TABLE from', $file);
   open my $fh, '<', $file
      or die "Cannot open $file: $OS_ERROR";

   local $INPUT_RECORD_SEPARATOR = '';

   my %schema;
   my $db = '';
   CHUNK:
   while (defined(my $chunk = <$fh>)) {
      MKDEBUG && _d('db:', $db, 'chunk:', $chunk);
      if ($chunk =~ m/Database: (\S+)/) {
         $db = $1; # XXX
         $db =~ s/^`//;  # strip leading `
         $db =~ s/`$//;  # and trailing `
         MKDEBUG && _d('New db:', $db);
      }
      elsif ($chunk =~ m/CREATE TABLE/) {
         MKDEBUG && _d('Chunk has CREATE TABLE');

         if ($chunk =~ m/DROP VIEW IF EXISTS/) {
            MKDEBUG && _d('Table is a VIEW, skipping');
            next CHUNK;
         }

         my ($create_table)
            = $chunk =~ m/^(?:$open_comment)?(CREATE TABLE.+?;)$/ms;
         if ( !$create_table ) {
            warn "Failed to parse CREATE TABLE from\n" . $chunk;
            next CHUNK;
         }
         $create_table =~ s/ \*\/;\Z/;/;  # remove end of version comment

         push @{$schema{$db}}, $create_table;
      }
      else {
         MKDEBUG && _d('Chunk has other data, ignoring');
      }
   }

   close $fh;

   return \%schema;
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
# End MysqldumpParser package
# ###########################################################################

# ###########################################################################
# SchemaQualifier package 7499
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/SchemaQualifier.pm
#   trunk/common/t/SchemaQualifier.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package SchemaQualifier;

{ # package scope
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
   my @required_args = qw(TableParser Quoter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
      schema                => {},  # db > tbl > col
      duplicate_column_name => {},
      duplicate_table_name  => {},
   };
   return bless $self, $class;
}

sub schema {
   my ( $self ) = @_;
   return $self->{schema};
}

sub get_duplicate_column_names {
   my ( $self ) = @_;
   return keys %{$self->{duplicate_column_name}};
}

sub get_duplicate_table_names {
   my ( $self ) = @_;
   return keys %{$self->{duplicate_table_name}};
}

sub set_schema_from_mysqldump {
   my ( $self, %args ) = @_;
   my @required_args = qw(dump);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($dump) = @args{@required_args};

   my $schema = $self->{schema};
   my $tp     = $self->{TableParser};
   my %column_name;
   my %table_name;

   DATABASE:
   foreach my $db (keys %$dump) {
      if ( !$db ) {
         warn "Empty database from parsed mysqldump output";
         next DATABASE;
      }

      TABLE:
      foreach my $table_def ( @{$dump->{$db}} ) {
         if ( !$table_def ) {
            warn "Empty CREATE TABLE for database $db parsed from mysqldump output";
            next TABLE;
         }
         my $tbl_struct = $tp->parse($table_def);
         $schema->{$db}->{$tbl_struct->{name}} = $tbl_struct->{is_col};

         map { $column_name{$_}++ } @{$tbl_struct->{cols}};
         $table_name{$tbl_struct->{name}}++;
      }
   }

   map { $self->{duplicate_column_name}->{$_} = 1 }
   grep { $column_name{$_} > 1 }
   keys %column_name;

   map { $self->{duplicate_table_name}->{$_} = 1 }
   grep { $table_name{$_} > 1 }
   keys %table_name;

   MKDEBUG && _d('Schema:', Dumper($schema));
   return;
}

sub qualify_column {
   my ( $self, %args ) = @_;
   my @required_args = qw(column);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($column) = @args{@required_args};

   MKDEBUG && _d('Qualifying', $column);
   my ($col, $tbl, $db) = reverse map { s/`//g; $_ } split /[.]/, $column;
   MKDEBUG && _d('Column', $column, 'has db', $db, 'tbl', $tbl, 'col', $col);

   my %qcol = (
      db  => $db,
      tbl => $tbl,
      col => $col,
   );
   if ( !$qcol{tbl} ) {
      @qcol{qw(db tbl)} = $self->get_table_for_column(column => $qcol{col});
   }
   elsif ( !$qcol{db} ) {
      $qcol{db} = $self->get_database_for_table(table => $qcol{tbl});
   }
   else {
      MKDEBUG && _d('Column is already database-table qualified');
   }

   return \%qcol;
}

sub get_table_for_column {
   my ( $self, %args ) = @_;
   my @required_args = qw(column);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($col) = @args{@required_args};
   MKDEBUG && _d('Getting table for column', $col);

   if ( $self->{duplicate_column_name}->{$col} ) {
      MKDEBUG && _d('Column name is duplicate, cannot qualify it');
      return;
   }

   my $schema = $self->{schema};
   foreach my $db ( keys %{$schema} ) {
      foreach my $tbl ( keys %{$schema->{$db}} ) {
         if ( $schema->{$db}->{$tbl}->{$col} ) {
            MKDEBUG && _d('Column is in database', $db, 'table', $tbl);
            return $db, $tbl;
         }
      }
   }

   MKDEBUG && _d('Failed to find column in any table');
   return;
}

sub get_database_for_table {
   my ( $self, %args ) = @_;
   my @required_args = qw(table);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($tbl) = @args{@required_args};
   MKDEBUG && _d('Getting database for table', $tbl);
   
   if ( $self->{duplicate_table_name}->{$tbl} ) {
      MKDEBUG && _d('Table name is duplicate, cannot qualify it');
      return;
   }

   my $schema = $self->{schema};
   foreach my $db ( keys %{$schema} ) {
     if ( $schema->{$db}->{$tbl} ) {
       MKDEBUG && _d('Table is in database', $db);
       return $db;
     }
   }

   MKDEBUG && _d('Failed to find table in any database');
   return;
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
# End SchemaQualifier package
# ###########################################################################

# ###########################################################################
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_table_usage;

use English qw(-no_match_vars);
use Data::Dumper;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use sigtrap 'handler', \&sig_int, 'normal-signals';

Transformers->import(qw(make_checksum));

# Global variables.  Only really essential variables should be here.
my $oktorun = 1;

sub main {
   @ARGV    = @_;  # set global ARGV for this package
   $oktorun = 1;   # reset between tests else pipeline won't run

   # ########################################################################
   # Get configuration information.
   # ########################################################################
   my $o = new OptionParser();
   $o->get_specs();
   $o->get_opts();

   my $dp = $o->DSNParser();
   $dp->prop('set-vars', $o->get('set-vars'));

   $o->usage_or_errors();

   # ########################################################################
   # Connect to MySQl for --explain-extended.
   # ########################################################################
   my $explain_ext_dbh;
   if ( my $dsn = $o->get('explain-extended') ) {
      $explain_ext_dbh = get_cxn(
         dsn          => $dsn,
         OptionParser => $o,
         DSNParser    => $dp,
      );
   }

   # ########################################################################
   # Make common modules.
   # ########################################################################
   my $qp = new QueryParser();
   my $qr = new QueryRewriter(QueryParser => $qp);
   my $sp = new SQLParser();
   my $tu = new TableUsage(
      constant_data_value => $o->get('constant-data-value'),
      QueryParser         => $qp,
      SQLParser           => $sp,
   );
   my %common_modules = (
      OptionParser  => $o,
      DSNParser     => $dp,
      QueryParser   => $qp,
      QueryRewriter => $qr,
   );

   # ########################################################################
   # Parse the --create-table-definitions files.
   # ########################################################################
   if ( my $files = $o->get('create-table-definitions') ) {
      my $q  = new Quoter();
      my $tp = new TableParser(Quoter => $q);
      my $sq = new SchemaQualifier(TableParser => $tp, Quoter => $q);

      my $dump_parser = new MysqldumpParser();
      FILE:
      foreach my $file ( @$files ) {
         my $dump = $dump_parser->parse_create_tables(file => $file);
         if ( !$dump || !keys %$dump ) {
            warn "No CREATE TABLE statements were found in $file";
            next FILE;
         }
         $sq->set_schema_from_mysqldump(dump => $dump); 
      }
      $sp->set_SchemaQualifier($sq);
   }

   # ########################################################################
   # Set up an array of callbacks.
   # ########################################################################
   my $pipeline_data = {
      # Add here any data to inject into the pipeline.
      # This hashref is $args in each pipeline process.
   };
   my $pipeline = new Pipeline(
      instrument        => 0,
      continue_on_error => $o->get('continue-on-error'),
   );

   { # prep
      $pipeline->add(
         name    => 'prep',
         process => sub {
            my ( $args ) = @_;
            # Stuff you'd like to do to make sure pipeline data is prepped
            # and ready to go...

            $args->{event} = undef;  # remove event from previous pass

            if ( $o->got('query') ) {
               if ( $args->{query} ) {
                  delete $args->{query};  # terminate
               }
               else {
                  $args->{query} = $o->get('query');  # analyze query once
               }
            }

            return $args;
         },
      );
   } # prep

   { # input
      my $fi        = new FileIterator();
      my $next_file = $fi->get_file_itr(@ARGV);
      my $input_fh; # the current input fh
      my $pr;       # Progress obj for ^

      $pipeline->add(
         name    => 'input',
         process => sub {
            my ( $args ) = @_;

            if ( $o->got('query') ) {
               MKDEBUG && _d("No input; using --query");
               return $args;
            }

            # Only get the next file when there's no fh or no more events in
            # the current fh.  This allows us to do collect-and-report cycles
            # (i.e. iterations) on huge files.  This doesn't apply to infinite
            # inputs because they don't set more_events false.
            if ( !$args->{input_fh} || !$args->{more_events} ) {
               if ( $args->{input_fh} ) {
                  close $args->{input_fh}
                     or die "Cannot close input fh: $OS_ERROR";
               }
               my ($fh, $filename, $filesize) = $next_file->();
               if ( $fh ) {
                  MKDEBUG && _d('Reading', $filename);

                  # Create callback to read next event.  Some inputs, like
                  # Processlist, may use something else but most next_event.
                  if ( my $read_time = $o->get('read-timeout') ) {
                     $args->{next_event}
                        = sub { return read_timeout($fh, $read_time); };
                  }
                  else {
                     $args->{next_event} = sub { return <$fh>; };
                  }
                  $args->{input_fh}    = $fh;
                  $args->{tell}        = sub { return tell $fh; };
                  $args->{more_events} = 1;

                  # Make a progress reporter, one per file.
                  if ( $o->get('progress') && $filename && -e $filename ) {
                     $pr = new Progress(
                        jobsize => $filesize,
                        spec    => $o->get('progress'),
                        name    => $filename,
                     );
                  }
               }
               else {
                  MKDEBUG && _d("No more input");
                  # This will cause terminator proc to terminate the pipeline.
                  $args->{input_fh}    = undef;
                  $args->{more_events} = 0;
               }
            }
            $pr->update($args->{tell}) if $pr;
            return $args;
         },
      );
   } # input

   { # event
      if ( $o->got('query') ) {
         $pipeline->add(
            name    => '--query',
            process => sub {
               my ( $args ) = @_;
               if ( $args->{query} ) {
                  $args->{event}->{arg} = $args->{query};
               }
               return $args;
            },
         );
      }
      else {
         # Only slowlogs are supported, but if we want parse other formats,
         # just tweak the code below to be like mk-query-digest.
         my %alias_for = (
            slowlog   => ['SlowLogParser'],
            # binlog    => ['BinaryLogParser'],
            # genlog    => ['GeneralLogParser'],
            # tcpdump   => ['TcpdumpParser','MySQLProtocolParser'],
         );
         my $type = ['slowlog'];
         $type    = $alias_for{$type->[0]} if $alias_for{$type->[0]};

         foreach my $module ( @$type ) {
            my $parser;
            eval {
               $parser = $module->new(
                  o => $o,
               );
            };
            if ( $EVAL_ERROR ) {
               die "Failed to load $module module: $EVAL_ERROR";
            }
            
            $pipeline->add(
               name    => ref $parser,
               process => sub {
                  my ( $args ) = @_;
                  if ( $args->{input_fh} ) {
                     my $event = $parser->parse_event(
                        event       => $args->{event},
                        next_event  => $args->{next_event},
                        tell        => $args->{tell},
                        oktorun     => sub { $args->{more_events} = $_[0]; },
                     );
                     if ( $event ) {
                        $args->{event} = $event;
                        return $args;
                     }
                     MKDEBUG && _d("No more events, input EOF");
                     return;  # next input
                  }
                  # No input, let pipeline run so the last report is printed.
                  return $args;
               },
            );
         }
      }
   } # event

   { # terminator
      my $runtime = new Runtime(
         now     => sub { return time },
         runtime => $o->get('run-time'),
      );

      $pipeline->add(
         name    => 'terminator',
         process => sub {
            my ( $args ) = @_;

            # Stop running if there's no more input.
            if ( !$args->{input_fh} && !$args->{query} ) {
               MKDEBUG && _d("No more input, terminating pipeline");

               # This shouldn't happen, but I want to know if it does.
               warn "Event in the pipeline but no current input: "
                     . Dumper($args)
                  if $args->{event};

               $oktorun = 0;  # 2. terminate pipeline
               return;        # 1. exit pipeline early
            }

            # Stop running if --run-time has elapsed.
            if ( !$runtime->have_time() ) {
               MKDEBUG && _d("No more time, terminating pipeline");
               $oktorun = 0;  # 2. terminate pipeline
               return;        # 1. exit pipeline early
            }

            # There's input and time left so keep runnning...
            if ( $args->{event} ) {
               MKDEBUG && _d("Event in pipeline, continuing");
               return $args;
            }
            else {
               MKDEBUG && _d("No event in pipeline, get next event");
               return;
            }
         },
      );
   } # terminator

   # ########################################################################
   # All pipeline processes after the terminator expect an event
   # (i.e. that $args->{event} exists and is a valid event).
   # ########################################################################

   if ( $o->get('filter') ) { # filter
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
      my $code = 'sub { my ( $args ) = @_; my $event = $args->{event}; '
               . "$filter && return \$args; };";
      MKDEBUG && _d('--filter code:', $code);
      my $sub = eval $code
         or die "Error compiling --filter code: $code\n$EVAL_ERROR";

      $pipeline->add(
         name    => 'filter',
         process => $sub,
      );
   } # filter

   if ( $explain_ext_dbh ) { # explain extended
      my $default_db = $o->get('database');

      $pipeline->add(
         name    => 'explain extended',
         process => sub {
            my ( $args ) = @_;
            my $query = $args->{event}->{arg};
            return unless $query;
            my $qualified_query;
            eval {
               $qualified_query = qualify_query(
                  query => $query,
                  dbh   => $explain_ext_dbh,
                  db    => $args->{event}->{db} || $default_db,
               );
            };
            if ( $EVAL_ERROR ) {
               warn $EVAL_ERROR;
               return;
            }
            $args->{event}->{original_arg} = $query;
            $args->{event}->{arg}          = $qualified_query;
            return $args;
         },
      );
   } # explain extended

   { # table usage
      my $default_db = $o->get('database');
      my $id_attrib  = $o->get('id-attribute');
      my $queryno    = 1;

      $pipeline->add(
         name    => 'table usage',
         process => sub {
            my ( $args ) = @_;
            my $event = $args->{event};
            my $query = $event->{arg};
            return unless $query;

            my $query_id;
            if ( $id_attrib ) {
               if (   !exists $event->{$id_attrib}
                   || !defined $event->{$id_attrib}) {
                  MKDEBUG && _d("Event", $id_attrib, "attrib doesn't exist",
                     "or isn't defined, skipping");
                  return;
               }
               $query_id = $event->{$id_attrib};
            }
            else {
               $query_id = "0x" . make_checksum(
                  $qr->fingerprint($event->{original_arg} || $event->{arg}));
            }

            my $table_usage = $tu->get_table_usage(
               query      => $query,
               default_db => $event->{db} || $default_db,
            );

            # TODO: I think this will happen for SELECT NOW(); i.e. not
            # sure what TableUsage returns for such queries.
            if ( !$table_usage || @$table_usage == 0 ) {
               MKDEBUG && _d("Query does not use any tables");
               return;
            }

            report_table_usage(
               table_usage => $table_usage,
               query_id    => $query_id,
               %common_modules,
            ); 

            return $args;
         },
      );
   } # table usage

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

   # ########################################################################
   # Parse the input.
   # ########################################################################

   # Pump the pipeline until either no more input, or we're interrupted by
   # CTRL-C, or--this shouldn't happen--the pipeline causes an error.  All
   # work happens inside the pipeline via the procs we created above.
   my $exit_status = 0;
   eval {
      $pipeline->execute(
         oktorun       => \$oktorun,
         pipeline_data => $pipeline_data,
      );
   };
   if ( $EVAL_ERROR ) {
      warn "The pipeline caused an error: $EVAL_ERROR";
      $exit_status = 1;
   }
   MKDEBUG && _d("Pipeline data:", Dumper($pipeline_data));

   $explain_ext_dbh->disconnect() if $explain_ext_dbh;

   return $exit_status;
} # End main().

# ###########################################################################
# Subroutines.
# ###########################################################################
sub report_table_usage {
   my ( %args ) = @_;
   my @required_args = qw(table_usage query_id);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($table_usage, $query_id) = @args{@required_args};
   MKDEBUG && _d("Reporting table usage");

   my $target_tbl_num = 1;
   TABLE:
   foreach my $table ( @$table_usage ) {
      print "Query_id: $query_id." . ($target_tbl_num++) . "\n";

      USAGE:
      foreach my $usage ( @$table ) {
         die "Invalid table usage: " . Dumper($usage)
            unless $usage->{context} && $usage->{table};

         print "$usage->{context} $usage->{table}\n";
      }
      print "\n";
   }

   return;
}

sub qualify_query {
   my ( %args ) = @_;
   my @required_args = qw(query dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($query, $dbh) = @args{@required_args};
   my $sql;

   if ( my $db = $args{db} ) {
      $sql = "USE $db";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   }

   $sql = "EXPLAIN EXTENDED $query";
   MKDEBUG && _d($dbh, $sql);
   $dbh->do($sql);  # don't need the result

   $sql = "SHOW WARNINGS";
   MKDEBUG && _d($dbh, $sql);
   my $warning = $dbh->selectrow_hashref($sql);
   if (    ($warning->{level} || "") !~ m/Note/i
        || ($warning->{code}  || 0)  != 1003 ) {
      die "EXPLAIN EXTENDED failed:\n"
         . "  Level: " . ($warning->{level}   || "") . "\n"
         . "   Code: " . ($warning->{code}    || "") . "\n"
         . "Message: " . ($warning->{message} || "") . "\n";
   }

   return $warning->{message};
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
   $dbh->{FetchHashKeyName} = 'NAME_lc';
   return $dbh;
}

sub sig_int {
   my ( $signal ) = @_;
   if ( $oktorun ) {
      print STDERR "# Caught SIG$signal.\n";
      $oktorun = 0;
   }
   else {
      print STDERR "# Exiting on SIG$signal.\n";
      exit(1);
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

mk-table-usage - Read queries from a log and analyze how they use tables.

=head1 SYNOPSIS

Usage: mk-table-usage [OPTION...] [FILE...]

mk-table-usage reads queries from slow query logs and analyzes how they use
tables.  If no FILE is specified, STDIN is read.  Table usage for every query
is printed to STDOUT.

=head1 RISKS

mk-table-use is very low risk because it only reads and examines queries from
a log and executes C<EXPLAIN EXTENDED> if the L<"--explain-extended"> option
is specified.

At the time of this release, there are no known bugs that could cause serious
harm to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-table-usage>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

mk-table-usage reads queries from slow query logs and analyzes how they use
tables.  Table usage indicates more than just which tables are read from or
written to by the query, it also indicates data flow: data in and data out.
Data flow is determined by the contexts in which tables are used by the query.
A single table can be used in several different contexts in the same query.
The reported table usage for each query lists every context for every table.
This CONTEXT-TABLE list tells how and where data flows, i.e. the query's table
usage.  The L<"OUTPUT"> section lists the possible contexts and describes how
to read a table usage report.

Since this tool analyzes table usage, it's important that queries use
table-qualified columns.  If a query uses only one table, then all columns
must be from that table and there's no problem.  But if a query uses
multiple tables and the columns are not table-qualified, then that creates a
problem that can only be solved by knowing the query's database and specifying
L<"--explain-extended">.  If the slow log does not specify the database
used by the query, then you can specify a default database with L<"--database">.
There is no other way to know or guess the database, so the query will be
skipped.  Secondly, if the database is known, then specifying
L<"--explain-extended"> causes mk-table-usage to do C<EXPLAIN EXTENDED ...>
C<SHOW WARNINGS> to get the fully qualified query as reported by MySQL
(i.e. all identifiers are fully database- and/or table-qualified).  For
best results, you should specify L<"--explain-extended"> and
L<"--database"> if you know that all queries use the same database.

Each query is identified in the output by either an MD5 hex checksum
of the query's fingerprint or the query's value for the specified
L<"--id-attribute">.  The query ID is for parsing and storing the table
usage reports in a table that is keyed on the query ID.  See L<"OUTPUT">
for more information.

=head1 OUTPUT

The table usage report that is printed for each query looks similar to the
following:

  Query_id: 0x1CD27577D202A339.1
  UPDATE t1
  SELECT DUAL
  JOIN t1
  JOIN t2
  WHERE t1

  Query_id: 0x1CD27577D202A339.2
  UPDATE t2
  SELECT DUAL
  JOIN t1
  JOIN t2
  WHERE t1

Usage reports are separated by blank lines.  The first line is always the
query ID: a unique ID that can be used to parse the output and store the
usage reports in a table keyed on this ID.  The query ID has two parts
separated by a period: the query ID and the target table number.

If L<"--id-attribute"> is not specified, then query IDs are automatically
created by making an MD5 hex checksum of the query's fingerprint
(as shown above, e.g. C<0x1CD27577D202A339>); otherwise, the query ID is the
query's value for the given attribute.

The target table number starts at 1 and increments by 1 for each table that
the query affects.  Only multi-table UPDATE queries can affect
multiple tables with a single query, so this number is 1 for all other types
of queries.  (Multi-table DELETE queries are not supported.)
The example output above is from this query:

  UPDATE t1 AS a JOIN t2 AS b USING (id)
  SET a.foo="bar", b.foo="bat"
  WHERE a.id=1;

The C<SET> clause indicates that two tables are updated: C<a> aliased as C<t1>,
and C<b> aliased as C<t2>.  So two usage reports are printed, one for each
table, and this is indicated in the output by their common query ID but
incrementing target table number.

After the first line is a variable number of CONTEXT-TABLE lines.  Possible
contexts are:

=over

=item * SELECT

SELECT means that data is taken out of the table for one of two reasons:
to be returned to the user as part of a result set, or to be put into another
table as part of an INSERT or UPDATE.  In the first case, since only SELECT
queries return result sets, a SELECT context is always listed for SELECT
queries.  In the second case, data from one table is used to insert or
update rows in another table.  For example, the UPDATE query in the example
above has the usage:

  SELECT DUAL

This refers to:

  SET a.foo="bar", b.foo="bat"

DUAL is used for any values that does not originate in a table, in this case the
literal values "bar" and "bat".  If that C<SET> clause were C<SET a.foo=b.foo>
instead, then the complete usage would be:

  Query_id: 0x1CD27577D202A339.1
  UPDATE t1
  SELECT t2
  JOIN t1
  JOIN t2
  WHERE t1

The presence of a SELECT context after another context, such as UPDATE or
INSERT, indicates where the UPDATE or INSERT retrieves its data.  The example
immediately above reflects an UPDATE query that updates rows in table C<t1>
with data from table C<t2>.

=item * Any other query type

Any other query type, such as INSERT, UPDATE, DELETE, etc. may be a context.
All these types indicate that the table is written or altered in some way.
If a SELECT context follows one of these types, then data is read from the
SELECT table and written to this table.  This happens, for example, with
INSERT..SELECT or UPDATE queries that set column values using values from
tables instead of constant values.

These query types are not supported:

  SET
  LOAD
  multi-table DELETE

=item * JOIN

The JOIN context lists tables that are joined, either with an explicit JOIN in
the FROM clause, or implicitly in the WHERE clause, such as C<t1.id = t2.id>.

=item * WHERE

The WHERE context lists tables that are used in the WHERE clause to filter
results.  This does not include tables that are implicitly joined in the
WHERE clause; those are listed as JOIN contexts.  For example:

  WHERE t1.id > 100 AND t1.id < 200 AND t2.foo IS NOT NULL

Results in:

  WHERE t1
  WHERE t2

Only unique tables are listed; that is why table C<t1> is listed only once.

=item * TLIST

The TLIST context lists tables that are accessed by the query but do not
appear in any other context.  These tables are usually an implicit
full cartesian join, so they should be avoided.  For example, the query
C<SELECT * FROM t1, t2> results in:

  Query_id: 0xBDDEB6EDA41897A8.1
  SELECT t1
  SELECT t2
  TLIST t1
  TLIST t2

First of all, there are two SELECT contexts, because C<SELECT *> selects
rows from all tables; C<t1> and C<t2> in this case.  Secondly, the tables
are implicitly joined, but without any kind of join condition, which results
in a full cartesian join as indicated by the TLIST context for each.

=back

=head1 EXIT STATUS

mk-table-usage exits 1 on any kind of error, or 0 if no errors.

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

=item --constant-data-value

type: string; default: DUAL

Value to print for constant data.  Constant data means all data not
from tables (or subqueries since subqueries are not supported).  For example,
real constant values like strings ("foo") and numbers (42), and data from
functions like C<NOW()>.  For example, in the query
C<INSERT INTO t (c) VALUES ('a')>, the string 'a' is constant data, so the
table usage report is:

  INSERT t
  SELECT DUAL

The first line indicates that data is inserted into table C<t> and the second
line indicates that that data comes from some constant value.

=item --[no]continue-on-error

default: yes

Continue parsing even if there is an error.

=item --create-table-definitions

type: array

Read C<CREATE TABLE> definitions from this list of comma-separated files.
If you cannot use L<"--explain-extended"> to fully qualify table and column
names, you can save the output of C<mysqldump --no-data> to one or more files
and specify those files with this option.  The tool will parse all
C<CREATE TABLE> definitions from the files and use this information to
qualify table and column names.  If a column name is used in multiple tables,
or table name is used in multiple databases, these duplicates cannot be
qualified.

=item --daemonize

Fork to the background and detach from the shell.  POSIX
operating systems only.

=item --database

short form: -D; type: string

Default database.

=item --defaults-file

short form: -F; type: string

Only read mysql options from the given file.  You must give an absolute pathname.

=item --explain-extended

type: DSN

EXPLAIN EXTENDED queries on this host to fully qualify table and column names.

=item --filter

type: string

Discard events for which this Perl code doesn't return true.

This option is a string of Perl code or a file containing Perl code that gets
compiled into a subroutine with one argument: $event.  This is a hashref.
If the given value is a readable file, then mk-query-digest reads the entire
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

If the filter code won't compile, mk-query-digest will die with an error.
If the filter code does compile, an error may still occur at runtime if the
code tries to do something wrong (like pattern match an undefined value).
mk-query-digest does not provide any safeguards so code carefully!

An example filter that discards everything but SELECT statements:

  --filter '$event->{arg} =~ m/^select/i'

This is compiled into a subroutine like the following:

  sub { $event = shift; ( $event->{arg} =~ m/^select/i ) && return $event; }

It is permissible for the code to have side effects (to alter C<$event>).

You can find an explanation of the structure of $event at
L<http://code.google.com/p/maatkit/wiki/EventAttributes>.

Here are more examples of filter code:

=over

=item Host/IP matches domain.com

--filter '($event->{host} || $event->{ip} || "") =~ m/domain.com/'

Sometimes MySQL logs the host where the IP is expected.  Therefore, we
check both.

=item User matches john

--filter '($event->{user} || "") =~ m/john/'

=item More than 1 warning

--filter '($event->{Warning_count} || 0) > 1'

=item Query does full table scan or full join

--filter '(($event->{Full_scan} || "") eq "Yes") || (($event->{Full_join} || "") eq "Yes")'

=item Query was not served from query cache

--filter '($event->{QC_Hit} || "") eq "No"'

=item Query is 1 MB or larger

--filter '$event->{bytes} >= 1_048_576'

=back

Since L<"--filter"> allows you to alter C<$event>, you can use it to do other
things, like create new attributes.


=item --help

Show help and exit.

=item --host

short form: -h; type: string

Connect to host.

=item --id-attribute

type: string

Identify each event using this attribute.  If not ID attribute is given, then
events are identified with the query's checksum: an MD5 hex checksum of the
query's fingerprint.

=item --log

type: string

Print all output to this file when daemonized.

=item --password

short form: -p; type: string

Password to use when connecting.

=item --pid

type: string

Create the given PID file when running.  The file contains the process
ID of the daemonized instance.  The PID file is removed when the
daemonized instance exits.  The program checks for the existence of the
PID file when starting; if it exists and the process with the matching PID
exists, the program exits.

=item --port

short form: -P; type: int

Port number to use for connection.

=item --progress

type: array; default: time,30

Print progress reports to STDERR.  The value is a comma-separated list with two
parts.  The first part can be percentage, time, or iterations; the second part
specifies how often an update should be printed, in percentage, seconds, or
number of iterations.

=item --query

type: string

Analyze only this given query.  If you want to analyze the table usage of
one simple query by providing on the command line instead of reading it
from a slow log file, then specify that query with this option.  The default
L<"--id-attribute"> will be used which is the query's checksum.

=item --read-timeout

type: time; default: 0

Wait this long for an event from the input; 0 to wait forever.

This option sets the maximum time to wait for an event from the input.  If an
event is not received after the specified time, the script stops reading the
input and prints its reports.

This option requires the Perl POSIX module.

=item --run-time

type: time

How long to run before exiting.  The default is to run forever (you can
interrupt with CTRL-C).

=item --set-vars

type: string; default: wait_timeout=10000

Set these MySQL variables.  Immediately after connecting to MySQL, this
string will be appended to SET and executed.

=item --socket

short form: -S; type: string

Socket file to use for connection.

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

Database that contains the query review table.

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

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-table-usage>.

Please use Google Code Issues and Groups to report bugs or request support:
L<http://code.google.com/p/maatkit/>.  You can also join #maatkit on Freenode to
discuss Maatkit.

Please include the complete command-line used to reproduce the problem you are
seeing, the version of all MySQL servers involved, the complete output of the
tool when run with L<"--version">, and if possible, debugging output produced by
running with the C<MKDEBUG=1> environment variable.

=head1 COPYRIGHT, LICENSE AND WARRANTY

This program is copyright 2009-2011 Percona Inc.
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

Daniel Nichter

=head1 VERSION

This manual page documents Ver 1.0.1 Distrib 7540 $Revision: 7531 $.

=cut

__END__
:endofperl
