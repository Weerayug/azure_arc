Start-Transcript -Path C:\Temp\DataServicesLogonScript.log

# Deployment environment variables
$Env:TempDir = "C:\Temp"

Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False

# Login as service principal
az login --service-principal --username $Env:spnClientId --password $Env:spnClientSecret --tenant $Env:spnTenantId

# Making extension install dynamic
az config set extension.use_dynamic_install=yes_without_prompt
# Installing Azure CLI extensions
Write-Host "`n"
Write-Host "Installing Azure CLI extensions"
az extension add --name arcdata
az extension add --name connectedk8s
az extension add --name k8s-extension
Write-Host "`n"
az -v

# Set default subscription to run commands against
# "subscriptionId" value comes from clientVM.json ARM template, based on which 
# subscription user deployed ARM template to. This is needed in case Service 
# Principal has access to multiple subscriptions, which can break the automation logic
az account set --subscription $Env:subscriptionId

# Installing Azure Data Studio extensions
Write-Host "`n"
Write-Host "Installing Azure Data Studio Extensions"
Write-Host "`n"
$Env:argument1="--install-extension"
$Env:argument2="microsoft.azcli"
$Env:argument3="microsoft.azuredatastudio-postgresql"
$Env:argument4="Microsoft.arc"
& "C:\Program Files\Azure Data Studio\bin\azuredatastudio.cmd" $Env:argument1 $Env:argument2
& "C:\Program Files\Azure Data Studio\bin\azuredatastudio.cmd" $Env:argument1 $Env:argument3
& "C:\Program Files\Azure Data Studio\bin\azuredatastudio.cmd" $Env:argument1 $Env:argument4

# Creating Azure Data Studio desktop shortcut
Write-Host "`n"
Write-Host "Creating Azure Data Studio Desktop shortcut"
Write-Host "`n"
$TargetFile = "C:\Program Files\Azure Data Studio\azuredatastudio.exe"
$ShortcutFile = "C:\Users\$Env:adminUsername\Desktop\Azure Data Studio.lnk"
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
$Shortcut.TargetPath = $TargetFile
$Shortcut.Save()

# Creating Microsoft SQL Server Management Studio (SSMS) desktop shortcut
Write-Host "`n"
Write-Host "Creating Microsoft SQL Server Management Studio (SSMS) desktop shortcut"
Write-Host "`n"
$TargetFile = "C:\Program Files (x86)\Microsoft SQL Server Management Studio 18\Common7\IDE\ssms.exe"
$ShortcutFile = "C:\Users\$Env:adminUsername\Desktop\Microsoft SQL Server Management Studio 18.lnk"
$WScriptShell = New-Object -ComObject WScript.Shell
$Shortcut = $WScriptShell.CreateShortcut($ShortcutFile)
$Shortcut.TargetPath = $TargetFile
$Shortcut.Save()

# Registering Azure Arc providers
Write-Host "Registering Azure Arc providers, hold tight..."
Write-Host "`n"
az provider register --namespace Microsoft.Kubernetes --wait
az provider register --namespace Microsoft.KubernetesConfiguration --wait
az provider register --namespace Microsoft.ExtendedLocation --wait
az provider register --namespace Microsoft.AzureArcData --wait

az provider show --namespace Microsoft.Kubernetes -o table
Write-Host "`n"
az provider show --namespace Microsoft.KubernetesConfiguration -o table
Write-Host "`n"
az provider show --namespace Microsoft.ExtendedLocation -o table
Write-Host "`n"
az provider show --namespace Microsoft.AzureArcData -o table
Write-Host "`n"

New-Item -ItemType "directory" -Path "C:\Users\$Env:adminUsername\.kube"
Push-Location "C:\Users\$Env:adminUsername\.kube"

# Localize kubeconfig
$Env:KUBECONFIG = "C:\Users\$Env:adminUsername\.kube\config"

function Get-AKSCreds {
    <#
        .SYNOPSIS
        PowerShell function for getting AKS cluster credentials kubeconfig file
        
        .DESCRIPTION
        PowerShell function for getting AKS cluster credentials kubeconfig file.
    #>
    Write-Host "`n"
    Write-Host "Getting AKS cluster credentials"
    Write-Host "`n"
    $aksArray = $(az resource list --resource-group $Env:resourceGroup --resource-type "Microsoft.ContainerService/managedClusters" --query "[].name" -o tsv)
    foreach ($aksCluster in $aksArray){
        az aks get-credentials --resource-group $Env:resourceGroup `
                               --name $aksCluster --admin
    }
}
# Run function
Get-AKSCreds

# Changing default _get-credentials_ output kubeconfig file name
Rename-Item "C:\Users\$Env:adminUsername\.kube\C" "$Env:KUBECONFIG"

function Change-AKSContext {
    <#
        .SYNOPSIS
        PowerShell function for changing Kubernetes cluster context name
        
        .DESCRIPTION
        PowerShell function for changing Kubernetes cluster context to a friendly name using kubectx.
    #>
    Write-Host "`n"
    Write-Host "Changing AKS cluster context name"
    Write-Host "`n"
    $aksArray = $(az resource list --resource-group $Env:resourceGroup --resource-type "Microsoft.ContainerService/managedClusters" --query "[].name" -o tsv)
    foreach ($aksCluster in $aksArray){
        kubectx $aksCluster="$aksCluster-admin"
    }
}
# Run function
Change-AKSContext

kubectx

Write-Host "Checking kubernetes nodes"
Write-Host "`n"
kubectl get nodes
Write-Host "`n"

# Onboarding the AKS cluster as an Azure Arc-enabled Kubernetes cluster
Write-Host "Onboarding the clusters as an Azure Arc-enabled Kubernetes clusters"
Write-Host "`n"


function Arc-Onboarding {
    <#
        .SYNOPSIS
        PowerShell function for onboarding the AKS clusters as Azure Arc-enabled Kubernetes clusters
        
        .DESCRIPTION
        PowerShell function for changing Kubernetes cluster context to a friendly name using kubectx.
    #>
    $aksArray = $(az resource list --resource-group $Env:resourceGroup --resource-type "Microsoft.ContainerService/managedClusters" --query "[].name" -o tsv)
    foreach ($aksCluster in $aksArray)
    {
        kubectx $aksCluster
        Write-Host "`n"
        $Env:KUBECONTEXT = kubectl config current-context
        # Create Kubernetes - Azure Arc Cluster
        az connectedk8s connect --name $aksCluster `
            --resource-group $Env:resourceGroup `
            --location $Env:azureLocation `
            --tags 'Project=jumpstart_azure_arc_data_services' `
            --kube-config $Env:KUBECONFIG `
            --kube-context $Env:KUBECONTEXT
    }
}
# Run function
Arc-Onboarding

# workflow Arc-Onboarding
# {
#     $aksArray = $(az resource list --resource-group $Env:resourceGroup --resource-type "Microsoft.ContainerService/managedClusters" --query "[].name" -o tsv)

#     # The disks are processed in parallel.
#     ForEach -Parallel ($aksCluster in $aksArray)
#     {
#         # The commands run sequentially on each cluster.
#         kubectx $aksCluster
#         $Env:KUBECONTEXT = kubectl config current-context
#         # Create Kubernetes - Azure Arc Cluster
#         az connectedk8s connect --name $aksCluster `
#             --resource-group $Env:resourceGroup `
#             --location $Env:azureLocation `
#             --tags 'Project=jumpstart_azure_arc_data_services' `
#             --kube-config $Env:KUBECONFIG `
#             --kube-context $Env:KUBECONTEXT
#     }
# }

# # Run workflow
# Arc-Onboarding

Push-Location "C:\Users\$Env:adminUsername"

# Defining the Azure Arc-enabled data services target Arc-connected Kubernetes cluster
$connectedClusterName = $(az resource list --resource-group $Env:resourceGroup --resource-type "Microsoft.ContainerService/managedClusters" --query "[].name" -o tsv | Select-String 0)
kubectx $connectedClusterName
# Start-Sleep -Seconds 10

# Enabling Container Insights cluster extension
Write-Host "`n"
Write-Host "Enabling Container Insights cluster extension"
az k8s-extension create --name "azuremonitor-containers" --cluster-name $connectedClusterName --resource-group $Env:resourceGroup --cluster-type connectedClusters --extension-type Microsoft.AzureMonitor.Containers --configuration-settings logAnalyticsWorkspaceResourceID=$workspaceId
Write-Host "`n"

# Monitor pods across arc namespace
$kubectlMonShell = Start-Process -PassThru PowerShell {for (0 -lt 1) {kubectl get pod -n arc; Start-Sleep -Seconds 5; Clear-Host }}

# Installing Azure Arc-enabled data services extension
Write-Host "`n"
Write-Host "Installing Azure Arc-enabled data services extension"
az k8s-extension create --name arc-data-services `
                        --extension-type microsoft.arcdataservices `
                        --cluster-type connectedClusters `
                        --cluster-name $connectedClusterName `
                        --resource-group $Env:resourceGroup `
                        --auto-upgrade false `
                        --scope cluster `
                        --release-namespace arc `
                        --config Microsoft.CustomLocation.ServiceAccount=sa-arc-bootstrapper `

Write-Host "`n"
Do {
    Write-Host "Waiting for bootstrapper pod, hold tight...(20s sleeping loop)"
    Start-Sleep -Seconds 20
    $podStatus = $(if(kubectl get pods -n arc | Select-String "bootstrapper" | Select-String "Running" -Quiet){"Ready!"}Else{"Nope"})
    } while ($podStatus -eq "Nope")

$connectedClusterId = az connectedk8s show --name $connectedClusterName --resource-group $Env:resourceGroup --query id -o tsv

$extensionId = az k8s-extension show --name arc-data-services `
                                     --cluster-type connectedClusters `
                                     --cluster-name $connectedClusterName `
                                     --resource-group $Env:resourceGroup `
                                     --query id -o tsv

Start-Sleep -Seconds 20

# Create Custom Location
az customlocation create --name 'jumpstart-cl' `
                         --resource-group $Env:resourceGroup `
                         --namespace arc `
                         --host-resource-id $connectedClusterId `
                         --cluster-extension-ids $extensionId `
                         --kubeconfig $Env:KUBECONFIG

# Deploying Azure Arc Data Controller
Write-Host "`n"
Write-Host "Deploying Azure Arc Data Controller"
Write-Host "`n"

$customLocationId = $(az customlocation show --name "jumpstart-cl" --resource-group $Env:resourceGroup --query id -o tsv)
$workspaceId = $(az resource show --resource-group $Env:resourceGroup --name $Env:workspaceName --resource-type "Microsoft.OperationalInsights/workspaces" --query properties.customerId -o tsv)
$workspaceKey = $(az monitor log-analytics workspace get-shared-keys --resource-group $Env:resourceGroup --workspace-name $Env:workspaceName --query primarySharedKey -o tsv)

$dataControllerParams = "$Env:TempDir\dataController.parameters.json"

(Get-Content -Path $dataControllerParams) -replace 'resourceGroup-stage',$Env:resourceGroup | Set-Content -Path $dataControllerParams
(Get-Content -Path $dataControllerParams) -replace 'azdataUsername-stage',$Env:AZDATA_USERNAME | Set-Content -Path $dataControllerParams
(Get-Content -Path $dataControllerParams) -replace 'azdataPassword-stage',$Env:AZDATA_PASSWORD | Set-Content -Path $dataControllerParams
(Get-Content -Path $dataControllerParams) -replace 'customLocation-stage',$customLocationId | Set-Content -Path $dataControllerParams
(Get-Content -Path $dataControllerParams) -replace 'subscriptionId-stage',$Env:subscriptionId | Set-Content -Path $dataControllerParams
(Get-Content -Path $dataControllerParams) -replace 'spnClientId-stage',$Env:spnClientId | Set-Content -Path $dataControllerParams
(Get-Content -Path $dataControllerParams) -replace 'spnTenantId-stage',$Env:spnTenantId | Set-Content -Path $dataControllerParams
(Get-Content -Path $dataControllerParams) -replace 'spnClientSecret-stage',$Env:spnClientSecret | Set-Content -Path $dataControllerParams
(Get-Content -Path $dataControllerParams) -replace 'logAnalyticsWorkspaceId-stage',$workspaceId | Set-Content -Path $dataControllerParams
(Get-Content -Path $dataControllerParams) -replace 'logAnalyticsPrimaryKey-stage',$workspaceKey | Set-Content -Path $dataControllerParams

az deployment group create --resource-group $Env:resourceGroup `
                           --template-file "$Env:TempDir\dataController.json" `
                           --parameters "$Env:TempDir\dataController.parameters.json"

Write-Host "`n"
Do {
    Write-Host "Waiting for data controller. Hold tight, this might take a few minutes...(45s sleeping loop)"
    Start-Sleep -Seconds 45
    $dcStatus = $(if(kubectl get datacontroller -n arc | Select-String "Ready" -Quiet){"Ready!"}Else{"Nope"})
    } while ($dcStatus -eq "Nope")

Write-Host "`n"
Write-Host "Azure Arc data controller is ready!"
Write-Host "`n"

# If flag set, deploy SQL MI
if ( $Env:deploySQLMI -eq $true )
{
& "$Env:TempDir\DeploySQLMI.ps1"
}

# If flag set, deploy PostgreSQL
if ( $Env:deployPostgreSQL -eq $true )
{
& "$Env:TempDir\DeployPostgreSQL.ps1"
}

# Enabling data controller auto metrics & logs upload to log analytics
Write-Host "`n"
Write-Host "Enabling data controller auto metrics & logs upload to log analytics"
Write-Host "`n"
$Env:WORKSPACE_ID=$(az resource show --resource-group $Env:resourceGroup --name $Env:workspaceName --resource-type "Microsoft.OperationalInsights/workspaces" --query properties.customerId -o tsv)
$Env:WORKSPACE_SHARED_KEY=$(az monitor log-analytics workspace get-shared-keys --resource-group $Env:resourceGroup --workspace-name $Env:workspaceName  --query primarySharedKey -o tsv)
az arcdata dc update --name jumpstart-dc --resource-group $Env:resourceGroup --auto-upload-logs true
az arcdata dc update --name jumpstart-dc --resource-group $Env:resourceGroup --auto-upload-metrics true

# Applying Azure Data Studio settings template file and operations url shortcut
if ( $Env:deploySQLMI -eq $true -or $Env:deployPostgreSQL -eq $true ){
    Write-Host "`n"
    Write-Host "Copying Azure Data Studio settings template file"
    New-Item -Path "C:\Users\$Env:adminUsername\AppData\Roaming\azuredatastudio\" -Name "User" -ItemType "directory" -Force
    Copy-Item -Path "$Env:TempDir\settingsTemplate.json" -Destination "C:\Users\$Env:adminUsername\AppData\Roaming\azuredatastudio\User\settings.json"

    # Creating desktop url shortcuts for built-in Grafana and Kibana services 
    $GrafanaURL = kubectl get service/metricsui-external-svc -n arc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    $GrafanaURL = "https://"+$GrafanaURL+":3000"
    $Shell = New-Object -ComObject ("WScript.Shell")
    $Favorite = $Shell.CreateShortcut($Env:USERPROFILE + "\Desktop\Grafana.url")
    $Favorite.TargetPath = $GrafanaURL;
    $Favorite.Save()

    $KibanaURL = kubectl get service/logsui-external-svc -n arc -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
    $KibanaURL = "https://"+$KibanaURL+":5601"
    $Shell = New-Object -ComObject ("WScript.Shell")
    $Favorite = $Shell.CreateShortcut($Env:USERPROFILE + "\Desktop\Kibana.url")
    $Favorite.TargetPath = $KibanaURL;
    $Favorite.Save()
}

# Changing to Client VM wallpaper
$imgPath="$Env:TempDir\wallpaper.png"
$code = @' 
using System.Runtime.InteropServices; 
namespace Win32{ 
    
     public class Wallpaper{ 
        [DllImport("user32.dll", CharSet=CharSet.Auto)] 
         static extern int SystemParametersInfo (int uAction , int uParam , string lpvParam , int fuWinIni) ; 
         
         public static void SetWallpaper(string thePath){ 
            SystemParametersInfo(20,0,thePath,3); 
         }
    }
 } 
'@

add-type $code 
[Win32.Wallpaper]::SetWallpaper($imgPath)

# Kill the open PowerShell monitoring kubectl get pods
Stop-Process -Id $kubectlMonShell.Id

# Removing the LogonScript Scheduled Task so it won't run on next reboot
Unregister-ScheduledTask -TaskName "DataServicesLogonScript" -Confirm:$false
Start-Sleep -Seconds 5

Stop-Process -Name powershell -Force

Stop-Transcript