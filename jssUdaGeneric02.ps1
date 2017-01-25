<# Code for grabbing JSS-SCCM importer's retrieved UserName field and comparing with existing UDA database to identify if new UDA
   relationships should be created. This utilizes the GUID created for devices to compare the fields and allows logic to skip devices previously
   translated and instantiated by this code. Expiration rules will still apply if configured within SCCM.
   Last Updated: 012517dc
#>
clear

# Validate your default installation path for SCCM below
Import-Module 'C:\Program Files (x86)\Microsoft Configuration Manager\AdminConsole\bin\ConfigurationManager.psd1' -Force
# Modify your hard-coded site name to manage below
Set-Location H01:
$appName = "yourNameToShowInEventLog"
# For event logging the appName variable needs to be run through New-EventLog to first register the source.
Write-EventLog -LogName Application -Source "$appName" -EntryType Information -EventId 4444 -Message `
                "UDA Automation Start: Beginning sync of JSS user inventory to SCCM AD objects..."
<# Setting variables. The domain is used for prepending the fields coming from JSS. If Down-Level Logon Names (eg. DOMAIN\username) are used
   in JSS, the domain variable should be set to an empty string. Note that the queries below used hard-coded server/database names, but
   otherwise the views/tables/fields should be portable between instances of SCCM. JSS usernames should NEVER contain PowerShell escape
   characters - can't imagine a scenario where you might want to.
#>
$domain = 'yourdomain'
$sqlserver01 = "(local)"
$database01 = "sqlServerName"
$smsSiteCode = "sccmSiteCode"
$smsServer01 = "sccmServerName"
$query01 = "
    /* Grab GUID, Machine Name and Local User info for Mac user assessment. We need all these values for manipulating the object eventually */
    SELECT [CM_H01].[dbo].[v_R_System].[ResourceID] AS ResourceGUID
          ,[CM_H01].[dbo].[v_R_System].[Name0] AS [MachineName]
	      ,[CM_H01].[dbo].[v_GS_COMPUTER_SYSTEM].UserName0 AS [JSSUsername]
    FROM [CM_H01].[dbo].[v_R_System]
	    INNER JOIN [CM_H01].[dbo].[v_GS_COMPUTER_SYSTEM] ON [CM_H01].[dbo].[v_R_System].ResourceID = [CM_H01].[dbo].[v_GS_COMPUTER_SYSTEM].ResourceID
    /* Check if this is OSX and verify the user field has been populated in and from JSS */
        WHERE (Operating_System_Name_and0 IS NULL
            AND
        ([CM_H01].[dbo].[v_GS_COMPUTER_SYSTEM].UserName0 IS NOT NULL
            AND
         [CM_H01].[dbo].[v_GS_COMPUTER_SYSTEM].UserName0 <> ''))
    /* Sort for readability, logging */
    ORDER BY [CM_H01].[dbo].[v_R_System].[Name0]
    "
$query02 = "
    /* Grab UUN and GUID for assessment against Mac user pull */
    SELECT [UniqueUserName] AS UniqueUserName
        ,[MachineResourceID] AS MachineResourceID
    FROM [CM_H01].[dbo].[v_UserMachineRelation]
    ORDER BY [CM_H01].[dbo].[v_UserMachineRelation].[MachineResourceID]
    "
# SQL connections
$sqlConn01 = New-Object System.Data.SqlClient.SqlConnection
$sqlConn01.ConnectionString = "Server=$sqlserver01;Database=$database01;Integrated Security=True"
$sqlCmd01 = New-Object System.Data.SqlClient.SqlCommand
$sqlCmd01.CommandText = $query01
$sqlCmd01.Connection = $sqlConn01
$sqlAdapter01 = New-Object System.Data.SqlClient.SqlDataAdapter
$sqlAdapter01.SelectCommand = $sqlCmd01
$sqlConn01.Open()
$dsMacs01 = New-Object System.Data.DataSet
# Fill Macs dataset
$sqlAdapter01.Fill($dsMacs01)
$sqlConn01.Close()
Write-Host '... Mac devices found/filled.' -f Green
# Fill UDA dataset
$dsUDA01 = New-Object System.Data.DataSet
$sqlCmd02 = New-Object System.Data.SqlClient.SqlCommand
$sqlCmd02.CommandText = $query02
$sqlCmd02.Connection = $sqlConn01
$sqlAdapter02 = New-Object System.Data.SqlClient.SqlDataAdapter
$sqlAdapter02.SelectCommand = $sqlCmd02
$sqlConn01.Open()
$sqlAdapter02.Fill($dsUDA01)
$sqlConn01.Close()
Write-Host '... Existing UDA records for devices.' -f Green

ForEach ($Row in $dsMacs01.Tables[0].Rows)
{
    $abort = $false
    $varResourceGUID = $Row.ResourceGUID
    $varMachineName = $Row.MachineName
    $varJSSUsername = $Row.JSSUsername
#   Write-Host $varResourceGUID $varMachineName $varJSSUsername

    # Loop through UDA dataset to identify existing matches that need to be excluded from record creation
    ForEach ($Row in $dsUDA01.Tables[0].Rows)
    {
        $varUUN = $Row.UniqueUserName
        $varMachineResourceID = $Row.MachineResourceID
        # Write-Host $varUUN $varMachineResourceID

        # Evaluate if Machine/User match already exists in UDA table and prepend domain to JSS user for check
        If ($varResourceGUID.Equals($varMachineResourceID) -And $varUUN.Equals("$domain\$varJSSUsername"))
            {
                $abort = $true
                # Abort, relationship already exists. Break below to save cycles.
                break
            }
            Else
            {
                # Keep looking for matches...
            }
    }

    # If abort flag has been raised for a device above do not process the invocation
    If ($abort -eq $false)
        {
        # Remove old UDA records if there are any
        $oldUdas = get-cmuserdeviceaffinity -devicename $varMachineName
        Write-Host 'Removing'$oldUdas.Count'old UDA records for'$varMachineName
            ForEach($record in $oldUdas) {
                # Update your hard-coded site name below
                Set-Location H01:
                Remove-CMUserAffinityFromDevice -DeviceName $record.ResourceName -UserName $record.UniqueUserName -Force
                Remove-CMDeviceAffinityFromUser -Devicename $record.ResourceName -UserName $record.UniqueUserName -Force
            }

        Invoke-WmiMethod -Namespace root/SMS/site_$($smsSiteCode) -Class SMS_UserMachineRelationship -Name CreateRelationship -ArgumentList `
            @($varResourceGUID, 2, 1, "$domain\$varJSSUsername") -ComputerName $smsServer01
        Write-Host "Making record for: " -nonewline; Write-Host "$varMachineName" -f Magenta -nonewline; `
            Write-Host " using " -nonewline; Write-Host "$varResourceGUID" -f Magenta -nonewline; `
            Write-Host " as GUID and " -nonewline; Write-Host "$domain\$varJSSUsername" -f Magenta -nonewline; Write-Host " as the user."
        Write-EventLog -LogName Application -Source "$appName" -EntryType Information -EventId 4444 -Message `
                "UDA Automation Success: The device $varMachineName has been registered to have affinity with user $domain\$varJSSUsername."
        }
        Else
        {Write-Host "Aborted: the device $varMachineName already has a UDA for user $domain\$varJSSUsername." -f Red}
}
Write-EventLog -LogName Application -Source "$appName" -EntryType Information -EventId 4444 -Message `
                "UDA Automation Complete: Asset sync process completed run."
# EOF