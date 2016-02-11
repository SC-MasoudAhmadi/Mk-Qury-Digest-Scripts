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

# This program synchronizes data efficiently between two MySQL tables, which
# can be on different servers.
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

our $VERSION = '1.0.31';
our $DISTRIB = '7540';
our $SVN_REV = sprintf("%d", (q$Revision: 7476 $ =~ m/(\d+)/g, 0));

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
# TableSyncStream package 5697
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/TableSyncStream.pm
#   trunk/common/t/TableSyncStream.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package TableSyncStream;

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
   return 'Stream';
}

sub can_sync {
   return 1;  # We can sync anything.
}

sub prepare_to_sync {
   my ( $self, %args ) = @_;
   my @required_args = qw(cols ChangeHandler);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   $self->{cols}            = $args{cols};
   $self->{buffer_in_mysql} = $args{buffer_in_mysql};
   $self->{ChangeHandler}   = $args{ChangeHandler};

   $self->{done}  = 0;

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
   return "SELECT "
      . ($self->{buffer_in_mysql} ? 'SQL_BUFFER_RESULT ' : '')
      . join(', ', map { $self->{Quoter}->quote($_) } @{$self->{cols}})
      . ' FROM ' . $self->{Quoter}->quote(@args{qw(database table)})
      . ' WHERE ' . ( $args{where} || '1=1' );
}

sub same_row {
   my ( $self, %args ) = @_;
   return;
}

sub not_in_right {
   my ( $self, %args ) = @_;
   $self->{ChangeHandler}->change('INSERT', $args{lr}, $self->key_cols());
}

sub not_in_left {
   my ( $self, %args ) = @_;
   $self->{ChangeHandler}->change('DELETE', $args{rr}, $self->key_cols());
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
# End TableSyncStream package
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
# MasterSlave package 6935
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
   if ( !$self->{not_a_master}->{$dbh} ) {
      my $sth = $self->{sths}->{$dbh}->{MASTER_STATUS}
            ||= $dbh->prepare('SHOW MASTER STATUS');
      MKDEBUG && _d($dbh, 'SHOW MASTER STATUS');
      $sth->execute();
      my ($ms) = @{$sth->fetchall_arrayref({})};

      if ( $ms && %$ms ) {
         $ms = { map { lc($_) => $ms->{$_} } keys %$ms }; # lowercase the keys
         if ( $ms->{file} && $ms->{position} ) {
            return $ms;
         }
      }

      MKDEBUG && _d('This server returns nothing for SHOW MASTER STATUS');
      $self->{not_a_master}->{$dbh}++;
   }
}

sub wait_for_master {
   my ( $self, %args ) = @_;
   my @required_args = qw(master_dbh slave_dbh);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($master_dbh, $slave_dbh) = @args{@required_args};
   my $timeout       = $args{timeout} || 60;
   my $master_status = $args{master_status}
                       || $self->get_master_status($master_dbh);

   my $result;
   my $waited;
   if ( $master_status ) {
      my $sql = "SELECT MASTER_POS_WAIT('$master_status->{file}', "
              . "$master_status->{position}, $timeout)";
      MKDEBUG && _d($slave_dbh, $sql);
      my $start  = time;
      ($result)  = $slave_dbh->selectrow_array($sql);

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
   my ( $self, $slave, $master, $time ) = @_;
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
            master_dbh    => $master,
            slave_dbh     => $slave,
            timeout       => $time,
            master_status => $master_status
      );
      if ( !defined $result ) {
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
package mk_table_sync;

use English qw(-no_match_vars);
use List::Util qw(sum max min);
use POSIX qw(ceil);

Transformers->import(qw(time_to_secs any_unix_timestamp));

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

$OUTPUT_AUTOFLUSH = 1;

my %dsn_for;

sub main {
   @ARGV = @_;  # set global ARGV for this package

   # Reset global vars else tests will have weird results.
   %dsn_for = ();

   # ########################################################################
   # Get configuration information.
   # ########################################################################
   my $o = new OptionParser();
   $o->get_specs();
   $o->get_opts();

   my $dp = $o->DSNParser();
   $dp->prop('set-vars', $o->get('set-vars'));

   if ( $o->get('replicate') || $o->get('sync-to-master') ) {
      $o->set('wait', 60) unless $o->got('wait');
   }
   if ( $o->get('wait') ) {
      $o->set('lock', 1) unless $o->got('lock');
   }
   if ( $o->get('dry-run') ) {
      $o->set('verbose', 1);
   }

   # There's a conflict of interests: we added 't' and 'D' parts to dp,
   # and there are -t and -D options (--tables, --databases), so parse_options()
   # is going to return a DSN with the default values from -t and -D,
   # but these are not actually be default dsn vals, they're filters.
   # So we have to remove them from $dsn_defaults.
   my $dsn_defaults = $dp->parse_options($o);
   $dsn_defaults->{D} = undef;
   $dsn_defaults->{t} = undef;

   my @dsns;
   while ( my $arg = shift(@ARGV) ) {
      my $dsn = $dp->parse($arg, $dsns[0], $dsn_defaults);
      die "You specified a t part, but not a D part in $arg"
         if ($dsn->{t} && !$dsn->{D});
      if ( $dsn->{D} && !$dsn->{t} ) {
         die "You specified a database but not a table in $arg.  Are you "
            . "trying to sync only tables in the '$dsn->{D}' database?  "
            . "If so, use '--databases $dsn->{D}' instead.\n";
      }
      push @dsns, $dsn;
   }

   if ( !@dsns
        || (@dsns ==1 && !$o->get('replicate') && !$o->get('sync-to-master'))) {
      $o->save_error('At least one DSN is required, and at least two are '
         . 'required unless --sync-to-master or --replicate is specified');
   }

   if ( @dsns > 1 && $o->get('sync-to-master') && $o->get('replicate') ) {
      $o->save_error('--sync-to-master and --replicate require only one DSN ',
         ' but ', scalar @dsns, ' where given');
   }

   if ( $o->get('lock-and-rename') ) {
      if ( @dsns != 2 || !$dsns[0]->{t} || !$dsns[1]->{t} ) {
         $o->save_error("--lock-and-rename requires exactly two DSNs and they "
            . "must each specify a table.");
      }
   }

   if ( $o->get('bidirectional') ) {
      if ( $o->get('replicate') || $o->get('sync-to-master') ) {
         $o->save_error('--bidirectional does not work with '
            . '--replicate or --sync-to-master');
      }
      if ( @dsns < 2 ) {
         $o->save_error('--bidirectional requires at least two DSNs');
      }
      if ( !$o->get('conflict-column') || !$o->get('conflict-comparison') ) {
         $o->save_error('--bidirectional requires --conflict-column '
            . 'and --conflict-comparison');
      }
      my $cc  = $o->get('conflict-comparison');
      my $cmp = $o->read_para_after(__FILE__, qr/MAGIC_comparisons/);
      $cmp    =~ s/ //g;
      if ( $cc && $cc !~ m/$cmp/ ) {
         $o->save_error("--conflict-comparison must be one of $cmp");
      }
      if ( $cc && $cc =~ m/equals|matches/ && !$o->get('conflict-value') ) {
         $o->save_error("--conflict-comparison $cc requires --conflict-value")
      }

      # Override --algorithms becuase only TableSyncChunk works with
      # bidirectional syncing.
      $o->set('algorithms', 'Chunk');
      $o->set('buffer-to-client', 0);
   }

   if ( $o->get('explain-hosts') ) {
      foreach my $host ( @dsns ) {
         print "# DSN: ", $dp->as_string($host), "\n";
      }
      return 0;
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
   # Do the work.
   # ########################################################################
   my $q         = new Quoter();
   my $tp        = new TableParser( Quoter => $q );
   my $vp        = new VersionParser();
   my $ms        = new MasterSlave(VersionParser => $vp);
   my $du        = new MySQLDump( cache => 0 );
   my $rt        = new Retry();
   my $chunker   = new TableChunker( Quoter => $q, MySQLDump => $du );
   my $nibbler   = new TableNibbler( Quoter => $q, TableParser => $tp );
   my $checksum  = new TableChecksum( Quoter => $q, VersionParser => $vp );
   my $syncer    = new TableSyncer(
      Quoter        => $q,
      VersionParser => $vp,
      MasterSlave   => $ms,
      TableChecksum => $checksum,
      DSNParser     => $dp,
      Retry         => $rt,
   );
   my %modules = (
      OptionParser   => $o,
      DSNParser      => $dp,
      MySQLDump      => $du,
      TableParser    => $tp,
      Quoter         => $q,
      VersionParser  => $vp,
      TableChunker   => $chunker,
      TableNibbler   => $nibbler,
      TableChecksum  => $checksum,
      MasterSlave    => $ms,
      TableSyncer    => $syncer,
   );

   # Create the sync plugins.
   my $plugins     = [];
   my %have_plugin = get_plugins();
   foreach my $algo ( split(',', $o->get('algorithms')) ) {
      my $plugin_name = $have_plugin{lc $algo};
      if ( !$plugin_name ) {
         die "The $algo algorithm is not available.  Available algorithms: "
            . join(", ", sort keys %have_plugin);
      }
      MKDEBUG && _d('Loading', $plugin_name);
      my $plugin;
      eval {
         $plugin = $plugin_name->new(%modules);
      };
      die "Error loading $plugin_name for $algo algorithm: $EVAL_ERROR"
         if $EVAL_ERROR;
      push @$plugins, $plugin;
   }

   # Create callbacks for bidirectional syncing.  Currently, this only
   # works with TableSyncChunk, so that should be the only plugin because
   # --algorithms was overriden earlier.
   if ( $o->get('bidirectional') ) {
      set_bidirectional_callbacks(
         plugin => $plugins->[0],
         %modules,
      );
   }

   my $exit_status = 0; # 1: internal error, 2: tables differed, 3: both

   # dsn[0] is expected to be the master (i.e. the source).  So if
   # --sync-to-master, then dsn[0] is a slave.  Find its master and
   # make the master dsn[0] and the slave dsn[1].
   if ( $o->get('sync-to-master') ) {
      MKDEBUG && _d('Getting master of', $dp->as_string($dsns[0]));
      $dsns[0]->{dbh} = get_cxn($dsns[0], %modules);
      my $master = $ms->get_master_dsn($dsns[0]->{dbh}, $dsns[0], $dp)
         or die "Can't determine master of " . $dp->as_string($dsns[0]);
      unshift @dsns, $master;  # dsn[0]=master, dsn[1]=slave
      $dsns[0]->{dbh} = get_cxn($dsns[0], %modules);
      if ( $o->get('check-master') ) {
         $ms->is_master_of($dsns[0]->{dbh}, $dsns[1]->{dbh});
      }
   }

   my %args = (
      dsns    => \@dsns,
      plugins => $plugins,
      %modules,
   );

   if ( $o->get('dry-run') ) {
      print "# NOTE: --dry-run does not show if data needs to be synced because it\n"
         .  "#       does not access, compare or sync data.  --dry-run only shows\n"
         .  "#       the work that would be done.\n";

   }

   if ( $o->get('lock-and-rename') ) {
      $exit_status = lock_and_rename(%args);
   }
   elsif ( $dsns[0]->{t} ) {
      $exit_status = sync_one_table(%args);
   }
   elsif ( $o->get('replicate') ) {
      $exit_status = sync_via_replication(%args);
   }
   else {
      $exit_status = sync_all(%args);
   }

   return $exit_status;
}

# ############################################################################
# Subroutines
# ############################################################################

# Sub: lock_and_rename
#   Lock and rename a table.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   dsns         - Arrayref of DSNs
#   plugins      - Arrayref of TableSync* objects
#   OptionParser - <OptionParser> object
#   DSNParser    - <DSNParser> object
#   Quoter       - <Quoter> object
#
# Returns:
#   Exit status
sub lock_and_rename {
   my ( %args ) = @_;
   my @required_args = qw(dsns plugins OptionParser DSNParser Quoter
                          VersionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $dsns = $args{dsns};
   my $o    = $args{OptionParser};
   my $dp   = $args{DSNParser};
   my $q    = $args{Quoter};

   MKDEBUG && _d('Locking and syncing ONE TABLE with rename');
   my $src = {
      dsn      => $dsns->[0],
      dbh      => $dsns->[0]->{dbh} || get_cxn($dsns->[0], %args),
      misc_dbh => get_cxn($dsns->[0], %args),
      db       => $dsns->[0]->{D},
      tbl      => $dsns->[0]->{t},
   };
   my $dst = {
      dsn      => $dsns->[1],
      dbh      => $dsns->[1]->{dbh} || get_cxn($dsns->[1], %args),
      misc_dbh => get_cxn($dsns->[1], %args),
      db       => $dsns->[1]->{D},
      tbl      => $dsns->[1]->{t},
   };

   if ( $o->get('verbose') ) {
      print_header("# Lock and rename " . $dp->as_string($src->{dsn}));
   }

   # We don't use lock_server() here because it does the usual stuff wrt
   # waiting for slaves to catch up to master, etc, etc.
   my $src_db_tbl = $q->quote($src->{db}, $src->{tbl});
   my $dst_db_tbl = $q->quote($dst->{db}, $dst->{tbl});
   my $tmp_db_tbl = $q->quote($src->{db}, $src->{tbl} . "_tmp_$PID");
   my $sql = "LOCK TABLES $src_db_tbl WRITE";
   MKDEBUG && _d($sql);
   $src->{dbh}->do($sql);
   $sql = "LOCK TABLES $dst_db_tbl WRITE";
   MKDEBUG && _d($sql);
   $dst->{dbh}->do($sql);

   my $exit_status = sync_a_table(
      src  => $src,
      dst  => $dst,
      %args,
   );

   # Now rename the tables to swap them.
   $sql = "ALTER TABLE $src_db_tbl RENAME $tmp_db_tbl";
   MKDEBUG && _d($sql);
   $src->{dbh}->do($sql);
   $sql = "ALTER TABLE $dst_db_tbl RENAME $src_db_tbl";
   MKDEBUG && _d($sql);
   $dst->{dbh}->do($sql);
   $sql = "UNLOCK TABLES";
   MKDEBUG && _d($sql);
   $src->{dbh}->do($sql);
   $sql = "ALTER TABLE $tmp_db_tbl RENAME $dst_db_tbl";
   MKDEBUG && _d($sql);
   $src->{dbh}->do($sql);

   unlock_server(src => $src, dst => $dst, %args);

   disconnect($src, $dst);
   return $exit_status;
}

# Sub: sync_one_table
#   Sync one table between one source host and multiple destination hosts.
#   The first DSN in $args{dsns} specifies the source host, database (D),
#   and table (t).  The other DSNs are the destination hosts.  If a destination
#   DSN does not specify a database or table, the source database or table
#   are used as defaults.  Else, the destination-specific database or table
#   are used.  This allows you to sync tables with different names.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   dsns          - Arrayref of DSNs
#   plugins       - Arrayref of TableSync* objects
#   OptionParser  - <OptionParser> object
#   DSNParser     - <DSNParser> object
#   Quoter        - <Quoter> object
#   VersionParser - <VersionParser> object
#
# Returns:
#   Exit status
sub sync_one_table {
   my ( %args ) = @_;
   my @required_args = qw(dsns plugins OptionParser DSNParser Quoter
                          VersionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my @dsns = @{$args{dsns}};
   my $o    = $args{OptionParser};
   my $dp   = $args{DSNParser};

   MKDEBUG && _d('DSN has t part; syncing ONE TABLE between servers');
   my $src = {
      dsn      => $dsns[0],
      dbh      => $dsns[0]->{dbh} || get_cxn($dsns[0], %args),
      misc_dbh => get_cxn($dsns[0], %args),
      db       => $dsns[0]->{D},
      tbl      => $dsns[0]->{t},
   };

   my $exit_status = 0;
   foreach my $dsn ( @dsns[1 .. $#dsns] ) {
      my $dst = {
         dsn      => $dsn,
         dbh      => $dsn->{dbh} || get_cxn($dsn, %args),
         misc_dbh => get_cxn($dsn, %args),
         db       => $dsn->{D} || $src->{db},
         tbl      => $dsn->{t} || $src->{tbl},
      };

      if ( $o->get('verbose') ) {
         print_header("# Syncing " . $dp->as_string($dsn)
            . ($o->get('dry-run')
               ? ' in dry-run mode, without accessing or comparing data'
               : ''));
      }

      lock_server(src => $src, dst => $dst, %args);

      $exit_status |= sync_a_table(
         src   => $src,
         dst   => $dst,
         %args,
      );

      unlock_server(src => $src, dst => $dst, %args);
      disconnect($dst);
   }

   disconnect($src);
   return $exit_status;
}

# Sub: sync_via_replication
#   Sync multiple destination hosts to one source host via replication.
#   The first DSN in $args{dsns} specifies the source host.
#   If --sync-to-master is specified, then the source host is a master
#   and there is only one destination host which is its slave.
#   Else, destination hosts are auto-discovered with
#   <MasterSlave::recurse_to_slaves()>.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   dsns          - Arrayref of DSNs
#   plugins       - Arrayref of TableSync* objects
#   OptionParser  - <OptionParser> object
#   DSNParser     - <DSNParser> object
#   Quoter        - <Quoter> object
#   VersionParser - <VersionParser> object
#   TableChecksum - <TableChecksum> object
#   MasterSlave   - <MasterSlave> object
#
# Returns:
#   Exit status
#
# See Also:
#   <filter_diffs()>
sub sync_via_replication {
   my ( %args ) = @_;
   my @required_args = qw(dsns plugins OptionParser DSNParser Quoter
                          VersionParser TableChecksum MasterSlave);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $dsns     = $args{dsns};
   my $o        = $args{OptionParser};
   my $dp       = $args{DSNParser};
   my $q        = $args{Quoter};
   my $checksum = $args{TableChecksum};
   my $ms       = $args{MasterSlave};

   MKDEBUG && _d('Syncing via replication');
   my $src = {
      dsn      => $dsns->[0],
      dbh      => $dsns->[0]->{dbh} || get_cxn($dsns->[0], %args),
      misc_dbh => get_cxn($dsns->[0], %args),
      db       => undef,  # set later
      tbl      => undef,  # set later
   };

   # Filters for --databases and --tables.  We have to do these manually
   # since we don't use MySQLFind for --replicate.
   my $databases = $o->get('databases');
   my $tables    = $o->get('tables');

   my $exit_status = 0;

   # Connect to the master and treat it as the source, then find
   # differences on the slave and sync them.
   if ( $o->get('sync-to-master') ) {
      my $dst = {
         dsn      => $dsns->[1],
         dbh      => $dsns->[1]->{dbh} || get_cxn($dsns->[1], %args),
         misc_dbh => get_cxn($dsns->[1], %args),
         db       => undef,  # set later
         tbl      => undef,  # set later
      };

      # First, check that the master (source) has no discrepancies itself,
      # and ignore tables that do.
      my %skip_table;
      map { $skip_table{$_->{db}}->{$_->{tbl}}++ }
         $checksum->find_replication_differences(
            $src->{dbh}, $o->get('replicate'));

      # Now check the slave for differences and sync them if necessary.
      my @diffs =  filter_diffs(
         \%skip_table,
         $databases,
         $tables,
         $checksum->find_replication_differences(
            $dst->{dbh}, $o->get('replicate'))
      );

      if ( $o->get('verbose') ) {
         print_header("# Syncing via replication " . $dp->as_string($dst->{dsn})
            . ($o->get('dry-run') ?
               ' in dry-run mode, without accessing or comparing data' : ''));
      }

      if ( @diffs ) {
         lock_server(src => $src, dst => $dst, %args);

         foreach my $diff ( @diffs ) {
            $src->{db}  = $dst->{db}  = $diff->{db};
            $src->{tbl} = $dst->{tbl} = $diff->{tbl};

            $exit_status |= sync_a_table(
               src   => $src,
               dst   => $dst,
               where => $diff->{boundaries},
               %args,
            );
         }

         unlock_server(src => $src, dst => $dst, %args);
      }
      else {
         MKDEBUG && _d('No checksum differences');
      }

      disconnect($dst);
   } # sync-to-master

   # The DSN is the master.  Connect to each slave, find differences,
   # then sync them.
   else {
      my %skip_table;
      $ms->recurse_to_slaves(
         {  dbh        => $src->{dbh},
            dsn        => $src->{dsn},
            dsn_parser => $dp,
            recurse    => 1,
            callback   => sub {
               my ( $dsn, $dbh, $level, $parent ) = @_;
               my @diffs = $checksum
                  ->find_replication_differences($dbh, $o->get('replicate'));
               if ( !$level ) {
                  # This is the master; don't sync any tables that are wrong
                  # here, for obvious reasons.
                  map { $skip_table{$_->{db}}->{$_->{tbl}}++ } @diffs;
               }
               else {
                  # This is a slave.
                  @diffs = filter_diffs(
                     \%skip_table,
                     $databases,
                     $tables,
                     @diffs
                  );

                  if ( $o->get('verbose') ) {
                     print_header("# Syncing via replication "
                        . $dp->as_string($dsn)
                        . ($o->get('dry-run')
                           ? ' in dry-run mode, without '
                             . 'accessing or comparing data'
                           : ''));
                  }

                  if ( @diffs ) {
                     my $dst = {
                        dsn      => $dsn,
                        dbh      => $dbh,
                        misc_dbh => get_cxn($dsn, %args),
                        db       => undef,  # set later
                        tbl      => undef,  # set later
                     };

                     lock_server(src => $src, dst => $dst, %args);

                     foreach my $diff ( @diffs ) {
                        $src->{db}  = $dst->{db}  = $diff->{db};
                        $src->{tbl} = $dst->{tbl} = $diff->{tbl};

                        $exit_status |= sync_a_table(
                           src   => $src,
                           dst   => $dst,
                           where => $diff->{boundaries},
                           %args,
                        );
                     } 

                     unlock_server(src => $src, dst => $dst, %args);
                     disconnect($dst);
                  }
                  else {
                     MKDEBUG && _d('No checksum differences');
                  }
               }  # this is a slave

               return;
            },  # recurse_to_slaves() callback
            method => $o->get('recursion-method'),
         },
      );
   } # DSN is master

   disconnect($src);
   return $exit_status;
}

# Sub: sync_all
#   Sync every table between one source host and multiple destination hosts.
#   The first DSN in $args{dsns} specifies the source host. The other DSNs
#   are the destination hosts.  Unlike <sync_one_table>, the database and
#   table names must be the same on the source and destination hosts.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   dsns          - Arrayref of DSNs
#   plugins       - Arrayref of TableSync* objects
#   OptionParser  - <OptionParser> object
#   DSNParser     - <DSNParser> object
#   Quoter        - <Quoter> object
#   VersionParser - <VersionParser> object
#   TableParser   - <TableParser> object
#   MySQLDump     - <MySQLDump> object
#
# Returns:
#   Exit status
sub sync_all {
   my ( %args ) = @_;
   my @required_args = qw(dsns plugins OptionParser DSNParser Quoter
                          VersionParser TableParser MySQLDump);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my @dsns = @{$args{dsns}};
   my $o    = $args{OptionParser};
   my $dp   = $args{DSNParser};

   MKDEBUG && _d('Syncing all dbs and tbls');
   my $src = {
      dsn      => $dsns[0],
      dbh      => $dsns[0]->{dbh} || get_cxn($dsns[0], %args),
      misc_dbh => get_cxn($dsns[0], %args),
      db       => undef,  # set later
      tbl      => undef,  # set later
   };

   my $si = new SchemaIterator(
      Quoter => $args{Quoter},
   );
   $si->set_filter($si->make_filter($o));

   # Make a list of all dbs.tbls on the source.  It's more efficient this
   # way because it avoids open/closing a dbh for each tbl and dsn, unless
   # we pre-opened the dsn.  It would also cause confusing verbose output.
   my @dbs_tbls;
   my $next_db = $si->get_db_itr(dbh => $src->{dbh});
   while ( my $db = $next_db->() ) {
      MKDEBUG && _d('Getting tables from', $db);
      my $next_tbl = $si->get_tbl_itr(
         dbh   => $src->{dbh},
         db    => $db,
         views => 0,
      );
      while ( my $tbl = $next_tbl->() ) {
         MKDEBUG && _d('Got table', $tbl);
         push @dbs_tbls, { db => $db, tbl => $tbl };
      }
   }

   my $exit_status = 0;
   foreach my $dsn ( @dsns[1 .. $#dsns] ) {
      if ( $o->get('verbose') ) {
         print_header("# Syncing " . $dp->as_string($dsn)
            . ($o->get('dry-run')
               ? ' in dry-run mode, without accessing or comparing data' : ''));
      }

      my $dst = {
         dsn      => $dsn,
         dbh      => $dsn->{dbh} || get_cxn($dsn, %args),
         misc_dbh => get_cxn($dsn, %args),
         db       => undef,  # set later
         tbl      => undef,  # set later
      };

      lock_server(src => $src, dst => $dst, %args);

      foreach my $db_tbl ( @dbs_tbls ) {
         $src->{db}  = $dst->{db}  = $db_tbl->{db};
         $src->{tbl} = $dst->{tbl} = $db_tbl->{tbl};

         $exit_status |= sync_a_table(
            src => $src,
            dst => $dst,
            %args,
         );
      }

      unlock_server(src => $src, dst => $dst, %args);
      disconnect($dst);
   }

   disconnect($src);
   return $exit_status;
}

# Sub: lock_server
#   Lock a host with FLUSH TABLES WITH READ LOCK.  This implements
#   --lock 3 by calling <TableSyncer::lock_and_wait()>.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   src           - Hashref with source host information
#   dst           - Hashref with destination host information
#   OptionParser  - <OptionParser> object
#   DSNParser     - <DSNParser> object
#   TableSyncer   - <TableSyncer> object
sub lock_server {
   my ( %args ) = @_;
   foreach my $arg ( qw(src dst OptionParser DSNParser TableSyncer) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $o = $args{OptionParser};

   return unless $o->get('lock') && $o->get('lock') == 3;

   eval {
      $args{TableSyncer}->lock_and_wait(
         %args,
         lock         => 3,
         lock_level   => 3,
         replicate    => $o->get('replicate'),
         timeout_ok   => $o->get('timeout-ok'),
         transaction  => $o->get('transaction'),
         wait         => $o->get('wait'),
      );
   };
   if ( $EVAL_ERROR ) {
      die "Failed to lock server: $EVAL_ERROR";
   }
   return;
}

# Sub: unlock_server
#   Unlock a host with UNLOCK TABLES.  This implements
#   --lock 3 by calling <TableSyncer::unlock()>.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   src           - Hashref with source host information
#   dst           - Hashref with destination host information
#   OptionParser  - <OptionParser> object
#   DSNParser     - <DSNParser> object
#   TableSyncer   - <TableSyncer> object
sub unlock_server {
   my ( %args ) = @_;
   my @required_args = qw(src dst OptionParser DSNParser TableSyncer);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($src, $dst, $o) = @args{@required_args};

   return unless $o->get('lock') && $o->get('lock') == 3;

   eval {
      # Open connections as needed.
      $src->{dbh}      ||= get_cxn($src->{dsn}, %args);
      $dst->{dbh}      ||= get_cxn($dst->{dsn}, %args);
      $src->{misc_dbh} ||= get_cxn($src->{dsn}, %args);
      $args{TableSyncer}->unlock(
         src_dbh      => $src->{dbh},
         src_db       => '',
         src_tbl      => '',
         dst_dbh      => $dst->{dbh},
         dst_db       => '',
         dst_tbl      => '',
         misc_dbh     => $src->{misc_dbh},
         replicate    => $o->get('replicate')   || 0,
         timeout_ok   => $o->get('timeout-ok')  || 0,
         transaction  => $o->get('transaction') || 0,
         wait         => $o->get('wait')        || 0,
         lock         => 3,
         lock_level   => 3,
      );
   };
   if ( $EVAL_ERROR ) {
      die "Failed to unlock server: $EVAL_ERROR";
   }
   return;
}

# Sub: sync_a_table
#   Sync the destination host table to the source host table.  This sub
#   is not called directly but indirectly via the other sync_* subs.
#   In turn, this sub calls <TableSyncer::sync_table()> which actually
#   does the sync work.  Calling sync_table() requires a fair amount of
#   prep work that this sub does/simplifies.  New <RowDiff> and <ChangeHandler>
#   objects are created, so those packages need to be available.
#
# Parameters:
#   $args - Arguments
#
# Required Arguments:
#   src           - Hashref with source host information
#   dst           - Hashref with destination host information
#   plugins       - Arrayref of TableSync* objects
#   OptionParser  - <OptionParser> object
#   Quoter        - <Quoter> object
#   TableParser   - <TableParser> object
#   MySQLDump     - <MySQLDump> object
#   TableSyncer   - <TableSyncer> object
#
# Returns:
#   Exit status
sub sync_a_table {
   my ( %args ) = @_;
   my @required_args = qw(src dst plugins OptionParser Quoter TableParser
                          MySQLDump TableSyncer);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($src, $dst, undef, $o, $q, $tp, $du, $syncer) = @args{@required_args};

   my ($start_ts, $end_ts);
   my $exit_status = 0; 
   my %status;
   eval {
      $start_ts = get_server_time($src->{dbh}) if $o->get('verbose');

      # This will either die if there's a problem or return the tbl struct.
      my $tbl_struct = ok_to_sync($src, $dst, %args);

      # If the table is InnoDB, prefer to sync it with transactions, unless
      # the user explicitly said not to.
      my $use_txn = $o->got('transaction')            ? $o->get('transaction')
                  : $tbl_struct->{engine} eq 'InnoDB' ? 1
                  :                                     0;

      # Turn off AutoCommit if we're using transactions.
      $src->{dbh}->{AutoCommit}      = !$use_txn;
      $src->{misc_dbh}->{AutoCommit} = !$use_txn;
      $dst->{dbh}->{AutoCommit}      = !$use_txn;
      $dst->{misc_dbh}->{AutoCommit} = !$use_txn;

      # Determine which columns to compare.
      my $ignore_columns  = $o->get('ignore-columns');
      my @compare_columns = grep {
         !$ignore_columns->{lc $_};
      } @{$o->get('columns') || $tbl_struct->{cols}};

      # Make sure conflict col is in compare cols else conflicting
      # rows won't have the col for --conflict-comparison.
      if ( my $conflict_col = $o->get('conflict-column') ) {
         push @compare_columns, $conflict_col
            unless grep { $_ eq $conflict_col } @compare_columns;
      }

      # --print --verbose --verbose is the magic formula for having
      # all src/dst sql printed so we can see the chunk/row sql.
      my $callback;
      if ( $o->get('print') && $o->get('verbose') >= 2 ) {
         $callback = \&print_sql;
      }

      # get_change_dbh() may die if, for example, the destination is
      # not a slave.  Perhaps its work should be part of can_sync()?
      my $change_dbh = get_change_dbh(tbl_struct => $tbl_struct, %args);
      my $actions    = make_action_subs(change_dbh => $change_dbh, %args);

      my $rd = new RowDiff(dbh => $src->{misc_dbh});
      my $ch = new ChangeHandler(
         left_db    => $src->{db},
         left_tbl   => $src->{tbl},
         right_db   => $dst->{db},
         right_tbl  => $dst->{tbl}, 
         tbl_struct => $tbl_struct,
         hex_blob   => $o->get('hex-blob'),
         queue      => $o->get('buffer-to-client') ? 1 : 0,
         replace    => $o->get('replace')
                       || $o->get('replicate')
                       || $o->get('sync-to-master')
                       || 0,
         actions    => $actions,
         Quoter     => $args{Quoter},
      );

      %status = $syncer->sync_table(
         %args,
         tbl_struct        => $tbl_struct,
         cols              => \@compare_columns,
         chunk_size        => $o->get('chunk-size'),
         RowDiff           => $rd,
         ChangeHandler     => $ch,
         transaction       => $use_txn,
         callback          => $callback,
         where             => $args{where} || $o->get('where'),
         bidirectional     => $o->get('bidirectional'),
         buffer_in_mysql   => $o->get('buffer-in-mysql'),
         buffer_to_client  => $o->get('buffer-to-client'),
         changing_src      => $o->get('replicate')
                              || $o->get('sync-to-master')
                              || $o->get('bidirectional')
                              || 0,
         float_precision   => $o->get('float-precision'),
         index_hint        => $o->get('index-hint'),
         chunk_index       => $o->get('chunk-index'),
         chunk_col         => $o->get('chunk-column'),
         zero_chunk        => $o->get('zero-chunk'),
         lock              => $o->get('lock'),
         replace           => $o->get('replace'),
         replicate         => $o->get('replicate'),
         dry_run           => $o->get('dry-run'),
         timeout_ok        => $o->get('timeout-ok'),
         trim              => $o->get('trim'),
         wait              => $o->get('wait'),
         function          => $o->get('function'),
      );

      if ( sum(@status{@ChangeHandler::ACTIONS}) ) {
         $exit_status |= 2;
      }
   };

   if ( $EVAL_ERROR ) {
      print_err($EVAL_ERROR, $dst->{db}, $dst->{tbl}, $dst->{dsn}->{h});
      $exit_status |= 1;
   }

   # Print this last so that the exit status is its final result.
   if ( $o->get('verbose') ) {
      $end_ts = get_server_time($src->{dbh}) || "";
      print_results(
         map { $_ || '0' } @status{@ChangeHandler::ACTIONS, 'ALGORITHM'},
         $start_ts, $end_ts,
         $exit_status, $src->{db}, $src->{tbl});
   }

   return $exit_status;
}

# Sub: get_change_dbh
#   Return the dbh to write to for syncing changes.  Write statements
#   are executed on the "change dbh".  If --sync-to-master or --replicate
#   is specified, the source (master) dbh is the "change dbh".  This means
#   changes replicate to all slaves.  Else, the destination dbh is the
#   change dbh.  This is the case when two independent servers (or perhaps
#   one table on the same server) are synced.  This sub implements
#   --[no]check-slave because writing to a slave is generally a bad thing.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   src           - Hashref with source host information
#   dst           - Hashref with destination host information
#   tbl_struct    - Hashref returned by <TableParser::parse()>
#   OptionParser  - <OptionParser> object
#   DSNParser     - <DSNParser> object
#   MasterSlave   - <MasterSlave> object
#
# Returns:
#   Either $args{src}->{dbh} or $args{dst}->{dbh} if no checks fail.
#
# See Also:
#   <make_action_subs()>
sub get_change_dbh {
   my ( %args ) = @_;
   my @required_args = qw(src dst tbl_struct OptionParser DSNParser
                          MasterSlave);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($src, $dst, $tbl_struct, $o, $dp, $ms) = @args{@required_args};

   my $change_dbh = $dst->{dbh};  # The default case: making changes on dst.

   if ( $o->get('sync-to-master') || $o->get('replicate') ) {
      # Is it possible to make changes on the master (i.e. the source)?
      # Only if REPLACE will work.
      my $can_replace = grep { $_->{is_unique} } values %{$tbl_struct->{keys}};
      MKDEBUG && _d("This table's replace-ability:", $can_replace);
      die "Can't make changes on the master because no unique index exists"
         unless $can_replace;
      $change_dbh = $src->{dbh};  # The alternate case.
      MKDEBUG && _d('Will make changes on source', $change_dbh);
   }
   elsif ( $o->get('check-slave') ) {
      # Is it safe to change data on the destination?  Only if it's *not*
      # a slave.  We don't change tables on slaves directly.  If we are
      # forced to change data on a slave, we require either that 1) binary
      # logging is disabled, or 2) the check is bypassed.  By the way, just
      # because the server is a slave doesn't mean it's not also the master
      # of the master (master-master replication).
      my $slave_status = $ms->get_slave_status($dst->{dbh});
      my (undef, $log_bin) = $dst->{dbh}->selectrow_array(
         'SHOW VARIABLES LIKE "log_bin"');
      my ($sql_log_bin) = $dst->{dbh}->selectrow_array(
         'SELECT @@SQL_LOG_BIN');
      MKDEBUG && _d('Variables on destination:',
         'log_bin=', (defined $log_bin ? $log_bin : 'NULL'),
         ' @@SQL_LOG_BIN=', (defined $sql_log_bin ? $sql_log_bin : 'NULL'));
      if ( $slave_status && $sql_log_bin && ($log_bin || 'OFF') eq 'ON' ) {
         die "Can't make changes on ", $dp->as_string($dst->{dsn}),
            " because it's a slave.  See the documentation section",
            " 'REPLICATION SAFETY' for solutions to this problem.";
      }
      MKDEBUG && _d('Will make changes on destination', $change_dbh);
   }

   return $change_dbh;
}

# Sub: make_action_subs
#   Make callbacks for <ChangeHandler::new()> actions argument.  This
#   sub implements --print and --execute.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   change_dbh   - dbh returned by <get_change_dbh>
#   OptionParser - <OptionParser> object
#
# Returns:
#   Arrayref of callbacks (coderefs)
sub make_action_subs {
   my ( %args ) = @_;
   my @required_args = qw(change_dbh OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($change_dbh, $o) = @args{@required_args};

   my @actions;
   if ( $o->get('execute') ) {
      push @actions, sub {
         my ( $sql, $dbh ) = @_;
         # Use $dbh if given.  It's from a bidirectional callback.
         $dbh ||= $change_dbh;
         MKDEBUG && _d('Execute on dbh', $dbh, $sql);
         $dbh->do($sql);
      };
   }
   if ( $o->get('print') ) {
      # Print AFTER executing, so the print isn't misleading in case of an
      # index violation etc that doesn't actually get executed.
      push @actions, sub { 
         my ( $sql, $dbh ) = @_;
         # Append /*host:port*/ to the sql, if possible, so the user
         # can see on which host it was/would be ran.
         my $dsn = $dsn_for{$dbh} if $dbh;
         if ( $dsn ) {
            my $h = $dsn->{h} || $dsn->{S} || '';
            my $p = $dsn->{P} || '';
            $sql  = "/*$h" . ($p ? ":$p" : '') . "*/ $sql";
         }
         print($sql, ";\n") or die "Cannot print: $OS_ERROR";
      };
   }

   return \@actions;
}


# Sub: print_err
#   Try to extract the MySQL error message and print it.
#
# Parameters:
#   $msg      - Error message
#   $database - Database name being synced when error occurred
#   $table    - Table name being synced when error occurred
#   $host     - Host name error occurred on
sub print_err {
   my ( $msg, $database, $table, $host ) = @_;
   return if !defined $msg;
   $msg =~ s/^.*?failed: (.*?) at \S+ line (\d+).*$/$1 at line $2/s;
   $msg =~ s/\s+/ /g;
   if ( $database && $table ) {
      $msg .= " while doing $database.$table";
   }
   if ( $host ) {
      $msg .= " on $host";
   }
   print STDERR $msg, "\n";
}

# Sub: get_cxn
#   Connect to host specified by DSN.
#
# Parameters:
#   $dsn  - Host DSN
#   %args - Arguments
#
# Required Arguments:
#   OptionaParser - <OptionParser> object
#   DSNParser     - <DSNParser> object
#
# Returns:
#   dbh
sub get_cxn {
   my ( $dsn, %args ) = @_;
   my @required_args = qw(OptionParser DSNParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($o, $dp) = @args{@required_args};

   if ( !$dsn->{p} && $o->get('ask-pass') ) {
      # Just "F=file" is a valid DSN but fill_in_dsn() can't help us
      # because we haven't connected yet.  If h is not specified,
      # then user is relying on F or .my.cnf/system defaults.
      # http://code.google.com/p/maatkit/issues/detail?id=947
      my $host  = $dsn->{h} ? $dsn->{h}
                :             "DSN ". $dp->as_string($dsn);
      $dsn->{p} = OptionParser::prompt_noecho("Enter password for $host: ");
   }
   my $dbh = $dp->get_dbh(
      $dp->get_cxn_params($dsn, {})  # get_cxn_params needs the 2nd arg
   );

   my $sql;
   if ( !$o->get('bin-log') ) {
      $sql = "/*!32316 SET SQL_LOG_BIN=0 */";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   }
   if ( !$o->get('unique-checks') ) {
      $sql = "/*!40014 SET UNIQUE_CHECKS=0 */";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   }
   if ( !$o->get('foreign-key-checks') ) {
      $sql = "/*!40014 SET FOREIGN_KEY_CHECKS=0 */";
      MKDEBUG && _d($dbh, $sql);
      $dbh->do($sql);
   }

   # Disable auto-increment on zero (bug #1919897).
   $sql = '/*!40101 SET @@SQL_MODE := CONCAT(@@SQL_MODE, '
        . '",NO_AUTO_VALUE_ON_ZERO")*/';
   MKDEBUG && _d($dbh, $sql);
   $dbh->do($sql);
   
   # Ensure statement-based replication.
   # http://code.google.com/p/maatkit/issues/detail?id=95
   $sql = '/*!50105 SET @@binlog_format="STATEMENT"*/';
   MKDEBUG && _d($dbh, $sql);
   $dbh->do($sql);

   if ( $o->get('transaction') ) {
      my $sql = "SET SESSION TRANSACTION ISOLATION LEVEL REPEATABLE READ";
      eval {
         MKDEBUG && _d($dbh, $sql);
         $dbh->do($sql);
      };
      die "Failed to $sql: $EVAL_ERROR" if $EVAL_ERROR;
   }

   $dsn_for{$dbh} = $dsn;

   MKDEBUG && _d('Opened dbh', $dbh);
   return $dbh;
}


# Sub: ok_to_sync
#   Check that the destination host table can be synced to the source host
#   table.  All sorts of sanity checks are performed to help ensure that
#   syncing the table won't cause problems in <sync_a_table()> or
#   <TableSyncer::sync_table()>.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   src           - Hashref with source host information
#   dst           - Hashref with destination host information
#   DSNParser     - <DSNParser> object
#   Quoter        - <Quoter> object
#   VersionParser - <VersionParser> object
#   TableParser   - <TableParser> object
#   MySQLDump     - <MySQLDump> object
#   TableSyncer   - <TableSyncer> object
#   OptionParser  - <OptionParser> object
#
# Returns:
#   Table structure (from <TableParser::parse()>) if ok to sync, else it dies.
sub ok_to_sync {
   my ( %args ) = @_;
   my @required_args = qw(src dst DSNParser Quoter VersionParser TableParser
                          MySQLDump TableSyncer OptionParser);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($src, $dst, $dp, $q, $vp, $tp, $du, $syncer, $o) = @args{@required_args};

   # First things first: check that the src and dst dbs and tbls exist.
   # This can fail in cases like h=host,D=bad,t=also_bad (i.e. simple
   # user error).  It can also fail when syncing all dbs/tbls with sync_all()
   # because the dst db/tbl is assumed to be the same as the src but
   # this isn't always the case.
   my $src_tbl_ddl;
   eval {
      # FYI: get_create_table() does USE db but doesn't eval it.
      $src->{dbh}->do("USE `$src->{db}`");
      $src_tbl_ddl = $du->get_create_table($src->{dbh}, $q,
         $src->{db}, $src->{tbl});
   };
   die $EVAL_ERROR if $EVAL_ERROR;

   my $dst_tbl_ddl;
   eval {
      # FYI: get_create_table() does USE db but doesn't eval it.
      $dst->{dbh}->do("USE `$dst->{db}`");
      $dst_tbl_ddl = $du->get_create_table($dst->{dbh}, $q,
         $dst->{db}, $dst->{tbl});
   };
   die $EVAL_ERROR if $EVAL_ERROR;

   # This doesn't work at the moment when syncing different table names.
   # Check that src.db.tbl has the exact same schema as dst.db.tbl.
   # if ( $o->get('check-schema') && ($src_tbl_ddl ne $dst_tbl_ddl) ) {
   #   die "Source and destination tables have different schemas";
   # }
   my $tbl_struct = $tp->parse($src_tbl_ddl);

   # Check that the user has all the necessary privs on the tbls.
   if ( $o->get('check-privileges') ) {
      MKDEBUG && _d('Checking privileges');
      if ( !$syncer->have_all_privs($src->{dbh}, $src->{db}, $src->{tbl}) ) {
         my $user = get_current_user($src->{dbh}) || "";
         die "User $user does not have all necessary privileges on ",
            $q->quote($src->{db}, $src->{tbl});
      }
      if ( !$syncer->have_all_privs($dst->{dbh}, $dst->{db}, $dst->{tbl}) ) {
         my $user = get_current_user($dst->{dbh}) || "";
         die "User $user does not have all necessary privileges on ",
            $q->quote($dst->{db}, $dst->{tbl});
      }
   }

   # Check that no triggers are defined on the dst tbl.
   if ( $o->get('check-triggers') ) {
      MKDEBUG && _d('Checking for triggers');
      if ( !defined $dst->{supports_triggers} ) {
         $dst->{supports_triggers} = $vp->version_ge($dst->{dbh}, '5.0.2');
      }
      if ( $dst->{supports_triggers}
           && $du->get_triggers($dst->{dbh}, $q, $dst->{db}, $dst->{tbl}) ) {
         die "Triggers are defined on the table";
      }
      else {
         MKDEBUG && _d('Destination does not support triggers',
            $dp->as_string($dst->{dsn}));
      }
   }

   return $tbl_struct;
}

# Sub: filter_diffs
#   Filter different slave tables according to the various schema object
#   filters.  This sub is called in <sync_via_replication()> to implement
#   schema object filters like --databases and --tables.
#
# Parameters:
#   $skip_table - Hashref of databases and tables to skip
#   $databases  - Hashref of databases to skip
#   $tables     - Hashref of tables to skip
#   @diffs      - Array of hashrefs, one for each different slave table
#
# Returns:
#   Array of different slave tables that pass the filters
sub filter_diffs {
   my ( $skip_table, $databases, $tables, @diffs ) = @_;
   return grep {
      !$skip_table->{$_->{db}}->{$_->{tbl}}
      && (!$databases || $databases->{$_->{db}})
      && (!$tables || ($tables->{$_->{tbl}} || $tables->{"$_->{db}.$_->{tbl}"}))
   } @diffs;
}


# Sub: disconnect
#   Disconnect host dbhs created by <get_cxn()>.  To make sure all dbh
#   are closed, mk-table-sync keeps track of the dbh it opens and this
#   sub helps keep track of the dbh that are closed.
#
# Parameters:
#   @hosts - Array of hashrefs with host information, one for each host 
sub disconnect {
   my ( @hosts ) = @_;
   foreach my $host ( @hosts ) {
      foreach my $thing ( qw(dbh misc_dbh) ) {
         my $dbh = $host->{$thing};
         next unless $dbh;
         delete $dsn_for{$dbh};
         $dbh->commit() unless $dbh->{AutoCommit};
         $dbh->disconnect();
         MKDEBUG && _d('Disconnected dbh', $dbh);
      }
   }
   return;
}

# Sub: print_sql
#   Callback for <TableSyncer::sync_table()> if --print --verbose --verbose
#   is specified.  The callback simply prints the SQL statements passed to
#   it by sync_table().  They're usually (always?) identical statements.
#
# Parameters:
#   $src_sql - SQL statement to be executed on the sourch host
#   $dst_sql - SQL statement to be executed on the destination host
sub print_sql {
   my ( $src_sql, $dst_sql ) = @_;
   print "# $src_sql\n" if $src_sql;
   print "# $dst_sql\n" if $dst_sql;
   return;
}

use constant UPDATE_LEFT      => -1;
use constant UPDATE_RIGHT     =>  1;
use constant UPDATE_NEITHER   =>  0;  # neither value equals/matches
use constant FAILED_THRESHOLD =>  2;  # failed to exceed threshold

# Sub: cmd_conflict_col
#   Compare --conflict-column values for --bidirectional.  This sub is
#   used as a callback in <set_bidirectional_callbacks()>.
#
# Parameters:
#   $left_val  - Column value from left (usually the source host)
#   $right_val - Column value from right (usually the destination host)
#   $cmp       - Type of conflict comparison, --conflict-comparison
#   $val       - Value for certain types of comparisons, --conflict-value
#   $thr       - Threshold for certain types of comparisons,
#                --conflict-threshold
#
# Returns:
#   One of the constants above, UPDATE_* or FAILED_THRESHOLD
sub cmp_conflict_col {
   my ( $left_val, $right_val, $cmp, $val, $thr ) = @_;
   MKDEBUG && _d('Compare', @_);
   my $res;
   if ( $cmp eq 'newest' || $cmp eq 'oldest' ) {
      $res = $cmp eq 'newest' ? ($left_val  || '') cmp ($right_val || '')
           :                    ($right_val || '') cmp ($left_val  || '');

      if ( $thr ) {
         $thr     = time_to_secs($thr);
         my $lts  = any_unix_timestamp($left_val);
         my $rts  = any_unix_timestamp($right_val);
         my $diff = abs($lts - $rts);
         MKDEBUG && _d('Check threshold, lts rts thr abs-diff:',
            $lts, $rts, $thr, $diff);
         if ( $diff < $thr ) {
            MKDEBUG && _d("Failed threshold");
            return FAILED_THRESHOLD;
         }
      }
   }
   elsif ( $cmp eq 'greatest' || $cmp eq 'least' ) {
      $res = $cmp eq 'greatest' ? (($left_val ||0) > ($right_val ||0) ? 1 : -1)
           :                      (($left_val ||0) < ($right_val ||0) ? 1 : -1);
      $res = 0 if ($left_val || 0) == ($right_val || 0);
      if ( $thr ) {
         my $diff = abs($left_val - $right_val);
         MKDEBUG && _d('Check threshold, abs-diff:', $diff);
         if ( $diff < $thr ) {
            MKDEBUG && _d("Failed threshold");
            return FAILED_THRESHOLD;
         }
      }
   }
   elsif ( $cmp eq 'equals' ) {
      $res = ($left_val  || '') eq $val ?  1
           : ($right_val || '') eq $val ? -1
           :                               0;
   }
   elsif ( $cmp eq 'matches' ) {
      $res = ($left_val  || '') =~ m/$val/ ?  1
           : ($right_val || '') =~ m/$val/ ? -1
           :                                  0;
   }
   else {
      # Should happen; caller should have verified this.
      die "Invalid comparison: $cmp";
   }

   return $res;
}

# Sub: set_bidirectional_callbacks
#   Set syncer plugin callbacks for --bidirectional.
#
# Parameters:
#   %args - Arguments
#
# Required Arguments:
#   plugin       - TableSync* object
#   OptionParser - <OptionParser> object
sub set_bidirectional_callbacks {
   my ( %args ) = @_;
   foreach my $arg ( qw(plugin OptionParser) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $o      = $args{OptionParser};
   my $plugin = $args{plugin};

   my $col = $o->get('conflict-column');
   my $cmp = $o->get('conflict-comparison');
   my $val = $o->get('conflict-value');
   my $thr = $o->get('conflict-threshold');

   # plugin and syncer are actually the same module.  For clarity we
   # name them differently.

   $plugin->set_callback('same_row', sub {
      my ( %args ) = @_;
      my ($lr, $rr, $syncer) = @args{qw(lr rr syncer)};
      my $ch = $syncer->{ChangeHandler};
      my $action = 'UPDATE';
      my $change_dbh;
      my $auth_row;
      my $err;

      my $left_val  = $lr->{$col} || '';
      my $right_val = $rr->{$col} || '';
      MKDEBUG && _d('left',  $col, 'value:', $left_val);
      MKDEBUG && _d('right', $col, 'value:', $right_val);

      my $res = cmp_conflict_col($left_val, $right_val, $cmp, $val, $thr);
      if ( $res == UPDATE_LEFT ) {
         MKDEBUG && _d("right dbh $args{right_dbh} $cmp; "
            . "update left dbh $args{left_dbh}");
         $ch->set_src('right', $args{right_dbh});
         $auth_row   = $args{rr};
         $change_dbh = $args{left_dbh};
      }
      elsif ( $res == UPDATE_RIGHT ) {
         MKDEBUG && _d("left dbh $args{left_dbh} $cmp; "
            . "update right dbh $args{right_dbh}");
         $ch->set_src('left', $args{left_dbh});
         $auth_row   = $args{lr};
         $change_dbh = $args{right_dbh};
      }
      elsif ( $res == UPDATE_NEITHER ) {
         if ( $cmp eq 'equals' || $cmp eq 'matches' ) {
            $err = "neither `$col` value $cmp $val";
         }
         else {
            $err = "`$col` values are the same"
         }
      }
      elsif ( $res == FAILED_THRESHOLD ) {
         $err = "`$col` values do not differ by the threhold, $thr."
      }
      else {
         # Shouldn't happen.
         die "cmp_conflict_col() returned an invalid result: $res."
      }

      if ( $err ) {
         $action   = undef;  # skip change in case we just warn
         my $where = $ch->make_where_clause($lr, $syncer->key_cols());
         $err      = "# Cannot resolve conflict WHERE $where: $err\n";

         # die here is caught in sync_a_table().  We're deeply nested:
         # sync_a_table > sync_table > compare_sets > syncer > here
         $o->get('conflict-error') eq 'warn' ? warn $err : die $err;
      }

      return $action, $auth_row, $change_dbh;
   });

   $plugin->set_callback('not_in_right', sub {
      my ( %args ) = @_;
      $args{syncer}->{ChangeHandler}->set_src('left', $args{left_dbh});
      return 'INSERT', $args{lr}, $args{right_dbh};
   });

   $plugin->set_callback('not_in_left', sub {
      my ( %args ) = @_;
      $args{syncer}->{ChangeHandler}->set_src('right', $args{right_dbh});
      return 'INSERT', $args{rr}, $args{left_dbh};
   });

   return;
}

# Sub: get_plugins
#   Get internal TableSync* plugins.
#
# Returns:
#   Hash of available algoritms and the plugin/module names that
#   implement them, like "chunk => TableSyncChunk".
sub get_plugins {
   my ( %args ) = @_;
   
   my $file = __FILE__;
   open my $fh, "<", $file or die "Cannot open $file: $OS_ERROR";
   my $contents = do { local $/ = undef; <$fh> };
   close $fh;

   my %local_plugins = map {
      my $package = $_;
      my ($module, $algo) = $package =~ m/(TableSync(\w+))/;
      lc $algo => $module;
   } $contents =~ m/^package TableSync\w{3,};/gm;

   return %local_plugins;
}

{
# DELETE REPLACE INSERT UPDATE ALGORITHM START END EXIT DATABASE.TABLE
my $hdr = "# %6s %7s %6s %6s %-9s %-8s %-8s %-4s %s.%s\n";

sub print_header {
   my ( $title ) = @_;
   print "$title\n" if $title;
   printf $hdr, @ChangeHandler::ACTIONS,
      qw(ALGORITHM START END EXIT DATABASE TABLE);
   return;
}

sub print_results {
   my ( @values ) = @_;
   printf $hdr, @values;
   return;
}
}

# Sub: get_server_time
#  Return HH:MM:SS of SELECT NOW() from the server.
#
# Parameters:
#   $dbh - dbh
sub get_server_time {
   my ( $dbh ) = @_;
   return unless $dbh;
   my $now;
   eval {
      my $sql = "SELECT NOW()";
      MKDEBUG && _d($dbh, $sql);
      ($now) = $dbh->selectrow_array($sql);
      MKDEBUG && _d("Server time:", $now);
      $now =~ s/^\S+\s+//;
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d("Failed to get server time:", $EVAL_ERROR);
   }
   return $now
}

sub get_current_user {
   my ( $dbh ) = @_;
   return unless $dbh;

   my $user;
   eval {
      my $sql = "SELECT CURRENT_USER()";
      MKDEBUG && _d($dbh, $sql);
      ($user) = $dbh->selectrow_array($sql);
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d("Error getting current user:", $EVAL_ERROR);
   }

   return $user;
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

mk-table-sync - Synchronize MySQL table data efficiently.

=head1 SYNOPSIS

Usage: mk-table-sync [OPTION...] DSN [DSN...]

mk-table-sync synchronizes data efficiently between MySQL tables.

This tool changes data, so for maximum safety, you should back up your data
before you use it.  When synchronizing a server that is a replication slave with
the --replicate or --sync-to-master methods, it B<always> makes the changes on
the replication master, B<never> the replication slave directly.  This is in
general the only safe way to bring a replica back in sync with its master;
changes to the replica are usually the source of the problems in the first
place.  However, the changes it makes on the master should be no-op changes that
set the data to their current values, and actually affect only the replica.
Please read the detailed documentation that follows to learn more about this.

Sync db.tbl on host1 to host2:

  mk-table-sync --execute h=host1,D=db,t=tbl h=host2

Sync all tables on host1 to host2 and host3:

  mk-table-sync --execute host1 host2 host3

Make slave1 have the same data as its replication master:

  mk-table-sync --execute --sync-to-master slave1

Resolve differences that L<mk-table-checksum> found on all slaves of master1:

  mk-table-sync --execute --replicate test.checksum master1

Same as above but only resolve differences on slave1:

  mk-table-sync --execute --replicate test.checksum \
    --sync-to-master slave1

Sync master2 in a master-master replication configuration, where master2's copy
of db.tbl is known or suspected to be incorrect:

  mk-table-sync --execute --sync-to-master h=master2,D=db,t=tbl

Note that in the master-master configuration, the following will NOT do what you
want, because it will make changes directly on master2, which will then flow
through replication and change master1's data:

  # Don't do this in a master-master setup!
  mk-table-sync --execute h=master1,D=db,t=tbl master2

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

With great power comes great responsibility!  This tool changes data, so it is a
good idea to back up your data.  It is also very powerful, which means it is
very complex, so you should run it with the L<"--dry-run"> option to see what it
will do, until you're familiar with its operation.  If you want to see which
rows are different, without changing any data, use L<"--print"> instead of
L<"--execute">.  

Be careful when using mk-table-sync in any master-master setup.  Master-master
replication is inherently tricky, and it's easy to make mistakes.  You need to
be sure you're using the tool correctly for master-master replication.  See the
L<"SYNOPSIS"> for the overview of the correct usage.

Also be careful with tables that have foreign key constraints with C<ON DELETE>
or C<ON UPDATE> definitions because these might cause unintended changes on the
child tables.

In general, this tool is best suited when your tables have a primary key or
unique index.  Although it can synchronize data in tables lacking a primary key
or unique index, it might be best to synchronize that data by another means.

At the time of this release, there is a potential bug using
L<"--lock-and-rename"> with MySQL 5.1, a bug detecting certain differences,
a bug using ROUND() across different platforms, and a bug mixing collations.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-table-sync>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

mk-table-sync does one-way and bidirectional synchronization of table data.
It does B<not> synchronize table structures, indexes, or any other schema
objects.  The following describes one-way synchronization.
L<"BIDIRECTIONAL SYNCING"> is described later.

This tool is complex and functions in several different ways.  To use it
safely and effectively, you should understand three things: the purpose
of L<"--replicate">, finding differences, and specifying hosts.  These
three concepts are closely related and determine how the tool will run. 
The following is the abbreviated logic:

   if DSN has a t part, sync only that table:
      if 1 DSN:
         if --sync-to-master:
            The DSN is a slave.  Connect to its master and sync.
      if more than 1 DSN:
         The first DSN is the source.  Sync each DSN in turn.
   else if --replicate:
      if --sync-to-master:
         The DSN is a slave.  Connect to its master, find records
         of differences, and fix.
      else:
         The DSN is the master.  Find slaves and connect to each,
         find records of differences, and fix.
   else:
      if only 1 DSN and --sync-to-master:
         The DSN is a slave.  Connect to its master, find tables and
         filter with --databases etc, and sync each table to the master.
      else:
         find tables, filtering with --databases etc, and sync each
         DSN to the first.

mk-table-sync can run in one of two ways: with L<"--replicate"> or without.
The default is to run without L<"--replicate"> which causes mk-table-sync
to automatically find differences efficiently with one of several
algorithms (see L<"ALGORITHMS">).  Alternatively, the value of
L<"--replicate">, if specified, causes mk-table-sync to use the differences
already found by having previously ran L<mk-table-checksum> with its own
C<--replicate> option.  Strictly speaking, you don't need to use
L<"--replicate"> because mk-table-sync can find differences, but many
people use L<"--replicate"> if, for example, they checksum regularly
using L<mk-table-checksum> then fix differences as needed with mk-table-sync.
If you're unsure, read each tool's documentation carefully and decide for
yourself, or consult with an expert.

Regardless of whether L<"--replicate"> is used or not, you need to specify
which hosts to sync.  There are two ways: with L<"--sync-to-master"> or
without.  Specifying L<"--sync-to-master"> makes mk-table-sync expect
one and only slave DSN on the command line.  The tool will automatically
discover the slave's master and sync it so that its data is the same as
its master.  This is accomplished by making changes on the master which
then flow through replication and update the slave to resolve its differences.
B<Be careful though>: although this option specifies and syncs a single
slave, if there are other slaves on the same master, they will receive
via replication the changes intended for the slave that you're trying to
sync.

Alternatively, if you do not specify L<"--sync-to-master">, the first
DSN given on the command line is the source host.  There is only ever
one source host.  If you do not also specify L<"--replicate">, then you
must specify at least one other DSN as the destination host.  There
can be one or more destination hosts.  Source and destination hosts
must be independent; they cannot be in the same replication topology.
mk-table-sync will die with an error if it detects that a destination
host is a slave because changes are written directly to destination hosts
(and it's not safe to write directly to slaves).  Or, if you specify
L<"--replicate"> (but not L<"--sync-to-master">) then mk-table-sync expects
one and only one master DSN on the command line.  The tool will automatically
discover all the master's slaves and sync them to the master.  This is
the only way to sync several (all) slaves at once (because
L<"--sync-to-master"> only specifies one slave).

Each host on the command line is specified as a DSN.  The first DSN
(or only DSN for cases like L<"--sync-to-master">) provides default values
for other DSNs, whether those other DSNs are specified on the command line
or auto-discovered by the tool.  So in this example,

  mk-table-sync --execute h=host1,u=msandbox,p=msandbox h=host2

the host2 DSN inherits the C<u> and C<p> DSN parts from the host1 DSN.
Use the L<"--explain-hosts"> option to see how mk-table-sync will interpret
the DSNs given on the command line.

=head1 OUTPUT

If you specify the L<"--verbose"> option, you'll see information about the 
differences between the tables.  There is one row per table.  Each server is
printed separately.  For example,

  # Syncing h=host1,D=test,t=test1
  # DELETE REPLACE INSERT UPDATE ALGORITHM START    END      EXIT DATABASE.TABLE
  #      0       0      3      0 Chunk     13:00:00 13:00:17 2    test.test1

Table test.test1 on host1 required 3 C<INSERT> statements to synchronize
and it used the Chunk algorithm (see L<"ALGORITHMS">).  The sync operation
for this table started at 13:00:00 and ended 17 seconds later (times taken
from C<NOW()> on the source host).  Because differences were found, its
L<"EXIT STATUS"> was 2.

If you specify the L<"--print"> option, you'll see the actual SQL statements
that the script uses to synchronize the table if L<"--execute"> is also
specified.

If you want to see the SQL statements that mk-table-sync is using to select
chunks, nibbles, rows, etc., then specify L<"--print"> once and L<"--verbose">
twice.  Be careful though: this can print a lot of SQL statements.

There are cases where no combination of C<INSERT>, C<UPDATE> or C<DELETE>
statements can resolve differences without violating some unique key.  For
example, suppose there's a primary key on column a and a unique key on column b.
Then there is no way to sync these two tables with straightforward UPDATE
statements:

 +---+---+  +---+---+
 | a | b |  | a | b |
 +---+---+  +---+---+
 | 1 | 2 |  | 1 | 1 |
 | 2 | 1 |  | 2 | 2 |
 +---+---+  +---+---+

The tool rewrites queries to C<DELETE> and C<REPLACE> in this case.  This is
automatically handled after the first index violation, so you don't have to
worry about it.

=head1 REPLICATION SAFETY

Synchronizing a replication master and slave safely is a non-trivial problem, in
general.  There are all sorts of issues to think about, such as other processes
changing data, trying to change data on the slave, whether the destination and
source are a master-master pair, and much more.

In general, the safe way to do it is to change the data on the master, and let
the changes flow through replication to the slave like any other changes.
However, this works only if it's possible to REPLACE into the table on the
master.  REPLACE works only if there's a unique index on the table (otherwise it
just acts like an ordinary INSERT).

If your table has unique keys, you should use the L<"--sync-to-master"> and/or
L<"--replicate"> options to sync a slave to its master.  This will generally do
the right thing.  When there is no unique key on the table, there is no choice
but to change the data on the slave, and mk-table-sync will detect that you're
trying to do so.  It will complain and die unless you specify
C<--no-check-slave> (see L<"--[no]check-slave">).

If you're syncing a table without a primary or unique key on a master-master
pair, you must change the data on the destination server.  Therefore, you need
to specify C<--no-bin-log> for safety (see L<"--[no]bin-log">).  If you don't,
the changes you make on the destination server will replicate back to the
source server and change the data there!

The generally safe thing to do on a master-master pair is to use the
L<"--sync-to-master"> option so you don't change the data on the destination
server.  You will also need to specify C<--no-check-slave> to keep
mk-table-sync from complaining that it is changing data on a slave.

=head1 ALGORITHMS

mk-table-sync has a generic data-syncing framework which uses different
algorithms to find differences.  The tool automatically chooses the best
algorithm for each table based on indexes, column types, and the algorithm
preferences specified by L<"--algorithms">.  The following algorithms are
available, listed in their default order of preference:

=over

=item Chunk

Finds an index whose first column is numeric (including date and time types),
and divides the column's range of values into chunks of approximately
L<"--chunk-size"> rows.  Syncs a chunk at a time by checksumming the entire
chunk.  If the chunk differs on the source and destination, checksums each
chunk's rows individually to find the rows that differ.

It is efficient when the column has sufficient cardinality to make the chunks
end up about the right size.

The initial per-chunk checksum is quite small and results in minimal network
traffic and memory consumption.  If a chunk's rows must be examined, only the
primary key columns and a checksum are sent over the network, not the entire
row.  If a row is found to be different, the entire row will be fetched, but not
before.

=item Nibble

Finds an index and ascends the index in fixed-size nibbles of L<"--chunk-size">
rows, using a non-backtracking algorithm (see L<mk-archiver> for more on this
algorithm).  It is very similar to L<"Chunk">, but instead of pre-calculating
the boundaries of each piece of the table based on index cardinality, it uses
C<LIMIT> to define each nibble's upper limit, and the previous nibble's upper
limit to define the lower limit.

It works in steps: one query finds the row that will define the next nibble's
upper boundary, and the next query checksums the entire nibble.  If the nibble
differs between the source and destination, it examines the nibble row-by-row,
just as L<"Chunk"> does.

=item GroupBy

Selects the entire table grouped by all columns, with a COUNT(*) column added.
Compares all columns, and if they're the same, compares the COUNT(*) column's
value to determine how many rows to insert or delete into the destination.
Works on tables with no primary key or unique index.

=item Stream

Selects the entire table in one big stream and compares all columns.  Selects
all columns.  Much less efficient than the other algorithms, but works when
there is no suitable index for them to use.

=item Future Plans

Possibilities for future algorithms are TempTable (what I originally called
bottom-up in earlier versions of this tool), DrillDown (what I originally
called top-down), and GroupByPrefix (similar to how SqlYOG Job Agent works).
Each algorithm has strengths and weaknesses.  If you'd like to implement your
favorite technique for finding differences between two sources of data on
possibly different servers, I'm willing to help.  The algorithms adhere to a
simple interface that makes it pretty easy to write your own.

=back

=head1 BIDIRECTIONAL SYNCING

Bidirectional syncing is a new, experimental feature.  To make it work
reliably there are a number of strict limitations:

  * only works when syncing one server to other independent servers
  * does not work in any way with replication
  * requires that the table(s) are chunkable with the Chunk algorithm
  * is not N-way, only bidirectional between two servers at a time
  * does not handle DELETE changes

For example, suppose we have three servers: c1, r1, r2.  c1 is the central
server, a pseudo-master to the other servers (viz. r1 and r2 are not slaves
to c1).  r1 and r2 are remote servers.  Rows in table foo are updated and
inserted on all three servers and we want to synchronize all the changes
between all the servers.  Table foo has columns:

  id    int PRIMARY KEY
  ts    timestamp auto updated
  name  varchar

Auto-increment offsets are used so that new rows from any server do not
create conflicting primary key (id) values.  In general, newer rows, as
determined by the ts column, take precedence when a same but differing row
is found during the bidirectional sync.  "Same but differing" means that
two rows have the same primary key (id) value but different values for some
other column, like the name column in this example.  Same but differing
conflicts are resolved by a "conflict".  A conflict compares some column of
the competing rows to determine a "winner".  The winning row becomes the
source and its values are used to update the other row.

There are subtle differences between three columns used to achieve
bidirectional syncing that you should be familiar with: chunk column
(L<"--chunk-column">), comparison column(s) (L<"--columns">), and conflict
column (L<"--conflict-column">).  The chunk column is only used to chunk the
table; e.g. "WHERE id >= 5 AND id < 10".  Chunks are checksummed and when
chunk checksums reveal a difference, the tool selects the rows in that
chunk and checksums the L<"--columns"> for each row.  If a column checksum
differs, the rows have one or more conflicting column values.  In a
traditional unidirectional sync, the conflict is a moot point because it can
be resolved simply by updating the entire destination row with the source
row's values.  In a bidirectional sync, however, the L<"--conflict-column">
(in accordance with other C<--conflict-*> options list below) is compared
to determine which row is "correct" or "authoritative"; this row becomes
the "source".

To sync all three servers completely, two runs of mk-table-sync are required.
The first run syncs c1 and r1, then syncs c1 and r2 including any changes
from r1.  At this point c1 and r2 are completely in sync, but r1 is missing
any changes from r2 because c1 didn't have these changes when it and r1
were synced.  So a second run is needed which syncs the servers in the same
order, but this time when c1 and r1 are synced r1 gets r2's changes.

The tool does not sync N-ways, only bidirectionally between the first DSN
given on the command line and each subsequent DSN in turn.  So the tool in
this example would be ran twice like:

  mk-table-sync --bidirectional h=c1 h=r1 h=r2

The L<"--bidirectional"> option enables this feature and causes various
sanity checks to be performed.  You must specify other options that tell
mk-table-sync how to resolve conflicts for same but differing rows.
These options are:

  * L<"--conflict-column">
  * L<"--conflict-comparison">
  * L<"--conflict-value">
  * L<"--conflict-threshold">
  * L<"--conflict-error">  (optional)

Use L<"--print"> to test this option before L<"--execute">.  The printed
SQL statements will have comments saying on which host the statement
would be executed if you used L<"--execute">.

Technical side note: the first DSN is always the "left" server and the other
DSNs are always the "right" server.  Since either server can become the source
or destination it's confusing to think of them as "src" and "dst".  Therefore,
they're generically referred to as left and right.  It's easy to remember
this because the first DSN is always to the left of the other server DSNs on
the command line.

=head1 EXIT STATUS

The following are the exit statuses (also called return values, or return codes)
when mk-table-sync finishes and exits.

   STATUS  MEANING
   ======  =======================================================
   0       Success.
   1       Internal error.
   2       At least one table differed on the destination.
   3       Combination of 1 and 2.

=head1 OPTIONS

Specify at least one of L<"--print">, L<"--execute">, or L<"--dry-run">.

L<"--where"> and L<"--replicate"> are mutually exclusive.

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --algorithms

type: string; default: Chunk,Nibble,GroupBy,Stream

Algorithm to use when comparing the tables, in order of preference.

For each table, mk-table-sync will check if the table can be synced with
the given algorithms in the order that they're given.  The first algorithm
that can sync the table is used.  See L<"ALGORITHMS">.

=item --ask-pass

Prompt for a password when connecting to MySQL.

=item --bidirectional

Enable bidirectional sync between first and subsequent hosts.

See L<"BIDIRECTIONAL SYNCING"> for more information.

=item --[no]bin-log

default: yes

Log to the binary log (C<SET SQL_LOG_BIN=1>).

Specifying C<--no-bin-log> will C<SET SQL_LOG_BIN=0>.

=item --buffer-in-mysql

Instruct MySQL to buffer queries in its memory.

This option adds the C<SQL_BUFFER_RESULT> option to the comparison queries.
This causes MySQL to execute the queries and place them in a temporary table
internally before sending the results back to mk-table-sync.  The advantage of
this strategy is that mk-table-sync can fetch rows as desired without using a
lot of memory inside the Perl process, while releasing locks on the MySQL table
(to reduce contention with other queries).  The disadvantage is that it uses
more memory on the MySQL server instead.

You probably want to leave L<"--[no]buffer-to-client"> enabled too, because
buffering into a temp table and then fetching it all into Perl's memory is
probably a silly thing to do.  This option is most useful for the GroupBy and
Stream algorithms, which may fetch a lot of data from the server.

=item --[no]buffer-to-client

default: yes

Fetch rows one-by-one from MySQL while comparing.

This option enables C<mysql_use_result> which causes MySQL to hold the selected
rows on the server until the tool fetches them.  This allows the tool to use
less memory but may keep the rows locked on the server longer.

If this option is disabled by specifying C<--no-buffer-to-client> then
C<mysql_store_result> is used which causes MySQL to send all selected rows to
the tool at once.  This may result in the results "cursor" being held open for
a shorter time on the server, but if the tables are large, it could take a long
time anyway, and use all your memory.

For most non-trivial data sizes, you want to leave this option enabled.

This option is disabled when L<"--bidirectional"> is used.

=item --charset

short form: -A; type: string

Default character set.  If the value is utf8, sets Perl's binmode on
STDOUT to utf8, passes the mysql_enable_utf8 option to DBD::mysql, and
runs SET NAMES UTF8 after connecting to MySQL.  Any other value sets
binmode on STDOUT without the utf8 layer, and runs SET NAMES after
connecting to MySQL.

=item --[no]check-master

default: yes

With L<"--sync-to-master">, try to verify that the detected
master is the real master.

=item --[no]check-privileges

default: yes

Check that user has all necessary privileges on source and destination table.

=item --[no]check-slave

default: yes

Check whether the destination server is a slave.

If the destination server is a slave, it's generally unsafe to make changes on
it.  However, sometimes you have to; L<"--replace"> won't work unless there's a
unique index, for example, so you can't make changes on the master in that
scenario.  By default mk-table-sync will complain if you try to change data on
a slave.  Specify C<--no-check-slave> to disable this check.  Use it at your own
risk.

=item --[no]check-triggers

default: yes

Check that no triggers are defined on the destination table.

Triggers were introduced in MySQL v5.0.2, so for older versions this option
has no effect because triggers will not be checked.

=item --chunk-column

type: string

Chunk the table on this column.

=item --chunk-index

type: string

Chunk the table using this index.

=item --chunk-size

type: string; default: 1000

Number of rows or data size per chunk.

The size of each chunk of rows for the L<"Chunk"> and L<"Nibble"> algorithms.
The size can be either a number of rows, or a data size.  Data sizes are
specified with a suffix of k=kibibytes, M=mebibytes, G=gibibytes.  Data sizes
are converted to a number of rows by dividing by the average row length.

=item --columns

short form: -c; type: array

Compare this comma-separated list of columns.

=item --config

type: Array

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --conflict-column

type: string

Compare this column when rows conflict during a L<"--bidirectional"> sync.

When a same but differing row is found the value of this column from each
row is compared according to L<"--conflict-comparison">, L<"--conflict-value">
and L<"--conflict-threshold"> to determine which row has the correct data and
becomes the source.  The column can be any type for which there is an
appropriate L<"--conflict-comparison"> (this is almost all types except, for
example, blobs).

This option only works with L<"--bidirectional">.
See L<"BIDIRECTIONAL SYNCING"> for more information.

=item --conflict-comparison

type: string

Choose the L<"--conflict-column"> with this property as the source.

The option affects how the L<"--conflict-column"> values from the conflicting
rows are compared.  Possible comparisons are one of these MAGIC_comparisons:

  newest|oldest|greatest|least|equals|matches

  COMPARISON  CHOOSES ROW WITH
  ==========  =========================================================
  newest      Newest temporal L<"--conflict-column"> value
  oldest      Oldest temporal L<"--conflict-column"> value
  greatest    Greatest numerical L<"--conflict-column"> value
  least       Least numerical L<"--conflict-column"> value
  equals      L<"--conflict-column"> value equal to L<"--conflict-value">
  matches     L<"--conflict-column"> value matching Perl regex pattern
              L<"--conflict-value">

This option only works with L<"--bidirectional">.
See L<"BIDIRECTIONAL SYNCING"> for more information.

=item --conflict-error

type: string; default: warn

How to report unresolvable conflicts and conflict errors

This option changes how the user is notified when a conflict cannot be
resolved or causes some kind of error.  Possible values are:

  * warn: Print a warning to STDERR about the unresolvable conflict
  * die:  Die, stop syncing, and print a warning to STDERR

This option only works with L<"--bidirectional">.
See L<"BIDIRECTIONAL SYNCING"> for more information.

=item --conflict-threshold

type: string

Amount by which one L<"--conflict-column"> must exceed the other.

The L<"--conflict-threshold"> prevents a conflict from being resolved if
the absolute difference between the two L<"--conflict-column"> values is
less than this amount.  For example, if two L<"--conflict-column"> have
timestamp values "2009-12-01 12:00:00" and "2009-12-01 12:05:00" the difference
is 5 minutes.  If L<"--conflict-threshold"> is set to "5m" the conflict will
be resolved, but if L<"--conflict-threshold"> is set to "6m" the conflict
will fail to resolve because the difference is not greater than or equal
to 6 minutes.  In this latter case, L<"--conflict-error"> will report
the failure.

This option only works with L<"--bidirectional">.
See L<"BIDIRECTIONAL SYNCING"> for more information.

=item --conflict-value

type: string

Use this value for certain L<"--conflict-comparison">.

This option gives the value for C<equals> and C<matches>
L<"--conflict-comparison">.

This option only works with L<"--bidirectional">.
See L<"BIDIRECTIONAL SYNCING"> for more information.

=item --databases

short form: -d; type: hash

Sync only this comma-separated list of databases.

A common request is to sync tables from one database with tables from another
database on the same or different server.  This is not yet possible.
L<"--databases"> will not do it, and you can't do it with the D part of the DSN
either because in the absence of a table name it assumes the whole server
should be synced and the D part controls only the connection's default database.

=item --defaults-file

short form: -F; type: string

Only read mysql options from the given file.  You must give an absolute pathname.

=item --dry-run

Analyze, decide the sync algorithm to use, print and exit.

Implies L<"--verbose"> so you can see the results.  The results are in the same
output format that you'll see from actually running the tool, but there will be
zeros for rows affected.  This is because the tool actually executes, but stops
before it compares any data and just returns zeros.  The zeros do not mean there
are no changes to be made.

=item --engines

short form: -e; type: hash

Sync only this comma-separated list of storage engines.

=item --execute

Execute queries to make the tables have identical data.

This option makes mk-table-sync actually sync table data by executing all
the queries that it created to resolve table differences.  Therefore, B<the
tables will be changed!>  And unless you also specify L<"--verbose">, the
changes will be made silently.  If this is not what you want, see
L<"--print"> or L<"--dry-run">.

=item --explain-hosts

Print connection information and exit.

Print out a list of hosts to which mk-table-sync will connect, with all
the various connection options, and exit.

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

=item --[no]foreign-key-checks

default: yes

Enable foreign key checks (C<SET FOREIGN_KEY_CHECKS=1>).

Specifying C<--no-foreign-key-checks> will C<SET FOREIGN_KEY_CHECKS=0>.

=item --function

type: string

Which hash function you'd like to use for checksums.

The default is C<CRC32>.  Other good choices include C<MD5> and C<SHA1>.  If you
have installed the C<FNV_64> user-defined function, C<mk-table-sync> will detect
it and prefer to use it, because it is much faster than the built-ins.  You can
also use MURMUR_HASH if you've installed that user-defined function.  Both of
these are distributed with Maatkit.  See L<mk-table-checksum> for more
information and benchmarks.

=item --help

Show help and exit.

=item --[no]hex-blob

default: yes

C<HEX()> C<BLOB>, C<TEXT> and C<BINARY> columns.

When row data from the source is fetched to create queries to sync the
data (i.e. the queries seen with L<"--print"> and executed by L<"--execute">),
binary columns are wrapped in HEX() so the binary data does not produce
an invalid SQL statement.  You can disable this option but you probably
shouldn't.

=item --host

short form: -h; type: string

Connect to host.

=item --ignore-columns

type: Hash

Ignore this comma-separated list of column names in comparisons.

This option causes columns not to be compared.  However, if a row is determined
to differ between tables, all columns in that row will be synced, regardless.
(It is not currently possible to exclude columns from the sync process itself,
only from the comparison.)

=item --ignore-databases

type: Hash

Ignore this comma-separated list of databases.

=item --ignore-engines

type: Hash; default: FEDERATED,MRG_MyISAM

Ignore this comma-separated list of storage engines.

=item --ignore-tables

type: Hash

Ignore this comma-separated list of tables.

Table names may be qualified with the database name.

=item --[no]index-hint

default: yes

Add FORCE/USE INDEX hints to the chunk and row queries.

By default C<mk-table-sync> adds a FORCE/USE INDEX hint to each SQL statement
to coerce MySQL into using the index chosen by the sync algorithm or specified
by L<"--chunk-index">.  This is usually a good thing, but in rare cases the
index may not be the best for the query so you can suppress the index hint
by specifying C<--no-index-hint> and let MySQL choose the index.

This does not affect the queries printed by L<"--print">; it only affects the
chunk and row queries that C<mk-table-sync> uses to select and compare rows.

=item --lock

type: int

Lock tables: 0=none, 1=per sync cycle, 2=per table, or 3=globally.

This uses C<LOCK TABLES>.  This can help prevent tables being changed while
you're examining them.  The possible values are as follows:

  VALUE  MEANING
  =====  =======================================================
  0      Never lock tables.
  1      Lock and unlock one time per sync cycle (as implemented
         by the syncing algorithm).  This is the most granular
         level of locking available.  For example, the Chunk
         algorithm will lock each chunk of C<N> rows, and then
         unlock them if they are the same on the source and the
         destination, before moving on to the next chunk.
  2      Lock and unlock before and after each table.
  3      Lock and unlock once for every server (DSN) synced, with
         C<FLUSH TABLES WITH READ LOCK>.

A replication slave is never locked if L<"--replicate"> or L<"--sync-to-master">
is specified, since in theory locking the table on the master should prevent any
changes from taking place.  (You are not changing data on your slave, right?)
If L<"--wait"> is given, the master (source) is locked and then the tool waits
for the slave to catch up to the master before continuing.

If C<--transaction> is specified, C<LOCK TABLES> is not used.  Instead, lock
and unlock are implemented by beginning and committing transactions.
The exception is if L<"--lock"> is 3.

If C<--no-transaction> is specified, then C<LOCK TABLES> is used for any
value of L<"--lock">. See L<"--[no]transaction">.

=item --lock-and-rename

Lock the source and destination table, sync, then swap names.  This is useful as
a less-blocking ALTER TABLE, once the tables are reasonably in sync with each
other (which you may choose to accomplish via any number of means, including
dump and reload or even something like L<mk-archiver>).  It requires exactly two
DSNs and assumes they are on the same server, so it does no waiting for
replication or the like.  Tables are locked with LOCK TABLES.

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

=item --print

Print queries that will resolve differences.

If you don't trust C<mk-table-sync>, or just want to see what it will do, this
is a good way to be safe.  These queries are valid SQL and you can run them
yourself if you want to sync the tables manually.

=item --recursion-method

type: string

Preferred recursion method used to find slaves.

Possible methods are:

  METHOD       USES
  ===========  ================
  processlist  SHOW PROCESSLIST
  hosts        SHOW SLAVE HOSTS

The processlist method is preferred because SHOW SLAVE HOSTS is not reliable.
However, the hosts method is required if the server uses a non-standard
port (not 3306).  Usually mk-table-sync does the right thing and finds
the slaves, but you may give a preferred method and it will be used first.
If it doesn't find any slaves, the other methods will be tried.


=item --replace

Write all C<INSERT> and C<UPDATE> statements as C<REPLACE>.

This is automatically switched on as needed when there are unique index
violations.

=item --replicate

type: string

Sync tables listed as different in this table.

Specifies that C<mk-table-sync> should examine the specified table to find data
that differs.  The table is exactly the same as the argument of the same name to
L<mk-table-checksum>.  That is, it contains records of which tables (and ranges
of values) differ between the master and slave.

For each table and range of values that shows differences between the master and
slave, C<mk-table-checksum> will sync that table, with the appropriate C<WHERE>
clause, to its master.

This automatically sets L<"--wait"> to 60 and causes changes to be made on the
master instead of the slave.

If L<"--sync-to-master"> is specified, the tool will assume the server you
specified is the slave, and connect to the master as usual to sync.

Otherwise, it will try to use C<SHOW PROCESSLIST> to find slaves of the server
you specified.  If it is unable to find any slaves via C<SHOW PROCESSLIST>, it
will inspect C<SHOW SLAVE HOSTS> instead.  You must configure each slave's
C<report-host>, C<report-port> and other options for this to work right.  After
finding slaves, it will inspect the specified table on each slave to find data
that needs to be synced, and sync it. 

The tool examines the master's copy of the table first, assuming that the master
is potentially a slave as well.  Any table that shows differences there will
B<NOT> be synced on the slave(s).  For example, suppose your replication is set
up as A->B, B->C, B->D.  Suppose you use this argument and specify server B.
The tool will examine server B's copy of the table.  If it looks like server B's
data in table C<test.tbl1> is different from server A's copy, the tool will not
sync that table on servers C and D.

=item --set-vars

type: string; default: wait_timeout=10000

Set these MySQL variables.  Immediately after connecting to MySQL, this
string will be appended to SET and executed.

=item --socket

short form: -S; type: string

Socket file to use for connection.

=item --sync-to-master

Treat the DSN as a slave and sync it to its master.

Treat the server you specified as a slave.  Inspect C<SHOW SLAVE STATUS>,
connect to the server's master, and treat the master as the source and the slave
as the destination.  Causes changes to be made on the master.  Sets L<"--wait">
to 60 by default, sets L<"--lock"> to 1 by default, and disables
L<"--[no]transaction"> by default.  See also L<"--replicate">, which changes
this option's behavior.

=item --tables

short form: -t; type: hash

Sync only this comma-separated list of tables.

Table names may be qualified with the database name.

=item --timeout-ok

Keep going if L<"--wait"> fails.

If you specify L<"--wait"> and the slave doesn't catch up to the master's
position before the wait times out, the default behavior is to abort.  This
option makes the tool keep going anyway.  B<Warning>: if you are trying to get a
consistent comparison between the two servers, you probably don't want to keep
going after a timeout.

=item --[no]transaction

Use transactions instead of C<LOCK TABLES>.

The granularity of beginning and committing transactions is controlled by
L<"--lock">.  This is enabled by default, but since L<"--lock"> is disabled by
default, it has no effect.

Most options that enable locking also disable transactions by default, so if
you want to use transactional locking (via C<LOCK IN SHARE MODE> and C<FOR
UPDATE>, you must specify C<--transaction> explicitly.

If you don't specify C<--transaction> explicitly C<mk-table-sync> will decide on
a per-table basis whether to use transactions or table locks.  It currently
uses transactions on InnoDB tables, and table locks on all others.

If C<--no-transaction> is specified, then C<mk-table-sync> will not use
transactions at all (not even for InnoDB tables) and locking is controlled
by L<"--lock">.

When enabled, either explicitly or implicitly, the transaction isolation level
is set C<REPEATABLE READ> and transactions are started C<WITH CONSISTENT
SNAPSHOT>.

=item --trim

C<TRIM()> C<VARCHAR> columns in C<BIT_XOR> and C<ACCUM> modes.  Helps when
comparing MySQL 4.1 to >= 5.0.

This is useful when you don't care about the trailing space differences between
MySQL versions which vary in their handling of trailing spaces. MySQL 5.0 and 
later all retain trailing spaces in C<VARCHAR>, while previous versions would 
remove them.

=item --[no]unique-checks

default: yes

Enable unique key checks (C<SET UNIQUE_CHECKS=1>).

Specifying C<--no-unique-checks> will C<SET UNIQUE_CHECKS=0>.

=item --user

short form: -u; type: string

User for login if not current user.

=item --verbose

short form: -v; cumulative: yes

Print results of sync operations.

See L<"OUTPUT"> for more details about the output.

=item --version

Show version and exit.

=item --wait

short form: -w; type: time

How long to wait for slaves to catch up to their master.

Make the master wait for the slave to catch up in replication before comparing
the tables.  The value is the number of seconds to wait before timing out (see
also L<"--timeout-ok">).  Sets L<"--lock"> to 1 and L<"--[no]transaction"> to 0
by default.  If you see an error such as the following,

  MASTER_POS_WAIT returned -1

It means the timeout was exceeded and you need to increase it.

The default value of this option is influenced by other options.  To see what
value is in effect, run with L<"--help">.

To disable waiting entirely (except for locks), specify L<"--wait"> 0.  This
helps when the slave is lagging on tables that are not being synced.

=item --where

type: string

C<WHERE> clause to restrict syncing to part of the table.

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

Database containing the table to be synced.

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

copy: yes

Table to be synced.

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

The environment variable MKDEBUG enables verbose debugging output in all of the
Maatkit tools:

   MKDEBUG=1 mk-....

=head1 SYSTEM REQUIREMENTS

You need Perl, DBI, DBD::mysql, and some core packages that ought to be
installed in any reasonably new version of Perl.

=head1 BUGS

For a list of known bugs see: L<http://www.maatkit.org/bugs/mk-table-sync>.

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

=head1 AUTHOR

Baron Schwartz

=head1 ABOUT MAATKIT

This tool is part of Maatkit, a toolkit for power users of MySQL.  Maatkit
was created by Baron Schwartz; Baron and Daniel Nichter are the primary
code contributors.  Both are employed by Percona.  Financial support for
Maatkit development is primarily provided by Percona and its clients. 

=head1 HISTORY AND ACKNOWLEDGMENTS

My work is based in part on Giuseppe Maxia's work on distributed databases,
L<http://www.sysadminmag.com/articles/2004/0408/> and code derived from that
article.  There is more explanation, and a link to the code, at
L<http://www.perlmonks.org/?node_id=381053>.

Another programmer extended Maxia's work even further.  Fabien Coelho changed
and generalized Maxia's technique, introducing symmetry and avoiding some
problems that might have caused too-frequent checksum collisions.  This work
grew into pg_comparator, L<http://www.coelho.net/pg_comparator/>.  Coelho also
explained the technique further in a paper titled "Remote Comparison of Database
Tables" (L<http://cri.ensmp.fr/classement/doc/A-375.pdf>).

This existing literature mostly addressed how to find the differences between
the tables, not how to resolve them once found.  I needed a tool that would not
only find them efficiently, but would then resolve them.  I first began thinking
about how to improve the technique further with my article
L<http://tinyurl.com/mysql-data-diff-algorithm>,
where I discussed a number of problems with the Maxia/Coelho "bottom-up"
algorithm.  After writing that article, I began to write this tool.  I wanted to
actually implement their algorithm with some improvements so I was sure I
understood it completely.  I discovered it is not what I thought it was, and is
considerably more complex than it appeared to me at first.  Fabien Coelho was
kind enough to address some questions over email.

The first versions of this tool implemented a version of the Coelho/Maxia
algorithm, which I called "bottom-up", and my own, which I called "top-down."
Those algorithms are considerably more complex than the current algorithms and
I have removed them from this tool, and may add them back later.  The
improvements to the bottom-up algorithm are my original work, as is the
top-down algorithm.  The techniques to actually resolve the differences are
also my own work.

Another tool that can synchronize tables is the SQLyog Job Agent from webyog.
Thanks to Rohit Nadhani, SJA's author, for the conversations about the general
techniques.  There is a comparison of mk-table-sync and SJA at
L<http://tinyurl.com/maatkit-vs-sqlyog>

Thanks to the following people and organizations for helping in many ways:

The Rimm-Kaufman Group L<http://www.rimmkaufman.com/>,
MySQL AB L<http://www.mysql.com/>,
Blue Ridge InternetWorks L<http://www.briworks.com/>,
Percona L<http://www.percona.com/>,
Fabien Coelho,
Giuseppe Maxia and others at MySQL AB,
Kristian Koehntopp (MySQL AB),
Rohit Nadhani (WebYog),
The helpful monks at Perlmonks,
And others too numerous to mention.

=head1 VERSION

This manual page documents Ver 1.0.31 Distrib 7540 $Revision: 7476 $.

=cut

__END__
:endofperl
