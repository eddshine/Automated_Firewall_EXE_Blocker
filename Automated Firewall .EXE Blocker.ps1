# UAC Elevation Code
param([switch]$Elevated)

function Test-Admin {
    $currentUser = New-Object Security.Principal.WindowsPrincipal $([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

if ((Test-Admin) -eq $false) {
    if ($Elevated) {
        Write-Host "Failed to elevate privileges. Exiting..."
        exit
    } else {
        Start-Process powershell.exe -Verb RunAs -ArgumentList ('-noprofile -noexit -file "{0}" -Elevated' -f ($myinvocation.MyCommand.Definition))
    }
    exit
}

# Add Windows Forms
Add-Type -AssemblyName System.Windows.Forms

# Create the Form
$form = New-Object system.Windows.Forms.Form
$form.Text = "Automated Firewall .EXE Blocker"
$form.Width = 500
$form.Height = 500
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Add_FormClosing({
    $form.Dispose()  # Dispose of the form resources
    [System.Windows.Forms.Application]::Exit()  # Exit the WinForms application
    exit  # Terminate the PowerShell script
})


# Create a Label
$label = New-Object system.Windows.Forms.Label
$label.Text = "Select FOLDERS or .EXE Files to block in INBOUND and OUTBOUND:"
$label.AutoSize = $true
$label.Top = 20
$label.Left = 10
$form.Controls.Add($label)

# Create a ListBox
$listBoxPaths = New-Object system.Windows.Forms.ListBox
$listBoxPaths.Width = 465
$listBoxPaths.Height = 200
$listBoxPaths.Top = 50
$listBoxPaths.Left = 10
$form.Controls.Add($listBoxPaths)

# Create a Button for Adding Paths
$btnBrowse = New-Object system.Windows.Forms.Button
$btnBrowse.Text = "Add Folders or .exe"
$btnBrowse.Top = 270
$btnBrowse.Left = 10
$btnBrowse.Width = 150
$btnBrowse.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnBrowse)

# Create Buttons for Remove and Block
$btnRemove = New-Object system.Windows.Forms.Button
$btnRemove.Text = "Remove Selected"
$btnRemove.Top = 270
$btnRemove.Left = 210
$btnRemove.Width = 120
$btnRemove.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnRemove)

# Create a Button to Clear all paths from the ListBox
$btnClearAll = New-Object system.Windows.Forms.Button
$btnClearAll.Text = "Clear All"
$btnClearAll.Top = 270
$btnClearAll.Left = 375  # Position next to "Remove Selected" button
$btnClearAll.Width = 100
$btnClearAll.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnClearAll)

$btnBlock = New-Object system.Windows.Forms.Button
$btnBlock.Text = "BLOCK IT!"
$btnBlock.Top = 410
$btnBlock.Left = 325
$btnBlock.Width = 150
$btnBlock.Cursor = [System.Windows.Forms.Cursors]::Hand
$form.Controls.Add($btnBlock)

# Create Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Minimum = 0
$progressBar.Maximum = 100
$progressBar.Value = 0
$progressBar.Width = 465
$progressBar.Height = 30
$progressBar.Top = 340
$progressBar.Left = 10
$progressBar.BackColor = "#A9A9A9"
$form.Controls.Add($progressBar)

# Create Progress Label
$progressLabel = New-Object system.Windows.Forms.Label
$progressLabel.Text = "Waiting to start..."
$progressLabel.AutoSize = $true
$progressLabel.Top = 375
$progressLabel.Left = 10
$form.Controls.Add($progressLabel)

# Create FolderBrowserDialog and OpenFileDialog
$folderBrowser = New-Object System.Windows.Forms.FolderBrowserDialog
$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$openFileDialog.Filter = "Executable Files (*.exe)|*.exe"

# Add Functionality to Buttons
$btnBrowse.Add_Click({
    $choice = [System.Windows.Forms.MessageBox]::Show(
        "Select a folder (Yes) or a .exe file (No).",
        "Choose Path Type",
        [System.Windows.Forms.MessageBoxButtons]::YesNoCancel
    )
    if ($choice -eq [System.Windows.Forms.DialogResult]::Yes) {
        if ($folderBrowser.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $listBoxPaths.Items.Add($folderBrowser.SelectedPath)
        }
    } elseif ($choice -eq [System.Windows.Forms.DialogResult]::No) {
        if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $listBoxPaths.Items.Add($openFileDialog.FileName)
        }
    }
})

$btnRemove.Add_Click({
    if ($listBoxPaths.SelectedItem) {
        $listBoxPaths.Items.Remove($listBoxPaths.SelectedItem)
    } else {
        [System.Windows.Forms.MessageBox]::Show("Please select an item to remove.")
    }
})

# Event to handle clearing all items from the ListBox
$btnClearAll.Add_Click({
    if ($listBoxPaths.Items.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("The list is already empty.")
        return
    }

    $listBoxPaths.Items.Clear()
    [System.Windows.Forms.MessageBox]::Show("All items have been cleared.")
})

function Update-ProgressBar($progress, $message) {
    $progressBar.Value = $progress
    $progressLabel.Text = $message
    $form.Refresh()
}

$btnBlock.Add_Click({
    if ($listBoxPaths.Items.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please add at least one folder or .exe file.")
        return
    }

    $totalItems = 0
    foreach ($item in $listBoxPaths.Items) {
        if (Test-Path $item) {
            if (Test-Path -PathType Leaf -Path $item) {
                $totalItems++
            } elseif (Test-Path -PathType Container -Path $item) {
                $totalItems += (Get-ChildItem -Path $item -Recurse -Filter *.exe).Count
            }
        }
    }

    if ($totalItems -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No .exe files found.")
        return
    }

    $currentProgress = 0
    $progressStep = 100 / $totalItems

    foreach ($item in $listBoxPaths.Items) {
        if (Test-Path $item) {
            if (Test-Path -PathType Leaf -Path $item) {
                $exePath = $item

                # Create rules if they don't exist
                $inboundRuleExists = Get-NetFirewallRule | Where-Object { 
                    $_.Direction -eq "Inbound" -and $_.Program -eq $exePath 
                }
                $outboundRuleExists = Get-NetFirewallRule | Where-Object { 
                    $_.Direction -eq "Outbound" -and $_.Program -eq $exePath 
                }

                if (-not $inboundRuleExists) {
                    New-NetFirewallRule -DisplayName "Block Inbound $([System.IO.Path]::GetFileName($exePath))" `
                                        -Direction Inbound -Action Block -Program $exePath
                }

                if (-not $outboundRuleExists) {
                    New-NetFirewallRule -DisplayName "Block Outbound $([System.IO.Path]::GetFileName($exePath))" `
                                        -Direction Outbound -Action Block -Program $exePath
                }
                $currentProgress += $progressStep
                Update-ProgressBar $currentProgress "Blocking $([System.IO.Path]::GetFileName($exePath))..."
            } elseif (Test-Path -PathType Container -Path $item) {
                foreach ($exe in Get-ChildItem -Path $item -Recurse -Filter *.exe) {
                    $exePath = $exe.FullName

                    # Create rules if they don't exist
                    $inboundRuleExists = Get-NetFirewallRule | Where-Object { 
                        $_.Direction -eq "Inbound" -and $_.Program -eq $exePath 
                    }
                    $outboundRuleExists = Get-NetFirewallRule | Where-Object { 
                        $_.Direction -eq "Outbound" -and $_.Program -eq $exePath 
                    }

                    if (-not $inboundRuleExists) {
                        New-NetFirewallRule -DisplayName "Block Inbound $($exe.Name)" `
                                            -Direction Inbound -Action Block -Program $exePath
                    }

                    if (-not $outboundRuleExists) {
                        New-NetFirewallRule -DisplayName "Block Outbound $($exe.Name)" `
                                            -Direction Outbound -Action Block -Program $exePath
                    }
                    $currentProgress += $progressStep
                    Update-ProgressBar $currentProgress "Blocking $($exe.Name)..."
                }
            }
        }
    }

    Update-ProgressBar 100 "Blocking complete!"
    [System.Windows.Forms.MessageBox]::Show("All selected items have been blocked!")
    Start-Sleep -Seconds 2
    Update-ProgressBar 0 "Waiting to start..."
})

# Show the form
$form.ShowDialog()
