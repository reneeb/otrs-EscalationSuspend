# --
# Kernel/System/Ticket/Custom/EscalationSuspend.pm
# Copyright (C) 2015 Perl-Services.de, http://perl-services.de
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Ticket::Custom::EscalationSuspend;

use strict;
use warnings;

use List::Util qw(first);

our $ObjectManagerDisabled = 1;

# disable redefine warnings in this scope
{
    no warnings 'redefine';

    my $DateCalc   = Kernel::System::Ticket->can('TicketEscalationDateCalculation');
    my $IndexBuild = Kernel::System::Ticket->can('TicketEscalationIndexBuild');

# TODO
    *Kernel::System::Ticket::TicketEscalationDateCalculation = sub {
    };

    *Kernel::System::Ticket::TicketEscalationIndexBuild = sub {
        my ( $Self, %Param ) = @_;

        my $TimeObject   = $Kernel::OM->Get('Kernel::System::Time');
        my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
        my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
        my $MainObject   = $Kernel::OM->Get('Kernel::System::Main');

        my $Debug         = $ConfigObject->Get('EscalationSuspend::Debug');
        my $SuspendStates = $ConfigObject->Get('EscalationSuspend::States') || [];

        if ( $Debug ) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => $MainObject->Dump( $SuspendStates ),
            );
        }

        my %EscalationInfo = $Self->TicketEscalationInfoGet( %Param );

        if ( $Debug ) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => $MainObject->Dump( \%EscalationInfo ),
            );
        }

        my %Ticket = $Self->TicketGet(
            TicketID => $Param{TicketID},
            UserID   => $Param{UserID},
        );

# TODO
        if ( first{ $Ticket{State} eq $_ }@{ $SuspendStates || [] } ) {
        }
        else {
        }

        if ( $Debug ) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => $MainObject->Dump( \%EscalationInfo ),
            );
        }

        my %Ticket     = $Self->TicketEscalationGet( %Param );
        my $Success    = $Self->$IndexBuild( %Param );
        my %Escalation = $Self->TicketEscalationGet( %Param );

        if ( $Debug ) {
            $LogObject->Log(
                Priority => 'notice',
                Message  => $MainObject->Dump( [ \%Ticket, \%Escalation ] ),
            );
        }

        # if escalation times are different to the current ones, add a history entry
        TYPE:
        for my $Type ( qw(FirstResponse Update Solution) ) {
            my $Key = $Type . 'TimeDestinationTime';

            next TYPE if !$Escalation{$Key};

            my $Current = $Ticket{$Key} // 0;
            my $New     = $Escalation{$Key};

            next TYPE if $Current == $New;

            my $SystemTime     = $TimeObject->SystemTime();
            my $EscalationType = $Type eq 'FirstResponse' ? 'ResponseTime' : $Type . 'Time';
            my $HistoryName    = join '%%', '', $EscalationType, $SystemTime;

            $Self->HistoryAdd(
                TicketID     => $Param{TicketID},
                CreateUserID => $Param{UserID},
                HistoryType  => 'CalculatedEscalationTime',
                Name         => $HistoryName,
            );
        }

        return $Success;
    };

    sub TicketEscalationGet {
        my ($Self, %Param) = @_;

        my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
        my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');

        for my $Needed ( qw(TicketID UserID) ) {
            if ( !$Param{$Needed} ) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "Need $Needed!",
                );

                return;
            }
        }

        my $SQL = qq~
            SELECT escalation_response_time, escalation_update_time, escalation_solution_time
            FROM ticket t
            WHERE t.id = ?
        ~;

        return if !$DBObject->Prepare(
            SQL   => $SQL,
            Bind  => [ \$Param{TicketID} ],
            Limit => 1,
        );

        my %Escalations = (
            FirstResponseTimeDestinationTime => 0,
            UpdateTimeDestinationTime        => 0,
            SolutionTimeDestinationTime      => 0,
        );

        ROW:
        while ( my @Row = $DBObject->FetchrowArray() ) {
            %Escalations = (
                FirstResponseTimeDestinationTime => $Row[0] // 0,
                UpdateTimeDestinationTime        => $Row[1] // 0,
                SolutionTimeDestinationTime      => $Row[2] // 0,
            );
        }

        return %Escalations;
    }

   

    sub TicketEscalationInfoGet {
        my ($Self, %Param) = @_;

        my $LogObject = $Kernel::OM->Get('Kernel::System::Log');
        my $DBObject  = $Kernel::OM->Get('Kernel::System::DB');

        for my $Needed ( qw(TicketID) ) {
            if ( !$Param{$Needed} ) {
                $LogObject->Log(
                    Priority => 'error',
                    Message  => "Need $Needed!",
                );

                return;
            }
        }

# TODO
        my $SQL = qq~
            SELECT 
            FROM ticket_history th
                INNER JOIN ticket_history_type tht
                    ON th.history_type_id = tht.id
            WHERE th.ticket_id = ?
                AND tht.name IN ('CalculatedEscalationTime','PausedEscalationTime','')
            ORDER BY th.id
        ~;

        return if !$DBObject->Prepare(
            SQL  => $SQL,
            Bind => [ \$Param{TicketID} ],
        );

        my %EscalationInfo;
        while ( my @Row = $DBObject->FetchrowArray() ) {
            my (undef, $Action, $Type, $Time, $Remaining) = split /\%\%/, $Row[0];

            $EscalationInfo{$Type} = {
                Time      => $Time,
                Action    => $Action,
                Remaining => $Remaining,
            };
        }

        return %EscalationInfo;
    }
}

1;

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
