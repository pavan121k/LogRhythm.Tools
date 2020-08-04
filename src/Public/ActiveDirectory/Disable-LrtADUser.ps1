using namespace System
using namespace System.Management.Automation
using namespace Microsoft.ActiveDirectory.Management

Function Disable-LrtADUser {
    <#
    .SYNOPSIS
        Disable an Active Directory user account.
    .PARAMETER Identity
        AD User Account to disable
    .EXAMPLE
        > Disable-LrtADUser -Identity testuser
    #>
    
    [CmdletBinding(DefaultParameterSetName = "ByADUser")]
    Param(
        [Parameter(
            Mandatory = $true,
            ParameterSetName = "ByADUser",
            ValueFromPipeline = $true,
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [ADUser] $Identity,


        [Parameter(
            Mandatory = $true,
            ParameterSetName = "ByObject",
            ValueFromPipelineByPropertyName = $true,
            Position = 1
        )]
        [Object] $ADUser,


        [Parameter(Mandatory = $false, Position = 1)]
        [switch] $PassThru
    )



    Begin {
        $Me = $MyInvocation.MyCommand.Name

        # Import Module ActiveDirectory
        if (! (Import-LrtADModule)) {
            throw [Exception] "LogRhythm.Tools Failed to load ActiveDirectory module."
        }


        # Determine which parameters to pass to AD cmdlets - Server, Credential, both, or neither.
        $Options = ""
        if ($LrtConfig.ActiveDirectory.Credential) {
            if ($LrtConfig.ActiveDirectory.Server) {
                $Options = "Server+Credential"
            } else {
                $Options = "Credential"
            }
        } else {
            if ($LrtConfig.ActiveDirectory.Server) {
                $Options = "Server"
            }
        }
    }


    Process {
        # If we got a normal ADUser / Name string Get-LrtADUserInfo
        #TODO: /BUG/ need to get-lrtaduserinfo regardless, in case user sends an OLD version of an object.
        #TODO: Need to do the same for Enable-LrtADUser
        if ($Identity) {
            $UserInfo = Get-LrtADUserInfo -Identity $Identity
            # Validate user exists
            if (! $UserInfo.Exists) {
                Write-Verbose "Could not find user [$Identity]."
                throw [ADIdentityNotFoundException] "[$Me]: Cannot find an object with identity '$($UserInfo.Name)'"
            }
            $ADUser = $UserInfo.ADUser
        }

        # If already disabled, return
        if (! $ADUser.Enabled) {
            Write-Verbose "[$Me]: $($ADUser.Name) is already disabled."
            if ($PassThru) {
                # Possibly we should return the userinfo object, but it depends on
                # how other cmdlets in the module use the output.
                # for now, returning the [ADUser] object
                return $ADUser
            } else {
                return $null
            }
        }

        
        # Disable Account
        switch ($Options) {
            "Server+Credential" {
                Write-Verbose "[$Me] options: Server+Credential"
                $ADUser | Disable-ADAccount `
                    -Server $LrtConfig.ActiveDirectory.Server `
                    -Credential $LrtConfig.ActiveDirectory.Credential `
                    -ErrorAction Stop
            }
            "Credential" {
                Write-Verbose "[$Me] options: Credential"
                $ADUser | Disable-ADAccount `
                    -Credential $LrtConfig.ActiveDirectory.Credential `
                    -ErrorAction Stop
            }
            "Server" {
                Write-Verbose "[$Me] options: Server"
                $ADUser | Disable-ADAccount `
                    -Server $LrtConfig.ActiveDirectory.Server `
                    -ErrorAction Stop
            }
            Default {
                Write-Verbose "[$Me] options: None"
                $ADUser | Disable-ADAccount -ErrorAction Stop
            }
        }            



        # Check account to ensure it is disabled
        $UserInfo = Get-LrtADUserInfo -Identity $ADUser
        if (! $UserInfo.Enabled) {
            Write-Verbose "[$Me]: Successfully disabled '$($UserInfo.Name)'"
        } else {
            throw [Exception] "[$Me]: Failed to disable object '$($UserInfo.Name)'"
        }


        # Implement PassThru
        if ($PassThru) {
            return $UserInfo.ADUser
        }
    }

    End {

    }


}