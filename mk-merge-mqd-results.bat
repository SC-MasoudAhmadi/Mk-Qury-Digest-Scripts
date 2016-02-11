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

# This program is copyright 2010 Percona Inc.
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
# QueryReportFormatter package 7274
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/QueryReportFormatter.pm
#   trunk/common/t/QueryReportFormatter.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package QueryReportFormatter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use POSIX qw(floor);

Transformers->import(qw(
   shorten micro_t parse_timestamp unix_timestamp make_checksum percentage_of
   crc32
));

use constant MKDEBUG           => $ENV{MKDEBUG} || 0;
use constant LINE_LENGTH       => 74;
use constant MAX_STRING_LENGTH => 10;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(OptionParser QueryRewriter Quoter) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   my $label_width = $args{label_width} || 12;
   MKDEBUG && _d('Label width:', $label_width);

   my $cheat_width = $label_width + 1;

   my $self = {
      %args,
      label_width    => $label_width,
      num_format     => "# %-${label_width}s %3s %7s %7s %7s %7s %7s %7s %7s",
      bool_format    => "# %-${label_width}s %3d%% yes, %3d%% no",
      string_format  => "# %-${label_width}s %s",
      global_headers => [qw(    total min max avg 95% stddev median)],
      event_headers  => [qw(pct total min max avg 95% stddev median)],
      hidden_attrib  => {   # Don't sort/print these attribs in the reports.
         arg         => 1, # They're usually handled specially, or not
         fingerprint => 1, # printed at all.
         pos_in_log  => 1,
         ts          => 1,
      },
   };
   return bless $self, $class;
}

sub set_report_formatter {
   my ( $self, %args ) = @_;
   my @required_args = qw(report formatter);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless exists $args{$arg};
   }
   my ($report, $formatter) = @args{@required_args};
   $self->{formatter_for}->{$report} = $formatter;
   return;
}

sub print_reports {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(reports ea worst orderby groupby) ) {
      die "I need a $arg argument" unless exists $args{$arg};
   }
   my $reports = $args{reports};
   my $group   = $args{group};
   my $last_report;

   foreach my $report ( @$reports ) {
      MKDEBUG && _d('Printing', $report, 'report'); 
      my $report_output = $self->$report(%args);
      if ( $report_output ) {
         print "\n"
            if !$last_report || !($group->{$last_report} && $group->{$report});
         print $report_output;
      }
      else {
         MKDEBUG && _d('No', $report, 'report');
      }
      $last_report = $report;
   }

   return;
}

sub rusage {
   my ( $self ) = @_;
   my ( $rss, $vsz, $user, $system ) = ( 0, 0, 0, 0 );
   my $rusage = '';
   eval {
      my $mem = `ps -o rss,vsz -p $PID 2>&1`;
      ( $rss, $vsz ) = $mem =~ m/(\d+)/g;
      ( $user, $system ) = times();
      $rusage = sprintf "# %s user time, %s system time, %s rss, %s vsz\n",
         micro_t( $user,   p_s => 1, p_ms => 1 ),
         micro_t( $system, p_s => 1, p_ms => 1 ),
         shorten( ($rss || 0) * 1_024 ),
         shorten( ($vsz || 0) * 1_024 );
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d($EVAL_ERROR);
   }
   return $rusage ? $rusage : "# Could not get rusage\n";
}

sub date {
   my ( $self ) = @_;
   return "# Current date: " . (scalar localtime) . "\n";
}

sub hostname {
   my ( $self ) = @_;
   my $hostname = `hostname`;
   if ( $hostname ) {
      chomp $hostname;
      return "# Hostname: $hostname\n";
   }
   return;
}

sub files {
   my ( $self, %args ) = @_;
   if ( $args{files} ) {
      return "# Files: " . join(', ', @{$args{files}}) . "\n";
   }
   return;
}

sub header {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ea orderby) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $ea      = $args{ea};
   my $orderby = $args{orderby};
   my $results = $ea->results();
   my @result;

   my $global_cnt = $results->{globals}->{$orderby}->{cnt} || 0;

   my ($qps, $conc) = (0, 0);
   if ( $global_cnt && $results->{globals}->{ts}
      && ($results->{globals}->{ts}->{max} || '')
         gt ($results->{globals}->{ts}->{min} || '')
   ) {
      eval {
         my $min  = parse_timestamp($results->{globals}->{ts}->{min});
         my $max  = parse_timestamp($results->{globals}->{ts}->{max});
         my $diff = unix_timestamp($max) - unix_timestamp($min);
         $qps     = $global_cnt / ($diff || 1);
         $conc    = $results->{globals}->{$args{orderby}}->{sum} / $diff;
      };
   }

   MKDEBUG && _d('global_cnt:', $global_cnt, 'unique:',
      scalar keys %{$results->{classes}}, 'qps:', $qps, 'conc:', $conc);
   my $line = sprintf(
      '# Overall: %s total, %s unique, %s QPS, %sx concurrency ',
      shorten($global_cnt, d=>1_000),
      shorten(scalar keys %{$results->{classes}}, d=>1_000),
      shorten($qps  || 0, d=>1_000),
      shorten($conc || 0, d=>1_000));
   $line .= ('_' x (LINE_LENGTH - length($line) + $self->{label_width} - 12));
   push @result, $line;

   if ( my $ts = $results->{globals}->{ts} ) {
      my $time_range = $self->format_time_range($ts) || "unknown";
      push @result, "# Time range: $time_range";
   }

   push @result, $self->make_global_header();

   my $attribs = $self->sort_attribs(
      ($args{select} ? $args{select} : $ea->get_attributes()),
      $ea,
   );

   foreach my $type ( qw(num innodb) ) {
      if ( $type eq 'innodb' && @{$attribs->{$type}} ) {
         push @result, "# InnoDB:";
      };

      NUM_ATTRIB:
      foreach my $attrib ( @{$attribs->{$type}} ) {
         next unless exists $results->{globals}->{$attrib};
         
         my $store   = $results->{globals}->{$attrib};
         my $metrics = $ea->stats()->{globals}->{$attrib};
         my $func    = $attrib =~ m/time|wait$/ ? \&micro_t : \&shorten;
         my @values  = ( 
            @{$store}{qw(sum min max)},
            $store->{sum} / $store->{cnt},
            @{$metrics}{qw(pct_95 stddev median)},
         );
         @values = map { defined $_ ? $func->($_) : '' } @values;

         push @result,
            sprintf $self->{num_format},
               $self->make_label($attrib), '', @values;
      }
   }

   if ( @{$attribs->{bool}} ) {
      push @result, "# Boolean:";
      my $printed_bools = 0;
      BOOL_ATTRIB:
      foreach my $attrib ( @{$attribs->{bool}} ) {
         next unless exists $results->{globals}->{$attrib};

         my $store = $results->{globals}->{$attrib};
         if ( $store->{sum} > 0 || $args{zero_bool} ) { 
            push @result,
               sprintf $self->{bool_format},
                  $self->make_label($attrib), $self->bool_percents($store);
            $printed_bools = 1;
         }
      }
      pop @result unless $printed_bools;
   }

   return join("\n", map { s/\s+$//; $_ } @result) . "\n";
}

sub query_report {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ea worst orderby groupby) ) {
      die "I need a $arg argument" unless defined $arg;
   }
   my $ea      = $args{ea};
   my $groupby = $args{groupby};
   my $worst   = $args{worst};

   my $o   = $self->{OptionParser};
   my $q   = $self->{Quoter};
   my $qv  = $self->{QueryReview};
   my $qr  = $self->{QueryRewriter};

   my $report = '';

   if ( $args{print_header} ) {
      $report .= "# " . ( '#' x 72 ) . "\n"
               . "# Report grouped by $groupby\n"
               . '# ' . ( '#' x 72 ) . "\n\n";
   }

   my $attribs = $self->sort_attribs(
      ($args{select} ? $args{select} : $ea->get_attributes()),
      $ea,
   );

   ITEM:
   foreach my $top_event ( @$worst ) {
      my $item       = $top_event->[0];
      my $reason     = $args{explain_why} ? $top_event->[1] : '';
      my $rank       = $top_event->[2];
      my $stats      = $ea->results->{classes}->{$item};
      my $sample     = $ea->results->{samples}->{$item};
      my $samp_query = $sample->{arg} || '';

      my $review_vals;
      if ( $qv ) {
         $review_vals = $qv->get_review_info($item);
         next ITEM if $review_vals->{reviewed_by} && !$o->get('report-all');
      }

      my ($default_db) = $sample->{db}       ? $sample->{db}
                       : $stats->{db}->{unq} ? keys %{$stats->{db}->{unq}}
                       :                       undef;
      my @tables;
      if ( $o->get('for-explain') ) {
         @tables = $self->{QueryParser}->extract_tables(
            query      => $samp_query,
            default_db => $default_db,
            Quoter     => $self->{Quoter},
         );
      }

      $report .= "\n" if $rank > 1;  # space between each event report
      $report .= $self->event_report(
         %args,
         item    => $item,
         sample  => $sample,
         rank    => $rank,
         reason  => $reason,
         attribs => $attribs,
         db      => $default_db,
      );

      if ( $o->get('report-histogram') ) {
         $report .= $self->chart_distro(
            %args,
            attrib => $o->get('report-histogram'),
            item   => $item,
         );
      }

      if ( $qv && $review_vals ) {
         $report .= "# Review information\n";
         foreach my $col ( $qv->review_cols() ) {
            my $val = $review_vals->{$col};
            if ( !$val || $val ne '0000-00-00 00:00:00' ) { # issue 202
               $report .= sprintf "# %13s: %-s\n", $col, ($val ? $val : '');
            }
         }
      }

      if ( $groupby eq 'fingerprint' ) {
         $samp_query = $qr->shorten($samp_query, $o->get('shorten'))
            if $o->get('shorten');

         $report .= "# Fingerprint\n#    $item\n"
            if $o->get('fingerprints');

         $report .= $self->tables_report(@tables)
            if $o->get('for-explain');

         if ( $samp_query && ($args{variations} && @{$args{variations}}) ) {
            my $crc = crc32($samp_query);
            $report.= "# CRC " . ($crc ? $crc % 1_000 : "") . "\n";
         }

         my $log_type = $args{log_type} || '';
         my $mark     = $log_type eq 'memcached'
                     || $log_type eq 'http'
                     || $log_type eq 'pglog' ? '' : '\G';

         if ( $item =~ m/^(?:[\(\s]*select|insert|replace)/ ) {
            if ( $item =~ m/^(?:insert|replace)/ ) { # No EXPLAIN
               $report .= "$samp_query${mark}\n";
            }
            else {
               $report .= "# EXPLAIN /*!50100 PARTITIONS*/\n$samp_query${mark}\n"; 
               $report .= $self->explain_report($samp_query, $default_db);
            }
         }
         else {
            $report .= "$samp_query${mark}\n"; 
            my $converted = $qr->convert_to_select($samp_query);
            if ( $o->get('for-explain')
                 && $converted
                 && $converted =~ m/^[\(\s]*select/i ) {
               $report .= "# Converted for EXPLAIN\n# EXPLAIN /*!50100 PARTITIONS*/\n$converted${mark}\n";
            }
         }
      }
      else {
         if ( $groupby eq 'tables' ) {
            my ( $db, $tbl ) = $q->split_unquote($item);
            $report .= $self->tables_report([$db, $tbl]);
         }
         $report .= "$item\n";
      }
   }

   return $report;
}

sub event_report {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ea item orderby) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $ea      = $args{ea};
   my $item    = $args{item};
   my $orderby = $args{orderby};
   my $results = $ea->results();
   my $o       = $self->{OptionParser};
   my @result;

   my $store = $results->{classes}->{$item};
   return "# No such event $item\n" unless $store;

   my $global_cnt = $results->{globals}->{$orderby}->{cnt};
   my $class_cnt  = $store->{$orderby}->{cnt};

   my ($qps, $conc) = (0, 0);
   if ( $global_cnt && $store->{ts}
      && ($store->{ts}->{max} || '')
         gt ($store->{ts}->{min} || '')
   ) {
      eval {
         my $min  = parse_timestamp($store->{ts}->{min});
         my $max  = parse_timestamp($store->{ts}->{max});
         my $diff = unix_timestamp($max) - unix_timestamp($min);
         $qps     = $class_cnt / $diff;
         $conc    = $store->{$orderby}->{sum} / $diff;
      };
   }

   my $line = sprintf(
      '# %s %d: %s QPS, %sx concurrency, ID 0x%s at byte %d ',
      ($ea->{groupby} eq 'fingerprint' ? 'Query' : 'Item'),
      $args{rank} || 0,
      shorten($qps  || 0, d=>1_000),
      shorten($conc || 0, d=>1_000),
      make_checksum($item),
      $results->{samples}->{$item}->{pos_in_log} || 0,
   );
   $line .= ('_' x (LINE_LENGTH - length($line) + $self->{label_width} - 12));
   push @result, $line;

   if ( $args{reason} ) {
      push @result,
         "# This item is included in the report because it matches "
            . ($args{reason} eq 'top' ? '--limit.' : '--outliers.');
   }

   {
      my $query_time = $ea->metrics(where => $item, attrib => 'Query_time');
      push @result,
         sprintf("# Scores: Apdex = %s [%3.1f]%s, V/M = %.2f",
            (defined $query_time->{apdex} ? "$query_time->{apdex}" : "NS"),
            ($query_time->{apdex_t} || 0),
            ($query_time->{cnt} < 100 ? "*" : ""),
            ($query_time->{stddev}**2 / ($query_time->{avg} || 1)),
         );
   }

   if ( $o->get('explain') && $results->{samples}->{$item}->{arg} ) {
      eval {
         my $sparkline = $self->explain_sparkline(
            $results->{samples}->{$item}->{arg}, $args{db});
         push @result, "# EXPLAIN sparkline: $sparkline\n";
      };
      if ( $EVAL_ERROR ) {
         MKDEBUG && _d("Failed to get EXPLAIN sparkline:", $EVAL_ERROR);
      }
   }

   if ( my $attrib = $o->get('report-histogram') ) {
      my $sparkline = $self->distro_sparkline(
         %args,
         attrib => $attrib,
         item   => $item,
      );
      if ( $sparkline ) {
         push @result, "# $attrib sparkline: |$sparkline|";
      }
   }

   if ( my $ts = $store->{ts} ) {
      my $time_range = $self->format_time_range($ts) || "unknown";
      push @result, "# Time range: $time_range";
   }

   push @result, $self->make_event_header();

   push @result,
      sprintf $self->{num_format}, 'Count',
         percentage_of($class_cnt, $global_cnt), $class_cnt, map { '' } (1..8);

   my $attribs = $args{attribs};
   if ( !$attribs ) {
      $attribs = $self->sort_attribs(
         ($args{select} ? $args{select} : $ea->get_attributes()),
         $ea
      );
   }

   foreach my $type ( qw(num innodb) ) {
      if ( $type eq 'innodb' && @{$attribs->{$type}} ) {
         push @result, "# InnoDB:";
      };

      NUM_ATTRIB:
      foreach my $attrib ( @{$attribs->{$type}} ) {
         next NUM_ATTRIB unless exists $store->{$attrib};
         my $vals = $store->{$attrib};
         next unless scalar %$vals;

         my $pct;
         my $func    = $attrib =~ m/time|wait$/ ? \&micro_t : \&shorten;
         my $metrics = $ea->stats()->{classes}->{$item}->{$attrib};
         my @values = (
            @{$vals}{qw(sum min max)},
            $vals->{sum} / $vals->{cnt},
            @{$metrics}{qw(pct_95 stddev median)},
         );
         @values = map { defined $_ ? $func->($_) : '' } @values;
         $pct   = percentage_of(
            $vals->{sum}, $results->{globals}->{$attrib}->{sum});

         push @result,
            sprintf $self->{num_format},
               $self->make_label($attrib), $pct, @values;
      }
   }

   if ( @{$attribs->{bool}} ) {
      push @result, "# Boolean:";
      my $printed_bools = 0;
      BOOL_ATTRIB:
      foreach my $attrib ( @{$attribs->{bool}} ) {
         next BOOL_ATTRIB unless exists $store->{$attrib};
         my $vals = $store->{$attrib};
         next unless scalar %$vals;

         if ( $vals->{sum} > 0 || $args{zero_bool} ) {
            push @result,
               sprintf $self->{bool_format},
                  $self->make_label($attrib), $self->bool_percents($vals);
            $printed_bools = 1;
         }
      }
      pop @result unless $printed_bools;
   }

   if ( @{$attribs->{string}} ) {
      push @result, "# String:";
      my $printed_strings = 0;
      STRING_ATTRIB:
      foreach my $attrib ( @{$attribs->{string}} ) {
         next STRING_ATTRIB unless exists $store->{$attrib};
         my $vals = $store->{$attrib};
         next unless scalar %$vals;

         push @result,
            sprintf $self->{string_format},
               $self->make_label($attrib),
               $self->format_string_list($attrib, $vals, $class_cnt);
         $printed_strings = 1;
      }
      pop @result unless $printed_strings;
   }

   return join("\n", map { s/\s+$//; $_ } @result) . "\n";
}

sub chart_distro {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ea item attrib) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $ea     = $args{ea};
   my $item   = $args{item};
   my $attrib = $args{attrib};

   my $results = $ea->results();
   my $store   = $results->{classes}->{$item}->{$attrib};
   my $vals    = $store->{all};
   return "" unless defined $vals && scalar %$vals;

   my @buck_tens = $ea->buckets_of(10);
   my @distro = map { 0 } (0 .. 7);

   my @buckets = map { 0 } (0..999);
   map { $buckets[$_] = $vals->{$_} } keys %$vals;
   $vals = \@buckets;  # repoint vals from given hashref to our array

   map { $distro[$buck_tens[$_]] += $vals->[$_] } (1 .. @$vals - 1);

   my $vals_per_mark; # number of vals represented by 1 #-mark
   my $max_val        = 0;
   my $max_disp_width = 64;
   my $bar_fmt        = "# %5s%s";
   my @distro_labels  = qw(1us 10us 100us 1ms 10ms 100ms 1s 10s+);
   my @results        = "# $attrib distribution";

   foreach my $n_vals ( @distro ) {
      $max_val = $n_vals if $n_vals > $max_val;
   }
   $vals_per_mark = $max_val / $max_disp_width;

   foreach my $i ( 0 .. $#distro ) {
      my $n_vals  = $distro[$i];
      my $n_marks = $n_vals / ($vals_per_mark || 1);

      $n_marks = 1 if $n_marks < 1 && $n_vals > 0;

      my $bar = ($n_marks ? '  ' : '') . '#' x $n_marks;
      push @results, sprintf $bar_fmt, $distro_labels[$i], $bar;
   }

   return join("\n", @results) . "\n";
}


sub distro_sparkline {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ea item attrib) ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my $ea     = $args{ea};
   my $item   = $args{item};
   my $attrib = $args{attrib};

   my $results = $ea->results();
   my $store   = $results->{classes}->{$item}->{$attrib};
   my $vals    = $store->{all};

   my $all_zeros_sparkline = " " x 8;

   return $all_zeros_sparkline unless defined $vals && scalar %$vals;

   my @buck_tens      = $ea->buckets_of(10);
   my @distro         = map { 0 } (0 .. 7);
   my @buckets        = map { 0 } (0..999);
   map { $buckets[$_] = $vals->{$_} } keys %$vals;
   $vals = \@buckets;
   map { $distro[$buck_tens[$_]] += $vals->[$_] } (1 .. @$vals - 1);

   my $vals_per_mark;
   my $max_val        = 0;
   my $max_disp_width = 64;
   foreach my $n_vals ( @distro ) {
      $max_val = $n_vals if $n_vals > $max_val;
   }
   $vals_per_mark = $max_val / $max_disp_width;

   my ($min, $max);
   foreach my $i ( 0 .. $#distro ) {
      my $n_vals  = $distro[$i];
      my $n_marks = $n_vals / ($vals_per_mark || 1);
      $n_marks    = 1 if $n_marks < 1 && $n_vals > 0;

      $min = $n_marks if $n_marks && (!$min || $n_marks < $min);
      $max = $n_marks if !$max || $n_marks > $max;
   }
   return $all_zeros_sparkline unless $min && $max;


   $min = 0 if $min == $max;
   my @range_min;
   my $d = floor(($max-$min) / 4);
   for my $x ( 1..4 ) {
      push @range_min, $min + ($d * $x);
   }

   my $sparkline = ""; 
   foreach my $i ( 0 .. $#distro ) {
      my $n_vals  = $distro[$i];
      my $n_marks = $n_vals / ($vals_per_mark || 1);
      $n_marks    = 1 if $n_marks < 1 && $n_vals > 0;
      $sparkline .= $n_marks <= 0             ? ' '
                  : $n_marks <= $range_min[0] ? '_'
                  : $n_marks <= $range_min[1] ? '.'
                  : $n_marks <= $range_min[2] ? '-'
                  :                             '^';
   }

   return $sparkline;
}

sub profile {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ea worst groupby) ) {
      die "I need a $arg argument" unless defined $arg;
   }
   my $ea      = $args{ea};
   my $worst   = $args{worst};
   my $other   = $args{other};
   my $groupby = $args{groupby};

   my $qr  = $self->{QueryRewriter};
   my $o   = $self->{OptionParser};

   my $results = $ea->results();
   my $total_r = $results->{globals}->{Query_time}->{sum} || 0;

   my @profiles;
   foreach my $top_event ( @$worst ) {
      my $item       = $top_event->[0];
      my $rank       = $top_event->[2];
      my $stats      = $ea->results->{classes}->{$item};
      my $sample     = $ea->results->{samples}->{$item};
      my $samp_query = $sample->{arg} || '';
      my $query_time = $ea->metrics(where => $item, attrib => 'Query_time');

      my %profile    = (
         rank   => $rank,
         r      => $stats->{Query_time}->{sum},
         cnt    => $stats->{Query_time}->{cnt},
         sample => $groupby eq 'fingerprint' ?
                    $qr->distill($samp_query, %{$args{distill_args}}) : $item,
         id     => $groupby eq 'fingerprint' ? make_checksum($item)   : '',
         vmr    => ($query_time->{stddev}**2) / ($query_time->{avg} || 1),
         apdex  => defined $query_time->{apdex} ? $query_time->{apdex} : "NS",
      ); 

      if ( $o->get('explain') && $samp_query ) {
         my ($default_db) = $sample->{db}       ? $sample->{db}
                          : $stats->{db}->{unq} ? keys %{$stats->{db}->{unq}}
                          :                       undef;
         eval {
            $profile{explain_sparkline} = $self->explain_sparkline(
               $samp_query, $default_db);
         };
         if ( $EVAL_ERROR ) {
            MKDEBUG && _d("Failed to get EXPLAIN sparkline:", $EVAL_ERROR);
         }
      }

      push @profiles, \%profile;
   }

   my $report = $self->{formatter_for}->{profile} || new ReportFormatter(
      line_width       => LINE_LENGTH,
      long_last_column => 1,
      extend_right     => 1,
   );
   $report->set_title('Profile');
   my @cols = (
      { name => 'Rank',          right_justify => 1,             },
      { name => 'Query ID',                                      },
      { name => 'Response time', right_justify => 1,             },
      { name => 'Calls',         right_justify => 1,             },
      { name => 'R/Call',        right_justify => 1,             },
      { name => 'Apdx',          right_justify => 1, width => 4, },
      { name => 'V/M',           right_justify => 1, width => 5, },
      ( $o->get('explain') ? { name => 'EXPLAIN' } : () ),
      { name => 'Item',                                          },
   );
   $report->set_columns(@cols);

   foreach my $item ( sort { $a->{rank} <=> $b->{rank} } @profiles ) {
      my $rt  = sprintf('%10.4f', $item->{r});
      my $rtp = sprintf('%4.1f%%', $item->{r} / ($total_r || 1) * 100);
      my $rc  = sprintf('%8.4f', $item->{r} / $item->{cnt});
      my $vmr = sprintf('%4.2f', $item->{vmr});
      my @vals = (
         $item->{rank},
         "0x$item->{id}",
         "$rt $rtp",
         $item->{cnt},
         $rc,
         $item->{apdex},
         $vmr,
         ( $o->get('explain') ? $item->{explain_sparkline} || "" : () ),
         $item->{sample},
      );
      $report->add_line(@vals);
   }

   if ( $other && @$other ) {
      my $misc = {
            r   => 0,
            cnt => 0,
      };
      foreach my $other_event ( @$other ) {
         my $item      = $other_event->[0];
         my $stats     = $ea->results->{classes}->{$item};
         $misc->{r}   += $stats->{Query_time}->{sum};
         $misc->{cnt} += $stats->{Query_time}->{cnt};
      }
      my $rt  = sprintf('%10.4f', $misc->{r});
      my $rtp = sprintf('%4.1f%%', $misc->{r} / ($total_r || 1) * 100);
      my $rc  = sprintf('%8.4f', $misc->{r} / $misc->{cnt});
      $report->add_line(
         "MISC",
         "0xMISC",
         "$rt $rtp",
         $misc->{cnt},
         $rc,
         'NS',   # Apdex is not meaningful here
         '0.0',  # variance-to-mean ratio is not meaningful here
         ( $o->get('explain') ? "MISC" : () ),
         "<".scalar @$other." ITEMS>",
      );
   }

   return $report->get_report();
}

sub prepared {
   my ( $self, %args ) = @_;
   foreach my $arg ( qw(ea worst groupby) ) {
      die "I need a $arg argument" unless defined $arg;
   }
   my $ea      = $args{ea};
   my $worst   = $args{worst};
   my $groupby = $args{groupby};

   my $qr = $self->{QueryRewriter};

   my @prepared;       # prepared statements
   my %seen_prepared;  # report each PREP-EXEC pair once
   my $total_r = 0;

   foreach my $top_event ( @$worst ) {
      my $item       = $top_event->[0];
      my $rank       = $top_event->[2];
      my $stats      = $ea->results->{classes}->{$item};
      my $sample     = $ea->results->{samples}->{$item};
      my $samp_query = $sample->{arg} || '';

      $total_r += $stats->{Query_time}->{sum};
      next unless $stats->{Statement_id} && $item =~ m/^(?:prepare|execute) /;

      my ($prep_stmt, $prep, $prep_r, $prep_cnt);
      my ($exec_stmt, $exec, $exec_r, $exec_cnt);

      if ( $item =~ m/^prepare / ) {
         $prep_stmt           = $item;
         ($exec_stmt = $item) =~ s/^prepare /execute /;
      }
      else {
         ($prep_stmt = $item) =~ s/^execute /prepare /;
         $exec_stmt           = $item;
      }

      if ( !$seen_prepared{$prep_stmt}++ ) {
         $exec     = $ea->results->{classes}->{$exec_stmt};
         $exec_r   = $exec->{Query_time}->{sum};
         $exec_cnt = $exec->{Query_time}->{cnt};
         $prep     = $ea->results->{classes}->{$prep_stmt};
         $prep_r   = $prep->{Query_time}->{sum};
         $prep_cnt = scalar keys %{$prep->{Statement_id}->{unq}},
         push @prepared, {
            prep_r   => $prep_r, 
            prep_cnt => $prep_cnt,
            exec_r   => $exec_r,
            exec_cnt => $exec_cnt,
            rank     => $rank,
            sample   => $groupby eq 'fingerprint'
                          ? $qr->distill($samp_query, %{$args{distill_args}})
                          : $item,
            id       => $groupby eq 'fingerprint' ? make_checksum($item)
                                                  : '',
         };
      }
   }

   return unless scalar @prepared;

   my $report = $self->{formatter_for}->{prepared} || new ReportFormatter(
      line_width       => LINE_LENGTH,
      long_last_column => 1,
      extend_right     => 1,     
   );
   $report->set_title('Prepared statements');
   $report->set_columns(
      { name => 'Rank',          right_justify => 1, },
      { name => 'Query ID',                          },
      { name => 'PREP',          right_justify => 1, },
      { name => 'PREP Response', right_justify => 1, },
      { name => 'EXEC',          right_justify => 1, },
      { name => 'EXEC Response', right_justify => 1, },
      { name => 'Item',                              },
   );

   foreach my $item ( sort { $a->{rank} <=> $b->{rank} } @prepared ) {
      my $exec_rt  = sprintf('%10.4f', $item->{exec_r});
      my $exec_rtp = sprintf('%4.1f%%',$item->{exec_r}/($total_r || 1) * 100);
      my $prep_rt  = sprintf('%10.4f', $item->{prep_r});
      my $prep_rtp = sprintf('%4.1f%%',$item->{prep_r}/($total_r || 1) * 100);
      $report->add_line(
         $item->{rank},
         "0x$item->{id}",
         $item->{prep_cnt} || 0,
         "$prep_rt $prep_rtp",
         $item->{exec_cnt} || 0,
         "$exec_rt $exec_rtp",
         $item->{sample},
      );
   }
   return $report->get_report();
}

sub make_global_header {
   my ( $self ) = @_;
   my @lines;

   push @lines,
      sprintf $self->{num_format}, "Attribute", '', @{$self->{global_headers}};

   push @lines,
      sprintf $self->{num_format},
         (map { "=" x $_ } $self->{label_width}),
         (map { " " x $_ } qw(3)),  # no pct column in global header
         (map { "=" x $_ } qw(7 7 7 7 7 7 7));

   return @lines;
}

sub make_event_header {
   my ( $self ) = @_;

   return @{$self->{event_header_lines}} if $self->{event_header_lines};

   my @lines;
   push @lines,
      sprintf $self->{num_format}, "Attribute", @{$self->{event_headers}};

   push @lines,
      sprintf $self->{num_format},
         map { "=" x $_ } ($self->{label_width}, qw(3 7 7 7 7 7 7 7));

   $self->{event_header_lines} = \@lines;
   return @lines;
}

sub make_label {
   my ( $self, $val ) = @_;
   return '' unless $val;

   $val =~ s/_/ /g;

   if ( $val =~ m/^InnoDB/ ) {
      $val =~ s/^InnoDB //;
      $val = $val eq 'trx id' ? "InnoDB trxID"
           : substr($val, 0, $self->{label_width});
   }

   $val = $val eq 'user'            ? 'Users'
        : $val eq 'db'              ? 'Databases'
        : $val eq 'Query time'      ? 'Exec time'
        : $val eq 'host'            ? 'Hosts'
        : $val eq 'Error no'        ? 'Errors'
        : $val eq 'bytes'           ? 'Query size'
        : $val eq 'Tmp disk tables' ? 'Tmp disk tbl'
        : $val eq 'Tmp table sizes' ? 'Tmp tbl size'
        : substr($val, 0, $self->{label_width});

   return $val;
}

sub bool_percents {
   my ( $self, $vals ) = @_;
   my $p_true  = percentage_of($vals->{sum},  $vals->{cnt});
   my $p_false = percentage_of(($vals->{cnt} - $vals->{sum}), $vals->{cnt});
   return $p_true, $p_false;
}

sub format_string_list {
   my ( $self, $attrib, $vals, $class_cnt ) = @_;
   my $o        = $self->{OptionParser};
   my $show_all = $o->get('show-all');

   if ( !exists $vals->{unq} ) {
      return ($vals->{cnt});
   }

   my $cnt_for = $vals->{unq};
   if ( 1 == keys %$cnt_for ) {
      my ($str) = keys %$cnt_for;
      $str = substr($str, 0, LINE_LENGTH - 30) . '...'
         if length $str > LINE_LENGTH - 30;
      return $str;
   }
   my $line = '';
   my @top = sort { $cnt_for->{$b} <=> $cnt_for->{$a} || $a cmp $b }
                  keys %$cnt_for;
   my $i = 0;
   foreach my $str ( @top ) {
      my $print_str;
      if ( $str =~ m/(?:\d+\.){3}\d+/ ) {
         $print_str = $str;  # Do not shorten IP addresses.
      }
      elsif ( length $str > MAX_STRING_LENGTH ) {
         $print_str = substr($str, 0, MAX_STRING_LENGTH) . '...';
      }
      else {
         $print_str = $str;
      }
      my $p = percentage_of($cnt_for->{$str}, $class_cnt);
      $print_str .= " ($cnt_for->{$str}/$p%)";
      if ( !$show_all->{$attrib} ) {
         last if (length $line) + (length $print_str)  > LINE_LENGTH - 27;
      }
      $line .= "$print_str, ";
      $i++;
   }

   $line =~ s/, $//;

   if ( $i < @top ) {
      $line .= "... " . (@top - $i) . " more";
   }

   return $line;
}

sub sort_attribs {
   my ( $self, $attribs, $ea ) = @_;
   return unless $attribs && @$attribs;
   MKDEBUG && _d("Sorting attribs:", @$attribs);

   my @num_order = qw(
      Query_time
      Exec_orig_time
      Transmit_time
      Lock_time
      Rows_sent
      Rows_examined
      Rows_affected
      Rows_read
      Bytes_sent
      Merge_passes
      Tmp_tables
      Tmp_disk_tables
      Tmp_table_sizes
      bytes
   );
   my $i         = 0;
   my %num_order = map { $_ => $i++ } @num_order;

   my (@num, @innodb, @bool, @string);
   ATTRIB:
   foreach my $attrib ( @$attribs ) {
      next if $self->{hidden_attrib}->{$attrib};

      my $type = $ea->type_for($attrib) || 'string';
      if ( $type eq 'num' ) {
         if ( $attrib =~ m/^InnoDB_/ ) {
            push @innodb, $attrib;
         }
         else {
            push @num, $attrib;
         }
      }
      elsif ( $type eq 'bool' ) {
         push @bool, $attrib;
      }
      elsif ( $type eq 'string' ) {
         push @string, $attrib;
      }
      else {
         MKDEBUG && _d("Unknown attrib type:", $type, "for", $attrib);
      }
   }

   @num    = sort { pref_sort($a, $num_order{$a}, $b, $num_order{$b}) } @num;
   @innodb = sort { uc $a cmp uc $b } @innodb;
   @bool   = sort { uc $a cmp uc $b } @bool;
   @string = sort { uc $a cmp uc $b } @string;

   return {
      num     => \@num,
      innodb  => \@innodb,
      string  => \@string,
      bool    => \@bool,
   };
}

sub pref_sort {
   my ( $attrib_a, $order_a, $attrib_b, $order_b ) = @_;

   if ( !defined $order_a && !defined $order_b ) {
      return $attrib_a cmp $attrib_b;
   }

   if ( defined $order_a && defined $order_b ) {
      return $order_a <=> $order_b;
   }

   if ( !defined $order_a ) {
      return 1;
   }
   else {
      return -1;
   }
}

sub tables_report {
   my ( $self, @tables ) = @_;
   return '' unless @tables;
   my $q      = $self->{Quoter};
   my $tables = "";
   foreach my $db_tbl ( @tables ) {
      my ( $db, $tbl ) = @$db_tbl;
      $tables .= '#    SHOW TABLE STATUS'
               . ($db ? " FROM `$db`" : '')
               . " LIKE '$tbl'\\G\n";
      $tables .= "#    SHOW CREATE TABLE "
               . $q->quote(grep { $_ } @$db_tbl)
               . "\\G\n";
   }
   return $tables ? "# Tables\n$tables" : "# No tables\n";
}

sub explain_report {
   my ( $self, $query, $db ) = @_;
   return '' unless $query;

   my $dbh = $self->{dbh};
   my $q   = $self->{Quoter};
   my $qp  = $self->{QueryParser};
   return '' unless $dbh && $q && $qp;

   my $explain = '';
   eval {
      if ( !$qp->has_derived_table($query) ) {
         if ( $db ) {
            MKDEBUG && _d($dbh, "USE", $db);
            $dbh->do("USE " . $q->quote($db));
         }
         my $sth = $dbh->prepare("EXPLAIN /*!50100 PARTITIONS */ $query");
         $sth->execute();
         my $i = 1;
         while ( my @row = $sth->fetchrow_array() ) {
            $explain .= "# *************************** $i. "
                      . "row ***************************\n";
            foreach my $j ( 0 .. $#row ) {
               $explain .= sprintf "# %13s: %s\n", $sth->{NAME}->[$j],
                  defined $row[$j] ? $row[$j] : 'NULL';
            }
            $i++;  # next row number
         }
      }
   };
   if ( $EVAL_ERROR ) {
      MKDEBUG && _d("EXPLAIN failed:", $query, $EVAL_ERROR);
   }
   return $explain ? $explain : "# EXPLAIN failed: $EVAL_ERROR";
}

sub format_time_range {
   my ( $self, $vals ) = @_;
   my $min = parse_timestamp($vals->{min} || '');
   my $max = parse_timestamp($vals->{max} || '');

   if ( $min && $max && $min eq $max ) {
      return "all events occurred at $min";
   }

   my ($min_day) = split(' ', $min) if $min;
   my ($max_day) = split(' ', $max) if $max;
   if ( ($min_day || '') eq ($max_day || '') ) {
      (undef, $max) = split(' ', $max);
   }

   return $min && $max ? "$min to $max" : '';
}

sub explain_sparkline {
   my ( $self, $query, $db ) = @_;
   return unless $query;

   my $q   = $self->{Quoter};
   my $dbh = $self->{dbh};
   my $ex  = $self->{ExplainAnalyzer};
   return unless $dbh && $ex;

   if ( $db ) {
      MKDEBUG && _d($dbh, "USE", $db);
      $dbh->do("USE " . $q->quote($db));
   }
   my $res = $ex->normalize(
      $ex->explain_query(
         dbh   => $dbh,
         query => $query,
      )
   );

   my $sparkline;
   if ( $res ) {
      $sparkline = $ex->sparkline(explain => $res);
   }

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
# End QueryReportFormatter package
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
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_merge_mqd_results;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use File::Basename qw(dirname);
use File::Find;
use File::Spec;
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

eval {
  require IO::Uncompress::Gunzip;
  IO::Uncompress::Gunzip->import(qw(gunzip $GunzipError));
};
my $can_gunzip = $EVAL_ERROR ? 0 : 1;

use constant MKDEBUG => $ENV{MKDEBUG}        || 0;

sub main {
   @ARGV = @_;  # set global ARGV for this package

   # ##########################################################################
   # Get configuration information.
   # ##########################################################################
   my $o = new OptionParser();
   $o->get_specs();
   $o->get_opts();

   my $dp = $o->DSNParser();
   $dp->prop('set-vars', $o->get('set-vars'));

   if ( !$o->get('help') ) {
   }

   $o->usage_or_errors();

   # ########################################################################
   # Set up for --explain.
   # ########################################################################
   my $ep_dbh;
   if ( my $ep_dsn = $o->get('explain') ) {
      if ( $o->get('ask-pass') ) {
         $ep_dsn->{p} = OptionParser::prompt_noecho("Enter password: ");
      }
      $ep_dbh = $dp->get_dbh($dp->get_cxn_params($ep_dsn), {});
      $ep_dbh->{InactiveDestroy}  = 1;  # Don't die on fork().
   }

   # ########################################################################
   # Load, merge results from files.
   # ########################################################################
   my ($ea, $groupby) = merge_results(@ARGV);

   # ########################################################################
   # Print the reports.
   # ########################################################################
   my $q  = new Quoter();
   my $qp = new QueryParser();
   my $qr = new QueryRewriter(QueryParser=>$qp);

   $ea->calculate_statistical_metrics();

   my ($orderby_attrib, $orderby_func) = split(/:/, $o->get('order-by'));
   MKDEBUG && _d('Doing reports for groupby', $groupby, 'orderby',
      $orderby_attrib, $orderby_func);

   my ($worst, $other) = get_worst_queries(
      OptionParser   => $o,
      ea             => $ea,
      orderby_attrib => $orderby_attrib,
      orderby_func   => $orderby_func,
      limit          => $o->get('limit') || '95%:20',
      outlier        => $o->get('outliers'),
   );

   my $expected_range = $o->get('expected-range');
   my $explain_why    = $expected_range
                      && (   @$worst < $expected_range->[0]
                          || @$worst > $expected_range->[1]);

   # Print a header for this groupby/class if we're doing the
   # standard query report and there's more than one class or
   # there's one class but it's not the normal class grouped
   # by fingerprint.
   my $print_header = 0;
   if ( (grep { $_ eq 'query_report'; } @{$o->get('report-format')})
        && $groupby ne 'fingerprint' ) {
      $print_header = 1;
   }

   my $qrf = new QueryReportFormatter(
      OptionParser  => $o,
      QueryRewriter => $qr,
      QueryParser   => $qp,
      Quoter        => $q,
      dbh           => $ep_dbh,
   );
   $qrf->print_reports(
      reports      => $o->get('report-format'),
      ea           => $ea,
      worst        => $worst,
      orderby      => $orderby_attrib,
      groupby      => $groupby,
      print_header => $print_header,
      explain_why  => $explain_why,
   );

   return 0;
} # End main()

# ############################################################################
# Subroutines.
# ############################################################################

sub merge_results {
   my ( @files ) = @_;

   # Get all files by recursing into any directories.
   my @all_files = get_files(@files);

   my @ea;
   foreach my $file ( @all_files ) {
      eval {
         my $ea_info = load_ea_info($file);
         my $ea      = new EventAggregator(
            groupby => $ea_info->{groupby},
            worst   => $ea_info->{worst},
         );
         $ea->set_attribute_types($ea_info->{attribute_types});
         $ea->set_results($ea_info->{results});
         push @ea, $ea;
      };
      if ( $EVAL_ERROR ) {
         warn "Failed to load results from $file: $EVAL_ERROR";
      }
   }

   my $sum_ea = EventAggregator::merge(@ea);
   return $sum_ea, $sum_ea->{groupby};
}

sub get_files {
   my ( @files ) = @_;
   my @all_files;
   File::Find::find(
      {  no_chdir => 1,
         wanted   => sub {
            my ( $dir, $filename ) = ($File::Find::dir, $File::Find::name);
            if ( -f $filename ) {
               my ($vol, $dirs, $file) = File::Spec->splitpath( $filename );
               push @all_files, $filename;
            }
         },
      },
      map { File::Spec->rel2abs($_) } @files
   );
   return @all_files;
}

sub load_ea_info {
   my ( $file ) = @_;
   die "I need a file argument" unless $file;

   my $ea_info = "";
   if ( $file =~ m/\.gz$/ ) {
      die "IO::Uncompress::Gunzip not installed" unless $can_gunzip;
      our $GunzipError;
      my $output = \$ea_info;
      gunzip($file => $output)
         or die "Cannot unzip $file: $GunzipError\n";
   }
   else {
      open my $fh, '<', $file
         or die "Cannot open $file: $OS_ERROR\n";
      $ea_info = do { local $/ = undef; <$fh> };
      close $fh;
   }

   # The dumped ea info is evaled into existence as $VAR1.
   my $VAR1;
   eval $ea_info;

   die "Invalid results"          unless (ref $VAR1 eq 'HASH') && keys %$VAR1;
   die "No groupby in results"    unless $VAR1->{groupby};
   die "No worst in results"      unless $VAR1->{worst};
   die "No attributes in results" unless $VAR1->{attribute_types};
   die "No results in results"    unless $VAR1->{results};
   MKDEBUG && _d('groupby:', $VAR1->{groupby}, 'worst:', $VAR1->{worst});

   return $VAR1;
}

sub get_worst_queries {
   my ( %args ) = @_;
   my $o              = $args{OptionParser};
   my $ea             = $args{ea};
   my $orderby_attrib = $args{orderby_attrib};
   my $orderby_func   = $args{orderby_func};
   my $limit          = $args{limit};
   my $outliers       = $args{outliers};

   # We don't report on all queries, just the worst, i.e. the top
   # however many.
   my ($total, $count);
   if ( $limit =~ m/^\d+$/ ) {
      $count = $limit;
   }
   else {
      # It's a percentage, so grab as many as needed to get to
      # that % of the file.
      ($total, $count) = $limit =~ m/(\d+)/g;
      $total *= ($ea->results->{globals}->{$orderby_attrib}->{sum} || 0) / 100;
   }
   my %top_spec = (
      attrib  => $orderby_attrib,
      orderby => $orderby_func || 'cnt',
      total   => $total,
      count   => $count,
   );
   if ( $args{outliers} ) {
      @top_spec{qw(ol_attrib ol_limit ol_freq)}
         = split(/:/, $args{outliers});
   }

   # The queries that will be reported.
   return $ea->top_events(%top_spec);
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

mk-merge-mqd-results - Merge multiple mk-query-digest reports into one.

=head1 SYNOPSIS

Usage: mk-merge-mqd-results [OPTION...] [FILE]

mk-merge-mqd-results parses and analyzes MySQL log files.  With no
FILE, or when FILE is -, read standard input.

Examples:

  mk-query-digest slow.log-1 --save-results res1.txt

  mk-query-digest slow.log-2 --save-results res2.txt

  mk-merge-mqd-results res1.txt res2.txt

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

At the time of this release, we know of no bugs that could cause serious harm
to users.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-merge-mqd-results>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

This is a light-weight script for merging and reporting on results saved
by mk-query-digest --save-results.

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

=item --defaults-file

short form: -F; type: string

Only read mysql options from the given file.  You must give an absolute pathname.

=item --expected-range

type: array; default: 5,10

Explain items when there are more or fewer than expected.

Defines the number of items expected to be seen in the report
as controlled by L<"--limit"> and L<"--outliers">.  If
there  are more or fewer items in the report, each one will explain why it was
included.

=item --explain

type: DSN

Run EXPLAIN for the sample query with this DSN and print results.

This causes mk-merge-mqd-results to run EXPLAIN and include the output into
the report.  For safety, queries that appear to have a subquery that EXPLAIN
will execute won't be EXPLAINed.  Those are typically "derived table" queries
of the form

  select ... from ( select .... ) der;

=item --fingerprints

Add query fingerprints to the standard query analysis report.  This is mostly
useful for debugging purposes.

=item --[no]for-explain

default: yes

Print extra information to make analysis easy.

This option adds code snippets to make it easy to run SHOW CREATE TABLE and SHOW
TABLE STATUS for the query's tables.  It also rewrites non-SELECT queries into a
SELECT that might be helpful for determining the non-SELECT statement's index
usage.

=item --help

Show help and exit.

=item --host

short form: -h; type: string

Connect to host.

=item --limit

type: string; default: 95%:20

Limit output to the given percentage or count.

If the argument is an integer, report only the top N worst queries.  If the
argument is an integer followed by the C<%> sign, report that percentage of the
worst queries.  If the percentage is followed by a colon and another integer,
report the top percentage or the number specified by that integer, whichever
comes first.

See also L<"--outliers">.

=item --order-by

type: string; default: Query_time:sum

Sort events by this attribute and aggregate function.

=item --outliers

type: string; default: Query_time:1:10

Report outliers by attribute:percentile:count.

The syntax of this option is a comma-separated list of colon-delimited strings.
The first field is the attribute by which an outlier is defined.  The second is
a number that is compared to the attribute's 95th percentile.  The third is
optional, and is compared to the attribute's cnt aggregate.  Queries that pass
this specification are added to the report, regardless of any limits you
specified in L<"--limit">.

For example, to report queries whose 95th percentile Query_time is at least 60
seconds and which are seen at least 5 times, use the following argument:

  --outliers Query_time:60:5

=item --password

short form: -p; type: string

Password to use when connecting.

=item --port

short form: -P; type: int

Port number to use for connection.

=item --report-format

type: Array; default: rusage,date,files,header,profile,query_report,prepared

Print these sections of the query analysis report.

  SECTION      PRINTS
  ============ ==============================================================
  rusgae       CPU times and memory usage reported by ps
  date         Current local date and time
  files        Input files read/parse
  header       Summary of the entire analysis run
  profile      Compact table of queries for an at-a-glance view of the report
  query_report Detailed information about each unique query
  prepared     Prepared statements

The sections are printed in the order specified.  The rusage, date, files and
header sections are grouped together if specified together; other sections are
separted by blank lines.

=item --report-histogram

type: string; default: Query_time

Chart the distribution of this attribute's values.

The distribution chart is limited to time-based attributes, so charting
C<Rows_examined>, for example, will produce a useless chart.

=item --set-vars

type: string; default: wait_timeout=10000

Set these MySQL variables.  Immediately after connecting to MySQL, this
string will be appended to SET and executed.

=item --shorten

type: int; default: 1024

Shorten long statements in reports.

Shortens long statements, replacing the omitted portion with a C</*... omitted
...*/> comment.  This applies only to the output in reports, not to information
stored other places.  It prevents a large statement from
causing difficulty in a report.  The argument is the preferred length of the
shortened statement.  Not all statements can be shortened, but very large INSERT
and similar statements often can; and so can IN() lists, although only the first
such list in the statement will be shortened.

If it shortens something beyond recognition, you can find the original statement
in the log, at the offset shown in the report header.

=item --show-all

type: Hash

Show all values for these attributes.

By default mk-query-digest only shows as many of an attribute's value that
fit on a single line.  This option allows you to specify attributes for which
all values will be shown (line width is ignored).  This only works for
attributes with string values like user, host, db, etc.  Multiple attributes
can be specified, comma-separated.

=item --socket

short form: -S; type: string

Socket file to use for connection.

=item --user

short form: -u; type: string

User for login if not current user.

=item --version

Show version and exit.

=item --[no]zero-bool

default: yes

Print 0% boolean values in report.

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

You need Perl and some core packages that ought to be installed in any
reasonably new version of Perl.

=head1 BUGS

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-merge-mqd-results>.

Please use Google Code Issues and Groups to report bugs or request support:
L<http://code.google.com/p/maatkit/>.  You can also join #maatkit on Freenode to
discuss Maatkit.

Please include the complete command-line used to reproduce the problem you are
seeing, the version of all MySQL servers involved, the complete output of the
tool when run with L<"--version">, and if possible, debugging output produced by
running with the C<MKDEBUG=1> environment variable.

=head1 COPYRIGHT, LICENSE AND WARRANTY

This program is copyright 2010 Percona Inc.
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

This manual page documents Ver 0.9.29 Distrib 7540 $Revision: 7477 $.

=cut

__END__
:endofperl
