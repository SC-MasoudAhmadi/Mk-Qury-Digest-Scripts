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

our $VERSION = '1.0.4';
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
# GeneralLogParser package 7522
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/GeneralLogParser.pm
#   trunk/common/t/GeneralLogParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package GeneralLogParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class ) = @_;
   my $self = {
      pending => [],
      db_for  => {},
   };
   return bless $self, $class;
}

my $genlog_line_1= qr{
   \A
   (?:(\d{6}\s+\d{1,2}:\d\d:\d\d))? # Timestamp
   \s+
   (?:\s*(\d+))                     # Thread ID
   \s
   (\w+)                            # Command
   \s+
   (.*)                             # Argument
   \Z
}xs;

sub parse_event {
   my ( $self, %args ) = @_;
   my @required_args = qw(next_event tell);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($next_event, $tell) = @args{@required_args};

   my $pending = $self->{pending};
   my $db_for  = $self->{db_for};
   my $line;
   my $pos_in_log = $tell->();
   LINE:
   while (
         defined($line = shift @$pending)
      or defined($line = $next_event->())
   ) {
      MKDEBUG && _d($line);
      my ($ts, $thread_id, $cmd, $arg) = $line =~ m/$genlog_line_1/;
      if ( !($thread_id && $cmd) ) {
         MKDEBUG && _d('Not start of general log event');
         next;
      }
      my @properties = ('pos_in_log', $pos_in_log, 'ts', $ts,
         'Thread_id', $thread_id);

      $pos_in_log = $tell->();

      @$pending = ();
      if ( $cmd eq 'Query' ) {
         my $done = 0;
         do {
            $line = $next_event->();
            if ( $line ) {
               my (undef, $next_thread_id, $next_cmd)
                  = $line =~ m/$genlog_line_1/;
               if ( $next_thread_id && $next_cmd ) {
                  MKDEBUG && _d('Event done');
                  $done = 1;
                  push @$pending, $line;
               }
               else {
                  MKDEBUG && _d('More arg:', $line);
                  $arg .= $line;
               }
            }
            else {
               MKDEBUG && _d('No more lines');
               $done = 1;
            }
         } until ( $done );

         chomp $arg;
         push @properties, 'cmd', 'Query', 'arg', $arg;
         push @properties, 'bytes', length($properties[-1]);
         push @properties, 'db', $db_for->{$thread_id} if $db_for->{$thread_id};
      }
      else {
         push @properties, 'cmd', 'Admin';

         if ( $cmd eq 'Connect' ) {
            if ( $arg =~ m/^Access denied/ ) {
               $cmd = $arg;
            }
            else {
               my ($user, undef, $db) = $arg =~ /(\S+)/g;
               my $host;
               ($user, $host) = split(/@/, $user);
               MKDEBUG && _d('Connect', $user, '@', $host, 'on', $db);

               push @properties, 'user', $user if $user;
               push @properties, 'host', $host if $host;
               push @properties, 'db',   $db   if $db;
               $db_for->{$thread_id} = $db;
            }
         }
         elsif ( $cmd eq 'Init' ) {
            $cmd = 'Init DB';
            $arg =~ s/^DB\s+//;
            my ($db) = $arg =~ /(\S+)/;
            MKDEBUG && _d('Init DB:', $db);
            push @properties, 'db',   $db   if $db;
            $db_for->{$thread_id} = $db;
         }

         push @properties, 'arg', "administrator command: $cmd";
         push @properties, 'bytes', length($properties[-1]);
      }

      push @properties, 'Query_time', 0;

      MKDEBUG && _d('Properties of event:', Dumper(\@properties));
      my $event = { @properties };
      if ( $args{stats} ) {
         $args{stats}->{events_read}++;
         $args{stats}->{events_parsed}++;
      }
      return $event;
   } # LINE

   @{$self->{pending}} = ();
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
# End GeneralLogParser package
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
# Advisor package 6830
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/Advisor.pm
#   trunk/common/t/Advisor.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package Advisor;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(match_type) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $self = {
      %args,
      rules          => [],  # Rules from all advisor modules.
      rule_index_for => {},  # Maps rules by ID to their array index in $rules.
      rule_info      => {},  # ID, severity, description, etc. for each rule.
   };

   return bless $self, $class;
}

sub load_rules {
   my ( $self, $advisor ) = @_;
   return unless $advisor;
   MKDEBUG && _d('Loading rules from', ref $advisor);

   my $i = scalar @{$self->{rules}};

   RULE:
   foreach my $rule ( $advisor->get_rules() ) {
      my $id = $rule->{id};
      if ( $self->{ignore_rules}->{"$id"} ) {
         MKDEBUG && _d("Ignoring rule", $id);
         next RULE;
      }
      die "Rule $id already exists and cannot be redefined"
         if defined $self->{rule_index_for}->{$id};
      push @{$self->{rules}}, $rule;
      $self->{rule_index_for}->{$id} = $i++;
   }

   return;
}

sub load_rule_info {
   my ( $self, $advisor ) = @_;
   return unless $advisor;
   MKDEBUG && _d('Loading rule info from', ref $advisor);
   my $rules = $self->{rules};
   foreach my $rule ( @$rules ) {
      my $id = $rule->{id};
      if ( $self->{ignore_rules}->{"$id"} ) {
         die "Rule $id was loaded but should be ignored";
      }
      my $rule_info = $advisor->get_rule_info($id);
      next unless $rule_info;
      die "Info for rule $id already exists and cannot be redefined"
         if $self->{rule_info}->{$id};
      $self->{rule_info}->{$id} = $rule_info;
   }
   return;
}


sub run_rules {
   my ( $self, %args ) = @_;
   my @matched_rules;
   my @matched_pos;
   my $rules      = $self->{rules};
   my $match_type = lc $self->{match_type};
   foreach my $rule ( @$rules ) {
      eval {
         my $match = $rule->{code}->(%args);
         if ( $match_type eq 'pos' ) {
            if ( defined $match ) {
               MKDEBUG && _d('Matches rule', $rule->{id}, 'near pos', $match);
               push @matched_rules, $rule->{id};
               push @matched_pos,   $match;
            }
         }
         elsif ( $match_type eq 'bool' ) {
            if ( $match ) {
               MKDEBUG && _d("Matches rule", $rule->{id});
               push @matched_rules, $rule->{id};
            }
         }
      };
      if ( $EVAL_ERROR ) {
         warn "Code for rule $rule->{id} caused an error: $EVAL_ERROR";
      }
   }
   return \@matched_rules, \@matched_pos;
};


sub get_rule_info {
   my ( $self, $id ) = @_;
   return unless $id;
   return $self->{rule_info}->{$id};
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
# End Advisor package
# ###########################################################################

# ###########################################################################
# AdvisorRules package 6813
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/AdvisorRules.pm
#   trunk/common/t/AdvisorRules.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package AdvisorRules;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(PodParser) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $self = {
      %args,
      rules     => [],
      rule_info => {},
   };
   return bless $self, $class;
}

sub load_rule_info {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(file section ) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $rules = $args{rules} || $self->{rules};
   my $p     = $self->{PodParser};

   $p->parse_from_file($args{file});
   my $rule_items = $p->get_items($args{section});
   my %seen;
   foreach my $rule_id ( keys %$rule_items ) {
      my $rule = $rule_items->{$rule_id};
      die "Rule $rule_id has no description" unless $rule->{desc};
      die "Rule $rule_id has no severity"    unless $rule->{severity};
      die "Rule $rule_id is already defined"
         if exists $self->{rule_info}->{$rule_id};
      $self->{rule_info}->{$rule_id} = {
         id          => $rule_id,
         severity    => $rule->{severity},
         description => $rule->{desc},
      };
   }

   foreach my $rule ( @$rules ) {
      die "There is no info for rule $rule->{id} in $args{file}"
         unless $self->{rule_info}->{ $rule->{id} };
   }

   return;
}

sub get_rule_info {
   my ( $self, $id ) = @_;
   return unless $id;
   return $self->{rule_info}->{$id};
}

sub _reset_rule_info {
   my ( $self ) = @_;
   $self->{rule_info} = {};
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
# End AdvisorRules package
# ###########################################################################

# ###########################################################################
# QueryAdvisorRules package 7473
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/QueryAdvisorRules.pm
#   trunk/common/t/QueryAdvisorRules.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package QueryAdvisorRules;
use base 'AdvisorRules';

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub new {
   my ( $class, %args ) = @_;
   my $self = $class->SUPER::new(%args);
   @{$self->{rules}} = $self->get_rules();
   MKDEBUG && _d(scalar @{$self->{rules}}, "rules");
   return $self;
}

sub get_rules {
   return
   {
      id   => 'ALI.001',      # Implicit alias
      code => sub {
         my ( %args ) = @_;
         my $event  = $args{event};
         my $struct = $event->{query_struct};
         my $tbls   = $struct->{from} || $struct->{into} || $struct->{tables};
         return unless $tbls;
         foreach my $tbl ( @$tbls ) {
            return 0 if $tbl->{alias} && !$tbl->{explicit_alias};
         }
         my $cols = $struct->{columns};
         return unless $cols;
         foreach my $col ( @$cols ) {
            return 0 if $col->{alias} && !$col->{explicit_alias};
         }
         return;
      },
   },
   {
      id   => 'ALI.002',      # tbl.* alias
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         my $cols  = $event->{query_struct}->{columns};
         return unless $cols;
         foreach my $col ( @$cols ) {
            return 0 if $col->{tbl} && $col->{col} eq '*' &&  $col->{alias};
         }
         return;
      },
   },
   {
      id   => 'ALI.003',      # tbl AS tbl
      code => sub {
         my ( %args ) = @_;
         my $event  = $args{event};
         my $struct = $event->{query_struct};
         my $tbls   = $struct->{from} || $struct->{into} || $struct->{tables};
         return unless $tbls;
         foreach my $tbl ( @$tbls ) {
            return 0 if $tbl->{alias} && $tbl->{alias} eq $tbl->{tbl};
         }
         my $cols = $struct->{columns};
         return unless $cols;
         foreach my $col ( @$cols ) {
            return 0 if $col->{alias} && $col->{alias} eq $col->{col};
         }
         return;
      },
   },
   {
      id   => 'ARG.001',      # col = '%foo'
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         my $where = $event->{query_struct}->{where};
         return unless $where && @$where;
         foreach my $arg ( @$where ) {
            return 0
               if ($arg->{operator} || '') eq 'like'
                  && $arg->{right_arg} =~ m/[\'\"][\%\_]./;
         }
         return;
      },
   },
   {
      id   => 'ARG.002',      # LIKE w/o wildcard
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};        
         my $where = $event->{query_struct}->{where};
         return unless $where && @$where;
         foreach my $arg ( @$where ) {
            return 0
               if ($arg->{operator} || '') eq 'like'
                  && $arg->{right_arg} !~ m/[%_]/;
         }
         return;
      },
   },
   {
      id   => 'CLA.001',      # SELECT w/o WHERE
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         return unless ($event->{query_struct}->{type} || '') eq 'select';
         return unless $event->{query_struct}->{from};
         return 0 unless $event->{query_struct}->{where};
         return;
      },
   },
   {
      id   => 'CLA.002',      # ORDER BY RAND()
      code => sub {
         my ( %args ) = @_;
         my $event   = $args{event};
         my $orderby = $event->{query_struct}->{order_by};
         return unless $orderby;
         foreach my $ident ( @$orderby ) {
            return 0 if $ident->{function} && $ident->{function} eq 'RAND';
         }
         return;
      },
   },
   {
      id   => 'CLA.003',      # LIMIT w/ OFFSET
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         return unless $event->{query_struct}->{limit};
         return unless defined $event->{query_struct}->{limit}->{offset};
         return 0;
      },
   },
   {
      id   => 'CLA.004',      # GROUP BY <number>
      code => sub {
         my ( %args ) = @_;
         my $event   = $args{event};
         my $groupby = $event->{query_struct}->{group_by};
         return unless $groupby;
         foreach my $ident ( @$groupby ) {
            return 0 if exists $ident->{position};
         }
         return;
      },
   },
   {
      id   => 'CLA.005',      # ORDER BY col where col=<constant>
      code => sub {
         my ( %args ) = @_;
         my $event   = $args{event};
         my $orderby = $event->{query_struct}->{order_by};
         return unless $orderby;
         my $where   = $event->{query_struct}->{where};
         return unless $where;
         my %orderby_col = map { lc $_->{column} => 1 }
                           grep { $_->{column} }
                           @$orderby;
         foreach my $pred ( @$where ) {
            my $val = $pred->{right_arg};
            next unless $val;
            return 0 if $val =~ m/^\d+$/ && $orderby_col{lc $pred->{left_arg}};
         }
         return;
      },
   },
   {
      id   => 'CLA.006',      # GROUP BY or ORDER BY different tables
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         my $groupby = $event->{query_struct}->{group_by};
         my $orderby = $event->{query_struct}->{order_by};
         return unless $groupby || $orderby;

         my %groupby_tbls = map { $_->{table} => 1 }
                            grep { $_->{table} }
                            @$groupby;
         return 0 if scalar keys %groupby_tbls > 1;
         
         my %orderby_tbls = map { $_->{table} => 1 }
                            grep { $_->{table} }
                            @$orderby;
         return 0 if scalar keys %orderby_tbls > 1;

         map { delete $groupby_tbls{$_} } keys %orderby_tbls;
         return 0 if scalar keys %groupby_tbls;

         return;
      },
   },
   {
      id   => 'CLA.007',      # ORDER BY ASC/DESC mix can't use index
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         my $order_by = $event->{query_struct}->{order_by}; 
         return unless $order_by;
         my ($asc, $desc) = (0, 0);
         foreach my $col ( @$order_by ) {
            if ( ($col->{sort} || 'ASC') eq 'ASC' ) {
               $asc++;
            }
            else {
               $desc++;
            }
            return 0 if $asc && $desc;
         }
         return;
      },
   },
   {
      id   => 'COL.001',      # SELECT *
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         return unless ($event->{query_struct}->{type} || '') eq 'select';
         my $cols = $event->{query_struct}->{columns};
         return unless $cols;
         foreach my $col ( @$cols ) {
            return 0 if $col->{col} eq '*';
         }
         return;
      },
   },
   {
      id   => 'COL.002',      # INSERT w/o (cols) def
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         my $type  = $event->{query_struct}->{type} || '';
         return unless $type eq 'insert' || $type eq 'replace';
         return 0 unless $event->{query_struct}->{columns};
         return;
      },
   },
   {
      id   => 'LIT.001',      # IP as string
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         if ( $event->{arg} =~ m/['"]\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/gc ) {
            return (pos $event->{arg}) || 0;
         }
         return;
      },
   },
   {
      id   => 'LIT.002',      # Date not quoted
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         if ( $event->{arg} =~ m/(?<!['"\w-])\d{4}-\d{1,2}-\d{1,2}\b/gc ) {
            return (pos $event->{arg}) || 0;
         }
         if ( $event->{arg} =~ m/(?<!['"\w\d-])\d{2}-\d{1,2}-\d{1,2}\b/gc ) {
            return (pos $event->{arg}) || 0;
         }
         return;
      },
   },
   {
      id   => 'KWR.001',      # SQL_CALC_FOUND_ROWS
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         return 0 if $event->{query_struct}->{keywords}->{sql_calc_found_rows};
         return;
      },
   },
   {
      id   => 'JOI.001',      # comma and ansi joins
      code => sub {
         my ( %args ) = @_;
         my $event  = $args{event};
         my $struct = $event->{query_struct};
         my $tbls   = $struct->{from} || $struct->{into} || $struct->{tables};
         return unless $tbls;
         my $comma_join = 0;
         my $ansi_join  = 0;
         foreach my $tbl ( @$tbls ) {
            if ( $tbl->{join} ) {
               if ( $tbl->{join}->{ansi} ) {
                  $ansi_join = 1;
               }
               else {
                  $comma_join = 1;
               }
            }
            return 0 if $comma_join && $ansi_join;
         }
         return;
      },
   },
   {
      id   => 'RES.001',      # non-deterministic GROUP BY
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         return unless ($event->{query_struct}->{type} || '') eq 'select';
         my $groupby = $event->{query_struct}->{group_by};
         return unless $groupby;
         my %groupby_col = map { $_->{column} => 1 }
                           grep { $_->{column} }
                           @$groupby;
         return unless scalar %groupby_col;
         my $cols = $event->{query_struct}->{columns};
         foreach my $col ( @$cols ) {
            return 0 unless $groupby_col{ $col->{col} };
         }
         return;
      },
   },
   {
      id   => 'RES.002',      # non-deterministic LIMIT w/o ORDER BY
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         return unless $event->{query_struct}->{limit};
         return unless    $event->{query_struct}->{from}
                         || $event->{query_struct}->{into}
                         || $event->{query_struct}->{tables};
         return 0 unless $event->{query_struct}->{order_by};
         return;
      },
   },
   {
      id   => 'STA.001',      # != instead of <>
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         return 0 if $event->{arg} =~ m/!=/;
         return;
      },
   },
   {
      id   => 'SUB.001',      # IN(<subquery>)
      code => sub {
         my ( %args ) = @_;
         my $event = $args{event};
         if ( $event->{arg} =~ m/\bIN\s*\(\s*SELECT\b/gi ) {
            return pos $event->{arg};
         }
         return;
      },
   },
   {
      id   => 'JOI.002',      # table joined more than once, but not self-join
      code => sub {
         my ( %args ) = @_;
         my $event  = $args{event};
         my $struct = $event->{query_struct};
         return unless $struct;
         my $tbls   = $struct->{from} || $struct->{into} || $struct->{tables};
         return unless $tbls;
         my %tbl_cnt;
         my $n_tbls = scalar @$tbls;

         for my $i ( 0..($n_tbls-1) ) {
            my $tbl      = $tbls->[$i];
            my $tbl_name = lc $tbl->{tbl};

            $tbl_cnt{$tbl_name}->{cnt}++;
            $tbl_cnt{$tbl_name}->{ansi_join}++
               if $tbl->{join} && $tbl->{join}->{ansi};
            $tbl_cnt{$tbl_name}->{comma_join}++
               if $tbl->{join} && !$tbl->{join}->{ansi};

            if ( $tbl_cnt{$tbl_name}->{cnt} > 1 ) {
               return 0
                  if    $tbl_cnt{$tbl_name}->{ansi_join}
                     && $tbl_cnt{$tbl_name}->{comma_join};
            }
         }
         return;
      },
   },
   {
      id   => 'JOI.003',  # OUTER JOIN converted to INNER JOIN
      code => sub {
         my ( %args ) = @_;
         my $event  = $args{event};
         my $struct = $event->{query_struct};
         return unless $struct;
         my $tbls   = $struct->{from} || $struct->{into} || $struct->{tables};
         return unless $tbls;
         my $where  = $struct->{where};
         return unless $where;

         my %outer_tbls = map { $_->{tbl} => 1 } get_outer_tables($tbls);
         MKDEBUG && _d("Outer tables:", keys %outer_tbls);
         return unless %outer_tbls;

         foreach my $pred ( @$where ) {
            next unless $pred->{left_arg};  # skip constants like 1 in "WHERE 1"
            my ($tbl, $col) = split /\./, $pred->{left_arg};
            if ( $tbl && $col && $outer_tbls{$tbl} ) {
               if ($pred->{operator} ne 'is' || $pred->{right_arg} !~ m/null/i)
               {
                  MKDEBUG && _d("Predicate prevents OUTER JOIN:",
                     map { $pred->{$_} } qw(left_arg operator right_arg));
                  return 0;
               }
            }
         }

         return;
      }
   },
   {
      id   => 'JOI.004',  # broken exclusion join
      code => sub {
         my ( %args ) = @_;
         my $event  = $args{event};
         my $struct = $event->{query_struct};
         return unless $struct;
         my $tbls   = $struct->{from} || $struct->{into} || $struct->{tables};
         return unless $tbls;
         my $where  = $struct->{where};
         return unless $where;

         my %outer_tbls;
         my %outer_tbl_join_cols;
         my @unknown_join_cols;
         foreach my $outer_tbl ( get_outer_tables($tbls) ) {
            $outer_tbls{$outer_tbl->{tbl}} = 1;

            my $join = $outer_tbl->{join};
            if ( !$join ) {
               my ($inner_tbl) = grep { 
                  exists $_->{join} 
                  && $_->{join}->{to} eq $outer_tbl->{tbl}
               } @$tbls;
               $join = $inner_tbl->{join}; 
               die "Cannot find join structure for $outer_tbl->{tbl}"
                  unless $join;
            }

            if ( $join->{condition} eq 'using' ) {
               %outer_tbl_join_cols = map { $_ => 1 } @{$join->{columns}};
            }
            else {
               my $where = $join->{where};
               die "Join structure for ON condition has no where structure"
                  unless $where;
               my @join_cols;
               foreach my $pred ( @$where ) {
                  next unless $pred->{operator} eq '=';
                  push @join_cols, $pred->{left_arg}, $pred->{right_arg};
               }
               MKDEBUG && _d("Join columns:", @join_cols);
               foreach my $join_col ( @join_cols ) {
                  my ($tbl, $col) = split /\./, $join_col;
                  if ( !$col ) {
                     $col = $tbl;
                     $tbl = determine_table_for_column(
                        column      => $col,
                        tbl_structs => $event->{tbl_structs},
                     );
                  }
                  if ( !$tbl ) {
                     MKDEBUG && _d("Cannot determine the table for join column",
                        $col);
                     push @unknown_join_cols, $col;
                  }
                  else {
                     $outer_tbl_join_cols{$col} = 1
                        if $tbl eq $outer_tbl->{tbl};
                  }
               }
            }
         }
         MKDEBUG && _d("Outer table join columns:", keys %outer_tbl_join_cols);
         MKDEBUG && _d("Unknown join columns:", @unknown_join_cols);

         foreach my $pred ( @$where ) {
            next unless $pred->{left_arg}; # skip constants like 1 in "WHERE 1"
            next unless $pred->{operator} eq 'is'
               && $pred->{right_arg} =~ m/NULL/i;

            my ($tbl, $col) = split /\./, $pred->{left_arg};
            if ( !$col ) {
               $col = $tbl;
               $tbl = determine_table_for_column(
                  column      => $col,
                  tbl_structs => $event->{tbl_structs},
               );
            }
            next unless $tbl;               # can't check tbl if tbl is unknown
            next unless $outer_tbls{$tbl};  # only want outer tbl cols

            next if $outer_tbl_join_cols{$col};

            return 0 unless grep { $col eq $_ } @unknown_join_cols;
         }

         return;  # rule does not match, as best as we can determine
      }
   },
};


sub get_outer_tables {
   my ( $tbls ) = @_;
   return unless $tbls;
   my @outer_tbls;
   my $n_tbls = scalar @$tbls;
   for my $i( 0..($n_tbls-1) ) {
      my $tbl = $tbls->[$i];
      next unless $tbl->{join} && $tbl->{join}->{type} =~ m/left|right/i;
      push @outer_tbls,
         $tbl->{join}->{type} =~ m/left/i ? $tbl
                                          : $tbls->[$i - 1];
   }
   return @outer_tbls;
}


sub determine_table_for_column {
   my ( %args ) = @_;
   my @required_args = qw(column);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($col) = @args{@required_args};

   my $tbl_structs = $args{tbl_structs};
   return unless $tbl_structs;

   foreach my $db ( keys %$tbl_structs ) {
      foreach my $tbl ( keys %{$tbl_structs->{$db}} ) {
         if ( $tbl_structs->{$db}->{$tbl}->{is_col}->{$col} ) {
            MKDEBUG && _d($col, "column belongs to", $db, $tbl);
            return $tbl;
         }
      }
   }

   MKDEBUG && _d("Cannot determine table for column", $col);
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
# End QueryAdvisorRules package
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
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_query_advisor;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

Transformers->import(qw(make_checksum));

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

# Some rules report their match pos.  This sets how many
# characters before and after that pos are shown to give
# the user some context.
use constant POS_CONTEXT => 12;

use sigtrap 'handler', \&sig_int, 'normal-signals';

my $oktorun = 1;  # global for sig handler

sub main {
   @ARGV = @_;  # set global ARGV for this package

   my %seen_id;           # already printed rule info (advice)
   my %seen_fingerprint;  # already seen queries
   my %advice_queue;      # queued up advice for --group-by
   my %severity_count;    # note/warn/crit count for each query id

   # ########################################################################
   # Get configuration information.
   # ########################################################################
   my $o = new OptionParser();
   $o->get_specs();
   $o->get_opts();

   my $dp = $o->DSNParser();
   $dp->prop('set-vars', $o->get('set-vars'));

   my $review_dsn = $o->get('review');
   my $groupby    = lc $o->get('group-by');

   if ( !$o->get('help') ) {
      if ( $review_dsn
           && (!defined $review_dsn->{D} || !defined $review_dsn->{t}) ) {
         $o->save_error('The --review DSN requires a D (database) and t'
            . ' (table) part specifying the query review table');
      }
      if ( $groupby !~ m/rule_id|query_id|none/ ) {
         $o->save_error("Invalid --group-by value.  Valid values are: "
            . "rule_id, query_id, none");
      }
   }

   $o->usage_or_errors();

   # #########################################################################
   # Load rules from POD and plugins.
   # #########################################################################
   my $p   = new PodParser();
   my $qar = new QueryAdvisorRules(PodParser => $p);
   my $adv = new Advisor(
      match_type   => "pos",
      ignore_rules => $o->get('ignore-rules'),
   );

   $qar->load_rule_info(
      file    => __FILE__,
      section => 'RULES',
   );
   $adv->load_rules($qar);
   $adv->load_rule_info($qar);

   # TODO: load rules from plugins

   # #########################################################################
   # Make common modules.
   # #########################################################################
   my $q  = new Quoter();
   my $qp = new QueryParser();
   my $qr = new QueryRewriter( QueryParser => $qp );
   my $sp = new SQLParser();
   my $tp = new TableParser(Quoter => $q);
   my $du = new MySQLDump();
   my %common_modules = (
      DSNParser     => $dp,
      Quoter        => $q,
      OptionParser  => $o,
      QueryParser   => $qp,
      QueryRewriter => $qr,
      SQLParser     => $sp,
      TableParser   => $tp,
      MySQLDump     => $du,
   );

   # #########################################################################
   # Connect to review table if necessary.
   # #########################################################################
   my $review_dbh;
   if ( $review_dsn ) {
      $review_dbh = get_cxn(
         dsn  => $review_dsn,
         opts => { AutoCommit => 1 },
         %common_modules,
      );
   }

   # #########################################################################
   # Try to connect to MySQL.
   # #########################################################################
   my $dbh;
   eval {
      $dbh = get_cxn(
         dsn => $dp->parse_options($o),
         %common_modules
      );
   };
   # TODO: for now we don't report if connection to MySQL cannot be made
   # because most rules don't need a connection.  Not connecting means rules
   # like JOI.004 may not be able to work in some cases.  Maybe we can add
   # a rule attrib like "uses cxn: yes" to determine if need a cxn?
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d("Cannot connect to MySQL:", $EVAL_ERROR);
   }

   # #########################################################################
   # Make pipeline.
   # #########################################################################
   my @pipeline;

   if ( my $query = $o->get('query') ) {
      push @pipeline, sub {
         my ( %args ) = @_;
         MKDEBUG && _d('callback: query:', $query);
         $args{oktorun}->(0) if $args{oktorun};
         return {
            cmd        => 'Query',
            arg        => $query,
            pos_in_log => 0,  # for compatibility
         };
      };
   }
   elsif ( $review_dbh ) {
      my $where = $o->get('where');
      my $sql   = "SELECT sample FROM "
                . $q->quote($review_dsn->{D}, $review_dsn->{t})
                . ($where ? " WHERE $where" : "");
      MKDEBUG && _d($review_dbh, $sql);
      my $queries = $review_dbh->selectall_arrayref($sql);

      push @pipeline, sub {
         my ( %args ) = @_;
         MKDEBUG && _d('callback: review');
         my $query = shift @$queries;
         if ( !$query ) {
            $args{oktorun}->(0) if $args{oktorun};
            return;
         }
         return {
            cmd        => 'Query',
            arg        => $query->[0],
            pos_in_log => 0,
         };
      };
   }
   else {
      my %alias_for = (
         slowlog   => ['SlowLogParser'],
         genlog    => ['GeneralLogParser'],
      );
      my $type = $o->get('type');
      $type    = $alias_for{$type->[0]} if $alias_for{$type->[0]};

      foreach my $module ( @$type ) {
         my $parser;
         eval {
            $parser = $module->new(o => $o);
         };
         if ( $EVAL_ERROR ) {
            die "Failed to load $module module: $EVAL_ERROR";
         }
         push @pipeline, sub {
            my ( %args ) = @_;
            return $parser->parse_event(%args);
         };
         MKDEBUG && _d('Added', $module, 'module to callbacks');
      }
   }

   # This proc is important because all procs below, and some of the
   # rules, expect the event to have an arg.
   push @pipeline, sub {
      my ( %args ) = @_;
      MKDEBUG && _d('callback: check cmd and arg');
      my $event = $args{event};
      if ( ($event->{cmd} || '') ne 'Query' ) {
         MKDEBUG && _d('Skipping non-Query cmd');
         return;
      }
      if ( !$event->{arg} ) {
         MKDEBUG && _d('Skipping empty arg');
         return;
      }
      return $event;
   };

   # Fingerprint query and check how many times we've seen it for --sample.
   my %seen;
   my $num_samples = $o->get('sample');
   push @pipeline, sub {
      my ( %args ) = @_;
      MKDEBUG && _d('callback: fingerprint/sample');
      my $event = $args{event};
      $event->{fingerprint} = $qr->fingerprint($event->{arg});
      if ( ++$seen_fingerprint{ $event->{fingerprint} } > $num_samples ) {
         MKDEBUG && _d("Event skipped because of --sample");
         return;
      }
      $event->{query_id} = make_checksum($event->{fingerprint});
      return $event;
   };

   # Parse the query.  The query struct is a hashref with keys
   # to various parts of the query.  If this fails we still
   # continue because some rules may not need the query struct.
   push @pipeline, sub {
      my ( %args ) = @_;
      MKDEBUG && _d('callback: parse query');
      my $event        = $args{event};
      my $query_struct;
      eval {
         $query_struct = $sp->parse($event->{arg});
         if ( !$query_struct ) {
            MKDEBUG && _d('Failed to parse query struct, no error');
         }
         $event->{query_struct} = $query_struct;
      };
      if ( $EVAL_ERROR ) {
         MKDEBUG && _d('Failed to parse query struct:', $EVAL_ERROR);
      } 
      return $event;
   };

   # Get info from MySQL related to the query, like tbl structs for
   # tables it uses.
   if ( $dbh ) {
      my $default_db  = $o->get('database');
      
      if ( $o->get('show-create-table') ) {
         my $tbl_structs = {};
         push @pipeline, sub {
            my ( %args ) = @_;
            MKDEBUG && _d('callback: show create table');
            my $event        = $args{event};
            my $query_struct = $event->{query_struct};
            if ( !$query_struct ) {
               MKDEBUG && _d("No query struct");
               return $event;
            }
            my $tbls = $query_struct->{from}
               || $query_struct->{into}
               || $query_struct->{tables};
            if ( !$tbls || !@$tbls ) {
               MKDEBUG && _d("Query has no tables");
               return $event;
            }

            foreach my $tbl_info ( @$tbls ) {
               my $tbl = $tbl_info->{tbl};
               my $db  = $tbl_info->{db} || $event->{db} || $default_db;
               if ( !$db ) {
                  MKDEBUG && _d("No database for table", $tbl);
                  next;
               }

               if ( !$tbl_structs->{$db}->{$tbl} ) {
                  my $tbl_struct;
                  eval {
                     $tbl_struct
                        = $tp->parse($du->get_create_table($dbh, $q, $db, $tbl));
                  };
                  if ( $EVAL_ERROR ) {
                     warn "Failed to get SHOW CREATE TABLE for $db.$tbl: "
                        . $EVAL_ERROR;
                     next;
                  }
                  $tbl_structs->{$db}->{$tbl} = $tbl_struct;
               }
            }

            $event->{tbl_structs} = $tbl_structs;
            return $event;
         };
      }
   }

   # Run rules on query, get a list of rules that match (advice).
   push @pipeline, sub {
      my ( %args ) = @_;
      MKDEBUG && _d('callback: check query');
      my $event  = $args{event};
      MKDEBUG && _d('Checking', $event->{arg});
      my ($advice, $near_pos) = $adv->run_rules(event => $event);
      $event->{advice}   = $advice;
      $event->{near_pos} = $near_pos;
      return $event;
   };

   # Print info (advice) about each rule that matched this query.
   if ( $groupby eq 'none' ) {
      push @pipeline, sub {
         my ( %args ) = @_;
         MKDEBUG && _d('callback: print advice');
         my $event  = $args{event};
         my $advice = $event->{advice};
         return $event unless @$advice || $o->get('print-all');
         $severity_count{$event->{query_id}}->{item} ||= $event->{fingerprint};
         print_advice(
            %args,
            seen_id        => \%seen_id,
            severity_count => \%severity_count,
            verbose        => $o->get('verbose'),
            report_format  => $o->get('report-format'),
            Advisor        => $adv,
         );
         return $event;
      };
   }
   else {   
      push @pipeline, sub {
         my ( %args ) = @_;
         MKDEBUG && _d('callback: queue advice for group-by', $groupby);
         my $event  = $args{event};
         my $advice = $event->{advice};
         return $event unless @$advice || $o->get('print-all');
         $severity_count{$event->{query_id}}->{item} ||= $event->{fingerprint};
         queue_advice(
            %args,
            advice_queue   => \%advice_queue,
            severity_count => \%severity_count,
            group_by       => $groupby,
            Advisor        => $adv,
         );
         return $event;
      };
   }

   # ##########################################################################
   # Get ready to do the main work.
   # ##########################################################################
   my $fh;
   my $event       = {};
   my $more_events = 1;
   my $oktorun_sub = sub { $more_events = $_[0]; };
   my $next_event;
   my $tell;

   if ( @ARGV == 0 ) {
      push @ARGV, '-'; # Magical STDIN filename.
   }

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

   # #########################################################################
   # Do it!
   # #########################################################################
   EVENT:
   while ( $oktorun ) {
      if ( !$fh ) {
         my $file = shift @ARGV;
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
         $next_event  = sub { return <$fh>; };
         $tell        = sub { return tell $fh; };
      }

      $event       = {};
      $more_events = 1;
      eval {
         foreach my $proc ( @pipeline ) {
            last unless $oktorun;  # the global oktorun var
            $event = $proc->(
               event      => $event,
               fh         => $fh,
               next_event => $next_event,
               tell       => $tell,
               oktorun    => $oktorun_sub,
            );
            last unless $event;
         }
      };
      if ( $EVAL_ERROR ) {
         _d($EVAL_ERROR);
         last EVENT unless $o->get('continue-on-error');
      }
      if ( !$more_events ) {
         MKDEBUG && _d('No more events');
         close $fh if $fh and $fh ne *STDIN;
         $fh = undef;
      }
   }  # EVENT

   $dbh->disconnect() if $dbh;
   $review_dbh->disconnect() if $review_dbh;

   # ########################################################################
   # Aggregate and report items for group-by reports
   # ########################################################################
   if ( $groupby ne 'none' ) {
      print_grouped_report(
         advice_queue  => \%advice_queue,
         group_by      => $groupby,
         verbose       => $o->get('verbose'),
         report_format => $o->get('report-format'),
      )
   }

   # ########################################################################
   # Create and print profile of each items note/warn/crit count.
   # ########################################################################
   if ( keys %severity_count ) {
      eval {
         my $profile = new ReportFormatter(
            long_last_column => 1,
            extend_right     => 1,
         );
         $profile->set_title("Profile");
         $profile->set_columns(
            { name => 'Query ID',                     },
            { name => 'NOTE',     right_justify => 1, },
            { name => 'WARN',     right_justify => 1, },
            { name => 'CRIT',     right_justify => 1, },
            { name => 'Item',                         },
         );
         foreach my $query_id ( sort keys %severity_count ) {
            $profile->add_line(
               "0x$query_id",
               $severity_count{$query_id}->{note} || 0,
               $severity_count{$query_id}->{warn} || 0,
               $severity_count{$query_id}->{crit} || 0,
               $severity_count{$query_id}->{item} || "",
            );
         }
         print "\n", $profile->get_report();
      };
      if ( $EVAL_ERROR ) {
         # shouldn't happen but just in case ReportFormatter borks
         warn "Error printing profile: $EVAL_ERROR";
      };
   }

   return 0;
}

# ##########################################################################
# Subroutines
# ##########################################################################

sub print_advice {
   my ( %args ) = @_;
   my $event          = $args{event};
   my $verbose        = $args{verbose} || 0;
   my $format         = $args{report_format};
   my $adv            = $args{Advisor};
   my $seen_id        = $args{seen_id};
   my $severity_count = $args{severity_count};

   my $advice   = $event->{advice};
   my $near_pos = $event->{near_pos};
   my $n_advice = scalar @$advice;
   my @seen_ids;

   # Header
   my $query_id = $event->{query_id} || "";
   print "\n# Query ID 0x$query_id at byte " . ($event->{pos_in_log} || 0) . "\n";

   # New check IDs and their descriptions
   foreach my $i ( 1..$n_advice ) {
      my $rule_id = $advice->[$i - 1];
      my $pos     = $near_pos->[$i - 1];
      my $info    = $adv->get_rule_info($rule_id);
      my $desc    = $info->{description} || '';  # shouldn't be blank
      if ( $format eq 'compact' && $seen_id->{$rule_id}++ ) {
         push @seen_ids, $rule_id;
      }
      else {
         # Haven't seen the description for this check ID yet so print it.
         my @desc = map {
               $_ .= '.' unless m/\.$/;
               $_;
            } split(/\.\s{1,2}/, $desc);
         my $desc = $verbose == 1 ? $desc[0]             # terse
                  : $verbose == 2 ? "$desc[0] $desc[1]"  # fuller
                  : $verbose >  2 ? $desc                # complete
                  :                 '';                  # none
         print "# ", uc $info->{severity}, " $rule_id $desc\n";

         if ( $pos ) {
            my $offset = $pos > POS_CONTEXT ? $pos - POS_CONTEXT : 0;
            print "#   matches near: ",
               substr($event->{arg}, $offset, ($pos - $offset) + POS_CONTEXT),
               "\n";
         }
      }

      $severity_count->{$query_id}->{$info->{severity}}++;
   }

   # Already seen check IDs
   print "# Also: @seen_ids\n" if scalar @seen_ids;

   # The query
   print "$event->{arg}\n";

   return;
}

sub queue_advice {
   my ( %args ) = @_;
   my @required_args = qw(advice_queue severity_count group_by event Advisor);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($advice_queue, $severity_count, $groupby, $event, $adv)
      = @args{@required_args};

   my $advice = $event->{advice};
   return unless scalar @$advice;

   my $query_id = $event->{query_id};
   if ( !$query_id ) {
      warn "Event does not have a query ID";  # shouldn't happen
      return;
   }

   foreach my $rule_id ( @$advice ) {
      my $info = $adv->get_rule_info($rule_id);
      if ( $groupby eq 'query_id' ) {
         $advice_queue->{$query_id}->{$rule_id}++;
      }
      elsif ( $groupby eq 'rule_id' ) {
         $advice_queue->{$rule_id}->{$query_id}++;
      }
      else {
         die "I don't know how to group items by $groupby";
      }
      $severity_count->{$query_id}->{$info->{severity}}++;
   } 

   return;
}

sub print_grouped_report {
   my ( %args ) = @_;
   my @required_args = qw(advice_queue group_by);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($advice_queue, $groupby) = @args{@required_args};
   my $verbose = $args{verbose} || 0;
   my %seen;


   foreach my $groupby_attrib ( sort keys %$advice_queue ) {
      print "\n" . ($groupby eq 'query_id' ? "0x" : "") . $groupby_attrib;
      foreach my $groupby_value (sort keys %{$advice_queue->{$groupby_attrib}}){
         print " " . ($groupby ne 'query_id' ? '0x' : '') . $groupby_value;
      }
      print "\n";
   }

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
      $dsn->{p} = OptionParser::prompt_noecho("Enter password: ");
   }

   my $dbh = $dp->get_dbh($dp->get_cxn_params($dsn), $args{opts});
   $dbh->{FetchHashKeyName} = 'NAME_lc';
   MKDEBUG && _d('Connected dbh', $dbh);
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

# ############################################################################
# Documentation
# ############################################################################

=pod

=head1 NAME

mk-query-advisor - Analyze queries and advise on possible problems.

=head1 SYNOPSIS

Usage: mk-query-advisor [OPTION...] [FILE]

mk-query-advisor analyzes queries and advises on possible problems.
Queries are given either by specifying slowlog files, --query, or --review.

   # Analyzer all queries in the given slowlog
   mk-query-advisor /path/to/slow-query.log

   # Get queries from tcpdump using mk-query-digest
   mk-query-digest --type tcpdump.txt --print --no-report | mk-query-advisor

   # Get queries from a general log
   mk-query-advisor --type genlog mysql.log

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

mk-query-advisor simply reads queries and examines them, and is thus
very low risk.

At the time of this release there is a bug that may cause an infinite (or
very long) loop when parsing very large queries.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-query-advisor>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

mk-query-advisor examines queries and applies rules to them, trying to
find queries that look bad according to the rules.  It reports on
queries that match the rules, so you can find bad practices or hidden
problems in your SQL.  By default, it accepts a MySQL slow query log
as input.

=head1 RULES

These are the rules that mk-query-advisor will apply to the queries it
examines.  Each rule has three bits of information: an ID, a severity
and a description.

The rule's ID is its identifier.  We use a seven-character ID, and the
naming convention is three characters, a period, and a three-digit
number.  The first three characters are sort of an abbreviation of the
general class of the rule.  For example, ALI.001 is some rule related
to how the query uses aliases.

The rule's severity is an indication of how important it is that this
rule matched a query.  We use NOTE, WARN, and CRIT to denote these
levels.

The rule's description is a textual, human-readable explanation of
what it means when a query matches this rule.  Depending on the
verbosity of the report you generate, you will see more of the text in
the description.  By default, you'll see only the first sentence,
which is sort of a terse synopsis of the rule's meaning.  At a higher
verbosity, you'll see subsequent sentences.

=over

=item ALI.001

severity: note

Aliasing without the AS keyword.  Explicitly using the AS keyword in
column or table aliases, such as "tbl AS alias," is more readable
than implicit aliases such as "tbl alias".

=item ALI.002

severity: warn

Aliasing the '*' wildcard.  Aliasing a column wildcard, such as
"SELECT tbl.* col1, col2" probably indicates a bug in your SQL.
You probably meant for the query to retrieve col1, but instead it
renames the last column in the *-wildcarded list.

=item ALI.003

severity: note

Aliasing without renaming.  The table or column's alias is the same as
its real name, and the alias just makes the query harder to read.

=item ARG.001

severity: warn

Argument with leading wildcard.  An argument has a leading
wildcard character, such as "%foo".  The predicate with this argument
is not sargable and cannot use an index if one exists.

=item ARG.002

severity: note

LIKE without a wildcard.  A LIKE pattern that does not include a
wildcard is potentially a bug in the SQL.

=item CLA.001

severity: warn

SELECT without WHERE.  The SELECT statement has no WHERE clause.

=item CLA.002

severity: note

ORDER BY RAND().  ORDER BY RAND() is a very inefficient way to
retrieve a random row from the results.

=item CLA.003

severity: note

LIMIT with OFFSET.  Paginating a result set with LIMIT and OFFSET is
O(n^2) complexity, and will cause performance problems as the data
grows larger.

=item CLA.004

severity: note

Ordinal in the GROUP BY clause.  Using a number in the GROUP BY clause,
instead of an expression or column name, can cause problems if the
query is changed.

=item CLA.005

severity: warn

ORDER BY constant column.

=item CLA.006

severity: warn

GROUP BY or ORDER BY different tables will force a temp table and filesort.

=item CLA.007

severity: warn

ORDER BY different directions prevents index from being used. All tables
in the ORDER BY clause must be either ASC or DESC, else MySQL cannot use
an index.

=item COL.001

severity: note

SELECT *.  Selecting all columns with the * wildcard will cause the
query's meaning and behavior to change if the table's schema
changes, and might cause the query to retrieve too much data.

=item COL.002

severity: note

Blind INSERT.  The INSERT or REPLACE query doesn't specify the
columns explicitly, so the query's behavior will change if the
table's schema changes; use "INSERT INTO tbl(col1, col2) VALUES..."
instead.

=item LIT.001

severity: warn

Storing an IP address as characters.  The string literal looks like
an IP address, but is not an argument to INET_ATON(), indicating that
the data is stored as characters instead of as integers.  It is
more efficient to store IP addresses as integers.

=item LIT.002

severity: warn

Unquoted date/time literal.  A query such as "WHERE col<2010-02-12"
is valid SQL but is probably a bug; the literal should be quoted.

=item KWR.001

severity: note

SQL_CALC_FOUND_ROWS is inefficient.  SQL_CALC_FOUND_ROWS can cause
performance problems because it does not scale well; use
alternative strategies to build functionality such as paginated
result screens.

=item JOI.001

severity: crit

Mixing comma and ANSI joins.  Mixing comma joins and ANSI joins
is confusing to humans, and the behavior differs between some
MySQL versions.

=item JOI.002

severity: crit

A table is joined twice.  The same table appears at least twice in the
FROM clause.

=item JOI.003

severity: warn

Reference to outer table column in WHERE clause prevents OUTER JOIN,
implicitly converts to INNER JOIN.

=item JOI.004

severity: warn

Exclusion join uses wrong column in WHERE.  The exclusion join (LEFT
OUTER JOIN with a WHERE clause that is satisfied only if there is no row in
the right-hand table) seems to use the wrong column in the WHERE clause.  A
query such as "... FROM l LEFT OUTER JOIN r ON l.l=r.r WHERE r.z IS NULL"
probably ought to list r.r in the WHERE IS NULL clause.

=item RES.001

severity: warn

Non-deterministic GROUP BY.  The SQL retrieves columns that are
neither in an aggregate function nor the GROUP BY expression, so
these values will be non-deterministic in the result.

=item RES.002

severity: warn

LIMIT without ORDER BY.  LIMIT without ORDER BY causes
non-deterministic results, depending on the query execution plan.

=item STA.001

severity: note

!= is non-standard.  Use the <> operator to test for inequality.

=item SUB.001

severity: crit

IN() and NOT IN() subqueries are poorly optimized.  MySQL executes the subquery
as a dependent subquery for each row in the outer query.  This is a frequent
cause of serious performance problems.  This might change version 6.0 of MySQL,
but for versions 5.1 and older, the query should be rewritten as a JOIN or a
LEFT OUTER JOIN, respectively.

=back

=head1 OPTIONS

L<"--query"> and L<"--review"> are mutually exclusive.

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

=item --[no]continue-on-error

default: yes

Continue working even if there is an error.

=item --daemonize

Fork to the background and detach from the shell.  POSIX
operating systems only.

=item --database

short form: -D; type: string

Connect to this database.  This is also used as the default database
for L<"--[no]show-create-table"> if a query does not use database-qualified
tables.

=item --defaults-file

short form: -F; type: string

Only read mysql options from the given file.  You must give an absolute
pathname.

=item --group-by

type: string; default: rule_id

Group items in the report by this attribute.  Possible attributes are:

   ATTRIBUTE GROUPS
   ========= ==========================================================
   rule_id   Items matching the same rule ID
   query_id  Queries with the same ID (the same fingerprint)
   none      No grouping, report each query and its advice individually

=item --help

Show help and exit.

=item --host

short form: -h; type: string

Connect to host.

=item --ignore-rules

type: hash

Ignore these rule IDs.

Specify a comma-separated list of rule IDs (e.g. LIT.001,RES.002,etc.)
to ignore. Currently, the rule IDs are case-sensitive and must be uppercase.

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

=item --print-all

Print all queries, even those that do not match any rules.  With
L<"--group-by"> C<none>, non-matching queries are printed in the main report
and profile.  For other L<"--group-by"> values, non-matching queries are only
printed in the profile.  Non-matching queries have zeros for C<NOTE>, C<WARN>
and C<CRIT> in the profile.

=item --query

type: string

Analyze this single query and ignore files and STDIN.  This option
allows you to supply a single query on the command line.  Any files
also specified on the command line are ignored.

=item --report-format

type: string; default: compact

Type of report format: full or compact.  In full mode, every query's
report contains the description of the rules it matched, even if this
information was previously displayed.  In compact mode, the repeated
information is suppressed, and only the rule ID is displayed.

=item --review

type: DSN

Analyze queries from this mk-query-digest query review table.

=item --sample

type: int; default: 1

How many samples of the query to show.

=item --set-vars

type: string; default: wait_timeout=10000

Set these MySQL variables.  Immediately after connecting to MySQL, this string
will be appended to SET and executed.

=item --[no]show-create-table

default: yes

Get C<SHOW CREATE TABLE> for each query's table.

If host connection options are given (like L<"--host">, L<"--port">, etc.)
then the tool will also get C<SHOW CREATE TABLE> for each query.  This
information is needed for some rules like JOI.004.  If this option is
disabled by specifying C<--no-show-create-table> then some rules may not
be checked.

=item --socket

short form: -S; type: string

Socket file to use for connection.

=item --type

type: Array

The type of input to parse (default slowlog).  The permitted types are
slowlog and genlog.

=item --user

short form: -u; type: string

User for login if not current user.

=item --verbose

short form: -v; cumulative: yes; default: 1

Increase verbosity of output.  At the default level of verbosity, the
program prints only the first sentence of each rule's description.  At
higher levels, the program prints more of the description.  See also
L<"--report-format">.

=item --version

Show version and exit.

=item --where

type: string

Apply this WHERE clause to the SELECT query on the L<"--review"> table.

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

=item * t

Table to use as the query review table.

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

You need the following Perl modules: DBI and DBD::mysql.

=head1 BUGS

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-query-advisor>.

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

Baron Schwartz, Daniel Nichter

=head1 ABOUT MAATKIT

This tool is part of Maatkit, a toolkit for power users of MySQL.  Maatkit
was created by Baron Schwartz; Baron and Daniel Nichter are the primary
code contributors.  Both are employed by Percona.  Financial support for
Maatkit development is primarily provided by Percona and its clients. 

=head1 VERSION

This manual page documents Ver 1.0.4 Distrib 7540 $Revision: 7531 $.

=cut

__END__
:endofperl
