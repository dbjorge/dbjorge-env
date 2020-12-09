# Prerequisite: Import-Module AzureAD

# usage: Get-AzureADGroup -SearchString 'a11y-insights-team` | Get-AzureADGroupMembersRecursive
function Get-AzureADGroupMembersRecursive([string]$SearchString) {
    $group = Get-AzureADGroup -SearchString $SearchString;
    return Get-AzureADGroupMembersRecursiveFromGroup -Group $group
}

function Get-AzureADGroupMembersRecursiveFromGroup($Group) {
    Write-Host "Querying members of $($Group.DisplayName)"
    $members = $Group | Get-AzureADGroupMember;
    $memberGroups = @($members | Where-Object ObjectType -eq 'Group');
    $memberUsers = @($members | Where-Object ObjectType -ne 'Group');
    $memberGroupUsers = @($memberGroups | ForEach-Object { Get-AzureADGroupMembersRecursiveFromGroup -Group $_ });
    return @($memberUsers + $memberGroupUsers) | Select-Object -Unique
}


Export-ModuleMember -Function @(
    'Get-AzureADGroupMembersRecursive'
);