
<#
    Storm Tweaks v3.1 - Panneau de controle d'optimisation Windows pour Fortnite
    Lancer en tant qu'administrateur pour que les tweaks s'appliquent.
    v3.1 : chaque tweak a maintenant une action d'annulation (Undo), appliquee
    quand le toggle est desactive, pour que "Appliquer" reflete vraiment
    l'etat affiche a l'ecran.
#>

# ---------------------------------------------------------------------------
# 0. Auto-elevation
# ---------------------------------------------------------------------------
# Vérification de la Licence via l'API Serveur
# ---------------------------------------------------------------------------
$apiUrl = "https://see-transit-achievements-permit.trycloudflare.com"

# Demande la clé à l'utilisateur
$userKey = Read-Host "Entrez votre clé de licence Storm"

# Récupération du HWID de la machine
$hwid = (Get-CimInstance Win32_ComputerSystemProduct).UUID

$body = @{
    Key  = $userKey
    HWID = $hwid
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body -ContentType "application/json"
    if (-not $response.Success) {
        [System.Windows.Forms.MessageBox]::Show("Erreur de licence : " + $response.Message, "Accès Refusé", "OK", "Error")
        exit
    }
    Write-Host "Licence validée avec succès !" -ForegroundColor Green
}
catch {
    [System.Windows.Forms.MessageBox]::Show("Impossible de contacter le serveur de licence.", "Erreur Connexion", "OK", "Error")
    exit
}
# ---------------------------------------------------------------------------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# API Windows pour forcer l'application immediate de certains reglages (ex: la
# souris) sans attendre une deconnexion/reconnexion. Ecrire dans le registre ne
# suffit pas pour ces parametres : Windows ne les relit qu'au prochain logon,
# sauf si on appelle explicitement SystemParametersInfo.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class StormNative {
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, int[] pvParam, uint fWinIni);
}
"@
$script:SPI_SETMOUSE      = 0x0004
$script:SPIF_SENDCHANGE   = 0x02

# ---------------------------------------------------------------------------
# 1. Palette de couleurs (identite conservee)
# ---------------------------------------------------------------------------
$colBg        = [System.Drawing.Color]::FromArgb(255, 9, 9, 14)
$colSidebar   = [System.Drawing.Color]::FromArgb(255, 13, 13, 19)
$colCard      = [System.Drawing.Color]::FromArgb(255, 23, 23, 33)
$colCardHover = [System.Drawing.Color]::FromArgb(255, 31, 31, 45)
$colBorder    = [System.Drawing.Color]::FromArgb(255, 42, 42, 58)
# Ombre portee des cartes : noir tres transparent, empile sur quelques
# pixels. Discret de pres, mais c'est ce qui donne la profondeur.
$colShadow    = [System.Drawing.Color]::FromArgb(70, 0, 0, 0)
# Filet clair sur l'arete haute : simule une lumiere venant du haut.
$colSheen     = [System.Drawing.Color]::FromArgb(16, 255, 255, 255)
$colPurple    = [System.Drawing.Color]::FromArgb(255, 139, 92, 246)
$colGold      = [System.Drawing.Color]::FromArgb(255, 245, 197, 24)
$colText      = [System.Drawing.Color]::FromArgb(255, 235, 235, 245)
$colSubText   = [System.Drawing.Color]::FromArgb(255, 145, 145, 160)
$colOn        = [System.Drawing.Color]::FromArgb(255, 59, 130, 246)   # bleu = active
$colOff       = [System.Drawing.Color]::FromArgb(255, 220, 38, 38)    # rouge = desactive
$colGreen     = [System.Drawing.Color]::FromArgb(255, 60, 210, 140)
$colTeal      = [System.Drawing.Color]::FromArgb(255, 20, 60, 70)
$colGoldHover   = [System.Drawing.Color]::FromArgb(255, 250, 210, 70)
$colPurpleHover = [System.Drawing.Color]::FromArgb(255, 158, 118, 250)
$colBolt        = [System.Drawing.Color]::FromArgb(255, 255, 214, 10)   # jaune vif dedie a l'eclair du logo
# Texte clair lisible sur le fond sarcelle du bandeau de recommandations
$colOnTeal      = [System.Drawing.Color]::FromArgb(255, 200, 228, 238)


function Get-AppFont([string]$weight, $size) {
    $style = if ($weight -eq "Regular") {
        [System.Drawing.FontStyle]::Regular
    } else {
        [System.Drawing.FontStyle]::Bold
    }

    return New-Object System.Drawing.Font("Segoe UI", $size, $style)
}

$fontH2     = Get-AppFont "SemiBold" 12
$fontSub    = Get-AppFont "Regular" 9.5
$fontBtn    = Get-AppFont "SemiBold" 10
$fontDesc   = Get-AppFont "Regular" 8.5
$fontToggle = Get-AppFont "SemiBold" 8


$fontLogo   = Get-AppFont "Bold" 15
$fontH1     = Get-AppFont "Bold" 22
$fontH2     = Get-AppFont "SemiBold" 12.5
$fontSub    = Get-AppFont "Regular" 9.5
$fontBtn    = Get-AppFont "SemiBold" 10
$fontDesc   = Get-AppFont "Regular" 8.5
$fontToggle = Get-AppFont "SemiBold" 8
$fontLog    = New-Object System.Drawing.Font("Cascadia Mono", 8.5)
if ($fontLog.Name -ne "Cascadia Mono") { $fontLog = New-Object System.Drawing.Font("Consolas", 8.5) }
# Segoe MDL2 Assets et Segoe UI restent necessaires pour les glyphes d'icones
# (fleche, corbeille, roue dentee, eclair) : Poppins ne contient pas ces symboles.
$fontIcon   = New-Object System.Drawing.Font("Segoe MDL2 Assets", 15)
$fontIconLg = New-Object System.Drawing.Font("Segoe MDL2 Assets", 22)

function Enable-DoubleBuffer($ctrl) {
    # Evite le scintillement quand on redessine (survol, changement d'etat)
    $prop = $ctrl.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
    if ($prop) { $prop.SetValue($ctrl, $true, $null) }
}

# Lit une valeur de registre et renvoie $null si elle est absente (au lieu de
# planter), pour pouvoir capturer fidelement "cette cle n'existait pas".
# ---------------------------------------------------------------------------
# Identite de version et source des mises a jour
# ---------------------------------------------------------------------------
# A CHANGER A CHAQUE PUBLICATION : $appVersion doit correspondre au champ
# "version" du manifeste distant, sinon l'application se croira perpetuellement
# a jour ou perpetuellement en retard.
# $updateManifestUrl doit pointer vers un fichier JSON accessible publiquement
# (voir le format attendu dans Get-UpdateManifest ci-dessous).
$script:appVersion = "1.0.0"
$script:updateManifestUrl = "https://see-transit-achievements-permit.trycloudflare.com"

# Compare deux versions "1.4.10" facon numerique : une comparaison de chaines
# dirait a tort que 1.4.9 est plus recent que 1.4.10.
function Compare-AppVersion([string]$a, [string]$b) {
    $pa = @($a -replace '[^\d\.]', '' -split '\.' | ForEach-Object { [int]("0$_") })
    $pb = @($b -replace '[^\d\.]', '' -split '\.' | ForEach-Object { [int]("0$_") })
    $n = [Math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $x = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }
        $y = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($x -gt $y) { return 1 }
        if ($x -lt $y) { return -1 }
    }
    return 0
}

function Format-Bytes([double]$b) {
    if ($b -ge 1GB) { return "$([math]::Round($b / 1GB, 2)) GB" }
    if ($b -ge 1MB) { return "$([math]::Round($b / 1MB, 2)) MB" }
    if ($b -ge 1KB) { return "$([math]::Round($b / 1KB, 1)) KB" }
    return "$([int]$b) B"
}

function Get-RegValueOrNull([string]$path, [string]$name) {
    $v = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    if ($null -eq $v) { return $null }
    return $v.$name
}

# Ecrit une valeur de registre, ou SUPPRIME la propriete si $value est $null -
# utilise pour restaurer exactement un etat capture par un point de sauvegarde
# (si la valeur n'existait pas avant, elle ne doit pas exister apres restore).
function Set-RegValueOrRemove([string]$path, [string]$name, $value, [string]$type = "DWord") {
    if ($null -eq $value) {
        Remove-ItemProperty -Path $path -Name $name -Force -ErrorAction SilentlyContinue
        return
    }
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
}

function New-RoundedPath($w, $h, $radius) {
    $d = [Math]::Min($radius * 2, [Math]::Min($w, $h))
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc(0, 0, $d, $d, 180, 90)
    $path.AddArc($w - $d, 0, $d, $d, 270, 90)
    $path.AddArc($w - $d, $h - $d, $d, $d, 0, 90)
    $path.AddArc(0, $h - $d, $d, $d, 90, 90)
    $path.CloseAllFigures()
    return $path
}

# Contour d'un eclair dessine a la main (polygone), pour ne plus dependre du
# rendu de l'emoji Unicode (couleurs fixes selon Windows, pas personnalisables).
function New-BoltPath($x, $y, $w, $h) {
    $pts = @(
        (New-Object System.Drawing.PointF(($x + 0.60*$w), ($y + 0.00*$h))),
        (New-Object System.Drawing.PointF(($x + 0.12*$w), ($y + 0.58*$h))),
        (New-Object System.Drawing.PointF(($x + 0.44*$w), ($y + 0.58*$h))),
        (New-Object System.Drawing.PointF(($x + 0.34*$w), ($y + 1.00*$h))),
        (New-Object System.Drawing.PointF(($x + 0.88*$w), ($y + 0.38*$h))),
        (New-Object System.Drawing.PointF(($x + 0.54*$w), ($y + 0.38*$h)))
    )
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddPolygon($pts)
    return $path
}

# Dessine un badge arrondi avec un eclair vectoriel dedans (logo). $fillBox =
# couleur de fond du badge, $boltBox = couleur de l'eclair. Mutables comme
# Add-SmoothRounded : changer .Color puis appeler .Invalidate() pour redessiner.
function Add-BoltBadge($ctrl, [int]$radius, [hashtable]$fillBox, [hashtable]$boltBox) {
    Enable-DoubleBuffer $ctrl
    $ctrl.Add_Paint({
        param($s, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $bgPath = New-RoundedPath $s.Width $s.Height $radius
        $bgBrush = New-Object System.Drawing.SolidBrush($fillBox.Color)
        $e.Graphics.FillPath($bgBrush, $bgPath)

        $bw = $s.Width * 0.46
        $bh = $s.Height * 0.62
        $bx = ($s.Width - $bw) / 2
        $by = ($s.Height - $bh) / 2
        $boltPath = New-BoltPath $bx $by $bw $bh
        $boltBrush = New-Object System.Drawing.SolidBrush($boltBox.Color)
        $e.Graphics.FillPath($boltBrush, $boltPath)
    }.GetNewClosure())
}

# Dessine une icone vectorielle simple (pas de dependance a une police) dans un
# badge circulaire semi-transparent de la couleur d'accent donnee. $iconType
# choisit la forme : bolt, chip, network, shield, display, mouse, gear, bell.
function Add-TweakIcon($ctrl, [string]$iconType, [System.Drawing.Color]$accentColor) {
    Enable-DoubleBuffer $ctrl
    $ctrl.Add_Paint({
        param($s, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

        $bgColor = [System.Drawing.Color]::FromArgb(40, $accentColor.R, $accentColor.G, $accentColor.B)
        $bgBrush = New-Object System.Drawing.SolidBrush($bgColor)
        $e.Graphics.FillEllipse($bgBrush, 0, 0, $s.Width, $s.Height)

        $pen = New-Object System.Drawing.Pen($accentColor, 2)
        $brush = New-Object System.Drawing.SolidBrush($accentColor)
        $cx = $s.Width / 2.0
        $cy = $s.Height / 2.0
        $r = $s.Width * 0.26

        switch ($iconType) {
            "bolt" {
                $bw = $s.Width * 0.32
                $bh = $s.Height * 0.48
                $bx = $cx - $bw / 2
                $by = $cy - $bh / 2
                $e.Graphics.FillPath($brush, (New-BoltPath $bx $by $bw $bh))
            }
            "chip" {
                $size = $s.Width * 0.36
                $x = $cx - $size / 2
                $y = $cy - $size / 2
                $e.Graphics.FillRectangle($brush, $x, $y, $size, $size)
                for ($i = 0; $i -lt 3; $i++) {
                    $py = $y + 4 + ($i * ($size - 8) / 2)
                    $e.Graphics.FillRectangle($brush, ($x - 5), $py, 4, 3)
                    $e.Graphics.FillRectangle($brush, ($x + $size + 1), $py, 4, 3)
                }
            }
            "network" {
                $e.Graphics.DrawEllipse($pen, ($cx - $r), ($cy - $r), ($r * 2), ($r * 2))
                $e.Graphics.DrawLine($pen, ($cx - $r), $cy, ($cx + $r), $cy)
                $e.Graphics.DrawEllipse($pen, ($cx - $r * 0.5), ($cy - $r), $r, ($r * 2))
            }
            "shield" {
                $w = $s.Width * 0.3
                $h = $s.Height * 0.36
                $pts = @(
                    (New-Object System.Drawing.PointF($cx, ($cy - $h))),
                    (New-Object System.Drawing.PointF(($cx + $w), ($cy - $h * 0.45))),
                    (New-Object System.Drawing.PointF(($cx + $w), ($cy + $h * 0.35))),
                    (New-Object System.Drawing.PointF($cx, ($cy + $h))),
                    (New-Object System.Drawing.PointF(($cx - $w), ($cy + $h * 0.35))),
                    (New-Object System.Drawing.PointF(($cx - $w), ($cy - $h * 0.45)))
                )
                $e.Graphics.FillPolygon($brush, $pts)
            }
            "display" {
                $w = $s.Width * 0.48
                $h = $s.Height * 0.3
                $e.Graphics.FillRectangle($brush, ($cx - $w / 2), ($cy - $h / 2 - 3), $w, $h)
                $e.Graphics.FillRectangle($brush, ($cx - $w * 0.14), ($cy + $h / 2 - 2), ($w * 0.28), 4)
            }
            "mouse" {
                $w = $s.Width * 0.26
                $h = $s.Height * 0.44
                $path = New-RoundedPath $w $h ($w / 2)
                $path.Transform((New-Object System.Drawing.Drawing2D.Matrix -ArgumentList 1,0,0,1,($cx - $w / 2),($cy - $h / 2)))
                $e.Graphics.FillPath($brush, $path)
                $e.Graphics.DrawLine($pen, $cx, ($cy - $h / 2 + 3), $cx, $cy)
            }
            "gear" {
                $e.Graphics.FillEllipse($brush, ($cx - $r), ($cy - $r), ($r * 2), ($r * 2))
                for ($i = 0; $i -lt 6; $i++) {
                    $angle = $i * 60 * [Math]::PI / 180
                    $tx = $cx + [Math]::Cos($angle) * $r * 1.35
                    $ty = $cy + [Math]::Sin($angle) * $r * 1.35
                    $e.Graphics.FillEllipse($brush, ($tx - 2.5), ($ty - 2.5), 5, 5)
                }
            }
            "bell" {
                $w = $s.Width * 0.3
                $h = $s.Height * 0.34
                $pts = @(
                    (New-Object System.Drawing.PointF(($cx - $w / 2), ($cy + $h / 2))),
                    (New-Object System.Drawing.PointF(($cx - $w / 2.6), ($cy - $h / 2))),
                    (New-Object System.Drawing.PointF(($cx + $w / 2.6), ($cy - $h / 2))),
                    (New-Object System.Drawing.PointF(($cx + $w / 2), ($cy + $h / 2)))
                )
                $e.Graphics.FillPolygon($brush, $pts)
                $e.Graphics.FillEllipse($brush, ($cx - 3), ($cy + $h / 2 - 1), 6, 6)
            }
            default {
                $e.Graphics.FillEllipse($brush, ($cx - $r), ($cy - $r), ($r * 2), ($r * 2))
            }
        }
    }.GetNewClosure())
}

# Dessine un rectangle arrondi anti-aliase en Paint (lisse, sans crenelage) au lieu
# de decouper une Region (qui produit des bords en escalier). $fillBox / $textBox /
# $borderBox sont des hashtables @{ Color = ... } mutables : on change .Color puis on
# appelle $ctrl.Invalidate() pour redessiner (ex: survol, etat actif/inactif).
function Add-SmoothRounded($ctrl, [int]$radius, [hashtable]$fillBox, [string]$text, $font, [hashtable]$textBox, [hashtable]$borderBox) {
    Enable-DoubleBuffer $ctrl
    $ctrl.Add_Paint({
        param($s, $e)
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

        # L'ombre est dessinee DANS le controle : la forme est donc raccourcie
        # de quelques pixels en bas. Aucune position n'a besoin de bouger, et
        # les elements internes gardent exactement leurs coordonnees.
        $shadowDepth = if ($s.Height -ge 60) { 3 } elseif ($s.Height -ge 30) { 2 } else { 0 }
        $w = $s.Width
        $h = $s.Height - $shadowDepth

        # Rayon adouci proportionnellement, borne par la taille du controle
        # pour que les petites pastilles restent parfaitement rondes.
        $r = [int][Math]::Min([Math]::Round($radius * 1.35), [Math]::Min($w, $h) / 2)
        if ($r -lt 1) { $r = 1 }

        for ($i = $shadowDepth; $i -ge 1; $i--) {
            $sp = New-RoundedPath $w $h $r
            $st = $g.Save()
            $g.TranslateTransform(0, $i)
            $alpha = [int](14 * ($shadowDepth - $i + 1))
            $sb = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($alpha, 0, 0, 0))
            $g.FillPath($sb, $sp)
            $sb.Dispose()
            $g.Restore($st)
            $sp.Dispose()
        }

        $path = New-RoundedPath $w $h $r
        $brush = New-Object System.Drawing.SolidBrush($fillBox.Color)
        $g.FillPath($brush, $path)
        $brush.Dispose()

        # Filet lumineux sur l'arete superieure : donne le relief des
        # interfaces Windows 11 sans changer la couleur de la carte.
        if ($h -ge 24) {
            $sheen = New-Object System.Drawing.Pen($colSheen, 1)
            $g.DrawArc($sheen, 1, 1, ($r * 2), ($r * 2), 180, 90)
            $g.DrawLine($sheen, ($r + 1), 1, ($w - $r - 1), 1)
            $g.DrawArc($sheen, ($w - $r * 2 - 1), 1, ($r * 2), ($r * 2), 270, 90)
            $sheen.Dispose()
        }

        if ($borderBox) {
            $pen = New-Object System.Drawing.Pen($borderBox.Color, 1)
            $g.DrawPath($pen, $path)
            $pen.Dispose()
        }
        $path.Dispose()

        if ($text) {
            $sf = New-Object System.Drawing.StringFormat
            $sf.Alignment = [System.Drawing.StringAlignment]::Center
            $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
            $tb = New-Object System.Drawing.SolidBrush($textBox.Color)
            $rect = New-Object System.Drawing.RectangleF(0, 0, $w, $h)
            $g.DrawString($text, $font, $tb, $rect, $sf)
            $tb.Dispose()
        }
    }.GetNewClosure())
}

# ---------------------------------------------------------------------------
# 2. Fenetre principale
# ---------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
# En dessous de la normale : quand le CPU est charge, Windows donne la main
# au jeu avant Storm Tweaks. L'interface reste parfaitement reactive, elle
# ne fait quasiment rien la plupart du temps.
try {
    [System.Diagnostics.Process]::GetCurrentProcess().PriorityClass =
        [System.Diagnostics.ProcessPriorityClass]::BelowNormal
} catch {}

$form.Text = "Storm Tweaks"
$form.Size = New-Object System.Drawing.Size(1000, 880)
$form.StartPosition = "CenterScreen"
$form.BackColor = $colBg
$form.FormBorderStyle = "FixedSingle"
$form.MaximizeBox = $false

# ---------------------------------------------------------------------------
# 3. Sidebar de navigation
# ---------------------------------------------------------------------------
$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Size = New-Object System.Drawing.Size(84, 880)
$sidebar.Location = New-Object System.Drawing.Point(0, 0)
$sidebar.BackColor = $colSidebar
$form.Controls.Add($sidebar)

$sbLogoBadge = New-Object System.Windows.Forms.Panel
$sbLogoBadge.Size = New-Object System.Drawing.Size(36, 36)
$sbLogoBadge.Location = New-Object System.Drawing.Point(18, 16)
$sbLogoBadge.BackColor = $colSidebar
$sidebar.Controls.Add($sbLogoBadge)
$sbLogoFill = @{ Color = $colPurple }
$sbLogoText = @{ Color = $colBolt }
Add-BoltBadge $sbLogoBadge 9 $sbLogoFill $sbLogoText

$navButtons = @{}
$pages = @{}

function New-NavButton($key, $iconCode, $label, $y) {
    # Barre d'indication verticale (visible seulement sur la page active)
    $indicator = New-Object System.Windows.Forms.Panel
    $indicator.Size = New-Object System.Drawing.Size(4, 26)
    $indicator.Location = New-Object System.Drawing.Point(0, ($y + 9))
    $indicator.BackColor = $colSidebar
    $sidebar.Controls.Add($indicator)
    # Pastille arrondie plutot qu'un rectangle : marqueur de page active
    # nettement plus lisible.
    $indFill = @{ Color = $colSidebar }
    Add-SmoothRounded $indicator 2 $indFill

    # "Chip" arrondi contenant l'icone, dessine en Paint (lisse, pas de crenelage)
    $btn = New-Object System.Windows.Forms.Panel
    $btn.Size = New-Object System.Drawing.Size(52, 44)
    $btn.Location = New-Object System.Drawing.Point(16, $y)
    $btn.BackColor = $colSidebar
    $btn.Cursor = "Hand"
    $btn.Tag = $key

    $fillBox = @{ Color = $colSidebar }
    $textBox = @{ Color = $colSubText }
    Add-SmoothRounded $btn 11 $fillBox ([string][char]$iconCode) $fontIcon $textBox

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = $label
    $lbl.Font = Get-AppFont "Regular" 7
    $lbl.ForeColor = $colSubText
    $lbl.Size = New-Object System.Drawing.Size(84, 14)
    $lbl.TextAlign = "MiddleCenter"
    $lbl.Location = New-Object System.Drawing.Point(0, ($y + 47))
    $sidebar.Controls.Add($lbl)

    $btn.Add_MouseEnter({
        if ($this.Tag -ne (Get-CurrentPageKey)) {
            $fillBox.Color = $colCardHover
            $textBox.Color = $colText
            $this.Invalidate()
        }
    }.GetNewClosure())
    $btn.Add_MouseLeave({
        if ($this.Tag -ne (Get-CurrentPageKey)) {
            $fillBox.Color = $colSidebar
            $textBox.Color = $colSubText
            $this.Invalidate()
        }
    }.GetNewClosure())
    $btn.Add_Click({ Show-Page $this.Tag }.GetNewClosure())

    $sidebar.Controls.Add($btn)
    $btn.BringToFront()
    $navButtons[$key] = @{ Button = $btn; Label = $lbl; Indicator = $indicator; Fill = $fillBox; TextColor = $textBox; IndFill = $indFill }
    return $btn
}

$script:currentPage = "home"

New-NavButton "home"    0xE80F "Home"    76  | Out-Null
New-NavButton "monitor" 0xE9D9 "Monitor" 152 | Out-Null
New-NavButton "clean"   0xE74D "Clean"   228 | Out-Null
New-NavButton "tweaks"  0xE90F "Tweaks"  304 | Out-Null
New-NavButton "profiles" 0xE9E9 "Profiles" 380 | Out-Null
New-NavButton "startup"  0xE7E8 "Startup"  456 | Out-Null

$settingsBtn = New-NavButton "settings" 0xE713 "Settings" 800

# ---------------------------------------------------------------------------
# 4. Zone de contenu (a droite de la sidebar)
# ---------------------------------------------------------------------------
$pageContainer = New-Object System.Windows.Forms.Panel
$pageContainer.Location = New-Object System.Drawing.Point(84, 0)
$pageContainer.Size = New-Object System.Drawing.Size(916, 700)
$pageContainer.BackColor = $colBg
$form.Controls.Add($pageContainer)

# ---- Zone de log commune (bas de fenetre, visible sur toutes les pages) --
$logBox = New-Object System.Windows.Forms.TextBox
$logShell = New-Object System.Windows.Forms.Panel
$logShell.Location = New-Object System.Drawing.Point(104, 716)
$logShell.Size = New-Object System.Drawing.Size(888, 132)
$logShell.BackColor = $colBg
$form.Controls.Add($logShell)
$logShellFill = @{ Color = $colCard }
$logShellBorder = @{ Color = $colBorder }
Add-SmoothRounded $logShell 12 $logShellFill "" $null $null $logShellBorder
# Show-Page est defini plus haut : il accede a l'ecrin via cette reference.
$script:logShellRef = $logShell

$logBox.Location = New-Object System.Drawing.Point(120, 728)
$logBox.Size = New-Object System.Drawing.Size(856, 108)
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.BackColor = $colCard
$logBox.ForeColor = $colGreen
$logBox.Font = $fontLog
$logBox.BorderStyle = "None"
$form.Controls.Add($logBox)
$logBox.BringToFront()

function Write-Log($msg) {
    $timestamp = Get-Date -Format "HH:mm:ss"
    $logBox.AppendText("[$timestamp] $msg`r`n")
    $logBox.SelectionStart = $logBox.Text.Length
    $logBox.ScrollToCaret()
}

# ---------------------------------------------------------------------------
# 5. Fonction de navigation
# ---------------------------------------------------------------------------
function Get-CurrentPageKey { return $script:currentPage }
function Get-UpdState        { return $script:upd }
function Get-StartupCfgRef   { return $script:startupCfg }
function Get-AppVersionText  { return $script:appVersion }
function Get-SysProfileRef   { return $script:sysProfile }

function Show-Page($key) {
    $script:currentPage = $key
    foreach ($k in $pages.Keys) { $pages[$k].Visible = ($k -eq $key) }

    # La page System Monitor occupe toute la zone : pas de console de logs.
    $logBox.Visible = ($key -ne "monitor")
    if ($null -ne $script:logShellRef) { $script:logShellRef.Visible = ($key -ne "monitor") }

    # Analyse automatique a la premiere ouverture du Cleaner. Une seule fois :
    # relancer un parcours complet du disque a chaque passage sur la page
    # serait penible, le bouton Refresh est la pour ca.
    if ($key -eq "clean" -and -not $script:cleanScanned) {
        $script:cleanScanned = $true
        Start-CleanScan
    }

    # Les tweaks individuels peuvent avoir change l'etat depuis la derniere
    # visite : on recalcule a chaque affichage plutot que de faire confiance
    # a un souvenir.
    if ($key -eq "profiles" -and (Get-Command Update-ActiveProfile -ErrorAction SilentlyContinue)) {
        Update-ActiveProfile
    }

    # Le monitoring ne tourne que lorsque la page est affichee, pour ne rien
    # consommer en arriere-plan le reste du temps.
    if ($null -ne $script:mon) {
        if ($key -eq "monitor") { Start-MonitorWorker }
        if (Get-Command Update-MonitorActive -ErrorAction SilentlyContinue) {
            Update-MonitorActive
        } else {
            $script:mon.Active = ($key -eq "monitor")
        }
    }
    foreach ($k in $navButtons.Keys) {
        $nb = $navButtons[$k]
        if ($k -eq $key) {
            $nb.Fill.Color = $colCardHover
            $nb.TextColor.Color = $colPurple
            $nb.IndFill.Color = $colPurple
            $nb.Label.ForeColor = $colText
        } else {
            $nb.Fill.Color = $colSidebar
            $nb.TextColor.Color = $colSubText
            $nb.IndFill.Color = $colSidebar
            $nb.Label.ForeColor = $colSubText
        }
        $nb.Button.Invalidate()
        $nb.Indicator.Invalidate()
    }

    # Transition : la page monte de 10 px en 5 images (~50 ms). Assez pour
    # que le changement se sente, trop court pour gener la navigation.
    $p = $pages[$key]
    if ($null -ne $p) {
        for ($i = 5; $i -ge 1; $i--) {
            $p.Top = [int](2 * $i)
            $p.Refresh()
            Start-Sleep -Milliseconds 8
        }
        $p.Top = 0
    }
}

# ===========================================================================
# PAGE : ACCUEIL
# ===========================================================================
$pageHome = New-Object System.Windows.Forms.Panel
$pageHome.Location = New-Object System.Drawing.Point(0, 0)
$pageHome.Size = New-Object System.Drawing.Size(916, 700)
$pageHome.BackColor = $colBg
$pageContainer.Controls.Add($pageHome)
$pages["home"] = $pageHome

# Banniere avec degrade personnalise (violet -> sarcelle)
$banner = New-Object System.Windows.Forms.Panel
$banner.Location = New-Object System.Drawing.Point(24, 24)
$banner.Size = New-Object System.Drawing.Size(868, 150)
$banner.BackColor = $colBg
$pageHome.Controls.Add($banner)
Enable-DoubleBuffer $banner
$banner.Add_Paint({
    param($s, $e)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $path = New-RoundedPath $s.Width $s.Height 16
    $rect = New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $colOn, $colPurple, 0)
    $e.Graphics.FillPath($brush, $path)
})

# Badge violet avec eclair jaune vif, reproduit du logo de reference
$badgeBox = New-Object System.Windows.Forms.Panel
$badgeBox.Size = New-Object System.Drawing.Size(44, 44)
$badgeBox.Location = New-Object System.Drawing.Point(24, 24)
$badgeBox.BackColor = [System.Drawing.Color]::Transparent
$banner.Controls.Add($badgeBox)
$badgeFill = @{ Color = $colPurple }
$badgeTextColor = @{ Color = $colBolt }
Add-BoltBadge $badgeBox 10 $badgeFill $badgeTextColor

# "Storm" (blanc) + "Tweaks" (dore), colles l'un a l'autre comme le logo de reference
$bannerStorm = New-Object System.Windows.Forms.Label
$bannerStorm.Text = "Storm "
$bannerStorm.Font = $fontH1
$bannerStorm.ForeColor = [System.Drawing.Color]::White
$bannerStorm.BackColor = [System.Drawing.Color]::Transparent
$bannerStorm.AutoSize = $true
$bannerStorm.Location = New-Object System.Drawing.Point(80, 27)
$banner.Controls.Add($bannerStorm)

$bannerTweaksWord = New-Object System.Windows.Forms.Label
$bannerTweaksWord.Text = "Tweaks"
$bannerTweaksWord.Font = $fontH1
$bannerTweaksWord.ForeColor = $colGold
$bannerTweaksWord.BackColor = [System.Drawing.Color]::Transparent
$bannerTweaksWord.AutoSize = $true
$bannerTweaksWord.Location = New-Object System.Drawing.Point(($bannerStorm.Right), 27)
$banner.Controls.Add($bannerTweaksWord)

$bannerSub = New-Object System.Windows.Forms.Label
$bannerSub.Text = "Optimize your PC and get the best performance in Fortnite"
$bannerSub.Font = $fontSub
$bannerSub.ForeColor = [System.Drawing.Color]::FromArgb(235, 255, 255, 255)
$bannerSub.BackColor = [System.Drawing.Color]::Transparent
$bannerSub.AutoSize = $true
$bannerSub.Location = New-Object System.Drawing.Point(24, 88)
$banner.Controls.Add($bannerSub)

$bannerTag = New-Object System.Windows.Forms.Label
$bannerTag.Text = "PERFORMANCE EDITION"
$bannerTag.Font = Get-AppFont "Bold" 7.5
$bannerTag.ForeColor = $colGold
$bannerTag.BackColor = [System.Drawing.Color]::Transparent
$bannerTag.AutoSize = $true
$banner.Controls.Add($bannerTag)
$bannerTag.Location = New-Object System.Drawing.Point(($banner.Width - $bannerTag.Width - 20), 18)

# Cartes d'acces rapide
function New-QuickCard($x, $iconCode, $title, $desc, $targetPage) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point($x, 194)
    $card.Size = New-Object System.Drawing.Size(278, 96)
    $card.BackColor = $colBg
    $card.Cursor = "Hand"
    $cardFill = @{ Color = $colCard }
    Add-SmoothRounded $card 10 $cardFill

    $icon = New-Object System.Windows.Forms.Label
    $icon.Text = [string][char]$iconCode
    $icon.Font = $fontIconLg
    $icon.ForeColor = $colPurple
    $icon.BackColor = [System.Drawing.Color]::Transparent
    $icon.Size = New-Object System.Drawing.Size(40, 40)
    $icon.TextAlign = "MiddleCenter"
    $icon.Location = New-Object System.Drawing.Point(18, 16)
    $card.Controls.Add($icon)

    $t = New-Object System.Windows.Forms.Label
    $t.Text = $title
    $t.Font = $fontH2
    $t.ForeColor = $colText
$t.BackColor = [System.Drawing.Color]::Transparent
    $t.AutoSize = $true
    $t.Location = New-Object System.Drawing.Point(68, 20)
    $card.Controls.Add($t)

    $d = New-Object System.Windows.Forms.Label
    $d.Text = $desc
    $d.Font = $fontDesc
    $d.ForeColor = $colSubText
$d.BackColor = [System.Drawing.Color]::Transparent
    $d.AutoSize = $true
    $d.Location = New-Object System.Drawing.Point(68, 44)
    $card.Controls.Add($d)

    $clickHandler = { Show-Page $targetPage }.GetNewClosure()
    $card.Add_Click($clickHandler)
    foreach ($c in $card.Controls) { $c.Add_Click($clickHandler) }
    $card.Add_MouseEnter({ $cardFill.Color = $colCardHover; $card.Invalidate() }.GetNewClosure())
    $card.Add_MouseLeave({ $cardFill.Color = $colCard; $card.Invalidate() }.GetNewClosure())

    $pageHome.Controls.Add($card)
}

New-QuickCard 24  0xE74D "Clean"             "Temp files, cache, recycle bin"      "clean"
New-QuickCard 318 0xE90F "Performance Tweaks" "GPU, network, latency, priority"     "tweaks"
New-QuickCard 612 0xE713 "Settings"          "Restore default settings"             "settings"

# Bloc informations systeme
$sysCard = New-Object System.Windows.Forms.Panel
$sysCard.Location = New-Object System.Drawing.Point(24, 310)
$sysCard.Size = New-Object System.Drawing.Size(868, 130)
$sysCard.BackColor = $colBg
$pageHome.Controls.Add($sysCard)
$sysCardFill = @{ Color = $colCard }
Add-SmoothRounded $sysCard 10 $sysCardFill

$sysTitle = New-Object System.Windows.Forms.Label
$sysTitle.Text = "System Information"
$sysTitle.Font = $fontH2
$sysTitle.ForeColor = $colText
$sysTitle.BackColor = [System.Drawing.Color]::Transparent
$sysTitle.AutoSize = $true
$sysTitle.Location = New-Object System.Drawing.Point(20, 14)
$sysCard.Controls.Add($sysTitle)

$sysInfoLabel = New-Object System.Windows.Forms.Label
$sysInfoLabel.Text = "Loading information..."
$sysInfoLabel.Font = $fontDesc
$sysInfoLabel.ForeColor = $colSubText
$sysInfoLabel.BackColor = [System.Drawing.Color]::Transparent
$sysInfoLabel.AutoSize = $false
$sysInfoLabel.Size = New-Object System.Drawing.Size(828, 90)
$sysInfoLabel.Location = New-Object System.Drawing.Point(20, 44)
$sysCard.Controls.Add($sysInfoLabel)

try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $ramGb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    $freeRamGb = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
    $sysInfoLabel.Text = "System: $($os.Caption)`r`nProcessor: $($cpu.Name)`r`nMemory: $freeRamGb GB free / $ramGb GB`r`nUser: $env:USERNAME"
} catch {
    $sysInfoLabel.Text = "System information unavailable."
}


# ---------------------------------------------------------------------------
# Option de demarrage : desactiver les applications d'arriere-plan Windows
# ---------------------------------------------------------------------------
# Volontairement OPT-IN, avec une demande explicite au premier lancement.
# Modifier Windows sans le dire des l'ouverture serait contraire au principe
# retenu pour la page Tweaks ("rien n'est applique avant le bouton Apply"),
# et un reglage change sans qu'on le sache est un reglage qu'on ne pense pas
# a remettre. Une fois accepte, il s'applique a chaque lancement sans rien
# redemander.
#
# Portee reelle, ecrite telle quelle dans l'interface : ce reglage Windows ne
# concerne QUE les applications du Microsoft Store (UWP). Discord, Steam,
# Spotify et les autres logiciels de bureau ne sont pas touches.
# ---------------------------------------------------------------------------
$script:startupCfgPath = Join-Path $env:LOCALAPPDATA "StormTweaks\startup.json"
$script:startupCfg = @{ AutoDisableBackgroundApps = $false; Asked = $false; AutoCheckUpdates = $true; SkippedVersion = "" }

function Save-StartupConfig {
    try {
        $dir = Split-Path $script:startupCfgPath
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        ($script:startupCfg | ConvertTo-Json) | Set-Content -Path $script:startupCfgPath -Encoding UTF8
    } catch {}
}

if (Test-Path $script:startupCfgPath) {
    try {
        $raw = Get-Content -Path $script:startupCfgPath -Raw | ConvertFrom-Json
        if ($null -ne $raw.AutoDisableBackgroundApps) { $script:startupCfg.AutoDisableBackgroundApps = [bool]$raw.AutoDisableBackgroundApps }
        if ($null -ne $raw.Asked) { $script:startupCfg.Asked = [bool]$raw.Asked }
        if ($null -ne $raw.AutoCheckUpdates) { $script:startupCfg.AutoCheckUpdates = [bool]$raw.AutoCheckUpdates }
        if ($null -ne $raw.SkippedVersion) { $script:startupCfg.SkippedVersion = [string]$raw.SkippedVersion }
    } catch {}
}

$script:bgAppsKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'

function Set-BackgroundAppsDisabled([bool]$disabled) {
    $v = if ($disabled) { 1 } else { 0 }
    Set-RegValueOrRemove $script:bgAppsKey 'GlobalUserDisabled' $v
}

# Applique tot, avant la construction de la page Tweaks, pour que
# l'interrupteur correspondant affiche l'etat reel.
if ($script:startupCfg.AutoDisableBackgroundApps) {
    try {
        Set-BackgroundAppsDisabled $true
        $script:startupApplied = $true
    } catch { $script:startupApplied = $false }
} else {
    $script:startupApplied = $false
}


# ===========================================================================
# MISES A JOUR
# ===========================================================================
# Le controle et le telechargement tournent dans un runspace d'arriere-plan
# et deposent leur avancement dans une hashtable synchronisee ; l'interface
# se contente de lire et d'afficher. C'est le meme principe que la page
# System Monitor : une connexion lente ne peut donc pas figer la fenetre.
#
# Format attendu du manifeste distant (update.json) :
#   {
#     "version":   "1.0.1",
#     "published": "2026-07-29",
#     "size":      184320,
#     "sha256":    "A1B2...",              (facultatif mais recommande)
#     "url":       "https://.../StormTweaks.ps1",
#     "notes":     ["Correction de bugs", "Nouveau module"]
#   }
# ---------------------------------------------------------------------------
$script:upd = [hashtable]::Synchronized(@{
    Phase = "idle"          # idle checking checked error downloading downloaded cancelled
    Error = $null
    ManifestUrl = $script:updateManifestUrl
    Version = $null; Published = $null; Size = 0; Sha256 = $null; Url = $null; Notes = @()
    Downloaded = 0; Total = 0; Speed = 0.0; Cancel = $false; File = $null
})
$script:updRunspace = $null
$script:updPowerShell = $null

function Start-UpdateJob($worker) {
    try {
        if ($null -ne $script:updPowerShell) {
            $script:updPowerShell.Dispose()
            $script:updPowerShell = $null
        }
        if ($null -ne $script:updRunspace) {
            $script:updRunspace.Close(); $script:updRunspace.Dispose()
            $script:updRunspace = $null
        }
        $script:updRunspace = [runspacefactory]::CreateRunspace()
        $script:updRunspace.ApartmentState = "STA"
        $script:updRunspace.ThreadOptions = "ReuseThread"
        $script:updRunspace.Open()
        $script:updRunspace.SessionStateProxy.SetVariable("upd", $script:upd)
        $script:updPowerShell = [powershell]::Create()
        $script:updPowerShell.Runspace = $script:updRunspace
        $script:updPowerShell.AddScript($worker) | Out-Null
        $script:updPowerShell.BeginInvoke() | Out-Null
        return $true
    } catch {
        $script:upd.Phase = "error"
        $script:upd.Error = $_.Exception.Message
        return $false
    }
}

$updCheckWorker = {
    try {
        # Beaucoup d'hebergeurs refusent TLS 1.0, valeur par defaut de
        # PowerShell 5.1 : sans cette ligne, la requete echoue sans raison
        # apparente.
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "StormTweaks")
        $json = $wc.DownloadString($upd.ManifestUrl)
        $wc.Dispose()
        $m = $json | ConvertFrom-Json
        $upd.Version   = [string]$m.version
        $upd.Published = [string]$m.published
        $upd.Size      = [double]$m.size
        $upd.Sha256    = [string]$m.sha256
        $upd.Url       = [string]$m.url
        $upd.Notes     = @($m.notes)
        $upd.Error     = $null
        $upd.Phase     = "checked"
    } catch {
        $upd.Error = $_.Exception.Message
        $upd.Phase = "error"
    }
}

$updDownloadWorker = {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $req = [System.Net.HttpWebRequest]::Create($upd.Url)
        $req.UserAgent = "StormTweaks"
        $req.Timeout = 30000
        $resp = $req.GetResponse()
        $len = [double]$resp.ContentLength
        if ($len -gt 0) { $upd.Total = $len } elseif ($upd.Size -gt 0) { $upd.Total = $upd.Size }

        $in = $resp.GetResponseStream()
        $out = [System.IO.File]::Create($upd.File)
        $buf = New-Object byte[] 65536
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $read = 0.0
        while ($true) {
            if ($upd.Cancel) { break }
            $n = $in.Read($buf, 0, $buf.Length)
            if ($n -le 0) { break }
            $out.Write($buf, 0, $n)
            $read += $n
            $upd.Downloaded = $read
            $sec = $sw.Elapsed.TotalSeconds
            if ($sec -gt 0.2) { $upd.Speed = $read / $sec }
        }
        $out.Close(); $in.Close(); $resp.Close()

        if ($upd.Cancel) {
            Remove-Item -LiteralPath $upd.File -Force -ErrorAction SilentlyContinue
            $upd.Phase = "cancelled"
        } else {
            $upd.Phase = "downloaded"
        }
    } catch {
        $upd.Error = $_.Exception.Message
        $upd.Phase = "error"
        try { Remove-Item -LiteralPath $upd.File -Force -ErrorAction SilentlyContinue } catch {}
    }
}

# ---- Fenetre de mise a jour ---------------------------------------------
function Show-UpdateWindow {
    $u = $script:upd

    $win = New-Object System.Windows.Forms.Form
    $win.Text = "Storm Tweaks - Update"
    $win.Size = New-Object System.Drawing.Size(540, 470)
    $win.StartPosition = "CenterParent"
    $win.FormBorderStyle = "FixedDialog"
    $win.MaximizeBox = $false
    $win.MinimizeBox = $false
    $win.BackColor = $colBg

    $h = New-Object System.Windows.Forms.Label
    $h.Text = "New version available"
    $h.Font = Get-AppFont "Bold" 14
    $h.ForeColor = $colText
    $h.AutoSize = $true
    $h.Location = New-Object System.Drawing.Point(24, 20)
    $win.Controls.Add($h)

    $info = New-Object System.Windows.Forms.Label
    $sizeTxt = if ($u.Size -gt 0) { Format-Bytes $u.Size } else { "unknown" }
    $pubTxt = if ($u.Published) { $u.Published } else { "not specified" }
    $info.Text = "Installed version : v$($script:appVersion)" + [string][char]10 +
                 "New version       : v$($u.Version)" + [string][char]10 +
                 "Published         : $pubTxt" + [string][char]10 +
                 "Download size     : $sizeTxt"
    $info.Font = $fontDesc
    $info.ForeColor = $colSubText
    $info.AutoSize = $false
    $info.Size = New-Object System.Drawing.Size(470, 76)
    $info.Location = New-Object System.Drawing.Point(24, 54)
    $win.Controls.Add($info)

    $notesTitle = New-Object System.Windows.Forms.Label
    $notesTitle.Text = "What's new"
    $notesTitle.Font = $fontH2
    $notesTitle.ForeColor = $colText
    $notesTitle.AutoSize = $true
    $notesTitle.Location = New-Object System.Drawing.Point(24, 134)
    $win.Controls.Add($notesTitle)

    $notes = New-Object System.Windows.Forms.TextBox
    $notes.Multiline = $true
    $notes.ReadOnly = $true
    $notes.ScrollBars = "Vertical"
    $notes.BorderStyle = "FixedSingle"
    $notes.BackColor = $colCard
    $notes.ForeColor = $colSubText
    $notes.Font = $fontDesc
    $notes.Size = New-Object System.Drawing.Size(470, 110)
    $notes.Location = New-Object System.Drawing.Point(24, 162)
    $lines = @()
    foreach ($n in $u.Notes) { $lines += "- $n" }
    if ($lines.Count -eq 0) { $lines = @("- No release notes provided.") }
    $notes.Text = ($lines -join "`r`n")
    $win.Controls.Add($notes)

    # ---- Zone de progression, masquee tant que rien n'est telecharge ----
    $barBack = New-Object System.Windows.Forms.Panel
    $barBack.Size = New-Object System.Drawing.Size(470, 10)
    $barBack.Location = New-Object System.Drawing.Point(24, 288)
    $barBack.BackColor = $colBg
    $barBack.Visible = $false
    $win.Controls.Add($barBack)
    $progress = @{ Value = 0.0 }
    Enable-DoubleBuffer $barBack
    $barBack.Add_Paint({
        param($s, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $e.Graphics.FillPath((New-Object System.Drawing.SolidBrush($colCard)), (New-RoundedPath $s.Width $s.Height 5))
        $w = [int]($s.Width * [Math]::Max(0.0, [Math]::Min(1.0, $progress.Value)))
        if ($w -gt 4) {
            $e.Graphics.FillPath((New-Object System.Drawing.SolidBrush($colPurple)), (New-RoundedPath $w $s.Height 5))
        }
    })

    $progLbl = New-Object System.Windows.Forms.Label
    $progLbl.Font = $fontDesc
    $progLbl.ForeColor = $colSubText
    $progLbl.AutoSize = $false
    $progLbl.Size = New-Object System.Drawing.Size(470, 32)
    $progLbl.Location = New-Object System.Drawing.Point(24, 304)
    $progLbl.Visible = $false
    $win.Controls.Add($progLbl)

    # ---- Boutons ----
    function New-UpdButton($x, $w, $text, $fillColor, $textColor) {
        $b = New-Object System.Windows.Forms.Panel
        $b.Size = New-Object System.Drawing.Size($w, 38)
        $b.Location = New-Object System.Drawing.Point($x, 380)
        $b.BackColor = $colBg
        $b.Cursor = "Hand"
        $win.Controls.Add($b)
        $f = @{ Color = $fillColor }
        $t = @{ Color = $textColor }
        $bd = @{ Color = $colBorder }
        Add-SmoothRounded $b 9 $f $text $fontBtn $t $bd
        return @{ Panel = $b; Fill = $f }
    }

    $btnGo    = New-UpdButton 24  210 "Download and install" $colPurple ([System.Drawing.Color]::White)
    $btnLater = New-UpdButton 246 120 "Later"                $colCard   $colText
    $btnSkip  = New-UpdButton 376 118 "Skip this version"    $colCard   $colSubText

    $btnGo.Panel.Add_MouseEnter({ $btnGo.Fill.Color = $colPurpleHover; $btnGo.Panel.Invalidate() }.GetNewClosure())
    $btnGo.Panel.Add_MouseLeave({ $btnGo.Fill.Color = $colPurple; $btnGo.Panel.Invalidate() }.GetNewClosure())

    $btnLater.Panel.Add_Click({ $win.Close() }.GetNewClosure())

    $btnSkip.Panel.Add_Click({
        $cfg = Get-StartupCfgRef
        $cfg.SkippedVersion = $u.Version
        Save-StartupConfig
        Write-Log "Update v$($u.Version) skipped. It will not be offered again."
        $win.Close()
    }.GetNewClosure())

    # Timer local : lit l'avancement depose par le runspace.
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 250

    $timer.Add_Tick({
        $s = $script:upd
        if ($s.Phase -eq "downloading" -or $s.Phase -eq "downloaded") {
            $tot = if ($s.Total -gt 0) { $s.Total } else { $s.Size }
            $pct = if ($tot -gt 0) { $s.Downloaded / $tot } else { 0 }
            $progress.Value = $pct
            $barBack.Invalidate()

            $etaTxt = "--"
            if ($s.Speed -gt 0 -and $tot -gt $s.Downloaded) {
                $sec = [int](($tot - $s.Downloaded) / $s.Speed)
                $etaTxt = if ($sec -ge 60) { "$([int]($sec / 60)) min $($sec % 60) s" } else { "$sec s" }
            }
            $progLbl.Text = "$([int]($pct * 100)) %  -  $(Format-Bytes $s.Downloaded) / $(Format-Bytes $tot)" + [string][char]10 +
                            "$(Format-Bytes $s.Speed)/s  -  time left: $etaTxt"
        }

        if ($s.Phase -eq "downloaded") {
            $timer.Stop()
            $progLbl.Text = "Download complete. Verifying..."
            Complete-UpdateInstall $win
        } elseif ($s.Phase -eq "cancelled") {
            $timer.Stop()
            $progLbl.Text = "Download cancelled."
            $btnGo.Panel.Visible = $true
            $btnSkip.Panel.Visible = $true
        } elseif ($s.Phase -eq "error") {
            $timer.Stop()
            $progLbl.Text = "Error: $($s.Error)"
            Write-Log "Update error: $($s.Error)"
            $btnGo.Panel.Visible = $true
            $btnSkip.Panel.Visible = $true
        }
    })

    $btnGo.Panel.Add_Click({
        $dir = Join-Path $env:LOCALAPPDATA "StormTweaks\update"
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $u2 = Get-UpdState
        $u2.File = Join-Path $dir "StormTweaks.new.ps1"
        $u2.Downloaded = 0
        $u2.Speed = 0
        $u2.Cancel = $false
        $u2.Phase = "downloading"

        $barBack.Visible = $true
        $progLbl.Visible = $true
        $btnGo.Panel.Visible = $false
        $btnSkip.Panel.Visible = $false
        # "Later" devient "Cancel" pendant le telechargement.
        $btnLater.Panel.Visible = $true

        Write-Log "Downloading update v$((Get-UpdState).Version)..."
        Start-UpdateJob $updDownloadWorker | Out-Null
        $timer.Start()
    }.GetNewClosure())

    $win.Add_FormClosing({
        $timer.Stop()
        $u3 = Get-UpdState
        if ($u3.Phase -eq "downloading") { $u3.Cancel = $true }
    }.GetNewClosure())

    $win.ShowDialog() | Out-Null
    $win.Dispose()
}

# ---- Verification puis remplacement --------------------------------------
function Complete-UpdateInstall($win) {
    $s = $script:upd
    try {
        if (-not (Test-Path $s.File)) { throw "Downloaded file not found." }

        # Verification d'integrite avant de toucher a quoi que ce soit.
        if ($s.Sha256) {
            $actual = (Get-FileHash -Path $s.File -Algorithm SHA256).Hash
            if ($actual -ne $s.Sha256.ToUpper()) {
                Remove-Item -LiteralPath $s.File -Force -ErrorAction SilentlyContinue
                throw "Checksum mismatch - the download was corrupted or altered. Update aborted."
            }
        }
        $len = (Get-Item $s.File).Length
        if ($len -lt 1024) { throw "Downloaded file looks truncated ($len bytes)." }

        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "Storm Tweaks v$($s.Version) is ready to install." +
            "`n`nThe application will close and reopen on the new version." +
            "`nThe current version is kept as StormTweaks.backup.ps1 next to it, so you can go back." +
            "`n`nInstall now?", "Install update", "YesNo", "Question")
        if ($confirm -ne "Yes") { return }

        $target = $PSCommandPath
        if ([string]::IsNullOrEmpty($target)) { throw "Cannot determine the running script path." }
        $backup = [System.IO.Path]::ChangeExtension($target, "backup.ps1")

        # Le remplacement est confie a un petit script externe : il attend la
        # fermeture complete de l'application avant d'ecrire, ce qui evite
        # d'ecraser un fichier encore ouvert.
        $tpl = @'
$ErrorActionPreference = "SilentlyContinue"
$target  = "__TARGET__"
$newFile = "__NEW__"
$backup  = "__BACKUP__"
$procId  = __PID__
$deadline = (Get-Date).AddSeconds(30)
while ((Get-Process -Id $procId -ErrorAction SilentlyContinue) -and ((Get-Date) -lt $deadline)) {
    Start-Sleep -Milliseconds 200
}
Copy-Item -LiteralPath $target -Destination $backup -Force
Copy-Item -LiteralPath $newFile -Destination $target -Force
if ((Get-Item $target).Length -lt 1024) {
    # Ecriture manifestement ratee : on remet la version precedente.
    Copy-Item -LiteralPath $backup -Destination $target -Force
}
Remove-Item -LiteralPath $newFile -Force
Start-Process powershell -ArgumentList @("-ExecutionPolicy","Bypass","-File",$target)
Start-Sleep -Seconds 2
Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force
'@
        $updaterPath = Join-Path $env:TEMP "StormTweaks-updater.ps1"
        $tpl = $tpl.Replace("__TARGET__", $target).Replace("__NEW__", $s.File).Replace("__BACKUP__", $backup).Replace("__PID__", "$PID")
        Set-Content -Path $updaterPath -Value $tpl -Encoding UTF8

        Write-Log "Installing v$($s.Version); the application will restart."
        Start-Process powershell -ArgumentList @("-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", $updaterPath)
        if ($win) { $win.Close() }
        $form.Close()
    } catch {
        Write-Log "Update install failed: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Update failed", "OK", "Error") | Out-Null
    }
}

# ---- Point d'entree commun (Home et demarrage automatique) ---------------
function Invoke-UpdateCheck([bool]$silent) {
    if ($script:updateManifestUrl -match "USER/REPO") {
        if (-not $silent) {
            [System.Windows.Forms.MessageBox]::Show(
                "No update source is configured yet." +
                "`n`nSet `$script:updateManifestUrl at the top of the script to the URL of your update.json file.",
                "Storm Tweaks", "OK", "Information") | Out-Null
        }
        return
    }

    $script:upd.Phase = "checking"
    $script:upd.Error = $null
    $updLabel.Text = "Checking for updates..."
    Start-UpdateJob $updCheckWorker | Out-Null

    $t = New-Object System.Windows.Forms.Timer
    $t.Interval = 300
    $t.Add_Tick({
        $s = Get-UpdState
        if ($s.Phase -eq "checking") { return }
        $t.Stop()
        if ($s.Phase -eq "error") {
            $updLabel.Text = "Update check failed."
            Write-Log "Update check failed: $($s.Error)"
            if (-not $silent) {
                [System.Windows.Forms.MessageBox]::Show("Update check failed:`n$($s.Error)", "Storm Tweaks", "OK", "Warning") | Out-Null
            }
            return
        }
        $ver = Get-AppVersionText
        $cmp = Compare-AppVersion $s.Version $ver
        if ($cmp -le 0) {
            $updLabel.Text = "Storm Tweaks v$ver - up to date"
            Write-Log "Up to date (v$ver)."
            if (-not $silent) {
                [System.Windows.Forms.MessageBox]::Show("Storm Tweaks v$ver is up to date.", "Storm Tweaks", "OK", "Information") | Out-Null
            }
            return
        }
        if ($silent -and (Get-StartupCfgRef).SkippedVersion -eq $s.Version) {
            $updLabel.Text = "v$($s.Version) available (skipped)"
            return
        }
        $updLabel.Text = "v$($s.Version) available"
        Write-Log "Update available: v$($s.Version)"
        Show-UpdateWindow
    }.GetNewClosure())
    $t.Start()
}

# ---- Carte "Updates" sur la page Home ------------------------------------
$updCard = New-Object System.Windows.Forms.Panel
$updCard.Location = New-Object System.Drawing.Point(24, 456)
$updCard.Size = New-Object System.Drawing.Size(868, 110)
$updCard.BackColor = $colBg
$pageHome.Controls.Add($updCard)
$updCardFill = @{ Color = $colCard }
Add-SmoothRounded $updCard 10 $updCardFill

$updTitle = New-Object System.Windows.Forms.Label
$updTitle.Text = "Updates"
$updTitle.Font = $fontH2
$updTitle.ForeColor = $colText
$updTitle.BackColor = [System.Drawing.Color]::Transparent
$updTitle.AutoSize = $true
$updTitle.Location = New-Object System.Drawing.Point(20, 14)
$updCard.Controls.Add($updTitle)

$updLabel = New-Object System.Windows.Forms.Label
$updLabel.Text = "Storm Tweaks v$($script:appVersion)"
$updLabel.Font = $fontDesc
$updLabel.ForeColor = $colSubText
$updLabel.BackColor = [System.Drawing.Color]::Transparent
$updLabel.AutoSize = $false
$updLabel.AutoEllipsis = $true
$updLabel.Size = New-Object System.Drawing.Size(540, 18)
$updLabel.TextAlign = "MiddleLeft"
$updLabel.Location = New-Object System.Drawing.Point(20, 44)
$updCard.Controls.Add($updLabel)

$updHint = New-Object System.Windows.Forms.Label
$updHint.Text = "Automatic check at launch can be turned off in Settings."
$updHint.Font = $fontDesc
$updHint.ForeColor = $colSubText
$updHint.BackColor = [System.Drawing.Color]::Transparent
$updHint.AutoSize = $false
$updHint.Size = New-Object System.Drawing.Size(540, 16)
$updHint.TextAlign = "MiddleLeft"
$updHint.Location = New-Object System.Drawing.Point(20, 68)
$updCard.Controls.Add($updHint)

$btnUpdCheck = New-Object System.Windows.Forms.Panel
$btnUpdCheck.Size = New-Object System.Drawing.Size(180, 38)
$btnUpdCheck.Location = New-Object System.Drawing.Point(668, 36)
$btnUpdCheck.BackColor = $colCard
$btnUpdCheck.Cursor = "Hand"
$updCard.Controls.Add($btnUpdCheck)
$btnUpdCheckFill = @{ Color = $colPurple }
$btnUpdCheckText = @{ Color = [System.Drawing.Color]::White }
Add-SmoothRounded $btnUpdCheck 9 $btnUpdCheckFill "Check for updates" $fontBtn $btnUpdCheckText
$btnUpdCheck.Add_MouseEnter({ $btnUpdCheckFill.Color = $colPurpleHover; $btnUpdCheck.Invalidate() }.GetNewClosure())
$btnUpdCheck.Add_MouseLeave({ $btnUpdCheckFill.Color = $colPurple; $btnUpdCheck.Invalidate() }.GetNewClosure())
$btnUpdCheck.Add_Click({ Invoke-UpdateCheck $false })

# ===========================================================================
# PAGE : SYSTEM MONITOR
# ===========================================================================
# Toute la collecte se fait dans un runspace d'arriere-plan et depose ses
# resultats dans une hashtable synchronisee. Le timer de l'interface se
# contente de LIRE cette hashtable et de redessiner : aucun appel WMI, aucun
# processus externe n'est lance sur le thread graphique, donc l'interface ne
# peut pas se figer, meme si une requete est lente.
#
# Detail important : les noms des compteurs de performance sont TRADUITS
# selon la langue de Windows. On utilise donc les classes CIM
# Win32_PerfFormattedData_*, dont les noms de proprietes ne le sont pas.
#
# Limite materielle assumee : la temperature CPU n'est pas exposee par
# Windows sur la majorite des machines (MSAcpi_ThermalZoneTemperature renvoie
# souvent "Not Supported", ou une sonde de carte mere). La temperature GPU
# n'est lisible que sur NVIDIA, via nvidia-smi. Quand la valeur n'existe pas,
# on affiche "n/a" plutot qu'un chiffre invente.
# ---------------------------------------------------------------------------
$pageMonitor = New-Object System.Windows.Forms.Panel
$pageMonitor.Location = New-Object System.Drawing.Point(0, 0)
$pageMonitor.Size = New-Object System.Drawing.Size(916, 700)
$pageMonitor.BackColor = $colBg
$pageMonitor.Visible = $false
$pageContainer.Controls.Add($pageMonitor)
$pages["monitor"] = $pageMonitor

# Etat partage entre le collecteur (arriere-plan) et l'interface.
$script:mon = [hashtable]::Synchronized(@{
    Running = $true
    Active  = $false
    Ready   = $false
    CpuName = "..."; CpuUsage = 0.0; CpuGhz = 0.0; CpuTemp = $null; Cores = 0; Threads = 0
    GpuName = "..."; GpuUsage = 0.0; GpuTemp = $null; VramUsed = 0.0; VramTotal = 0.0; GpuClock = 0.0
    RamUsed = 0.0; RamFree = 0.0; RamTotal = 0.0; RamPct = 0.0
    DiskUsed = 0.0; DiskFree = 0.0; DiskTotal = 0.0; DiskPct = 0.0
    NetDown = 0.0; NetUp = 0.0; Ping = $null; Dns = "..."
    Err = $null
})
$script:monRunspace = $null
$script:monPowerShell = $null
$script:monTimer = $null

# ---- Banniere ------------------------------------------------------------
$monBanner = New-Object System.Windows.Forms.Panel
$monBanner.Location = New-Object System.Drawing.Point(24, 20)
$monBanner.Size = New-Object System.Drawing.Size(868, 56)
$monBanner.BackColor = $colBg
$pageMonitor.Controls.Add($monBanner)
Enable-DoubleBuffer $monBanner
$monBanner.Add_Paint({
    param($s, $e)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $path = New-RoundedPath $s.Width $s.Height 12
    $rect = New-Object System.Drawing.Rectangle(0, 0, $s.Width, $s.Height)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, $colOn, $colPurple, 0)
    $e.Graphics.FillPath($brush, $path)
})

$monBannerTitle = New-Object System.Windows.Forms.Label
$monBannerTitle.Text = "System Monitor"
$monBannerTitle.Font = Get-AppFont "Bold" 15
$monBannerTitle.ForeColor = [System.Drawing.Color]::White
$monBannerTitle.BackColor = [System.Drawing.Color]::Transparent
$monBannerTitle.AutoSize = $false
$monBannerTitle.Size = New-Object System.Drawing.Size(400, 24)
$monBannerTitle.TextAlign = "MiddleLeft"
$monBannerTitle.Location = New-Object System.Drawing.Point(20, 8)
$monBanner.Controls.Add($monBannerTitle)

$monBannerSub = New-Object System.Windows.Forms.Label
$monBannerSub.Text = "Live hardware readings, refreshed every second"
$monBannerSub.Font = $fontDesc
$monBannerSub.ForeColor = [System.Drawing.Color]::FromArgb(235, 255, 255, 255)
$monBannerSub.BackColor = [System.Drawing.Color]::Transparent
$monBannerSub.AutoSize = $false
$monBannerSub.Size = New-Object System.Drawing.Size(400, 18)
$monBannerSub.TextAlign = "MiddleLeft"
$monBannerSub.Location = New-Object System.Drawing.Point(20, 32)
$monBanner.Controls.Add($monBannerSub)

# ---- Quatre cartes de tete ----------------------------------------------
# Renvoie les etiquettes a mettre a jour, pour ne jamais avoir a rechercher
# un controle par son nom pendant le rafraichissement.
function New-MonitorCard($x, $title, $iconType, $accent) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point($x, 88)
    $card.Size = New-Object System.Drawing.Size(205, 110)
    $card.BackColor = $colBg
    $cardFill = @{ Color = $colCard }
    Add-SmoothRounded $card 12 $cardFill
    $pageMonitor.Controls.Add($card)

    $badge = New-Object System.Windows.Forms.Panel
    $badge.Size = New-Object System.Drawing.Size(30, 30)
    $badge.Location = New-Object System.Drawing.Point(12, 12)
    $badge.BackColor = [System.Drawing.Color]::Transparent
    $card.Controls.Add($badge)
    Add-TweakIcon $badge $iconType $accent

    $t = New-Object System.Windows.Forms.Label
    $t.Text = $title
    $t.Font = Get-AppFont "SemiBold" 9
    $t.ForeColor = $colSubText
    $t.BackColor = [System.Drawing.Color]::Transparent
    $t.AutoSize = $false
    $t.Size = New-Object System.Drawing.Size(110, 18)
    $t.TextAlign = "MiddleLeft"
    $t.Location = New-Object System.Drawing.Point(48, 18)
    $card.Controls.Add($t)

    # Pastille d'etat : verte / orange / rouge selon les seuils.
    $dot = New-Object System.Windows.Forms.Panel
    $dot.Size = New-Object System.Drawing.Size(12, 12)
    $dot.Location = New-Object System.Drawing.Point(164, 21)
    $dot.BackColor = [System.Drawing.Color]::Transparent
    $card.Controls.Add($dot)
    $dotFill = @{ Color = $colGreen }
    Add-SmoothRounded $dot 6 $dotFill

    $val = New-Object System.Windows.Forms.Label
    $val.Text = "--"
    $val.Font = Get-AppFont "Bold" 16
    $val.ForeColor = $colText
    $val.BackColor = [System.Drawing.Color]::Transparent
    $val.AutoSize = $false
    $val.AutoEllipsis = $true
    $val.Size = New-Object System.Drawing.Size(168, 26)
    $val.TextAlign = "MiddleLeft"
    $val.Location = New-Object System.Drawing.Point(14, 44)
    $card.Controls.Add($val)

    # Ligne 1 : la valeur la plus parlante (temperature quand elle existe).
    $line1 = New-Object System.Windows.Forms.Label
    $line1.Text = ""
    $line1.Font = $fontDesc
    $line1.ForeColor = $colText
    $line1.BackColor = [System.Drawing.Color]::Transparent
    $line1.AutoSize = $false
    $line1.AutoEllipsis = $true
    $line1.Size = New-Object System.Drawing.Size(168, 15)
    $line1.TextAlign = "MiddleLeft"
    $line1.Location = New-Object System.Drawing.Point(14, 72)
    $card.Controls.Add($line1)

    $line2 = New-Object System.Windows.Forms.Label
    $line2.Text = ""
    $line2.Font = $fontDesc
    $line2.ForeColor = $colSubText
    $line2.BackColor = [System.Drawing.Color]::Transparent
    $line2.AutoSize = $false
    $line2.AutoEllipsis = $true
    $line2.Size = New-Object System.Drawing.Size(168, 15)
    $line2.TextAlign = "MiddleLeft"
    $line2.Location = New-Object System.Drawing.Point(14, 88)
    $card.Controls.Add($line2)

    $card.Add_MouseEnter({ $cardFill.Color = $colCardHover; $card.Invalidate() }.GetNewClosure())
    $card.Add_MouseLeave({ $cardFill.Color = $colCard; $card.Invalidate() }.GetNewClosure())

    return @{ Card = $card; Value = $val; Line1 = $line1; Line2 = $line2; Dot = $dot; DotFill = $dotFill }
}

$cardCpu = New-MonitorCard 24  "CPU"     "chip"    $colOn
$cardGpu = New-MonitorCard 245 "GPU"     "display" $colPurple
$cardRam = New-MonitorCard 466 "RAM"     "gear"    $colGreen
$cardNet = New-MonitorCard 687 "NETWORK" "network" $colGold

# ---- Graphique temps reel ------------------------------------------------
$script:histLen = 60
$script:histCpu = New-Object 'double[]' $script:histLen
$script:histGpu = New-Object 'double[]' $script:histLen
$script:histRam = New-Object 'double[]' $script:histLen

$graphPanel = New-Object System.Windows.Forms.Panel
$graphPanel.Location = New-Object System.Drawing.Point(24, 210)
$graphPanel.Size = New-Object System.Drawing.Size(868, 252)
$graphPanel.BackColor = $colBg
$pageMonitor.Controls.Add($graphPanel)
Enable-DoubleBuffer $graphPanel

# Trace une serie lissee (spline cardinale) sur toute la largeur utile.
function Add-GraphSeries($g, $values, $color, $x0, $y0, $w, $h) {
    $n = $values.Length
    if ($n -lt 2) { return }
    $pts = New-Object 'System.Drawing.PointF[]' $n
    for ($i = 0; $i -lt $n; $i++) {
        $v = [Math]::Max(0.0, [Math]::Min(100.0, [double]$values[$i]))
        $px = $x0 + ($w * $i / ($n - 1))
        $py = $y0 + $h - ($h * $v / 100.0)
        $pts[$i] = New-Object System.Drawing.PointF($px, $py)
    }
    $pen = New-Object System.Drawing.Pen($color, 2)
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddCurve($pts, 0.5)
    $g.DrawPath($pen, $path)
}

$graphPanel.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $bg = New-RoundedPath $s.Width $s.Height 12
    $g.FillPath((New-Object System.Drawing.SolidBrush($colCard)), $bg)

    $padL = 44; $padT = 34; $padR = 16; $padB = 26
    $w = $s.Width - $padL - $padR
    $h = $s.Height - $padT - $padB

    # Grille discrete + graduations
    $gridPen = New-Object System.Drawing.Pen($colBorder, 1)
    $lblBrush = New-Object System.Drawing.SolidBrush($colSubText)
    $lblFont = Get-AppFont "Regular" 7
    foreach ($p in @(0, 25, 50, 75, 100)) {
        $y = $padT + $h - ($h * $p / 100.0)
        $g.DrawLine($gridPen, $padL, $y, ($padL + $w), $y)
        $g.DrawString("$p%", $lblFont, $lblBrush, 8, ($y - 7))
    }

    Add-GraphSeries $g $script:histCpu $colOn     $padL $padT $w $h
    Add-GraphSeries $g $script:histGpu $colPurple $padL $padT $w $h
    Add-GraphSeries $g $script:histRam $colGreen  $padL $padT $w $h

    # Legende
    $legFont = Get-AppFont "SemiBold" 8
    $lx = $padL
    foreach ($item in @(@{N = "CPU"; C = $colOn}, @{N = "GPU"; C = $colPurple}, @{N = "RAM"; C = $colGreen})) {
        $g.FillEllipse((New-Object System.Drawing.SolidBrush($item.C)), $lx, 13, 9, 9)
        $g.DrawString($item.N, $legFont, (New-Object System.Drawing.SolidBrush($colText)), ($lx + 13), 10)
        $lx += 62
    }
    $g.DrawString("last 60 seconds", $lblFont, $lblBrush, ($s.Width - 106), 13)
})

# ---- Ligne inferieure : Disk et System Health ---------------------------
function New-WideCard($x, $title) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point($x, 478)
    $card.Size = New-Object System.Drawing.Size(426, 186)
    $card.BackColor = $colBg
    $cardFill = @{ Color = $colCard }
    Add-SmoothRounded $card 12 $cardFill
    $pageMonitor.Controls.Add($card)

    $t = New-Object System.Windows.Forms.Label
    $t.Text = $title
    $t.Font = $fontH2
    $t.ForeColor = $colText
    $t.BackColor = [System.Drawing.Color]::Transparent
    $t.AutoSize = $false
    $t.Size = New-Object System.Drawing.Size(360, 22)
    $t.TextAlign = "MiddleLeft"
    $t.Location = New-Object System.Drawing.Point(18, 12)
    $card.Controls.Add($t)

    $body = New-Object System.Windows.Forms.Label
    $body.Text = ""
    $body.Font = $fontDesc
    $body.ForeColor = $colSubText
    $body.BackColor = [System.Drawing.Color]::Transparent
    $body.AutoSize = $false
    $body.Size = New-Object System.Drawing.Size(390, 140)
    $body.TextAlign = "TopLeft"
    $body.Location = New-Object System.Drawing.Point(18, 40)
    $card.Controls.Add($body)

    $card.Add_MouseEnter({ $cardFill.Color = $colCardHover; $card.Invalidate() }.GetNewClosure())
    $card.Add_MouseLeave({ $cardFill.Color = $colCard; $card.Invalidate() }.GetNewClosure())
    return @{ Card = $card; Body = $body }
}

$cardDisk = New-WideCard 24 "Disk"
$cardHealth = New-WideCard 466 "System Health"

# ---- Seuils d'alerte -----------------------------------------------------
$script:degC = [string][char]176 + "C"

function Format-Rate($mbPerSec) {
    $v = [double]$mbPerSec
    if ($v -lt 1.0) { return "$([int]($v * 1024)) KB/s" }
    return "$([math]::Round($v, 2)) MB/s"
}

function Get-StatusColor($value, $amber, $red) {
    if ($null -eq $value) { return $colSubText }
    if ($value -ge $red) { return $colOff }
    if ($value -ge $amber) { return $colGold }
    return $colGreen
}
function Get-StatusWord($value, $amber, $red) {
    if ($null -eq $value) { return "n/a" }
    if ($value -ge $red) { return "High" }
    if ($value -ge $amber) { return "Watch" }
    return "Excellent"
}

# ---- Collecteur d'arriere-plan ------------------------------------------
$monitorWorker = {
    # Toutes les fonctions de lecture vivent ici : elles s'executent dans le
    # runspace d'arriere-plan, jamais sur le thread de l'interface.

    function Get-CpuInfo($state, $baseMhz) {
        $got = $false
        try {
            # PercentProcessorPerformance depasse 100 en turbo : c'est voulu.
            $pi = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation `
                  -Filter "Name LIKE '%_Total'" -ErrorAction Stop | Select-Object -First 1
            if ($pi) {
                # PercentIdleTime est le complement le plus fiable : certaines
                # machines laissent PercentProcessorTime a 0 en permanence.
                $idle = [double]$pi.PercentIdleTime
                if ($idle -gt 0) { $state.CpuUsage = [math]::Max(0.0, 100.0 - $idle); $got = $true }
                elseif ([double]$pi.PercentProcessorTime -gt 0) { $state.CpuUsage = [double]$pi.PercentProcessorTime; $got = $true }
                if ($baseMhz -gt 0) {
                    $state.CpuGhz = [math]::Round(($baseMhz * [double]$pi.PercentProcessorPerformance / 100.0) / 1000.0, 2)
                }
            }
        } catch {}
        if (-not $got) {
            try {
                $p = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop
                if ($p) { $state.CpuUsage = [double]$p.PercentProcessorTime }
            } catch {}
        }
        try {
            # Absent sur la majorite des machines : on laisse $null si echec.
            $z = @(Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop)
            if ($z.Count -gt 0) {
                $state.CpuTemp = [math]::Round(([double]$z[0].CurrentTemperature / 10.0) - 273.15, 0)
            }
        } catch { $state.CpuTemp = $null }
    }

    function Get-GpuInfo($state, $useNvidiaSmi) {
        if ($useNvidiaSmi) {
            try {
                $raw = & nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,clocks.current.graphics --format=csv,noheader,nounits 2>$null
                if ($raw) {
                    $f = ($raw | Select-Object -First 1).Split(",")
                    if ($f.Count -ge 5) {
                        $state.GpuUsage  = [double]$f[0].Trim()
                        $state.GpuTemp   = [double]$f[1].Trim()
                        $state.VramUsed  = [math]::Round([double]$f[2].Trim() / 1024.0, 1)
                        $state.VramTotal = [math]::Round([double]$f[3].Trim() / 1024.0, 1)
                        $state.GpuClock  = [double]$f[4].Trim()
                        return
                    }
                }
            } catch {}
        }
        # Repli universel (AMD, Intel, ou nvidia-smi indisponible) : compteurs
        # GPU de Windows 10/11. Pas de temperature disponible par cette voie.
        try {
            $eng = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine `
                   -Filter "Name LIKE '%engtype_3D%'" -ErrorAction Stop
            $sum = 0.0
            foreach ($x in $eng) { $sum += [double]$x.UtilizationPercentage }
            $state.GpuUsage = [math]::Min(100.0, [math]::Round($sum, 0))
        } catch {}
        try {
            $mem = Get-CimInstance Win32_PerfFormattedData_GPUPerformanceCounters_GPUAdapterMemory -ErrorAction Stop
            $ded = 0.0
            foreach ($x in $mem) { $ded += [double]$x.DedicatedUsage }
            $state.VramUsed = [math]::Round($ded / 1GB, 1)
        } catch {}
    }

    function Get-RamInfo($state) {
        try {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
            $total = [double]$os.TotalVisibleMemorySize / 1MB
            $free  = [double]$os.FreePhysicalMemory / 1MB
            $state.RamTotal = [math]::Round($total, 1)
            $state.RamFree  = [math]::Round($free, 1)
            $state.RamUsed  = [math]::Round($total - $free, 1)
            if ($total -gt 0) { $state.RamPct = [math]::Round((($total - $free) / $total) * 100.0, 0) }
        } catch {}
    }

    function Get-DiskInfo($state) {
        $letter = $env:SystemDrive.TrimEnd(":")
        try {
            $dr = Get-PSDrive -Name $letter -ErrorAction Stop
            $used = [double]$dr.Used
            $free = [double]$dr.Free
            $total = $used + $free
            if ($total -gt 0) {
                $state.DiskTotal = [math]::Round($total / 1GB, 1)
                $state.DiskFree  = [math]::Round($free / 1GB, 1)
                $state.DiskUsed  = [math]::Round($used / 1GB, 1)
                $state.DiskPct   = [math]::Round(($used / $total) * 100.0, 0)
                return
            }
        } catch {}
        try {
            $d = Get-CimInstance Win32_LogicalDisk -ErrorAction Stop |
                 Where-Object { $_.DeviceID -eq $env:SystemDrive } | Select-Object -First 1
            if ($d -and [double]$d.Size -gt 0) {
                $size = [double]$d.Size; $fr = [double]$d.FreeSpace
                $state.DiskTotal = [math]::Round($size / 1GB, 1)
                $state.DiskFree  = [math]::Round($fr / 1GB, 1)
                $state.DiskUsed  = [math]::Round(($size - $fr) / 1GB, 1)
                $state.DiskPct   = [math]::Round((($size - $fr) / $size) * 100.0, 0)
            }
        } catch {}
    }

    function Get-NetworkInfo($state, $withPing) {
        try {
            # Ces compteurs sont deja exprimes par seconde : aucun delta a
            # calculer nous-memes, donc pas de derive si un cycle est retarde.
            $ifs = Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface `
                   -Filter "NOT Name LIKE '%Loopback%' AND NOT Name LIKE '%isatap%'" -ErrorAction Stop
            $rx = 0.0; $tx = 0.0
            foreach ($i in $ifs) {
                $rx += [double]$i.BytesReceivedPersec
                $tx += [double]$i.BytesSentPersec
            }
            $state.NetDown = [math]::Round($rx / 1MB, 2)
            $state.NetUp   = [math]::Round($tx / 1MB, 2)
        } catch {}
        if ($withPing) {
            try {
                $p = New-Object System.Net.NetworkInformation.Ping
                $r = $p.Send("1.1.1.1", 900)
                if ($r.Status -eq "Success") { $state.Ping = [int]$r.RoundtripTime } else { $state.Ping = $null }
                $p.Dispose()
            } catch { $state.Ping = $null }
            try {
                $ad = Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
                if ($ad) {
                    $srv = (Get-DnsClientServerAddress -InterfaceIndex $ad.ifIndex -AddressFamily IPv4 -ErrorAction Stop).ServerAddresses
                    if ($srv -and $srv.Count -gt 0) { $state.Dns = ($srv -join ", ") } else { $state.Dns = "automatic" }
                }
            } catch {}
        }
    }

    # ---- Valeurs fixes, lues une seule fois ----
    $baseMhz = 0
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $mon.CpuName = $cpu.Name
        $mon.Cores   = [int]$cpu.NumberOfCores
        $mon.Threads = [int]$cpu.NumberOfLogicalProcessors
        $baseMhz     = [double]$cpu.MaxClockSpeed
    } catch {}

    $useNvidiaSmi = $false
    try {
        $gpu = Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name } | Select-Object -First 1
        if ($gpu) { $mon.GpuName = $gpu.Name }
        if ($gpu -and $gpu.Name -match "NVIDIA") {
            if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) { $useNvidiaSmi = $true }
        }
    } catch {}
    if (-not $useNvidiaSmi) {
        # VRAM totale : AdapterRAM est plafonne a 4 Go (champ 32 bits), la
        # cle de registre du pilote donne la vraie taille.
        try {
            $keys = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -ErrorAction Stop
            $best = 0.0
            foreach ($k in $keys) {
                $q = (Get-ItemProperty -Path $k.PSPath -Name "HardwareInformation.qwMemorySize" -ErrorAction SilentlyContinue)."HardwareInformation.qwMemorySize"
                if ($q -and [double]$q -gt $best) { $best = [double]$q }
            }
            if ($best -gt 0) { $mon.VramTotal = [math]::Round($best / 1GB, 1) }
        } catch {}
    }

    $tick = 0
    while ($mon.Running) {
        if (-not $mon.Active) { Start-Sleep -Milliseconds 500; continue }
        try {
            Get-CpuInfo $mon $baseMhz
            # nvidia-smi lance un processus a chaque appel : c'est de loin la
            # mesure la plus chere, donc une fois sur deux (4 s) au lieu de
            # chaque cycle.
            if (($tick % 2) -eq 0) { Get-GpuInfo $mon $useNvidiaSmi }
            Get-RamInfo $mon
            # Disque, ping et DNS changent lentement : toutes les 10 s suffit.
            Get-NetworkInfo $mon (($tick % 5) -eq 0)
            if (($tick % 5) -eq 0) { Get-DiskInfo $mon }
            $mon.Ready = $true
            $mon.Err = $null
        } catch {
            $mon.Err = $_.Exception.Message
        }
        $tick++
        Start-Sleep -Milliseconds 2000
    }
}

function Start-MonitorWorker {
    if ($null -ne $script:monRunspace) { return }
    try {
        $script:monRunspace = [runspacefactory]::CreateRunspace()
        $script:monRunspace.ApartmentState = "STA"
        $script:monRunspace.ThreadOptions = "ReuseThread"
        $script:monRunspace.Open()
        $script:monRunspace.SessionStateProxy.SetVariable("mon", $script:mon)
        $script:monPowerShell = [powershell]::Create()
        $script:monPowerShell.Runspace = $script:monRunspace
        $script:monPowerShell.AddScript($monitorWorker) | Out-Null
        $script:monPowerShell.BeginInvoke() | Out-Null
        Write-Log "System Monitor started."
    } catch {
        Write-Log "System Monitor could not start: $($_.Exception.Message)"
    }
}

# ---- Rafraichissement de l'interface (thread graphique, lecture seule) ---
function Update-Graph {
    # Decalage d'un cran vers la gauche, la nouvelle valeur entre a droite.
    for ($i = 0; $i -lt ($script:histLen - 1); $i++) {
        $script:histCpu[$i] = $script:histCpu[$i + 1]
        $script:histGpu[$i] = $script:histGpu[$i + 1]
        $script:histRam[$i] = $script:histRam[$i + 1]
    }
    $script:histCpu[$script:histLen - 1] = [double]$script:mon.CpuUsage
    $script:histGpu[$script:histLen - 1] = [double]$script:mon.GpuUsage
    $script:histRam[$script:histLen - 1] = [double]$script:mon.RamPct
    $graphPanel.Invalidate()
}

function Update-Dashboard {
    $m = $script:mon

    # --- CPU : temperature en premier, c'est l'info la plus attendue ---
    $cpuTempTxt = if ($null -ne $m.CpuTemp) { "$($m.CpuTemp)$script:degC" } else { "temp n/a" }
    $cardCpu.Value.Text = "$([int]$m.CpuUsage) %"
    $cardCpu.Line1.Text = "$cpuTempTxt  -  $($m.CpuGhz) GHz"
    $cardCpu.Line2.Text = "$($m.Cores) cores / $($m.Threads) threads"
    $cardCpu.DotFill.Color = if ($null -ne $m.CpuTemp) { Get-StatusColor $m.CpuTemp 70 85 } else { Get-StatusColor $m.CpuUsage 80 95 }
    $cardCpu.Dot.Invalidate()

    # --- GPU ---
    $gpuTempTxt = if ($null -ne $m.GpuTemp) { "$($m.GpuTemp)$script:degC" } else { "temp n/a" }
    $gpuClockTxt = if ($m.GpuClock -gt 0) { "  -  $([int]$m.GpuClock) MHz" } else { "" }
    $vramTxt = if ($m.VramTotal -gt 0) { "VRAM $($m.VramUsed) / $($m.VramTotal) GB" } else { "VRAM $($m.VramUsed) GB" }
    $cardGpu.Value.Text = "$([int]$m.GpuUsage) %"
    $cardGpu.Line1.Text = "$gpuTempTxt$gpuClockTxt"
    $cardGpu.Line2.Text = $vramTxt
    $cardGpu.DotFill.Color = if ($null -ne $m.GpuTemp) { Get-StatusColor $m.GpuTemp 75 85 } else { Get-StatusColor $m.GpuUsage 85 95 }
    $cardGpu.Dot.Invalidate()

    # --- RAM ---
    $cardRam.Value.Text = "$([int]$m.RamPct) %"
    $cardRam.Line1.Text = "$($m.RamUsed) / $($m.RamTotal) GB used"
    $cardRam.Line2.Text = "Free: $($m.RamFree) GB"
    $cardRam.DotFill.Color = Get-StatusColor $m.RamPct 70 90
    $cardRam.Dot.Invalidate()

    # --- Reseau ---
    $pingTxt = if ($null -ne $m.Ping) { "$($m.Ping) ms" } else { "n/a" }
    $cardNet.Value.Text = (Format-Rate $m.NetDown)
    $cardNet.Line1.Text = "Up $(Format-Rate $m.NetUp)  -  Ping $pingTxt"
    $cardNet.Line2.Text = "DNS: $($m.Dns)"
    $cardNet.DotFill.Color = if ($null -ne $m.Ping) { Get-StatusColor $m.Ping 60 120 } else { $colSubText }
    $cardNet.Dot.Invalidate()

    # --- Disque ---
    $cardDisk.Body.Text = "Used: $($m.DiskUsed) GB`nFree: $($m.DiskFree) GB`nTotal: $($m.DiskTotal) GB`nUsage: $([int]$m.DiskPct) %"

    # --- Sante globale, deduite des memes seuils ---
    $cpuWord = if ($null -ne $m.CpuTemp) { Get-StatusWord $m.CpuTemp 70 85 } else { Get-StatusWord $m.CpuUsage 80 95 }
    $gpuWord = if ($null -ne $m.GpuTemp) { Get-StatusWord $m.GpuTemp 75 85 } else { Get-StatusWord $m.GpuUsage 85 95 }
    $ramWord = Get-StatusWord $m.RamPct 70 90
    $netWord = if ($null -ne $m.Ping) { Get-StatusWord $m.Ping 60 120 } else { "n/a" }
    $dskWord = Get-StatusWord $m.DiskPct 80 92
    $cardHealth.Body.Text = "CPU: $cpuWord`nGPU: $gpuWord`nRAM: $ramWord ($([int]$m.RamPct) %)`nNetwork: $netWord`nDisk: $dskWord ($([int]$m.DiskPct) %)"
}

$script:formFocused = $true

# Le monitoring ne tourne que si les TROIS conditions sont reunies : page
# affichee, fenetre non reduite, fenetre au premier plan. Des qu'on bascule
# sur un jeu, la collecte s'arrete entierement.
function Update-MonitorActive {
    if ($null -eq $script:mon) { return }
    $shouldRun = ($script:currentPage -eq "monitor") -and
                 ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) -and
                 $script:formFocused
    $script:mon.Active = $shouldRun
    if ($null -ne $script:monTimer) {
        if ($shouldRun) { $script:monTimer.Start() } else { $script:monTimer.Stop() }
    }
}

$form.Add_Activated({ $script:formFocused = $true;  Update-MonitorActive })
$form.Add_Deactivate({ $script:formFocused = $false; Update-MonitorActive })
$form.Add_Resize({ Update-MonitorActive })

$script:monTimer = New-Object System.Windows.Forms.Timer
$script:monTimer.Interval = 2000
$script:monTimer.Add_Tick({
    try {
        Update-Dashboard
        Update-Graph
    } catch {
        # Un souci d'affichage ne doit jamais arreter le rafraichissement.
    }
})

# Arret propre : sans cela, le runspace survivrait a la fermeture de la fenetre.
# Demande unique au premier lancement. Posee apres l'affichage de la fenetre
# pour que l'utilisateur voie a quoi il repond.
$form.Add_Shown({
    if ($script:startupCfg.Asked) { return }
    $script:startupCfg.Asked = $true
    Save-StartupConfig
    $r = [System.Windows.Forms.MessageBox]::Show(
        "Disable Windows background apps each time Storm Tweaks starts?" +
        "`n`nThis frees the resources used by Microsoft Store apps running in the background." +
        "`n`nIt does NOT affect Discord, Steam or other desktop programs - those keep their own startup settings." +
        "`n`nYou can change this any time in Settings, and turning it off restores the Windows default.",
        "Storm Tweaks", "YesNo", "Question")
    if ($r -eq "Yes") {
        $script:startupCfg.AutoDisableBackgroundApps = $true
        Save-StartupConfig
        try {
            Set-BackgroundAppsDisabled $true
            Write-Log "Startup option enabled: background apps disabled now and at every launch."
        } catch {}
        Update-StartupToggleVisual
    } else {
        Write-Log "Startup option declined. It can be enabled later in Settings."
    }
})

# Verification automatique, apres l'affichage de la fenetre pour ne pas
# retarder son ouverture. Silencieuse : elle ne derange que si une version
# plus recente existe reellement.
$form.Add_Shown({
    if ($script:startupCfg.AutoCheckUpdates) { Invoke-UpdateCheck $true }
})

$form.Add_FormClosing({
    try {
        if ($null -ne $script:monTimer) { $script:monTimer.Stop() }
        if ($null -ne $script:updPowerShell) { $script:upd.Cancel = $true; $script:updPowerShell.Dispose() }
        if ($null -ne $script:updRunspace) { $script:updRunspace.Close(); $script:updRunspace.Dispose() }
        if ($null -ne $script:mon) { $script:mon.Running = $false; $script:mon.Active = $false }
        if ($null -ne $script:monPowerShell) { $script:monPowerShell.Dispose() }
        if ($null -ne $script:monRunspace) { $script:monRunspace.Close(); $script:monRunspace.Dispose() }
    } catch {}
})

# ===========================================================================
# PAGE : NETTOYER
# ===========================================================================
# Toute la mesure et toute la suppression tournent dans un runspace
# d'arriere-plan ; l'interface se contente de lire une hashtable synchronisee.
# Parcourir des dizaines de milliers de fichiers ne peut donc pas figer la
# fenetre.
#
# SECURITE - le principe retenu :
#   1. Les chemins sont ecrits en dur, jamais construits a partir d'une saisie.
#   2. Chaque suppression repasse malgre tout par Test-CleanPathSafe, qui
#      refuse la racine d'un disque, le profil utilisateur et tout dossier
#      personnel (Bureau, Documents, Images, Telechargements...).
#   3. On supprime le CONTENU des dossiers, jamais les dossiers eux-memes.
#   4. Un fichier verrouille est ignore, pas force.
# Le double garde-fou est volontaire : la liste en dur peut etre modifiee un
# jour par erreur, le garde-fou, lui, reste.
# ---------------------------------------------------------------------------
$pageClean = New-Object System.Windows.Forms.Panel
$pageClean.Location = New-Object System.Drawing.Point(0, 0)
$pageClean.Size = New-Object System.Drawing.Size(916, 700)
$pageClean.BackColor = $colBg
$pageClean.Visible = $false
$pageContainer.Controls.Add($pageClean)
$pages["clean"] = $pageClean

$script:cleanHistPath = Join-Path $env:LOCALAPPDATA "StormTweaks\clean-history.json"

# --- Detection materielle : on n'affiche que les caches reellement presents.
$script:cleanGpuVendors = @()
try {
    $gpuNames = (Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object { $_.Name }) -join " "
    if ($gpuNames -match "NVIDIA")       { $script:cleanGpuVendors += "NVIDIA" }
    if ($gpuNames -match "AMD|Radeon")   { $script:cleanGpuVendors += "AMD" }
    if ($gpuNames -match "Intel")        { $script:cleanGpuVendors += "Intel" }
} catch {}

# --- Catalogue des categories -------------------------------------------
# Safe = $true  : coche par defaut et retenu par Smart Clean.
# Safe = $false : jamais coche automatiquement (Prefetch ralentit les
#                 premiers demarrages tant que Windows ne l'a pas reconstruit).
function Get-CleanCategories {
    $c = @()
    $c += @{ Key = "temp"; Title = "Temporary Files"; Safe = $true
             Desc = "%TEMP%, Windows Temp"
             Paths = @("$env:TEMP", "$env:WINDIR\Temp", "$env:LOCALAPPDATA\Temp") }
    $c += @{ Key = "prefetch"; Title = "Prefetch"; Safe = $false
             Desc = "Slows the next few boots until Windows rebuilds it"
             Paths = @("$env:WINDIR\Prefetch") }
    $c += @{ Key = "dxcache"; Title = "DirectX Shader Cache"; Safe = $true
             Desc = "Clearing costs FPS until games recompile their shaders"
             Paths = @("$env:LOCALAPPDATA\D3DSCache", "$env:LOCALAPPDATA\Microsoft\DirectX Shader Cache") }

    if ($script:cleanGpuVendors -contains "NVIDIA") {
        $c += @{ Key = "nvidia"; Title = "NVIDIA Cache"; Safe = $true
                 Desc = "Clearing costs FPS until games recompile their shaders"
                 Paths = @("$env:LOCALAPPDATA\NVIDIA\DXCache", "$env:LOCALAPPDATA\NVIDIA\GLCache",
                           "$env:LOCALAPPDATA\NVIDIA Corporation\NV_Cache", "$env:APPDATA\NVIDIA\ComputeCache") }
    }
    if ($script:cleanGpuVendors -contains "AMD") {
        $c += @{ Key = "amd"; Title = "AMD Cache"; Safe = $true
                 Desc = "Clearing costs FPS until games recompile their shaders"
                 Paths = @("$env:LOCALAPPDATA\AMD\DxCache", "$env:LOCALAPPDATA\AMD\DxcCache",
                           "$env:LOCALAPPDATA\AMD\GLCache", "$env:LOCALAPPDATA\AMD\VkCache") }
    }
    if ($script:cleanGpuVendors -contains "Intel") {
        $c += @{ Key = "intel"; Title = "Intel Shader Cache"; Safe = $true
                 Desc = "Clearing costs FPS until games recompile their shaders"
                 Paths = @("$env:LOCALAPPDATA\Intel\ShaderCache") }
    }

    $c += @{ Key = "wupdate"; Title = "Windows Update Cache"; Safe = $true
             Desc = "Downloaded installers already applied"
             Paths = @("$env:WINDIR\SoftwareDistribution\Download") }
    $c += @{ Key = "store"; Title = "Microsoft Store Cache"; Safe = $true
             Desc = "Store local cache"
             Paths = @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache") }
    $c += @{ Key = "thumbs"; Title = "Thumbnail Cache"; Safe = $true
             Desc = "Explorer thumbnails, rebuilt on demand"
             Paths = @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer"); Pattern = "thumbcache_*.db" }
    $c += @{ Key = "logs"; Title = "Windows Logs"; Safe = $true
             Desc = "CBS and DISM servicing logs"
             Paths = @("$env:WINDIR\Logs\CBS", "$env:WINDIR\Logs\DISM") }
    $c += @{ Key = "crash"; Title = "Crash Dumps and Error Reports"; Safe = $true
             Desc = "Memory dumps and queued error reports"
             Paths = @("$env:LOCALAPPDATA\CrashDumps", "$env:LOCALAPPDATA\Microsoft\Windows\WER",
                       "$env:PROGRAMDATA\Microsoft\Windows\WER\ReportQueue") }
    $c += @{ Key = "recycle"; Title = "Recycle Bin"; Safe = $true
             Desc = "Permanently removes deleted files"
             Paths = @(); Special = "recyclebin" }

    # --- Navigateurs : UNIQUEMENT les dossiers de cache.
    # Cookies, historique, mots de passe et telechargements ne figurent
    # volontairement dans aucun chemin : vider les cookies deconnecte de tous
    # les sites, ce qui ne se devine pas depuis un bouton "nettoyer".
    $browsers = @(
        @{ Name = "Google Chrome"; Root = "$env:LOCALAPPDATA\Google\Chrome\User Data" },
        @{ Name = "Microsoft Edge"; Root = "$env:LOCALAPPDATA\Microsoft\Edge\User Data" },
        @{ Name = "Brave"; Root = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data" },
        @{ Name = "Opera"; Root = "$env:APPDATA\Opera Software\Opera Stable" }
    )
    foreach ($b in $browsers) {
        if (-not (Test-Path $b.Root)) { continue }
        $paths = @()
        foreach ($sub in @("Default\Cache", "Default\Code Cache", "Default\GPUCache", "Cache", "Code Cache", "GPUCache")) {
            $p = Join-Path $b.Root $sub
            if (Test-Path $p) { $paths += $p }
        }
        if ($paths.Count -gt 0) {
            $c += @{ Key = "br_" + ($b.Name -replace '\W', ''); Title = "$($b.Name) Cache"; Safe = $true
                     Desc = "Cache only - cookies, history and passwords are never touched"
                     Paths = $paths }
        }
    }
    # Firefox range son cache ailleurs, dans un dossier de profil aleatoire.
    $ffCache = "$env:LOCALAPPDATA\Mozilla\Firefox\Profiles"
    if (Test-Path $ffCache) {
        $ffPaths = @()
        foreach ($prof in (Get-ChildItem $ffCache -Directory -ErrorAction SilentlyContinue)) {
            foreach ($sub in @("cache2", "startupCache")) {
                $p = Join-Path $prof.FullName $sub
                if (Test-Path $p) { $ffPaths += $p }
            }
        }
        if ($ffPaths.Count -gt 0) {
            $c += @{ Key = "br_Firefox"; Title = "Firefox Cache"; Safe = $true
                     Desc = "Cache only - cookies, history and passwords are never touched"
                     Paths = $ffPaths }
        }
    }
    return $c
}

$script:cleanCats = @(Get-CleanCategories)

$script:clean = [hashtable]::Synchronized(@{
    Phase = "idle"        # idle scanning scanned cleaning cleaned
    Progress = 0
    Current = ""
    Cancel = $false
    Results = [hashtable]::Synchronized(@{})   # Key -> @{ Bytes; Files }
    Freed = [hashtable]::Synchronized(@{})     # Key -> octets liberes
    Cats = @()
    Selected = @()
    Skipped = 0
})
$script:cleanRunspace = $null
$script:cleanPowerShell = $null

# ---- En-tete -------------------------------------------------------------
$cleanTitle = New-Object System.Windows.Forms.Label
$cleanTitle.Text = "Cleaner"
$cleanTitle.Font = $fontH1
$cleanTitle.ForeColor = $colText
$cleanTitle.AutoSize = $true
$cleanTitle.Location = New-Object System.Drawing.Point(24, 20)
$pageClean.Controls.Add($cleanTitle)

$cleanSub = New-Object System.Windows.Forms.Label
$cleanSub.Text = "Only caches and temporary files. Personal folders are never touched."
$cleanSub.Font = $fontSub
$cleanSub.ForeColor = $colSubText
$cleanSub.AutoSize = $true
$cleanSub.Location = New-Object System.Drawing.Point(24, 58)
$pageClean.Controls.Add($cleanSub)

# ---- Carte de synthese ---------------------------------------------------
$sumCard = New-Object System.Windows.Forms.Panel
$sumCard.Location = New-Object System.Drawing.Point(24, 88)
$sumCard.Size = New-Object System.Drawing.Size(868, 124)
$sumCard.BackColor = $colBg
$sumCardFill = @{ Color = $colCard }
Add-SmoothRounded $sumCard 14 $sumCardFill
$pageClean.Controls.Add($sumCard)

$sumCaption = New-Object System.Windows.Forms.Label
$sumCaption.Text = "TOTAL JUNK FOUND"
$sumCaption.Font = Get-AppFont "SemiBold" 8
$sumCaption.ForeColor = $colSubText
$sumCaption.BackColor = [System.Drawing.Color]::Transparent
$sumCaption.AutoSize = $true
$sumCaption.Location = New-Object System.Drawing.Point(24, 16)
$sumCard.Controls.Add($sumCaption)

$sumTotal = New-Object System.Windows.Forms.Label
$sumTotal.Text = "--"
$sumTotal.Font = Get-AppFont "Bold" 26
$sumTotal.ForeColor = $colText
$sumTotal.BackColor = [System.Drawing.Color]::Transparent
$sumTotal.AutoSize = $false
$sumTotal.Size = New-Object System.Drawing.Size(280, 40)
$sumTotal.TextAlign = "MiddleLeft"
$sumTotal.Location = New-Object System.Drawing.Point(22, 34)
$sumCard.Controls.Add($sumTotal)

$sumFiles = New-Object System.Windows.Forms.Label
$sumFiles.Font = $fontDesc
$sumFiles.ForeColor = $colSubText
$sumFiles.BackColor = [System.Drawing.Color]::Transparent
$sumFiles.AutoSize = $false
$sumFiles.Size = New-Object System.Drawing.Size(280, 16)
$sumFiles.TextAlign = "MiddleLeft"
$sumFiles.Location = New-Object System.Drawing.Point(24, 76)
$sumCard.Controls.Add($sumFiles)

$sumHistory = New-Object System.Windows.Forms.Label
$sumHistory.Font = $fontDesc
$sumHistory.ForeColor = $colSubText
$sumHistory.BackColor = [System.Drawing.Color]::Transparent
$sumHistory.AutoSize = $false
$sumHistory.Size = New-Object System.Drawing.Size(320, 16)
$sumHistory.TextAlign = "MiddleLeft"
$sumHistory.Location = New-Object System.Drawing.Point(24, 96)
$sumCard.Controls.Add($sumHistory)

# Score de proprete : 100 moins une penalite proportionnelle au volume
# trouve. Purement indicatif, mais il rend le resultat lisible d'un coup.
$scoreCaption = New-Object System.Windows.Forms.Label
$scoreCaption.Text = "SYSTEM CLEANLINESS"
$scoreCaption.Font = Get-AppFont "SemiBold" 8
$scoreCaption.ForeColor = $colSubText
$scoreCaption.BackColor = [System.Drawing.Color]::Transparent
$scoreCaption.AutoSize = $false
$scoreCaption.Size = New-Object System.Drawing.Size(200, 16)
$scoreCaption.TextAlign = "MiddleRight"
$scoreCaption.Location = New-Object System.Drawing.Point(640, 16)
$sumCard.Controls.Add($scoreCaption)

$scoreValue = New-Object System.Windows.Forms.Label
$scoreValue.Text = "--"
$scoreValue.Font = Get-AppFont "Bold" 26
$scoreValue.ForeColor = $colGreen
$scoreValue.BackColor = [System.Drawing.Color]::Transparent
$scoreValue.AutoSize = $false
$scoreValue.Size = New-Object System.Drawing.Size(200, 40)
$scoreValue.TextAlign = "MiddleRight"
$scoreValue.Location = New-Object System.Drawing.Point(640, 34)
$sumCard.Controls.Add($scoreValue)

$scoreHint = New-Object System.Windows.Forms.Label
$scoreHint.Font = $fontDesc
$scoreHint.ForeColor = $colSubText
$scoreHint.BackColor = [System.Drawing.Color]::Transparent
$scoreHint.AutoSize = $false
$scoreHint.Size = New-Object System.Drawing.Size(200, 16)
$scoreHint.TextAlign = "MiddleRight"
$scoreHint.Location = New-Object System.Drawing.Point(640, 76)
$sumCard.Controls.Add($scoreHint)

# Barre de progression, visible seulement pendant analyse et nettoyage.
$progBack = New-Object System.Windows.Forms.Panel
$progBack.Size = New-Object System.Drawing.Size(500, 8)
$progBack.Location = New-Object System.Drawing.Point(340, 60)
$progBack.BackColor = $colCard
$sumCard.Controls.Add($progBack)
$progBackFill = @{ Color = $colBorder }
Add-SmoothRounded $progBack 4 $progBackFill
$progBack.Visible = $false

$progFill = New-Object System.Windows.Forms.Panel
$progFill.Size = New-Object System.Drawing.Size(0, 8)
$progFill.Location = New-Object System.Drawing.Point(340, 60)
$progFill.BackColor = $colCard
$sumCard.Controls.Add($progFill)
$progFillFill = @{ Color = $colPurple }
Add-SmoothRounded $progFill 4 $progFillFill
$progFill.Visible = $false
$progFill.BringToFront()

$progLabel = New-Object System.Windows.Forms.Label
$progLabel.Font = $fontDesc
$progLabel.ForeColor = $colSubText
$progLabel.BackColor = [System.Drawing.Color]::Transparent
$progLabel.AutoSize = $false
$progLabel.AutoEllipsis = $true
$progLabel.Size = New-Object System.Drawing.Size(500, 16)
$progLabel.TextAlign = "MiddleLeft"
$progLabel.Location = New-Object System.Drawing.Point(340, 38)
$sumCard.Controls.Add($progLabel)
$progLabel.Visible = $false

function Format-CleanSize([double]$bytes) {
    if ($bytes -ge 1GB) { return "$([math]::Round($bytes / 1GB, 2)) GB" }
    if ($bytes -ge 1MB) { return "$([math]::Round($bytes / 1MB, 1)) MB" }
    if ($bytes -ge 1KB) { return "$([math]::Round($bytes / 1KB, 0)) KB" }
    return "$([int]$bytes) B"
}

# ---- Boutons -------------------------------------------------------------
function New-CleanButton($x, $w, $label, $fillColor, $textColor, $hoverColor) {
    $b = New-Object System.Windows.Forms.Panel
    $b.Size = New-Object System.Drawing.Size($w, 40)
    $b.Location = New-Object System.Drawing.Point($x, 224)
    $b.BackColor = $colBg
    $b.Cursor = "Hand"
    $pageClean.Controls.Add($b)
    $f = @{ Color = $fillColor }
    $t = @{ Color = $textColor }
    $brd = if ($fillColor -eq $colCard) { @{ Color = $colBorder } } else { $null }
    Add-SmoothRounded $b 10 $f $label $fontBtn $t $brd
    $b.Add_MouseEnter({ $f.Color = $hoverColor; $b.Invalidate() }.GetNewClosure())
    $b.Add_MouseLeave({ $f.Color = $fillColor; $b.Invalidate() }.GetNewClosure())
    return $b
}

$btnAnalyze   = New-CleanButton 24  132 "Analyze"        $colCard   $colText $colCardHover
$btnSmart     = New-CleanButton 168 168 "Smart Clean"    $colPurple ([System.Drawing.Color]::White) $colPurpleHover
$btnCleanSel  = New-CleanButton 348 168 "Clean Selected" $colCard   $colText $colCardHover
$btnCleanAll  = New-CleanButton 528 180 "Clean Everything" $colCard $colGold $colCardHover
$btnRefresh   = New-CleanButton 720 132 "Refresh"        $colCard   $colText $colCardHover

# ---- Liste des categories ------------------------------------------------
$cleanFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$cleanFlow.Location = New-Object System.Drawing.Point(24, 278)
$cleanFlow.Size = New-Object System.Drawing.Size(868, 398)
$cleanFlow.BackColor = $colBg
$cleanFlow.AutoScroll = $true
$cleanFlow.FlowDirection = "TopDown"
$cleanFlow.WrapContents = $false
$pageClean.Controls.Add($cleanFlow)

$script:cleanRows = @{}

function Build-CleanRows {
    $cleanFlow.SuspendLayout()
    $cleanFlow.Controls.Clear()
    $script:cleanRows = @{}

    foreach ($cat in $script:cleanCats) {
        $row = New-Object System.Windows.Forms.Panel
        $row.Size = New-Object System.Drawing.Size(836, 56)
        $row.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
        $row.BackColor = $colBg
        $rowFill = @{ Color = $colCard }
        Add-SmoothRounded $row 10 $rowFill
        $cleanFlow.Controls.Add($row)

        # Case a cocher dessinee, pour rester dans le style de l'application.
        $box = New-Object System.Windows.Forms.Panel
        $box.Size = New-Object System.Drawing.Size(20, 20)
        $box.Location = New-Object System.Drawing.Point(16, 17)
        $box.BackColor = $colCard
        $box.Cursor = "Hand"
        $row.Controls.Add($box)
        $boxFill = @{ Color = $colCard }
        $boxBorder = @{ Color = $colBorder }
        Add-SmoothRounded $box 5 $boxFill "" $null $null $boxBorder

        $tick = New-Object System.Windows.Forms.Label
        $tick.Text = [string][char]0xE73E
        $tick.Font = New-Object System.Drawing.Font("Segoe MDL2 Assets", 9)
        $tick.ForeColor = [System.Drawing.Color]::White
        $tick.BackColor = [System.Drawing.Color]::Transparent
        $tick.Size = New-Object System.Drawing.Size(20, 20)
        $tick.TextAlign = "MiddleCenter"
        $tick.Location = New-Object System.Drawing.Point(0, 0)
        $tick.Cursor = "Hand"
        $box.Controls.Add($tick)

        $name = New-Object System.Windows.Forms.Label
        $name.Text = $cat.Title
        $name.Font = Get-AppFont "SemiBold" 9
        $name.ForeColor = $colText
        $name.BackColor = [System.Drawing.Color]::Transparent
        $name.AutoSize = $false
        $name.AutoEllipsis = $true
        $name.Size = New-Object System.Drawing.Size(420, 18)
        $name.TextAlign = "MiddleLeft"
        $name.Location = New-Object System.Drawing.Point(50, 9)
        $row.Controls.Add($name)

        $desc = New-Object System.Windows.Forms.Label
        $desc.Text = $cat.Desc
        $desc.Font = $fontDesc
        $desc.ForeColor = $colSubText
        $desc.BackColor = [System.Drawing.Color]::Transparent
        $desc.AutoSize = $false
        $desc.AutoEllipsis = $true
        $desc.Size = New-Object System.Drawing.Size(420, 16)
        $desc.TextAlign = "MiddleLeft"
        $desc.Location = New-Object System.Drawing.Point(50, 29)
        $row.Controls.Add($desc)

        $size = New-Object System.Windows.Forms.Label
        $size.Text = "--"
        $size.Font = Get-AppFont "SemiBold" 10
        $size.ForeColor = $colText
        $size.BackColor = [System.Drawing.Color]::Transparent
        $size.AutoSize = $false
        $size.Size = New-Object System.Drawing.Size(130, 18)
        $size.TextAlign = "MiddleRight"
        $size.Location = New-Object System.Drawing.Point(490, 10)
        $row.Controls.Add($size)

        $count = New-Object System.Windows.Forms.Label
        $count.Font = $fontDesc
        $count.ForeColor = $colSubText
        $count.BackColor = [System.Drawing.Color]::Transparent
        $count.AutoSize = $false
        $count.Size = New-Object System.Drawing.Size(130, 16)
        $count.TextAlign = "MiddleRight"
        $count.Location = New-Object System.Drawing.Point(490, 29)
        $row.Controls.Add($count)

        $dot = New-Object System.Windows.Forms.Panel
        $dot.Size = New-Object System.Drawing.Size(10, 10)
        $dot.Location = New-Object System.Drawing.Point(636, 23)
        $dot.BackColor = [System.Drawing.Color]::Transparent
        $row.Controls.Add($dot)
        $dotFill = @{ Color = $colBorder }
        Add-SmoothRounded $dot 5 $dotFill

        $btn = New-Object System.Windows.Forms.Panel
        $btn.Size = New-Object System.Drawing.Size(110, 32)
        $btn.Location = New-Object System.Drawing.Point(710, 12)
        $btn.BackColor = $colCard
        $btn.Cursor = "Hand"
        $row.Controls.Add($btn)
        $btnFill = @{ Color = $colCard }
        $btnText = @{ Color = $colSubText }
        $btnBorder = @{ Color = $colBorder }
        Add-SmoothRounded $btn 8 $btnFill "Clean" $fontToggle $btnText $btnBorder
        $btn.Add_MouseEnter({ $btnFill.Color = $colCardHover; $btn.Invalidate() }.GetNewClosure())
        $btn.Add_MouseLeave({ $btnFill.Color = $colCard; $btn.Invalidate() }.GetNewClosure())

        $state = @{ Cat = $cat; Checked = [bool]$cat.Safe; Box = $box; BoxFill = $boxFill
                    BoxBorder = $boxBorder; Tick = $tick; Size = $size; Count = $count
                    DotFill = $dotFill; Dot = $dot; Row = $row }
        $script:cleanRows[$cat.Key] = $state

        $refreshBox = {
            param($st)
            if ($st.Checked) {
                $st.BoxFill.Color = $colPurple; $st.BoxBorder.Color = $colPurple
                $st.Tick.Visible = $true
            } else {
                $st.BoxFill.Color = $colCard; $st.BoxBorder.Color = $colBorder
                $st.Tick.Visible = $false
            }
            $st.Box.Invalidate()
        }
        & $refreshBox $state

        $toggleBox = {
            $state.Checked = -not $state.Checked
            & $refreshBox $state
        }.GetNewClosure()
        $box.Add_Click($toggleBox)
        $tick.Add_Click($toggleBox)
        $name.Add_Click($toggleBox)

        $btn.Add_Click({ Start-CleanJob @($cat.Key) }.GetNewClosure())

        $row.Add_MouseEnter({ $rowFill.Color = $colCardHover; $row.Invalidate() }.GetNewClosure())
        $row.Add_MouseLeave({ $rowFill.Color = $colCard; $row.Invalidate() }.GetNewClosure())
    }
    $cleanFlow.ResumeLayout()
}
Build-CleanRows

# ---- Historique ----------------------------------------------------------
function Show-CleanHistory {
    if (-not (Test-Path $script:cleanHistPath)) {
        $sumHistory.Text = "No cleaning recorded yet"
        return
    }
    try {
        $h = Get-Content $script:cleanHistPath -Raw | ConvertFrom-Json
        $when = [datetime]$h.date
        $days = [int]((Get-Date).Date - $when.Date).TotalDays
        $ago = if ($days -eq 0) { "today" } elseif ($days -eq 1) { "yesterday" } else { "$days days ago" }
        $sumHistory.Text = "Last cleaning: $ago  -  $(Format-CleanSize ([double]$h.freed)) removed"
    } catch { $sumHistory.Text = "No cleaning recorded yet" }
}

function Save-CleanHistory([double]$freed) {
    try {
        $dir = Split-Path $script:cleanHistPath
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        (@{ date = (Get-Date).ToString("o"); freed = $freed } | ConvertTo-Json) |
            Set-Content -Path $script:cleanHistPath -Encoding UTF8
    } catch {}
}
Show-CleanHistory

# ---- Travailleurs d'arriere-plan ----------------------------------------
$cleanWorkerPrelude = @'
# Deuxieme ligne de defense, executee juste avant CHAQUE suppression.
# Refuse la racine d'un disque, le profil utilisateur lui-meme et tout
# dossier personnel, meme si un chemin errone arrivait jusqu'ici.
function Test-CleanPathSafe([string]$p) {
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    try { $full = [System.IO.Path]::GetFullPath($p).TrimEnd('\') } catch { return $false }
    if ($full.Length -lt 8) { return $false }
    if ($full -match '^[A-Za-z]:\\?$') { return $false }
    $profile = $env:USERPROFILE.TrimEnd('\')
    if ($full -ieq $profile) { return $false }
    foreach ($n in @('Desktop','Documents','Pictures','Downloads','Videos','Music','Favorites','Contacts','Links','Saved Games','Searches','OneDrive')) {
        if ($full -ieq (Join-Path $profile $n)) { return $false }
        if ($full -ilike ((Join-Path $profile $n) + '\*')) { return $false }
    }
    foreach ($bad in @($env:WINDIR, "$env:WINDIR\System32", "$env:WINDIR\SysWOW64", $env:ProgramFiles, ${env:ProgramFiles(x86)}, "$env:SystemDrive\Users")) {
        if ($bad -and ($full -ieq $bad.TrimEnd('\'))) { return $false }
    }
    return $true
}

function Measure-CleanPath([string]$p, [string]$pattern) {
    $bytes = 0.0; $files = 0
    if (-not (Test-Path -LiteralPath $p)) { return @{ Bytes = 0.0; Files = 0 } }
    try {
        if ($pattern) {
            $items = Get-ChildItem -LiteralPath $p -Filter $pattern -Force -File -ErrorAction SilentlyContinue
        } else {
            $items = Get-ChildItem -LiteralPath $p -Recurse -Force -File -ErrorAction SilentlyContinue
        }
        foreach ($i in $items) { $bytes += [double]$i.Length; $files++ }
    } catch {}
    return @{ Bytes = $bytes; Files = $files }
}
'@

$cleanScanWorker = [scriptblock]::Create($cleanWorkerPrelude + @'

$clean.Phase = "scanning"
$clean.Progress = 0
$n = $clean.Cats.Count
$idx = 0
foreach ($cat in $clean.Cats) {
    if ($clean.Cancel) { break }
    $clean.Current = "Analyzing " + $cat.Title
    $bytes = 0.0; $files = 0
    if ($cat.Special -eq "recyclebin") {
        # La corbeille se mesure sur le disque systeme ; les autres volumes
        # ont leur propre dossier, ignore ici volontairement.
        $rb = Join-Path $env:SystemDrive '$Recycle.Bin'
        $r = Measure-CleanPath $rb $null
        $bytes = $r.Bytes; $files = $r.Files
    } else {
        foreach ($p in $cat.Paths) {
            $r = Measure-CleanPath $p $cat.Pattern
            $bytes += $r.Bytes; $files += $r.Files
        }
    }
    $clean.Results[$cat.Key] = @{ Bytes = $bytes; Files = $files }
    $idx++
    $clean.Progress = [int](100.0 * $idx / $n)
}
$clean.Current = ""
$clean.Phase = "scanned"
'@)

$cleanCleanWorker = [scriptblock]::Create($cleanWorkerPrelude + @'

$clean.Phase = "cleaning"
$clean.Progress = 0
$clean.Skipped = 0
$sel = @($clean.Selected)
$n = [Math]::Max(1, $sel.Count)
$idx = 0
foreach ($cat in $clean.Cats) {
    if ($clean.Cancel) { break }
    if ($sel -notcontains $cat.Key) { continue }
    $clean.Current = "Cleaning " + $cat.Title
    $freed = 0.0

    if ($cat.Special -eq "recyclebin") {
        try {
            $before = (Measure-CleanPath (Join-Path $env:SystemDrive '$Recycle.Bin') $null).Bytes
            Clear-RecycleBin -Force -ErrorAction SilentlyContinue
            $freed = $before
        } catch {}
    } else {
        foreach ($p in $cat.Paths) {
            if (-not (Test-Path -LiteralPath $p)) { continue }
            if (-not (Test-CleanPathSafe $p)) { continue }
            try {
                if ($cat.Pattern) {
                    $items = Get-ChildItem -LiteralPath $p -Filter $cat.Pattern -Force -File -ErrorAction SilentlyContinue
                } else {
                    # On enumere le CONTENU : le dossier lui-meme n'est jamais
                    # supprime, sinon l'application qui l'utilise pourrait ne
                    # pas savoir le recreer.
                    $items = Get-ChildItem -LiteralPath $p -Force -ErrorAction SilentlyContinue
                }
                foreach ($item in $items) {
                    try {
                        $sz = if ($item.PSIsContainer) {
                            (Measure-CleanPath $item.FullName $null).Bytes
                        } else { [double]$item.Length }
                        Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
                        $freed += $sz
                    } catch {
                        # Fichier verrouille : on passe, jamais de forcage.
                        $clean.Skipped++
                    }
                }
            } catch {}
        }
    }
    $clean.Freed[$cat.Key] = $freed
    $idx++
    $clean.Progress = [int](100.0 * $idx / $n)
}
$clean.Current = ""
$clean.Phase = "cleaned"
'@)

function Start-CleanRunspace($worker) {
    try {
        if ($null -ne $script:cleanPowerShell) { $script:cleanPowerShell.Dispose(); $script:cleanPowerShell = $null }
        if ($null -ne $script:cleanRunspace) { $script:cleanRunspace.Close(); $script:cleanRunspace.Dispose(); $script:cleanRunspace = $null }
        $script:cleanRunspace = [runspacefactory]::CreateRunspace()
        $script:cleanRunspace.ApartmentState = "STA"
        $script:cleanRunspace.ThreadOptions = "ReuseThread"
        $script:cleanRunspace.Open()
        $script:cleanRunspace.SessionStateProxy.SetVariable("clean", $script:clean)
        $script:cleanPowerShell = [powershell]::Create()
        $script:cleanPowerShell.Runspace = $script:cleanRunspace
        $script:cleanPowerShell.AddScript($worker) | Out-Null
        $script:cleanPowerShell.BeginInvoke() | Out-Null
        return $true
    } catch {
        Write-Log "Cleaner could not start: $($_.Exception.Message)"
        return $false
    }
}

function Start-CleanScan {
    if ($script:clean.Phase -eq "scanning" -or $script:clean.Phase -eq "cleaning") { return }
    $script:clean.Cats = $script:cleanCats
    $script:clean.Results = [hashtable]::Synchronized(@{})
    $script:clean.Cancel = $false
    $progBack.Visible = $true; $progFill.Visible = $true; $progLabel.Visible = $true
    $progFill.Width = 0
    Write-Log "Cleaner: analysis started."
    if (Start-CleanRunspace $cleanScanWorker) { $script:cleanTimer.Start() }
}

function Start-CleanJob([string[]]$keys) {
    if ($script:clean.Phase -eq "scanning" -or $script:clean.Phase -eq "cleaning") { return }
    if ($keys.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Select at least one category first.", "Storm Tweaks", "OK", "Information") | Out-Null
        return
    }
    $titles = @()
    $totalBytes = 0.0
    foreach ($k in $keys) {
        $c = $script:cleanCats | Where-Object { $_.Key -eq $k } | Select-Object -First 1
        if ($c) { $titles += $c.Title }
        if ($script:clean.Results.ContainsKey($k)) { $totalBytes += [double]$script:clean.Results[$k].Bytes }
    }
    $msg = "Remove the following?" + "`n`n  " + ($titles -join "`n  ")
    if ($totalBytes -gt 0) { $msg += "`n`nAbout $(Format-CleanSize $totalBytes) will be freed." }
    $msg += "`n`nOnly caches and temporary files are affected. Documents, pictures, desktop and downloads are never touched."
    if ([System.Windows.Forms.MessageBox]::Show($msg, "Confirm cleaning", "YesNo", "Warning") -ne "Yes") { return }

    $script:clean.Cats = $script:cleanCats
    $script:clean.Selected = $keys
    $script:clean.Freed = [hashtable]::Synchronized(@{})
    $script:clean.Cancel = $false
    $progBack.Visible = $true; $progFill.Visible = $true; $progLabel.Visible = $true
    $progFill.Width = 0
    Write-Log "Cleaner: removing $($keys.Count) category(ies)..."
    if (Start-CleanRunspace $cleanCleanWorker) { $script:cleanTimer.Start() }
}

# ---- Rafraichissement de l'interface (lecture seule) --------------------
function Update-CleanUI {
    $c = $script:clean
    $progFill.Width = [int](500.0 * $c.Progress / 100.0)
    $progLabel.Text = if ($c.Current) { "$($c.Current)  -  $($c.Progress)%" } else { "" }

    $total = 0.0; $files = 0
    foreach ($cat in $script:cleanCats) {
        if (-not $c.Results.ContainsKey($cat.Key)) { continue }
        $r = $c.Results[$cat.Key]
        $row = $script:cleanRows[$cat.Key]
        if ($null -eq $row) { continue }
        $row.Size.Text = Format-CleanSize ([double]$r.Bytes)
        $row.Count.Text = "$($r.Files) file(s)"
        # Vert / orange / rouge selon le volume, comme demande.
        $row.DotFill.Color = if ($r.Bytes -ge 2GB) { $colOff } elseif ($r.Bytes -ge 500MB) { $colGold } else { $colGreen }
        $row.Dot.Invalidate()
        $total += [double]$r.Bytes
        $files += [int]$r.Files
    }

    $sumTotal.Text = Format-CleanSize $total
    $sumFiles.Text = "$files file(s) across $($script:cleanCats.Count) categories"

    $score = [int]([Math]::Max(0, [Math]::Min(100, 100 - ($total / 1GB) * 6)))
    $scoreValue.Text = "$score / 100"
    $scoreValue.ForeColor = if ($score -ge 75) { $colGreen } elseif ($score -ge 45) { $colGold } else { $colOff }
    $scoreHint.Text = "Recoverable: $(Format-CleanSize $total)"
}

$script:cleanTimer = New-Object System.Windows.Forms.Timer
$script:cleanTimer.Interval = 250
$script:cleanTimer.Add_Tick({
    try {
        Update-CleanUI
        $ph = $script:clean.Phase
        if ($ph -eq "scanned") {
            $script:clean.Phase = "idle"
            $script:cleanTimer.Stop()
            $progBack.Visible = $false; $progFill.Visible = $false; $progLabel.Visible = $false
            Write-Log "Cleaner: analysis complete - $($sumTotal.Text) recoverable."
        } elseif ($ph -eq "cleaned") {
            $script:clean.Phase = "idle"
            $script:cleanTimer.Stop()
            $progBack.Visible = $false; $progFill.Visible = $false; $progLabel.Visible = $false

            $lines = @(); $freedTotal = 0.0
            foreach ($cat in $script:cleanCats) {
                if (-not $script:clean.Freed.ContainsKey($cat.Key)) { continue }
                $f = [double]$script:clean.Freed[$cat.Key]
                $freedTotal += $f
                $lines += "  OK  $($cat.Title)   $(Format-CleanSize $f)"
            }
            Save-CleanHistory $freedTotal
            Show-CleanHistory
            $report = "Cleaning completed`n`n" + ($lines -join "`n") + "`n`nTotal cleaned: $(Format-CleanSize $freedTotal)"
            if ($script:clean.Skipped -gt 0) {
                $report += "`n$($script:clean.Skipped) file(s) skipped because they were in use."
            }
            Write-Log "Cleaner: $(Format-CleanSize $freedTotal) freed, $($script:clean.Skipped) file(s) in use skipped."
            [System.Windows.Forms.MessageBox]::Show($report, "Storm Tweaks", "OK", "Information") | Out-Null
            Start-CleanScan
        }
    } catch {}
})

# ---- Actions des boutons -------------------------------------------------
$btnAnalyze.Add_Click({ Start-CleanScan })
$btnRefresh.Add_Click({
    $script:cleanCats = @(Get-CleanCategories)
    Build-CleanRows
    Start-CleanScan
})
$btnCleanSel.Add_Click({
    $keys = @()
    foreach ($k in $script:cleanRows.Keys) { if ($script:cleanRows[$k].Checked) { $keys += $k } }
    Start-CleanJob $keys
})
$btnCleanAll.Add_Click({
    Start-CleanJob @($script:cleanCats | ForEach-Object { $_.Key })
})
# Smart Clean : coche les categories sures (Prefetch reste de cote) puis
# lance directement, sans obliger a cocher une a une.
$btnSmart.Add_Click({
    $keys = @()
    foreach ($cat in $script:cleanCats) {
        $st = $script:cleanRows[$cat.Key]
        if ($null -eq $st) { continue }
        $st.Checked = [bool]$cat.Safe
        if ($st.Checked) {
            $st.BoxFill.Color = $colPurple; $st.BoxBorder.Color = $colPurple; $st.Tick.Visible = $true
            $keys += $cat.Key
        } else {
            $st.BoxFill.Color = $colCard; $st.BoxBorder.Color = $colBorder; $st.Tick.Visible = $false
        }
        $st.Box.Invalidate()
    }
    Start-CleanJob $keys
})

# ===========================================================================
# PAGE : TWEAKS
# ===========================================================================
$pageTweaks = New-Object System.Windows.Forms.Panel
$pageTweaks.Location = New-Object System.Drawing.Point(0, 0)
$pageTweaks.Size = New-Object System.Drawing.Size(916, 700)
$pageTweaks.BackColor = $colBg
$pageTweaks.Visible = $false
$pageContainer.Controls.Add($pageTweaks)
$pages["tweaks"] = $pageTweaks

$tweaksTitle = New-Object System.Windows.Forms.Label
$tweaksTitle.Text = "Performance Tweaks"
$tweaksTitle.Font = $fontH1
$tweaksTitle.ForeColor = $colText
$tweaksTitle.AutoSize = $true
$tweaksTitle.Location = New-Object System.Drawing.Point(24, 20)
$pageTweaks.Controls.Add($tweaksTitle)

$btnApply = New-Object System.Windows.Forms.Panel
$btnApply.Size = New-Object System.Drawing.Size(150, 38)
$btnApply.Location = New-Object System.Drawing.Point(742, 24)
$btnApply.BackColor = $colBg
$btnApply.Cursor = "Hand"
$pageTweaks.Controls.Add($btnApply)
$btnApplyFill = @{ Color = $colPurple }
$btnApplyText = @{ Color = [System.Drawing.Color]::White }
Add-SmoothRounded $btnApply 10 $btnApplyFill
$btnApply.Add_MouseEnter({ $btnApplyFill.Color = $colPurpleHover; $btnApply.Invalidate() }.GetNewClosure())
$btnApply.Add_MouseLeave({ $btnApplyFill.Color = $colPurple; $btnApply.Invalidate() }.GetNewClosure())
$btnApply.Visible = $false

# Libelle porte par un Label enfant : il doit alterner entre "Apply" et
# "Apply All (n)", ce qu'un texte fige dans le gestionnaire Paint ne permet pas.
$btnApplyLabel = New-Object System.Windows.Forms.Label
$btnApplyLabel.Text = "Apply"
$btnApplyLabel.Font = $fontBtn
$btnApplyLabel.ForeColor = [System.Drawing.Color]::White
$btnApplyLabel.BackColor = [System.Drawing.Color]::Transparent
$btnApplyLabel.AutoSize = $false
$btnApplyLabel.Size = New-Object System.Drawing.Size(150, 38)
$btnApplyLabel.Location = New-Object System.Drawing.Point(0, 0)
$btnApplyLabel.TextAlign = "MiddleCenter"
$btnApplyLabel.Cursor = "Hand"
$btnApply.Controls.Add($btnApplyLabel)

# ---------------------------------------------------------------------------
# Analyse materielle : lue une seule fois au demarrage (CPU, RAM, GPU, type
# de disque systeme, portable ou non). Sert a decider quels tweaks sont
# recommandes pour CETTE machine, en plus des tweaks toujours recommandes.
# Chaque erreur de detection retombe sur une hypothese raisonnable plutot
# que de faire planter l'analyse (ex: disque suppose SSD si indetectable).
# ---------------------------------------------------------------------------
function Get-SystemProfile {
    $sysInfo = @{
        CpuName          = "Unknown"
        CpuCores         = 4
        RamGB            = 8
        GpuNames         = @()
        IsLaptop         = $false
        SystemDriveIsSSD = $true
        FreeDiskPercent  = 100
    }
    try {
        $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
        $sysInfo.CpuName = $cpu.Name
        if ($cpu.NumberOfCores) { $sysInfo.CpuCores = [int]$cpu.NumberOfCores }
    } catch {}
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $sysInfo.RamGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    } catch {}
    try {
        $gpus = Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name }
        $sysInfo.GpuNames = @($gpus | ForEach-Object { $_.Name })
    } catch {}
    try {
        $battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        $sysInfo.IsLaptop = [bool]$battery
    } catch {}
    try {
        $sysLetter = $env:SystemDrive.TrimEnd(':')
        $part = Get-Partition -DriveLetter $sysLetter -ErrorAction Stop
        $disk = Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq $part.DiskNumber } | Select-Object -First 1
        if ($disk) { $sysInfo.SystemDriveIsSSD = ($disk.MediaType -eq "SSD") }
    } catch {}
    try {
        $vol = Get-PSDrive -Name $env:SystemDrive.TrimEnd(':') -ErrorAction Stop
        $total = $vol.Used + $vol.Free
        if ($total -gt 0) { $sysInfo.FreeDiskPercent = [math]::Round(($vol.Free / $total) * 100, 1) }
    } catch {}
    return $sysInfo
}

$script:sysProfile = Get-SystemProfile

# Un tweak est recommande soit parce qu'il l'est toujours (Recommended =
# $true), soit parce que l'analyse materielle le justifie pour cette machine
# precise (RecommendIf, evalue avec le profil detecte ci-dessus).
function Test-TweakRecommended($tweak) {
    if ($tweak.ContainsKey('Recommended') -and $tweak.Recommended) { return $true }
    if ($tweak.ContainsKey('RecommendIf')) {
        try { return [bool](& $tweak.RecommendIf $script:sysProfile) } catch { return $false }
    }
    return $false
}

# ---- Bandeau "Recommandations" : analyse la config actuelle (etat reel de
# chaque tweak) et propose automatiquement les optimisations marquees comme
# recommandees et pas encore actives, avec un bouton pour tout appliquer. ----
$recoBanner = New-Object System.Windows.Forms.Panel
$recoBanner.Location = New-Object System.Drawing.Point(24, 60)
$recoBanner.Size = New-Object System.Drawing.Size(868, 80)
$recoBanner.BackColor = $colBg
$pageTweaks.Controls.Add($recoBanner)
$recoBannerFill = @{ Color = $colTeal }
Add-SmoothRounded $recoBanner 10 $recoBannerFill

$recoIcon = New-Object System.Windows.Forms.Label
$recoIcon.Text = [string][char]0xE90F
$recoIcon.Font = $fontIcon
$recoIcon.ForeColor = $colGold
$recoIcon.BackColor = [System.Drawing.Color]::Transparent
$recoIcon.Size = New-Object System.Drawing.Size(26, 26)
$recoIcon.TextAlign = "MiddleCenter"
$recoIcon.Location = New-Object System.Drawing.Point(14, 12)
$recoBanner.Controls.Add($recoIcon)

$recoCountLabel = New-Object System.Windows.Forms.Label
$recoCountLabel.Text = "Analyzing your configuration..."
$recoCountLabel.Font = $fontH2
$recoCountLabel.ForeColor = $colText
$recoCountLabel.BackColor = [System.Drawing.Color]::Transparent
$recoCountLabel.AutoSize = $false
$recoCountLabel.Size = New-Object System.Drawing.Size(552, 24)
$recoCountLabel.TextAlign = "MiddleLeft"
$recoCountLabel.Location = New-Object System.Drawing.Point(50, 6)
$recoBanner.Controls.Add($recoCountLabel)

# Ligne d'analyse materielle : CPU, RAM, GPU, disque systeme, portable ou non.
$gpuSummary = if ($script:sysProfile.GpuNames.Count -gt 0) { $script:sysProfile.GpuNames -join ", " } else { "unknown GPU" }
$driveSummary = if ($script:sysProfile.SystemDriveIsSSD) { "SSD" } else { "HDD" }
$formSummary = if ($script:sysProfile.IsLaptop) { "laptop" } else { "desktop" }
$recoHardwareLabel = New-Object System.Windows.Forms.Label
$recoHardwareLabel.Text = "Detected: $($script:sysProfile.CpuCores) cores * $($script:sysProfile.RamGB) GB RAM * $gpuSummary * $driveSummary * $formSummary"
$recoHardwareLabel.Font = $fontDesc
$recoHardwareLabel.ForeColor = $colOnTeal
$recoHardwareLabel.BackColor = [System.Drawing.Color]::Transparent
$recoHardwareLabel.AutoSize = $false
$recoHardwareLabel.AutoEllipsis = $true
$recoHardwareLabel.Size = New-Object System.Drawing.Size(552, 20)
$recoHardwareLabel.TextAlign = "MiddleLeft"
$recoHardwareLabel.Location = New-Object System.Drawing.Point(50, 32)
$recoBanner.Controls.Add($recoHardwareLabel)

$recoSubLabel = New-Object System.Windows.Forms.Label
$recoSubLabel.Text = "Based on the tweaks that are not active yet on this PC"
$recoSubLabel.Font = $fontDesc
$recoSubLabel.ForeColor = $colOnTeal
$recoSubLabel.BackColor = [System.Drawing.Color]::Transparent
$recoSubLabel.AutoSize = $false
$recoSubLabel.AutoEllipsis = $true
$recoSubLabel.Size = New-Object System.Drawing.Size(552, 20)
$recoSubLabel.TextAlign = "MiddleLeft"
$recoSubLabel.Location = New-Object System.Drawing.Point(50, 54)
$recoBanner.Controls.Add($recoSubLabel)

$btnApplyReco = New-Object System.Windows.Forms.Panel
$btnApplyReco.Size = New-Object System.Drawing.Size(174, 34)
$btnApplyReco.Location = New-Object System.Drawing.Point(680, 23)
$btnApplyReco.BackColor = $colBg
$btnApplyReco.Cursor = "Hand"
$recoBanner.Controls.Add($btnApplyReco)
$btnApplyRecoFill = @{ Color = $colGold }
$btnApplyRecoText = @{ Color = [System.Drawing.Color]::Black }
Add-SmoothRounded $btnApplyReco 9 $btnApplyRecoFill "Select recommended" $fontBtn $btnApplyRecoText
$btnApplyReco.Add_MouseEnter({ $btnApplyRecoFill.Color = $colGoldHover; $btnApplyReco.Invalidate() }.GetNewClosure())
$btnApplyReco.Add_MouseLeave({ $btnApplyRecoFill.Color = $colGold; $btnApplyReco.Invalidate() }.GetNewClosure())

# Relit l'etat reel de chaque tweak recommande (via Check/State) et met a
# jour le texte du bandeau ; se masque tout seul quand tout est deja actif.
# "Active" doit vouloir dire reellement applique dans Windows, donc on lit
# Applied (etat reel) et non State (ce que l'utilisateur a coche mais pas
# encore applique). Le bouton, lui, depend de ce qui reste a cocher.
function Update-RecoBanner {
    $notActive = @()
    $notSelected = 0
    foreach ($t in $toggles) {
        $d = $t.Tag
        if (Test-TweakRecommended $d.Tweak) {
            if (-not $d.Applied) { $notActive += $d.Tweak.Name }
            if (-not $d.State) { $notSelected++ }
        }
    }
    if ($notActive.Count -eq 0) {
        if ($toggles.Count -gt 0) {
            $recoCountLabel.Text = "All recommended optimizations are active"
            $recoSubLabel.Text = "Your configuration is fully optimized for Fortnite"
        }
    } else {
        $recoCountLabel.Text = "$($notActive.Count) recommended optimization(s) for your configuration"
        $recoSubLabel.Text = "Not yet active: " + ($notActive -join ", ")
    }
    $btnApplyReco.Visible = ($notSelected -gt 0)
}

# Ne touche pas a Windows : coche seulement les interrupteurs recommandes.
# L'ecriture reste reservee au bouton Apply.
$btnApplyReco.Add_Click({
    $selected = 0
    foreach ($t in $toggles) {
        $d = $t.Tag
        if ((Test-TweakRecommended $d.Tweak) -and -not $d.State) {
            $d.State = $true
            $t.Tag = $d
            Set-ToggleVisual $t $true
            $selected++
        }
    }
    Update-PendingApply
    Update-RecoBanner
    if ($selected -gt 0) {
        Write-Log "$selected recommended optimization(s) selected - press Apply to write them to Windows."
    } else {
        Write-Log "All recommended optimizations are already selected."
    }
})

# ---- Recherche + filtres rapides (favoris / recommandes) au-dessus de la
# liste des tweaks. Le filtrage joue seulement sur la visibilite des cartes,
# le FlowLayoutPanel se rearrange tout seul autour des cartes visibles. ----
$script:searchPlaceholder = "Search a tweak..."
$script:showFavoritesOnly = $false
$script:showRecommendedOnly = $false
$script:tweakCards = @()
# Cree tot : Update-TweakFilter la lit, et le chargement depuis le disque se
# fait plus bas, au moment de construire les cartes.
$script:favorites = @{}

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Location = New-Object System.Drawing.Point(24, 152)
$searchBox.Size = New-Object System.Drawing.Size(480, 28)
$searchBox.BackColor = $colCard
$searchBox.ForeColor = $colSubText
$searchBox.Font = $fontSub
$searchBox.BorderStyle = "FixedSingle"
$searchBox.Text = $script:searchPlaceholder
$pageTweaks.Controls.Add($searchBox)

# $logReason non vide => on ecrit le resultat dans le journal. Sert a rendre
# visible un filtre qui ne repond pas, au lieu d'echouer en silence : une
# exception levee dans un gestionnaire d'evenement WinForms est avalee.
function Update-TweakFilter([string]$logReason) {
    if ($null -eq $script:favorites) { $script:favorites = @{} }
    try {
        $raw = $searchBox.Text
        if ($raw -eq $script:searchPlaceholder) { $raw = "" }
        $query = $raw.Trim().ToLower()
        $shown = 0
        foreach ($entry in $script:tweakCards) {
            $name = $entry.Tweak.Name.ToLower()
            $desc = $entry.Tweak.Desc.ToLower()
            $matchText = [string]::IsNullOrEmpty($query) -or $name.Contains($query) -or $desc.Contains($query)
            $isFav = $script:favorites.ContainsKey($entry.Tweak.Name) -and $script:favorites[$entry.Tweak.Name]
            $isReco = Test-TweakRecommended $entry.Tweak
            $matchFav = (-not $script:showFavoritesOnly) -or $isFav
            $matchReco = (-not $script:showRecommendedOnly) -or $isReco
            $visible = ($matchText -and $matchFav -and $matchReco)
            $entry.Card.Visible = $visible
            if ($visible) { $shown++ }
        }
        if ($logReason) {
            $favTxt = if ($script:showFavoritesOnly) { "on" } else { "off" }
            $recoTxt = if ($script:showRecommendedOnly) { "on" } else { "off" }
            Write-Log "$logReason -> $shown/$($script:tweakCards.Count) tweaks shown (favorites: $favTxt, recommended: $recoTxt)"
        }
    } catch {
        Write-Log "Filter error: $($_.Exception.Message)"
    }
}

$searchBox.Add_Enter({
    if ($searchBox.Text -eq $script:searchPlaceholder) {
        $searchBox.Text = ""
        $searchBox.ForeColor = $colText
    }
})
$searchBox.Add_Leave({
    if ([string]::IsNullOrWhiteSpace($searchBox.Text)) {
        $searchBox.Text = $script:searchPlaceholder
        $searchBox.ForeColor = $colSubText
    }
})
$searchBox.Add_TextChanged({
    if ($searchBox.Text -ne $script:searchPlaceholder) { Update-TweakFilter }
})

# $onToggle recoit $true/$false (etat actif du filtre) a chaque clic. L'etat
# vit dans $chip.Tag, donc le gestionnaire ne depend d'aucune variable
# exterieure - c'est la meme approche que New-NavButton, qui fonctionne.
function New-FilterChip($x, $y, $label, $onToggle) {
    $chip = New-Object System.Windows.Forms.Panel
    $chip.Size = New-Object System.Drawing.Size(140, 28)
    $chip.Location = New-Object System.Drawing.Point($x, $y)
    $chip.BackColor = $colBg
    $chip.Cursor = "Hand"
    $chipFill = @{ Color = $colCard }
    $chipText = @{ Color = $colSubText }
    $chipBorder = @{ Color = $colBorder }
    Add-SmoothRounded $chip 9 $chipFill $label $fontToggle $chipText $chipBorder
    $chip.Tag = @{ Active = $false; Fill = $chipFill; Text = $chipText; Border = $chipBorder; Label = $label }

    $chip.Add_Click({
        $d = $this.Tag
        $d.Active = -not $d.Active
        if ($d.Active) {
            $d.Fill.Color = $colPurple
            $d.Text.Color = [System.Drawing.Color]::White
            $d.Border.Color = $colPurple
        } else {
            $d.Fill.Color = $colCard
            $d.Text.Color = $colSubText
            $d.Border.Color = $colBorder
        }
        $this.Tag = $d
        $this.Invalidate()
        try {
            & $onToggle $d.Active
        } catch {
            Write-Log "Filter error ($($d.Label)): $($_.Exception.Message)"
        }
    }.GetNewClosure())

    $pageTweaks.Controls.Add($chip)
    $chip.BringToFront()
    return $chip
}

$favChip = New-FilterChip 512 152 "Favorites" {
    param($active)
    $script:showFavoritesOnly = $active
    Update-TweakFilter "Favorites filter"
}

$recoChip = New-FilterChip 660 152 "Recommended" {
    param($active)
    $script:showRecommendedOnly = $active
    Update-TweakFilter "Recommended filter"
}

$tweaksFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$tweaksFlow.Location = New-Object System.Drawing.Point(24, 198)
$tweaksFlow.Size = New-Object System.Drawing.Size(868, 478)
$tweaksFlow.AutoScroll = $true
$tweaksFlow.BackColor = $colBg
$tweaksFlow.FlowDirection = "LeftToRight"
$tweaksFlow.WrapContents = $true
$pageTweaks.Controls.Add($tweaksFlow)

# Chaque tweak a "Action" (activer) ET "Undo" (revenir a l'etat par defaut),
# plus "Verify" qui relit la vraie valeur Windows pour prouver l'effet.
$tweaks = @(
    @{ Name = "Windows Game Mode"; Desc = "Prioritizes CPU/GPU for the foreground game"; Recommended = $True
       Tip = "Windows automatically limits background tasks and prioritizes your game's CPU and GPU resources. No real downside; only kicks in once a game is detected as fullscreen or borderless."
       Action = {
            if (-not (Test-Path "HKCU:\Software\Microsoft\GameBar")) { New-Item -Path "HKCU:\Software\Microsoft\GameBar" -Force | Out-Null }
            New-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 1 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value 1 -PropertyType DWord -Force | Out-Null
       }
       Undo = {
            if (-not (Test-Path "HKCU:\Software\Microsoft\GameBar")) { New-Item -Path "HKCU:\Software\Microsoft\GameBar" -Force | Out-Null }
            New-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "AutoGameModeEnabled" -Value 0 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path "HKCU:\Software\Microsoft\GameBar" -Name "AllowAutoGameMode" -Value 0 -PropertyType DWord -Force | Out-Null
       }
       Verify = { "AutoGameModeEnabled = $((Get-ItemProperty -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -ErrorAction SilentlyContinue).AutoGameModeEnabled)" }
       Check = { $v = (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -ErrorAction SilentlyContinue).AutoGameModeEnabled; ($null -eq $v) -or ($v -eq 1) }
       Snapshot = { @{ AutoGameModeEnabled = (Get-RegValueOrNull 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'); AllowAutoGameMode = (Get-RegValueOrNull 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode') } }
       Restore = { param($v) Set-RegValueOrRemove 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' $v.AutoGameModeEnabled; Set-RegValueOrRemove 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' $v.AllowAutoGameMode }
    },

    @{ Name = "Hardware-accelerated GPU Scheduling"; Desc = "Reduces input latency (Hardware-accelerated GPU Scheduling)"; Recommended = $False
       RecommendIf = { param($p) $p.GpuNames.Count -gt 0 -and ($p.GpuNames -match "NVIDIA|AMD|Radeon|Arc|Iris") }
       Tip = "Lets the GPU manage its own memory scheduling instead of relying on the Windows kernel, which can reduce input lag on recent NVIDIA/AMD/Intel drivers. Requires a restart to fully take effect."
       Action = { New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2 -PropertyType DWord -Force | Out-Null }
       Undo = { New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 1 -PropertyType DWord -Force | Out-Null }
       Verify = { "HwSchMode = $((Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -ErrorAction SilentlyContinue).HwSchMode) (requires a restart to be visible in Windows)" }
       Check = { (Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' -Name 'HwSchMode' -ErrorAction SilentlyContinue).HwSchMode -eq 2 }
       Snapshot = { @{ HwSchMode = (Get-RegValueOrNull 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode') } }
       Restore = { param($v) Set-RegValueOrRemove 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' $v.HwSchMode }
    },

    @{ Name = "Ultimate Performance power plan"; Desc = "Prevents the CPU from throttling down"; Recommended = $False
       RecommendIf = { param($p) -not $p.IsLaptop }
       Tip = "A hidden Windows power plan that removes CPU parking and frequency-scaling limits, keeping your processor at full speed at all times. Increases power draw and heat, best suited to desktops."
       Action = {
            # Deux pieges ici : les noms de plans sont traduits ("Performances
            # ultimes" en francais) ET -duplicatescheme ne reutilise pas
            # toujours le GUID du modele. On renomme donc notre copie avec un
            # nom fixe qu'on choisit, ce qui rend la detection exacte partout.
            $ultTemplate = "e9a42b02-d5df-448d-aa00-03f14749eb61"
            $rx = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
            $tag = "Storm Ultimate Performance"

            $listText = (powercfg -list) -join "`n"
            if ($listText -notmatch [regex]::Escape($tag)) {
                $target = $null
                if ($listText -match [regex]::Escape($ultTemplate)) {
                    $target = $ultTemplate
                } else {
                    $dupText = (powercfg -duplicatescheme $ultTemplate 2>&1) -join "`n"
                    if ($dupText -match $rx) { $target = $matches[0] }
                }
                if ($target) { powercfg -changename $target $tag | Out-Null }
            }

            $line = (powercfg -list) | Where-Object { $_ -match [regex]::Escape($tag) } | Select-Object -First 1
            if ($line -and ($line -match $rx)) { powercfg -setactive $matches[0] }
       }
       Undo = {
            # GUID du plan "Equilibre" / "Balanced", identique partout.
            powercfg -setactive 381b4222-f694-41f0-9685-ff5bb260df2e
       }
       Verify = { "Active plan = $((powercfg -getactivescheme) -replace '.*\((.+)\)', '$1')" }
       Check = { ((powercfg -getactivescheme) -join "`n") -match [regex]::Escape("Storm Ultimate Performance") }
       Snapshot = { @{ Guid = ((powercfg -getactivescheme) -replace '.*: ([0-9a-fA-F-]{36}).*', '$1').Trim() } }
       Restore = { param($v) if ($v.Guid) { powercfg -setactive $v.Guid.Trim() } }
    },

    @{ Name = "Disable fullscreen optimizations"; Desc = "Removes micro-stutters caused by the Windows compatibility layer"; Recommended = $True
       Tip = "Bypasses the DWM compatibility layer Windows applies to fullscreen apps, which can cause micro-stutters and extra input latency. Recommended for competitive titles like Fortnite."
       Action = {
            New-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Value 2 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_HonorUserFSEBehaviorMode" -Value 1 -PropertyType DWord -Force | Out-Null
       }
       Undo = {
            New-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Value 0 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_HonorUserFSEBehaviorMode" -Value 0 -PropertyType DWord -Force | Out-Null
       }
       Verify = { "GameDVR_FSEBehaviorMode = $((Get-ItemProperty -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_FSEBehaviorMode' -ErrorAction SilentlyContinue).GameDVR_FSEBehaviorMode)" }
       Check = { (Get-ItemProperty -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_FSEBehaviorMode' -ErrorAction SilentlyContinue).GameDVR_FSEBehaviorMode -eq 2 }
       Snapshot = { @{ FSE = (Get-RegValueOrNull 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode'); Honor = (Get-RegValueOrNull 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode') } }
       Restore = { param($v) Set-RegValueOrRemove 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' $v.FSE; Set-RegValueOrRemove 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' $v.Honor }
    },

    @{ Name = "Disable Xbox Game Bar / DVR"; Desc = "Stops background recording (CPU/GPU)"; Recommended = $True
       Tip = "Prevents Windows from recording your game in the background for the Xbox Game Bar overlay, freeing CPU/GPU and disk I/O. You lose the built-in Win+G recording shortcut."
       Action = {
            New-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -PropertyType DWord -Force | Out-Null
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Force | Out-Null
            New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0 -PropertyType DWord -Force | Out-Null
       }
       Undo = {
            New-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 1 -PropertyType DWord -Force | Out-Null
            if (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR") {
                New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 1 -PropertyType DWord -Force | Out-Null
            }
       }
       Verify = { "GameDVR_Enabled = $((Get-ItemProperty -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -ErrorAction SilentlyContinue).GameDVR_Enabled) (reopen Settings > Gaming to see the change)" }
       Check = { (Get-ItemProperty -Path 'HKCU:\System\GameConfigStore' -Name 'GameDVR_Enabled' -ErrorAction SilentlyContinue).GameDVR_Enabled -eq 0 }
       Snapshot = { @{ Enabled = (Get-RegValueOrNull 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'); Policy = (Get-RegValueOrNull 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR') } }
       Restore = { param($v) Set-RegValueOrRemove 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' $v.Enabled; Set-RegValueOrRemove 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR' 'AllowGameDVR' $v.Policy }
    },

    @{ Name = "Visual effects set to Performance"; Desc = "Disables unnecessary animations and transparency"; Recommended = $False
       RecommendIf = { param($p) $p.RamGB -lt 8 -or $p.CpuCores -le 4 }
       Tip = "Switches Windows to `"Adjust for best performance`", removing animations, shadows and transparency effects that consume GPU cycles. The interface looks less smooth but feels more responsive."
       Action = { New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 2 -PropertyType DWord -Force | Out-Null }
       Undo = { New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 0 -PropertyType DWord -Force | Out-Null }
       Verify = { "VisualFXSetting = $((Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -ErrorAction SilentlyContinue).VisualFXSetting)" }
       Check = { (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -ErrorAction SilentlyContinue).VisualFXSetting -eq 2 }
       Snapshot = { @{ VisualFXSetting = (Get-RegValueOrNull 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting') } }
       Restore = { param($v) Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' $v.VisualFXSetting }
    },

    @{ Name = "System priority for games"; Desc = "Gives game processes higher CPU/GPU priority"; Recommended = $False
       Tip = "Raises the GPU and CPU scheduling priority Windows grants to processes tagged as games, so they get resources first when the system is under load."
       Action = {
            $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
            New-Item -Path $path -Force | Out-Null
            New-ItemProperty -Path $path -Name "GPU Priority" -Value 8 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $path -Name "Priority" -Value 6 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $path -Name "Scheduling Category" -Value "High" -PropertyType String -Force | Out-Null
       }
       Undo = {
            $path = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games"
            New-ItemProperty -Path $path -Name "GPU Priority" -Value 8 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $path -Name "Priority" -Value 2 -PropertyType DWord -Force | Out-Null
            New-ItemProperty -Path $path -Name "Scheduling Category" -Value "Medium" -PropertyType String -Force | Out-Null
       }
       Verify = { "Scheduling Category = $((Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'Scheduling Category' -ErrorAction SilentlyContinue).'Scheduling Category')" }
       Check = { (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games' -Name 'Scheduling Category' -ErrorAction SilentlyContinue).'Scheduling Category' -eq 'High' }
       Snapshot = { $p = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; @{ GpuPriority = (Get-RegValueOrNull $p 'GPU Priority'); Priority = (Get-RegValueOrNull $p 'Priority'); Category = (Get-RegValueOrNull $p 'Scheduling Category') } }
       Restore = { param($v) $p = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Set-RegValueOrRemove $p 'GPU Priority' $v.GpuPriority; Set-RegValueOrRemove $p 'Priority' $v.Priority; Set-RegValueOrRemove $p 'Scheduling Category' $v.Category 'String' }
    },

    @{ Name = "Remove network bandwidth cap"; Desc = "Removes the network cap reserved by Windows (QoS)"; Recommended = $True
       Tip = "Windows reserves a share of bandwidth for QoS packet scheduling by default; this removes that reservation so your game can use the full available bandwidth."
       Action = { New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 0xffffffff -PropertyType DWord -Force | Out-Null }
       Undo = { New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" -Name "NetworkThrottlingIndex" -Value 10 -PropertyType DWord -Force | Out-Null }
       Verify = { $v = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -ErrorAction SilentlyContinue).NetworkThrottlingIndex; if ($null -eq $v) { "NetworkThrottlingIndex = (absent)" } else { "NetworkThrottlingIndex = 0x$('{0:X}' -f $v) (raw=$v, type=$($v.GetType().Name))" } }
       Check = { $v = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -ErrorAction SilentlyContinue).NetworkThrottlingIndex; ($null -ne $v) -and (('{0:X}' -f $v) -eq 'FFFFFFFF') }
       Snapshot = { @{ Idx = (Get-RegValueOrNull 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex') } }
       Restore = { param($v) Set-RegValueOrRemove 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' 'NetworkThrottlingIndex' $v.Idx }
    },

    @{ Name = "Disable background apps"; Desc = "Stops UWP apps from using CPU while you game"; Recommended = $False
       RecommendIf = { param($p) $p.RamGB -lt 8 }
       Tip = "Stops UWP Store apps from running and syncing in the background, freeing CPU cycles while you play. Notifications from those apps may be delayed."
       Action = { New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1 -PropertyType DWord -Force | Out-Null }
       Undo = { New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 0 -PropertyType DWord -Force | Out-Null }
       Verify = { "GlobalUserDisabled = $((Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -ErrorAction SilentlyContinue).GlobalUserDisabled)" }
       Check = { (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -ErrorAction SilentlyContinue).GlobalUserDisabled -eq 1 }
       Snapshot = { @{ Disabled = (Get-RegValueOrNull 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled') } }
       Restore = { param($v) Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' $v.Disabled }
    },

    @{ Name = "Disable Nagle's algorithm"; Desc = "Reduces network latency (immediate TCP ACK) on all interfaces"; Recommended = $True
       Tip = "Forces the network stack to send TCP packets immediately instead of buffering them, which can lower and smooth out in-game ping at the cost of slightly more network overhead."
       Action = {
            $ifPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
            Get-ChildItem $ifPath | ForEach-Object {
                New-ItemProperty -Path $_.PsPath -Name "TcpAckFrequency" -Value 1 -PropertyType DWord -Force | Out-Null
                New-ItemProperty -Path $_.PsPath -Name "TCPNoDelay" -Value 1 -PropertyType DWord -Force | Out-Null
            }
       }
       Undo = {
            $ifPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
            Get-ChildItem $ifPath | ForEach-Object {
                Remove-ItemProperty -Path $_.PsPath -Name "TcpAckFrequency" -Force -ErrorAction SilentlyContinue
                Remove-ItemProperty -Path $_.PsPath -Name "TCPNoDelay" -Force -ErrorAction SilentlyContinue
            }
       }
       Verify = {
            $ifPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
            $withKey = Get-ChildItem $ifPath | Where-Object { (Get-ItemProperty $_.PsPath -Name "TcpAckFrequency" -ErrorAction SilentlyContinue) }
            "TcpAckFrequency present on $($withKey.Count) interface(s)"
       }
       Check = { $ifPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'; $any = Get-ChildItem $ifPath | Where-Object { (Get-ItemProperty $_.PsPath -Name 'TcpAckFrequency' -ErrorAction SilentlyContinue).TcpAckFrequency -eq 1 }; [bool]$any }
       Snapshot = { $ifPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'; $map = @{}; Get-ChildItem $ifPath | ForEach-Object { $map[$_.PSChildName] = @{ Ack = (Get-RegValueOrNull $_.PsPath 'TcpAckFrequency'); NoDelay = (Get-RegValueOrNull $_.PsPath 'TCPNoDelay') } }; $map }
       Restore = { param($v) $ifPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'; foreach ($k in $v.PSObject.Properties.Name) { $sub = $v.$k; $p = Join-Path $ifPath $k; Set-RegValueOrRemove $p 'TcpAckFrequency' $sub.Ack; Set-RegValueOrRemove $p 'TCPNoDelay' $sub.NoDelay } }
    },

    @{ Name = "Fast DNS (Cloudflare 1.1.1.1)"; Desc = "Switches the active network adapter to a low-latency DNS"; Recommended = $False
       Tip = "Points your active network adapter to Cloudflare's 1.1.1.1 resolver, which is often faster than your ISP's default DNS for resolving game servers and matchmaking endpoints."
       Action = {
            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
            if ($adapter) { Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ServerAddresses ("1.1.1.1","1.0.0.1") }
       }
       Undo = {
            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
            if ($adapter) { Set-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -ResetServerAddresses }
       }
       Verify = {
            $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
            if ($adapter) { "DNS = $((Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4).ServerAddresses -join ', ')" } else { "No active adapter" }
       }
       Check = { $hit = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Where-Object { (Get-DnsClientServerAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses -contains '1.1.1.1' }; [bool]$hit }
       Snapshot = { $adapter = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -First 1; if ($adapter) { @{ IfIndex = $adapter.ifIndex; Servers = @((Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4).ServerAddresses) } } else { @{ IfIndex = $null; Servers = @() } } }
       Restore = { param($v) if ($v.IfIndex) { if ($v.Servers -and $v.Servers.Count -gt 0) { Set-DnsClientServerAddress -InterfaceIndex $v.IfIndex -ServerAddresses $v.Servers } else { Set-DnsClientServerAddress -InterfaceIndex $v.IfIndex -ResetServerAddresses } } }
    },

    @{ Name = "Disable mouse acceleration"; Desc = "True 1:1 mouse movement, no smoothing"; Recommended = $True
       Tip = "Removes Windows' pointer-speed curve so every physical inch of mouse movement maps to the same distance on screen - the standard setup for competitive aim."
       Action = {
            Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value "0" -Type String -Force
            Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "0" -Type String -Force
            Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "0" -Type String -Force
            [int[]]$params = @(0, 0, 0)
            [StormNative]::SystemParametersInfo($script:SPI_SETMOUSE, 0, $params, $script:SPIF_SENDCHANGE) | Out-Null
       }
       Undo = {
            Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseSpeed" -Value "1" -Type String -Force
            Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold1" -Value "6" -Type String -Force
            Set-ItemProperty -Path "HKCU:\Control Panel\Mouse" -Name "MouseThreshold2" -Value "10" -Type String -Force
            [int[]]$params = @(6, 10, 1)
            [StormNative]::SystemParametersInfo($script:SPI_SETMOUSE, 0, $params, $script:SPIF_SENDCHANGE) | Out-Null
       }
       Verify = { "MouseSpeed = $((Get-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -ErrorAction SilentlyContinue).MouseSpeed) (applied immediately, no restart needed)" }
       Check = { (Get-ItemProperty -Path 'HKCU:\Control Panel\Mouse' -Name 'MouseSpeed' -ErrorAction SilentlyContinue).MouseSpeed -eq '0' }
       Snapshot = { @{ Speed = (Get-RegValueOrNull 'HKCU:\Control Panel\Mouse' 'MouseSpeed'); T1 = (Get-RegValueOrNull 'HKCU:\Control Panel\Mouse' 'MouseThreshold1'); T2 = (Get-RegValueOrNull 'HKCU:\Control Panel\Mouse' 'MouseThreshold2') } }
       Restore = { param($v) $spd = if ($v.Speed) { $v.Speed } else { '1' }; $t1 = if ($v.T1) { $v.T1 } else { '6' }; $t2 = if ($v.T2) { $v.T2 } else { '10' }; Set-RegValueOrRemove 'HKCU:\Control Panel\Mouse' 'MouseSpeed' $spd 'String'; Set-RegValueOrRemove 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' $t1 'String'; Set-RegValueOrRemove 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' $t2 'String'; [int[]]$params = @([int]$t1, [int]$t2, [int]$spd); [StormNative]::SystemParametersInfo($script:SPI_SETMOUSE, 0, $params, $script:SPIF_SENDCHANGE) | Out-Null }
    },

    @{ Name = "Disable SysMain (Superfetch)"; Desc = "Frees up CPU/disk used by pre-caching"; Recommended = $False
       RecommendIf = { param($p) $p.SystemDriveIsSSD }
       Tip = "Stops the service that pre-loads frequently used apps into RAM in the background. Frees up CPU and disk activity, most noticeable on HDDs or lower-end CPUs."
       Action = { Stop-Service -Name "SysMain" -Force -ErrorAction SilentlyContinue; Set-Service -Name "SysMain" -StartupType Disabled -ErrorAction Stop }
       Undo = { Set-Service -Name "SysMain" -StartupType Automatic -ErrorAction Stop; Start-Service -Name "SysMain" -ErrorAction SilentlyContinue }
       Verify = { $svc = Get-Service -Name "SysMain" -ErrorAction SilentlyContinue; if ($svc) { "SysMain = $($svc.Status) / $($svc.StartType)" } else { "SysMain not found" } }
       Check = { (Get-Service -Name 'SysMain' -ErrorAction SilentlyContinue).StartType -eq 'Disabled' }
       Snapshot = { $svc = Get-Service -Name 'SysMain' -ErrorAction SilentlyContinue; if ($svc) { @{ StartType = $svc.StartType.ToString(); WasRunning = ($svc.Status -eq 'Running') } } else { @{ StartType = $null; WasRunning = $false } } }
       Restore = { param($v) if ($v.StartType) { Set-Service -Name 'SysMain' -StartupType $v.StartType -ErrorAction SilentlyContinue; if ($v.WasRunning) { Start-Service -Name 'SysMain' -ErrorAction SilentlyContinue } else { Stop-Service -Name 'SysMain' -Force -ErrorAction SilentlyContinue } } }
    },

    @{ Name = "Disable search indexing"; Desc = "Stops the service that continuously indexes your files"; Recommended = $False
       RecommendIf = { param($p) -not $p.SystemDriveIsSSD }
       Tip = "Stops Windows Search from continuously scanning your files to keep its index up to date, freeing background disk and CPU usage. Start menu search will be slower afterward."
       Action = { Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue; Set-Service -Name "WSearch" -StartupType Disabled -ErrorAction Stop }
       Undo = { Set-Service -Name "WSearch" -StartupType Automatic -ErrorAction Stop; Start-Service -Name "WSearch" -ErrorAction SilentlyContinue }
       Verify = { $svc = Get-Service -Name "WSearch" -ErrorAction SilentlyContinue; if ($svc) { "WSearch = $($svc.Status) / $($svc.StartType)" } else { "WSearch not found" } }
       Check = { (Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue).StartType -eq 'Disabled' }
       Snapshot = { $svc = Get-Service -Name 'WSearch' -ErrorAction SilentlyContinue; if ($svc) { @{ StartType = $svc.StartType.ToString(); WasRunning = ($svc.Status -eq 'Running') } } else { @{ StartType = $null; WasRunning = $false } } }
       Restore = { param($v) if ($v.StartType) { Set-Service -Name 'WSearch' -StartupType $v.StartType -ErrorAction SilentlyContinue; if ($v.WasRunning) { Start-Service -Name 'WSearch' -ErrorAction SilentlyContinue } else { Stop-Service -Name 'WSearch' -Force -ErrorAction SilentlyContinue } } }
    },

    @{ Name = "Disable hibernation"; Desc = "Frees up disk space and removes a background service"; Recommended = $False
       RecommendIf = { param($p) $p.FreeDiskPercent -lt 20 }
       Tip = "Removes the hiberfil.sys file Windows keeps reserved on your drive and disables the hibernation power state, freeing disk space roughly equal to your RAM size."
       Action = { powercfg -h off }
       Undo = { powercfg -h on }
       Verify = { if (Test-Path "$env:SystemDrive\hiberfil.sys") { "hiberfil.sys present (hibernation on)" } else { "hiberfil.sys absent (hibernation off)" } }
       Check = { -not (Test-Path "$env:SystemDrive\hiberfil.sys") }
       Snapshot = { @{ Present = (Test-Path "$env:SystemDrive\hiberfil.sys") } }
       Restore = { param($v) if ($v.Present) { powercfg -h on } else { powercfg -h off } }
    },

    @{ Name = "Reduce Windows telemetry"; Desc = "Reduces background data collection"; Recommended = $False
       Tip = "Lowers the diagnostic data collection level Windows sends to Microsoft, which slightly reduces background network and CPU activity."
       Action = {
            New-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Force | Out-Null
            New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0 -PropertyType DWord -Force | Out-Null
       }
       Undo = { Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Force -ErrorAction SilentlyContinue }
       Verify = { $v = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -ErrorAction SilentlyContinue).AllowTelemetry; if ($null -eq $v) { "AllowTelemetry = (key absent, default value)" } else { "AllowTelemetry = $v" } }
       Check = { (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -ErrorAction SilentlyContinue).AllowTelemetry -eq 0 }
       Snapshot = { @{ Val = (Get-RegValueOrNull 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry') } }
       Restore = { param($v) Set-RegValueOrRemove 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' $v.Val }
    },

    @{ Name = "Disable system notifications"; Desc = "Stops Windows pop-ups from interrupting your game"; Recommended = $False
       Tip = "Stops Windows toast notifications from popping up on screen, so app alerts can't interrupt or distract you mid-game."
       Action = { New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "ToastEnabled" -Value 0 -PropertyType DWord -Force | Out-Null }
       Undo = { New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications" -Name "ToastEnabled" -Value 1 -PropertyType DWord -Force | Out-Null }
       Verify = { "ToastEnabled = $((Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' -Name 'ToastEnabled' -ErrorAction SilentlyContinue).ToastEnabled)" }
       Check = { (Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' -Name 'ToastEnabled' -ErrorAction SilentlyContinue).ToastEnabled -eq 0 }
       Snapshot = { @{ Val = (Get-RegValueOrNull 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled') } }
       Restore = { param($v) Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' $v.Val }
    }
)

# ---------------------------------------------------------------------------
# Point de sauvegarde ("baseline") des reglages Windows d'origine, cree une
# seule fois, au tout premier lancement (avant qu'aucun tweak ne soit
# applique). Le bouton "Reset Settings" (page Reglages) restaure exactement
# ces valeurs, contrairement a "Restore" qui remet des valeurs par defaut
# generiques (pas forcement celles que l'utilisateur avait avant).
# ---------------------------------------------------------------------------
$script:baselinePath = Join-Path $env:LOCALAPPDATA "StormTweaks\baseline.json"

if (-not (Test-Path $script:baselinePath)) {
    $baselineDir = Split-Path $script:baselinePath
    if (-not (Test-Path $baselineDir)) { New-Item -Path $baselineDir -ItemType Directory -Force | Out-Null }

    $baseline = @{}
    foreach ($tweak in $tweaks) {
        if ($tweak.ContainsKey('Snapshot')) {
            try { $baseline[$tweak.Name] = & $tweak.Snapshot } catch { $baseline[$tweak.Name] = $null }
        }
    }

    try {
        ($baseline | ConvertTo-Json -Depth 8) | Set-Content -Path $script:baselinePath -Encoding UTF8
    } catch {
        # Si l'ecriture echoue (permissions, disque...), le bouton "Reset
        # Settings" affichera simplement qu'aucun point de sauvegarde n'est
        # disponible plutot que de faire planter le lancement de l'appli.
    }
}

# Icone et couleur d'accent associees a chaque tweak (meme ordre que $tweaks)
$tweakVisuals = @(
    @{ Icon = "bolt";    Accent = $colPurple },
    @{ Icon = "chip";    Accent = $colOn },
    @{ Icon = "bolt";    Accent = $colGold },
    @{ Icon = "display"; Accent = $colPurple },
    @{ Icon = "display"; Accent = $colOn },
    @{ Icon = "display"; Accent = $colGold },
    @{ Icon = "gear";    Accent = $colPurple },
    @{ Icon = "network"; Accent = $colOn },
    @{ Icon = "gear";    Accent = $colGreen },
    @{ Icon = "network"; Accent = $colOn },
    @{ Icon = "network"; Accent = $colGreen },
    @{ Icon = "mouse";   Accent = $colGold },
    @{ Icon = "gear";    Accent = $colGreen },
    @{ Icon = "gear";    Accent = $colPurple },
    @{ Icon = "gear";    Accent = $colOn },
    @{ Icon = "shield";  Accent = $colGreen },
    @{ Icon = "bell";    Accent = $colGold }
)

$toggles = @()

# ---- Etat persistant "Favoris" (etoile sur chaque carte de tweak) -------
$script:favoritesPath = Join-Path $env:LOCALAPPDATA "StormTweaks\favorites.json"
if (Test-Path $script:favoritesPath) {
    try {
        $rawFav = Get-Content -Path $script:favoritesPath -Raw | ConvertFrom-Json
        foreach ($p in $rawFav.PSObject.Properties) { $script:favorites[$p.Name] = [bool]$p.Value }
    } catch {}
}
function Save-Favorites {
    try {
        $dir = Split-Path $script:favoritesPath
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        ($script:favorites | ConvertTo-Json) | Set-Content -Path $script:favoritesPath -Encoding UTF8
    } catch {}
}
function Set-FavStarVisual($lbl, $isFav) {
    if ($isFav) {
        $lbl.Text = [string][char]0xE735
        $lbl.ForeColor = $colGold
    } else {
        $lbl.Text = [string][char]0xE734
        $lbl.ForeColor = $colSubText
    }
}

# ---- Infobulles detaillees affichees au survol de chaque carte ----------
$tt = New-Object System.Windows.Forms.ToolTip
$tt.AutoPopDelay = 9000
$tt.InitialDelay = 300
$tt.ReshowDelay = 100
$tt.ShowAlways = $true

# Interrupteur "pilule" avec curseur glissant
function Set-ToggleVisual($track, $state, [bool]$animate = $false) {
    $data = $track.Tag
    $target = if ($state) { 27 } else { 3 }
    $color = if ($state) { $colOn } else { $colOff }

    if ($animate) {
        # Glissement en 6 images (~60 ms). Reserve au clic : animer les 17
        # interrupteurs au demarrage ajouterait une seconde d'attente.
        $from = $data.Knob.Location.X
        for ($i = 1; $i -le 6; $i++) {
            $x = [int]($from + ($target - $from) * $i / 6.0)
            $data.Knob.Location = New-Object System.Drawing.Point($x, 3)
            if ($i -eq 3) { $data.Fill.Color = $color; $data.Knob.BackColor = $color; $track.Invalidate() }
            $track.Refresh()
            Start-Sleep -Milliseconds 10
        }
    }

    $data.Fill.Color = $color
    $data.Knob.BackColor = $color
    $data.Knob.Location = New-Object System.Drawing.Point($target, 3)
    $track.Invalidate()
}

for ($tweakIdx = 0; $tweakIdx -lt $tweaks.Count; $tweakIdx++) {
    $tweak = $tweaks[$tweakIdx]
    $visual = $tweakVisuals[$tweakIdx]

    $card = New-Object System.Windows.Forms.Panel
    $card.Size = New-Object System.Drawing.Size(176, 176)
    $card.BackColor = $colBg
    $card.Margin = New-Object System.Windows.Forms.Padding(0, 0, 14, 14)
    $cardFill = @{ Color = $colCard }
    Add-SmoothRounded $card 12 $cardFill

    # Badge d'icone, centre en haut de la carte
    $iconBadge = New-Object System.Windows.Forms.Panel
    $iconBadge.Size = New-Object System.Drawing.Size(48, 48)
    $iconBadge.Location = New-Object System.Drawing.Point(64, 14)
    $iconBadge.BackColor = [System.Drawing.Color]::Transparent
    $card.Controls.Add($iconBadge)
    Add-TweakIcon $iconBadge $visual.Icon $visual.Accent

    # Badge "Recommended" : visible pour les tweaks juges les plus utiles
    # pour Fortnite (voir Recommended = $true dans la liste des tweaks).
    $isRecommendedTweak = Test-TweakRecommended $tweak
    if ($isRecommendedTweak) {
        $recoBadge = New-Object System.Windows.Forms.Label
        $recoBadge.Text = [string][char]0xE90F
        $recoBadge.Font = New-Object System.Drawing.Font("Segoe MDL2 Assets", 9)
        $recoBadge.ForeColor = $colGold
        $recoBadge.BackColor = [System.Drawing.Color]::Transparent
        $recoBadge.Size = New-Object System.Drawing.Size(20, 20)
        $recoBadge.TextAlign = "MiddleCenter"
        $recoBadge.Location = New-Object System.Drawing.Point(8, 8)
        $card.Controls.Add($recoBadge)
        $tt.SetToolTip($recoBadge, "Recommended by Storm Tweaks for gaming performance")
    }

    # Etoile de favori en haut a droite de la carte - persiste entre sessions.
    $favStar = New-Object System.Windows.Forms.Label
    $favStar.Font = New-Object System.Drawing.Font("Segoe MDL2 Assets", 12)
    $favStar.BackColor = [System.Drawing.Color]::Transparent
    $favStar.Size = New-Object System.Drawing.Size(24, 24)
    $favStar.TextAlign = "MiddleCenter"
    $favStar.Location = New-Object System.Drawing.Point(146, 6)
    $favStar.Cursor = "Hand"
    $card.Controls.Add($favStar)
    $isFavTweak = $script:favorites.ContainsKey($tweak.Name) -and $script:favorites[$tweak.Name]
    Set-FavStarVisual $favStar $isFavTweak
    $favClick = {
        $name = $tweak.Name
        $newFav = -not ($script:favorites.ContainsKey($name) -and $script:favorites[$name])
        $script:favorites[$name] = $newFav
        Set-FavStarVisual $favStar $newFav
        Save-Favorites
        $favWord = if ($newFav) { "added to" } else { "removed from" }
        Write-Log "$name $favWord favorites"
        Update-TweakFilter
    }.GetNewClosure()
    $favStar.Add_Click($favClick)

    $lblName = New-Object System.Windows.Forms.Label
    $lblName.Text = $tweak.Name
    $lblName.Font = Get-AppFont "SemiBold" 8.5
    $lblName.ForeColor = $colText
    $lblName.BackColor = [System.Drawing.Color]::Transparent
    $lblName.AutoSize = $false
    $lblName.TextAlign = "MiddleCenter"
    $lblName.Size = New-Object System.Drawing.Size(160, 44)
    $lblName.Location = New-Object System.Drawing.Point(8, 66)
    $card.Controls.Add($lblName)

    # Description detaillee au survol (carte, icone et titre)
    $hoverTip = if ($tweak.ContainsKey('Tip')) { $tweak.Tip } else { $tweak.Desc }
    $tt.SetToolTip($card, $hoverTip)
    $tt.SetToolTip($iconBadge, $hoverTip)
    $tt.SetToolTip($lblName, $hoverTip)

    # Piste de l'interrupteur (forme pilule, rayon = moitie de la hauteur), centree en bas
    $track = New-Object System.Windows.Forms.Panel
    $track.Size = New-Object System.Drawing.Size(54, 26)
    $track.Location = New-Object System.Drawing.Point(61, 136)
    $track.BackColor = $colCard
    $track.Cursor = "Hand"
    $trackFill = @{ Color = $colOn }
    Add-SmoothRounded $track 13 $trackFill
    $card.Controls.Add($track)

    # Curseur circulaire qui glisse a gauche/droite selon l'etat
    $knob = New-Object System.Windows.Forms.Panel
    $knob.Size = New-Object System.Drawing.Size(20, 20)
    $knob.BackColor = $colOn
    $knobFill = @{ Color = [System.Drawing.Color]::White }
    Add-SmoothRounded $knob 10 $knobFill
    $track.Controls.Add($knob)

    # Etat initial = ce qui est vraiment actif sur Windows en ce moment (lu via
    # Check), pas une valeur arbitraire. Si la lecture echoue, on part du
    # principe que le tweak n'est pas applique (etat le plus honnete).
    $initialState = $false
    if ($tweak.ContainsKey('Check')) {
        try { $initialState = [bool](& $tweak.Check) } catch { $initialState = $false }
    }

    # State = ce que l'utilisateur veut (affiche), Applied = ce que Windows a
    # vraiment. Un clic ne change que State ; rien n'est ecrit dans Windows
    # tant que "Apply" n'a pas ete presse.
    $track.Tag = @{ Tweak = $tweak; State = $initialState; Applied = $initialState; Knob = $knob; Fill = $trackFill }
    Set-ToggleVisual $track $initialState

    $toggleClick = {
        $t = $track
        $data = $t.Tag
        $data.State = -not $data.State
        $t.Tag = $data
        Set-ToggleVisual $t $data.State $true
        Update-PendingApply
        Update-RecoBanner
    }.GetNewClosure()
    $track.Add_Click($toggleClick)
    $knob.Add_Click($toggleClick)

    $card.Controls.Add($track)
    $card.Add_MouseEnter({ $cardFill.Color = $colCardHover; $card.Invalidate() }.GetNewClosure())
    $card.Add_MouseLeave({ $cardFill.Color = $colCard; $card.Invalidate() }.GetNewClosure())

    $script:tweakCards += @{ Card = $card; Tweak = $tweak }
    $toggles += $track
    $tweaksFlow.Controls.Add($card)
}

# Compte les interrupteurs dont l'etat affiche differe de l'etat reel de
# Windows, et adapte le bouton : cache si rien a faire, "Apply" pour une
# seule modification, "Apply All (n)" au-dela.
function Update-PendingApply {
    $pending = 0
    foreach ($t in $toggles) {
        $d = $t.Tag
        if ($d.State -ne $d.Applied) { $pending++ }
    }
    if ($pending -eq 0) {
        $btnApply.Visible = $false
    } else {
        $btnApplyLabel.Text = if ($pending -eq 1) { "Apply" } else { "Apply All ($pending)" }
        $btnApply.Visible = $true
        $btnApply.BringToFront()
    }
}

# Seul endroit du programme qui ecrit reellement dans Windows depuis la page
# Tweaks. On n'applique QUE les differences, puis on relit chaque tweak via
# Check pour que l'affichage reflete ce que Windows a vraiment retenu - si un
# tweak ne "prend" pas, l'interrupteur revient sur OFF immediatement au lieu
# de mentir jusqu'au prochain lancement.
$applyPendingHandler = {
    $changes = @()
    foreach ($t in $toggles) {
        $d = $t.Tag
        if ($d.State -ne $d.Applied) { $changes += $t }
    }
    if ($changes.Count -eq 0) {
        $btnApply.Visible = $false
        return
    }

    Write-Log "Applying $($changes.Count) change(s)..."
    $okCount = 0
    $errCount = 0
    $rejected = @()

    foreach ($t in $changes) {
        $d = $t.Tag
        $tw = $d.Tweak
        $wanted = $d.State
        try {
            if ($wanted) {
                & $tw.Action
            } elseif ($tw.ContainsKey('Undo')) {
                & $tw.Undo
            }

            # Relecture immediate de l'etat reel
            $actual = $wanted
            if ($tw.ContainsKey('Check')) {
                try { $actual = [bool](& $tw.Check) } catch { $actual = $wanted }
            }
            $proof = ""
            if ($tw.ContainsKey('Verify')) {
                try { $proof = "  ==>  " + (& $tw.Verify) } catch { $proof = "" }
            }

            $d.State = $actual
            $d.Applied = $actual
            $t.Tag = $d
            Set-ToggleVisual $t $actual

            if ($actual -eq $wanted) {
                $okCount++
                $label = if ($wanted) { "ON " } else { "OFF" }
                Write-Log "$label - $($tw.Name)$proof"
            } else {
                $rejected += $tw.Name
                Write-Log "NOT APPLIED - $($tw.Name): Windows still reports the opposite state$proof"
            }
        } catch {
            $errCount++
            Write-Log "ERROR - $($tw.Name): $($_.Exception.Message)"
            # L'etat affiche revient a la realite plutot que de mentir
            $d.State = $d.Applied
            $t.Tag = $d
            Set-ToggleVisual $t $d.Applied
        }
    }

    Update-PendingApply
    Update-RecoBanner

    $summary = "$okCount change(s) applied."
    if ($rejected.Count -gt 0) { $summary += "`n$($rejected.Count) not accepted by Windows: " + ($rejected -join ", ") }
    if ($errCount -gt 0) { $summary += "`n$errCount error(s) - see the log." }
    $summary += "`nA restart is recommended."
    Write-Log $summary.Replace("`n", " ")
    [System.Windows.Forms.MessageBox]::Show($summary, "Storm Tweaks", "OK", "Information") | Out-Null
}
$btnApply.Add_Click($applyPendingHandler)
$btnApplyLabel.Add_Click($applyPendingHandler)

Update-TweakFilter
Update-RecoBanner
Update-PendingApply


# ===========================================================================
# PAGE : PROFILES
# ===========================================================================
# Un profil = un ensemble coherent de reglages Windows applique d'un coup.
# Tout est filtre par la configuration reelle (voir $script:sysProfile) : un
# reglage jamais applique est un reglage qui ne peut pas destabiliser le PC.
#
# Limite assumee : les reglages du pilote graphique (Panneau NVIDIA, AMD
# Software) ne sont PAS modifiables depuis PowerShell. NVIDIA ne fournit
# aucune ligne de commande pour cela, uniquement le SDK NVAPI qui demande un
# programme compile. On applique donc uniquement les reglages Windows, y
# compris ceux lies au GPU qui, eux, sont accessibles (planification GPU
# materielle par exemple).
# ---------------------------------------------------------------------------
$pageProfiles = New-Object System.Windows.Forms.Panel
$pageProfiles.Location = New-Object System.Drawing.Point(0, 0)
$pageProfiles.Size = New-Object System.Drawing.Size(916, 700)
$pageProfiles.BackColor = $colBg
$pageProfiles.Visible = $false
$pageContainer.Controls.Add($pageProfiles)
$pages["profiles"] = $pageProfiles

$profTitle = New-Object System.Windows.Forms.Label
$profTitle.Text = "Profiles"
$profTitle.Font = $fontH1
$profTitle.ForeColor = $colText
$profTitle.AutoSize = $true
$profTitle.Location = New-Object System.Drawing.Point(24, 20)
$pageProfiles.Controls.Add($profTitle)

$profSub = New-Object System.Windows.Forms.Label
$profSub.Text = "Applies a coherent set of Windows settings in one click, limited to what this PC supports"
$profSub.Font = $fontSub
$profSub.ForeColor = $colSubText
$profSub.AutoSize = $true
$profSub.Location = New-Object System.Drawing.Point(24, 58)
$pageProfiles.Controls.Add($profSub)

# Pastille alignee sur le titre : l'information la plus attendue de la page
# doit se voir sans avoir a parcourir les cartes.
$profActivePill = New-Object System.Windows.Forms.Panel
$profActivePill.Location = New-Object System.Drawing.Point(600, 22)
$profActivePill.Size = New-Object System.Drawing.Size(292, 34)
$profActivePill.BackColor = $colBg
$pageProfiles.Controls.Add($profActivePill)
$profActiveFill = @{ Color = $colCard }
$profActiveBorder = @{ Color = $colBorder }
Add-SmoothRounded $profActivePill 10 $profActiveFill "" $null $null $profActiveBorder

$profActiveLabel = New-Object System.Windows.Forms.Label
$profActiveLabel.Text = "Checking..."
$profActiveLabel.Font = $fontBtn
$profActiveLabel.ForeColor = $colSubText
$profActiveLabel.BackColor = [System.Drawing.Color]::Transparent
$profActiveLabel.AutoSize = $false
$profActiveLabel.Size = New-Object System.Drawing.Size(292, 32)
$profActiveLabel.TextAlign = "MiddleCenter"
$profActiveLabel.Location = New-Object System.Drawing.Point(0, 0)
$profActivePill.Controls.Add($profActiveLabel)

$profHwLabel = New-Object System.Windows.Forms.Label
$profHwLabel.Font = $fontDesc
$profHwLabel.ForeColor = $colOnTeal
$profHwLabel.AutoSize = $false
$profHwLabel.AutoEllipsis = $true
$profHwLabel.Size = New-Object System.Drawing.Size(868, 18)
$profHwLabel.TextAlign = "MiddleLeft"
$profHwLabel.Location = New-Object System.Drawing.Point(24, 86)
$pageProfiles.Controls.Add($profHwLabel)

$profGpuNote = New-Object System.Windows.Forms.Label
$profGpuNote.Text = "Note: driver panel settings (NVIDIA Control Panel, AMD Software) cannot be changed from PowerShell - only Windows-side settings are applied."
$profGpuNote.Font = $fontDesc
$profGpuNote.ForeColor = $colSubText
$profGpuNote.AutoSize = $false
$profGpuNote.AutoEllipsis = $true
$profGpuNote.Size = New-Object System.Drawing.Size(868, 18)
$profGpuNote.TextAlign = "MiddleLeft"
$profGpuNote.Location = New-Object System.Drawing.Point(24, 106)
$pageProfiles.Controls.Add($profGpuNote)

# ---- Plans d'alimentation (GUID : identiques dans toutes les langues) ----
$script:PLAN_BALANCED = "381b4222-f694-41f0-9685-ff5bb260df2e"
$script:PLAN_HIGHPERF = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"

function Get-StormUltimatePlanGuid {
    $ultTemplate = "e9a42b02-d5df-448d-aa00-03f14749eb61"
    $rx = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
    $tag = "Storm Ultimate Performance"
    $listText = (powercfg -list) -join "`n"
    if ($listText -notmatch [regex]::Escape($tag)) {
        $target = $null
        if ($listText -match [regex]::Escape($ultTemplate)) {
            $target = $ultTemplate
        } else {
            $dupText = (powercfg -duplicatescheme $ultTemplate 2>&1) -join "`n"
            if ($dupText -match $rx) { $target = $matches[0] }
        }
        if ($target) { powercfg -changename $target $tag | Out-Null }
    }
    $line = (powercfg -list) | Where-Object { $_ -match [regex]::Escape($tag) } | Select-Object -First 1
    if ($line -and ($line -match $rx)) { return $matches[0] }
    return $null
}

# Sur portable on ne force jamais un plan sans bridage : autonomie et
# temperature en patiraient sans gain reel de FPS.
function Set-ProfilePowerPlan([string]$mode, $hw) {
    if ($mode -eq "max" -and -not $hw.IsLaptop) {
        $g = Get-StormUltimatePlanGuid
        if ($g) { powercfg -setactive $g; return "Ultimate Performance power plan" }
        powercfg -setactive $script:PLAN_HIGHPERF
        return "High performance power plan"
    }
    if ($mode -eq "high") {
        powercfg -setactive $script:PLAN_HIGHPERF
        return "High performance power plan"
    }
    powercfg -setactive $script:PLAN_BALANCED
    return "Balanced power plan"
}

# ---- Sauvegarde / restauration des reglages touches par les profils ------
# Liste unique : elle sert a la fois de sauvegarde et de restauration, donc
# rien ne peut etre modifie sans etre restaurable.
$script:profileManaged = @(
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'; Name = 'VisualFXSetting'; Type = 'DWord' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize';     Name = 'EnableTransparency'; Type = 'DWord' },
    @{ Path = 'HKCU:\Software\Microsoft\GameBar';                                       Name = 'AutoGameModeEnabled'; Type = 'DWord' },
    @{ Path = 'HKCU:\System\GameConfigStore';                                           Name = 'GameDVR_Enabled'; Type = 'DWord' },
    @{ Path = 'HKCU:\System\GameConfigStore';                                           Name = 'GameDVR_FSEBehaviorMode'; Type = 'DWord' },
    @{ Path = 'HKCU:\System\GameConfigStore';                                           Name = 'GameDVR_HonorUserFSEBehaviorMode'; Type = 'DWord' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications';       Name = 'ToastEnabled'; Type = 'DWord' },
    @{ Path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications'; Name = 'GlobalUserDisabled'; Type = 'DWord' },
    @{ Path = 'HKCU:\Control Panel\Desktop';                                            Name = 'MenuShowDelay'; Type = 'String' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'NetworkThrottlingIndex'; Type = 'DWord' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'; Name = 'SystemResponsiveness'; Type = 'DWord' },
    @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers';                 Name = 'HwSchMode'; Type = 'DWord' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'GPU Priority'; Type = 'DWord' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Priority'; Type = 'DWord' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'Scheduling Category'; Type = 'String' },
    @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games'; Name = 'SFIO Priority'; Type = 'String' }
)

# Services reellement basculees par les profils. Elles sont sauvegardees au
# meme titre que les cles de registre : rien n'est desactive sans pouvoir
# etre remis exactement dans son etat d'origine.
$script:profileServices = @('SysMain', 'WSearch', 'DiagTrack')
$script:profileBackupPath = Join-Path $env:LOCALAPPDATA "StormTweaks\profile-backup.json"

# Ecrite une seule fois : la sauvegarde doit contenir l'etat AVANT tout
# profil, pas l'etat laisse par le profil precedent.
function Backup-ProfileSettings {
    if (Test-Path $script:profileBackupPath) { return $false }
    $dir = Split-Path $script:profileBackupPath
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
    $data = @{ Values = @(); PowerPlan = $null; Services = @() }
    foreach ($m in $script:profileManaged) {
        $data.Values += @{ Path = $m.Path; Name = $m.Name; Type = $m.Type; Value = (Get-RegValueOrNull $m.Path $m.Name) }
    }
    foreach ($svcName in $script:profileServices) {
        try {
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            $data.Services += @{ Name = $svcName; StartType = [string]$svc.StartType }
        } catch {}
    }
    try {
        $rx = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
        $act = (powercfg -getactivescheme) -join "`n"
        if ($act -match $rx) { $data.PowerPlan = $matches[0] }
    } catch {}
    ($data | ConvertTo-Json -Depth 6) | Set-Content -Path $script:profileBackupPath -Encoding UTF8
    return $true
}

function Restore-ProfileSettings {
    if (-not (Test-Path $script:profileBackupPath)) { return "No backup found." }
    $data = Get-Content -Path $script:profileBackupPath -Raw | ConvertFrom-Json
    $n = 0
    foreach ($v in $data.Values) {
        try {
            Set-RegValueOrRemove $v.Path $v.Name $v.Value $v.Type
            $n++
        } catch {
            Write-Log "Restore error on $($v.Name): $($_.Exception.Message)"
        }
    }
    if ($data.PowerPlan) { try { powercfg -setactive $data.PowerPlan } catch {} }
    $s = 0
    if ($data.Services) {
        foreach ($sv in $data.Services) {
            try {
                Set-Service -Name $sv.Name -StartupType $sv.StartType -ErrorAction Stop
                if ($sv.StartType -ne "Disabled") { Start-Service -Name $sv.Name -ErrorAction SilentlyContinue }
                $s++
            } catch {
                Write-Log "Restore error on service $($sv.Name): $($_.Exception.Message)"
            }
        }
    }
    return "$n setting(s) and $s service(s) restored to their pre-profile values."
}

function New-StormRestorePoint {
    try {
        # Antislash construit explicitement : "$env:SystemDrive\" se termine sur
        # le guillemet et cette forme est ambigue a relire.
        $sysRoot = "$env:SystemDrive" + [string][char]92
        Enable-ComputerRestore -Drive $sysRoot -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Storm Tweaks - before profile" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        return "Restore point created"
    } catch {
        # Windows n'autorise qu'un point toutes les 24 h par defaut, et la
        # protection systeme peut etre desactivee : ce n'est pas bloquant,
        # la sauvegarde JSON des reglages reste faite.
        return "Restore point skipped ($($_.Exception.Message.Split([char]10)[0]))"
    }
}

# ---- Definition des trois profils ---------------------------------------
# Chaque Apply recoit le profil materiel et renvoie la liste de ce qui a
# vraiment ete fait, pour que le resume affiche corresponde a la realite.
$stormProfiles = @(
    @{ Key = "competitive"; Title = "Competitive"; Icon = "bolt"; Accent = $colPurple
       Signature = @{ SystemResponsiveness = 0; GlobalUserDisabled = 1; VisualFXSetting = 2; AutoGameModeEnabled = 1 }
       Desc = "For FPS games. Minimal input lag: background activity, indexing and telemetry stopped, scheduling pushed to the game."
       Apply = {
            param($hw)
            $done = @()
            $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            $games = "$mm\Tasks\Games"

            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
            $done += "Windows animations and transparency disabled"

            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
            Set-RegValueOrRemove 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
            Set-RegValueOrRemove 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 2
            Set-RegValueOrRemove 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 1
            $done += "Game Mode on, background recording and fullscreen layer off"

            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 0
            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1
            Set-RegValueOrRemove 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '0' 'String'
            $done += "Notifications and background apps disabled"

            # SystemResponsiveness 0 : tout le temps CPU reserve aux taches
            # multimedia est rendu au jeu. Ideal en competitif, mauvais pour
            # l'encodage (voir le profil Streaming).
            Set-RegValueOrRemove $mm 'NetworkThrottlingIndex' -1
            Set-RegValueOrRemove $mm 'SystemResponsiveness' 0
            Set-RegValueOrRemove $games 'GPU Priority' 8
            Set-RegValueOrRemove $games 'Priority' 6
            Set-RegValueOrRemove $games 'Scheduling Category' 'High' 'String'
            Set-RegValueOrRemove $games 'SFIO Priority' 'High' 'String'
            $done += "Network throttling removed, game scheduling priority raised"

            if (($hw.GpuNames -join " ") -match 'NVIDIA|AMD|Radeon|Arc') {
                Set-RegValueOrRemove 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
                $done += "Hardware-accelerated GPU scheduling enabled"
            } else {
                $done += "GPU scheduling skipped (no dedicated GPU detected)"
            }

            $done += (Set-ProfileServices @{ SysMain = "Disabled"; WSearch = "Disabled"; DiagTrack = "Disabled" })
            $done += (Set-ProfilePowerPlan "max" $hw)
            return $done
       }
    },
    @{ Key = "streaming"; Title = "Streaming"; Icon = "display"; Accent = $colOn
       Signature = @{ SystemResponsiveness = 10; GlobalUserDisabled = 0; VisualFXSetting = 2; AutoGameModeEnabled = 1 }
       Desc = "For OBS, Discord and browser alongside the game. Keeps encoder and background apps running, favours stability over raw latency."
       Apply = {
            param($hw)
            $done = @()
            $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            $games = "$mm\Tasks\Games"

            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2
            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0
            $done += "Windows animations disabled (frees GPU for the encoder)"

            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1
            Set-RegValueOrRemove 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0
            $done += "Game Mode on, Windows background recording off (OBS handles capture)"

            # Notifications coupees pour ne pas apparaitre a l'antenne, mais
            # les apps d'arriere-plan restent actives : OBS, Discord et le
            # navigateur en dependent.
            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 0
            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 0
            Set-RegValueOrRemove 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '200' 'String'
            $done += "Notifications off, background apps kept running for OBS and Discord"

            # SystemResponsiveness 10 (et non 0) : l'encodage et l'audio
            # passent par MMCSS. Tout donner au jeu ferait sauter des images
            # a l'encodage et cracher le son.
            Set-RegValueOrRemove $mm 'NetworkThrottlingIndex' -1
            Set-RegValueOrRemove $mm 'SystemResponsiveness' 10
            Set-RegValueOrRemove $games 'GPU Priority' 8
            Set-RegValueOrRemove $games 'Priority' 2
            Set-RegValueOrRemove $games 'Scheduling Category' 'Medium' 'String'
            Set-RegValueOrRemove $games 'SFIO Priority' 'Normal' 'String'
            $done += "Scheduling balanced between game and encoder, upload throttling removed"

            if (($hw.GpuNames -join " ") -match 'NVIDIA|AMD|Radeon|Arc') {
                Set-RegValueOrRemove 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode' 2
                $done += "Hardware-accelerated GPU scheduling enabled"
            } else {
                $done += "GPU scheduling skipped (no dedicated GPU detected)"
            }

            # L'indexation reste active : on cherche des fichiers en direct.
            # Seule la telemetrie est coupee.
            $done += (Set-ProfileServices @{ SysMain = "Automatic"; WSearch = "Automatic"; DiagTrack = "Disabled" })
            $done += (Set-ProfilePowerPlan "high" $hw)
            return $done
       }
    },
    @{ Key = "daily"; Title = "Daily"; Icon = "gear"; Accent = $colGreen
       Signature = @{ SystemResponsiveness = 20; GlobalUserDisabled = 0; VisualFXSetting = 1; AutoGameModeEnabled = 0 }
       Desc = "Everyday use. Full Windows experience, quiet and power-efficient, every service back to its normal behaviour."
       Apply = {
            param($hw)
            $done = @()
            $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
            $games = "$mm\Tasks\Games"

            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 1
            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 1
            $done += "Full Windows visual effects and transparency restored"

            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 0
            Set-RegValueOrRemove 'HKCU:\System\GameConfigStore' 'GameDVR_FSEBehaviorMode' 0
            Set-RegValueOrRemove 'HKCU:\System\GameConfigStore' 'GameDVR_HonorUserFSEBehaviorMode' 0
            $done += "Game Mode off, Windows default fullscreen behaviour"

            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications' 'ToastEnabled' 1
            Set-RegValueOrRemove 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 0
            Set-RegValueOrRemove 'HKCU:\Control Panel\Desktop' 'MenuShowDelay' '200' 'String'
            $done += "Notifications and background apps enabled"

            Set-RegValueOrRemove $mm 'NetworkThrottlingIndex' 10
            Set-RegValueOrRemove $mm 'SystemResponsiveness' 20
            Set-RegValueOrRemove $games 'GPU Priority' 8
            Set-RegValueOrRemove $games 'Priority' 2
            Set-RegValueOrRemove $games 'Scheduling Category' 'Medium' 'String'
            Set-RegValueOrRemove $games 'SFIO Priority' 'Normal' 'String'
            $done += "Windows default multimedia and network values restored"

            $done += (Set-ProfileServices @{ SysMain = "Automatic"; WSearch = "Automatic"; DiagTrack = "Automatic" })
            $done += (Set-ProfilePowerPlan "balanced" $hw)
            return $done
       }
    }
)

# Bascule les services d'un profil. Un service absent ou protege est ignore
# sans faire echouer le profil : mieux vaut un reglage en moins qu'un profil
# a moitie applique.
function Set-ProfileServices([hashtable]$wanted) {
    $changed = @()
    foreach ($svcName in $wanted.Keys) {
        $target = $wanted[$svcName]
        try {
            $svc = Get-Service -Name $svcName -ErrorAction Stop
            if ([string]$svc.StartType -eq $target) { continue }
            Set-Service -Name $svcName -StartupType $target -ErrorAction Stop
            if ($target -eq "Disabled") {
                Stop-Service -Name $svcName -Force -ErrorAction SilentlyContinue
            } else {
                Start-Service -Name $svcName -ErrorAction SilentlyContinue
            }
            $changed += "$svcName -> $target"
        } catch {
            Write-Log "Service $svcName could not be changed: $($_.Exception.Message)"
        }
    }
    if ($changed.Count -eq 0) { return "Services already in the expected state" }
    return "Services: " + ($changed -join ", ")
}

# Avertissement affiche AVANT d'appliquer, pas apres : l'utilisateur decide
# en connaissance de cause.
# Lit les quatre valeurs qui distinguent les profils entre eux et renvoie la
# cle du profil correspondant, ou $null si l'etat ne correspond a aucun.
# SystemResponsiveness suffirait presque seul (0 / 10 / 20), les trois autres
# servent a detecter qu'un reglage a ete change depuis.
function Get-ActiveProfileKey {
    $mm = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    $current = @{
        SystemResponsiveness = (Get-RegValueOrNull $mm 'SystemResponsiveness')
        GlobalUserDisabled   = (Get-RegValueOrNull 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled')
        VisualFXSetting      = (Get-RegValueOrNull 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting')
        AutoGameModeEnabled  = (Get-RegValueOrNull 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled')
    }
    foreach ($p in $stormProfiles) {
        if (-not $p.ContainsKey('Signature')) { continue }
        $match = $true
        foreach ($k in $p.Signature.Keys) {
            if ($null -eq $current[$k] -or [int]$current[$k] -ne [int]$p.Signature[$k]) { $match = $false; break }
        }
        if ($match) { return $p.Key }
    }
    return $null
}

$script:profileCards = @{}

function Update-ActiveProfile {
    $active = Get-ActiveProfileKey

    foreach ($k in $script:profileCards.Keys) {
        $c = $script:profileCards[$k]
        $isActive = ($k -eq $active)
        $c.Badge.Visible = $isActive
        $c.Border.Color = if ($isActive) { $c.Accent } else { $colCard }
        $c.ButtonLabel.Text = if ($isActive) { "Re-apply" } else { "Apply Profile" }
        $c.Card.Invalidate()
        $c.Button.Invalidate()
    }

    if ($active) {
        $p = $stormProfiles | Where-Object { $_.Key -eq $active } | Select-Object -First 1
        $profActiveLabel.Text = "Active profile: $($p.Title)"
        $profActiveFill.Color = $p.Accent
        $profActiveLabel.ForeColor = [System.Drawing.Color]::White
    } else {
        $profActiveLabel.Text = "No profile active - custom settings"
        $profActiveFill.Color = $colCard
        $profActiveLabel.ForeColor = $colSubText
    }
    $profActivePill.Invalidate()
}

function Get-ProfileWarning($key, $hw) {
    $hasGpu = (($hw.GpuNames -join " ") -match 'NVIDIA|AMD|Radeon|Arc')
    if ($key -eq "competitive") {
        if ($hw.IsLaptop) {
            return "A laptop was detected.`nThe unthrottled power plan will not be forced, to protect battery life and temperatures.`nSearch indexing and SysMain will be disabled (reversible)."
        }
        return "Search indexing, SysMain and telemetry will be disabled.`nAll of them are restored by Restore Original Settings."
    }
    if ($key -eq "streaming") {
        if (-not $hasGpu) {
            return "No dedicated GPU detected.`nHardware encoding may be unavailable, so streaming will fall back to the CPU."
        }
        if ($hw.RamGB -lt 16) {
            return "$($hw.RamGB) GB of RAM detected.`nStreaming while gaming is comfortable from 16 GB upwards; expect some tension below that."
        }
    }
    return $null
}

function Update-ProfileHardwareLabel {
    $hw = $script:sysProfile
    $gpu = if ($hw.GpuNames.Count -gt 0) { $hw.GpuNames -join ", " } else { "unknown GPU" }
    $drive = if ($hw.SystemDriveIsSSD) { "SSD" } else { "HDD" }
    $form = if ($hw.IsLaptop) { "laptop" } else { "desktop" }
    $profHwLabel.Text = "Detected: $($hw.CpuCores) cores * $($hw.RamGB) GB RAM * $gpu * $drive * $form * $($hw.FreeDiskPercent)% free"
}
Update-ProfileHardwareLabel

function New-ProfileCard($x, $prof) {
    $card = New-Object System.Windows.Forms.Panel
    $card.Location = New-Object System.Drawing.Point($x, 132)
    $card.Size = New-Object System.Drawing.Size(278, 248)
    $card.BackColor = $colBg
    $cardFill = @{ Color = $colCard }
    # La bordure passe a la couleur du profil quand il est actif.
    $cardBorder = @{ Color = $colCard }
    Add-SmoothRounded $card 12 $cardFill "" $null $null $cardBorder
    $pageProfiles.Controls.Add($card)

    # Pastille ACTIVE, masquee tant que le profil ne correspond pas.
    $activeBadge = New-Object System.Windows.Forms.Panel
    $activeBadge.Size = New-Object System.Drawing.Size(62, 20)
    $activeBadge.Location = New-Object System.Drawing.Point(14, 14)
    $activeBadge.BackColor = $colCard
    $card.Controls.Add($activeBadge)
    $activeBadgeFill = @{ Color = $prof.Accent }
    $activeBadgeText = @{ Color = [System.Drawing.Color]::White }
    Add-SmoothRounded $activeBadge 6 $activeBadgeFill "ACTIVE" (Get-AppFont "SemiBold" 7) $activeBadgeText
    $activeBadge.Visible = $false

    $badge = New-Object System.Windows.Forms.Panel
    $badge.Size = New-Object System.Drawing.Size(48, 48)
    $badge.Location = New-Object System.Drawing.Point(115, 16)
    $badge.BackColor = [System.Drawing.Color]::Transparent
    $card.Controls.Add($badge)
    Add-TweakIcon $badge $prof.Icon $prof.Accent

    $t = New-Object System.Windows.Forms.Label
    $t.Text = $prof.Title
    $t.Font = $fontH2
    $t.ForeColor = $colText
    $t.BackColor = [System.Drawing.Color]::Transparent
    $t.AutoSize = $false
    $t.Size = New-Object System.Drawing.Size(278, 24)
    $t.TextAlign = "MiddleCenter"
    $t.Location = New-Object System.Drawing.Point(0, 72)
    $card.Controls.Add($t)

    $d = New-Object System.Windows.Forms.Label
    $d.Text = $prof.Desc
    $d.Font = $fontDesc
    $d.ForeColor = $colSubText
    $d.BackColor = [System.Drawing.Color]::Transparent
    $d.AutoSize = $false
    $d.Size = New-Object System.Drawing.Size(246, 88)
    $d.TextAlign = "TopCenter"
    $d.Location = New-Object System.Drawing.Point(16, 102)
    $card.Controls.Add($d)

    $btn = New-Object System.Windows.Forms.Panel
    $btn.Size = New-Object System.Drawing.Size(180, 36)
    $btn.Location = New-Object System.Drawing.Point(49, 198)
    $btn.BackColor = $colCard
    $btn.Cursor = "Hand"
    $card.Controls.Add($btn)
    $btnFill = @{ Color = $prof.Accent }
    $btnText = @{ Color = [System.Drawing.Color]::White }
    Add-SmoothRounded $btn 9 $btnFill "" $fontBtn $btnText

    $btnLabel = New-Object System.Windows.Forms.Label
    $btnLabel.Text = "Apply Profile"
    $btnLabel.Font = $fontBtn
    $btnLabel.ForeColor = [System.Drawing.Color]::White
    $btnLabel.BackColor = [System.Drawing.Color]::Transparent
    $btnLabel.AutoSize = $false
    $btnLabel.Size = New-Object System.Drawing.Size(180, 34)
    $btnLabel.TextAlign = "MiddleCenter"
    $btnLabel.Location = New-Object System.Drawing.Point(0, 0)
    $btnLabel.Cursor = "Hand"
    $btn.Controls.Add($btnLabel)

    $script:profileCards[$prof.Key] = @{
        Card = $card; Border = $cardBorder; Badge = $activeBadge
        Button = $btn; ButtonLabel = $btnLabel; Accent = $prof.Accent
    }
    $btn.Add_MouseEnter({ $btnFill.Color = $colPurpleHover; $btn.Invalidate() }.GetNewClosure())
    $btn.Add_MouseLeave({ $btnFill.Color = $prof.Accent; $btn.Invalidate() }.GetNewClosure())

    $profileClick = {
        $hw = Get-SysProfileRef
        $warn = Get-ProfileWarning $prof.Key $hw
        $msg = "Apply the '$($prof.Title)' profile?"
        if ($warn) { $msg += "`n`n$warn" }
        $msg += "`n`nA restore point will be created first (this can take a minute)."
        $confirm = [System.Windows.Forms.MessageBox]::Show($msg, "Storm Tweaks", "YesNo", "Question")
        if ($confirm -ne "Yes") { return }

        $form.Cursor = "WaitCursor"
        $summary = @()
        try {
            Write-Log "Applying profile '$($prof.Title)'..."
            $rp = New-StormRestorePoint
            Write-Log $rp
            $summary += $rp

            if (Backup-ProfileSettings) {
                Write-Log "Original settings saved (first profile applied on this PC)."
                $summary += "Original settings saved"
            } else {
                $summary += "Original settings already saved"
            }

            $done = & $prof.Apply $hw
            foreach ($line in $done) {
                Write-Log "  $line"
                $summary += $line
            }
            Write-Log "Profile '$($prof.Title)' applied."
        } catch {
            Write-Log "Profile error: $($_.Exception.Message)"
            $summary += "Error: $($_.Exception.Message)"
        }
        $form.Cursor = "Default"

        # L'etat affiche est recalcule depuis Windows, pas suppose.
        Update-ActiveProfile

        [System.Windows.Forms.MessageBox]::Show(
            ($summary -join "`n") + "`n`nA restart is recommended.",
            "Profile applied", "OK", "Information") | Out-Null
    }.GetNewClosure()
    $btn.Add_Click($profileClick)
    $btnLabel.Add_Click($profileClick)

    $card.Add_MouseEnter({ $cardFill.Color = $colCardHover; $card.Invalidate() }.GetNewClosure())
    $card.Add_MouseLeave({ $cardFill.Color = $colCard; $card.Invalidate() }.GetNewClosure())
}

$profX = 24
foreach ($p in $stormProfiles) {
    New-ProfileCard $profX $p
    $profX += 294
}
Update-ActiveProfile

# ---- Boutons bas de page -------------------------------------------------
$btnAnalyze = New-Object System.Windows.Forms.Panel
$btnAnalyze.Size = New-Object System.Drawing.Size(160, 38)
$btnAnalyze.Location = New-Object System.Drawing.Point(24, 398)
$btnAnalyze.BackColor = $colBg
$btnAnalyze.Cursor = "Hand"
$pageProfiles.Controls.Add($btnAnalyze)
$btnAnalyzeFill = @{ Color = $colCard }
$btnAnalyzeText = @{ Color = $colText }
$btnAnalyzeBorder = @{ Color = $colBorder }
Add-SmoothRounded $btnAnalyze 9 $btnAnalyzeFill "Analyze PC" $fontBtn $btnAnalyzeText $btnAnalyzeBorder
$btnAnalyze.Add_MouseEnter({ $btnAnalyzeFill.Color = $colCardHover; $btnAnalyze.Invalidate() }.GetNewClosure())
$btnAnalyze.Add_MouseLeave({ $btnAnalyzeFill.Color = $colCard; $btnAnalyze.Invalidate() }.GetNewClosure())
$btnAnalyze.Add_Click({
    $form.Cursor = "WaitCursor"
    $script:sysProfile = Get-SystemProfile
    Update-ProfileHardwareLabel
    $form.Cursor = "Default"
    $hw = $script:sysProfile
    Write-Log "----- Hardware analysis -----"
    Write-Log "CPU: $($hw.CpuName) ($($hw.CpuCores) cores)"
    Write-Log "RAM: $($hw.RamGB) GB"
    Write-Log "GPU: $(if ($hw.GpuNames.Count -gt 0) { $hw.GpuNames -join ', ' } else { 'not detected' })"
    Write-Log "System drive: $(if ($hw.SystemDriveIsSSD) { 'SSD' } else { 'HDD' }) - $($hw.FreeDiskPercent)% free"
    Write-Log "Form factor: $(if ($hw.IsLaptop) { 'laptop' } else { 'desktop' })"
    foreach ($p in $stormProfiles) {
        $w = Get-ProfileWarning $p.Key $hw
        if ($w) { Write-Log "$($p.Title): $($w.Split([char]10)[0])" }
        else { Write-Log "$($p.Title): fully supported" }
    }
    Write-Log "----- End of analysis -----"
})

$btnProfRestore = New-Object System.Windows.Forms.Panel
$btnProfRestore.Size = New-Object System.Drawing.Size(230, 38)
$btnProfRestore.Location = New-Object System.Drawing.Point(200, 398)
$btnProfRestore.BackColor = $colBg
$btnProfRestore.Cursor = "Hand"
$pageProfiles.Controls.Add($btnProfRestore)
$btnProfRestoreFill = @{ Color = $colCard }
$btnProfRestoreText = @{ Color = $colGold }
$btnProfRestoreBorder = @{ Color = $colBorder }
Add-SmoothRounded $btnProfRestore 9 $btnProfRestoreFill "Restore Original Settings" $fontBtn $btnProfRestoreText $btnProfRestoreBorder
$btnProfRestore.Add_MouseEnter({ $btnProfRestoreFill.Color = $colCardHover; $btnProfRestore.Invalidate() }.GetNewClosure())
$btnProfRestore.Add_MouseLeave({ $btnProfRestoreFill.Color = $colCard; $btnProfRestore.Invalidate() }.GetNewClosure())
$btnProfRestore.Add_Click({
    if (-not (Test-Path $script:profileBackupPath)) {
        [System.Windows.Forms.MessageBox]::Show("No profile has been applied on this PC yet, so there is nothing to restore.", "Storm Tweaks", "OK", "Warning") | Out-Null
        return
    }
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Restore every setting touched by the profiles back to the values captured before the first profile was applied?",
        "Restore Original Settings", "YesNo", "Question")
    if ($confirm -ne "Yes") { return }
    $form.Cursor = "WaitCursor"
    try {
        $res = Restore-ProfileSettings
        Write-Log $res
        Update-ActiveProfile
        [System.Windows.Forms.MessageBox]::Show("$res`n`nA restart is recommended.", "Storm Tweaks", "OK", "Information") | Out-Null
    } catch {
        Write-Log "Restore error: $($_.Exception.Message)"
    }
    $form.Cursor = "Default"
})


# ---------------------------------------------------------------------------
# Carte "GPU Drivers" - LECTURE SEULE
# ---------------------------------------------------------------------------
# Cette carte ne modifie rien. Elle lit des versions et ouvre des pages web.
# Le "nettoyage type DDU" a ete volontairement retire : supprimer un pilote
# graphique ne peut pas etre sans risque, quel que soit le soin apporte au
# code. Les chemins de secours officiels (option d'installation propre des
# installeurs NVIDIA/AMD, puis DDU en dernier recours) sont eprouves sur des
# millions de machines ; les reproduire ici n'aurait apporte aucun gain, mais
# un risque bien reel. Storm Tweaks se contente donc d'y orienter.
# ---------------------------------------------------------------------------

function Get-GpuDriverInfo {
    $list = @()
    try {
        $ctrls = Get-CimInstance Win32_VideoController -ErrorAction Stop | Where-Object { $_.Name }
    } catch { return $list }

    foreach ($c in $ctrls) {
        $vendor = if ($c.Name -match 'NVIDIA') { "NVIDIA" }
                  elseif ($c.Name -match 'AMD|Radeon') { "AMD" }
                  elseif ($c.Name -match 'Intel') { "Intel" }
                  else { "Other" }
        $marketing = $null

        if ($vendor -eq "NVIDIA") {
            try {
                $v = & nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>$null | Select-Object -First 1
                if ($v) { $marketing = $v.Trim() }
            } catch {}
            if (-not $marketing -and $c.DriverVersion) {
                # Windows expose 32.0.15.7602 ; la version commerciale NVIDIA
                # correspond aux 5 derniers chiffres : 57602 -> 576.02
                $digits = ($c.DriverVersion -replace '\D', '')
                if ($digits.Length -ge 5) {
                    $tail = $digits.Substring($digits.Length - 5)
                    $marketing = $tail.Substring(0, 3) + "." + $tail.Substring(3, 2)
                }
            }
        } elseif ($vendor -eq "AMD") {
            try {
                $cn = Get-ItemProperty "HKLM:\SOFTWARE\AMD\CN" -ErrorAction SilentlyContinue
                if ($cn -and $cn.Catalyst_Version) { $marketing = "Adrenalin $($cn.Catalyst_Version)" }
            } catch {}
            if (-not $marketing) {
                try {
                    $keys = Get-ChildItem "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}" -ErrorAction Stop
                    foreach ($k in $keys) {
                        $rs = (Get-ItemProperty -Path $k.PSPath -Name "RadeonSoftwareVersion" -ErrorAction SilentlyContinue).RadeonSoftwareVersion
                        if ($rs) { $marketing = "Adrenalin $rs"; break }
                    }
                } catch {}
            }
        }

        $dateTxt = ""
        try { if ($c.DriverDate) { $dateTxt = ([datetime]$c.DriverDate).ToString("yyyy-MM-dd") } } catch {}

        $list += @{
            Name = $c.Name; Vendor = $vendor
            DriverVersion = $c.DriverVersion
            Marketing = $marketing; DriverDate = $dateTxt
        }
    }
    return $list
}

function Get-VendorDownloadUrl($vendor) {
    switch ($vendor) {
        "NVIDIA" { return "https://www.nvidia.com/Download/index.aspx" }
        "AMD"    { return "https://www.amd.com/en/support" }
        "Intel"  { return "https://www.intel.com/content/www/us/en/download-center/home.html" }
    }
    return "https://www.google.com/search?q=graphics+driver+download"
}

$drvCard = New-Object System.Windows.Forms.Panel
$drvCard.Location = New-Object System.Drawing.Point(24, 446)
$drvCard.Size = New-Object System.Drawing.Size(868, 144)
$drvCard.BackColor = $colBg
$drvCardFill = @{ Color = $colCard }
Add-SmoothRounded $drvCard 12 $drvCardFill
$pageProfiles.Controls.Add($drvCard)

$drvTitle = New-Object System.Windows.Forms.Label
$drvTitle.Text = "GPU Drivers"
$drvTitle.Font = $fontH2
$drvTitle.ForeColor = $colText
$drvTitle.BackColor = [System.Drawing.Color]::Transparent
$drvTitle.AutoSize = $true
$drvTitle.Location = New-Object System.Drawing.Point(18, 10)
$drvCard.Controls.Add($drvTitle)

$drvLine1 = New-Object System.Windows.Forms.Label
$drvLine1.Font = $fontDesc
$drvLine1.ForeColor = $colText
$drvLine1.BackColor = [System.Drawing.Color]::Transparent
$drvLine1.AutoSize = $false
$drvLine1.AutoEllipsis = $true
$drvLine1.Size = New-Object System.Drawing.Size(560, 17)
$drvLine1.TextAlign = "MiddleLeft"
$drvLine1.Location = New-Object System.Drawing.Point(18, 40)
$drvCard.Controls.Add($drvLine1)

$drvLine2 = New-Object System.Windows.Forms.Label
$drvLine2.Font = $fontDesc
$drvLine2.ForeColor = $colSubText
$drvLine2.BackColor = [System.Drawing.Color]::Transparent
$drvLine2.AutoSize = $false
$drvLine2.AutoEllipsis = $true
$drvLine2.Size = New-Object System.Drawing.Size(560, 17)
$drvLine2.TextAlign = "MiddleLeft"
$drvLine2.Location = New-Object System.Drawing.Point(18, 59)
$drvCard.Controls.Add($drvLine2)

$drvNote = New-Object System.Windows.Forms.Label
$drvNote.Text = "Read-only: Storm Tweaks never installs or removes a driver." + [string][char]10 + "No official API publishes the latest version, so the check opens the vendor download page."
$drvNote.Font = $fontDesc
$drvNote.ForeColor = $colSubText
$drvNote.BackColor = [System.Drawing.Color]::Transparent
$drvNote.AutoSize = $false
$drvNote.Size = New-Object System.Drawing.Size(560, 36)
$drvNote.TextAlign = "TopLeft"
$drvNote.Location = New-Object System.Drawing.Point(18, 90)
$drvCard.Controls.Add($drvNote)

$script:gpuDrivers = @()
function Update-DriverCard {
    $script:gpuDrivers = @(Get-GpuDriverInfo)
    if ($script:gpuDrivers.Count -eq 0) {
        $drvLine1.Text = "No display adapter detected."
        $drvLine2.Text = ""
        return
    }
    $rows = @()
    foreach ($d in $script:gpuDrivers) {
        $ver = if ($d.Marketing) { "$($d.Marketing)  ($($d.DriverVersion))" } else { $d.DriverVersion }
        $dt = if ($d.DriverDate) { "  -  $($d.DriverDate)" } else { "" }
        $rows += "$($d.Vendor): $($d.Name)  -  driver $ver$dt"
    }
    $drvLine1.Text = $rows[0]
    $drvLine2.Text = if ($rows.Count -gt 1) { $rows[1] } else { "" }
}
Update-DriverCard

$btnDrvCheck = New-Object System.Windows.Forms.Panel
$btnDrvCheck.Size = New-Object System.Drawing.Size(180, 34)
$btnDrvCheck.Location = New-Object System.Drawing.Point(666, 38)
$btnDrvCheck.BackColor = $colCard
$btnDrvCheck.Cursor = "Hand"
$drvCard.Controls.Add($btnDrvCheck)
$btnDrvCheckFill = @{ Color = $colPurple }
$btnDrvCheckText = @{ Color = [System.Drawing.Color]::White }
Add-SmoothRounded $btnDrvCheck 9 $btnDrvCheckFill "Check for update" $fontBtn $btnDrvCheckText
$btnDrvCheck.Add_MouseEnter({ $btnDrvCheckFill.Color = $colPurpleHover; $btnDrvCheck.Invalidate() }.GetNewClosure())
$btnDrvCheck.Add_MouseLeave({ $btnDrvCheckFill.Color = $colPurple; $btnDrvCheck.Invalidate() }.GetNewClosure())
$btnDrvCheck.Add_Click({
    Update-DriverCard
    if ($script:gpuDrivers.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("No display adapter detected.", "Storm Tweaks", "OK", "Warning") | Out-Null
        return
    }
    $d = $script:gpuDrivers[0]
    $ver = if ($d.Marketing) { $d.Marketing } else { $d.DriverVersion }
    $msg = "Installed: $($d.Vendor) $ver"
    if ($d.DriverDate) { $msg += " (released $($d.DriverDate))" }
    $msg += "`n`nThere is no official API that reports the latest available version, so Storm Tweaks cannot compare automatically."
    $msg += "`n`nOpen the official $($d.Vendor) download page to check?"
    $r = [System.Windows.Forms.MessageBox]::Show($msg, "Driver version", "YesNo", "Information")
    if ($r -eq "Yes") {
        Write-Log "Opening $($d.Vendor) driver download page (installed: $ver)"
        Start-Process (Get-VendorDownloadUrl $d.Vendor)
    }
})

# Remplace l'ancien bouton "Clean driver". N'execute rien : explique la
# procedure officielle et ouvre une page si l'utilisateur le demande.
$btnDrvHelp = New-Object System.Windows.Forms.Panel
$btnDrvHelp.Size = New-Object System.Drawing.Size(180, 34)
$btnDrvHelp.Location = New-Object System.Drawing.Point(666, 80)
$btnDrvHelp.BackColor = $colCard
$btnDrvHelp.Cursor = "Hand"
$drvCard.Controls.Add($btnDrvHelp)
$btnDrvHelpFill = @{ Color = $colCard }
$btnDrvHelpText = @{ Color = $colText }
$btnDrvHelpBorder = @{ Color = $colBorder }
Add-SmoothRounded $btnDrvHelp 9 $btnDrvHelpFill "Clean install help" $fontBtn $btnDrvHelpText $btnDrvHelpBorder
$btnDrvHelp.Add_MouseEnter({ $btnDrvHelpFill.Color = $colCardHover; $btnDrvHelp.Invalidate() }.GetNewClosure())
$btnDrvHelp.Add_MouseLeave({ $btnDrvHelpFill.Color = $colCard; $btnDrvHelp.Invalidate() }.GetNewClosure())
$btnDrvHelp.Add_Click({
    $vendor = if ($script:gpuDrivers.Count -gt 0) { $script:gpuDrivers[0].Vendor } else { "your GPU" }
    $steps = switch ($vendor) {
        "NVIDIA" { "1. Download the driver from nvidia.com.`n2. Run the installer, choose Custom (Advanced).`n3. Tick 'Perform a clean installation'.`n4. Restart." }
        "AMD"    { "1. Download AMD Software from amd.com.`n2. Run the installer.`n3. Choose 'Factory Reset' when offered.`n4. Restart." }
        "Intel"  { "1. Download the driver from intel.com.`n2. Run the installer.`n3. Tick the clean installation option.`n4. Restart." }
        default  { "Download the driver from the vendor site and use its clean installation option." }
    }
    $msg = "Storm Tweaks does not remove drivers, on purpose: deleting a graphics driver cannot be made risk-free, and a failed removal leaves the PC on a basic display."
    $msg += "`n`nThe official clean install is safer and does the same job:`n`n$steps"
    $msg += "`n`nOnly if that is not enough, DDU (Display Driver Uninstaller) is the established tool for a deep clean in Safe Mode."
    $msg += "`n`nOpen the $vendor download page?"
    $r = [System.Windows.Forms.MessageBox]::Show($msg, "Clean driver install", "YesNo", "Information")
    if ($r -eq "Yes") { Start-Process (Get-VendorDownloadUrl $vendor) }
})


# ===========================================================================
# PAGE : STARTUP
# ===========================================================================
# Liste ce qui se lance avec Windows et permet de l'activer ou non.
#
# Aucune entree n'est jamais supprimee. On ecrit uniquement dans
# StartupApproved, le mecanisme que le Gestionnaire des taches utilise
# lui-meme pour son onglet Demarrage : un premier octet a 2 signifie active,
# a 3 desactive, suivi de l'horodatage. Reactiver revient donc simplement a
# reecrire cet octet, et le Gestionnaire des taches affichera exactement le
# meme etat que cette page.
# ---------------------------------------------------------------------------
$pageStartup = New-Object System.Windows.Forms.Panel
$pageStartup.Location = New-Object System.Drawing.Point(0, 0)
$pageStartup.Size = New-Object System.Drawing.Size(916, 700)
$pageStartup.BackColor = $colBg
$pageStartup.Visible = $false
$pageContainer.Controls.Add($pageStartup)
$pages["startup"] = $pageStartup

$stTitle = New-Object System.Windows.Forms.Label
$stTitle.Text = "Startup"
$stTitle.Font = $fontH1
$stTitle.ForeColor = $colText
$stTitle.AutoSize = $true
$stTitle.Location = New-Object System.Drawing.Point(24, 20)
$pageStartup.Controls.Add($stTitle)

$stSub = New-Object System.Windows.Forms.Label
$stSub.Text = "Programs that launch with Windows. Nothing is ever deleted - entries are only switched off."
$stSub.Font = $fontSub
$stSub.ForeColor = $colSubText
$stSub.AutoSize = $true
$stSub.Location = New-Object System.Drawing.Point(24, 58)
$pageStartup.Controls.Add($stSub)

$stCount = New-Object System.Windows.Forms.Label
$stCount.Font = $fontDesc
$stCount.ForeColor = $colSubText
$stCount.AutoSize = $false
$stCount.Size = New-Object System.Drawing.Size(500, 16)
$stCount.TextAlign = "MiddleLeft"
$stCount.Location = New-Object System.Drawing.Point(24, 86)
$pageStartup.Controls.Add($stCount)

$stFlow = New-Object System.Windows.Forms.FlowLayoutPanel
$stFlow.Location = New-Object System.Drawing.Point(24, 112)
$stFlow.Size = New-Object System.Drawing.Size(868, 564)
$stFlow.BackColor = $colBg
$stFlow.AutoScroll = $true
$stFlow.FlowDirection = "TopDown"
$stFlow.WrapContents = $false
$pageStartup.Controls.Add($stFlow)

# ---- Lecture des entrees -------------------------------------------------
# Chaque source a sa propre cle StartupApproved : c'est la que Windows
# memorise l'etat active/desactive.
function Get-StartupSources {
    return @(
        @{ Type = "Reg";    Run = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
           Approved = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"; Scope = "User" },
        @{ Type = "Reg";    Run = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
           Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"; Scope = "All users" },
        @{ Type = "Reg";    Run = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"
           Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run32"; Scope = "All users (32-bit)" },
        @{ Type = "Folder"; Run = [Environment]::GetFolderPath("Startup")
           Approved = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"; Scope = "User folder" },
        @{ Type = "Folder"; Run = [Environment]::GetFolderPath("CommonStartup")
           Approved = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\StartupFolder"; Scope = "Shared folder" }
    )
}

function Test-StartupEnabled($approvedPath, $name) {
    try {
        $item = Get-ItemProperty -Path $approvedPath -Name $name -ErrorAction Stop
        $bytes = $item.$name
        if ($null -eq $bytes -or $bytes.Length -eq 0) { return $true }
        # 2 et 6 = active ; 3 et 7 = desactive par l'utilisateur.
        return ($bytes[0] -eq 2 -or $bytes[0] -eq 6)
    } catch {
        # Pas d'entree StartupApproved : Windows considere le programme actif.
        return $true
    }
}

function Set-StartupEnabled($approvedPath, $name, [bool]$enabled) {
    if (-not (Test-Path $approvedPath)) { New-Item -Path $approvedPath -Force | Out-Null }
    if ($enabled) {
        $bytes = [byte[]](2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    } else {
        # Meme format que le Gestionnaire des taches : 03 puis la date de
        # desactivation sur 8 octets.
        $stamp = [BitConverter]::GetBytes((Get-Date).ToFileTime())
        $bytes = [byte[]](3, 0, 0, 0) + $stamp
    }
    New-ItemProperty -Path $approvedPath -Name $name -Value $bytes -PropertyType Binary -Force | Out-Null
}

function Get-StartupEntries {
    $entries = @()
    foreach ($s in (Get-StartupSources)) {
        if ($s.Type -eq "Reg") {
            if (-not (Test-Path $s.Run)) { continue }
            try {
                $props = Get-ItemProperty -Path $s.Run -ErrorAction Stop
                foreach ($p in $props.PSObject.Properties) {
                    if ($p.Name -like "PS*") { continue }
                    $entries += @{
                        Name = $p.Name; Command = [string]$p.Value; Scope = $s.Scope
                        Approved = $s.Approved; Enabled = (Test-StartupEnabled $s.Approved $p.Name)
                    }
                }
            } catch {}
        } else {
            if ([string]::IsNullOrEmpty($s.Run) -or -not (Test-Path $s.Run)) { continue }
            try {
                foreach ($f in (Get-ChildItem -Path $s.Run -File -ErrorAction Stop)) {
                    if ($f.Name -eq "desktop.ini") { continue }
                    $entries += @{
                        Name = $f.Name; Command = $f.FullName; Scope = $s.Scope
                        Approved = $s.Approved; Enabled = (Test-StartupEnabled $s.Approved $f.Name)
                    }
                }
            } catch {}
        }
    }
    return ($entries | Sort-Object { $_.Name })
}

# ---- Construction de la liste -------------------------------------------
function Build-StartupList {
    $stFlow.SuspendLayout()
    $stFlow.Controls.Clear()

    $entries = @(Get-StartupEntries)
    $off = @($entries | Where-Object { -not $_.Enabled }).Count
    $stCount.Text = "$($entries.Count) program(s) registered - $off disabled"

    if ($entries.Count -eq 0) {
        $empty = New-Object System.Windows.Forms.Label
        $empty.Text = "Nothing launches with Windows."
        $empty.Font = $fontSub
        $empty.ForeColor = $colSubText
        $empty.AutoSize = $true
        $stFlow.Controls.Add($empty)
        $stFlow.ResumeLayout()
        return
    }

    foreach ($entry in $entries) {
        $row = New-Object System.Windows.Forms.Panel
        $row.Size = New-Object System.Drawing.Size(828, 52)
        $row.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
        $row.BackColor = $colBg
        $rowFill = @{ Color = $colCard }
        Add-SmoothRounded $row 10 $rowFill
        $stFlow.Controls.Add($row)

        $nameLbl = New-Object System.Windows.Forms.Label
        $nameLbl.Text = $entry.Name
        $nameLbl.Font = Get-AppFont "SemiBold" 9
        $nameLbl.ForeColor = if ($entry.Enabled) { $colText } else { $colSubText }
        $nameLbl.BackColor = [System.Drawing.Color]::Transparent
        $nameLbl.AutoSize = $false
        $nameLbl.AutoEllipsis = $true
        $nameLbl.Size = New-Object System.Drawing.Size(580, 18)
        $nameLbl.TextAlign = "MiddleLeft"
        $nameLbl.Location = New-Object System.Drawing.Point(16, 7)
        $row.Controls.Add($nameLbl)

        $pathLbl = New-Object System.Windows.Forms.Label
        $pathLbl.Text = "$($entry.Scope)  -  $($entry.Command)"
        $pathLbl.Font = $fontDesc
        $pathLbl.ForeColor = $colSubText
        $pathLbl.BackColor = [System.Drawing.Color]::Transparent
        $pathLbl.AutoSize = $false
        $pathLbl.AutoEllipsis = $true
        $pathLbl.Size = New-Object System.Drawing.Size(580, 16)
        $pathLbl.TextAlign = "MiddleLeft"
        $pathLbl.Location = New-Object System.Drawing.Point(16, 27)
        $row.Controls.Add($pathLbl)

        $btn = New-Object System.Windows.Forms.Panel
        $btn.Size = New-Object System.Drawing.Size(124, 32)
        $btn.Location = New-Object System.Drawing.Point(688, 10)
        $btn.BackColor = $colCard
        $btn.Cursor = "Hand"
        $row.Controls.Add($btn)
        $btnFill = @{ Color = $colCard }
        $btnText = @{ Color = $colSubText }
        $btnBorder = @{ Color = $colBorder }
        Add-SmoothRounded $btn 8 $btnFill "" $fontToggle $btnText $btnBorder

        $btnLbl = New-Object System.Windows.Forms.Label
        $btnLbl.Font = $fontToggle
        $btnLbl.BackColor = [System.Drawing.Color]::Transparent
        $btnLbl.AutoSize = $false
        $btnLbl.Size = New-Object System.Drawing.Size(124, 32)
        $btnLbl.TextAlign = "MiddleCenter"
        $btnLbl.Location = New-Object System.Drawing.Point(0, 0)
        $btnLbl.Cursor = "Hand"
        $btn.Controls.Add($btnLbl)

        # Etat porte par le bouton : rien a rechercher au moment du clic.
        $btn.Tag = @{ Entry = $entry; Fill = $btnFill; Text = $btnText; Border = $btnBorder; Label = $btnLbl; Name = $nameLbl }

        $applyVisual = {
            param($b)
            $d = $b.Tag
            if ($d.Entry.Enabled) {
                $d.Fill.Color = $colCard; $d.Border.Color = $colGreen
                $d.Text.Color = $colGreen; $d.Label.ForeColor = $colGreen
                $d.Label.Text = "Enabled"
                $d.Name.ForeColor = $colText
            } else {
                $d.Fill.Color = $colCard; $d.Border.Color = $colBorder
                $d.Text.Color = $colSubText; $d.Label.ForeColor = $colSubText
                $d.Label.Text = "Disabled"
                $d.Name.ForeColor = $colSubText
            }
            $b.Invalidate()
        }
        & $applyVisual $btn

        $clickHandler = {
            $d = $btn.Tag
            $want = -not $d.Entry.Enabled
            try {
                Set-StartupEnabled $d.Entry.Approved $d.Entry.Name $want
                $d.Entry.Enabled = $want
                $btn.Tag = $d
                & $applyVisual $btn
                $word = if ($want) { "enabled" } else { "disabled" }
                Write-Log "Startup: $($d.Entry.Name) $word"
                $all = @(Get-StartupEntries)
                $offNow = @($all | Where-Object { -not $_.Enabled }).Count
                $stCount.Text = "$($all.Count) program(s) registered - $offNow disabled"
            } catch {
                Write-Log "Startup: could not change $($d.Entry.Name) - $($_.Exception.Message)"
            }
        }.GetNewClosure()

        $btn.Add_Click($clickHandler)
        $btnLbl.Add_Click($clickHandler)

        $row.Add_MouseEnter({ $rowFill.Color = $colCardHover; $row.Invalidate() }.GetNewClosure())
        $row.Add_MouseLeave({ $rowFill.Color = $colCard; $row.Invalidate() }.GetNewClosure())
    }

    $stFlow.ResumeLayout()
}

$btnStRefresh = New-Object System.Windows.Forms.Panel
$btnStRefresh.Size = New-Object System.Drawing.Size(150, 34)
$btnStRefresh.Location = New-Object System.Drawing.Point(742, 24)
$btnStRefresh.BackColor = $colBg
$btnStRefresh.Cursor = "Hand"
$pageStartup.Controls.Add($btnStRefresh)
$btnStRefreshFill = @{ Color = $colCard }
$btnStRefreshText = @{ Color = $colText }
$btnStRefreshBorder = @{ Color = $colBorder }
Add-SmoothRounded $btnStRefresh 9 $btnStRefreshFill "Refresh" $fontBtn $btnStRefreshText $btnStRefreshBorder
$btnStRefresh.Add_MouseEnter({ $btnStRefreshFill.Color = $colCardHover; $btnStRefresh.Invalidate() }.GetNewClosure())
$btnStRefresh.Add_MouseLeave({ $btnStRefreshFill.Color = $colCard; $btnStRefresh.Invalidate() }.GetNewClosure())
$btnStRefresh.Add_Click({ Build-StartupList })

Build-StartupList

# ===========================================================================
# PAGE : REGLAGES
# ===========================================================================
$pageSettings = New-Object System.Windows.Forms.Panel
$pageSettings.Location = New-Object System.Drawing.Point(0, 0)
$pageSettings.Size = New-Object System.Drawing.Size(916, 700)
$pageSettings.BackColor = $colBg
$pageSettings.Visible = $false
$pageContainer.Controls.Add($pageSettings)
$pages["settings"] = $pageSettings

$setTitle = New-Object System.Windows.Forms.Label
$setTitle.Text = "Settings"
$setTitle.Font = $fontH1
$setTitle.ForeColor = $colText
$setTitle.AutoSize = $true
$setTitle.Location = New-Object System.Drawing.Point(24, 24)
$pageSettings.Controls.Add($setTitle)

$restoreCard = New-Object System.Windows.Forms.Panel
$restoreCard.Location = New-Object System.Drawing.Point(24, 90)
$restoreCard.Size = New-Object System.Drawing.Size(848, 90)
$restoreCard.BackColor = $colBg
$pageSettings.Controls.Add($restoreCard)
$restoreCardFill = @{ Color = $colCard }
Add-SmoothRounded $restoreCard 10 $restoreCardFill

$restoreTitle = New-Object System.Windows.Forms.Label
$restoreTitle.Text = "Restore Default Settings"
$restoreTitle.Font = $fontH2
$restoreTitle.ForeColor = $colText
$restoreTitle.BackColor = [System.Drawing.Color]::Transparent
$restoreTitle.AutoSize = $true
$restoreTitle.Location = New-Object System.Drawing.Point(18, 14)
$restoreCard.Controls.Add($restoreTitle)

$restoreDesc = New-Object System.Windows.Forms.Label
$restoreDesc.Text = "Undoes the main applied tweaks and returns Windows to a standard state"
$restoreDesc.Font = $fontDesc
$restoreDesc.ForeColor = $colSubText
$restoreDesc.BackColor = [System.Drawing.Color]::Transparent
$restoreDesc.AutoSize = $true
$restoreDesc.Location = New-Object System.Drawing.Point(18, 38)
$restoreCard.Controls.Add($restoreDesc)

$btnRestore = New-Object System.Windows.Forms.Panel
$btnRestore.Size = New-Object System.Drawing.Size(150, 36)
$btnRestore.Location = New-Object System.Drawing.Point(680, 27)
$btnRestore.BackColor = $colCard
$btnRestore.Cursor = "Hand"
$restoreCard.Controls.Add($btnRestore)
$btnRestoreFill = @{ Color = $colCard }
$btnRestoreText = @{ Color = $colText }
$btnRestoreBorder = @{ Color = $colBorder }
Add-SmoothRounded $btnRestore 9 $btnRestoreFill "Restore" $fontBtn $btnRestoreText $btnRestoreBorder
$btnRestore.Add_MouseEnter({ $btnRestoreFill.Color = $colCardHover; $btnRestore.Invalidate() }.GetNewClosure())
$btnRestore.Add_MouseLeave({ $btnRestoreFill.Color = $colCard; $btnRestore.Invalidate() }.GetNewClosure())

$btnRestore.Add_Click({
    Write-Log "Restoring default settings..."
    try {
        foreach ($tweak in $tweaks) {
            if ($tweak.ContainsKey('Undo')) {
                try {
                    & $tweak.Undo
                    $proof = ""
                    if ($tweak.ContainsKey('Verify')) {
                        try { $proof = "  ==>  " + (& $tweak.Verify) } catch { $proof = "" }
                    }
                    Write-Log "Restored - $($tweak.Name)$proof"
                } catch { Write-Log "Restore error '$($tweak.Name)': $($_.Exception.Message)" }
            }
        }
        foreach ($toggleBtn in $toggles) {
            $d = $toggleBtn.Tag
            $newState = $false
            if ($d.Tweak.ContainsKey('Check')) {
                try { $newState = [bool](& $d.Tweak.Check) } catch { $newState = $false }
            }
            $d.State = $newState
            $d.Applied = $newState
            $toggleBtn.Tag = $d
            Set-ToggleVisual $toggleBtn $newState
        }
        Update-PendingApply
        Update-RecoBanner
        Write-Log "Settings restored. Restart your PC to fully apply the changes."
        [System.Windows.Forms.MessageBox]::Show("Settings restored.`nA restart is recommended.", "Storm Tweaks", "OK", "Information") | Out-Null
    } catch {
        Write-Log "Error during restore: $($_.Exception.Message)"
    }
})

# ---- Carte "Reset Settings" : restaure exactement les valeurs Windows
# capturees au tout premier lancement (avant tout tweak), au lieu de valeurs
# par defaut generiques comme le bouton "Restore" ci-dessus. ----
$resetCard = New-Object System.Windows.Forms.Panel
$resetCard.Location = New-Object System.Drawing.Point(24, 190)
$resetCard.Size = New-Object System.Drawing.Size(848, 90)
$resetCard.BackColor = $colBg
$pageSettings.Controls.Add($resetCard)
$resetCardFill = @{ Color = $colCard }
Add-SmoothRounded $resetCard 10 $resetCardFill

$resetTitle = New-Object System.Windows.Forms.Label
$resetTitle.Text = "Reset Settings"
$resetTitle.Font = $fontH2
$resetTitle.ForeColor = $colText
$resetTitle.BackColor = [System.Drawing.Color]::Transparent
$resetTitle.AutoSize = $true
$resetTitle.Location = New-Object System.Drawing.Point(18, 14)
$resetCard.Controls.Add($resetTitle)

$resetDesc = New-Object System.Windows.Forms.Label
$resetDesc.Text = "Restores the exact Windows settings captured on first launch, before any tweak"
$resetDesc.Font = $fontDesc
$resetDesc.ForeColor = $colSubText
$resetDesc.BackColor = [System.Drawing.Color]::Transparent
$resetDesc.AutoSize = $true
$resetDesc.Location = New-Object System.Drawing.Point(18, 38)
$resetCard.Controls.Add($resetDesc)

$btnReset = New-Object System.Windows.Forms.Panel
$btnReset.Size = New-Object System.Drawing.Size(150, 36)
$btnReset.Location = New-Object System.Drawing.Point(680, 27)
$btnReset.BackColor = $colCard
$btnReset.Cursor = "Hand"
$resetCard.Controls.Add($btnReset)
$btnResetFill = @{ Color = $colCard }
$btnResetText = @{ Color = $colGold }
$btnResetBorder = @{ Color = $colBorder }
Add-SmoothRounded $btnReset 9 $btnResetFill "Reset Settings" $fontBtn $btnResetText $btnResetBorder
$btnReset.Add_MouseEnter({ $btnResetFill.Color = $colCardHover; $btnReset.Invalidate() }.GetNewClosure())
$btnReset.Add_MouseLeave({ $btnResetFill.Color = $colCard; $btnReset.Invalidate() }.GetNewClosure())

$btnReset.Add_Click({
    if (-not (Test-Path $script:baselinePath)) {
        Write-Log "No restore point found (baseline.json is missing)."
        [System.Windows.Forms.MessageBox]::Show("No restore point was found on this PC.`nIt should have been created automatically the first time Storm Tweaks was launched.", "Storm Tweaks", "OK", "Warning") | Out-Null
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "This will restore Windows settings exactly as they were the first time Storm Tweaks was launched on this PC.`nContinue?",
        "Reset Settings", "YesNo", "Question")
    if ($confirm -ne "Yes") { return }

    Write-Log "Restoring the first-launch restore point..."
    try {
        $raw = Get-Content -Path $script:baselinePath -Raw | ConvertFrom-Json
    } catch {
        Write-Log "Error reading the restore point: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show("The restore point file is unreadable or corrupted.", "Storm Tweaks", "OK", "Error") | Out-Null
        return
    }

    foreach ($tweak in $tweaks) {
        if (-not $tweak.ContainsKey('Restore')) { continue }
        $stored = $raw.($tweak.Name)
        if ($null -eq $stored) {
            Write-Log "Skipped (not in restore point) - $($tweak.Name)"
            continue
        }
        try {
            & $tweak.Restore $stored
            Write-Log "Reset - $($tweak.Name)"
        } catch {
            Write-Log "Reset error '$($tweak.Name)': $($_.Exception.Message)"
        }
    }

    # Rafraichit chaque interrupteur pour refleter l'etat reellement restaure
    foreach ($toggleBtn in $toggles) {
        $data = $toggleBtn.Tag
        $newState = $false
        if ($data.Tweak.ContainsKey('Check')) {
            try { $newState = [bool](& $data.Tweak.Check) } catch { $newState = $false }
        }
        $data.State = $newState
        $data.Applied = $newState
        $toggleBtn.Tag = $data
        Set-ToggleVisual $toggleBtn $newState
    }
    Update-PendingApply
    Update-RecoBanner

    Write-Log "Settings reset to the first-launch restore point. Restart your PC to fully apply the changes."
    [System.Windows.Forms.MessageBox]::Show("Windows settings have been reset to your first-launch restore point.`nA restart is recommended.", "Storm Tweaks", "OK", "Information") | Out-Null
})

# ---- Carte "Diagnostics" : affiche, pour chaque tweak, ce que Windows
# repond reellement (Check + Verify). Sert a identifier precisement un tweak
# qui ne "prend" pas, au lieu de deviner. ----
$diagCard = New-Object System.Windows.Forms.Panel
$diagCard.Location = New-Object System.Drawing.Point(24, 300)
$diagCard.Size = New-Object System.Drawing.Size(848, 90)
$diagCard.BackColor = $colBg
$pageSettings.Controls.Add($diagCard)
$diagCardFill = @{ Color = $colCard }
Add-SmoothRounded $diagCard 10 $diagCardFill

$diagTitle = New-Object System.Windows.Forms.Label
$diagTitle.Text = "Diagnostics"
$diagTitle.Font = $fontH2
$diagTitle.ForeColor = $colText
$diagTitle.BackColor = [System.Drawing.Color]::Transparent
$diagTitle.AutoSize = $true
$diagTitle.Location = New-Object System.Drawing.Point(18, 14)
$diagCard.Controls.Add($diagTitle)

$diagDesc = New-Object System.Windows.Forms.Label
$diagDesc.Text = "Reports what Windows actually returns for every tweak, into the log below"
$diagDesc.Font = $fontDesc
$diagDesc.ForeColor = $colSubText
$diagDesc.BackColor = [System.Drawing.Color]::Transparent
$diagDesc.AutoSize = $true
$diagDesc.Location = New-Object System.Drawing.Point(18, 38)
$diagCard.Controls.Add($diagDesc)

$btnDiag = New-Object System.Windows.Forms.Panel
$btnDiag.Size = New-Object System.Drawing.Size(150, 36)
$btnDiag.Location = New-Object System.Drawing.Point(680, 27)
$btnDiag.BackColor = $colCard
$btnDiag.Cursor = "Hand"
$diagCard.Controls.Add($btnDiag)
$btnDiagFill = @{ Color = $colCard }
$btnDiagText = @{ Color = $colText }
$btnDiagBorder = @{ Color = $colBorder }
Add-SmoothRounded $btnDiag 9 $btnDiagFill "Run diagnostics" $fontBtn $btnDiagText $btnDiagBorder
$btnDiag.Add_MouseEnter({ $btnDiagFill.Color = $colCardHover; $btnDiag.Invalidate() }.GetNewClosure())
$btnDiag.Add_MouseLeave({ $btnDiagFill.Color = $colCard; $btnDiag.Invalidate() }.GetNewClosure())

$btnDiag.Add_Click({
    Write-Log "----- Diagnostics -----"
    foreach ($tweak in $tweaks) {
        $chk = "?"
        if ($tweak.ContainsKey('Check')) {
            try { $chk = if ([bool](& $tweak.Check)) { "ON " } else { "OFF" } } catch { $chk = "ERR" }
        }
        $ver = ""
        if ($tweak.ContainsKey('Verify')) {
            try { $ver = (& $tweak.Verify) } catch { $ver = "Verify failed: $($_.Exception.Message)" }
        }
        Write-Log "[$chk] $($tweak.Name)  |  $ver"
    }
    Write-Log "----- End of diagnostics -----"
})

# ---- Carte "Startup" -----------------------------------------------------
$startCard = New-Object System.Windows.Forms.Panel
$startCard.Location = New-Object System.Drawing.Point(24, 500)
$startCard.Size = New-Object System.Drawing.Size(848, 96)
$startCard.BackColor = $colBg
$pageSettings.Controls.Add($startCard)
$startCardFill = @{ Color = $colCard }
Add-SmoothRounded $startCard 10 $startCardFill

$startTitle = New-Object System.Windows.Forms.Label
$startTitle.Text = "On launch"
$startTitle.Font = $fontH2
$startTitle.ForeColor = $colText
$startTitle.BackColor = [System.Drawing.Color]::Transparent
$startTitle.AutoSize = $true
$startTitle.Location = New-Object System.Drawing.Point(18, 10)
$startCard.Controls.Add($startTitle)

$startDesc = New-Object System.Windows.Forms.Label
$startDesc.Text = "Disable Windows background apps every time Storm Tweaks starts"
$startDesc.Font = $fontDesc
$startDesc.ForeColor = $colSubText
$startDesc.BackColor = [System.Drawing.Color]::Transparent
$startDesc.AutoSize = $false
$startDesc.Size = New-Object System.Drawing.Size(560, 16)
$startDesc.TextAlign = "MiddleLeft"
$startDesc.Location = New-Object System.Drawing.Point(18, 36)
$startCard.Controls.Add($startDesc)

$startNote = New-Object System.Windows.Forms.Label
$startNote.Text = "Store (UWP) apps only - Discord, Steam and other desktop programs are not affected"
$startNote.Font = $fontDesc
$startNote.ForeColor = $colSubText
$startNote.BackColor = [System.Drawing.Color]::Transparent
$startNote.AutoSize = $false
$startNote.AutoEllipsis = $true
$startNote.Size = New-Object System.Drawing.Size(560, 16)
$startNote.TextAlign = "MiddleLeft"
$startNote.Location = New-Object System.Drawing.Point(18, 52)
$startNote.Size = New-Object System.Drawing.Size(560, 14)
$startCard.Controls.Add($startNote)

$btnStartToggle = New-Object System.Windows.Forms.Panel
$btnStartToggle.Size = New-Object System.Drawing.Size(150, 28)
$btnStartToggle.Location = New-Object System.Drawing.Point(680, 32)
$btnStartToggle.BackColor = $colCard
$btnStartToggle.Cursor = "Hand"
$startCard.Controls.Add($btnStartToggle)
$btnStartFill = @{ Color = $colCard }
$btnStartText = @{ Color = $colSubText }
$btnStartBorder = @{ Color = $colBorder }
Add-SmoothRounded $btnStartToggle 9 $btnStartFill "" $fontBtn $btnStartText $btnStartBorder

$btnStartLabel = New-Object System.Windows.Forms.Label
$btnStartLabel.Font = $fontBtn
$btnStartLabel.BackColor = [System.Drawing.Color]::Transparent
$btnStartLabel.AutoSize = $false
$btnStartLabel.Size = New-Object System.Drawing.Size(150, 28)
$btnStartLabel.TextAlign = "MiddleCenter"
$btnStartLabel.Location = New-Object System.Drawing.Point(0, 0)
$btnStartLabel.Cursor = "Hand"
$btnStartToggle.Controls.Add($btnStartLabel)

function Update-StartupToggleVisual {
    if ($script:startupCfg.AutoDisableBackgroundApps) {
        $btnStartFill.Color = $colGreen
        $btnStartBorder.Color = $colGreen
        $btnStartLabel.Text = "Enabled"
        $btnStartLabel.ForeColor = [System.Drawing.Color]::Black
    } else {
        $btnStartFill.Color = $colCard
        $btnStartBorder.Color = $colBorder
        $btnStartLabel.Text = "Disabled"
        $btnStartLabel.ForeColor = $colSubText
    }
    $btnStartToggle.Invalidate()
}
Update-StartupToggleVisual

# Desactiver l'option remet aussi le reglage Windows a sa valeur normale :
# sinon on laisserait derriere soi une modification que l'utilisateur croit
# annulee.
$startupToggleHandler = {
    $new = -not $script:startupCfg.AutoDisableBackgroundApps
    $script:startupCfg.AutoDisableBackgroundApps = $new
    Save-StartupConfig
    try {
        Set-BackgroundAppsDisabled $new
        if ($new) {
            Write-Log "Startup option enabled: background apps disabled now and at every launch."
        } else {
            Write-Log "Startup option disabled: background apps re-enabled."
        }
    } catch {
        Write-Log "Could not change the background apps setting: $($_.Exception.Message)"
    }
    Update-StartupToggleVisual
}
$btnStartToggle.Add_Click($startupToggleHandler)
$btnStartLabel.Add_Click($startupToggleHandler)

# Deuxieme ligne de la meme carte : verification automatique des mises a jour.
$updDesc = New-Object System.Windows.Forms.Label
$updDesc.Text = "Check for a new Storm Tweaks version at launch"
$updDesc.Font = $fontDesc
$updDesc.ForeColor = $colSubText
$updDesc.BackColor = [System.Drawing.Color]::Transparent
$updDesc.AutoSize = $false
$updDesc.Size = New-Object System.Drawing.Size(500, 16)
$updDesc.TextAlign = "MiddleLeft"
$updDesc.Location = New-Object System.Drawing.Point(18, 70)
$startCard.Controls.Add($updDesc)

$btnUpdAuto = New-Object System.Windows.Forms.Panel
$btnUpdAuto.Size = New-Object System.Drawing.Size(104, 28)
$btnUpdAuto.Location = New-Object System.Drawing.Point(726, 64)
$btnUpdAuto.BackColor = $colCard
$btnUpdAuto.Cursor = "Hand"
$startCard.Controls.Add($btnUpdAuto)
$btnUpdAutoFill = @{ Color = $colCard }
$btnUpdAutoText = @{ Color = $colSubText }
$btnUpdAutoBorder = @{ Color = $colBorder }
Add-SmoothRounded $btnUpdAuto 9 $btnUpdAutoFill "" $fontBtn $btnUpdAutoText $btnUpdAutoBorder

$btnUpdAutoLabel = New-Object System.Windows.Forms.Label
$btnUpdAutoLabel.Font = $fontBtn
$btnUpdAutoLabel.BackColor = [System.Drawing.Color]::Transparent
$btnUpdAutoLabel.AutoSize = $false
$btnUpdAutoLabel.Size = New-Object System.Drawing.Size(104, 28)
$btnUpdAutoLabel.TextAlign = "MiddleCenter"
$btnUpdAutoLabel.Location = New-Object System.Drawing.Point(0, 0)
$btnUpdAutoLabel.Cursor = "Hand"
$btnUpdAuto.Controls.Add($btnUpdAutoLabel)

$btnUpdNow = New-Object System.Windows.Forms.Panel
$btnUpdNow.Size = New-Object System.Drawing.Size(108, 28)
$btnUpdNow.Location = New-Object System.Drawing.Point(610, 64)
$btnUpdNow.BackColor = $colCard
$btnUpdNow.Cursor = "Hand"
$startCard.Controls.Add($btnUpdNow)
$btnUpdNowFill = @{ Color = $colPurple }
$btnUpdNowText = @{ Color = [System.Drawing.Color]::White }
Add-SmoothRounded $btnUpdNow 9 $btnUpdNowFill "Check now" $fontBtn $btnUpdNowText
$btnUpdNow.Add_MouseEnter({ $btnUpdNowFill.Color = $colPurpleHover; $btnUpdNow.Invalidate() }.GetNewClosure())
$btnUpdNow.Add_MouseLeave({ $btnUpdNowFill.Color = $colPurple; $btnUpdNow.Invalidate() }.GetNewClosure())
# $false = mode non silencieux : un "vous etes a jour" s'affiche aussi,
# sinon un clic sans nouvelle version semblerait n'avoir rien fait.
$btnUpdNow.Add_Click({ Invoke-UpdateCheck $false })

function Update-AutoCheckVisual {
    if ($script:startupCfg.AutoCheckUpdates) {
        $btnUpdAutoFill.Color = $colGreen; $btnUpdAutoBorder.Color = $colGreen
        $btnUpdAutoLabel.Text = "Enabled"; $btnUpdAutoLabel.ForeColor = [System.Drawing.Color]::Black
    } else {
        $btnUpdAutoFill.Color = $colCard; $btnUpdAutoBorder.Color = $colBorder
        $btnUpdAutoLabel.Text = "Disabled"; $btnUpdAutoLabel.ForeColor = $colSubText
    }
    $btnUpdAuto.Invalidate()
}
Update-AutoCheckVisual

$autoCheckHandler = {
    $script:startupCfg.AutoCheckUpdates = -not $script:startupCfg.AutoCheckUpdates
    # Reactiver la verification remet aussi a zero la version ignoree :
    # sinon elle resterait masquee sans que l'utilisateur comprenne pourquoi.
    if ($script:startupCfg.AutoCheckUpdates) { $script:startupCfg.SkippedVersion = "" }
    Save-StartupConfig
    Update-AutoCheckVisual
    Write-Log "Automatic update check: $(if ($script:startupCfg.AutoCheckUpdates) { 'enabled' } else { 'disabled' })"
}
$btnUpdAuto.Add_Click($autoCheckHandler)
$btnUpdAutoLabel.Add_Click($autoCheckHandler)

$aboutCard = New-Object System.Windows.Forms.Panel
$aboutCard.Location = New-Object System.Drawing.Point(24, 410)
$aboutCard.Size = New-Object System.Drawing.Size(848, 90)
$aboutCard.BackColor = $colBg
$aboutCard.Cursor = "Hand"
$pageSettings.Controls.Add($aboutCard)
$aboutCardFill = @{ Color = $colCard }
Add-SmoothRounded $aboutCard 10 $aboutCardFill

$aboutTitle = New-Object System.Windows.Forms.Label
$aboutTitle.Text = "About"
$aboutTitle.Font = $fontH2
$aboutTitle.ForeColor = $colText
$aboutTitle.BackColor = [System.Drawing.Color]::Transparent
$aboutTitle.AutoSize = $true
$aboutTitle.Location = New-Object System.Drawing.Point(18, 14)
$aboutCard.Controls.Add($aboutTitle)

$aboutDesc = New-Object System.Windows.Forms.Label
$aboutDesc.Text = "Storm Tweaks $($script:appVersion)`r`nClick for more information"
$aboutDesc.Font = $fontDesc
$aboutDesc.ForeColor = $colSubText
$aboutDesc.BackColor = [System.Drawing.Color]::Transparent
$aboutDesc.AutoSize = $true
$aboutDesc.Location = New-Object System.Drawing.Point(18, 38)
$aboutCard.Controls.Add($aboutDesc)

$aboutChevron = New-Object System.Windows.Forms.Label
$aboutChevron.Text = [string][char]0xE76C
$aboutChevron.Font = $fontIcon
$aboutChevron.ForeColor = $colSubText
$aboutChevron.BackColor = [System.Drawing.Color]::Transparent
$aboutChevron.Size = New-Object System.Drawing.Size(30, 30)
$aboutChevron.TextAlign = "MiddleCenter"
$aboutChevron.Location = New-Object System.Drawing.Point(804, 30)
$aboutCard.Controls.Add($aboutChevron)

$aboutClickHandler = {
    [System.Windows.Forms.MessageBox]::Show(
        "Storm Tweaks 1.0.0`r`nDeveloped by Buuks`r`n`r`nWindows optimization tool for gaming.`r`nNo personal data is collected.`r`nChanges are applied only to this computer.",
        "About Storm Tweaks",
        "OK",
        "Information"
    ) | Out-Null
}.GetNewClosure()
$aboutCard.Add_Click($aboutClickHandler)
foreach ($c in $aboutCard.Controls) { $c.Add_Click($aboutClickHandler) }
$aboutCard.Add_MouseEnter({ $aboutCardFill.Color = $colCardHover; $aboutCard.Invalidate() }.GetNewClosure())
$aboutCard.Add_MouseLeave({ $aboutCardFill.Color = $colCard; $aboutCard.Invalidate() }.GetNewClosure())

# ---------------------------------------------------------------------------
# 7. Lancement
# ---------------------------------------------------------------------------
if ($script:startupApplied) {
    Write-Log "Startup option: Windows background apps disabled (Store apps only)."
}

Show-Page "home"
Write-Log "Storm Tweaks ready. Each switch applies immediately on Windows."

[System.Windows.Forms.Application]::EnableVisualStyles()
$form.ShowDialog() | Out-Null
