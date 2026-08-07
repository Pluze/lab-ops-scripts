[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$IfrPath,
    [Parameter(Mandatory)]
    [string]$PromptPattern,
    [string]$VariableBodyPath,
    [ValidateRange(0, 2147483647)]
    [int]$MatchIndex = 0,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'

function Convert-HexOrDecimalToUInt64([string]$Value) {
    if ($Value -match '^0x') {
        return [Convert]::ToUInt64($Value.Substring(2), 16)
    }
    return [Convert]::ToUInt64($Value, 10)
}

function Get-LeadingWhitespaceLength([string]$Value) {
    return [regex]::Match($Value, '^\s*').Value.Length
}

$resolvedIfrPath = (Resolve-Path -LiteralPath $IfrPath).Path
$lines = [IO.File]::ReadAllLines($resolvedIfrPath)

$varStores = @{}
foreach ($line in $lines) {
    if ($line -match '^\s*VarStore(?:Efi)?\s+Guid:\s*([0-9A-Fa-f-]+),\s*VarStoreId:\s*(0x[0-9A-Fa-f]+),.*?Size:\s*(0x[0-9A-Fa-f]+),\s*Name:\s*"([^"]+)"') {
        $varStores[$matches[2].ToUpperInvariant()] = [pscustomobject][ordered]@{
            Id = $matches[2].ToUpperInvariant()
            Name = $matches[4]
            Guid = $matches[1].ToLowerInvariant()
            Size = Convert-HexOrDecimalToUInt64 $matches[3]
        }
    }
}

$questions = [Collections.Generic.List[object]]::new()
for ($i = 0; $i -lt $lines.Length; $i++) {
    $line = $lines[$i]
    if ($line -notmatch '^\s*(OneOf|CheckBox|Numeric)\s+Prompt:\s*"([^"]*)"') { continue }

    $kind = $matches[1]
    $prompt = $matches[2]
    if ($prompt -notmatch $PromptPattern) { continue }
    if ($line -notmatch 'VarStoreId:\s*(0x[0-9A-Fa-f]+)') { continue }
    $varStoreId = $matches[1].ToUpperInvariant()
    if ($line -notmatch 'VarOffset:\s*(0x[0-9A-Fa-f]+)') { continue }
    $varOffsetText = $matches[1]

    $sizeBits = $null
    if ($line -match 'Size:\s*(8|16|32|64)') {
        $sizeBits = [int]$matches[1]
    }
    elseif ($kind -eq 'CheckBox') {
        $sizeBits = 8
    }
    else {
        continue
    }

    $questionIndent = Get-LeadingWhitespaceLength $line
    $options = [Collections.Generic.List[object]]::new()
    $explicitDefaults = [Collections.Generic.List[object]]::new()
    for ($j = $i + 1; $j -lt $lines.Length; $j++) {
        $childLine = $lines[$j]
        $childIndent = Get-LeadingWhitespaceLength $childLine
        if ($childLine.Trim() -eq 'End' -and $childIndent -le $questionIndent) { break }

        if ($childLine -match '^\s*OneOfOption\s+Option:\s*"([^"]*)"\s+Value:\s*(0x[0-9A-Fa-f]+|\d+)(.*)$') {
            $suffix = $matches[3]
            $options.Add([pscustomobject][ordered]@{
                Name = $matches[1]
                Value = Convert-HexOrDecimalToUInt64 $matches[2]
                Default = $suffix -match '(^|,\s*)Default(,|$)'
                ManufacturingDefault = $suffix -match '(^|,\s*)MfgDefault(,|$)'
            })
        }
        elseif ($childLine -match '^\s*Default\s+DefaultId:\s*(0x[0-9A-Fa-f]+)\s+Value:\s*(0x[0-9A-Fa-f]+|\d+)') {
            $explicitDefaults.Add([pscustomobject][ordered]@{
                DefaultId = $matches[1]
                Value = Convert-HexOrDecimalToUInt64 $matches[2]
            })
        }
    }

    $store = $varStores[$varStoreId]
    $offsetValue = Convert-HexOrDecimalToUInt64 $varOffsetText
    $questions.Add([pscustomobject][ordered]@{
        LineNumber = $i + 1
        Kind = $kind
        Prompt = $prompt
        VarStoreId = $varStoreId
        VarStoreName = if ($store) { $store.Name } else { $null }
        VarStoreGuid = if ($store) { $store.Guid } else { $null }
        VarStoreSize = if ($store) { $store.Size } else { $null }
        VarOffset = $offsetValue
        VarOffsetHex = ('0x{0:X}' -f $offsetValue)
        SizeBits = $sizeBits
        Options = @($options)
        ExplicitDefaults = @($explicitDefaults)
    })
}

if ($questions.Count -eq 0) {
    throw "No IFR question prompt matched pattern '$PromptPattern'."
}
if ($MatchIndex -ge $questions.Count) {
    throw "MatchIndex $MatchIndex is outside the $($questions.Count) matching IFR questions."
}

$selected = $questions[$MatchIndex]
$currentValue = $null
$decodedOption = $null
$resolvedVariableBodyPath = $null
if ($VariableBodyPath) {
    $resolvedVariableBodyPath = (Resolve-Path -LiteralPath $VariableBodyPath).Path
    $data = [IO.File]::ReadAllBytes($resolvedVariableBodyPath)
    $byteCount = [int]($selected.SizeBits / 8)
    $offset = [int64]$selected.VarOffset
    if (($offset + $byteCount) -gt $data.LongLength) {
        throw "Variable body is too short for offset $($selected.VarOffsetHex) and $($selected.SizeBits)-bit value."
    }

    switch ($selected.SizeBits) {
        8  { $currentValue = [uint64]$data[$offset] }
        16 { $currentValue = [uint64][BitConverter]::ToUInt16($data, [int]$offset) }
        32 { $currentValue = [uint64][BitConverter]::ToUInt32($data, [int]$offset) }
        64 { $currentValue = [BitConverter]::ToUInt64($data, [int]$offset) }
    }
    $decodedOption = @($selected.Options | Where-Object Value -eq $currentValue | Select-Object -First 1)
    if ($decodedOption.Count -eq 0) { $decodedOption = $null } else { $decodedOption = $decodedOption[0] }
}

$result = [pscustomobject][ordered]@{
    Timestamp = (Get-Date).ToString('o')
    ReadOnly = $true
    IfrPath = $resolvedIfrPath
    PromptPattern = $PromptPattern
    MatchingQuestionCount = $questions.Count
    MatchingQuestions = @($questions)
    SelectedMatchIndex = $MatchIndex
    Question = $selected
    VariableBodyPath = $resolvedVariableBodyPath
    CurrentValue = $currentValue
    CurrentValueHex = if ($null -ne $currentValue) { '0x{0:X}' -f $currentValue } else { $null }
    DecodedOption = $decodedOption
}

$json = $result | ConvertTo-Json -Depth 8
if ($OutputPath) {
    $parent = Split-Path -Parent $OutputPath
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8
}
$json
