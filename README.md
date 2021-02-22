# Summary
A script to find GPOs which have no links, or have other undesirable configurations.  

The script will return a Powershell object containing an array of GPO objects, along with custom properties identifying which/how many GPOs have potentially undesirable configurations.

The script will optionally log all progress to a log file, to the console, and/or export the results to a CSV file.  

Table of contents:
  - [Usage](#Usage)
  - [Examples](#Examples)
  - [Parameters](#Parameters)
  - [Output](#Output)
  - [Notes](#Notes)
<br />

# Usage
1. Download `Audit-MisconfiguredGpos.psm1`.
2. Import it as a module: `Import-Module "c:\path\to\Audit-MisconfiguredGpos.psm1"`.
3. Run the module as your SU account, using the examples and parameter documentation provided below.
<br />
 
# Examples
It's recommended to capture the output to a variable, and select for the data you want, e.g.:  
`$object = Audit-MisconfiguredGpos` or `$object = Audit-MisconfiguredGpos -GetFullReports`

Once you have the object, you can use the following examples.  

See the [Output](#Output) section below for more details on the structure of the returned `$object`.  
<br />

## Examples which are always valid
These examples do not require `-GetFullReports`.
<br />

### Get overall statistics:  
- `$object`  
- Note: `MatchingGposCount` + `MisnamedGposCount` should equal `LinkedGposCount` + `UnlinkedGposCount<Slow|Fast>`.  
<br />

### Get all GPOs which match the given `-DisplayNameQuery` and have zero links:  
- `$object.Gpos | Where { ($_._Matches -eq $true) -and ($_._LinksCountFast -eq 0) } | Select DisplayName`  
<br />

### Get all misnamed GPOs (i.e. linked to the given `-OUDN`, but which do not match the given `-DisplayNameQuery`):  
- `$object.Gpos | Where { ($_._LinksCountFast -gt 0) -and ($_._Matches -eq $false) } | Select DisplayName `  
<br />

### Get all matching GPOs which have both their Computer and User configuration disabled:  
- `$object.Gpos | Where { ($_._Matches -eq $true) -and ($_.GpoStatus -eq "AllSettingsDisabled") } | Select DisplayName`  
<br />

### Get all GPOs which have WMI filters:
- `$object.Gpos | Where { $_.WmiFilter -ne $null } | Select DisplayName,WmiFilter`
<br />

### Get all GPOs which have a description matching a given string:
- `$object.Gpos | Where { $_.Description -like "*test*" } | Select DisplayName,Description`
<br />

## Examples which are only valid when `-GetFullReports` is specified
These examples rely on data only gathered when `-GetFullReports` is specified.
<br />

### Get all matching GPOs which have links, but all links are disabled:  
- `$object.Gpos | Where { $_._AllLinksDisabled -eq $true } | Select DisplayName`  
<br />

### Get all matching GPOs which have links, but at least one link is disabled:  
- `$object.Gpos | Where { $_._SomeLinksDisabled -eq $true } | Select DisplayName`  
<br />

### Get all matching GPOs which have User settings enabled, but have none configured:
- `$object.Gpos | Where { ($_.User.Enabled -eq "true") -and ($_._UserSettingsConfigured -eq $false) } | Select DisplayName`
<br />

### Get all matching GPOs which have Computer settings configured, but disabled:
- `$object.Gpos | Where { ($_._ComputerSettingsConfigured -eq $true) -and ($_.Computer.Enabled -eq "false") } | Select DisplayName`
<br />

### Confirm that both fast and slow methods of counting unlinked GPOs agree on the result:  
```powershell
$object.UnlinkedGposCountFast
($object.Gpos | Where { ($_._Matches -eq $true) -and ($_._LinksCountFast -eq 0) }).count
$object.UnlinkedGposCountSlow
($object.Gpos | Where { ($_._Matches -eq $true) -and ($_._LinksCountSlow -eq 0) }).count
```
<br />

## Examples of remediation
:warning: `Audit-MisconfiguredGpos` does NOT make ANY changes to AD. It is meant solely for gathering information to inform your decisions and actions. After using it to gather a list of GPOs you want to take action on, you should review those GPOs to ensure they should actually be changed, before taking any action.  

The following examples may be run independently of `Audit-MisconfiguredGpos`, and are provided for convenient reference.  
<br />

### Disable User and Computer settings on GPOs where they are enabled, but not configured:
- WIP
<br />

### Remove GPOs named like "*X*", but exclude certain GPOs:
- Note: At UIUC, we (edge IT) don't actually create or remove GPOs, as that is done centrally. This scenario is provided primarily as an example of how to exclude GPOs.

<details>
<summary><i>Click to expand</i></summary>

```powershell
# Get all the data
$object = Audit-MisconfiguredGpos

# Select all GPOs that match a query.
# In this example, we're selecting all GPOs named like "*Summer 2020 Test*", and storing them in a new variable.
$testGpos = $object.Gpos | Where { $_.DisplayName -like "*Summer 2020 Test*" }

# Print the list of the GPOs in question:
$testGpos | Select DisplayName

# You indepentently check these GPOs that each of these GPOs should be removed.
# You've confirmed this, except there's one that needs to remain, which is named "ENGR Summer 2020 Test GPO (Original)".

# Check how many GPOs are currently in the variable:
$testGpos.count # Outputs 10

# Make a new variable that doesn't contain the GPO you want to keep:
$gposToRemove = $testGpos | Where { $_.DisplayName -ne "ENGR Summer 2020 Test GPO (Original)" }

# Double check that the desired GPO was removed:
$gposToRemove.count # Outputs 9
$gposToRemove | Select DisplayName

# Now you can remove the remaining test GPOs:
$gposToRemove | ForEach-Object { Write-Host "Removing GPO: `"$($_.DisplayName)`""; Remove-GPO -Name $_.DisplayName }
```
</details>
<br />

# Parameters

### -Domain \<string\>
Optional string.  
The domain to limit the GPO search to.  
Default is `ad.uillinois.edu`.  

### -DisplayNameFilter \<string\>
Optional string.  
The wildcard query used to filter GPOs by their `DisplayName` property.  
Default is `ENGR*`.  

### -OUDN \<string\>
Optional string.  
The DistniguishedName of the OU to look for GPO links in.  
Default is `OU=Engineering,OU=Urbana,DC=ad,DC=uillinois,DC=edu`.  

### -GetFullReports
Optional switch.  
If specified, a full GPO report will be retrieved for each matching GPO.  
This takes significantly longer, about 1 extra second for every 2 matching GPOs. For all GPOs matching `ENGR*` this takes about 12 minutes, versus 2 minutes if `-GetFullReports` is omitted.  
  - When `-GetFullReports` is omitted, the script gathers a list of all GPOs matching `-DisplayNameFilter`, and a list of GPOs linked to all OUs under `-OUDN`, and takes the difference to determine which GPOs are unlinked. This is faster because no GPO reports must be retrieved.
  - When `-GetFullReports` is specified, the script takes a more traditional approach. It gets the full GPO report for each GPO matching `-DisplayNameFilter`, and uses the GPO report data to determine whether they have any links.

However this allows for gathering additional data:
  - A second check for which GPOs are unlinked.
  - Whether each matching GPO has any _disabled_ links, and whether _all_ of a given GPO's links are disabled.
  - A tally of how many matching GPOs have _some_ disabled links, and how many have _all_ of their links disabled.

### -Csv
Optional string.  
The full path of a file to export polled data to, in CSV format.  
If omitted, no CSV will be created.  
If `:TS:` is given as part of the string, it will be replaced by a timestamp of when the script was started, with a format specified by `-LogFileTimestampFormat`.  
Specify `:ENGRIT:` to use a default path (i.e. `c:\engrit\logs\Audit-MisconfiguredGpos_<timestamp>.csv`).  

### -Log
Optional string.  
The full path of a file to log to.  
If omitted, no log will be created.  
If `:TS:` is given as part of the string, it will be replaced by a timestamp of when the script was started, with a format specified by `-LogFileTimestampFormat`.  
Specify `:ENGRIT:` to use a default path (i.e. `c:\engrit\logs\Audit-MisconfiguredGpos_<timestamp>.log`).  

### -Quiet
Optional switch.  
If specified, progress output is not logged to the console.  

### -Indent \<string\>
Optional string.  
The string used as an indent, when indenting log entries.  
Default is four space characters.  

### -LogFileTimestampFormat \<string\>
Optional string.  
The format of the timestamp used in filenames which include `:TS:`.  
Default is `yyyy-MM-dd_HH-mm-ss`.  

### -LogLineTimestampFormat \<string\>
Optional string.  
The format of the timestamp which prepends each log line.  
Default is `[HH:mm:ss]⎵`.  

### -Verbosity \<int\>
Optional integer.  
The level of verbosity to include in output logged to the console and logfile.  
Default is `0`.  
Specify `1` for more verbose logging.  
Specify `2` for even more verbose logging.  
<br />

# Output

### The parent object
To see the overall structure of the returned object, simply output it: `$object`.  

The object returned by the script has the following structure:  

<details>
<summary><i>Click to expand</i></summary>

- Return object
  - GposCount: Total number of GPOs.
  - MatchingGposCount: Total number of GPOs whose DisplayName matches the given `-DisplayNameFilter`.
  - LinkedGposCount: Total number of GPOs which have at least one link.
  - UnlinkedGposCountFast: Total number of GPOs which have zero links (calculated via fast method).
  - UnlinkedGposCountSlow: Total number of GPOs which have zero links (calculated via slow method, only when `-GetFullReports` is specified).
  - SomeLinksDisabledGposCount: Total number of GPOs which have links where at least one link is disabled (calculated via slow method, only when `-GetFullReports` is specified).
  - AllLinksDisabledGposCount: Total number of GPOs which have links where all links are disabled (calculated via slow method, only when `-GetFullReports` is specified).
  - MisnamedGposCount: Total number of GPOs which have at least one link, but whose DisplayName does _not_ match the given `-DisplayNameFilter`.
  - BothSettingsDisabledGposCount: Total number of GPOs which have both their Computer and User settings disabled.
  - ComputerSettingsEnabledButNotConfiguredGposCount: Total number of GPOs which have Computer configuration settings enabled, but have no such settings defined.
  - ComputerSettingsConfiguredButNotEnabledGposCount: Total number of GPOs which have Computer configuration settings configured, but have them disabled.
  - UserSettingsEnabledButNotConfiguredGposCount: Total number of GPOs which have User configuration settings enabled, but have no such settings defined.
  - UserSettingsConfiguredButNotEnabledGposCount: Total number of GPOs which have User configuration settings configured, but have them disabled.
  - Gpos: Array of all GPOs.
  - Ous: Array of all OUs under (and including) the given `-OUDN`.
  - AllGpoLinks: Flat array of all GPO links on the discovered OUs, including duplicated (i.e. where GPOs are linked to more than one OU).
  - UniqueGpoLinks: Flat array of all unique GPO links on the discovered OUs.
  - StartTime: When the module was started.
  - EndTime: When the module finished running.
  - RunTime: How long the module took to run.
</details>
<br />

### GPO objects
To see a specific GPO object (one of many in the `$object.Gpos` array), you can use e.g.:  
`$object.Gpos | Where { $_.DisplayName -like "*ENGR US Administra*" } | Select *`  
` | Select *` is needed to see the additional custom properties added by the script, because GPO objects are a built-in type of object which only show their normal properties by default. These custom properties are prepended with `_`.  

[GPO objects](https://docs.microsoft.com/en-us/previous-versions/windows/desktop/wmi_v2/class-library/gpo-class-microsoft-grouppolicy) have the following structure:  

<details>
<summary><i>Click to expand</i></summary>

- GPO object
  - \_Matches: A boolean representing whether or not this GPO's DisplayName property matches the given `-DisplayNameFilter`.
  - \_LinksCountFast: The number of links this GPO has across all OUs under (and including) the given `-OUDN`.
  - \_Report: The full GPO report, in the format of a Powershell XML object, as returned by `Get-GPOReport -Guid $guid -ReportType "XML"`. Only present when `-GetFullReports` is specified, and only on GPOs where `_Matches -eq $true`.
  - \_LinksCountSlow: The number of links this GPO has according to its `_Report`. Only present when `-GetFullReports` is specified.
  - \_SomeLinksDisabled: A boolean representing whether or not this GPO has one or more links which are disabled. Simply calculated from the data in `_Report` for more convenient searchability. Only present when `-GetFullReports` is specified.
    - Roughly equivalent to `($gpo._Report.GPO.LinksTo.Enabled) -contains "false"`.
  - \_AllLinksDisabled: A boolean representing whether or not all of this GPO's links are disabled. Simply calculated from the data in `_Report` for more convenient searchability. Only present when `-GetFullReports` is specified.
    - Roughly equivalent to `$unique = ($gpo._Report.GPO.LinksTo.Enabled | Select -Unique); ($unique.count -eq 1) -and ($unique -contains "false")`.
  - \_ComputerSettingsConfigured: A boolean representing whether or not this GPO has any Computer configuration settings defined. Calculated from data in `_Report` for more convenient searchability. Only present when `-GetFullReports` is specified.
    - Equivalent to `$gpo._Report.GPO.Computer.ExtensionData -eq $null`.
  - \_UserSettingsConfigured: A boolean representing whether or not this GPO has any User configuration settings defined. Calculated from data in `_Report` for more convenient searchability. Only present when `-GetFullReports` is specified.
    - Equivalent to `$gpo._Report.GPO.User.ExtensionData -eq $null`.
  - Id: The GPO's GUID (in [UUID format](https://en.wikipedia.org/wiki/Universally_unique_identifier)).
  - DisplayName: The GPO's friendly name.
  - Path: The GPO's distinguished path.
  - Owner: The GPO's owner.
  - DomainName: The domain where the GPO exists.
  - CreationTime: When the GPO was created.
  - ModificationTime: When the GPO was last modified.
  - UserVersion: The revision number of the GPO's User configuration. Updated whenever it is modified. Only shown when ` | Select *` is omitted.
  - User: A [`UserConfiguration`](https://docs.microsoft.com/en-us/previous-versions/windows/desktop/wmi_v2/class-library/userconfiguration-class-microsoft-grouppolicy) object representing the User settings configured in the GPO. Only shown when ` | Select *` is used.
  - ComputerVersion: The revision number of the GPO's Computer configuration. Updated whenever it is modified. Only shown when ` | Select *` is omitted.
  - Computer: A [`ComputerConfiguration`](https://docs.microsoft.com/en-us/previous-versions/windows/desktop/wmi_v2/class-library/computerconfiguration-class-microsoft-grouppolicy) object representing the Computer settings configured in the GPO. Only shown when ` | Select *` is used.
  - GpoStatus: The state of the User and Computer configurations. [Possible values](https://docs.microsoft.com/en-us/previous-versions/windows/desktop/wmi_v2/class-library/gpostatus-enumeration-microsoft-grouppolicy) are `AllSettingsEnabled`, `UserSettingsDisabled`, `ComputerSettingsDisabled`, and `AllSettingsDisabled`.
  - WmiFilter: If the GPO is configured to use a WMI filter, this will contain a [WmiFilter obejct](https://docs.microsoft.com/en-us/previous-versions/windows/desktop/wmi_v2/class-library/wmifilter-class-microsoft-grouppolicy), otherwise it will ne `$null`.
  - Description: The GPO's description field string.
</details>
<br />

### User and Computer configuration objects
<details>
<summary><i>Click to expand</i></summary>

The UserConfiguration and ComputerConfiguration objects which are part of the normal GPO object only contain meta-data, and contain nothing about the actual settings defined in the GPO. This information is only available in a full GPO report, such as `$gpo._Report.GPO.Computer`. The actual settings defined in a GPO are recorded in `$gpo._Report.GPO.Computer.ExtensionData`. GPOs which do not have any settings defined for a particular configuration object will have no `ExtensionData` node. In other words `$gpo._Report.GPO.Computer.ExtensionData` will equal `$null`.  

This is leveraged to identify GPOs which:  
  - have settings configured, but which have those settings disabled
  - have settings enabled, but which have no settings configured
</details>
<br />

# Notes
- You can run this as your non-SU account, but you may recieve some errors when the script tries to gather data about campus-level GPO.
- By mseng3. See my other projects here: https://github.com/mmseng/code-compendium.
