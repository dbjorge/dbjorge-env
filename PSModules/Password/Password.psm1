
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-SecurePassword {
    Param(
        [int]$Length = 32,
        [string]$CandidateChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_!@#$%^&*()_[]{};:/"
    )

    $CandidateCharArray = $CandidateChars.ToCharArray();
    $MaxUnbiasedRandomByte = ([byte]::MaxValue / $CandidateCharArray.Length) * $CandidateCharArray.Length;
    $Rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider;
    $Password = '';
    $RandomBytes = New-Object "System.Byte[]" ($Length * 8);
    $RandomBytesNextUnusedIndex = $RandomBytes.Length;

    while ($Password.Length -lt $Length) {
        if ($RandomBytesNextUnusedIndex -ge $RandomBytes.Length) {
            $Rng.GetBytes($RandomBytes);
            $RandomBytesNextUnusedIndex = 0;
        }
        
        $NextByte = $RandomBytes[$RandomBytesNextUnusedIndex];
        $RandomBytesNextUnusedIndex += 1;

        # Clamping random bytes to this number before doing $RandomByte % $MaxTargetNumber avoids issues
        # described in https://channel9.msdn.com/Events/GoingNative/2013/rand-Considered-Harmful
        if ($NextByte -lt $MaxUnbiasedRandomByte) {
            $NextChar = $CandidateCharArray[$NextByte % $CandidateChars.Length];
            $Password += $NextChar;
        }
    }

    return $Password;
}
