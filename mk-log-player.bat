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

# This program is copyright 2008-2011 Percona Inc.
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

our $VERSION = '1.0.9';
our $DISTRIB = '7540';
our $SVN_REV = sprintf("%d", (q$Revision: 7531 $ =~ m/(\d+)/g, 0));

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
# BinaryLogParser package 7522
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/BinaryLogParser.pm
#   trunk/common/t/BinaryLogParser.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package BinaryLogParser;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);
use constant MKDEBUG => $ENV{MKDEBUG} || 0;

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

my $binlog_line_1 = qr/at (\d+)$/m;
my $binlog_line_2 = qr/^#(\d{6}\s+\d{1,2}:\d\d:\d\d)\s+server\s+id\s+(\d+)\s+end_log_pos\s+(\d+)\s+(\S+)\s*([^\n]*)$/m;
my $binlog_line_2_rest = qr/thread_id=(\d+)\s+exec_time=(\d+)\s+error_code=(\d+)/m;

sub new {
   my ( $class, %args ) = @_;
   my $self = {
      delim     => undef,
      delim_len => 0,
   };
   return bless $self, $class;
}


sub parse_event {
   my ( $self, %args ) = @_;
   my @required_args = qw(next_event tell);
   foreach my $arg ( @required_args ) {
      die "I need a $arg argument" unless $args{$arg};
   }
   my ($next_event, $tell) = @args{@required_args};

   local $INPUT_RECORD_SEPARATOR = ";\n#";
   my $pos_in_log = $tell->();
   my $stmt;
   my ($delim, $delim_len) = ($self->{delim}, $self->{delim_len});

   EVENT:
   while ( defined($stmt = $next_event->()) ) {
      my @properties = ('pos_in_log', $pos_in_log);
      my ($ts, $sid, $end, $type, $rest);
      $pos_in_log = $tell->();
      $stmt =~ s/;\n#?\Z//;

      my ( $got_offset, $got_hdr );
      my $pos = 0;
      my $len = length($stmt);
      my $found_arg = 0;
      LINE:
      while ( $stmt =~ m/^(.*)$/mg ) { # /g requires scalar match.
         $pos     = pos($stmt);  # Be careful not to mess this up!
         my $line = $1;          # Necessary for /g and pos() to work.
         $line    =~ s/$delim// if $delim;
         MKDEBUG && _d($line);

         if ( $line =~ m/^\/\*.+\*\/;/ ) {
            MKDEBUG && _d('Comment line');
            next LINE;
         }
 
         if ( $line =~ m/^DELIMITER/m ) {
            my ( $del ) = $line =~ m/^DELIMITER (\S*)$/m;
            if ( $del ) {
               $self->{delim_len} = $delim_len = length $del;
               $self->{delim}     = $delim     = quotemeta $del;
               MKDEBUG && _d('delimiter:', $delim);
            }
            else {
               MKDEBUG && _d('Delimiter reset to ;');
               $self->{delim}     = $delim     = undef;
               $self->{delim_len} = $delim_len = 0;
            }
            next LINE;
         }

         next LINE if $line =~ m/End of log file/;

         if ( !$got_offset && (my ( $offset ) = $line =~ m/$binlog_line_1/m) ) {
            MKDEBUG && _d('Got the at offset line');
            push @properties, 'offset', $offset;
            $got_offset++;
         }

         elsif ( !$got_hdr && $line =~ m/^#(\d{6}\s+\d{1,2}:\d\d:\d\d)/ ) {
            ($ts, $sid, $end, $type, $rest) = $line =~ m/$binlog_line_2/m;
            MKDEBUG && _d('Got the header line; type:', $type, 'rest:', $rest);
            push @properties, 'cmd', 'Query', 'ts', $ts, 'server_id', $sid,
               'end_log_pos', $end;
            $got_hdr++;
         }

         elsif ( $line =~ m/^(?:#|use |SET)/i ) {

            if ( my ( $db ) = $line =~ m/^use ([^;]+)/ ) {
               MKDEBUG && _d("Got a default database:", $db);
               push @properties, 'db', $db;
            }

            elsif ( my ($setting) = $line =~ m/^SET\s+([^;]*)/ ) {
               MKDEBUG && _d("Got some setting:", $setting);
               push @properties, map { s/\s+//; lc } split(/,|\s*=\s*/, $setting);
            }

         }
         else {
            MKDEBUG && _d("Got the query/arg line at pos", $pos);
            $found_arg++;
            if ( $got_offset && $got_hdr ) {
               if ( $type eq 'Xid' ) {
                  my ($xid) = $rest =~ m/(\d+)/;
                  push @properties, 'Xid', $xid;
               }
               elsif ( $type eq 'Query' ) {
                  my ($i, $t, $c) = $rest =~ m/$binlog_line_2_rest/m;
                  push @properties, 'Thread_id', $i, 'Query_time', $t,
                                    'error_code', $c;
               }
               elsif ( $type eq 'Start:' ) {
                  MKDEBUG && _d("Binlog start");
               }
               else {
                  MKDEBUG && _d('Unknown event type:', $type);
                  next EVENT;
               }
            }
            else {
               MKDEBUG && _d("It's not a query/arg, it's just some SQL fluff");
               push @properties, 'cmd', 'Query', 'ts', undef;
            }

            my $delim_len = ($pos == length($stmt) ? $delim_len : 0);
            my $arg = substr($stmt, $pos - length($line) - $delim_len);

            $arg =~ s/$delim// if $delim; # Remove the delimiter.

            if ( $arg =~ m/^DELIMITER/m ) {
               my ( $del ) = $arg =~ m/^DELIMITER (\S*)$/m;
               if ( $del ) {
                  $self->{delim_len} = $delim_len = length $del;
                  $self->{delim}     = $delim     = quotemeta $del;
                  MKDEBUG && _d('delimiter:', $delim);
               }
               else {
                  MKDEBUG && _d('Delimiter reset to ;');
                  $del       = ';';
                  $self->{delim}     = $delim     = undef;
                  $self->{delim_len} = $delim_len = 0;
               }

               $arg =~ s/^DELIMITER.*$//m;  # Remove DELIMITER from arg.
            }

            $arg =~ s/;$//gm;  # Ensure ending ; are gone.
            $arg =~ s/\s+$//;  # Remove trailing spaces and newlines.

            push @properties, 'arg', $arg, 'bytes', length($arg);
            last LINE;
         }
      } # LINE

      if ( $found_arg ) {
         MKDEBUG && _d('Properties of event:', Dumper(\@properties));
         my $event = { @properties };
         if ( $args{stats} ) {
            $args{stats}->{events_read}++;
            $args{stats}->{events_parsed}++;
         }
         return $event;
      }
      else {
         MKDEBUG && _d('Event had no arg');
      }
   } # EVENT

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
# End BinaryLogParser package
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
# LogSplitter package 7177
# This package is a copy without comments from the original.  The original
# with comments and its test file can be found in the SVN repository at,
#   trunk/common/LogSplitter.pm
#   trunk/common/t/LogSplitter.t
# See http://code.google.com/p/maatkit/wiki/Developers for more information.
# ###########################################################################

package LogSplitter;

use strict;
use warnings FATAL => 'all';
use English qw(-no_match_vars);

use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use constant MKDEBUG           => $ENV{MKDEBUG} || 0;
use constant MAX_OPEN_FILES    => 1000;
use constant CLOSE_N_LRU_FILES => 100;

my $oktorun = 1;

sub new {
   my ( $class, %args ) = @_;
   foreach my $arg ( qw(attribute base_dir parser session_files) ) {
      die "I need a $arg argument" unless $args{$arg};
   }

   $args{base_dir} .= '/' if substr($args{base_dir}, -1, 1) ne '/';

   if ( $args{split_random} ) {
      MKDEBUG && _d('Split random');
      $args{attribute} = '_sessionno';  # set round-robin 1..session_files
   }

   my $self = {
      base_file_name    => 'session',
      max_dirs          => 1_000,
      max_files_per_dir => 5_000,
      max_sessions      => 5_000_000,  # max_dirs * max_files_per_dir
      merge_sessions    => 1,
      session_files     => 64,
      quiet             => 0,
      verbose           => 0,
      %args,
      n_dirs_total       => 0,  # total number of dirs created
      n_files_total      => 0,  # total number of session files created
      n_files_this_dir   => -1, # number of session files in current dir
      session_fhs        => [], # filehandles for each session
      n_open_fhs         => 0,  # current number of open session filehandles
      n_events_total     => 0,  # total number of events in log
      n_events_saved     => 0,  # total number of events saved
      n_sessions_skipped => 0,  # total number of sessions skipped
      n_sessions_saved   => 0,  # number of sessions saved
      sessions           => {}, # sessions data store
      created_dirs       => [],
   };

   MKDEBUG && _d('new LogSplitter final args:', Dumper($self));
   return bless $self, $class;
}

sub split {
   my ( $self, @logs ) = @_;
   $oktorun = 1; # True as long as we haven't created too many

   my $callbacks = $self->{callbacks};

   my $next_sessionno;
   if ( $self->{split_random} ) {
      $next_sessionno = make_rr_iter(1, $self->{session_files});
   }

   if ( @logs == 0 ) {
      MKDEBUG && _d('Implicitly reading STDIN because no logs were given');
      push @logs, '-';
   }

   my $lp = $self->{parser};
   LOG:
   foreach my $log ( @logs ) {
      last unless $oktorun;
      next unless defined $log;

      if ( !-f $log && $log ne '-' ) {
         warn "Skipping $log because it is not a file";
         next LOG;
      }
      my $fh;
      if ( $log eq '-' ) {
         $fh = *STDIN;
      }
      else {
         if ( !open $fh, "<", $log ) {
            warn "Cannot open $log: $OS_ERROR\n";
            next LOG;
         }
      }

      MKDEBUG && _d('Splitting', $log);
      my $event           = {};
      my $more_events     = 1;
      my $more_events_sub = sub { $more_events = $_[0]; };
      EVENT:
      while ( $oktorun ) {
         $event = $lp->parse_event(
            next_event => sub { return <$fh>;    },
            tell       => sub { return tell $fh; },
            oktorun => $more_events_sub,
         );
         if ( $event ) {
            $self->{n_events_total}++;
            if ( $self->{split_random} ) {
               $event->{_sessionno} = $next_sessionno->();
            }
            if ( $callbacks ) {
               foreach my $callback ( @$callbacks ) {
                  $event = $callback->($event);
                  last unless $event;
               }
            }
            $self->_save_event($event) if $event;
         }
         if ( !$more_events ) {
            MKDEBUG && _d('Done parsing', $log);
            close $fh;
            next LOG;
         }
         last LOG unless $oktorun;
      }
   }

   while ( my $fh = pop @{ $self->{session_fhs} } ) {
      close $fh->{fh};
   }
   $self->{n_open_fhs}  = 0;

   $self->_merge_session_files() if $self->{merge_sessions};
   $self->print_split_summary() unless $self->{quiet};

   return;
}

sub _save_event {
   my ( $self, $event ) = @_; 
   my ($session, $session_id) = $self->_get_session_ds($event);
   return unless $session;

   if ( !defined $session->{fh} ) {
      $self->{n_sessions_saved}++;
      MKDEBUG && _d('New session:', $session_id, ',',
         $self->{n_sessions_saved}, 'of', $self->{max_sessions});

      my $session_file = $self->_get_next_session_file();
      if ( !$session_file ) {
         $oktorun = 0;
         MKDEBUG && _d('Not oktorun because no _get_next_session_file');
         return;
      }

      $self->_close_lru_session() if $self->{n_open_fhs} >= MAX_OPEN_FILES;

      open my $fh, '>', $session_file
         or die "Cannot open session file $session_file: $OS_ERROR";
      $session->{fh} = $fh;
      $self->{n_open_fhs}++;

      $session->{active}       = 1;
      $session->{session_file} = $session_file;

      push @{$self->{session_fhs}}, { fh => $fh, session_id => $session_id };

      MKDEBUG && _d('Created', $session_file, 'for session',
         $self->{attribute}, '=', $session_id);

      print $fh "-- START SESSION $session_id\n\n";
   }
   elsif ( !$session->{active} ) {

      $self->_close_lru_session() if $self->{n_open_fhs} >= MAX_OPEN_FILES;

       open $session->{fh}, '>>', $session->{session_file}
          or die "Cannot reopen session file "
            . "$session->{session_file}: $OS_ERROR";

       $session->{active} = 1;
       $self->{n_open_fhs}++;

       MKDEBUG && _d('Reopend', $session->{session_file}, 'for session',
         $self->{attribute}, '=', $session_id);
   }
   else {
      MKDEBUG && _d('Event belongs to active session', $session_id);
   }

   my $session_fh = $session->{fh};

   my $db = $event->{db} || $event->{Schema};
   if ( $db && ( !defined $session->{db} || $session->{db} ne $db ) ) {
      print $session_fh "use $db\n\n";
      $session->{db} = $db;
   }

   print $session_fh $self->flatten($event->{arg}), "\n\n";
   $self->{n_events_saved}++;

   return;
}

sub _get_session_ds {
   my ( $self, $event ) = @_;

   my $attrib = $self->{attribute};
   if ( !$event->{ $attrib } ) {
      MKDEBUG && _d('No attribute', $attrib, 'in event:', Dumper($event));
      return;
   }

   return unless $event->{arg};

   return if ($event->{cmd} || '') eq 'Admin';

   my $session;
   my $session_id = $event->{ $attrib };

   if ( $self->{n_sessions_saved} < $self->{max_sessions} ) {
      $session = $self->{sessions}->{ $session_id } ||= {};
   }
   elsif ( exists $self->{sessions}->{ $session_id } ) {
      $session = $self->{sessions}->{ $session_id };
   }
   else {
      $self->{n_sessions_skipped} += 1;
      MKDEBUG && _d('Skipping new session', $session_id,
         'because max_sessions is reached');
   }

   return $session, $session_id;
}

sub _close_lru_session {
   my ( $self ) = @_;
   my $session_fhs = $self->{session_fhs};
   my $lru_n       = $self->{n_sessions_saved} - MAX_OPEN_FILES - 1;
   my $close_to_n  = $lru_n + CLOSE_N_LRU_FILES - 1;

   MKDEBUG && _d('Closing session fhs', $lru_n, '..', $close_to_n,
      '(',$self->{n_sessions}, 'sessions', $self->{n_open_fhs}, 'open fhs)');

   foreach my $session ( @$session_fhs[ $lru_n..$close_to_n ] ) {
      close $session->{fh};
      $self->{n_open_fhs}--;
      $self->{sessions}->{ $session->{session_id} }->{active} = 0;
   }

   return;
}

sub _get_next_session_file {
   my ( $self, $n ) = @_;
   return if $self->{n_dirs_total} >= $self->{max_dirs};

   if ( ($self->{n_files_this_dir} >= $self->{max_files_per_dir})
        || $self->{n_files_this_dir} < 0 ) {
      $self->{n_dirs_total}++;
      $self->{n_files_this_dir} = 0;
      my $new_dir = "$self->{base_dir}$self->{n_dirs_total}";
      if ( !-d $new_dir ) {
         my $retval = system("mkdir $new_dir");
         if ( ($retval >> 8) != 0 ) {
            die "Cannot create new directory $new_dir: $OS_ERROR";
         }
         MKDEBUG && _d('Created new base_dir', $new_dir);
         push @{$self->{created_dirs}}, $new_dir;
      }
      elsif ( MKDEBUG ) {
         _d($new_dir, 'already exists');
      }
   }
   else {
      MKDEBUG && _d('No dir created; n_files_this_dir:',
         $self->{n_files_this_dir}, 'n_files_total:',
         $self->{n_files_total});
   }

   $self->{n_files_total}++;
   $self->{n_files_this_dir}++;
   my $dir_n        = $self->{n_dirs_total} . '/';
   my $session_n    = sprintf '%d', $n || $self->{n_sessions_saved};
   my $session_file = $self->{base_dir}
                    . $dir_n
                    . $self->{base_file_name}."-$session_n.txt";
   MKDEBUG && _d('Next session file', $session_file);
   return $session_file;
}

sub flatten {
   my ( $self, $query ) = @_;
   return unless $query;
   $query =~ s!/\*.*?\*/! !g;
   $query =~ s/^\s+//;
   $query =~ s/\s{2,}/ /g;
   return $query;
}

sub _merge_session_files {
   my ( $self ) = @_;

   print "Merging session files...\n" unless $self->{quiet};

   my @multi_session_files;
   for my $i ( 1..$self->{session_files} ) {
      push @multi_session_files, $self->{base_dir} ."sessions-$i.txt";
   }

   my @single_session_files = map {
      $_->{session_file};
   } values %{$self->{sessions}};

   my $i = make_rr_iter(0, $#multi_session_files);  # round-robin iterator
   foreach my $single_session_file ( @single_session_files ) {
      my $multi_session_file = $multi_session_files[ $i->() ];
      my $cmd;
      if ( $self->{split_random} ) {
         $cmd = "mv $single_session_file $multi_session_file";
      }
      else {
         $cmd = "cat $single_session_file >> $multi_session_file";
      }
      eval { `$cmd`; };
      if ( $EVAL_ERROR ) {
         warn "Failed to `$cmd`: $OS_ERROR";
      }
   }

   foreach my $created_dir ( @{$self->{created_dirs}} ) {
      my $cmd = "rm -rf $created_dir";
      eval { `$cmd`; };
      if ( $EVAL_ERROR ) {
         warn "Failed to `$cmd`: $OS_ERROR";
      }
   }

   return;
}

sub make_rr_iter {
   my ( $start, $end ) = @_;
   my $current = $start;
   return sub {
      $current = $start if $current > $end ;
      $current++;  # For next iteration.
      return $current - 1;
   };
}

sub print_split_summary {
   my ( $self ) = @_;
   print "Split summary:\n";
   my $fmt = "%-20s %-10s\n";
   printf $fmt, 'Total sessions',
      $self->{n_sessions_saved} + $self->{n_sessions_skipped};
   printf $fmt, 'Sessions saved',
      $self->{n_sessions_saved};
   printf $fmt, 'Total events', $self->{n_events_total};
   printf $fmt, 'Events saved', $self->{n_events_saved};
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
# End LogSplitter package
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
# This is a combination of modules and programs in one -- a runnable module.
# http://www.perl.com/pub/a/2006/07/13/lightning-articles.html?page=last
# Or, look it up in the Camel book on pages 642 and 643 in the 3rd edition.
#
# Check at the end of this package for the call to main() which actually runs
# the program.
# ###########################################################################
package mk_log_player;

use POSIX;
use Time::HiRes qw(time usleep);
use File::Basename qw(dirname);
use File::Find;
use File::Spec;
use List::Util qw(max);
use Data::Dumper;
$Data::Dumper::Indent    = 1;
$Data::Dumper::Sortkeys  = 1;
$Data::Dumper::Quotekeys = 0;

use English qw(-no_match_vars);

use constant MKDEBUG => $ENV{MKDEBUG} || 0;

# These are global so the --play threads can access them.
my $o;
my $dp;

sub main {
   @ARGV = @_;  # set global ARGV for this package

   # #########################################################################
   # Get configuration information.
   # #########################################################################
   $o = new OptionParser();
   $o->get_specs();
   $o->get_opts();

   $dp = $o->DSNParser(); 
   $dp->prop('set-vars', $o->get('set-vars'));

   # LogSplitter will override the split attribute if split_random is true.
   # Set --split to some arbitrary value so we don't have to check for both
   # and --play will not be invoked.
   $o->set('split', 'random') if $o->get('split-random');

   # If not --split then the remaining arg should be a DSN for --play.
   my $dsn;
   if ( !$o->get('split') && !$o->get('print') && !$o->get('dry-run') ) {
      my $dsn_defaults = $dp->parse_options($o);
      $dsn = @ARGV ? $dp->parse(shift @ARGV, $dsn_defaults) : $dsn_defaults;
      if ( !$dsn ) {
         $o->save_error('Missing or invalid host');
      }
   }

   if ( !-d $o->get('base-dir') ) {
      $o->save_error('Invalid --base-dir: '
         . $o->get('base-dir') . ' is not a directory');
   }

   $o->set('threads', max(2, MaatkitCommon::get_number_of_cpus()))
      unless $o->got('threads');

   $o->set('verbose', 0) if $o->get('quiet');

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

   # #########################################################################
   # Split the logs into session files and exit.
   # #########################################################################
   my $split  = $o->get('split');
   my $base_dir = $o->get('base-dir');
   if ( $split ) {
      die "$base_dir is not a directory" if !-d $base_dir;

      # It's sad because I wrote this script but I still frequently forget
      # to specify the split attribute (Thread_id, etc.). So the log file
      # is taken to be the split attrib and then LogSplitter tries to read
      # from STDIN. This is my self-reminder.
      warn "The --split attribute $split does not appear valid"
         if $split !~ m/^[\w]+$/;

      $ARGV[0] = '-' if scalar @ARGV == 0; # causes LogSplitter to read STDIN

      my @callbacks;
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

      my $parser = $o->get('type') eq 'slowlog' ? new SlowLogParser()
                 : $o->get('type') eq 'binlog'  ? new BinaryLogParser()
                 : $o->get('type') eq 'genlog'  ? new GeneralLogParser()
                 : die("Unknown type " . $o->get('type'));
      my $ls = new LogSplitter(
         attribute      => $split,
         split_random   => $o->get('split-random'),
         base_dir       => $base_dir,
         base_file_name => $o->get('base-file-name'),
         max_sessions   => $o->get('max-sessions'),
         session_files  => $o->get('session-files'),
         quiet          => $o->get('quiet'),
         verbose        => $o->get('verbose'),
         parser         => $parser,
         callbacks      => \@callbacks,
      );
      $ls->split(@ARGV);

      return 0;
   }

   # #########################################################################
   # Make list of session files to play. If playing a whole, the log is
   # treated as one big session file.
   # ######################################################################### 
   my @session_files;
   foreach my $session_file ( split ',', $o->get('play') ) {
      # The session "file" might actually be a dir, in which case we
      # read ALL files in that dir.
      if ( -d $session_file ) {
         MKDEBUG && _d('Reading all session log files in', $session_file);
         opendir my $dir, $session_file
            or die "Cannot open directory $session_file: $OS_ERROR";
         push @session_files,
            map     { "$session_file/$_"    } # 3. Save full dir/file
            grep    { -f "$session_file/$_" } # 2. If it's a file
            readdir $dir;                     # 1. Each file in dir
         closedir $dir;
      }
      else {
         if ( !-f $session_file ) {
            warn "$session_file is not a file";
         }
         else {
            push @session_files, $session_file;
         }
      }
   }

   MKDEBUG && _d('Session files:', @session_files);

   if ( @session_files == 0 ) {
      warn 'No valid session files';
      return 0;
   }

   my $n_session_files = scalar @session_files;
   print "Found $n_session_files session files.\n" unless $o->get('quiet');

   if ( $o->get('threads') > $n_session_files ) {
      warn "--threads is greater than the number of session files.  "
         . "Only $n_session_files concurrent process will be ran";
      $o->set('threads', $n_session_files);
   }
   my $threads = $o->get('threads');

   my @child_tasks;
   my $childno = LogSplitter::make_rr_iter(0, $threads-1);
   while ( defined (my $session_file = pop @session_files) ) {
      push @{$child_tasks[$childno->()]}, $session_file;
   }

   # Shouldn't happen...
   warn "There are unassigned session files" if @session_files > 0;

   if ( $o->get('dry-run') || $o->get('verbose') ) {
      for my $i ( 0..($threads-1) ) {
         print "Process $i plays $_\n" for @{$child_tasks[$i]};
      }
      # Shouldn't happen...
      print "Unassigned session files: " . join(', ', @session_files), "\n"
         if @session_files;
      return 0 if $o->get('dry-run');
   }

   # #########################################################################
   # Connect parent to MySQL.
   # #########################################################################
   my $parent_dbh;
   if ( !$o->get('print') ) {
      if ( $o->get('ask-pass') ) {
         $o->set('password', OptionParser::prompt_noecho("Enter password: "));
      }
      $parent_dbh = get_cxn($dsn);
      $parent_dbh->{InactiveDestroy} = 1; # Don't die on fork().
   }

   # #########################################################################
   # Assign sessions to child processes.
   # #########################################################################
   my %children;
   my %exited_children;
   # This signal handler will do nothing but wake up the sleeping parent process
   # and record the exit status and time of the child that exited (as a side
   # effect of not discarding the signal).
   # -- Presently, however, we do not use this information.
   $SIG{CHLD} = sub {
      my $pid;
      while (($pid = waitpid(-1, POSIX::WNOHANG)) > 0) {
         # Must right-shift to get the actual exit status of the child.
         $exited_children{$pid}->{exit_status} = $CHILD_ERROR >> 8;
         $exited_children{$pid}->{exit_time}   = time;
      }
   };

   # Fork the child processes.
   print "Running processes...\n" unless $o->get('quiet');
   for my $childno ( 0..($threads-1) ) {
      my $child_tasks = $child_tasks[$childno];

      my $pid = fork();
      die "Cannot fork process $childno: $OS_ERROR" unless defined $pid;
      if ( $pid ) {              # I'm the parent.
         $children{$pid} = $childno + 1;
      }
      else {                     # I'm the child.
         $SIG{CHLD} = 'DEFAULT'; # See bug #1886444
         MKDEBUG && _d('Child PID', $PID, 'started');
         play_session($dsn, ($childno + 1), $child_tasks);
         MKDEBUG && _d('Child PID', $PID, 'finished');
         return 0;
      }
   } 
   print "All processes are running; waiting for them to finish...\n"
      unless $o->get('quiet');

   # Wait for and reap the child processes.
   do {
      # Possibly wait for child.
      my $reaped = 0;
      foreach my $pid ( keys %exited_children ) { 
         $reaped = 1;
         print "Process ", $children{$pid}, " finished with exit status ",
            $exited_children{$pid}->{exit_status}, ".\n"
            unless $o->get('quiet');
         MKDEBUG && _d('Reaped child PID', $pid);
         delete $children{$pid};
         delete $exited_children{$pid};
      }

      if ( keys %children && !$reaped ) {
         # Don't busy-wait.  But don't wait forever either, as a child may exit
         # and signal while we're not sleeping, so if we sleep forever we may
         # not get the signal.
         MKDEBUG && _d('Sleeping to wait for children');
         sleep 1;
      }
      MKDEBUG && _d(scalar keys %children, 'children are still working');

   } while ( keys %children );

   print "All processes have finished.\n" unless $o->get('quiet');
   return 0;
}

# #############################################################################
# Subroutines.
# #############################################################################
sub play_session {
   my ( $dsn, $childno, $session_files ) = @_;

   my $query_time;
   my $slowlog_fmt = "# Thread_id: %s  Query_time: %.6f  Schema: %s\n%s;\n";
   my $only_select = $o->get('only-select');
   my $warnings    = $o->get('warnings');
   my $print       = $o->get('print');
   my $results     = $o->get('results');
   my $dbh         = get_cxn($dsn) unless $print;

   # Each thread writes to its own file because contention will not allow
   # them all to write correctly to STDOUT at once.
   my $base_dir    = $o->get('base-dir');
   my $output_file = $o->get('base-dir')
                   . '/'
                   . $o->get('base-file-name') . "-results-$PID.txt";
   my $output_fh;
   if ( $results || $print ) {
      open $output_fh, '>', $output_file
         or die "Cannot open $output_file for writing: $OS_ERROR";
      MKDEBUG && _d('Proc', $childno, 'writing to', $output_file);
   }
   else {
      MKDEBUG && _d('Proc', $childno, 'not writing results');
   }

   local $INPUT_RECORD_SEPARATOR = '';

   ITERATION:
   for my $iteration_n ( 1..$o->get('iterations') ) {
      MKDEBUG && _d('Proc', $childno, 'starting iteration', $iteration_n);

      SESSION_FILE:
      foreach my $session_file ( @$session_files ) {
         my $session_fh;
         my $session_n;
         if ( !open $session_fh, '<', $session_file ) {
            warn "Cannot open session file $session_file: $OS_ERROR";
            next SESSION_FILE;
         }

         my $db;
         QUERY:
         while ( my $query = <$session_fh> ) {
            if ( $print ) {
               print $output_fh $query;
               next QUERY;
            }

            if ( $query =~ m/^-- START SESSION (\S+)/ ) {
               $session_n = $1;
               next QUERY;
            }

            if ( $only_select ) {
               # Remove leading /* comments */ (issue 903)
               $query =~ s!^/\*.*?\*/\s*!!;
               if ( $query !~ m/^(?:SELECT|USE) /i ) {
                  MKDEBUG && _d('Skipping query for --only-select:', $query);
                  next QUERY;
               }
            }

            if ( $query =~ m/^use (\S+)/ ) {
               $db = $1;
               eval { $dbh->do($query); };
               if ( $EVAL_ERROR && $warnings ) {
                  warn_error($childno, $session_n, $query,$dbh->errstr());
               }
               next QUERY;
            }

            $query_time = time;
            eval { $dbh->do($query); };
            if ( $EVAL_ERROR && $warnings ) {
               warn_error($childno, $session_n, $query, $dbh->errstr());
               next QUERY;
            }

            if ( $results ) {
               chomp $query;
               printf $output_fh $slowlog_fmt,
                  "$childno$session_n",
                  time - $query_time,
                  ($db || ''),
                  $query;
            }
         } # QUERY

         MKDEBUG && _d('No more sessions in', $session_file);
         close $session_fh;
      } # SESSION_FILE
   } # ITERATION

   close $output_fh if $output_fh;
   $dbh->disconnect() if $dbh;
   return;
}

sub get_delay {
   my ( $delay ) = @_;
   return 0 if !defined $delay || scalar @$delay == 0;
   my $t = 0;

   my ( $from, $to ) = @$delay[0..1];
   if ( defined $to ) {
      $t = rand($to) + $from;
   }
   else {
      $t = $from;
   }

   # Return time is expressed in microseconds because this value
   # is used with usleep() which takes a microsecond time value.
   return $t *= 1_000_000;
}

sub get_cxn {
   my ( $dsn ) = @_;
   return $dp->get_dbh( $dp->get_cxn_params($dsn) );
}

sub warn_error {
   my ( $childno, $session_n, $query, $warning ) = @_;
   $childno     = -1 unless defined $childno;
   $session_n   = -1 unless defined $session_n;
   $query     ||= "";
   $warning   ||= "";
   warn "Query '$query' in proc $childno session $session_n caused an error: "
      . "$warning\n";
   return;
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

mk-log-player - Replay MySQL query logs.

=head1 SYNOPSIS

Usage: mk-log-player [OPTION...] [DSN]

mk-log-player splits and plays slow log files.

Split slow.log on Thread_id into 16 session files, save in ./sessions:

  mk-log-player --split Thread_id --session-files 16 --base-dir ./sessions slow.log

Play all those sessions on host1, save results in ./results:

  mk-log-player --play ./sessions --base-dir ./results h=host1

Use L<mk-query-digest> to summarize the results:

  mk-query-digest ./results/*

=head1 RISKS

The following section is included to inform users about the potential risks,
whether known or unknown, of using this tool.  The two main categories of risks
are those created by the nature of the tool (e.g. read-only tools vs. read-write
tools) and those created by bugs.

This tool is meant to load a server as much as possible, for stress-testing
purposes.  It is not designed to be used on production servers.

At the time of this release there is a bug which causes mk-log-player to
exceed max open files during L<"--split">.

The authoritative source for updated information is always the online issue
tracking system.  Issues that affect this tool will be marked as such.  You can
see a list of such issues at the following URL:
L<http://www.maatkit.org/bugs/mk-log-player>.

See also L<"BUGS"> for more information on filing bugs and getting help.

=head1 DESCRIPTION

mk-log-player does two things: it splits MySQL query logs into session files
and it plays (executes) queries in session files on a MySQL server.  Only
session files can be played; slow logs cannot be played directly without
being split.

A session is a group of queries from the slow log that all share a common
attribute, usually Thread_id.  The common attribute is specified with
L<"--split">.  Multiple sessions are saved into a single session file.
See L<"--session-files">, L<"--max-sessions">, L<"--base-file-name"> and
L<"--base-dir">.  These session files are played with L<"--play">.

mk-log-player will L<"--play"> session files in parallel using N number of
L<"--threads">.  (They're not technically threads, but we call them that
anyway.)  Each thread will play all the sessions in its given session files.
The sessions are played as fast as possible--there are no delays--because the
goal is to stress-test and load-test the server.  So be careful using this
script on a production server!

Each L<"--play"> thread writes its results to a separate file.  These result
files are in slow log format so they can be aggregated and summarized with
L<mk-query-digest>.  See L<"OUTPUT">.

=head1 OUTPUT

Both L<"--split"> and L<"--play"> have two outputs: status messages printed to
STDOUT to let you know what the script is doing, and session or result files
written to separate files saved in L<"--base-dir">.  You can suppress all
output to STDOUT for each with L<"--quiet">, or increase output with
L<"--verbose">.

The session files written by L<"--split"> are simple text files containing
queries grouped into sessions.  For example:

  -- START SESSION 10

  use foo

  SELECT col FROM foo_tbl

The format of these session files is important: each query must be a single
line separated by a single blank line.  And the "-- START SESSION" comment
tells mk-log-player where individual sessions begin and end so that L<"--play">
can correctly fake Thread_id in its result files.

The result files written by L<"--play"> are in slow log format with a minimal
header: the only attributes printed are Thread_id, Query_time and Schema.

=head1 OPTIONS

Specify at least one of L<"--play">, L<"--split"> or L<"--split-random">.

L<"--play"> and L<"--split"> are mutually exclusive.

This tool accepts additional command-line arguments.  Refer to the
L<"SYNOPSIS"> and usage information for details.

=over

=item --ask-pass

group: Play

Prompt for a password when connecting to MySQL.

=item --base-dir

type: string; default: ./

Base directory for L<"--split"> session files and L<"--play"> result file.

=item --base-file-name

type: string; default: session

Base file name for L<"--split"> session files and L<"--play"> result file.

Each L<"--split"> session file will be saved as <base-file-name>-N.txt, where
N is a four digit, zero-padded session ID.  For example: session-0003.txt.

Each L<"--play"> result file will be saved as <base-file-name>-results-PID.txt,
where PID is the process ID of the executing thread.

All files are saved in L<"--base-dir">.

=item --charset

short form: -A; type: string; group: Play

Default character set.  If the value is utf8, sets Perl's binmode on STDOUT to
utf8, passes the mysql_enable_utf8 option to DBD::mysql, and runs SET NAMES UTF8
after connecting to MySQL.  Any other value sets binmode on STDOUT without the
utf8 layer, and runs SET NAMES after connecting to MySQL.

=item --config

type: Array

Read this comma-separated list of config files; if specified, this must be the
first option on the command line.

=item --defaults-file

short form: -F; type: string

Only read mysql options from the given file.

=item --dry-run

Print which processes play which session files then exit.

=item --filter

type: string; group: Split

Discard L<"--split"> events for which this Perl code doesn't return true.

This option only works with L<"--split">.

This option allows you to inject Perl code into the tool to affect how the
tool runs.  Usually your code should examine C<$event> to decided whether
or not to allow the event.  C<$event> is a hashref of attributes and values of
the event being filtered.  Or, your code could add new attribute-value pairs
to C<$event> for use by other options that accept event attributes as their
value.  You can find an explanation of the structure of C<$event> at
L<http://code.google.com/p/maatkit/wiki/EventAttributes>.

There are two ways to supply your code: on the command line or in a file.
If you supply your code on the command line, it is injected into the following
subroutine where C<$filter> is your code:

   sub {
      MKDEBUG && _d('callback: filter');
      my( $event ) = shift;
      ( $filter ) && return $event;
   }

Therefore you must ensure two things: first, that you correctly escape any
special characters that need to be escaped on the command line for your
shell, and two, that your code is syntactically valid when injected into
the subroutine above.

Here's an example filter supplied on the command line that discards
events that are not SELECT statements:

  --filter '$event->{arg} =~ m/^select/i'

The second way to supply your code is in a file.  If your code is too complex
to be expressed on the command line that results in valid syntax in the
subroutine above, then you need to put the code in a file and give the file
name as the value to L<"--filter">.  The file should not contain a shebang
(C<#!/usr/bin/perl>) line.  The entire contents of the file is injected into
the following subroutine:

   sub {
      MKDEBUG && _d('callback: filter');
      my( $event ) = shift;
      $filter && return $event;
   }

That subroutine is almost identical to the one above except your code is
not wrapped in parentheses.  This allows you to write multi-line code like:

   my $event_ok;
   if (...) {
      $event_ok = 1;
   }
   else {
      $event_ok = 0;
   }
   $event_ok

Notice that the last line is not syntactically valid by itself, but it
becomes syntactically valid when injected into the subroutine because it
becomes:

   $event_ok && return $event;

If your code doesn't compile, the tool will die with an error.  Even if your
code compiles, it may crash to tool during runtime if, for example, it tries
a pattern match an undefined value.  No safeguards of any kind of provided so
code carefully!

=item --help

Show help and exit.

=item --host

short form: -h; type: string; group: Play

Connect to host.

=item --iterations

type: int; default: 1; group: Play

How many times each thread should play all its session files.

=item --max-sessions

type: int; default: 5000000; group: Split

Maximum number of sessions to L<"--split">.

By default, C<mk-log-player> tries to split every session from the log file.
For huge logs, however, this can result in millions of sessions.  This
option causes only the first N number of sessions to be saved.  All sessions
after this number are ignored, but sessions split before this number will
continue to have their queries split even if those queries appear near the end
of the log and after this number has been reached.

=item --only-select

group: Play

Play only SELECT and USE queries; ignore all others.

=item --password

short form: -p; type: string; group: Play

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

=item --play

type: string; group: Play

Play (execute) session files created by L<"--split">.

The argument to play must be a comma-separated list of session files
created by L<"--split"> or a directory.  If the argument is a directory,
ALL files in that directory will be played.

=item --port

short form: -P; type: int; group: Play

Port number to use for connection.

=item --print

group: Play

Print queries instead of playing them; requires L<"--play">.

You must also specify L<"--play"> with L<"--print">.  Although the queries
will not be executed, L<"--play"> is required to specify which session files to
read.

=item --quiet

short form: -q

Do not print anything; disables L<"--verbose">.

=item --[no]results

default: yes

Print L<"--play"> results to files in L<"--base-dir">.

=item --session-files

type: int; default: 8; group: Split

Number of session files to create with L<"--split">.

The number of session files should either be equal to the number of
L<"--threads"> you intend to L<"--play"> or be an even multiple of
L<"--threads">.  This number is important for maximum performance because it:
  * allows each thread to have roughly the same amount of sessions to play
  * avoids having to open/close many session files
  * avoids disk IO overhead by doing large sequential reads

You may want to increase this number beyond L<"--threads"> if each session
file becomes too large.  For example, splitting a 20G log into 8 sessions
files may yield roughly eight 2G session files.

See also L<"--max-sessions">.


=item --set-vars

type: string; group: Play; default: wait_timeout=10000

Set these MySQL variables.  Immediately after connecting to MySQL, this string
will be appended to SET and executed.

=item --socket

short form: -S; type: string; group: Play

Socket file to use for connection.

=item --split

type: string; group: Split

Split log by given attribute to create session files.

Valid attributes are any which appear in the log: Thread_id, Schema,
etc.

=item --split-random

group: Split

Split log without an attribute, write queries round-robin to session files.

This option, if specified, overrides L<"--split"> and causes the log to be
split query-by-query, writing each query to the next session file in round-robin
style.  If you don't care about "sessions" and just want to split a lot into
N many session files and the relation or order of the queries does not matter,
then use this option.

=item --threads

type: int; default: 2; group: Play

Number of threads used to play sessions concurrently.

Specifies the number of parallel processes to run.  The default is 2.  On
GNU/Linux machines, the default is the number of times 'processor' appears in
F</proc/cpuinfo>.  On Windows, the default is read from the environment.
In any case, the default is at least 2, even when there's only a single
processor.

See also L<"--session-files">.

=item --type

type: string; group: Split

The type of log to L<"--split"> (default slowlog).  The permitted types are

=over

=item binlog

Split the output of running C<mysqlbinlog> against a binary log file.
Currently, splitting binary logs does not always work well depending
on what the binary logs contain.  Be sure to check the session files
after splitting to ensure proper L<"OUTPUT">.

If the binary log contains row-based replication data, you need to run
C<mysqlbinlog> with options C<--base64-output=decode-rows --verbose>,
else invalid statements will be written to the session files.

=item genlog

Split a general log file.

=item slowlog

Split a log file in any variation of MySQL slow-log format.

=back

=item --user

short form: -u; type: string; group: Play

User for login if not current user.

=item --verbose

short form: -v; cumulative: yes; default: 0

Increase verbosity; can be specified multiple times.

This option is disabled by L<"--quiet">.

=item --version

Show version and exit.

=item --wait-between-sessions

type: array; default: 0; group: Play

Not implemented yet.

The wait time is given in seconds with microsecond precision and can be either
a single value or a range.  A single value causes an exact wait; example:
0.010 = wait 10 milliseconds.  A range causes a random wait between
the given value times; example: 0.001,1 = random wait from 1 millisecond to
1 second.

=item --[no]warnings

default: no; group: Play

Print warnings about SQL errors such as invalid queries to STDERR.

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

You need Perl and some core packages that ought to be installed in any
reasonably new version of Perl.

=head1 BUGS

For a list of known bugs see L<http://www.maatkit.org/bugs/mk-log-player>.

Please use Google Code Issues and Groups to report bugs or request support:
L<http://code.google.com/p/maatkit/>.  You can also join #maatkit on Freenode to
discuss Maatkit.

Please include the complete command-line used to reproduce the problem you are
seeing, the version of all MySQL servers involved, the complete output of the
tool when run with L<"--version">, and if possible, debugging output produced by
running with the C<MKDEBUG=1> environment variable.

=head1 COPYRIGHT, LICENSE AND WARRANTY

This program is copyright 2008-2011 Percona Inc.
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

=head1 ABOUT MAATKIT

This tool is part of Maatkit, a toolkit for power users of MySQL.  Maatkit
was created by Baron Schwartz; Baron and Daniel Nichter are the primary
code contributors.  Both are employed by Percona.  Financial support for
Maatkit development is primarily provided by Percona and its clients. 

=head1 VERSION

This manual page documents Ver 1.0.9 Distrib 7540 $Revision: 7531 $.

=cut

__END__
:endofperl
