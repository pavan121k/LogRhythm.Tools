using namespace System
using namespace System.Collections.Generic
using namespace Microsoft.ActiveDirectory.Management

Function Get-LrtADUserInfo {
    <#
    .SYNOPSIS 
        Retrieves information about and Active Directory user object.
    .DESCRIPTION
        The Get-LrtADUserInfo cmdlet retrieves information about an Active Directory 
        user object, and calculates or looks up information that is commonly desired,
        such as determining if an account is a Service Account, and the number of days
        since the last password change.
    .PARAMETER Identity
        Specifies an Active Directory user in the form of a valid SamAccountName.
    .INPUTS
        None - does not support pipeline.
    .OUTPUTS
        An object with the following fields is returned:
        - Name:             [string]    Common Name (CN)
        - SamAccountName:   [string]    Account Logon (7Letter)
        - Title             [string]    User Title
        - EmailAddress:     [string]    SMTP AddressGet
        - Exists:           [boolean]   User Exists
        - Enabled:          [boolean]   User is Enabled
        - LockedOut:        [boolean]   Account is Locked
        - PasswordExpired:  [boolean]   Password is Expired
        - PasswordAge:      [integer]   Days since Password Changed
        - Manager:          [ADUser]    User's manager
        - OrgUnits:         [List]      OU Hierarchy
        - ADUser:           [ADUser]    Full ADUser Object
        - Groups:           [List]      ADGroups this user belongs to
        - Exceptions:       [List]      List of System.Exceptions raised during the
                                        execution of this command.
    .EXAMPLE
        $UserInfo = Get-LrtADUserInfo -Identity bjones
    .EXAMPLE
        PS C:\> if((Get-LrtADUserInfo bjones).HasManager) { "Has a manager." }
        ---
        Determine if a the account has a manager.
    #>

    [CmdletBinding()]
    Param(
        [Parameter(
            Mandatory = $true,
            ValueFromPipeline = $true,
            ValueFromPipelineByPropertyName = $true,
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [ADUser] $Identity,


        [Parameter(Mandatory = $false, Position = 1)]
        [string] $Server = $LrtConfig.ActiveDirectory.Server,


        [Parameter(Mandatory = $false, Position = 2)]
        [pscredential] $Credential = $LrtConfig.ActiveDirectory.Credential
    )


    Begin {
        # Import Module ActiveDirectory
        if (! (Import-LrtADModule)) {
            throw [Exception] "LogRhythm.Tools Failed to load ActiveDirectory module."
        }
    }



    Process {
        # strip off domain if present - e.g. abc\userbob
        $DomainCheck = $Identity -split "\\"
        if ($DomainCheck.Count -gt 1) {
            $Identity = $DomainCheck[1]
        }


        #region: User Object Structure                                                             
        # User Result Object
        $UserInfo = [PSCustomObject]@{
            Name            = $Identity
            SamAccountName  = ""
            Title           = ""
            EmailAddress    = ""
            Exists          = $false
            Enabled         = $false
            LockedOut       = $false
            PasswordExpired = $false
            PasswordAge     = 0
            Manager         = $null
            OrgUnits        = [List[string]]::new()
            ADUser          = $null
            Groups          = $null
            Exceptions      = [List[Exception]]::new()
        }        
        #endregion



        #region: Lookup User Info                                                                         
        # Try to get [ADUser] from Get-LrtADUser cmdlet, which will use Server/Credential as needed
        try {
            $ADUser = Get-LrtADUser -Identity $Identity -Server $Server -Credential $Credential
            $UserInfo.ADUser = $ADUser
        } catch {
            Write-Warning "[$Identity] User Lookup: $($PSItem.Exception.Message)"
            $UserInfo.Exceptions.Add($PSItem.Exception)
            return $UserInfo
        }


        # Basic Properties
        $UserInfo.Name = $ADUser.Name
        $UserInfo.SamAccountName = $ADUser.SamAccountName
        $UserInfo.Title = $ADUser.Title
        $UserInfo.EmailAddress = $ADUser.EmailAddress
        $UserInfo.Exists = $true
        $UserInfo.Enabled = $ADUser.Enabled
        $UserInfo.LockedOut = $ADUser.LockedOut
        $UserInfo.PasswordExpired = $ADUser.PasswordExpired


        # Password Age - sometimes PasswordLastSet is null
        if ($ADUser.PasswordLastSet -is [datetime]) {
            $UserInfo.PasswordAge = (New-TimeSpan -Start $ADUser.PasswordLastSet -End (Get-Date)).Days    
        } else {
            $UserInfo.PasswordAge = $ADUser.PasswordLastSet
        }
        #endregion



        #region: Lookup Manager Info                                                                      
        # Get Manager Info
        if ($ADUser.Manager) {
            try {
                $UserInfo.Manager = Get-LrtADUser -Identity $ADUser.Manager -Server $Server -Credential $Credential
            }
            catch {
                Write-Warning "[$Identity] Manager Lookup: $($PSItem.Exception.Message)"
                $UserInfo.Exceptions.Add($PSItem.Exception)
                # if something goes wrong we will just plug in the default manager field into the result
                # instead of the manager's name.
                $UserInfo.Manager = $ADUser.Manager
            }
        }        
        #endregion


        
        #region: Lookup Groups                                                                            
        # Run the appropriate version of Get-ADGroup
        try {
            if ($Server) {
                if ($Credential) {
                    $UserInfo.Groups = $ADUser.MemberOf | Get-ADGroup -Server $Server -Credential $Credential
                } else {
                    $UserInfo.Groups = $ADUser.MemberOf | Get-ADGroup -Server $Server
                }
            } else {
                if ($Credential) {
                    Write-Verbose "Get-ADUser Options: +Credential"
                    $UserInfo.Groups = $ADUser.MemberOf | Get-ADGroup -Credential $Credential
                } else {
                    $UserInfo.Groups = $ADUser.MemberOf | Get-ADGroup
                }
            }
        } catch {
            Write-Warning "[$Identity] Group Lookup: $($PSItem.Exception.Message)"
            $UserInfo.Exceptions.Add($PSItem.Exception)
        }
        #endregion



        #region: Org Unit Info                                                                     
        $DN = ($ADUser.DistinguishedName) -split ','
        foreach ($value in $DN) {
            if ($value -match $OUPattern) {
                $UserInfo.OrgUnits.Add(($value -split '=')[1])
            }
        }
        #endregion


        return $UserInfo
    }



    End { }

}