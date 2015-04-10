param (
    [string]$environmentName,
    [string]$machineNames, 
    [string]$sourcePath,
    [string]$targetPath,
    [string]$cleanTargetBeforeCopy,
    [string]$deployFilesInParallel,
    [string]$alternateCredentialsUsername,
	[string]$alternateCredentialsPassword
    )

Write-Verbose "Entering script DeployFilesToMachines.ps1" -Verbose
Write-Verbose "environmentName = $environmentName" -Verbose
Write-Verbose "machineNames = $machineNames" -Verbose
Write-Verbose "sourcePath = $sourcePath" -Verbose
Write-Verbose "targetPath = $targetPath" -Verbose
Write-Verbose "deployFilesInParallel = $deployFilesInParallel" -Verbose
Write-Verbose "cleanTargetBeforeCopy = $cleanTargetBeforeCopy" -Verbose

function Output-ResponseLogs
{
    param([string]$operationName,
          [string]$fqdn,
          [object]$deploymentResponse)

    Write-Verbose "Finished $operationName operation on $fqdn" -Verbose

    if ([string]::IsNullOrEmpty($deploymentResponse.DeploymentLog) -eq $false)
    {
        Write-Verbose "Deployment logs for $operationName operation on $fqdn " -Verbose
        Write-Verbose ($deploymentResponse.DeploymentLog | Format-List | Out-String) -Verbose
    }
    if ([string]::IsNullOrEmpty($deploymentResponse.ServiceLog) -eq $false)
    {
        Write-Verbose "Service logs for $operationName operation on $fqdn " -Verbose
        Write-Verbose ($deploymentResponse.ServiceLog | Format-List | Out-String) -Verbose
    }
}

$CopyJob = {
param (
    [string]$environmentName,
    [guid]$envOperationId,
    [string]$fqdn, 
    [string]$sourcePath,
    [string]$targetPath,
    [string]$username,
	[string]$password,
    [string]$cleanTargetBeforeCopy
    )

    Get-ChildItem $env:AGENT_HOMEDIRECTORY\Agent\Worker\*.dll | % {
    [void][reflection.assembly]::LoadFrom( $_.FullName )
    Write-Verbose "Loading .NET assembly:`t$($_.name)" -Verbose
    }

    Get-ChildItem $env:AGENT_HOMEDIRECTORY\Agent\Worker\Modules\Microsoft.TeamFoundation.DistributedTask.Task.DevTestLabs\*.dll | % {
    [void][reflection.assembly]::LoadFrom( $_.FullName )
    Write-Verbose "Loading .NET assembly:`t$($_.name)" -Verbose
    }

   $resOperationId = Invoke-ResourceOperation -EnvironmentName $environmentName -ResourceName $fqdn -EnvironmentOperationId $envOperationId -ErrorAction Stop

   Write-Verbose "ResourceOperationId = $resOperationId for resource $fqdn" -Verbose

   $credential = New-Object 'System.Net.NetworkCredential' -ArgumentList $username, $password

   Write-Verbose "Initiating copy on $fqdn, username: $username" -Verbose

   if($cleanTargetBeforeCopy -eq "true")
    {
         $copyResponse = Copy-FilesToTargetMachine -MachineDnsName $fqdn -SourcePath $sourcePath -DestinationPath $targetPath -Credential $credential -CleanTargetPath -SkipCACheck -UseHttp
    }

    else
    {
         $copyResponse = Copy-FilesToTargetMachine -MachineDnsName $fqdn -SourcePath $sourcePath -DestinationPath $targetPath -Credential $credential -SkipCACheck -UseHttp
    }

    $logs = New-Object 'System.Collections.Generic.List[System.Object]'
    $log = "Deployment Logs : " + $copyResponse.DeploymentLog + "`nService Logs : " + $copyResponse.ServiceLog               
    $resourceOperationLog = New-OperationLog -Content $log
    $logs.Add($resourceOperationLog)

	Complete-ResourceOperation -EnvironmentName $environmentName -EnvironmentOperationId $envOperationId -ResourceOperationId $resOperationId -Status $copyResponse.Status -ErrorMessage $copyResponse.Error -Logs $logs -ErrorAction Stop
    
    Write-Output $copyResponse
}

import-module "Microsoft.TeamFoundation.DistributedTask.Task.DevTestLabs"

$env:DTL_ALTERNATE_CREDENTIALS_USERNAME = $alternateCredentialsUsername
$env:DTL_ALTERNATE_CREDENTIALS_PASSWORD = $alternateCredentialsPassword

$resources = Get-EnvironmentResources -EnvironmentName $environmentName -ResourceFilter $machineNames -ErrorAction Stop

$machineUserName = Get-EnvironmentProperty -EnvironmentName $environmentName -Key "Username" -ErrorAction Stop

$machinePassword = Get-EnvironmentProperty -EnvironmentName $environmentName -Key "Password" -ErrorAction Stop

$envOperationId = Invoke-EnvironmentOperation -EnvironmentName $environmentName -OperationName "Copy Files" -ErrorAction Stop

Write-Verbose "envOperationId = $envOperationId" -Verbose
$envOperationStatus = "Passed"

if($deployFilesInParallel -eq "false")
{
    foreach($resource in $resources)
    {
        $fdqn = $resource.Name
        Write-Output "Copy will be Started for - $fdqn"

        $resOperationId = Invoke-ResourceOperation -EnvironmentName $environmentName -ResourceName $fdqn -EnvironmentOperationId $envOperationId -ErrorAction Stop
        Write-Verbose "ResourceOperationId = $resOperationId for resource $fdqn" -Verbose

        $credential = New-Object 'System.Net.NetworkCredential' -ArgumentList $machineUserName, $machinePassword

        Write-Verbose "Initiating copy on $fdqn, username: $machineUserName" -Verbose
        Write-Output "Copy Started for  - $fdqn"

        if($cleanTargetBeforeCopy -eq "true")
        {
            $copyResponse = Copy-FilesToTargetMachine -MachineDnsName $fdqn -SourcePath $sourcePath -DestinationPath $targetPath -Credential $credential -CleanTargetPath -SkipCACheck -UseHttp
        }

        else
        {
             $copyResponse = Copy-FilesToTargetMachine -MachineDnsName $fdqn -SourcePath $sourcePath -DestinationPath $targetPath -Credential $credential -SkipCACheck -UseHttp
        }

        $result = $copyResponse.DeploymentLog
        $status = $copyResponse.Status

        $logs = New-Object 'System.Collections.Generic.List[System.Object]'
        $log = "Deployment Logs : " + $copyResponse.DeploymentLog + "`nService Logs : " + $copyResponse.ServiceLog             
        $resourceOperationLog = New-OperationLog -Content $log
        $logs.Add($resourceOperationLog)

	    Complete-ResourceOperation -EnvironmentName $environmentName -EnvironmentOperationId $envOperationId -ResourceOperationId $resOperationId -Status $copyResponse.Status -ErrorMessage $copyResponse.Error -Logs $logs -ErrorAction Stop
        
        Output-ResponseLogs -operationName "copy" -fqdn $fdqn -deploymentResponse $copyResponse
        Write-Output "Result for machine $fdqn : $result"
        Write-Output "Copy Status for machine $fdqn : $status"

        if($status -ne "Passed")
        {
             $envOperationStatus = "Failed"
             break
        }
    } 
}

else
{
    $Jobs = New-Object "System.Collections.Generic.Dictionary``2[int, string]"

    foreach($resource in $resources)
    {
        $machine = $resource.Name
	
        Write-Output "Copy will be Started for - $machine"

        $job = Start-Job -ScriptBlock $CopyJob -ArgumentList $environmentName, $envOperationId, $machine, $sourcePath, $targetPath, $machineUserName, $machinePassword, $cleanTargetBeforeCopy

        $Jobs.Add($job.Id, $machine)
    
        Write-Output "Copy Started for  - $machine"
    }

    While (Get-Job)
    {
         Start-Sleep 10 
         foreach($job in Get-Job)
         {
             if($job.State -ne "Running")
             {
                 $output = Receive-Job -Job $job
                 $result = $output.DeploymentLog
                 $status = $output.Status

                 if($status -ne "Passed")
                 {
                     $envOperationStatus = "Failed"
                 }
            
                 $machineName = $Jobs.Item($job.Id)

                 Output-ResponseLogs -operationName "copy" -fqdn $machineName -deploymentResponse $output
                 Write-Output "Result for machine $machineName : $result"
                 Write-Output "Copy Status for machine $machineName : $status"
                 Remove-Job $Job
              } 
        }
    }
}

Complete-EnvironmentOperation -EnvironmentName $environmentName -EnvironmentOperationId $envOperationId -Status $envOperationStatus -ErrorAction Stop

if($envOperationStatus -ne "Passed")
{
    throw "copy to one or more machine failed."
}

