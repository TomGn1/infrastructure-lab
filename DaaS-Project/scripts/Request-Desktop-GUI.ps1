<#
.SYNOPSIS
    Interface graphique WPF pour demander un desktop éphémère
.DESCRIPTION
    Interface moderne avec barre de progression et informations de session
    Version 2.0 - Améliorations UX
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms

# ========================================
# Configuration
# ========================================

$OrchestratorUrl = "http://<ip_serveur>:5000"
$Username = $env:USERNAME
$Domain = "PROTO"

# Variables globales
$script:SessionInfo = $null

# ========================================
# Interface XAML
# ========================================

[xml]$XAML = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Desktop as a Service - DaaS" 
        Height="520" 
        Width="600"
        WindowStartupLocation="CenterScreen"
        ResizeMode="NoResize"
        Background="#F5F5F5">
    
    <Window.Resources>
        <!-- Style pour les boutons -->
        <Style TargetType="Button">
            <Setter Property="Background" Value="#0078D4"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Padding" Value="15,10"/>
            <Setter Property="Margin" Value="5"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#005A9E"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                    <Setter Property="Background" Value="#CCCCCC"/>
                    <Setter Property="Foreground" Value="#666666"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        
        <!-- Style pour les TextBlocks de label -->
        <Style x:Key="LabelStyle" TargetType="TextBlock">
            <Setter Property="FontWeight" Value="Bold"/>
            <Setter Property="Foreground" Value="#333333"/>
            <Setter Property="Margin" Value="0,0,10,0"/>
        </Style>
        
        <!-- Style pour les TextBlocks de valeur -->
        <Style x:Key="ValueStyle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#0078D4"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
        </Style>
    </Window.Resources>
    
    <Grid Margin="20">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        
        <!-- En-tête -->
        <Border Grid.Row="0" 
                Background="#0078D4" 
                Padding="20" 
                Margin="-20,-20,-20,20"
                CornerRadius="0">
            <StackPanel>
                <TextBlock Text="🖥️  Desktop as a Service" 
                          FontSize="24" 
                          FontWeight="Bold" 
                          Foreground="White" 
                          HorizontalAlignment="Center"/>
                <TextBlock Text="Orchestrateur de Desktops Éphémères" 
                          FontSize="12" 
                          Foreground="#E0E0E0" 
                          HorizontalAlignment="Center" 
                          Margin="0,5,0,0"/>
            </StackPanel>
        </Border>
        
        <!-- Informations utilisateur -->
        <Border Grid.Row="1" 
                Background="White" 
                Padding="15" 
                Margin="0,0,0,15"
                CornerRadius="5"
                BorderBrush="#E0E0E0"
                BorderThickness="1">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <TextBlock Grid.Column="0" 
                          Text="👤 Utilisateur :" 
                          Style="{StaticResource LabelStyle}"/>
                <TextBlock Grid.Column="1" 
                          Name="txtUsername" 
                          Style="{StaticResource ValueStyle}"/>
            </Grid>
        </Border>
        
        <!-- Zone principale -->
        <Border Grid.Row="2" 
                Background="White" 
                Padding="20"
                CornerRadius="5"
                BorderBrush="#E0E0E0"
                BorderThickness="1">
            <Grid>
                <StackPanel Name="panelCreation" Visibility="Visible">
                    <TextBlock Name="txtStatus" 
                              Text="Prêt à créer un desktop" 
                              FontSize="16" 
                              FontWeight="SemiBold"
                              Foreground="#333333"
                              HorizontalAlignment="Center" 
                              Margin="0,20,0,20"/>
                    
                    <ProgressBar Name="progressBar" 
                                Height="25" 
                                Minimum="0" 
                                Maximum="100" 
                                Value="0"
                                Margin="0,0,0,10"/>
                    
                    <TextBlock Name="txtProgress" 
                              Text="" 
                              FontSize="12"
                              Foreground="#666666"
                              HorizontalAlignment="Center"/>
                </StackPanel>
                
                <!-- Informations de session (cachées au départ) -->
                <StackPanel Name="panelSession" Visibility="Collapsed">
                    <TextBlock Text="✅ Desktop créé avec succès !" 
                              FontSize="18" 
                              FontWeight="Bold"
                              Foreground="#107C10"
                              HorizontalAlignment="Center" 
                              Margin="0,0,0,20"/>
                    
                    <Grid Margin="0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="120"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="Session ID :" Style="{StaticResource LabelStyle}"/>
                        <TextBlock Grid.Column="1" Name="txtSessionId" Style="{StaticResource ValueStyle}"/>
                    </Grid>
                    
                    <Grid Margin="0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="120"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="Nom VM :" Style="{StaticResource LabelStyle}"/>
                        <TextBlock Grid.Column="1" Name="txtVmName" Style="{StaticResource ValueStyle}"/>
                    </Grid>
                    
                    <Grid Margin="0,5">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="120"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="Adresse IP :" Style="{StaticResource LabelStyle}"/>
                        <TextBlock Grid.Column="1" Name="txtVmIp" Style="{StaticResource ValueStyle}"/>
                    </Grid>
                    
                    <Grid Margin="0,5,0,15">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="120"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>
                        <TextBlock Grid.Column="0" Text="Port RDP :" Style="{StaticResource LabelStyle}"/>
                        <TextBlock Grid.Column="1" Name="txtRdpPort" Style="{StaticResource ValueStyle}"/>
                    </Grid>
                    
                    <!-- Info destruction automatique -->
                    <Border Background="#E3F2FD" 
                           Padding="12" 
                           Margin="0,10,0,0"
                           CornerRadius="3"
                           BorderBrush="#2196F3"
                           BorderThickness="1">
                        <StackPanel>
                            <TextBlock Text="ℹ️  Destruction automatique" 
                                      FontWeight="Bold" 
                                      Foreground="#1976D2"
                                      Margin="0,0,0,5"/>
                            <TextBlock Foreground="#1565C0"
                                      TextWrapping="Wrap"
                                      FontSize="11">
                                Le desktop sera automatiquement détruit après votre déconnexion RDP ou après 30 minutes d'inactivité.
                                <LineBreak/>
                                <LineBreak/>
                                💾 Pensez à sauvegarder vos fichiers dans le dossier <Bold>~/Partage</Bold> !
                            </TextBlock>
                        </StackPanel>
                    </Border>
                </StackPanel>
            </Grid>
        </Border>
        
        <!-- Boutons d'action -->
        <StackPanel Grid.Row="3" 
                   Orientation="Horizontal" 
                   HorizontalAlignment="Center"
                   Margin="0,15,0,0">
            <Button Name="btnCreate" 
                   Content="Créer une session virtuelle" 
                   Width="230"
                   Background="#107C10"/>
            <Button Name="btnConnect" 
                   Content="🖥️  Se connecter en RDP" 
                   Width="200"
                   IsEnabled="False"
                   Visibility="Collapsed"/>
            <Button Name="btnClose" 
                   Content="✖️  Fermer" 
                   Width="200"
                   Background="#6C757D"
                   Visibility="Collapsed"/>
        </StackPanel>
        
        <!-- Pied de page -->
        <TextBlock Grid.Row="4" 
                  Text="DaaS Orchestrator v2.0 - Tom TSSR" 
                  FontSize="10" 
                  Foreground="#999999"
                  HorizontalAlignment="Center"
                  Margin="0,15,0,0"/>
    </Grid>
</Window>
"@

# ========================================
# Chargement de la fenêtre
# ========================================

$reader = New-Object System.Xml.XmlNodeReader $XAML
$Window = [Windows.Markup.XamlReader]::Load($reader)

# Récupérer les contrôles
$txtUsername = $Window.FindName("txtUsername")
$txtStatus = $Window.FindName("txtStatus")
$txtProgress = $Window.FindName("txtProgress")
$progressBar = $Window.FindName("progressBar")
$panelCreation = $Window.FindName("panelCreation")
$panelSession = $Window.FindName("panelSession")
$txtSessionId = $Window.FindName("txtSessionId")
$txtVmName = $Window.FindName("txtVmName")
$txtVmIp = $Window.FindName("txtVmIp")
$txtRdpPort = $Window.FindName("txtRdpPort")
$btnCreate = $Window.FindName("btnCreate")
$btnConnect = $Window.FindName("btnConnect")
$btnClose = $Window.FindName("btnClose")

# Initialiser les valeurs
$txtUsername.Text = "$Username@$Domain"

# ========================================
# Fonctions
# ========================================

function Create-Desktop {
    $btnCreate.IsEnabled = $false
    $txtStatus.Text = "Création du desktop en cours..."
    
    # Créer un runspace pour ne pas bloquer l'UI
    $Runspace = [runspacefactory]::CreateRunspace()
    $Runspace.ApartmentState = "STA"
    $Runspace.ThreadOptions = "ReuseThread"
    $Runspace.Open()
    $Runspace.SessionStateProxy.SetVariable("Window", $Window)
    $Runspace.SessionStateProxy.SetVariable("OrchestratorUrl", $OrchestratorUrl)
    $Runspace.SessionStateProxy.SetVariable("Username", $Username)
    
    $PowerShell = [powershell]::Create()
    $PowerShell.Runspace = $Runspace
    
    [void]$PowerShell.AddScript({
            param($Window, $OrchestratorUrl, $Username)
        
            function Update-ProgressLocal {
                param([int]$Percent, [string]$Status)
                $Window.Dispatcher.Invoke([action] {
                        $progressBar = $Window.FindName("progressBar")
                        $txtProgress = $Window.FindName("txtProgress")
                        $txtStatus = $Window.FindName("txtStatus")
                        $progressBar.Value = $Percent
                        $txtProgress.Text = $Status
                        $txtStatus.Text = "$Status"
                    })
            }
        
            try {
                Update-ProgressLocal -Percent 10 -Status "Connexion à l'orchestrateur..."
                Start-Sleep -Seconds 1
            
                Update-ProgressLocal -Percent 20 -Status "Envoi de la demande..."
            
                $body = @{ username = $Username } | ConvertTo-Json
            
                Update-ProgressLocal -Percent 30 -Status "Création de la VM (Terraform)..."
            
                $response = Invoke-RestMethod `
                    -Uri "$OrchestratorUrl/api/session/create" `
                    -Method POST `
                    -Body $body `
                    -ContentType "application/json" `
                    -TimeoutSec 600
            
                Update-ProgressLocal -Percent 70 -Status "Configuration du desktop (Ansible)..."
                Start-Sleep -Seconds 2
            
                Update-ProgressLocal -Percent 100 -Status "Desktop prêt"
            
                # Afficher les infos de session
                $Window.Dispatcher.Invoke([action] {
                        $txtSessionId = $Window.FindName("txtSessionId")
                        $txtVmName = $Window.FindName("txtVmName")
                        $txtVmIp = $Window.FindName("txtVmIp")
                        $txtRdpPort = $Window.FindName("txtRdpPort")
                        $panelCreation = $Window.FindName("panelCreation")
                        $panelSession = $Window.FindName("panelSession")
                        $btnCreate = $Window.FindName("btnCreate")
                        $btnConnect = $Window.FindName("btnConnect")
                        $btnClose = $Window.FindName("btnClose")
                
                        $txtSessionId.Text = $response.session_id
                        $txtVmName.Text = $response.vm_name
                        $txtVmIp.Text = $response.vm_ip
                        $txtRdpPort.Text = $response.rdp_port
                
                        $panelCreation.Visibility = "Collapsed"
                        $panelSession.Visibility = "Visible"
                
                        $btnCreate.Visibility = "Collapsed"
                        $btnConnect.Visibility = "Visible"
                        $btnConnect.IsEnabled = $true
                        $btnClose.Visibility = "Visible"
                
                        # Sauvegarder les infos de session
                        $Window.Tag = $response
                    })
            
            }
            catch {
                $Window.Dispatcher.Invoke([action] {
                        $txtStatus = $Window.FindName("txtStatus")
                        $btnCreate = $Window.FindName("btnCreate")
                        $txtStatus.Text = "Erreur: $($_.Exception.Message)"
                        $btnCreate.IsEnabled = $true
                    })
                [System.Windows.MessageBox]::Show("Erreur lors de la création du desktop:`n`n$($_.Exception.Message)", "Erreur", "OK", "Error")
            }
        }).AddArgument($Window).AddArgument($OrchestratorUrl).AddArgument($Username)
    
    $PowerShell.BeginInvoke()
}

function Connect-RDP {
    $sessionInfo = $Window.Tag
    
    if ($sessionInfo) {
        $vmIp = $sessionInfo.vm_ip
        $rdpFile = "$env:TEMP\daas-session-$($sessionInfo.session_id).rdp"
        
        $rdpContent = @"
full address:s:$vmIp`:3389
username:s:$Domain\$Username
authentication level:i:0
prompt for credentials:i:0
prompt for credentials on client:i:0
enablecredsspsupport:i:0
displayconnectionbar:i:1
autoreconnection enabled:i:1
"@
        
        $rdpContent | Out-File -FilePath $rdpFile -Encoding ASCII
        
        # Lancer RDP
        Start-Process mstsc.exe -ArgumentList $rdpFile
        
        # Changer le bouton en "RDP lancé"
        $btnConnect.Content = "RDP lancé"
        $btnConnect.IsEnabled = $false
        $btnConnect.Background = "#107C10"
        
        # Message dans le status
        $txtStatus.Text = "Connexion RDP lancée"
        $txtProgress.Text = "La fenêtre se fermera automatiquement après votre déconnexion"
    }
}

# ========================================
# Events
# ========================================

$btnCreate.Add_Click({
        Create-Desktop
    })

$btnConnect.Add_Click({
        Connect-RDP
    })

$btnClose.Add_Click({
        $Window.Close()
    })

# ========================================
# Afficher la fenêtre
# ========================================

$Window.ShowDialog() | Out-Null