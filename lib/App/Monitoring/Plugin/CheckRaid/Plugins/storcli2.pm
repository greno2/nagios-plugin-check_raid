package App::Monitoring::Plugin::CheckRaid::Plugins::storcli2;

use base 'App::Monitoring::Plugin::CheckRaid::Plugin';
use strict;
use warnings;
use JSON qw( decode_json );
use Data::Dumper;

sub program_names {
	qw(storcli2);
}

sub commands {
	{
                'pdlist' => ['-|', '@CMD', '/call', '/eall', '/sall', 'show', 'nolog', 'J'],
                'ldinfo' => ['-|', '@CMD', '/call', '/vall', 'show', 'all', 'nolog', 'J'],
	}
}

# parse physical devices
sub parse_pd {
	my $this = shift;

	my $fh = $this->cmd('pdlist');
	my $output = "";
        while (<$fh>) {
	  $output=$output.$_;
	}	
        $this->critical unless close $fh;
	my $decoded_json = decode_json( $output );
        return $decoded_json;
}

sub parse_ld {
        my $this = shift;

        my $fh = $this->cmd('ldinfo');
        my $output = "";
        while (<$fh>) {
          $output=$output.$_;
        }
        $this->critical unless close $fh;
        my $decoded_json = decode_json( $output );
        return $decoded_json;
}

sub parse {
	my $this = shift;

	my $pd = $this->parse_pd;
	my $ld = $this->parse_ld;
	return {
		logical => $ld->{'Controllers'}[0]{'Response Data'}{'Virtual Drives'},
		physical => $pd->{'Controllers'}[0]{'Response Data'}{'Drive Information'},
	};
}

sub check {
	my $this = shift;

	my $c = $this->parse;

	my @vstatus;
	foreach my $vol (@{$c->{logical}}) {
		push(@vstatus, sprintf "%s:%s", $vol->{'VD Info'}{'Name'}, $vol->{'VD Info'}{'State'});

                if ($vol->{'VD Info'}{'State'} ne 'Optl') {
                	$this->critical;
                }
	}

	my %dstatus;
	foreach my $dev (sort {$a->{'PID'} <=> $b->{'PID'}} @{$c->{physical}}) {
		if ($dev->{'Status'} eq 'Online') {
			push(@{$dstatus{$dev->{'Status'}}}, sprintf "%s", $dev->{'EID:Slt'});
		} else {
			$this->critical;
                        push(@{$dstatus{$dev->{'Status'}}}, sprintf "%s (%s)", $dev->{'EID:Slt'}, $dev->{'Model'});
		}
	}

	my @cstatus;
	push(@cstatus, 'Volumes(' . ($#{$c->{logical}} + 1) . '): ' . join(',', @vstatus));
	push(@cstatus, 'Devices(' . ($#{$c->{physical}} + 1) . '): ' . $this->join_status(\%dstatus));
	my @status = join('; ', @cstatus);

	return unless @status;

	# denote this plugin as ran ok
	$this->ok;

	$this->message(join(' ', @status));
}

1;
