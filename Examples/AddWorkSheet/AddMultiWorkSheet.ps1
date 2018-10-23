try {. $PSScriptRoot\..\..\LoadPSD1.ps1} catch {}

$xlSourcefile = "$env:TEMP\Source.xlsx"

Remove-Item $xlSourcefile -ErrorAction Ignore

#Put some simple data in a worksheet and Get an excel package object to represent the file
$excel = 1..10 | Export-Excel $xlSourcefile -PassThru

#Add a new worksheet named 'NewSheet' and copying the sheet that was just made (Sheet1) to the new sheet
#Add-WorkSheet -ExcelPackage $excel -WorkSheetname "NewSheet" -CopySource $excel.Workbook.Worksheets["Sheet1"]
#Save and open in Excel
#Close-ExcelPackage -ExcelPackage $excel -Show

#Put some simple data in a worksheet and Get an excel package object to represent the file
$TabData1 = 1..10 | Export-Excel $xlSourcefile -PassThru -WorksheetName 'Tab 1' -AutoSize -AutoFilter
Close-ExcelPackage -ExcelPackage $TabData1 

#Add another tab.  Replace the $TabData2 with your data
$TabData2 = 1..10 | Export-Excel $xlSourcefile -PassThru -WorksheetName 'Tab 2' -AutoSize -AutoFilter
Close-ExcelPackage -ExcelPackage $TabData2

#Add another tab.  Replace the $TabData3 with your data
$TabData3 = 1..10  | Export-Excel $xlSourcefile -PassThru -WorksheetName 'Tab 3' -AutoSize -AutoFilter
Close-ExcelPackage -ExcelPackage $TabData3 -Show
