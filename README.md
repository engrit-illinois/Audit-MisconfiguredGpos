# Summary
A script to find Active Directory Group Policy Objects (GPOs) which have no links, or have other potentially undesirable configurations.  

The script will return a Powershell object containing an array of GPO objects, along with custom properties identifying which/how many GPOs have potentially undesirable configurations.

Potential misconfigurations detected:
- GPOs which have zero links
- GPOs with names which do not match a given wildcard query
- GPOs with Computer or User settings which are configured but not enabled
- GPOs with Computer or User settings which are enabled but not configured
- GPOs with disabled links
- GPOs which have Computer or User settings (or both) which are identical to other GPOs

To find GPOs which contain orphaned settings due to those settings being deprecated by ADMX template updates, see [Get-GpoContainingSetting](https://github.com/engrit-illinois/Get-GpoContainingSetting). Specifically, see the example referencing `Extra Registry Settings`.  

This module can also be used to easily query the returned matching GPO objects for any given part of their policy. This can be used to, for example, find all GPOs which have a specific policy configured, and much more.  

The script will optionally log all progress to a log file, to the console, and/or export the results to a CSV file.  

Table of contents:
  - [Usage](#Usage)
  - [Examples](#Examples)
  - [Parameters](#Parameters)
  - [Output](#Output)
  - [Notes](#Notes)
<br />

# Usage
1. Download `Audit-MisconfiguredGpos.psm1` to the appropriate subdirectory of your PowerShell [modules directory](https://github.com/engrit-illinois/how-to-install-a-custom-powershell-module).
2. Customize the default values of the `-Domain`, `-DisplayNameFilter`, and `-OUDN` for your use case at the top of `Audit-MisconfiguredGpos.psm1`.
3. Run the module as your SU account, using the examples and parameter documentation provided below.
<br />
 
# Examples
It's recommended to capture the output to a variable, and select for the data you want, e.g.:  
```powershell
$object = Audit-MisconfiguredGpos
```
See the [Output](#Output) section below for more details on the structure of the returned `$object`.  
<br />

## Examples which are always valid
These examples do not require `-GetFullReports` to be specified.
<br />
<br />

```powershell
$object = Audit-MisconfiguredGpos

# Get overall statistics, i.e. just output the returned object:
# Note: `MatchingGposCount` + `MisnamedGposCount` should be equal to `LinkedGposCount` + `UnlinkedGposCount<Slow|Fast>`.
$object

# GPOs which match the given `-DisplayNameQuery` and have zero links:  
$object.Gpos | Where { ($_._Matches -eq $true) -and ($_._LinksCountFast -eq 0) } | Select DisplayName

# GPOs (i.e. linked to the given `-OUDN`, but which do not match the given `-DisplayNameQuery`):  
$object.Gpos | Where { ($_._LinksCountFast -gt 0) -and ($_._Matches -eq $false) } | Select DisplayName

# GPOs which have both their Computer and User configuration disabled:  
$object.Gpos | Where { ($_._Matches -eq $true) -and ($_.GpoStatus -eq "AllSettingsDisabled") } | Select DisplayName

# GPOs which have any WMI filter configured:
$object.Gpos | Where { $_.WmiFilter -ne $null } | Select DisplayName,WmiFilter

# GPOs which have a WMI filter with a specific name configured:
$object.Gpos | Where { $_.WmiFilter.Name -eq "Windows 10 Client Filter" } | Select DisplayName

# GPOs which have a description matching a given string:
$object.Gpos | Where { $_.Description -like "*test*" } | Select DisplayName,Description

# GPOs which have a blank description:
$object.Gpos | Where { ($_.Description -eq $null) -or ($_.Description -eq "") -or ($_.Description -eq " ") -or ($_.Description.length -lt 1) } | Select DisplayName,Description | Format-Table -AutoSize

# GPOs which have a description under a given length:
$object.Gpos | Where { $_.Description.length -lt 20 } | Select DisplayName,Description | Format-Table -AutoSize

# GPOs which have a description containing specific text:
$object.Gpos | Where { ($_.DisplayName -like "ENGR*") -and ($_.Description -like "*please do not remove*") } | Select DisplayName,Description | Format-Table -AutoSize
```
<br />

## Examples which are only valid when `-GetFullReports` is specified
These examples rely on data only gathered when `-GetFullReports` is specified.
<br />
<br />

```powershell
$object = Audit-MisconfiguredGpos -GetFullReports

# GPOs which have links, but all links are disabled:  
$object.Gpos | Where { $_._AllLinksDisabled -eq $true } | Select DisplayName

# GPOs which have links, but at least one link is disabled:  
$object.Gpos | Where { $_._SomeLinksDisabled -eq $true } | Select DisplayName

# GPOs which have User settings enabled, but have none configured:
$object.Gpos | Where { ($_.User.Enabled -eq "true") -and ($_._UserSettingsConfigured -eq $false) } | Select DisplayName

# GPOs which have Computer settings configured, but disabled:
$object.Gpos | Where { ($_._ComputerSettingsConfigured -eq $true) -and ($_.Computer.Enabled -eq "false") } | Select DisplayName

# GPOs which have a specific setting configured:
$object.Gpos | Where { $_._Report.Computer.ExtensionData.Extension.Policy.Name -eq "Require a password when a computer wakes (plugged in)" } | Select DisplayName

# GPOs which have a specific setting configured, include the actual setting values in the output:
$gpos = $object.Gpos | Where { $_._Report.User.ExtensionData.Extension.Policy.Name -eq "Desktop Wallpaper" }
$gpos | Select DisplayName,
    @{Name="Name";Expression={$_._Report.User.ExtensionData.Extension.Policy.Name}},
    @{Name="State";Expression={$_._Report.User.ExtensionData.Extension.Policy.State}},
    @{Name="Value";Expression={$_._Report.User.ExtensionData.Extension.Policy.EditText.Value}}

# Get the name and state of all settings which are configured in a specific GPO:
$gpo = $object.Gpos | Where { $_.Displayname -eq "ENGR EWS Labs General Settings" }
$gpo._Report.User.ExtensionData.Extension.Policy | Select Name,State

# Confirm that both fast and slow methods of counting unlinked GPOs agree on the result:  
$object.UnlinkedGposCountFast
($object.Gpos | Where { ($_._Matches -eq $true) -and ($_._LinksCountFast -eq 0) }).count
$object.UnlinkedGposCountSlow
($object.Gpos | Where { ($_._Matches -eq $true) -and ($_._LinksCountSlow -eq 0) }).count
```
<br />

## Cache GPO reports / Use cached GPO reports
If for whatever reason you plan to run this module more than once without needing to retrieve updated data from AD, you can use caching to save retrieved GPO reports to an XML file, and use that for future runs instead of retrieving them all from AD again. This is primarily useful for testing purposes, as retrieving GPO reports from AD takes some time, and generates one login per matching GPO, which may raise some red flags with your AD security folks.

```powershell
$object = Audit-MisconfiguredGpos -GetFullReports

# First run
$object = Audit-MisconfiguredGpos -GetFullReports -CacheGpos "c:\gpocache.xml"

# Subsequent runs
$object = Audit-MisconfiguredGpos -GetFullReports -UseCachedGpos "c:\gpocache.xml"
```
<br />

## Examples which are only valid when `-GetFullReports` and `-GetDuplicates` are specified:
These examples rely on data only gathered when `-GetFullReports` and `-GetDuplicates` are both is specified.
<br />
<br />

```powershell
$object = Audit-MisconfiguredGpos -GetFullReports -GetDuplicates

# GPOs with duplicate Computer settings:
$object.Gpos | Where { $_._DuplicateComputerGpos } | Select DisplayName,_DuplicateComputerGpos

# GPOs with duplicate User settings:
$object.Gpos | Where { $_._DuplicateUserGpos } | Select DisplayName,_DuplicateUserGpos

# GPOs with both duplicate Computer and User settings:
$object.Gpos | Where { $_._DuplicateBothGpos } | Select DisplayName,_DuplicateBothGpos
```

Note: In my testing I came across two noteworthy scenarios regarding duplicate GPOs:  
1. Some GPOs which seemingly have no Computer or User settings, still have a vestigial `ExtensionData` node in their GPO report's XML. My assumption is that this is due to the GPOs having originally been configured with settings, but the settings have since been removed, and the XML is simply not entirely cleaned. This appears to be benign as far as the GPO's functionality, however it still causes this module to detect GPOs with identical vestigial data as duplicates. This will not be "fixed" because A) this case is non-trivial to differentiate from legitimately duplicate GPOs and B) this could be considered a misconfiguration, or at least something to investigate, even if it ends up being benign.
2. There were several GPOs which had identical (actual, non-vestigial) settings configured, but which were disabled on one of the GPOs. This is likely due to GPOs being decommissioned and re-used without being fully cleared. For example, a GPO might have certain User settings configured, and is then decommissioned and the User settings are disabled without actually clearing the User settings. The GPO is then reused, leaving the User settings disabled, but configuring Computer settings for the new use case. Meanwhile some other GPO is created which configures those same User settings. Again, this is probably benign, but it's certainly a misconfiguration, similar to any other GPO which has settings configured but disabled. Disabled settings which are not actually intended to be used should be removed entirely.

Editorial note: both of the above scenarios are more or less an eventual consequence of our university's distributed IT, multi-tenant, but centrally-managed AD architecture, where edge IT units are not allowed to directly create new GPOs. This incentivizes the re-use of existing GPOs, instead of deleting GPOs and creating new ones.  
<br />

## Examples of remediation
:warning: `Audit-MisconfiguredGpos` does NOT make ANY changes to AD. It is meant solely for gathering information to inform your decisions and actions. After using it to gather a list of GPOs you want to take action on, you should review those GPOs to ensure they should actually be changed, before taking any action.  

The following examples are only provided as a reference, and should *NOT* be run without modification or a full understanding of the code.  
<br />

### Disable User or Computer settings on GPOs where they are enabled, but not configured:

WIP

One of the most common issues we see with GPOs is when somebody makes a new GPO, configures the Computer settings on it, has no need for the User settings, but leaves the User settings enabled. While this is not technically _problem_, it is an inefficiency, causing extra group policy processing work for computers when somebody logs in. When there is a lot of GPOs to process, this inefficiency adds up and causes logins to take far longer than they need to. Best practice is to always disable whichever settings sections are unused on a GPO.

This example uses `Audit-MisconfiguredGpos` to identify GPOs with this misconfiguration, and shows how to disable the appropriate settings section on all the GPOs, in bulk. A similar thing can be done for GPOs with misconfigured Computer settings as well, with a few tweaks.

<details>
<summary><i>Click to expand</i></summary>

```powershell
# Get all the data
$object = Audit-MisconfiguredGpos -GetFullReports

# Select all GPOs which have User settings enabled but not configured.
$misconfiguredGpos = $object.Gpos | Where { ($_.User.Enabled -eq "true") -and ($_._UserSettingsConfigured -eq $false) }

# Print the list of the GPOs in question:
$misconfiguredGpos | Select DisplayName

# You should indepentently check these GPOs to make sure you do indeed want to edit them!

# Disable User settings on the misconfigured GPOs
$misconfiguredGpos | ForEach-Object {
	Write-Host "Disabling User settings on GPO: `"$($_.DisplayName)`"..."
	
	# This part of this example is a work in progress
	# Apparently there are no native Powershell cmdlets which directly edit such GPO settings.
	# So we'll have to export the GPOs (we already have their GPO report in XML format),
	# edit the XML, and then import it, overwriting the GPO's settings. Ugh.
	# This will require some thorough testing.
}
```
</details>
<br />

### Remove GPOs named like "*X*", but exclude certain GPOs:

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
$gposToRemove | ForEach-Object {
	Write-Host "Removing GPO: `"$($_.DisplayName)`"..."
	Remove-GPO -Name $_.DisplayName
}
```
</details>
<br />

# Parameters

### -Domain \<string\>
Optional string.  
The domain to limit the GPO search to.  
Default is `ad.uillinois.edu`.  
If your domain is different, then change this default at the top of `Audit-MisconfiguredGpos.psm1` and then re-import the module, so you don't have to specify this parameter every time.  

### -DisplayNameFilter \<string\>
Optional string.  
The wildcard query used to filter GPOs by their `DisplayName` property.  
Default is `ENGR*`.  
If your GPOs use a different common name convention, then change this default at the top of `Audit-MisconfiguredGpos.psm1` and then reimport the module, so you don't have to specify this parameter every time.  

### -OUDN \<string\>
Optional string.  
The DistniguishedName of the OU to look for GPO links in.  
Default is `OU=Engineering,OU=Urbana,DC=ad,DC=uillinois,DC=edu`.  
If your usual OU is different, then change this default at the top of `Audit-MisconfiguredGpos.psm1` and then reimport the module, so you don't have to specify this parameter every time.  

### -GetFullReports
Optional switch.  
If specified, a full GPO report will be retrieved for each matching GPO.  
This takes significantly longer, about 1 extra second for every 2 matching GPOs. For all GPOs matching `ENGR*` (~900) this takes about 12 minutes, versus 2 minutes if `-GetFullReports` is omitted.  
  - When `-GetFullReports` is omitted, the script gathers a list of all GPOs matching `-DisplayNameFilter`, and a list of GPOs linked to all OUs under `-OUDN`, and takes the difference to determine which GPOs are unlinked. This is faster because no GPO reports must be retrieved.
  - When `-GetFullReports` is specified, the script takes a more traditional approach. It gets the full GPO report for each GPO matching `-DisplayNameFilter`, and uses the GPO report data to determine whether they have any links.

However this allows for gathering additional data:
  - A second check for which GPOs are unlinked.
  - Whether each matching GPO has any _disabled_ links, and whether _all_ of a given GPO's links are disabled.
    - A tally of how many such GPOs were found.
  - Whether each matching GPO has Computer or User settings enabled but not configured, or configured but not enabled.
    - A tally of how many such GPOs were found.
  - Whether each matching GPO has Computer of User settings which are identical to other matching GPOs.
    - A tally of how many such GPOs were found.

### -GetDuplicates
Optional switch.  
Only relevant when `-GetFullReports` is also specified. Ignored otherwise.  
If specified, each matching GPO is compared to each other matching GPO to determine which GPOs have identical settings.  
This is done separately for Computer and User settings.  
Warning: This will increase runtime _dramatically_. For all GPOs matching `ENGR *` (~900), this takes about 12 hours, versus 15 minutes or less if `-GetDuplicates` is omitted.  

### -Csv
Optional string.  
The full path of a file to export polled data to, in CSV format.  
If omitted, no CSV will be created.  

### -Log
Optional string.  
The full path of a file to log to.  
If omitted, no log will be created.  

### -Quiet
Optional switch.  
If specified, progress output is not logged to the console.  

### -CacheGpos \<string\>
Optional string.  
The full path to an XML file which will store reports for matching GPOs to be used during the current or subsequent runs by specifying `-UseCachedGpos`, instead of always pulling reports directly from AD.  
Only relevant when `-GetFullReports` is also specified. Ignored otherwise.  
Only relevant when `-UseCachedGpos` is NOT specified. Ignored otherwise.  
This is to prevent numerous calls to AD when performing multiple runs (primarily useful when testing), to save time and to prevent campus security from bugging me about thousands of AD logins (one for each `Get-GPOReport` call) when I test the module.  

### -UseCachedGpos \<string\>
Optional string.  
The full path to an XML file previously output by this module when `-CacheGpos` was specified.  
Only relevant when `-GetFullReports` is also specified. Ignored otherwise.  
Cause the module to pull GPO report data from the cache file instead of directly from AD.  
Warning: Using cached GPOs may result in the returned data containing some anomalies, due to GPOs being created, removed, or changed since the cached data was retrieved.  

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
  - UnlinkedGposCountSlow: Total number of matching GPOs which have zero links (calculated via slow method, only when `-GetFullReports` is specified).
  - SomeLinksDisabledGposCount: Total number of matching GPOs which have links where at least one link is disabled (calculated via slow method, only when `-GetFullReports` is specified).
  - AllLinksDisabledGposCount: Total number of matching GPOs which have links where all links are disabled (calculated via slow method, only when `-GetFullReports` is specified).
  - MisnamedGposCount: Total number of GPOs which have at least one link, but whose DisplayName does _not_ match the given `-DisplayNameFilter`.
  - BothSettingsDisabledGposCount: Total number of matching GPOs which have both their Computer and User settings disabled.
  - ComputerSettingsEnabledButNotConfiguredGposCount: Total number of matching GPOs which have Computer configuration settings enabled, but have no such settings defined.
  - ComputerSettingsConfiguredButNotEnabledGposCount: Total number of matching GPOs which have Computer configuration settings configured, but have them disabled.
  - UserSettingsEnabledButNotConfiguredGposCount: Total number of matching GPOs which have User configuration settings enabled, but have no such settings defined.
  - UserSettingsConfiguredButNotEnabledGposCount: Total number of matching GPOs which have User configuration settings configured, but have them disabled.
  - DuplicateComputerGposCount: Total number of matching GPOs which have Computer settings that exactly duplicate Computer settings in other GPOs.
  - DuplicateUserGposCount: Total number of matching GPOs which have User settings that exactly duplicate User settings in other GPOs.
  - DuplicateBothGposCount: Total number of matching GPOs which have both Computer _and_ User settings that exactly duplicate Computer and User settings in other GPOs.
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
` | Select *` is needed to see the additional custom properties added by the script, because GPO objects are a built-in type of object which only show their normal properties by default. These custom properties are prepended with `_` to distinguish them from the built-in GPO object properties.  

[GPO objects](https://docs.microsoft.com/en-us/previous-versions/windows/desktop/wmi_v2/class-library/gpo-class-microsoft-grouppolicy) have the following structure:  

<details>
<summary><i>Click to expand</i></summary>

- GPO object
  - DisplayName: The GPO's friendly name.
  - \_Matches: A boolean representing whether or not this GPO's DisplayName property matches the given `-DisplayNameFilter`.
  - \_LinksCountFast: The number of links this GPO has across all OUs under (and including) the given `-OUDN`.
  - \_Report: The full GPO report, in the format of a Powershell XML object, as returned by `(Get-GPOReport -Guid $guid -ReportType "XML").GPO`.
    - Only present when `-GetFullReports` is specified, and only on GPOs where `_Matches -eq $true`.
  - \_LinksCountSlow: The number of links this GPO has according to its `_Report`. Only present when `-GetFullReports` is specified.
  - \_SomeLinksDisabled: A boolean representing whether or not this GPO has one or more links which are disabled.
    - Simply calculated from the data in `_Report` for more convenient searchability.
	- Only present when `-GetFullReports` is specified.
    - Roughly equivalent to `($gpo._Report.LinksTo.Enabled) -contains "false"`.
  - \_AllLinksDisabled: A boolean representing whether or not all of this GPO's links are disabled.
    - Simply calculated from the data in `_Report` for more convenient searchability.
    - Only present when `-GetFullReports` is specified.
    - Roughly equivalent to `$unique = ($gpo._Report.LinksTo.Enabled | Select -Unique); ($unique.count -eq 1) -and ($unique -contains "false")`.
  - \_ComputerSettingsConfigured: A boolean representing whether or not this GPO has any Computer configuration settings defined.
    - Calculated from data in `_Report` for more convenient searchability.
	- Only present when `-GetFullReports` is specified.
    - Equivalent to `$gpo._Report.Computer.ExtensionData -eq $null`.
  - \_UserSettingsConfigured: A boolean representing whether or not this GPO has any User configuration settings defined.
    - Calculated from data in `_Report` for more convenient searchability.
	- Only present when `-GetFullReports` is specified.
    - Equivalent to `$gpo._Report.User.ExtensionData -eq $null`.
  - \_DuplicateComputerGpos: An array of strings representing the DisplayNames of other GPOs which have identical Computer settings.
    - Only present when `-GetFullReports` is specified.
	- In the CSV output, this is munged into a format like `"Dupe GPO 1 DisplayName";"Dupe GPO 2 DisplayName";"Dupe GPO 3 DisplayName"`.
  - \_DuplicateUserGpos: An array of strings representing the DisplayNames of other GPOs which have identical User settings.
    - Only present when `-GetFullReports` is specified.
	- In the CSV output, this is munged into a format like `"Dupe GPO 1 DisplayName";"Dupe GPO 2 DisplayName";"Dupe GPO 3 DisplayName"`.
  - \_DuplicateBothGpos: An array of strings representing the DisplayNames of other GPOs which have both identical Computer and User settings.
    - Only present when `-GetFullReports` is specified.
	- In the CSV output, this is munged into a format like `"Dupe GPO 1 DisplayName";"Dupe GPO 2 DisplayName";"Dupe GPO 3 DisplayName"`.
  - Id: The GPO's GUID (in [UUID format](https://en.wikipedia.org/wiki/Universally_unique_identifier)).
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

The UserConfiguration and ComputerConfiguration objects which are part of the normal GPO object only contain meta-data, and contain nothing about the actual settings defined in the GPO. This information is only available in a full GPO report, such as `$gpo._Report.Computer`. The actual settings defined in a GPO are recorded in `$gpo._Report.Computer.ExtensionData`. GPOs which do not have any settings defined for a particular configuration object will have no `ExtensionData` node. In other words `$gpo._Report.Computer.ExtensionData` will equal `$null`.  

Update: It seems that in reports for GPOs which previously had Computer or User settings configured, but where those settings have been removed, there is still a vestigial ExtensionData node in the report's XML, which contains only an empty `Extension` node and a `Name` node. This causes the duplicate detection feature to not skip these GPOs and instead evaluate them as identical to other such GPOs. This will not be "fixed" because A) this case is non-trivial to differentiate from legitimately duplicate GPOs and B) this could be considered a misconfiguration, or at least something to investigate, even if it ends up being benign.  

This is leveraged to identify GPOs which:  
  - have settings configured, but which have those settings disabled
  - have settings enabled, but which have no settings configured
</details>
<br />

# Notes
- You can run this as your non-SU account, but you may recieve some errors when the script tries to gather data about campus-level GPOs.
- If you want something far more powerful and far-reaching, but more complicated and less targeted at Illinois edge IT, then check out [GPOZaurr](https://www.reddit.com/r/PowerShell/comments/l42lc2/the_only_command_you_will_ever_need_to_understand/).
- By mseng3. See my other projects here: https://github.com/mmseng/code-compendium.
