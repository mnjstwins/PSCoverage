Function Invoke-AppVeyorBumpVersion() {
    [CmdletBinding()]
    Param()

    Write-Host "Listing Env Vars for debugging:" -ForegroundColor Yellow
    # Filter Results to prevent exposing secure vars.
    Get-ChildItem -Path "Env:*" | Where-Object { $_.name -notlike "NuGetToken"} | Sort-Object -Property Name | Format-Table

    Try {
        $ModManifest = Get-Content -Path '.\src\PSCoverage.psd1'
        $BumpedManifest = $ModManifest -replace '\$Env:APPVEYOR_BUILD_VERSION', "'$Env:APPVEYOR_BUILD_VERSION'"
        Remove-Item -Path '.\src\PSCoverage.psd1'
        Out-File -FilePath '.\src\PSCoverage.psd1' -InputObject $BumpedManifest -NoClobber -Encoding utf8 -Force
    }
    Catch {
        $MsgParams = @{
            Message = 'Could not bump current version into module manifest.'
            Category = 'Error'
            Details = $_.Exception.Message
        }
        Add-AppveyorMessage @MsgParams
        Throw $MsgParams.Message
    }
}

Function Invoke-AppVeyorBuild() {
    [CmdletBinding()]
    Param()
    $MsgParams = @{
        Message = 'Creating build artifacts'
        Category = 'Information'
        Details = 'Extracting srouce files and compressing them into zip file.'
    }
    Add-AppveyorMessage @MsgParams
    $CompParams = @{
        Path = "{0}\src\*" -f $env:APPVEYOR_BUILD_FOLDER
        DestinationPath = "{0}\bin\PSCoverage.zip" -f $env:APPVEYOR_BUILD_FOLDER
        Update = $True
        Verbose = $True
    }
    Compress-Archive @CompParams
    $MsgParams = @{
        Message = 'Pushing artifacts'
        Category = 'Information'
        Details = 'Pushing artifacts to AppVeyor store.'
    }
    Add-AppveyorMessage @MsgParams
    Push-AppveyorArtifact ".\bin\PSCoverage.zip"
}

Function Invoke-AppVeyorTests() {
    [CmdletBinding()]
    Param()

    $MsgParams = @{
            Message = 'Starting Pester tests'
            Category = 'Information'
            Details = 'Now running all test found in .\tests\ dir.'
        }
    Add-AppveyorMessage @MsgParams
    $testresults = Invoke-Pester -Path ".\tests\*" -PassThru
    ForEach ($Item in $testresults.TestResult) {
        Switch ($Item.Result) {
            "Passed" {
                $TestParams = @{
                    Name = "{0}: {1}" -f $Item.Context, $Item.Name
                    Framework = "NUnit"
                    Filename = $Item.Describe
                    Outcome = "Passed"
                    Duration =$Item.Time.Milliseconds
                }
                Add-AppveyorTest @TestParams
            }
            "Failed" {
                $TestParams = @{
                    Name = "{0}: {1}" -f $Item.Context, $Item.Name
                    Framework = "NUnit"
                    Filename = $Item.Describe
                    Outcome = "Failed"
                    Duration =$Item.Time.Milliseconds
                    ErrorMessage= $Item.FailureMessage
                    ErrorStackTrace = $Item.StackTrace
                }
                Add-AppveyorTest @TestParams
            }
            Default {
                $TestParams = @{
                    Name = "{0}: {1}" -f $Item.Context, $Item.Name
                    Framework = "NUnit"
                    Filename = $Item.Describe
                    Outcome = "None"
                    Duration =$Item.Time.Milliseconds
                    ErrorMessage= $Item.FailureMessage
                    ErrorStackTrace = $Item.StackTrace
                }
                Add-AppveyorTest @TestParams
            }
        }
    }
    If ($testresults.FailedCount -gt 0) {
        $MsgParams = @{
            Message = 'Pester Tests failed.'
            Category = 'Error'
            Details = "$($testresults.FailedCount) tests failed."
        }
        Add-AppveyorMessage @MsgParams
        Throw $MsgParams.Message
    }

}

function Invoke-AppVeyorPSGallery() {
    [CmdletBinding()]
    Param()
    Expand-Archive -Path '.\bin\PSCoverage.zip' -DestinationPath 'C:\Users\appveyor\Documents\WindowsPowerShell\Modules\PSCoverage\' -Verbose
    Import-Module -Name 'PSCoverage' -Verbose -Force
    Write-Host "Available Package Provider:" -ForegroundColor Yellow
    Get-PackageProvider -ListAvailable
    Write-Host "Available Package Sources:" -ForegroundColor Yellow
    Get-PackageSource
    Try {
        Write-Host "Try to get NuGet Provider:" -ForegroundColor Yellow
        Get-PackageProvider -Name NuGet -ErrorAction Stop
    }
    Catch {
        Write-Host "Installing NuGet..." -ForegroundColor Yellow
        Install-PackageProvider -Name NuGet -MinimumVersion '2.8.5.201' -Force -Verbose
        Import-PackageProvider NuGet -MinimumVersion '2.8.5.201' -Force
    }
    Try {
        If ($env:APPVEYOR_REPO_BRANCH -eq 'master') {
            Write-Host "try to publish module" -ForegroundColor Yellow
            Publish-Module -Name 'PSCoverage' -NuGetApiKey $env:NuGetToken -Verbose -Force
        }
        Else {
            Write-Host "Skip publishing to PS Gallery because we are on $($env:APPVEYOR_REPO_BRANCH) branch." -ForegroundColor Yellow
            # had to remve the publish-Module statement bacause it would publish although the -WhatIf is given.
            # Publish-Module -Name 'PSCoverage' -NuGetApiKey $env:NuGetToken -Verbose -WhatIf
        }
    }
    Catch {
        $MsgParams = @{
            Message = 'Could not delpoy module to PSGallery.'
            Category = 'Error'
            Details = $_.Exception.Message
        }
        Add-AppveyorMessage @MsgParams
        Throw $MsgParams.Message
    }
}
