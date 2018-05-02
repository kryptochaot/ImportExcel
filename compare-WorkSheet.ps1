﻿Function Compare-WorkSheet {
<#
    .Synopsis 
        Compares two worksheets with the same name in different files. 
    .Description
        This command takes two file names, a worksheet name and a name for a key column. 
        It reads the worksheet from each file and decides the column names.
        It builds as hashtable of the key column values and the rows they appear in  
        It then uses PowerShell's compare object command to compare the sheets (explicity checking all column names which have not been excluded)
        For the difference rows it adds the row number for the key of that row - we have to add the key after doing the comparison, 
        otherwise rows will be considered as different simply because they have different row numbers 
        We also add the name of the file in which the difference occurs.  
        If -BackgroundColor is specified the difference rows will be changed to that background. 
    .Example 
        Compare-WorkSheet -Referencefile 'Server1.xlsx' -Differencefile 'Server2.xlsx'  -WorkSheetName Products -key IdentifyingNumber -ExcludeProperty Install* | format-table
        The two workbooks in this example contain the result of redirecting a subset of properties from Get-WmiObject -Class win32_product to Export-Excel
        The command compares the "products" pages in the two workbooks, but we don't want a match if the software was installed on a 
        different date or from a different place,  so Excluding Install* removes InstallDate and InstallSource. The results will be presented as a table.  
    .Example 
        Compare-WorkSheet  'Server1.xlsx' 'Server2.xlsx'  -WorkSheetName Services -key Name -BackgroundColor lightGreen
        This time two workbooks contain the result of redirecting Get-WmiObject -Class win32_service to Export-Excel 
        This command compares the "services" pages and highlights the rows in the spreadsheet files. 
        Here the -Differencefile and -Referencefile parameter switches are assumed
    .Example 
        Compare-WorkSheet 'Server1.xlsx' 'Server2.xlsx'  -WorkSheetName Services -BackgroundColor lightGreen -fontColor Red -Show
        This builds on the previous example: this time Where two rows in the services have the same name, this will also highlight  the changed cells in red. 
        This example will open the Excel files and  omits the -key parameter because "Name" will be assumed to the label for the key column 
    .Example
        Compare-WorkSheet 'Pester-tests.xlsx' 'Pester-tests.xlsx' -WorkSheetName 'Server1','Server2' -Property "full Description","Executed","Result" -Key "full Description"
        This time the reference file and the difference file are the same file and two different sheets are used. Because the tests include the
        machine name and time the test was run only a limited set of columns.   
    .Example
        Compare-WorkSheet  'Server1.xlsx' 'Server2.xlsx' -WorkSheetName general -Startrow 2 -Headername Label,value -Key Label -GridView -ExcludeDifferent 
        The "General" page has a title and two unlabelled columns with a row forCPU, Memory, Domain, Disk and so on 
        So the command is instructed to starts at row 2 to skip the title and to name the columns: the first is "label" and the Second "Value";
         the label acts as the key. This time we interested the rows which are the same in both sheets, 
        and the result is displayed using grid view. Note that grid view works best when the number of columns is small. 
    .Example
        Compare-WorkSheet 'Server1.xlsx' 'Server2.xlsx' -WorkSheetName general -Startrow 2 -Headername Label,value -Key Label -BackgroundColor White -Show -AllDataBackgroundColor LightGray
        This version of the previous command lightlights all the cells in lightgray and then sets the changed rows back to white; only 
        the unchanged rows are highlighted
#>
[cmdletbinding(DefaultParameterSetName)]
    Param(
        #First file to compare 
        [parameter(Mandatory=$true,Position=0)]
        $Referencefile ,
        #Second file to compare
        [parameter(Mandatory=$true,Position=1)]
        $Differencefile   ,
        #Name(s) of worksheets to compare.
        $WorkSheetName   = "Sheet1",
        #Properties to include in the DIFF - supports wildcards, default is "*"
        $Property        = "*"    ,
        #Properties to exclude from the the search - supports wildcards 
        $ExcludeProperty ,
        #Specifies custom property names to use, instead of the values defined in the column headers of the TopRow.
        [Parameter(ParameterSetName='B', Mandatory)]
        [String[]]$Headername,   
        #Automatically generate property names (P1, P2, P3, ..) instead of the using the values the top row of the sheet
        [Parameter(ParameterSetName='C', Mandatory)]
        [switch]$NoHeader, 
        #The row from where we start to import data, all rows above the StartRow are disregarded. By default this is the first row.
        [int]$Startrow = 1, 
        #If specified, highlights all the cells - so you can make Equal cells one colour, and Diff cells another. 
        [System.Drawing.Color]$AllDataBackgroundColor,
        #If specified, highlights the DIFF rows 
        [System.Drawing.Color]$BackgroundColor,
        #If specified identifies the tabs which contain DIFF rows  (ignored if -backgroundColor is omitted)   
        [System.Drawing.Color]$TabColor,
        #Name of a column which is unique and will be used to add a row to the DIFF object, default is "Name" 
        $Key             = "Name" ,
        #If specified, highlights the DIFF columns in rows which have the same key.  
        [System.Drawing.Color]$FontColor,
        #If specified opens the Excel workbooks instead of outputting the diff to the console (unless -passthru is also specified) 
        [Switch]$Show,
        #If specified, the command tries to the show the DIFF in a Gridview and not on the console. (unless-Passthru is also specified). This Works best with few columns selected, and requires a key 
        [switch]$GridView,
        #If specified -Passthrough full set of diff data is returned without filtering to the specified properties 
        [Switch]$PassThru,
        #If specified the result will include equal rows as well. By default only different rows are returned 
        [Switch]$IncludeEqual,
        #If Specified the result includes only the rows where both are equal
        [Switch]$ExcludeDifferent
    )
    
    #if the filenames don't resolve, give up now. 
    try    { $oneFile = ((Resolve-Path -Path $Referencefile -ErrorAction Stop).path -eq (Resolve-Path -Path $Differencefile  -ErrorAction Stop).path)}
    Catch  { Write-Warning -Message "Could not Resolve the filenames." ; return } 
        
    #If we have one file , we mush have two different worksheet names. If we have two files we can a single string or two strings. 
    if     ($onefile -and ( ($WorkSheetName.count -ne 2) -or $WorkSheetName[0] -eq $WorkSheetName[1] ) ) {
        Write-Warning -Message "If both the Reference and difference file are the same then worksheet name must provide 2 different names" 
        return
    }
    if     ($WorkSheetName.count -eq 2)       {$worksheet1 = $WorkSheetName[0] ;   $WorkSheet2 = $WorkSheetName[1]} 
    elseif ($WorkSheetName -is [string])      {$worksheet1 = $WorkSheet2 = $WorkSheetName}
    else   {Write-Warning -Message "You must provide either a single worksheet name or two names." ; return }   
    
    $params= @{ ErrorAction = [System.Management.Automation.ActionPreference]::Stop } 
    foreach ($p in @("HeaderName","NoHeader","StartRow")) {if ($PSBoundParameters[$p]) {$params[$p] = $PSBoundParameters[$p]}}
    try    {
        $Sheet1 = Import-Excel -Path $Referencefile  -WorksheetName $WorkSheet1 @params                                                                       
        $Sheet2 = Import-Excel -Path $Differencefile -WorksheetName $WorkSheet2 @Params 
    }
    Catch  {Write-Warning -Message "Could not read the worksheet from $Referencefile and/or $Differencefile." ; return } 
    
    #Get Column headings and create a hash table of Name to column letter. 
    $headings = $Sheet1[-1].psobject.Properties.name # This preserves the sequence - using get-member would sort them alphabetically!
    $headings | ForEach-Object -Begin {$columns  = @{}  ; } -Process  {$Columns[$_] = [char]($i ++) }
    
    #Make a list of property headings using the Property (default "*") and ExcludeProperty parameters 
    if ($Key -eq "Name" -and $NoHeader) {$key  = "p1"} 
    $propList = @() 
    foreach ($p in $Property)           {$propList += ($headings.where({$_ -like    $p}) )} 
    foreach ($p in $ExcludeProperty)    {$propList  =  $propList.where({$_ -notlike $p})  } 
    if (($headings -contains $key) -and ($propList -notcontains $Key)) {$propList += $Key}
    $propList = $propList | Select-Object -Unique 
    if ($propList.Count -eq 0)  {Write-Warning -Message "No Columns are selected with -Property = '$Property' and -excludeProperty = '$ExcludeProperty'." ; return}

    #Add RowNumber, Sheetname and file name to every row 
    $i = $startRow + 1 ; foreach ($row in $Sheet1) {Add-Member -InputObject $row -MemberType NoteProperty -Name "_Row"   -Value ($i ++) 
                                                    Add-Member -InputObject $row -MemberType NoteProperty -Name "_Sheet" -Value  $worksheet1
                                                    Add-Member -InputObject $row -MemberType NoteProperty -Name "_File"  -Value  $Referencefile} 
    $i = $startRow + 1 ; foreach ($row in $Sheet2) {Add-Member -InputObject $row -MemberType NoteProperty -Name "_Row"   -Value ($i ++) 
                                                    Add-Member -InputObject $row -MemberType NoteProperty -Name "_Sheet" -Value  $worksheet2
                                                    Add-Member -InputObject $row -MemberType NoteProperty -Name "_File"  -Value  $Differencefile} 
    
    if ($ExcludeDifferent -and -not $IncludeEqual) {$IncludeEqual = $true} 
    #Do the comparison and add file,sheet and row to the result - these are prefixed with "_" to show they are added the addition will fail if the sheet has these properties so split the operations 
    $diff = Compare-Object -ReferenceObject $Sheet1 -DifferenceObject $Sheet2 -Property $propList -PassThru -IncludeEqual:$IncludeEqual -ExcludeDifferent:$ExcludeDifferent  |
                Sort-Object -Property "_Row","File"
    
    #if BackgroundColor was specified, set it on extra or extra or changed rows  
    if     ($diff -and $BackgroundColor) {
        #Differences may only exist in one file. So gather the changes for each file; open the file, update each impacted row in the shee, save the file  
        $updates = $diff.where({$_.SideIndicator -ne "=="}) | Group-object -Property "_File"
        foreach   ($file in $updates) {
            try   {$xl  = Open-ExcelPackage -Path $file.name }
            catch {Write-warning -Message "Can't open $($file.Name) for writing." ; return} 
            if ($AllDataBackgroundColor) {
                $file.Group._sheet | Sort-Object -Unique | ForEach-Object {
                    $ws =  $xl.Workbook.Worksheets[$_] 
                    if ($headerName) {$range = "A" +  $startrow      + ":" + $ws.dimension.end.address}
                    else             {$range = "A" + ($startrow + 1) + ":" + $ws.dimension.end.address}
                    Set-Format -WorkSheet $ws -BackgroundColor $AllDataBackgroundColor -Range $Range 
                }
            }
            foreach ($row in $file.group)  {
                $ws    = $xl.Workbook.Worksheets[$row._Sheet]
                $range = $ws.Dimension -replace "\d+",$row._row
                Set-Format -WorkSheet $ws -Range $range -BackgroundColor $BackgroundColor         
            }
            if ($TabColor) {
                foreach ($tab in ($file.group._sheet | Select-Object -Unique)) {
                    $xl.Workbook.Worksheets[$tab].TabColor = $TabColor
                 }
            }
            $xl.save()  ; $xl.Stream.Close() ; $xl.Dispose()
        }
    }
    #if font colour was specified, set it on changed properties where the same key appears in both sheets. 
    if     ($diff -and $FontColor -and ($propList -contains $Key)  ) {
        $updates = $diff.where({$_.SideIndicator -ne "=="})  | Group-object -Property $Key | where {$_.count -eq 2} 
        if ($updates) {
            $XL1 = Open-ExcelPackage -path $Referencefile
            if ($oneFile ) {$xl2 = $xl1} 
            else           {$xl2 = Open-ExcelPackage -path $Differencefile }
            foreach ($u in $updates) {
                 foreach ($p in $propList) {
                    if($u.Group[0].$p -ne $u.Group[1].$p ) {
                        Set-Format -WorkSheet $xl1.Workbook.Worksheets[$u.Group[0]._sheet] -Range ($Columns[$p] + $u.Group[0]._Row) -FontColor $FontColor
                        Set-Format -WorkSheet $xl2.Workbook.Worksheets[$u.Group[1]._sheet] -Range ($Columns[$p] + $u.Group[1]._Row) -FontColor $FontColor
                    } 
                } 
            }
            $xl1.Save()                     ; $xl1.Stream.Close() ; $xl1.Dispose()
            if (-not $oneFile) {$xl2.Save() ; $xl2.Stream.Close() ; $xl2.Dispose()}
        }
    }
    elseif ($diff -and $FontColor) {Write-Warning -Message "To match rows to set changed cells, you must specify -Key and it must match one of the included properties" }   

    if     ($show)           { 
        Start-Process -FilePath $Referencefile 
        if (-not $oneFile)  { Start-Process -FilePath $Differencefile }
    }    
    elseif ($GridView)       { 
            $Sheet2 | ForEach-Object -Begin {$Rowhash = @{} } -Process {$Rowhash[$_.$key] = $_._row } 
            if ($StartRow) { $rowCount1 = $StartRow} else {  $rowCount1 = 1}
            $rowCount2 = $null 
            $diff | Group-Object -Property $key | Sort-Object -Property @{e={($_.group | Measure-Object -Property _row -Maximum).maximum} } | ForEach-Object  {
                $hash = [ordered]@{"<Row" = $rowCount1} ;
                $keyVal =  $_.Name;  
                foreach ($row IN $_.Group) {
                    if  ($row.sideindicator -ne "=>")         {$rowCount1    = $hash["<Row"] =  $row._Row  } 
                    if  ($hash.Side) {$hash.side = "<>"} else {$hash["Side"] = $row.sideindicator}
                    if  ($Rowhash[$keyval])                   {$rowCount2    = $Rowhash[$keyval] }
                    $hash[">Row"] = $rowCount2
                    $Hash[$key]   = $keyVal 
                    foreach ($p in $propList.Where({$_ -ne $key})) {
                        if  ($row.SideIndicator -eq "==")  {$hash[("=>$P")] = $hash[("<=$P")] =$row.$P}
                        else                               {$hash[($row.SideIndicator+$P)]    =$row.$P}
                    }
                } 
                [Pscustomobject]$hash   }   | Sort-Object   -Property "<row","side"| Update-FirstObjectProperties | Out-GridView -Title "Comparing $Referencefile::$worksheet1 (<=) with $Differencefile::$WorkSheet2 (=>)"   
    }
    elseif (-not $PassThru)  {return ($diff | Select-Object -Property (@(@{n="_Side";e={$_.SideIndicator}},"_File" ,"_Sheet","_Row") + $propList))}
    if     (     $PassThru)  {return  $diff }
}