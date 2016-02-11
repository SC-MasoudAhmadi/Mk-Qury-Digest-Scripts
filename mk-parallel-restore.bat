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

# This is a program to load files into MySQL in parallel.
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

our $VERSION = '1.0.24';
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
# MaatkitCommon package 7096
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/MaatkitCommon.pm
#   trunk/common/t/MaatkitCommon.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################
package MaatkitCommon;


use strict;
use warnings FATAL => 'all';

use English qw(-no_match_vars);

require Exporter;
our @ISA         = qw(Exporter);
our %EXPORT_TAGS = ();
our @EXPORT      = qw();
our @EXPORT_OK   = qw(
   _d
   get_number_of_cpus
);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

sub _d {
   my ($package, undef, $line) = caller 0;
   @_ = map { (my $temp = $_) =~ s/\n/\n# /g; $temp; }
        map { defined $_ ? $_ : 'undef' }
        @_;
   print STDERR "# $package:$line $PID ", join(' ', @_), "\n";
}

sub get_number_of_cpus {
   my ( $sys_info ) = @_;
   my $n_cpus; 

   my $cpuinfo;
   if ( $sys_info || (open $cpuinfo, "<", "/proc/cpuinfo") ) {
      local $INPUT_RECORD_SEPARATOR = undef;
      my $contents = $sys_info || <$cpuinfo>;
      MKDEBUG && _d('sys info:', $contents);
      close $cpuinfo if $cpuinfo;
      $n_cpus = scalar( map { $_ } $contents =~ m/(processor)/g );
      MKDEBUG && _d('Got', $n_cpus, 'cpus from /proc/cpuinfo');
      return $n_cpus if $n_cpus;
   }


   if ( $sys_info || ($OSNAME =~ m/freebsd/i) || ($OSNAME =~ m/darwin/i) ) { 
      my $contents = $sys_info || `sysctl hw.ncpu`;
      MKDEBUG && _d('sys info:', $contents);
      ($n_cpus) = $contents =~ m/(\d)/ if $contents;
      MKDEBUG && _d('Got', $n_cpus, 'cpus from sysctl hw.ncpu');
      return $n_cpus if $n_cpus;
   } 

   $n_cpus ||= $ENV{NUMBER_OF_PROCESSORS};

   return $n_cpus || 1; # There has to be at least 1 CPU.
}

1;

# ###########################################################################
# End MaatkitCommon package
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
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_parallel_restore;

use English qw(-no_match_vars);
use File::Basename qw(dirname);
use File::Find;
use File::Spec;
use File::Temp;
use List::Util qw(max sum);
use POSIX;
use Time::HiRes qw(time);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

Transformers->import(qw(shorten secs_to_time ts));

# Global variables.
my $last_bytes_done = 0;

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

   $o->set('threads', max(2, MaatkitCommon::get_number_of_cpus()))
      unless $o->got('threads');

   # ########################################################################
   # Process options.
   # ########################################################################
   $o->set('base-dir', File::Spec->rel2abs($o->get('base-dir')));

   if ( $o->get('quiet') ) {
      $o->set('verbose', 0);
   }

   if ( $o->get('csv') ) {
      $o->set('tab', 1);
   }

   if ( $o->get('tab') ) {
      $o->set('commit', 1)             unless $o->get('commit');
      $o->set('disable-keys', 1)       unless $o->got('disable-keys');
      $o->set('no-auto-value-on-0', 1) unless $o->got('no-auto-value-on-0');
      $o->set('bin-log', 0)            unless $o->got('bin-log');
      $o->set('unique-checks', 0)      unless $o->got('unique-checks');
      $o->set('foreign-key-checks', 0) unless $o->got('foreign-key-checks');
   }

   my $dsn;
   if ( @ARGV ) {
      my @paths;
      foreach my $arg ( @ARGV ) {
         # Arg is a path if it's a path or file that exist or, for paths/files
         # that don't exist, it doesn't have equal signs in its name (most
         # paths/files shouldn't; most DSN do).
         if ( -d $arg || -e $arg || $arg !~ m/=/ ) {
            MKDEBUG && _d('Auto-detected', $arg, 'as a path');
            push @paths, $arg;
         }
         else {
            MKDEBUG && _d('Auto-detected', $arg, 'as a DSN');
            if ( $dsn ) {
               $o->save_error("More than one DSN was specified; "
                  . "only one is allowed");
               next;
            }
            $dsn = $arg;
         }
      }
      @ARGV = @paths;
   }
   if ( !@ARGV ) {
      $o->save_error("You did not specify any files to restore");
   }

   foreach my $opt ( qw(bulk-insert-buffer-size local ignore replace) ) {
      if ( $o->got($opt) && !$o->get('tab') ) {
         $o->save_error("Option --$opt is ineffective without --tab or --csv");
      }
   }

   if ( $o->get('fifo') ) {
      if ( !$o->got('umask') ) {
         $o->set('umask', 0);
      }
   }

   if ( $o->get('umask') ) {
      umask oct($o->get('umask'));
   }

   # See issue 31.
   my $biggest_first = $o->got('biggest-first') ? $o->get('biggest-first')
                     : @ARGV > 1                ? 0
                     : $o->get('biggest-first'); # default from POD
   $o->set('biggest-first', $biggest_first);

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
   # Make common modules.
   # ########################################################################
   my $q  = new Quoter();
   my $tp = new TableParser(Quoter => $q);
   my %common_modules = (
      o  => $o,
      dp => $dp,
      q  => $q,
      tp => $tp,
   );

   # ########################################################################
   # Connect.
   # ########################################################################
   if ( $o->get('ask-pass') ) {
      $o->set('password', OptionParser::prompt_noecho("Enter password: "));
   }
   my $dbh = get_cxn(o=>$o, dp=>$dp, dsn=>$dsn);
   $dbh->{InactiveDestroy}  = 1;         # Don't die on fork().
   $dbh->{FetchHashKeyName} = 'NAME_lc'; # Lowercases all column names for fetchrow_hashref()

   # Turn off binary logging on the main dbh else some things
   # like --create-databases will replicate.
   _do($dbh, $o->get('dry-run'), 'SET SQL_LOG_BIN=0') unless $o->get('bin-log');

   # ########################################################################
   # Discover files to be restored.
   # ########################################################################
   my @tables_to_do;
   my @view_files;
   my %files_for_table;
   my %size_for_table;
   my %size_for_file;
   my %chunks_for_table;
   my %stats;
   my $known_filetypes = 'sql|txt|csv';
   my $bytes = 0; # For progress measurements

   {
   # These vars aren't needed outside this local scope.
   my $databases       = $o->get('databases');
   my $databases_regex = $o->get('databases-regex');
   my $tables          = $o->get('tables');
   my $tables_regex    = $o->get('tables-regex');
   my %has_tables;

   # Find directories and files and save them.
   File::Find::find(
      {  no_chdir => 1,
         wanted   => sub {
            my ( $dir, $filename ) = ($File::Find::dir, $File::Find::name);
            if ( -f $filename && $filename !~ m/00_master/ ) {
               my ($vol, $dirs, $file) = File::Spec->splitpath( $filename );
               if ( $file =~ m/\.(?:$known_filetypes)(?:\.\d+)?(?:\.gz)?$/ ) {
                  my @dirs       = grep { $_ } File::Spec->splitdir($dir);
                  my $db         = $dirs[-1];
                  my $restore_db = $o->get('database') || $dirs[-1];
                  my ($tbl)      = $file =~ m/^(?:\d\d_)?([^.]+)/;

                  if ( ( !$databases || exists($databases->{$db}) )
                     && ( !$databases_regex || $db =~ m/$databases_regex/ )
                     && ( !exists $o->get('ignore-databases')->{$db} )
                     && ( !exists $o->get('ignore-tables')->{$tbl} )
                     && ( !exists $o->get('ignore-tables')->{"$db.$tbl"} )
                     && ( !$tables || exists($tables->{$tbl}) )
                     && ( !$tables_regex || $tbl =~ m/$tables_regex/ ) )
                  {
                     if ( filetype($file) !~ m/sql/ && !$o->get('tab') ) {
                        die "$filename isn't a SQL file and you didn't tell me "
                           . "to load tab-delimited files.  Maybe you should "
                           . "specify the --tab option.\n";
                     }

                     if ( $o->get('only-empty-databases') ) {
                        if ( defined $has_tables{$restore_db}
                             && $has_tables{$restore_db} ) {
                           info($o, 1, "Skipping file $filename because "
                              . "database $restore_db is not empty");
                           return;
                        }

                        my $tbls;
                        eval {
                           my $sql = "SHOW TABLES FROM ".$q->quote($restore_db);
                           MKDEBUG && _d($sql);
                           $tbls = $dbh->selectall_arrayref($sql);
                        };
                        if ( $EVAL_ERROR ) {
                           # An error may indicate that the db doesn't exist.
                           MKDEBUG && _d($EVAL_ERROR);
                           $has_tables{$restore_db} = 0;
                        }
                        else {
                           $has_tables{$restore_db} = scalar @$tbls;
                           MKDEBUG && _d($restore_db, 'has',
                              $has_tables{$restore_db}, 'tables');
                           if ( $has_tables{$restore_db} ) {
                              info($o, 1, "Skipping file $filename because "
                                 . "database $restore_db is not empty");
                              return;
                           }
                        }
                     }

                     $stats{files}++;
                     push @{$files_for_table{$restore_db}->{$tbl}}, $filename;
                     my $size = -s $filename; # For progress measurements
                     $bytes += $size;
                     $size_for_table{$restore_db}->{$tbl} += $size;
                     $size_for_file{$filename} = $size;
                     push @tables_to_do, { # This pushes a dupe, filtered later.
                        D => $restore_db,
                        N => $tbl,
                     };
                  }
                  else {
                     MKDEBUG && _d($db, $tbl, "doesn't pass filters");
                  }

                  # Check if a chunks file for this table exits. This file
                  # is used for resuming interrupted restores.
                  my $chunks_file = $dirs . $tbl . '.chunks';
                  if ( !exists $chunks_for_table{$restore_db}->{$tbl}
                       && -f $chunks_file ) {
                     open my $CHUNKS_FILE, "< $chunks_file"
                        or die "Cannot open $file: $OS_ERROR";
                     my $chunks = do { local $/ = undef; <$CHUNKS_FILE> };
                     close $CHUNKS_FILE
                        or die "Cannot close $file: $OS_ERROR";
                     push @{ $chunks_for_table{$restore_db}->{$tbl} },
                        split(/\n/, $chunks);
                  }
               }
            }
            elsif ( !-d $filename && $filename !~ m/00_master_data.sql/ ) {
               info($o, 1, "Skipping file $filename");
            }
         },
      },
      map { File::Spec->rel2abs($_) } @ARGV
   );
   }

   # ########################################################################
   # Canonicalize table list in the order they were discovered, filtering out
   # tables that should not be done.
   # ########################################################################
   {
      my %seen;
      @tables_to_do = grep { !$seen{$_->{D}}->{$_->{N}}++ } @tables_to_do;
      $stats{tables} = scalar(@tables_to_do);

      if ( $o->get('create-databases') ) {
         my %dbs;
         map { $dbs{ $_->{D} }++ } @tables_to_do;
         foreach my $db ( keys %dbs ) {
            _do($dbh, $o->get('dry-run'),
               "CREATE DATABASE IF NOT EXISTS " . $q->quote($db));
         }
      }
   }

   # #########################################################################
   # Design the format for printing out.
   # #########################################################################
   my ( $maxdb, $maxtbl);
   $maxdb  = max(8, map { length($_->{D}) } @tables_to_do);
   $maxtbl = max(5, map { length($_->{N}) } @tables_to_do);
   my $format = "%-${maxdb}s %-${maxtbl}s %5s %5s %6s %7s";
   info($o, 2, sprintf($format, qw(DATABASE TABLE FILES TIME STATUS THREADS)));

   # This signal handler will do nothing but wake up the sleeping parent process
   # and record the exit status and time of the child that exited (as a side
   # effect of not discarding the signal).  Due to Solaris's signal handling and
   # File::Find's use of forking, this must go after File::Find.  See
   # bug #1887102.
   my %exited_children;
   $SIG{CHLD} = sub {
      my $kid;
      while (($kid = waitpid(-1, POSIX::WNOHANG)) > 0) {
         # Must right-shift to get the actual exit status of the child.
         $exited_children{$kid}->{exit_status} = $CHILD_ERROR >> 8;
         $exited_children{$kid}->{exit_time}   = time();
      }
   };

   # Save the table sizes to make testing more reliable.
   foreach my $tbl ( @tables_to_do ) {
      $tbl->{Z} = $size_for_table{ $tbl->{D} }->{ $tbl->{N} };
   }

   if ( $o->get('biggest-first') ) {
      @tables_to_do = sort { $b->{Z} <=> $a->{Z} } @tables_to_do;
   }

   # #########################################################################
   # Assign the work to child processes.  Initially just start --threads
   # number of children.  Each child that exits will trigger a new one to
   # start after that.
   # #########################################################################
   my $start = time();
   my $done  = 0; # For progress measurements. 

   my %kids;
   while ( @tables_to_do || %kids ) {

      # Wait for the MySQL server to become responsive.
      my $tries = 0;
      while ( !$dbh->ping && $tries++ < $o->get('wait') ) {
         sleep(1);
         eval {
            $dbh = get_cxn(dsn=>$dsn, %common_modules);
         };
         if ( $EVAL_ERROR ) {
            info($o, 0, 'Waiting: ' . scalar(localtime) . ' '
               . mysql_error_msg($EVAL_ERROR));
         }
      }
      if ( $tries >= $o->get('wait') ) {
         die "Too many retries, exiting.\n";
      }

      # Start a new child process.
      while ( @tables_to_do && $o->get('threads') > keys %kids ) {
         my $todo = shift @tables_to_do;
         $todo->{time} = time;
         my $pid = fork();
         die "Can't fork: $OS_ERROR" unless defined $pid;
         if ( $pid ) {              # I'm the parent
            $kids{$pid} = $todo;
         }
         else {                     # I'm the child
            $SIG{CHLD} = 'DEFAULT'; # See bug #1886444
            MKDEBUG && _d("PID", $PID, "got", Dumper($todo));
            my $exit_status = 0;
            $exit_status = do_table(
               file_types  => $known_filetypes,
               db          => $todo->{D},
               tbl         => $todo->{N},
               files       => $files_for_table{$todo->{D}}->{$todo->{N}},
               file_size   => \%size_for_file,
               tbl_chunks  => \%chunks_for_table,
               dsn         => $dsn,
               %common_modules,
            ) || $exit_status;
            exit($exit_status);
         }
      }

      # Possibly wait for child.
      my $reaped = 0;
      foreach my $kid ( keys %exited_children ) {
         my $status = $exited_children{$kid};
         my $todo   = $kids{$kid};
         my $stat   = $status->{exit_status};
         my $time   = $status->{exit_time} - $todo->{time};
         info($o, 2, sprintf($format, @{$todo}{qw(D N)},
            scalar(@{$files_for_table{$todo->{D}}->{$todo->{N}}}),
            sprintf('%.2f', $time), $stat, scalar(keys %kids)));
         $stats{ $stat ? 'failure' : 'success' }++;
         $stats{time} += $time;
         delete $kids{$kid};
         delete $exited_children{$kid};
         $reaped = 1;
         $done += $todo->{Z};
         # Reap progress report. See sub bytes_done_from_processlist() below.
         print_progress_report($o, $done, $dbh, $bytes, $start)
            if $o->get('progress');
      }

      if ( !$reaped ) {
         # Don't busy-wait.  But don't wait forever either, as a child may exit
         # and signal while we're not sleeping, so if we sleep forever we may
         # not get the signal.
         sleep(1);
         # Sleep progress report. See sub bytes_done_from_processlist() below.
         print_progress_report($o, $done, $dbh, $bytes, $start)
            if $o->get('progress');
      }
   }

   # Print final progress report which will show 100% done.
   # undef for the dbh param prevents checking the proclist
   # because all children are supposed to be done at this point.
   print_progress_report($o, $done, undef, $bytes, $start)
      if $o->get('progress');

   $stats{wallclock} = time() - $start;

   info($o, 1, sprintf(
      '%5d tables, %5d files, %5d successes, %2d failures, '
      . '%6.2f wall-clock time, %6.2f load time',
         map {
            $stats{$_} || 0
         } qw(tables files success failure wallclock time)
      ));

   # Exit status is 1 if there were any failures.
   return ($stats{failure} ? 1 : 0);
}

# ############################################################################
# Subroutines
# ############################################################################

sub makefifo {
   my ( $o ) = @_;
   my $filename = File::Spec->catfile($o->get('base-dir'), "mpr_fifo_$PID");
   if ( !-p $filename ) {
      if ( -e $filename ) {
         die "Cannot make fifo: $filename exists";
      }
      if ( $o->get('dry-run') ) {
         print "mkfifo $filename\n";
      }
      else {
         POSIX::mkfifo($filename, 0777)
            or die "Cannot make fifo $filename: $OS_ERROR";
      }
   }
   return $filename;
}

sub mysql_error_msg {
   my ( $text ) = @_;
   $text =~ s/^.*?failed: (.*?) at \S+ line (\d+).*$/$1 at line $2/s;
   return $text;
}

# Prints a message.
sub info {
   my ( $o, $level, $msg ) = @_;
   if ( $level <= $o->get('verbose') ) {
      print $msg, "\n";
   }
}

# Actually restores a table.
sub do_table {
   my ( %args ) = @_;
   foreach my $arg ( qw(file_types db tbl files o dp file_size tp) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $file_types = $args{file_types};
   my $db         = $args{db};
   my $tbl        = $args{tbl};
   my @files      = @{$args{files}};
   my $o          = $args{o};
   my $file_size  = $args{file_size};

   my $dry_run      = $o->get('dry-run');
   my $exit_status  = 0;
   my $bytes_done   = 0;
   my $dbh          = get_cxn(%args);
   my ($fifo, $load_from);

   # Sort files.  If it's a --tab, this will result in the following load
   # order:
   # * sql     (drop and create table)
   # * txt/csv (load data into table)
   @files = sort {
      my $a_type = filetype($a);
      my $b_type = filetype($b);
      (index($file_types, $a_type) <=> index($file_types, $b_type))
         || ($a cmp $b);
   } @files;

   if ( $o->get('resume') ) {
      $bytes_done = skip_finished_chunks(
         \@files,
         dbh => $dbh,
         %args,
      );
   }

   # Newer versions of mk-parallel-dump make the first file, called
   # 00_TBL.sql, contain only CREATE TABLE.  Then table data begins
   # with the second file.  Older versions of mk-parallel-dump put
   # CREATE TABLE with the first chunk of table data in the first file.
   # skip_finished_chunks() handles both versions and removes whatever
   # file has CREATE TABLE if necessary.  So if there's a first file
   # and it's from a new version dump, then we need to execute it to
   # create the table.  Else, skip_finished_chunks() determined that
   # the table already exists.
   my $create_table = $files[0] && $files[0] =~ m/00_$tbl\.sql$/ ? shift @files                                                                  : undef;
   MKDEBUG && _d('CREATE TABLE', $tbl, 'in', $create_table);
   my $table_ddl;
   my $indexes_ddl;
   my $engine = '';
   if ( $create_table && $o->get('create-tables') ) {
      MKDEBUG && _d('Creating table');
      open my $fh, '<', $create_table
         or die "Cannot open $create_table: $OS_ERROR";
      $table_ddl = do { local $/ = undef; <$fh> };
      close $fh or warn "Cannot close $create_table: $OS_ERROR";

      # Don't let engine be undef.
      $engine = $args{tp}->get_engine($table_ddl) || '';

      if ( $o->get('fast-index') ) {
         ($table_ddl, $indexes_ddl)
            = $args{tp}->remove_secondary_indexes($table_ddl);
      }

      my @sql;
      push @sql, "USE `$db`";
      push @sql, 'SET SQL_LOG_BIN=0' unless $o->get('bin-log');
      push @sql, 'SET FOREIGN_KEY_CHECKS=0' unless $o->get('foreign-key-checks');
      push @sql, "DROP TABLE IF EXISTS `$db`.`$tbl`" if $o->get('drop-tables');
      push @sql, $table_ddl;
      _do($dbh, $dry_run, @sql);
      $bytes_done += $file_size->{$create_table};
   }

   _do($dbh, $dry_run, "LOCK TABLES `$db`.`$tbl` WRITE")
      if $o->get('lock-tables');
   _do($dbh, $dry_run, "TRUNCATE TABLE `$db`.`$tbl`")
      if $o->get('truncate');

   foreach my $file ( @files ) {

      # skip_finished_chunks() undefs files which are already restored
      next unless $file;

      # Make sure dbh is connected (it should be).
      $dbh ||= get_cxn(%args);

      # If restoring a new, "pure" dump, then $engine will already be set.
      # Else, we're restoring an old dump in which the table won't be created
      # until after the first file.  That means SHOW CREATE will fail on the
      # first file, work on the second file, and then we can get the engine.
      if ( !$engine ) {
         MKDEBUG && _d('Getting table ddl and engine');
         if ( !$dry_run ) {
            eval {
               $table_ddl = $dbh->selectall_arrayref("SHOW CREATE TABLE `$db`.`$tbl`")->[0]->[1];
            };
            MKDEBUG && $EVAL_ERROR && _d($EVAL_ERROR);
         }
         $engine = $args{tp}->get_engine($table_ddl || '') || '';
      }

      # Set options.
      my @sql;
      push @sql, "USE `$db`"; # For binary logging.

      push @sql, "/*!40000 ALTER TABLE `$db`.`$tbl` DISABLE KEYS */"
         if $o->get('disable-keys') && $engine eq 'MyISAM';

      push @sql, '/*!40101 SET SQL_MODE="NO_AUTO_VALUE_ON_ZERO" */'
         if $o->get('no-auto-value-on-0');

      push @sql, 'SET UNIQUE_CHECKS=0'
         unless $o->get('unique-checks');

      push @sql, 'SET FOREIGN_KEY_CHECKS=0'
         unless $o->get('foreign-key-checks');

      push @sql, 'SET SQL_LOG_BIN=0'
         unless $o->get('bin-log');

      if ( my $bibs = $o->get('bulk-insert-buffer-size') ) {
         push @sql, "SET SESSION bulk_insert_buffer_size=$bibs";
      }
      _do($dbh, $dry_run, @sql);

      # Restore the data.
      if ( filetype($file) eq 'sql' ) {
         $exit_status |= do_sql_file(
            dbh  => $dbh,
            file => $file,
            %args,
         );
      }
      else {
         if ( $file =~ m/\.gz$/ ) {
            if ( $o->get('fifo') ) {
               $fifo ||= makefifo($o);
               $exit_status
                  |= system_call($o, qq{gunzip --stdout '$file' > '$fifo' &});
               $load_from = $fifo;
            }
            else {
               $exit_status |= system_call($o, qq{gunzip '$file'});
               ( $load_from = $file ) =~ s/\.gz$//;
            }
         }
         else {
            $load_from = $file;
         }

         my $sql;
         my $charset = $o->get('charset');
         my $LOCAL   = $o->get('local') ? ' LOCAL' : '';
         my $OPT     = $o->get('ignore')  ? 'IGNORE'
                     : $o->get('replace') ? 'REPLACE'
                     : '';
         if ( $o->get('csv') ) {
            $sql  = qq{LOAD DATA$LOCAL INFILE /*done:$bytes_done $db\.$tbl*/ ? }
                  . qq{$OPT INTO TABLE `$db`.`$tbl` }
                  . qq{/*!50038 CHARACTER SET $charset */ }
                  . qq{FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\\"' }
                  . qq{LINES TERMINATED BY '\\n'};
         }
         elsif ( $o->get('tab') ) {
            $sql  = qq{LOAD DATA$LOCAL INFILE /*done:$bytes_done $db\.$tbl*/ ? }
                  . qq{$OPT INTO TABLE `$db`.`$tbl` }
                  . qq{/*!50038 CHARACTER SET $charset */};
         }

         if ( $sql ) {
            if ( $dry_run ) {
               print $sql, "\n";
            }
            else {
               eval {
                  $dbh->do($sql, {}, $load_from); 
               };
               if ( $EVAL_ERROR ) {
                  die mysql_error_msg($EVAL_ERROR)." while restoring $db.$tbl";
               }
               $bytes_done += $file_size->{$file};
            }
         }
         else {
            unlink $fifo if $fifo;
            die "I don't understand how to load file $file\n";
         }
      } # .txt tab file

      $dbh->commit() if $o->get('commit');

   } # each file

   if ( $dbh ) {
      my @sql;
      push @sql, "/*!40000 ALTER TABLE `$db`.`$tbl` ENABLE KEYS */"
         if $o->get('disable-keys') && $engine eq 'MyISAM';
      push @sql, 'UNLOCK TABLES'
         if $o->get('lock-tables');

      # Do InnoDB fast index creation.
      if ( $o->get('fast-index') && $indexes_ddl ) {
         push @sql, "ALTER TABLE `$db`.`$tbl` $indexes_ddl";
      }

      $exit_status |= _do($dbh, $dry_run, @sql);
   }

   unlink $fifo if $fifo && !$dry_run;
   $dbh->disconnect() if $dbh;

   return $exit_status;
}

# Execute sql statements in file through dbh->do() so that we can
# control things like SQL_LOG_BIN. Otherwise, we may replicate
# DROP TABLE statments.
# Returns 0 on success, 1 on failure (this is to mimic the exit
# status of older code).
sub do_sql_file {
   my ( %args ) = @_;
   foreach my $arg ( qw(o dbh file) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $o           = $args{o};
   my $dbh         = $args{dbh};
   my $file        = $args{file};
   my $decompress  = $o->get('decompress');
   my $exit_status = 0;

   MKDEBUG && _d('Restoring', $file);

   my $fh;
   if ( $file =~ m/\.gz/ ) {
      if ( !open $fh, '-|', "$decompress $file" ) {
         warn "Cannot $decompress $file: $OS_ERROR";
         return 1;
      }
   }
   else {
      if ( !open $fh, '<', "$args{file}" ) {
         warn "Cannot open $file: $OS_ERROR";
         return 1;
      }
   }

   local $INPUT_RECORD_SEPARATOR = ";\n";
   while ( my $sql = <$fh> ) {
      next if $sql =~ m/^$/;  # issue 625
      if ( $o->get('dry-run') ) {
         print $sql;
      }
      else {
         eval {
            $dbh->do($sql);
         };
         if ( $EVAL_ERROR ) {
            warn mysql_error_msg($EVAL_ERROR) . " while restoring $file";
            $exit_status |= 1;
         }
      } 
   }

   close $fh;
   return $exit_status;
}

# Undef files in $files_ref for which the rows in the corresponding
# chunk have already been restored.
# Returns the number of bytes "done" (already restored) in order to
# keep --progress accurate.
sub skip_finished_chunks {
   my ( $files, %args ) = @_;
   foreach my $arg ( qw(dbh db tbl tbl_chunks file_size o dp q tp) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $db        = $args{db};
   my $tbl       = $args{tbl};
   my $file_size = $args{file_size};
   my $o         = $args{o};
   my $chunks    = $args{tbl_chunks}->{$db}->{$tbl};
   my $q         = $args{q};
   my $dbh       = $args{dbh};
   my $tp        = $args{tp};

   my $db_tbl = $q->quote($db, $tbl);

   MKDEBUG && _d("Checking if restore of", $db_tbl, "can be resumed");

   if ( !defined $chunks ) {
      MKDEBUG && _d('Cannot resume restore: no chunks file');
      return 0;
   }

   if ( $chunks->[0] eq '1=1' ) {
      MKDEBUG && _d('Cannot resume restore: only 1 chunk (1=1)');
      return 0;
   }

   $dbh->do("USE `$db`");

   my $first_missing_chunk = 0;
   # First check that the table exists (issue 221).
   # If not, then we resume from chunk 0 which will contain
   # the create table def.
   if ( $tp->check_table(dbh=>$dbh, db=>$db, tbl=>$tbl) ) {
      # Table exists, so figure out the first missing chunk.
      foreach my $chunk ( @$chunks ) {
         my $select_chunk   = "SELECT 1 FROM $db_tbl WHERE ( $chunk ) LIMIT 1";
         my $chunk_restored = $dbh->selectall_arrayref($select_chunk);
         last if scalar @$chunk_restored == 0;
         $first_missing_chunk++;
      }
   }
   elsif ( MKDEBUG ) {
      _d("Restoring from chunk 0 because table", $db_tbl, "does not exist");
   }

   my $bytes_done = 0;
   if ( $first_missing_chunk ) {
      $first_missing_chunk -= 1 unless $o->get('atomic-resume');

      if ( defined $chunks->[$first_missing_chunk] ) {
         # We need to DELETE the first missing chunk otherwise we may try to
         # INSERT dupliate values.
         my @sql;
         push @sql, 'SET FOREIGN_KEY_CHECKS=0'
            unless $o->get('foreign-key-checks');
         push @sql, 'SET SQL_LOG_BIN=0'
            unless $o->get('bin-log');
         push @sql, "DELETE FROM $db_tbl WHERE $chunks->[$first_missing_chunk]";
         _do($dbh, $o->get('dry-run'), @sql);
      }

      my $first_file = 0;
      my $last_file  = $first_missing_chunk - 1;
      if ( $files->[0] =~ m/00_$tbl\.sql$/ ) {
         $first_file  = 1;
         $last_file  += 1;
         $files->[0]  = undef;
      }
      MKDEBUG && _d('First chunk file', $first_file, $files->[$first_file]);
      foreach my $file ( @$files[$first_file..$last_file] ) {
         $bytes_done += $file_size->{$file};
         $file = undef;
      }
   }

   MKDEBUG && _d('Resuming restore of', $db_tbl, 'from chunk',
      $first_missing_chunk, 'with', $bytes_done, 'bytes already done;',
      scalar @$chunks, 'chunks; first missing chunk:',
      $chunks->[$first_missing_chunk]);

   return $bytes_done;
}

# The following 2 subs allow us a much finer gradient of progress reporting.
# However, a little magick has to be wielded to insure smooth operation.
# Above, in the main loop there is a "reap" and a "sleep" progress report.
# For both, the recorded bytes done + bytes repoted via the processlist are
# reported. For the reap report, this is not problematic except that it
# doesn't happen often enough. On really big tables, we would go a long
# time without a reap report. Therefore, we must also do sleep reports which
# are printed about once every second. These give us the gradient of
# reporting that we want. However, sleep reports cause another problem.
# Occasionally, they'll report less bytes done than the previous report
# because the bytes done seen via the proclist increase and decrease.
# Mostly, they increase, but occasionally a sleep report will catch a
# bunch of new children who haven't done anything yet so their bytes
# done compared to all the children that just finished is much less.
# This is why we return -1 in the sub below and don't print a report.
sub bytes_done_from_processlist {
   my ( $dbh ) = @_;
   my $bytes_done = 0;

   my $proclist = $dbh->selectall_arrayref('SHOW PROCESSLIST');
   foreach my $proc ( @$proclist ) {
      my $info = $proc->[7] || '';
      my ( $done ) = $info =~ /LOAD DATA.+\/\*done:(\d+)\b/;
      $done ||= 0;
      $bytes_done += $done;
   }

   return -1 if ($bytes_done <= $last_bytes_done);
   $last_bytes_done = $bytes_done;

   return $bytes_done;
}

sub print_progress_report {
   my ( $o, $done, $dbh, $bytes, $start ) = @_;

   my $done_from_proclist
      =  defined $dbh ? bytes_done_from_processlist($dbh) : 0;
   return if $done_from_proclist < 0;

   my $done_and_doing = $done + $done_from_proclist;
   my $pct            = $done_and_doing / $bytes;
   my $now            = time();
   my $remaining      = ($now - $start) / $pct;

   info($o, 1, sprintf("done: %s/%s %6.2f%% %s remain (%s)",
        shorten($done_and_doing), shorten($bytes), $pct * 100,
        secs_to_time($remaining), ts($now + $remaining)));

   return;
}

sub filetype {
   my ( $filename ) = @_;
   my ( $type ) = $filename =~ m/\.(sql|txt|csv)(?:\.\d+)?(?:\.gz)?$/;
   return $type || '';
}

sub get_cxn {
   my ( %args ) = @_;
   foreach my $arg ( qw(o dp) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $o  = $args{o};
   my $dp = $args{dp};

   # DSNParser will interpret D has the default database for the connection,
   # but in this script D means the database into which all files are loaded.
   # Therefore, we must get the opt values and manually remove D.
   my $dsn_defaults = $dp->parse_options($o);
   my $dsn   = $args{dsn} ? $dp->parse($args{dsn}, $dsn_defaults)
             :              $dsn_defaults;
   $dsn->{D} = undef;
   my $dbh   = $dp->get_dbh($dp->get_cxn_params($dsn));

   if ( my $charset = $o->get('charset') ) {
      $dbh->do("/*!40101 SET character_set_database=$charset */");
   }

   return $dbh;
}

sub system_call {
   my ( $o, @cmd ) = @_;
   my $exit_status = 0;
   if ( $o->get('dry-run') ) {
      print join(' ', @cmd), "\n";
   }
   else {
      $exit_status = system(join(' ', @cmd));
      # Must right-shift to get the actual exit status of the command.
      # Otherwise the upstream exit() call that's about to happen will get a
      # larger value than it likes, and will just report zero to waitpid().
      $exit_status = $exit_status >> 8;
   }
   return $exit_status;
}

# Executes $dbh->do() for each statement, unless $dry_run in which case
# the statements are just printed.  This could be accomplished by subclassing
# DBI, but this is the quick and easy solution.
sub _do {
   my ( $dbh, $dry_run, @statements ) = @_;
   my $retval = 0;
   eval {
      foreach my $sql ( @statements ) {
         next unless $sql;
         MKDEBUG && _d($sql);
         if ( $dry_run ) {
            print "$sql\n"
         }
         else {
            $dbh->do($sql);
         }
      }
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($EVAL_ERROR);
      warn $EVAL_ERROR;
      $retval |= 1;
   }
   return $retval;
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
# Documentation.
# ############################################################################

=pod

=head1 NAME

mk-parallel-restore - (DEPRECATED) Load files into MySQL in parallel.

=head1 SYNOPSIS

This tool is deprecated because after several complete redesigns, we concluded
that Perl is the wrong technology for this task.  Read L<"RISKS"> before you use
it, please.  It remains useful for some people who we know aren't depending on
it in production, and therefore we are not removing it from the distribution.

Usage: mk-parallel-restore [OPTION...] [DSN] PATH [PATH...]

mk-parallel-restore description loads files into MySQL in parallel to make some
type of data loads faster.  IT IS NOT A BACKUP TOOL!

  mk-parallel-restore /path/to/files
  mk-parallel-restore --tab /path/to/files

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

mk-parallel-restore is not a backup program!  It is only for fast data imports,
for purposes such as loading test data into a system quickly.  Do not use
mk-parallel-restore for backups.  mk-parallel-restore inserts data unless you
use the L<"--dry-run"> option.

At the time of this release, there is a bug that prevents huge statements from
being printed when an error is encountered, a bug applying
L<"--[no]foreign-key-checks"> when truncating tables, and a bug with LOAD
DATA LOCAL.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-parallel-restore>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

mk-parallel-restore is a way to load SQL or delimited-file dumps into MySQL
in parallel at high speed.  It is especially designed for restoring files
dumped by L<mk-parallel-dump>.  It automatically
detects whether a file contains SQL or delimited data from the filename
extension, and either shells out to C<mysql> or executes C<LOAD DATA INFILE>
with the file.  On UNIX-like systems, it will even make a FIFO to decompress
gzipped files for C<LOAD DATA INFILE>.

By default it discovers all files in the directory you specify on the command
line.  It uses the file's parent directory as the database name and the file's
name (up to the first dot) as the table name.  It can deal with files named
like the following:

  dir/tbl.sql
  dir/tbl.txt
  dir/tbl.csv

It is also happy with files that look like this, where C<EXT> is one of the
extensions just listed.

  dir/tbl.EXT.000
  dir/tbl.EXT.000.gz

By default, it loads C<SQL> files first, if they exist, then loads C<CSV> or
C<TXT> files next, in order of the numbers in the filename extension as just
shown.  This makes it easy for you to reload a table's definition followed by
its data, in case you dumped them into separate files (as happens with
C<mysqldump>'s C<--tab> option).  See L<mk-parallel-dump> for details on how
data is dumped.

Exit status is 0 if everything went well, 1 if any files failed, and any
other value indicates an internal error.

=head1 OUTPUT

Output depends on verbosity.  When L<"--dry-run"> is given, output includes
commands that would be executed.

When L<"--verbose"> is 0, there is normally no output unless there's an error.

When L<"--verbose"> is 1, there is one line of output for the entire job,
showing how many tables were processed, how many files were loaded with what
status, how much time elapsed, and how much time the parallel load jobs added
up to.  If any files were skipped, the filenames are printed to the output.

When L<"--verbose"> is 2, there's one line of output per table, showing extra
data such as how many threads were running when each table finished loading:

  DATABASE TABLE            FILES  TIME STATUS THREADS
  sakila   language             2  0.07      0       2
  sakila   film_actor           2  0.07      0       2
  sakila   actor                2  0.06      0       2
  sakila   payment              2  0.07      0       2
  sakila   transport_backup     2  0.05      0       2
  sakila   country              2  0.08      0       2
  sakila   film                 2  0.05      0       2
  sakila   rental               2  0.07      0       2

=head1 SPEED OF PARALLEL LOADING

User-contributed benchmarks are welcome.  See
L<http://www.paragon-cs.com/wordpress/?p=52> for one user's experiences.

=head1 OPTIONS

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --ask-pass

Prompt for a password when connecting to MySQL.

=item --[no]atomic-resume

default: yes

Treat chunks as atomic when resuming restore.

By default C<mk-parallel-restore> resumes restoration from the first chunk that
is missing all its rows.  For dumps of transactionally-safe tables (InnoDB),
it cannot happen that a chunk is only partially restored.  Therefore, restoring 
from the first missing chunk is safe.

However, for dumps of non-transactionally safe tables, it is possible that a
chunk can be only partially restored.  In such cases, the chunk will wrongly
appear to be fully restored.  Therefore, you must specify C<--no-atomic-resume>
so that the partially restored chunk is fully restored.

=item --base-dir

type: string

Directory where FIFO files will be created.

=item --[no]biggest-first

default: yes

Restore the biggest tables first for highest concurrency.

=item --[no]bin-log

default: yes

Enable binary logging (C<SET SQL_LOG_BIN=1>).

Restore operations are replicated by default (SQL_LOG_BIN=1) except for
L<"--tab"> restores which are not replicated by default (SQL_LOG_BIN=0).
This prevents large loads from being logged to the server's binary log.

The value given on the command line overrides the defaults.  Therefore,
specifying C<--bin-log> with L<"--tab"> will allow the L<"--tab"> restore
to replicate.

=item --bulk-insert-buffer-size

type: int

Set bulk_insert_buffer_size before each C<LOAD DATA INFILE>.

Has no effect without L<"--tab">.

=item --charset

short form: -A; type: string; default: BINARY

Sets the connection, database, and C<LOAD DATA INFILE> character set.

The default is C<BINARY>, which is the safest value to use for C<LOAD DATA
INFILE>.  Has no effect without L<"--tab">.

=item --[no]commit

default: yes

Commit after each file.

=item --config

type: Array

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --create-databases

Create databases if they don't exist.

=item --[no]create-tables

default: yes

Create tables.

See also L<"--[no]drop-tables">.

=item --csv

Files are in CSV format (implies L<"--tab">).

Changes L<"--tab"> options so the following C<LOAD DATA INFILE> statement is used:

   LOAD DATA INFILE <filename> INTO TABLE <table>
   FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'
   LINES TERMINATED BY '\n';

=item --database

short form: -D; type: string

Load all files into this database.

Overrides the database which is normally specified by the directory in which the
files live.  Does I<not> specify a default database for the connection.

=item --databases

short form: -d; type: hash

Restore only this comma-separated list of databases.

=item --databases-regex

type: string

Restore only databases whose names match this regex.

=item --decompress

type: string; default: gzip -d -c

Command used to decompress and print .gz files to STDOUT (like zcat).

=item --defaults-file

short form: -F; type: string

Only read mysql options from the given file.  You must give an absolute
pathname.

=item --[no]disable-keys

default: yes

Execute C<ALTER TABLE DISABLE KEYS> before each MyISAM table.

This option only works with MyISAM tables.

=item --[no]drop-tables

default: yes

Execute C<DROP TABLE IF EXISTS> before creating each table.

=item --dry-run

Print commands instead of executing them.

=item --fast-index

Do InnoDB plugin fast index creation by restoring secondary indexes after data.

This option only works with InnoDB tables and the InnoDB plugin.

=item --[no]fifo

default: yes

Stream files into a FIFO for L<"--tab">.

Load compressed tab-separated files by piping them into a FIFO and using the
FIFO with C<LOAD DATA INFILE>, instead of by decompressing the files on disk.
Sets L<"--umask"> to 0.

=item --[no]foreign-key-checks

default: yes

Set C<FOREIGN_KEY_CHECKS=1> before C<LOAD DATA INFILE>.

=item --help

Show help and exit.

=item --host

short form: -h; type: string

Connect to host.

=item --ignore

Adds the C<IGNORE> modifier to C<LOAD DATA INFILE>.

=item --ignore-databases

type: Hash

Ignore this comma-separated list of databases.

=item --ignore-tables

type: Hash

Ignore this comma-separated list of table names.

Table names may be qualified with the database name.

=item --local

Uses the C<LOCAL> option to C<LOAD DATA INFILE>.

If you enable this option, the files are read locally by the client library, not
by the server.

=item --[no]lock-tables

Lock tables before C<LOAD DATA INFILE>.

=item --[no]no-auto-value-on-0

default: yes

Set SQL C<NO_AUTO_VALUE_ON_ZERO>.

=item --only-empty-databases

Restore only to empty databases.

By default mk-parallel-restore will restore tables into a database so long
as it exists (or is created by L<"--create-databases">).  This option is
a safety feature that prevents any tables from being restored into a database
that already has tables even if those tables are the same ones being restored.
If you specify this option, every database must have zero tables.

This implicitly disables L<"--[no]resume">.  L<"--create-databases"> will work
if the database doesn't already exist and it creates it.

The databases are checked after all filters (L<"--databases">, etc.)

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

=item --progress

Display progress messages.

Progress is displayed each time a table finishes loading.  Progress is
calculated by measuring the size of each file to be loaded, and assuming all
bytes are created equal.  The output is the completed and total size, the
percent completed, estimated time remaining, and estimated completion time.

=item --quiet

short form: -q

Sets L<"--verbose"> to 0.

=item --replace

Adds the C<REPLACE> modifier to C<LOAD DATA INFILE>.

=item --[no]resume

default: yes

Resume the restore from a previously incomplete restore.

By default, C<mk-parallel-restore> checks each table's chunks for existing
rows and restores only from the point where a previous restore stopped.
Specify L<--no-resume> to disable restore resumption and fully restores every
table.

Restore resumption does not work with tab-separated files or dumps that were
not chunked.

=item --set-vars

type: string; default: wait_timeout=10000

Set these MySQL variables.  Immediately after connecting to MySQL, this
string will be appended to SET and executed.

=item --socket

short form: -S; type: string

Socket file to use for connection.

=item --tab

Load tab-separated files with C<LOAD DATA INFILE>.

This is similar to what C<mysqlimport> does, but more flexible.

The following options are enabled unless they are specifically disabled
on the command line:

   L<"--commit">
   L<"--[no]disable-keys">
   L<"--[no]no-auto-value-on-0">

And the following options are disabled (C<--no-bin-log>, etc.) unless they
are specifically enabled on the command line:

   L<"--[no]bin-log">
   L<"--[no]unique-checks">
   L<"--[no]foreign-key-checks">

=item --tables

short form: -t; type: hash

Restore only this comma-separated list of table names.

Table names may be qualified with the database name.

=item --tables-regex

type: string

Restore only tables whose names match this regex.

=item --threads

type: int; default: 2

Specifies the number of parallel processes to run.

The default is 2 (this is mk-parallel-restore after all -- 1 is not parallel).
On GNU/Linux machines, the default is the number of times 'processor' appears in
F</proc/cpuinfo>.  On Windows, the default is read from the environment.  In any
case, the default is at least 2, even when there's only a single processor.

=item --truncate

Run C<TRUNCATE TABLE> before C<LOAD DATA INFILE>.

This will delete all rows from a table before loading the first tab-delimited
file into it.

=item --umask

type: string

Set the program's C<umask> to this octal value.

This is useful when you want created files (such as FIFO files) to be readable
or writable by other users (for example, the MySQL server itself).

=item --[no]unique-checks

default: yes

Set C<UNIQUE_CHECKS=1> before C<LOAD DATA INFILE>.

=item --user

short form: -u; type: string

User for login if not current user.

=item --verbose

short form: -v; cumulative: yes; default: 1

Verbosity; can specify multiple times.

Repeatedly specifying it increments the verbosity.  Default is 1 if not
specified.  See L<"OUTPUT">.

=item --version

Show version and exit.

=item --wait

short form: -w; type: time; default: 5m

Wait limit when server is down.

If the MySQL server crashes during loading, waits until the server comes back
and then continues with the rest of the files.  C<mk-parallel-restore> will
check the server every second until this time is exhausted, at which point it
will give up and exit.

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

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-parallel-restore>.

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

See also L<mk-parallel-dump>.

=head1 AUTHOR

Baron Schwartz

=head1 ABOUT MAATKIT

This tool is part of Maatkit, a toolkit for power users of MySQL.  Maatkit
was created by Baron Schwartz; Baron and Daniel Nichter are the primary
code contributors.  Both are employed by Percona.  Financial support for
Maatkit development is primarily provided by Percona and its clients. 

=head1 VERSION

This manual page documents Ver 1.0.24 Distrib 7540 $Revision: 7477 $.

=cut

__END__
:endofperl
