<#
.SYNOPSIS
    Universal OTP & Password Decryptor Utility (CLI & GUI)
    Supports Base64 OTPs, Hex strings (0x...), and AES-256 encrypted passwords (SCIPL, MPMS, PMC, SCPL).

.EXAMPLE
    .\Decode-OTP.ps1 -InputText "NjQ4NDU3"
    .\Decode-OTP.ps1 -InputText "qRbaj8yHFQCTwPNd6bZ4EZFzF4xu3O826ddgc7LRA6g="
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [string]$InputText
)

Add-Type -AssemblyName System.Security

function Decrypt-Universal($inputStr) {
    if ([string]::IsNullOrWhiteSpace($inputStr)) { return @{ Text = ""; Method = "" } }
    $clean = $inputStr.Trim()

    $keys = @(
        "SCIPLSPBNI99212",
        "LPICS00223SPBNI",
        "SCIPL",
        "SCPL",
        "MPMS",
        "UNNATI",
        "PMC",
        "AKOLA",
        "PARBHANI",
        "WASHIM",
        "AMRAVATI",
        "JALNA",
        "PALUS",
        "admin",
        "password",
        "123456",
        "SCIPL@123",
        "SCPL@123",
        "MPMS@123"
    )

    # 1. Try AES-256 (Unicode & UTF-8 with Rfc2898 "Ivan Medvedev" salt)
    if ($clean.Length -ge 16 -and ($clean.Length % 4 -eq 0)) {
        try {
            $cipherBytes = [System.Convert]::FromBase64String($clean.Replace(" ", "+"))
            $salt = [System.Text.Encoding]::ASCII.GetBytes("Ivan Medvedev")
            
            foreach ($k in $keys) {
                try {
                    $pdb = New-Object System.Security.Cryptography.Rfc2898DeriveBytes($k, $salt)
                    $aes = [System.Security.Cryptography.Aes]::Create()
                    $aes.Key = $pdb.GetBytes(32)
                    $aes.IV = $pdb.GetBytes(16)
                    
                    $ms = New-Object System.IO.MemoryStream
                    $cs = New-Object System.Security.Cryptography.CryptoStream($ms, $aes.CreateDecryptor(), [System.Security.Cryptography.CryptoStreamMode]::Write)
                    $cs.Write($cipherBytes, 0, $cipherBytes.Length)
                    $cs.Close()

                    $decBytes = $ms.ToArray()
                    $decUnicode = [System.Text.Encoding]::Unicode.GetString($decBytes)
                    if ($decUnicode -match '^[\x20-\x7E]+$' -and $decUnicode.Length -ge 2) {
                        return @{
                            Text = $decUnicode
                            Method = "AES-256 Unicode (Key: $k)"
                            Subtitle = "Decrypted Password / Secret"
                        }
                    }

                    $decUtf8 = [System.Text.Encoding]::UTF8.GetString($decBytes)
                    if ($decUtf8 -match '^[\x20-\x7E]+$' -and $decUtf8.Length -ge 2) {
                        return @{
                            Text = $decUtf8
                            Method = "AES-256 UTF-8 (Key: $k)"
                            Subtitle = "Decrypted Password / Secret"
                        }
                    }
                } catch {}
            }
        } catch {}
    }

    # 2. Hex String (0x...)
    if ($clean.StartsWith("0x", [System.StringComparison]::OrdinalIgnoreCase)) {
        try {
            $hex = $clean.Substring(2)
            if ($hex.Length % 2 -ne 0) { $hex = "0" + $hex }
            $bytes = New-Object byte[] ($hex.Length / 2)
            for ($i = 0; $i -lt $hex.Length; $i += 2) {
                $bytes[$i / 2] = [System.Convert]::ToByte($hex.Substring($i, 2), 16)
            }
            $otpText = [System.Text.Encoding]::UTF8.GetString($bytes).Trim()
            if ($otpText -match '^[\x20-\x7E]+$') {
                return @{
                    Text = $otpText
                    Method = "Hexadecimal (0x...)"
                    Subtitle = "$($otpText.Length)-Digit Verification Code / String"
                }
            }
        } catch {}
    }

    # 3. Base64 standard (e.g. NjQ4NDU3 -> 648457)
    try {
        $b64 = $clean -replace '\s+', ''
        $mod = $b64.Length % 4
        if ($mod -gt 0) { $b64 += "=" * (4 - $mod) }
        $decodedBytes = [System.Convert]::FromBase64String($b64)
        $otpText = [System.Text.Encoding]::UTF8.GetString($decodedBytes).Trim()
        
        if ($otpText -match '^[\x20-\x7E]+$') {
            return @{
                Text = $otpText
                Method = "Base64 (Standard)"
                Subtitle = "$($otpText.Length)-Digit Verification Code"
            }
        }
    } catch {}

    # 4. XOR Cipher
    try {
        $cleanB64 = $clean.Trim().Replace(' ', '')
        $rawBytes = [System.Convert]::FromBase64String($cleanB64)
        foreach ($k in $keys) {
            $chars = New-Object char[] $rawBytes.Length
            for ($i = 0; $i -lt $rawBytes.Length; $i++) {
                $kChar = [int]$k[$i % $k.Length]
                $chars[$i] = [char]($rawBytes[$i] -bxor $kChar)
            }
            $xorStr = -join $chars
            if ($xorStr -match '^[a-zA-Z0-9@#\$\*\.\-_! ]{3,30}$') {
                return @{
                    Text = $xorStr
                    Method = "XOR Cipher (Key: $k)"
                    Subtitle = "Decrypted String"
                }
            }
        }
    } catch {}

    return @{
        Text = $clean
        Method = "Plain Text / Unchanged"
        Subtitle = "Decoded String"
    }
}

if (-not $InputText) {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " UNIVERSAL OTP & PASSWORD DECRYPTOR" -ForegroundColor White
    Write-Host "==========================================================" -ForegroundColor Cyan
    $InputText = Read-Host "Enter Encoded OTP or Encrypted Password"
}

if ([string]::IsNullOrWhiteSpace($InputText)) {
    Write-Warning "No input provided."
    return
}

$res = Decrypt-Universal $InputText

Write-Host ""
Write-Host "==========================================================" -ForegroundColor DarkGray
Write-Host " RAW INPUT:       $InputText" -ForegroundColor Gray
Write-Host " METHOD / KEY:    $($res.Method)" -ForegroundColor Cyan
Write-Host " DECRYPTED VALUE: $($res.Text)" -ForegroundColor Green
Write-Host " TYPE:            $($res.Subtitle)" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor DarkGray
Write-Host ""

try {
    Add-Type -AssemblyName PresentationCore
    [System.Windows.Clipboard]::SetText($res.Text)
    Write-Host "[Copied to Clipboard!]" -ForegroundColor DarkGreen
} catch {}
