#requires -Version 7.0
<#
.SYNOPSIS
    Check, and optionally grant, your own access to the Foundry model the
    Chapter 6 agent calls.

.DESCRIPTION
    The Chapter 6 agent runs inside the Ward General app and calls the gpt-5
    deployment as YOU, through DefaultAzureCredential. That needs a Foundry
    data-plane role on the account - typically Cognitive Services OpenAI User.
    Owner and Contributor carry no data actions, so even a subscription owner
    gets 401 on the agent's first model call without it. Chapter 5 granted this
    role only to the SQL server's and the gateway's managed identities.

    The script reads the agent endpoint (Agent__Endpoint, else Agent:Endpoint in
    src/WardGeneral.Web/appsettings.Development.json, else appsettings.json),
    finds that Foundry account in the current subscription, and checks whether
    the signed-in user already holds a role that allows chat completions there,
    directly, through a group, or inherited from the resource group.

    Without -Apply it only reports. With -Apply it assigns Cognitive Services
    OpenAI User to the signed-in user on that one account. It never assigns a
    role to anyone else and never changes the account itself.

    Assigning a role needs Microsoft.Authorization/roleAssignments/write - Owner,
    User Access Administrator, or Role Based Access Control Administrator - the
    same rights Chapter 5's deploy already required. A new assignment can take a
    few minutes to take effect.

.PARAMETER Endpoint
    The Foundry endpoint, e.g. https://contoso-ai.openai.azure.com/. Defaults to
    the app's configured Agent endpoint.

.PARAMETER Apply
    Create the role assignment if it is missing.

.PARAMETER Quiet
    Report only through the exit code: 0 when you have access, 1 when the role
    is missing. Problems that stop the check (no endpoint, not signed in) still
    throw. Used by the app's run preflight when the AiAgent flag is on.

.EXAMPLE
    ./grant-model-access.ps1
    Report whether you can call the agent's model.

.EXAMPLE
    ./grant-model-access.ps1 -Apply
    Grant yourself Cognitive Services OpenAI User on that account if needed.
#>
[CmdletBinding()]
param(
    [string] $Endpoint,
    [switch] $Apply,
    [switch] $Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Say([string] $Text, [string] $Color = 'Gray') {
    if (-not $Quiet) { Write-Host $Text -ForegroundColor $Color }
}

$roleName   = 'Cognitive Services OpenAI User'
$chatAction = 'Microsoft.CognitiveServices/accounts/OpenAI/deployments/chat/completions/action'

if (-not $Endpoint) { $Endpoint = $env:Agent__Endpoint }
if (-not $Endpoint) {
    $webDir = Join-Path $PSScriptRoot '..' 'ch04-first-app' 'src' 'WardGeneral.Web'
    foreach ($file in 'appsettings.Development.json', 'appsettings.json') {
        $path = Join-Path $webDir $file
        if (Test-Path $path) {
            $settings = Get-Content $path -Raw | ConvertFrom-Json
            $value = if ($settings.PSObject.Properties['Agent']) { $settings.Agent.Endpoint } else { $null }
            if (-not [string]::IsNullOrWhiteSpace($value)) { $Endpoint = $value; break }
        }
    }
}
if ([string]::IsNullOrWhiteSpace($Endpoint) -or $Endpoint -match '<[^>]*>') {
    throw 'No agent endpoint. Set Agent:Endpoint in examples/ch04-first-app/src/WardGeneral.Web/appsettings.Development.json (see the Chapter 6 README, Configure), or pass -Endpoint.'
}

$accountName = ([Uri]$Endpoint).Host.Split('.')[0]

$account = az account show --query '{name:name, id:id}' -o json 2>$null | ConvertFrom-Json
if (-not $account) { throw 'Not signed in. Run: az login' }

$me = az ad signed-in-user show --query '{id:id, upn:userPrincipalName}' -o json 2>$null | ConvertFrom-Json
if (-not $me -or -not $me.id) {
    throw 'Could not read the signed-in user. This script grants a role to a signed-in Entra user; sign in with az login as yourself.'
}

$resourceId = @(az cognitiveservices account list --query "[?name=='$accountName'].id" -o tsv) | Select-Object -First 1
if ([string]::IsNullOrWhiteSpace($resourceId)) {
    throw "No Foundry account named '$accountName' in subscription '$($account.name)'. Check the endpoint, or select the subscription that holds it (az account set)."
}

Say 'Chapter 6 agent model access' Cyan
Say "  subscription : $($account.name)"
Say "  account      : $accountName"
Say "  signed in as : $($me.upn)"
Say ''

# Any role that allows chat completions counts - assigned directly, through a
# group, or inherited from the resource group or subscription.
$roles = @(@(az role assignment list --assignee $me.id --scope $resourceId --include-inherited --include-groups --query '[].roleDefinitionName' -o tsv) |
    Where-Object { $_ } | Sort-Object -Unique)
$granting = @(foreach ($role in $roles) {
    $dataActions = @(az role definition list --name $role --query '[0].permissions[].dataActions[]' -o tsv)
    if (@($dataActions | Where-Object { $chatAction -like $_ }).Count -gt 0) { $role }
})

if ($granting.Count -gt 0) {
    Say "OK: you can call the agent's model through: $($granting -join ', ')." Green
    exit 0
}

Say "MISSING: none of your roles on '$accountName' allows chat completions." Yellow
if ($roles.Count -gt 0) {
    Say "  Roles you have there: $($roles -join ', ') (no data actions for the model)." DarkGray
}
Say "  Proposed: assign '$roleName' to $($me.upn) on $accountName." Yellow

if (-not $Apply) {
    Say ''
    Say 'Preview only. Re-run with -Apply to create the assignment.' Yellow
    exit 1
}

az role assignment create `
    --assignee-object-id $me.id `
    --assignee-principal-type User `
    --role $roleName `
    --scope $resourceId `
    --output none
if ($LASTEXITCODE -ne 0) {
    throw "Could not assign '$roleName'. Assigning roles needs Owner, User Access Administrator, or Role Based Access Control Administrator; ask someone who has it to run this script with -Apply for you, or to make the assignment."
}

Write-Host "Assigned '$roleName' to $($me.upn) on $accountName." -ForegroundColor Green
Write-Host 'It can take a few minutes to take effect. If the agent still returns 401, wait and retry.' -ForegroundColor DarkGray
