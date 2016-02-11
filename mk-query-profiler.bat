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

# This is mk-query-profiler, a program to analyze MySQL workload.
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

our $VERSION = '1.1.22';
our $DISTRIB = '7540';
our $SVN_REV = sprintf("%d", (q$Revision: 7477 $ =~ m/(\d+)/g, 0));

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
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_query_profiler;

use English qw(-no_match_vars);
use List::Util qw(sum min max first);
use Time::HiRes qw(time);

$OUTPUT_AUTOFLUSH = 1;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;
use constant MAX_ULONG => 4294967295; # 2^32-1

# Globals that'll get set by subroutines.  Used in formats, which is why they
# must be global.
my $ch                 = {};
my $qcost              = 0;
my $qcost_total        = 0;
my $qtime_total        = 0;
my $bytes_in_total     = 0;
my $bytes_out_total    = 0;
my $which_query        = 0;
my $query_time         = 0;
my $query_text         = '';
my $qcache_inval       = 0;
my $qcache_inval_total = 0;
my $hdr_type           = '';

# Every status variable this script cares about
my @important_vars = qw(
   Bytes_received Bytes_sent
   Com_commit Com_delete Com_delete_multi Com_insert Com_insert_select
   Com_replace Com_replace_select Com_select Com_update Com_update_multi
   Created_tmp_disk_tables Created_tmp_files Created_tmp_tables Handler_commit
   Handler_delete Handler_read_first Handler_read_key Handler_read_next
   Handler_read_prev Handler_read_rnd Handler_read_rnd_next Handler_update
   Handler_write Innodb_buffer_pool_pages_flushed
   Innodb_buffer_pool_read_ahead_rnd Innodb_buffer_pool_read_ahead_seq
   Innodb_buffer_pool_read_requests Innodb_buffer_pool_reads
   Innodb_buffer_pool_wait_free Innodb_buffer_pool_write_requests
   Innodb_data_fsyncs Innodb_data_read Innodb_data_reads Innodb_data_writes
   Innodb_data_written Innodb_dblwr_pages_written Innodb_dblwr_writes
   Innodb_log_waits Innodb_log_write_requests Innodb_log_writes
   Innodb_os_log_fsyncs Innodb_os_log_written Innodb_pages_created
   Innodb_pages_read Innodb_pages_written Innodb_row_lock_time
   Innodb_row_lock_waits Innodb_rows_deleted Innodb_rows_inserted
   Innodb_rows_read Innodb_rows_updated Key_read_requests Key_reads
   Key_write_requests Key_writes Last_query_cost Qcache_hits Qcache_inserts
   Qcache_lowmem_prunes Qcache_queries_in_cache Questions Select_full_join
   Select_full_range_join Select_range Select_range_check Select_scan
   Sort_merge_passes Sort_range Sort_rows Sort_scan Table_locks_immediate
);

# Status variables that may decrease (if monotonically increasing variables
# decrease, it means they wrapped over the max size of a ulong).
my %non_monotonic_vars = (
   Qcache_queries_in_cache => 1,
   Last_query_cost         => 1,
);

sub main {
   @ARGV = @_;  # set global ARGV for this package

   # ########################################################################
   # Get configuration information.
   # ########################################################################
   my $o = new OptionParser();
   $o->get_specs();
   $o->get_opts();

   my $dp = $o->DSNParser();
   $dp->prop('set-vars', $o->get('set-vars'));

   $o->set('verbose', min(2, $o->get('verbose')));

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

   # Connect to the database
   if ( $o->get('ask-pass') ) {
      $o->set('p', OptionParser::prompt_noecho("Enter password: "));
   }
   my $dsn = $dp->parse_options($o);
   my $dbh = $dp->get_dbh($dp->get_cxn_params($dsn), { AutoCommit => 1, });

   my $variables = get_variables($dbh);

   my $have_innodb
      = $o->get('innodb') && $variables->{have_innodb} eq 'YES' ? 1 : 0;

   # SESSION status and InnoDB status values.
   my $have_session
      = $o->get('session') && version_ge($dbh, '5.0.2'); 

   # InnoDB row lock status.
   my $have_rowlock = version_ge($dbh, '5.0.3') && $have_innodb; 

   # Last query cost according to optimizer.
   my $have_last = version_ge($dbh, '5.0.1') && !$o->get('external');    

   # Configure the query cache
   my $have_qcache = 0;
   if ( $variables->{query_cache_size} ) {
      if ( $o->get('allow-cache') || $o->get('external') ) {
         $have_qcache = 1;
      }
      else {
         $dbh->do("SET SESSION query_cache_type = OFF");
      }
   }

   # Depending on the level of verbosity and the server version, summary and
   # separate printouts will include different formats.
   my $formats_for = {
      0 => [
         $have_last    ? qw( OPT_COST ) : qw(),
                         qw( TBL_IDX ),
         $have_qcache  ? qw( QCACHE )   : qw(),
      ],
      1 => [
         $have_last    ? qw( OPT_COST )       : qw(),
                         qw( TBL_IDX ),
         $have_qcache  ? qw( QCACHE )         : qw(),
         $have_innodb  ? qw( ROW_OPS_INNODB ) : qw( ROW_OPS ),
      ],
      2 => [
         $have_last    ? qw( OPT_COST )                         : qw(),
                         qw( TBL_IDX ),
         $have_qcache  ? qw( QCACHE )                           : qw(),
         $have_innodb  ? qw( ROW_OPS_INNODB )                   : qw( ROW_OPS ),
         $have_rowlock ? qw( ROW_LOCKS )                        : qw(),
         $have_innodb  ? qw( IO_OPS IO_INNODB INNODB_DATA_OPS ) : qw( IO_OPS ),
      ],
   };

   # ########################################################################
   # Get a baseline for how much SHOW STATUS costs.
   # ########################################################################

   # SESSION status variables this script cares about.
   my @session_vars
      = $have_session
      ? qw(
         Bytes_received Bytes_sent Com_commit Com_delete Com_delete_multi
         Com_insert Com_insert_select Com_replace Com_replace_select
         Com_select Com_update Com_update_multi Created_tmp_disk_tables
         Created_tmp_tables Handler_commit Handler_delete
         Handler_read_first Handler_read_key Handler_read_next Handler_read_prev
         Handler_read_rnd Handler_read_rnd_next Handler_update Handler_write
         Last_query_cost Select_full_join Select_full_range_join Select_range
         Select_range_check Select_scan Sort_merge_passes Sort_range Sort_rows
         Sort_scan
         )
      : qw();

   # Throwaway to prime caches after FLUSH
   get_status_info($o, $dbh, $have_session); 
   my $status_0 = get_status_info($o, $dbh, $have_session);
   my $status_1 = get_status_info($o, $dbh, $have_session);

   my $base = $o->get('calibrate')
      ? ( { map { $_ => $status_1->{$_} - $status_0->{$_} } @important_vars } )
      : ( { map { $_ => 0 } @important_vars } );

   if ( $o->get('verify') ) {
      my $base_2 = $o->get('calibrate') ? $base
                 : ( { map { $_ => $status_1->{$_} - $status_0->{$_} } @important_vars } );

      sleep(1);
      my $status_2 = get_status_info($o, $dbh, $have_session);
      my $base_3
         = { map { $_ => $status_2->{$_} - $status_1->{$_} } @session_vars };
      foreach my $key ( @session_vars ) {
         if ( $base_3->{$key} != $base_2->{$key} ) {
            print "Cost of observation changed: $key $base_3->{$key} $base_2->{$key}\n";
         }
      }
   }

   # ########################################################################
   # The main work happens now.
   # ########################################################################

   # Get a baseline status.
   my $sql_status_0 = get_status_info($o, $dbh, $have_session);
   my @queries;

   # ########################################################################
   # Do the profiling.
   # ########################################################################
   my $have_flushed_tables = 0;

   if ( $o->get('external') ) { # An external process will issue queries
      if ( !@ARGV ) { # Don't read files or STDIN
         flush_tables($o, $dbh, $have_flushed_tables++);
         my $start = time();
         print "Press <ENTER> when the external program is finished";
         <STDIN>;
         my $end = time();
         # Hack the @queries variable by stuffing the external program's
         # data in as a hash reference just as though it had been a query
         # in a file.
         push @queries, {
            text   => '[External program]',
            start  => $start,
            end    => $end,
            status => get_status_info($o, $dbh, $have_session),
         };
      }
      else {
         while ( my $line = <> ) { # Read from STDIN, or files named on cmdline
            chomp $line;
            next unless $line;

            flush_tables($o, $dbh, $have_flushed_tables++);
            my $start = time();
            print `$line`;
            my $end = time();
            push @queries, {
               text   => $line,
               start  => $start,
               end    => $end,
               status => get_status_info($o, $dbh, $have_session),
            };
         }
      }
   }
   else {
      local $INPUT_RECORD_SEPARATOR = ''; # read a paragraph at a time
      while ( my $line = <> ) { # Read from STDIN, or files named on cmdline
         chomp $line;
         next unless $line;
         $line =~ s/;\s*\z//xms; # Remove trailing whitespace/semicolon

         flush_tables($o, $dbh, $have_flushed_tables++);
         my $query = {
            text  => $line,
            start => time(),
         };
         # It appears to me that this actually fetches all the data over the
         # wire, which is what I want for purposes of counting bytes in and
         # bytes out.
         $dbh->do( $line );
         $query->{end}    = time();
         $query->{status} = get_status_info($o, $dbh, $have_session);
         push @queries, $query;
      }
   }

   # ########################################################################
   # Tab-separated output for a spreadsheet.
   # ########################################################################
   if ( $o->get('tab') ) {

      # Get a list of all the SHOW STATUS measurements.
      my @statuses = (
         $sql_status_0,
         ( map { $_->{status} } @queries ),
         get_status_info($o, $dbh, $have_session),
      );

      # Decide which variables to output.  If verbosity is 0, output only those
      # whose values are non-zero across the board.  If verbosity is greater,
      # output everything.
      my @variables = sort keys %$sql_status_0;
      if ( !$o->get('verbose') ) {
         @variables = grep {
            # Discover whether there is a true value in any set.  A 'true'
            # value is one where the value isn't the same as the value for
            # the same key in the previous set.  The first (before) and last
            # (calibrate) set are excluded.
            my $var = $_;
            first { # first() terminates early, unlike grep()
               defined $statuses[$_]->{$var}
               && defined $statuses[$_ - 1]->{$var}
               && $statuses[$_]->{$var} != $statuses[$_ - 1]->{$var}
            } ( 1 .. $#statuses - 1 );
         } @variables;
      }

      # Print headers.
      print
         join("\t",
            'Variable_name',
            'Before',
            ( map { "After$_" } ( 1 ..  $#statuses - 1 ) ),
            'Calibration',
         ),
         "\n";

      # Print each variable in tab-separated values.
      foreach my $key ( @variables ) {
         print
            join("\t", $key,
               map { defined($_->{$key}) ? $_->{$key} : '' } @statuses),
            "\n";
      }
   }

   # ########################################################################
   # Tabular layout for human readability.
   # ########################################################################
   else {
      # Print the separate results and accumulate global totals.
      foreach my $i ( 0 .. $#queries ) {
         my $query     = $queries[$i];
         my $before    = $i ? $queries[ $i - 1 ]->{status} : $sql_status_0;
         my $after     = $query->{status};

         # Accumulate some globals
         $qcost_total += $after->{Last_query_cost};
         $qtime_total += $query->{end} - $query->{start};
         $which_query = $i + 1;
         $query_time  = $query->{end} - $query->{start};
         $ch          = get_changes($base, $before, $after, 1);

         # Accumulate query cache invalidations
         $qcache_inval
            = ($ch->{Qcache_inserts} > 0 && $ch->{Qcache_queries_in_cache} == 0)
               || $ch->{Qcache_queries_in_cache} < 0
            ? -$ch->{Qcache_queries_in_cache} - $ch->{Qcache_lowmem_prunes}
            : 0;
         $qcache_inval_total += $qcache_inval;
         $bytes_in_total     += $ch->{Bytes_received};
         $bytes_out_total    += $ch->{Bytes_sent};

         # Print separate stats
         if ( $o->get('separate') && @queries > 1
              && (!$o->get('only') || $o->get('only')->{ $i + 1 } )) {
            $qcost        = $after->{Last_query_cost};
            ( $query_text = $query->{text} ) =~ s/\s+/ /g;
            $FORMAT_NAME  = $o->get('external') ? 'SUMMARY'  : 'QUERY';
            $hdr_type     = $o->get('external') ? 'EXTERNAL' : 'QUERY';
            write;
            foreach my $format_name ( @{$formats_for->{$o->get('verbose')}}) {
               $FORMAT_NAME = $format_name;
               write;
            }
         }
      }

      # Print summary stats
      $ch           = get_changes($base, $sql_status_0, $queries[-1]->{status}, scalar(@queries) );
      $qcache_inval = $qcache_inval_total;
      $qcost        = $qcost_total;
      $FORMAT_NAME  = "SUMMARY";
      write;
      foreach my $format_name ( @{$formats_for->{$o->get('verbose')}}) {
         $FORMAT_NAME = $format_name;
         write;
      }
      if ( !$have_session ) {
         if ( $queries[-1]->{status}->{Questions} - $sql_status_0->{Questions}
            > (@queries * 2) + 1 ) {
            print STDERR "WARNING: Something else accessed the database at "
               . "the same time you were trying to profile this batch!  These "
               . "numbers are not correct!\n";
         }
         else {
            print STDERR "WARNING: These statistics could be wrong if "
               . "anything else was accessing the database at the same time.\n";
         }
      }
   }

   $dbh->disconnect();

   return 0;
}

# ############################################################################
# Subroutines
# ############################################################################

sub flush_tables {
   my ($o, $dbh, $have_flushed) = @_;
   return if !$o->get('flush')
      || ( $o->get('flush') == 1 && $have_flushed );
   eval { $dbh->do("FLUSH TABLES") };
   if ( $EVAL_ERROR ) {
      print STDERR "Warning: can't FLUSH TABLES because $EVAL_ERROR\n";
   }
}

sub get_changes {
   my ( $base, $before, $after, $num_base ) = @_;
   $num_base ||= 1;
   return { map {
      $after->{$_}  ||= 0;
      $before->{$_} ||= 0;
      my $val = $after->{$_} - $before->{$_} - ( $num_base * $base->{$_} );
      if ( $val < 0 && !defined($non_monotonic_vars{$_}) ) {
         # Handle when a ulong wraps over the 32-bit boundary
         $val += MAX_ULONG;
      }
      $_ => $val;
   } @important_vars };
}

sub get_status_info {
   my ( $o, $dbh, $have_session ) = @_;
   my $res = $dbh->selectall_arrayref(
      $have_session
         ? ($o->get('external') ? 'SHOW GLOBAL STATUS' : 'SHOW SESSION STATUS')
         : 'SHOW STATUS' );
   my %result = map { @{$_} } @$res;
   return { map { $_ => $result{$_} || 0 } @important_vars };
}

sub get_variables {
   my $dbh = shift;
   my $res = $dbh->selectall_arrayref('SHOW VARIABLES');
   return { map { @{$_} } @$res };
}

# Compares versions like 5.0.27 and 4.1.15-standard-log
sub version_ge {
   my ( $dbh, $target ) = @_;
   my $version = sprintf('%03d%03d%03d', $dbh->{mysql_serverinfo} =~ m/(\d+)/g);
   return $version ge sprintf('%03d%03d%03d', $target =~ m/(\d+)/g);
}

sub get_file {
   my $filename = shift;
   open my $file, "<", "$filename" or die "Can't open $filename: $OS_ERROR";
   my $file_contents = do { local $INPUT_RECORD_SEPARATOR; <$file>; };
   close $file;
   return $file_contents;
}

# ############################################################################
# Formats
# ############################################################################

format SUMMARY =

+----------------------------------------------------------+
| @||||||||||||||||||||||||||||||||||||||||||||||||||||||| |
sprintf("$hdr_type %d (%.4f sec)", $which_query, $query_time)
+----------------------------------------------------------+

__ Overall stats _______________________ Value _____________
   Total elapsed time              @##########.###
$qtime_total
   Questions                       @##########
$ch->{Questions}
     COMMIT                        @##########
$ch->{Com_commit}
     DELETE                        @##########
$ch->{Com_delete}
     DELETE MULTI                  @##########
$ch->{Com_delete_multi}
     INSERT                        @##########
$ch->{Com_insert}
     INSERT SELECT                 @##########
$ch->{Com_insert_select}
     REPLACE                       @##########
$ch->{Com_replace}
     REPLACE SELECT                @##########
$ch->{Com_replace_select}
     SELECT                        @##########
$ch->{Com_select}
     UPDATE                        @##########
$ch->{Com_update}
     UPDATE MULTI                  @##########
$ch->{Com_update_multi}
   Data into server                @##########
$bytes_in_total
   Data out of server              @##########
$bytes_out_total
.

format TBL_IDX =

__ Table and index accesses ____________ Value _____________
   Table locks acquired            @##########
$ch->{Table_locks_immediate}
   Table scans                     @##########
$ch->{Select_scan} + $ch->{Select_full_join}
     Join                          @##########
$ch->{Select_full_join}
   Index range scans               @##########
{
   $ch->{Select_range} + $ch->{Select_full_range_join}
   + $ch->{Select_range_check}
}
     Join without check            @##########
$ch->{Select_full_range_join}
     Join with check               @##########
$ch->{Select_range_check}
   Rows sorted                     @##########
$ch->{Sort_rows}
     Range sorts                   @##########
$ch->{Sort_range}
     Merge passes                  @##########
$ch->{Sort_merge_passes}
     Table scans                   @##########
$ch->{Sort_scan}
     Potential filesorts           @##########
min($ch->{Sort_scan}, $ch->{Created_tmp_tables})
.

format QCACHE =
   Query cache
     Hits                          @##########
$ch->{Qcache_hits}
     Inserts                       @##########
$ch->{Qcache_inserts}
     Invalidations                 @##########
$qcache_inval
.

format ROW_OPS_INNODB =

__ Row operations ____________________ Handler ______ InnoDB
   Reads                           @##########   @##########
{
   $ch->{Handler_read_rnd}
   + $ch->{Handler_read_rnd_next}
   + $ch->{Handler_read_key}
   + $ch->{Handler_read_first}
   + $ch->{Handler_read_next}
   + $ch->{Handler_read_prev},
   $ch->{Innodb_rows_read} || 0
}
     Fixed pos (might be sort)     @##########
$ch->{Handler_read_rnd}
     Next row (table scan)         @##########
$ch->{Handler_read_rnd_next}
     Bookmark lookup               @##########
$ch->{Handler_read_key}
     First in index (full scan?)   @##########
$ch->{Handler_read_first}
     Next in index                 @##########
$ch->{Handler_read_next}
     Prev in index                 @##########
$ch->{Handler_read_prev}
   Writes
     Delete                        @##########   @##########
$ch->{Handler_delete}, $ch->{Innodb_rows_deleted}
     Update                        @##########   @##########
$ch->{Handler_update}, $ch->{Innodb_rows_updated}
     Insert                        @##########   @##########
$ch->{Handler_write}, $ch->{Innodb_rows_inserted}
     Commit                        @##########
$ch->{Handler_commit}
.

format ROW_OPS =

__ Row operations ____________________ Handler _____________
   Reads                           @##########
{
   $ch->{Handler_read_rnd}
   + $ch->{Handler_read_rnd_next}
   + $ch->{Handler_read_key}
   + $ch->{Handler_read_first}
   + $ch->{Handler_read_next}
   + $ch->{Handler_read_prev}
}
     Fixed pos (might be sort)     @##########
$ch->{Handler_read_rnd}
     Next row (table scan)         @##########
$ch->{Handler_read_rnd_next}
     Bookmark lookup               @##########
$ch->{Handler_read_key}
     First in index (full scan?)   @##########
$ch->{Handler_read_first}
     Next in index                 @##########
$ch->{Handler_read_next}
     Prev in index                 @##########
$ch->{Handler_read_prev}
   Writes
     Delete                        @##########
$ch->{Handler_delete}
     Update                        @##########
$ch->{Handler_update}
     Insert                        @##########
$ch->{Handler_write}
     Commit                        @##########
$ch->{Handler_commit}
.

format ROW_LOCKS =
   InnoDB row locks
     Number of locks waited for                  @##########
$ch->{Innodb_row_lock_waits}
     Total ms spent acquiring locks              @##########
$ch->{Innodb_row_lock_time}
.

format IO_OPS =

__ I/O Operations _____________________ Memory ________ Disk
   Key cache
     Key reads                     @##########    @#########
$ch->{Key_read_requests}, $ch->{Key_reads}
     Key writes                    @##########    @#########
$ch->{Key_write_requests}, $ch->{Key_writes}
   Temp tables                     @##########    @#########
$ch->{Created_tmp_tables}, $ch->{Created_tmp_disk_tables}
   Temp files                                     @#########
$ch->{Created_tmp_files}
.

format IO_INNODB =
   InnoDB buffer pool
     Reads                         @##########    @#########
$ch->{Innodb_buffer_pool_read_requests}, $ch->{Innodb_buffer_pool_reads}
     Random read-aheads            @##########
$ch->{Innodb_buffer_pool_read_ahead_rnd}
     Sequential read-aheads        @##########
$ch->{Innodb_buffer_pool_read_ahead_seq}
     Write requests                @##########    @#########
$ch->{Innodb_buffer_pool_write_requests}, $ch->{Innodb_buffer_pool_pages_flushed}
     Reads/creates blocked by flushes             @#########
$ch->{Innodb_buffer_pool_wait_free}
   InnoDB log operations
     Log writes                    @##########    @#########
$ch->{Innodb_log_write_requests}, $ch->{Innodb_log_writes}
     Log writes blocked by flushes                @#########
$ch->{Innodb_log_waits}
.

format INNODB_DATA_OPS =

__ InnoDB Data Operations ____ Pages _____ Ops _______ Bytes
   Reads                   @######## @########    @#########
$ch->{Innodb_pages_read}, $ch->{Innodb_data_reads}, $ch->{Innodb_data_read}
   Writes                  @######## @########    @#########
$ch->{Innodb_pages_written}, $ch->{Innodb_data_writes}, $ch->{Innodb_data_written}
   Doublewrites            @######## @########
$ch->{Innodb_dblwr_pages_written}, $ch->{Innodb_dblwr_writes}
   Creates                 @########
$ch->{Innodb_pages_created}
   Fsyncs                            @########
$ch->{Innodb_data_fsyncs}
   OS fsyncs                         @########    @#########
$ch->{Innodb_os_log_fsyncs}, $ch->{Innodb_os_log_written}
.

format QUERY =

+----------------------------------------------------------+
| @||||||||||||||||||||||||||||||||||||||||||||||||||||||| |
sprintf("QUERY %d (%.4f sec)", $which_query, $query_time)
+----------------------------------------------------------+
^<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<...
$query_text

__ Overall stats _______________________ Value _____________
   Elapsed time                    @##########.###
$query_time
   Data into server                @##########
$ch->{Bytes_received}
   Data out of server              @##########
$ch->{Bytes_sent}
.

format OPT_COST =
   Optimizer cost                  @##########.###
$qcost
.

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

mk-query-profiler - Execute SQL statements and print statistics, or measure
activity caused by other processes.

=head1 SYNOPSIS

Usage: mk-query-profiler [OPTION...] [FILE...]

mk-query-profiler reads and executes queries, and prints statistics about
MySQL server load.  Connection options are read from MySQL option files.
If FILE is given, queries are read and executed from the file(s).  With no
FILE, or when FILE is -, read standard input.  If --external is specified,
lines in FILE are executed by the shell.  You must specify - if no FILE and
you want --external to read and execute from standard input.  Queries in
FILE must be terminated with a semicolon and separated by a blank line.

mk-query-profiler can profile the (semicolon-terminated, blank-line
separated) queries in a file:

   mk-query-profiler queries.sql
   cat queries.sql | mk-query-profiler
   mk-query-profiler -vv queries.sql
   mk-query-profiler -v --separate --only 2,5,6 queries.sql
   mk-query-profiler --tab queries.sql > results.csv

It can also just observe what happens in the server:

   mk-query-profiler --external

Or it can run shell commands from a file and measure the result:

   mk-query-profiler --external commands.txt
   mk-query-profiler --external - < commands.txt

Read L<"HOW TO INTERPRET"> to learn what it all means.

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

mk-query-profiler is generally read-only and very low risk.  It will execute FLUSH TABLES if you specify L<"--flush">.

At the time of this release, we know of no bugs that could cause serious harm to
users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-query-profiler>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

mk-query-profiler reads a file containing one or more SQL statements or shell
commands, executes them, and analyzes the output of SHOW STATUS afterwards.
It then prints statistics about how the batch performed.  For example, it can
show how many table scans the batch caused, how many page reads, how many
temporary tables, and so forth.

All command-line arguments are optional, but you must either specify a file
containing the batch to profile as the last argument, or specify that you're
profiling an external program with the L<"--external"> option, or provide
input to STDIN.

If the file contains multiple statements, they must be separated by blank
lines.  If you don't do that, mk-query-profiler won't be able to split the
file into individual queries, and MySQL will complain about syntax errors.

If the MySQL server version is before 5.0.2, you should make sure the server
is completely unused before trying to profile a batch.  Prior to this version,
SHOW STATUS showed only global status variables, so other queries will
interfere and produce false results.  mk-query-profiler will try to detect
if anything did interfere, but there can be no guarantees.

Prior to MySQL 5.0.2, InnoDB status variables are not available, and prior to
version 5.0.3, InnoDB row lock status variables are not available.
mk-query-profiler will omit any output related to these variables if they're not
available.

For more information about SHOW STATUS, read the relevant section of the MySQL
manual at
L<http://dev.mysql.com/doc/en/server-status-variables.html>

=head1 HOW TO INTERPRET

=head2 TAB-SEPARATED OUTPUT

If you specify L<"--tab">, you will get the raw output of SHOW STATUS in
tab-separated format, convenient for opening with a spreadsheet.  This is not
the default output, but it's so much easier to describe that I'll cover it
first.

=over

=item *

Most of the command-line options for controlling verbosity and such are
ignored in --tab mode.

=item *

The variable names you see in MySQL, such as 'Com_select', are kept --
there are no euphimisms, so you have to know your MySQL variables.

=item *

The columns are Variable_name, Before, After1...AfterN, Calibration.
The Variable_name column is just what it sounds like.  Before is the result
from the first run of SHOW STATUS.  After1, After2, etc are the results of
running SHOW STATUS after each query in the batch.  Finally, the last column
is the result of running SHOW STATUS just after the last AfterN column, so you
can see how much work SHOW STATUS itself causes.

=item *

If you specify L<"--verbose">, output includes every variable
mk-query-profiler measures.  If not (default) it only includes variables where
there was some difference from one column to the next.

=back

=head2 NORMAL OUTPUT

If you don't specify --tab, you'll get a report formatted for human
readability.  This is the default output format.

mk-query-profiler can output a lot of information, as you've seen if you
ran the examples in the L<"SYNOPSIS">.  What does it all mean?

First, there are two basic groups of information you might see: per-query and
summary.  If your batch contains only one query, these will be the same and
you'll only see the summary.  You can recognize the difference by looking for
centered, all-caps, boxed-in section headers.  Externally profiled commands will
have EXTERNAL, individually profiled queries will have QUERY, and summary will
say SUMMARY.

Next, the information in each section is grouped into subsections, headed by
an underlined title.  Each of these sections has varying information in it.
Which sections you see depends on command-line arguments and your MySQL
version.  I'll explain each section briefly.  If you really want to know where
the numbers come from, read
L<http://dev.mysql.com/doc/en/server-status-variables.html>.

You need to understand which numbers are insulated from other queries and
which are not.  This depends on your MySQL version.  Version 5.0.2 introduced
the concept of session status variables, so you can see information about only
your own connection.  However, many variables aren't session-ized, so when you
have MySQL 5.0.2 or greater, you will actually see a mix of session and global
variables.  That means other queries happening at the same time will pollute
some of your results.  If you have MySQL versions older than 5.0.2, you won't
have ANY connection-specific stats, so your results will be polluted by other
queries no matter what.  Because of the mixture of session and global
variables, by far the best way to profile is on a completely quiet server
where nothing else is interfering with your results.

While explaining the results in the sections that follow, I'll refer to a
value as "protected" if it comes from a session-specific variable and can be
relied upon to be accurate even on a busy server.  Just keep in mind, if
you're not using MySQL 5.0.2 or newer, your results will be inaccurate unless
you're running against a totally quiet server, even if I label it as
"protected."

=head2 Overall stats

This section shows the overall elapsed time for the query, as measured by
Perl, and the optimizer cost as reported by MySQL.

If you're viewing separate query statistics, this is all you'll see.  If
you're looking at a summary, you'll also see a breakdown of the questions the
queries asked the server.

The execution time is not totally reliable, as it includes network round-trip
time, Perl's own execution time, and so on.  However, on a low-latency
network, this should be fairly negligible, giving you a reasonable measure of
the query's time, especially for queries longer than a few tenths of a second.

The optimizer cost comes from the Last_query_cost variable, and is protected
from other connections in MySQL 5.0.7 and greater.  It is not available before
5.0.1.

The total number of questions is not protected, but the breakdown of
individual question types is, because it comes from the Com_ status variables.

=head2 Table and index accesses

This section shows you information about the batch's table and index-level
operations (as opposed to row-level operations, which will be in the next
section).  The "Table locks acquired" and "Temp files" values are unprotected,
but everything else in this section is protected.

The "Potential filesorts" value is calculated as the number of times a query had
both a scan sort (Sort_scan) and created a temporary table (Created_tmp_tables).
There is no Sort_filesort or similar status value, so it's a best guess at
whether a query did a filesort.  It should be fairly accurate.

If you specified L<"--allow-cache">, you'll see statistics on the query cache.
These are unprotected.

=head2 Row operations

These values are all about the row-level operations your batch caused.  For
example, how many rows were inserted, updated, or deleted.  You'll also see
row-level index access statistics, such as how many times the query sought and
read the next entry in an index.

Depending on your MySQL version, you'll either see one or two columns of
information in this section.  The one headed "Handler" is all from the
Handler_ variables, and those statistics are protected.  If your MySQL version
supports it, you'll also see a column headed "InnoDB," which is unprotected.

=head2 I/O Operations

This section gives information on I/O operations your batch caused, both in
memory and on disk.  Unless you have MySQL 5.0.2 or greater, you'll only see
information on the key cache.  Otherwise, you'll see a lot of information on
InnoDB's I/O operations as well, such as how many times the query was able to
satisfy a read from the buffer pool and how many times it had to go to the
disk.

None of the information in this section is protected.

=head2 InnoDB Data Operations

This section only appears when you're querying MySQL 5.0.2 or newer.  None of
the information is protected.  You'll see statistics about how many pages were
affected, how many operations took place, and how many bytes were affected.

=head1 OPTIONS

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --allow-cache

Let MySQL query cache cache the queries executed.

By default this is disabled.  When enabled, cache profiling information is added
to the printout.  See L<http://dev.mysql.com/doc/en/query-cache.html> for more
information about the query cache.

=item --ask-pass

Prompt for a password when connecting to MySQL.

=item --[no]calibrate

default: yes

Try to compensate for C<SHOW STATUS>.

Measure and compensate for the "cost of observation" caused by running SHOW
STATUS.  Only works reliably on a quiet server; on a busy server, other
processes can cause the calibration to be wrong.

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

=item --database

short form: -D; type: string

Database to use for connection.

=item --defaults-file

short form: -F; type: string

Only read mysql options from the given file.  You must give an absolute
pathname.

=item --external

Calibrate, then pause while an external program runs.

This is typically useful while you run an external program.  When you press
[enter] mk-query-profiler will stop sleeping and take another measurement, then
print statistics as usual.

When there is a filename on the command line, mk-query-profiler executes
each line in the file as a shell command.  If you give - as the filename,
mk-query-profiler reads from STDIN.

Output from shell commands is printed to STDOUT and terminated with __BEGIN__,
after which mk-query-profiler prints its own output.

=item --flush

cumulative: yes

Flush tables.  Specify twice to do between every query.

Calls FLUSH TABLES before profiling.  If you are executing queries from a
batch file, specifying --flush twice will cause mk-query-profiler to call
FLUSH TABLES between every query, not just once at the beginning.  Default is
not to flush at all. See L<http://dev.mysql.com/doc/en/flush.html> for more
information.

=item --help

Show help and exit.

=item --host

short form: -h; type: string

Connect to host.

=item --[no]innodb

default: yes

Show InnoDB statistics.

=item --only

type: hash

Only show statistics for this comma-separated list of queries or commands.

=item --password

short form: -p; type: string

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

short form: -P; type: int

Port number to use for connection.

=item --separate

Print stats separately for each query.

The default is to show only the summary of the entire batch.  See also
L<"--verbose">.

=item --[no]session

default: yes

Use session C<SHOW STATUS> and C<SHOW VARIABLES>.

Disabled if the server version doesn't support it.

=item --set-vars

type: string; default: wait_timeout=10000

Set these MySQL variables.  Immediately after connecting to MySQL, this string
will be appended to SET and executed.

=item --socket

short form: -S; type: string

Socket file to use for connection.

=item --tab

Print tab-separated values instead of whitespace-aligned columns.

=item --user

short form: -u; type: string

User for login if not current user.

=item --verbose

short form: -v; cumulative: yes; default: 0

Verbosity; specify multiple times for more detailed output.

When L<"--tab"> is given, prints variables that don't change.  Otherwise
increasing the level of verbosity includes extra sections in the output.

=item --verify

Verify nothing else is accessing the server.

This is a weak verification; it simply calibrates twice (see
L<"--[no]calibrate">) and verifies that the cost of observation remains
constant.

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

You need Perl, DBI, DBD::mysql, and some core modules.

=head1 BUGS

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-query-profiler>.

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

See also L<mk-profile-compact>.

=head1 AUTHOR

Baron Schwartz

=head1 ABOUT MAATKIT

This tool is part of Maatkit, a toolkit for power users of MySQL.  Maatkit
was created by Baron Schwartz; Baron and Daniel Nichter are the primary
code contributors.  Both are employed by Percona.  Financial support for
Maatkit development is primarily provided by Percona and its clients. 

=head1 ACKNOWLEDGEMENTS

I was inspired by the wonderful mysqlreport utility available at
L<http://www.hackmysql.com/>.

Other contributors: Bart van Bragt.

Thanks to all who have helped.

=head1 VERSION

This manual page documents Ver 1.1.22 Distrib 7540 $Revision: 7477 $.

=cut

__END__
:endofperl
