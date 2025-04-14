function Write-FunctionBlock{
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Currently using Write-Host because it supports -NoNewLine')]
    [CmdletBinding()]
    param(
        [string]$lineOne,
        [string]$lineTwo,
        [string]$lineColor
    )

    # Calculate the amount of left padding needed
    $l1Padding = [math]::floor((41-$lineOne.Length) / 2)
    $l2Padding = [math]::floor((41-$lineTwo.Length) / 2)

    Write-Host "========================================="
    Write-Host $lineOne.PadLeft((41 - $l1Padding), " ")

    switch ($lineColor.ToLower()) {
        "red"{
            Write-Host $lineTwo.PadLeft((41 - $l2Padding), " ") -ForegroundColor Red
        }

        "green" {
            Write-Host $lineTwo.PadLeft((41 - $l2Padding), " ") -ForegroundColor Green
        }

        default {
            Write-Host $lineTwo.PadLeft((41 - $l2Padding), " ")
        }
    }

    Write-Host "========================================="
}