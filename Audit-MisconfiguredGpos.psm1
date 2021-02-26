# Documentation home: https://github.com/engrit-illinois/Audit-MisconfiguredGpos
# By mseng3

function Audit-MisconfiguredGpos {
	param(
		[string]$Domain = "ad.uillinois.edu",
		[string]$DisplayNameFilter = "ENGR*",
        [string]$OUDN = "OU=Engineering,OU=Urbana,DC=ad,DC=uillinois,DC=edu",
		
		[switch]$GetFullReports,
		[switch]$GetDuplicates,
		
		# ":ENGRIT:" will be replaced with "c:\engrit\logs\$($MODULE_NAME)_:TS:.csv"
		# ":TS:" will be replaced with start timestamp
		[string]$Csv,
		
		# ":ENGRIT:" will be replaced with "c:\engrit\logs\$($MODULE_NAME)_:TS:.log"
		# ":TS:" will be replaced with start timestamp
		[string]$Log,
		
		[switch]$Quiet,
		[string]$Indent = "    ",
		[string]$LogFileTimestampFormat = "yyyy-MM-dd_HH-mm-ss",
		[string]$LogLineTimestampFormat = "[HH:mm:ss] ",
		#[string]$LogLineTimestampFormat = "[yyyy-MM-dd HH:mm:ss:ffff] ",
		#[string]$LogLineTimestampFormat = $null, # For no timestamp
		[int]$Verbosity = 0
	)
	
	$MODULE_NAME = "Audit-MisconfiguredGpos"
	
	$ENGRIT_LOG_DIR = "c:\engrit\logs"
	$ENGRIT_LOG_FILENAME = "$($MODULE_NAME)_:TS:"
	
	$START_TIMESTAMP = Get-Date -Format $LogFileTimestampFormat
	if($Log) {
		$Log = $Log.Replace(":ENGRIT:","$($ENGRIT_LOG_DIR)\$($ENGRIT_LOG_FILENAME).log")
		$Log = $Log.Replace(":TS:",$START_TIMESTAMP)
	}
	if($Csv) {
		$Csv = $Csv.Replace(":ENGRIT:","$($ENGRIT_LOG_DIR)\$($ENGRIT_LOG_FILENAME).csv")
		$Csv = $Csv.Replace(":TS:",$START_TIMESTAMP)
	}
	
	# Value for $gpo._LinkCount, $gpo._SomeLinksDisabled, and $gpo._AllLinksDisabled if the GPO wasn't queried because it didn't match $DisplayNameFilter:
	$GPO_NOT_A_MATCH = -1
	
	function log {
		param (
			[Parameter(Position=0)]
			[string]$Msg = "",

			[int]$L = 0, # level of indentation
			[int]$V = 0, # verbosity level
			
			[ValidateScript({[System.Enum]::GetValues([System.ConsoleColor]) -contains $_})]
			[string]$FC = (get-host).ui.rawui.ForegroundColor, # foreground color
			[ValidateScript({[System.Enum]::GetValues([System.ConsoleColor]) -contains $_})]
			[string]$BC = (get-host).ui.rawui.BackgroundColor, # background color
			
			[switch]$E, # error
			[switch]$NoTS, # omit timestamp
			[switch]$NoNL, # omit newline after output
			[switch]$NoConsole, # skip outputting to console
			[switch]$NoLog # skip logging to file
		)
			
		if($E) { $FC = "Red" }
		
		# Custom indent per message, good for making output much more readable
		for($i = 0; $i -lt $L; $i += 1) {
			$Msg = "$Indent$Msg"
		}
		
		# Add timestamp to each message
		# $NoTS parameter useful for making things like tables look cleaner
		if(!$NoTS) {
			if($LogLineTimestampFormat) {
				$ts = Get-Date -Format $LogLineTimestampFormat
			}
			$Msg = "$ts$Msg"
		}

		# Each message can be given a custom verbosity ($V), and so can be displayed or ignored depending on $Verbosity
		# Check if this particular message is too verbose for the given $Verbosity level
		if($V -le $Verbosity) {
		
			# Check if this particular message is supposed to be output to console
			if(!$NoConsole) {

				# Uncomment one of these depending on whether output goes to the console by default or not, such that the user can override the default
				#if($ConsoleOutput) {
				if(!$Quiet) {
				
					# If we're allowing console output, then Write-Host
					if($NoNL) {
						Write-Host $Msg -NoNewline -ForegroundColor $FC -BackgroundColor $BC
					}
					else {
						Write-Host $Msg -ForegroundColor $FC -BackgroundColor $BC
					}
				}
			}

			# Check if this particular message is supposed to be logged
			if(!$NoLog) {
				
				# If $Log was specified, then log to file
				if($Log) {
					
					# Check that the logfile already exists, and if not, then create it (and the full directory path that should contain it)
					if(!(Test-Path -PathType "Leaf" -Path $Log)) {
						New-Item -ItemType "File" -Force -Path $Log | Out-Null
						log "Logging to `"$Log`"."
					}

					if($NoNL) {
						$Msg | Out-File $Log -Append -NoNewline
					}
					else {
						$Msg | Out-File $Log -Append
					}
				}
			}
		}
	}
	
	function Get-Object {
		[PSCustomObject]@{
			"StartTime" = Get-Date
		}
	}
	
	function Get-RunTime($object) {
		$endTime = Get-Date
		$runTime = New-TimeSpan -Start $object.StartTime -End $endTime
		$object = addm "EndTime" $endTime $object
		$object = addm "RunTime" $runTime $object
		log "Runtime: $runTime"
		$object
	}
	
	# Shorthand for an annoying common line
	function addm($property, $value, $object, $adObject = $false) {
		if($adObject) {
			# This gets me EVERY FLIPPIN TIME:
			# https://stackoverflow.com/questions/32919541/why-does-add-member-think-every-possible-property-already-exists-on-a-microsoft
			$object | Add-Member -NotePropertyName $property -NotePropertyValue $value -Force
		}
		else {
			$object | Add-Member -NotePropertyName $property -NotePropertyValue $value
		}
		$object
	}
	
	# Shorthand for an annoying common practice
	# Because of Powershell's weird way of handling arrays containing null values
	# i.e. null values in arrays still count as items in the array
	function count($array) {
		$count = 0
		if($array) {
			# This would return 1 if $array was $null
			# i.e. @().count = 0, @($null).count = 1
			$count = @($array).count
		}
		$count
	}
	
	function Get-Gpos($object) {
		log "Getting all GPOs..."
		
		$gpos = Get-GPO -Domain $Domain -All | Sort DisplayName
		$object = addm "Gpos" $gpos $object
		
		$gposCount = count $gpos
		log "Found $gposCount total GPOs in domain `"$Domain`"." -L 1
		$object = addm "GposCount" $gposCount $object
		
		$object
	}
	
	function Mark-MatchingGpos($object) {
		log "Identifying which GPOs have a DisplayName which matches `"$DisplayNameFilter`"..."
		
		foreach($gpo in $object.Gpos) {
			$matches = $false
			if($gpo.DisplayName -like $DisplayNameFilter) {
				$matches = $true
			}
			$gpo = addm "_Matches" $matches $gpo $true
		}
		
		$count = count ($object.Gpos | Where { $_._Matches -eq $true })
		log "Found $count matching GPOs." -L 1
		$object = addm "MatchingGposCount" $count $object
		
		$object
	}
	
	function Get-Ous($object) {
		log "Getting all OUs under (and including) `"$OUDN`"..." -L 1
		$ous = Get-ADOrganizationalUnit -Filter "Name -like '*'" -SearchBase $OUDN | Sort DistinguishedName
		$ousCount = count $ous
		log "Found $ousCount total OUs." -L 2
		$object = addm "Ous" $ous $object
		$object
	}
	
	function Get-OuLinks($object) {
		log "Getting all GPO links on OUs..." -L 1
		
		$linkedGpoGuids = @()
		foreach($ou in $object.Ous) {
			$linkedGpoGuids += @($ou.LinkedGroupPolicyObjects)
		}
		$linkedGpoGuidsCount = count $linkedGpoGuids
		log "Found $linkedGpoGuidsCount total (non-unique) GPO links." -L 2
		$object = addm "AllGpoLinks" $linkedGpoGuids $object
		
		$uniqueLinkedGpoGuids = $linkedGpoGuids | Sort -Unique
		$uniqueLinkedGpoCount = count $uniqueLinkedGpoGuids
		log "Found $uniqueLinkedGpoCount unique GPO links." -L 2
		$object = addm "UniqueGpoLinks" $uniqueLinkedGpoGuids $object
		
		$object
	}
	
	function Get-GuidFromLink($link) {
		$link = $link.ToLower()
		$hex = "[0-9a-f]"
		$regex = "^cn=\{([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\}.*$"
		$match = $link | Select-String -Pattern $regex
		$guid = $match.Matches.Groups[1].Value
		if(!$guid) {
			Quit "Malformed OU link GUID sent to Get-GuidFromLink(): `"$link`"!"
		}
		$guid
	}
	
	function Mark-LinkedGpos($object) {
		log "Identifying which GPOs are linked in the given OU..."
		
		$object = Get-Ous $object
		$object = Get-OuLinks $object
		
		log "Identifying linked GPOs because we only have the GUIDs currently (this may take a couple minutes)..."
		
		$uniqueGpoLinksCount = count $object.UniqueGpoLinks
		$i = 0
		foreach($link in $object.UniqueGpoLinks) {
			$i += 1
			$guid = Get-GuidFromLink $link
			log "Polling GUID #$i/$($uniqueGpoLinksCount): `"$guid`"..." -L 1 -V 1
			
			$gpo = $object.Gpos | Where { $_.Id -eq $guid }
			if($gpo) {
				log "This GUID belongs to GPO: `"$($gpo.DisplayName)`"." -L 2 -V 2
				
				$guidLinks = $object.AllGpoLinks | Where { $_ -like "*$guid*" }
				$guidLinksCount = count $guidLinks
				log "This GPO is linked $guidLinksCount times." -L 2 -V 2
				
				# This is really not needed for anything, and they are all the same anyway
				#$object = addm "_Links" $guidLinks $gpo $true
				
				$newGpo = addm "_LinksCountFast" $guidLinksCount $gpo $true
				$object.Gpos | Where { $_.Id -eq $guid } | ForEach { $_ = $newGpo }
			}
			else {
				log "Could not find a GPO with this GUID!" -L 2 -V 1 -E
			}
		}
		
		# Count linked GPOs
		$linkedGpos = $object.Gpos | Where { $_._LinksCountFast -ge 1 }
		$linkedGposCount = count $linkedGpos
		log "Found $linkedGposCount linked GPOs." -L 1
		$object = addm "LinkedGposCount" $linkedGposCount $object
		
		$uniqueLinkedGpos = $linkedGpos | Sort DisplayName -Unique
		$uniqueLinkedGposCount = count $uniqueLinkedGpos
		log "Found $uniqueLinkedGposCount unique linked GPOs." -L 1
		
		$object
	}
	
	function Mark-UnlinkedGpos($object) {
		$object = Mark-UnlinkedGposFast $object
		$object = Mark-UnlinkedGposSlow $object
		$object
	}
	
	function Mark-UnlinkedGposFast($object) {
		log "Identifying GPOs which have no links (fast method)..."
		
		$unlinkedGpos = $object.Gpos | Where { $_._LinksCountFast -eq 0 }
		$unlinkedGposCount = count $unlinkedGpos
		log "Found $unlinkedGposCount GPOs which have already been identified as having no links. This should be zero." -L 1 -V 1
		
		$unmarkedGpos = $object.Gpos | Where { $_._LinksCountFast -eq $null }
		$unmarkedGposCount = count $unmarkedGpos
		log "Found $unmarkedGposCount GPOs which have not been identified as having links." -L 1 -V 1
		
		$gposCount = count $object.Gpos
		$linkedGpos = $object.Gpos | Where { ($_._LinksCountFast -is [int]) -and ($_._LinksCountFast -gt 0) }
		$linkedGposCount = count $linkedGpos
		$linkedAndUnlinkedGposCount = $linkedGposCount + $unmarkedGposCount
		log "$linkedGposCount linked GPOs + $unmarkedGposCount unidentified GPOs = $($linkedAndUnlinkedGposCount). This should be equal to the total number of GPOs ($gposCount)." -L 1 -V 1
		
		log "Marking unidentified GPOs as unlinked..." -L 1 -V 1
		foreach($gpo in $object.Gpos) {
			if($gpo._LinksCountFast -eq $null) {
				$gpo = addm "_LinksCountFast" 0 $gpo
			}
		}
		$unlinkedGpos = $object.Gpos | Where { $_._LinksCountFast -eq 0 }
		$unlinkedGposCount = count $unlinkedGpos
		log "There are now $unlinkedGposCount total GPOs marked as having no links." -L 2 -V 1
				
		$unlinkedMatchingGpos = $object.Gpos | Where { ($_._Matches -eq $true) -and ($_._LinksCountFast -eq 0) }
		$unlinkedMatchingGposCount = count $unlinkedMatchingGpos
		log "Found $unlinkedMatchingGposCount matching GPOs with no links." -L 1
		$object = addm "UnlinkedGposCountFast" $unlinkedMatchingGposCount $object
		
		$object
	}
	
	function Get-ReportsForGpos($object) {
		log "Getting GPO reports for matching GPOs (this may take several minutes)..." -L 1
		
		$matchingGposCount = count ($object.Gpos | Where { $_._Matches -eq $true })
		$i = 0
		foreach($gpo in $object.Gpos) {
			
			if($gpo._Matches -eq $true) {
				$i += 1
				log "Getting report for GPO #$i/$($matchingGposCount): `"$($gpo.DisplayName)`"..." -L 2 -V 1
				
				[xml]$report = $gpo | Get-GPOReport -ReportType "XML"
				$gpo = addm "_Report" $report $gpo $true
				
				$linkCount = count ($report.GPO.LinksTo)
				log "Found $linkCount links for GPO." -L 3 -V 2
				
				$disabled = $report.GPO.LinksTo | Where { $_.Enabled -eq "false" }
				$disabledCount = count $disabled
				log "$disabledCount/$linkCount links are disabled." -L 3 -V 2
				
				$someDisabled = $false
				$allDisabled = $false
				if($disabledCount -gt 0) {
					$someDisabled = $true
					if($disabledCount -eq $linkCount) {
						$allDisabled = $true
					}
				}
			
				$gpo = addm "_LinksCountSlow" $linkCount $gpo $true
				$gpo = addm "_SomeLinksDisabled" $someDisabled $gpo $true
				$gpo = addm "_AllLinksDisabled" $allDisabled $gpo $true
			}
		}
		
		$object
	}
	
	function Mark-UnlinkedGposSlow($object) {
		
		if($GetFullReports) {
			log "Identifying GPOs which have no links (slow method)..."
			
			$object = Get-ReportsForGpos $object
			
			$unlinkedGpos = $object.Gpos | Where { $_._LinksCountSlow -eq 0 }
			$unlinkedGposCount = count $unlinkedGpos
			log "Found $unlinkedGposCount matching GPOs with no links." -L 1
			
			$someLinksDisabledGpos = $object.Gpos | Where { $_._SomeLinksDisabled -eq $true }
			$someLinksDisabledGposCount = count $someLinksDisabledGpos
			log "Found $someLinksDisabledGposCount matching GPOs with at least one link disabled." -L 1
			
			$allLinksDisabledGpos = $object.Gpos | Where { $_._AllLinksDisabled -eq $true }
			$allLinksDisabledGposCount = count $allLinksDisabledGpos
			log "Found $allLinksDisabledGposCount matching GPOs with all links disabled." -L 1
		}
		else {
			$unlinkedGposCount = "-GetFullReports was not specified."
			$someLinksDisabledGposCount = "-GetFullReports was not specified."
			$allLinksDisabledGposCount = "-GetFullReports was not specified."
		}
		
		$object = addm "UnlinkedGposCountSlow" $unlinkedGposCount $object
		$object = addm "SomeLinksDisabledGposCount" $someLinksDisabledGposCount $object
		$object = addm "AllLinksDisabledGposCount" $allLinksDisabledGposCount $object
		
		$object
	}
	
	function Get-SettingsEnabled($type, $gpo) {
		# There's two ways to determine this
		# From the GPO object itself
		$fastResult = "unknown"
		# And from the GPO report's GPO.User.Enabled or GPO.Computer.Enabled property
		$slowResult = "unknown"
		
		# Determine result from GPO object itself
		switch($type) {
			"User" {
				switch($gpo.GpoStatus) {
					"AllSettingsEnabled" { $fastResult = $true }
					"UserSettingsDisabled" { $fastResult = $false }
					"ComputerSettingsDisabled" { $fastResult = $true }
					"AllSettingsDisabled" { $fastResult = $false }
					Default { Quit "GPO with invalid GpoStatus property sent to Get-SettingsStatus(): `"$($gpo.DisplayName)`"!" }
				}
			}
			"Computer" {
				switch($gpo.GpoStatus) {
					"AllSettingsEnabled" { $fastResult = $true }
					"UserSettingsDisabled" { $fastResult = $true }
					"ComputerSettingsDisabled" { $fastResult = $false }
					"AllSettingsDisabled" { $fastResult = $false }
					Default { Quit "GPO with invalid GpoStatus property sent to Get-SettingsStatus(): `"$($gpo.DisplayName)`"!" }
				}
			}
			Default { Quit "Invalid type sent to Get-SettingsStatus(): `"$type`"!" }
		}
		
		# If we have the report, also determine result from that
		if($GetFullReports) {
			switch($type) {
				"User" {
					$slowResult = $false
					if($gpo._Report.GPO.User.Enabled -eq "true") {
						$slowResult = $true
					}
				}
				"Computer" {
					$slowResult = $false
					if($gpo._Report.GPO.Computer.Enabled -eq "true") {
						$slowResult = $true
					}
				}
				Default { Quit "Invalid type sent to Get-SettingsStatus(): `"$type`"!" }
			}
			
			# If we have both results, compare them for a sanity check
			if($fastResult -ne $slowResult) {
				Quit "A GPO's `"$type`" settings status could not be determined, because the GPO object and the GPO report disagree: `"$($gpo.DisplayName)`"!"
			}
		}
		
		# If we've gotten this far, then either we don't have the GPO report to compare, or $fastResult = $slowResult
		$fastResult
	}
	
	function Mark-UnconfiguredSettingsGpos($object) {
		log "Indentifying GPOs which have no User or Computer settings configured..."
		if($GetFullReports) {
			
			$computerSettingsEnabledButNotConfiguredGposCount = 0
			$computerSettingsConfiguredButNotEnabledGposCount = 0
			$userSettingsEnabledButNotConfiguredGposCount = 0
			$userSettingsConfiguredButNotEnabledGposCount = 0
			
			log "Looping through GPOs..." -L 1 -V 1
			$matchingGposCount = count ($object.Gpos | Where { $_._Matches -eq $true })
			$i = 0
			foreach($gpo in $object.Gpos) {
				if($gpo._Matches -eq $true) {
					$i += 1
					log "Identifying for GPO #$i/$($matchingGposCount): `"$($gpo.DisplayName)`"..." -L 2 -V 1
					
					$computerSettingsConfigured = $true
					if($gpo._Report.GPO.Computer.ExtensionData -eq $null) {
						$computerSettingsConfigured = $false
					}
					$gpo = addm "_ComputerSettingsConfigured" $computerSettingsConfigured $gpo $true
					log "_ComputerSettingsConfigured: `"$computerSettingsConfigured`"." -L 3 -V 2
					
					$userSettingsConfigured = $true
					if($gpo._Report.GPO.User.ExtensionData -eq $null) {
						$userSettingsConfigured = $false
					}
					$gpo = addm "_UserSettingsConfigured" $userSettingsConfigured $gpo $true
					log "_UserSettingsConfigured: `"$userSettingsConfigured`"." -L 3 -V 2
					
					$computerSettingsEnabled = Get-SettingsEnabled "Computer" $gpo
					log "Computer settings enabled: `"$computerSettingsEnabled`"." -L 3 -V 2
					
					$userSettingsEnabled = Get-SettingsEnabled "User" $gpo
					log "User settings enabled: `"$userSettingsEnabled`"." -L 3 -V 2
					
					if(($computerSettingsEnabled) -and (!$computerSettingsConfigured)) {
						$computerSettingsEnabledButNotConfiguredGposCount += 1
						log "This GPO has Computer settings enabled but not configured!" -L 3 -V 2
					}
					
					if(($computerSettingsConfigured) -and (!$computerSettingsEnabled)) {
						$computerSettingsConfiguredButNotEnabledGposCount += 1
						log "This GPO has Computer settings configured but not enabled!" -L 3 -V 2
					}
					
					if(($userSettingsEnabled) -and (!$userSettingsConfigured)) {
						$userSettingsEnabledButNotConfiguredGposCount += 1
						log "This GPO has User settings enabled but not configured!" -L 3 -V 2
					}
					
					if(($userSettingsConfigured) -and (!$userSettingsEnabled)) {
						$userSettingsConfiguredButNotEnabledGposCount += 1
						log "This GPO has User settings configured but not enabled!" -L 3 -V 2
					}
				}
			}
			
			log "Found $computerSettingsEnabledButNotConfiguredGposCount GPOs with Computer settings enabled but not configured." -L 1
			log "Found $computerSettingsConfiguredButNotEnabledGposCount GPOs with Computer settings configured but not enabled." -L 1
			log "Found $userSettingsEnabledButNotConfiguredGposCount GPOs with User settings enabled but not configured." -L 1
			log "Found $userSettingsConfiguredButNotEnabledGposCount GPOs with User settings configured but not enabled." -L 1
		}
		else {
			$computerSettingsEnabledButNotConfiguredGposCount = "-GetFullReports was not specified."
			$computerSettingsConfiguredButNotEnabledGposCount = "-GetFullReports was not specified."
			$userSettingsEnabledButNotConfiguredGposCount = "-GetFullReports was not specified."
			$userSettingsConfiguredButNotEnabledGposCount = "-GetFullReports was not specified."
		}
		
		$object = addm "ComputerSettingsEnabledButNotConfiguredGposCount" $computerSettingsEnabledButNotConfiguredGposCount $object
		$object = addm "ComputerSettingsConfiguredButNotEnabledGposCount" $computerSettingsConfiguredButNotEnabledGposCount $object
		$object = addm "UserSettingsEnabledButNotConfiguredGposCount" $userSettingsEnabledButNotConfiguredGposCount $object
		$object = addm "UserSettingsConfiguredButNotEnabledGposCount" $userSettingsConfiguredButNotEnabledGposCount $object
		
		$object
	}
	
	function Mark-DuplicateGpo($object, $gpo) {
		
		$duplicateComputerGpos = @()
		$duplicateUserGpos = @()
		$duplicateBothGpos = @()
		
		$gpoComputerSettings = $gpo._Report.GPO.Computer.ExtensionData
		$gpoUserSettings = $gpo._Report.GPO.User.ExtensionData
		
		if($gpoComputerSettings -or $gpoUserSettings) {
			$matchingGposCount = count ($object.Gpos | Where { $_._Matches -eq $true })
			log "Looping through other GPOs..." -L 2 -V 1
			$i = 0
			foreach($thisGpo in $object.Gpos) {
				if($thisGpo._Matches -eq $true) {
					$i += 1
					log "Comparing to GPO #$i/$($matchingGposCount): `"$($thisGpo.DisplayName)`"..." -L 3 -V 1
					if($thisGpo.DisplayName -eq $gpo.Displayname) {
						log "This is the same GPO being compared. Skipping." -L 4 -V 2
					}
					else {
						# Compare Computer settings
						if($gpoComputerSettings) {
							$thisGpoComputerSettings = $thisGpo._Report.GPO.Computer.ExtensionData
							if($thisGpoComputerSettings) {
								if($gpoComputerSettings.InnerXml -eq $thisGpoComputerSettings.InnerXml) {
									$duplicateComputerGpos += @($thisGpo.DisplayName)
									log "This GPO has identical Computer settings." -L 4 -V 2
								}
								else {
									log "This GPO does not have identical Computer settings."
								}
							}
							else {
								log "This GPO has no Computer settings." -L 4 -V 2
							}
						}
						else {
							log "Base GPO has no Computer settings." -L 4 -V 2
						}
						
						# Compare User settings
						if($gpoUserSettings) {
							$thisGpoUserSettings = $thisGpo._Report.GPO.User.ExtensionData
							if($thisGpoUserSettings) {
								if($gpoUserSettings.InnerXml -eq $thisGpoUserSettings.InnerXml) {
									$duplicateUserGpos += @($thisGpo.DisplayName)
									log "This GPO has identical User settings." -L 4 -V 2
								}
								else {
									log "This GPO does not have identical User settings."
								}
							}
							else {
								log "This GPO has no User settings." -L 4 -V 2
							}
						}
						else {
							log "Base GPO has no User settings." -L 4 -V 2
						}
						
						# If both Computer and User settings are identical
						$duplicateBothSettings = $duplicateComputerSettings -and $duplicateUserSettings
						if($duplicateBothSettings) {
							$duplicateBothGpos += @($thisGpo.DisplayName)
							log "This GPO has identical Computer AND User settings." -L 4 -V 2
						}
						else {
							log "This GPO does not have both identical Computer and User settings."
						}
					}
				}
			}
		}
		else {
			log "This GPO has no settings." -L 2 -V 1
		}
		
		$duplicateComputerGposCount = count $duplicateComputerGpos
		if($duplicateComputerGposCount -gt 0) {
			$gpo = addm "_DuplicateComputerGpos" $duplicateComputerGpos $gpo $true
			$object.DuplicateComputerGposCount += $duplicateComputerGposCount
		}
		
		$duplicateUserGposCount = count $duplicateUserGpos
		if($duplicateUserGposCount -gt 0) {
			$gpo = addm "_DuplicateUserGpos" $duplicateUserGpos $gpo $true
			$object.DuplicateUserGposCount += $duplicateUserGposCount
		}
		
		$duplicateBothGposCount = count $duplicateBothGpos
		if($duplicateBothGposCount -gt 0) {
			$gpo = addm "_DuplicateBothGpos" $duplicateBothGpos $gpo $true
			$object.DuplicateBothGposCount += $duplicateBothGposCount
		}
		
		$object
	}
	
	function Mark-DuplicateGpos($object) {
		log "Indentifying duplicate GPOs (i.e. which have identical settings configured)..."
		if($GetFullReports) {
			if($GetDuplicates) {
				$object = addm "DuplicateComputerGposCount" 0 $object
				$object = addm "DuplicateUserGposCount" 0 $object
				$object = addm "DuplicateBothGposCount" 0 $object
				
				$matchingGposCount = count ($object.Gpos | Where { $_._Matches -eq $true })
				log "Looping through GPOs..." -L 1 -V 1
				$i = 0
				foreach($gpo in $object.Gpos) {
					if($gpo._Matches -eq $true) {
						$i += 1
						log "Identifying for GPO #$i/$($matchingGposCount): `"$($gpo.DisplayName)`"..." -L 2 -V 1
						$object = Mark-DuplicateGpo $object $gpo
					}
				}
				
				log "Found $($object.DuplicateComputerGposCount) GPOs with Computer settings which duplicate those of other GPOs." -L 1
				log "Found $($object.DuplicateUserGposCount) GPOs with User settings which duplicate those of other GPOs." -L 1
				log "Found $($object.DuplicateBothGposCount) GPOs with Computer AND User settings which duplicate those of other GPOs." -L 1
			}
			else {
				$object = addm "DuplicateComputerGposCount" "-GetDuplicates was not specified." $object
				$object = addm "DuplicateUserGposCount" "-GetDuplicates was not specified." $object
				$object = addm "DuplicateBothGposCount" "-GetDuplicates was not specified." $object
			}
		}
		else {
			$object = addm "DuplicateComputerGposCount" "-GetFullReports was not specified." $object
			$object = addm "DuplicateUserGposCount" "-GetFullReports was not specified." $object
			$object = addm "DuplicateBothGposCount" "-GetFullReports was not specified." $object
		}
		
		$object
	}
	
	function Get-MisnamedGpos($object) {
		log "Counting misnamed GPOs (i.e. linked, but which do not match `"$DisplayNameFilter`")..." -V 1
		$misnamedGpos = $object.Gpos | Where { ($_.DisplayName -notlike $DisplayNameFilter) -and ($_._LinksCountFast -gt 0) }
		$misnamedGposCount = count $misnamedGpos
		log "Found $misnamedGposCount misnamed GPOs." -L 1
		$object = addm "MisnamedGposCount" $misnamedGposCount $object
		$object
	}
	
	function Get-DisabledSettingsGpos($object) {
		log "Counting GPOs which have both their Computer and User settings disabled." -V 1
		# https://docs.microsoft.com/en-us/previous-versions/windows/desktop/wmi_v2/class-library/gpostatus-enumeration-microsoft-grouppolicy
		$bothDisabledGpos = $object.Gpos | Where { $_.GpoStatus -eq "AllSettingsDisabled" }
		$bothDisabledGposCount = count $bothDisabledGpos
		log "Found $bothDisabledGposCount GPOs with both settings disabled." -L 1
		$object = addm "BothSettingsDisabledGposCount" $bothDisabledGposCount $object
		$object
	}
	
	function Quit($msg) {
		log $msg -E
		throw $msg
		Exit $msg
	}
	
	function Export-Gpos($object) {
		if($Csv) {
			log "-Csv was specified. Exporting data to `"$Csv`"..."
			$object.Gpos | Export-Csv -NoTypeInformation -Encoding "Ascii" -Path $Csv
		}
	}
	
	function Return-Object($object) {
		$object | Select `
			GposCount,
			MatchingGposCount,
			LinkedGposCount,
			UnlinkedGposCountFast,
			UnlinkedGposCountSlow,
			SomeLinksDisabledGposCount,
			AllLinksDisabledGposCount,
			MisnamedGposCount,
			BothSettingsDisabledGposCount,
			ComputerSettingsEnabledButNotConfiguredGposCount,
			ComputerSettingsConfiguredButNotEnabledGposCount,
			UserSettingsEnabledButNotConfiguredGposCount,
			UserSettingsConfiguredButNotEnabledGposCount,
			DuplicateComputerGposCount,
			DuplicateUserGposCount,
			DuplicateBothGposCount,
			Gpos,
			Ous,
			AllGpoLinks,
			UniqueGpoLinks,
			StartTime,
			EndTime,
			RunTime
	}
	
	function Do-Stuff {
		
		$object = Get-Object
		$object = Get-Gpos $object
		$object = Mark-MatchingGpos $object
		$object = Mark-LinkedGpos $object
		$object = Get-MisnamedGpos $object
		$object = Get-DisabledSettingsGpos $object
		$object = Mark-UnlinkedGpos $object
		$object = Mark-UnconfiguredSettingsGpos $object
		$object = Mark-DuplicateGpos $object
				
		$object = Get-RunTime $object
		
		Export-Gpos $object
		Return-Object $object
	}
	
	Do-Stuff
	
	log "EOF"
}