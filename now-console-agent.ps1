<#
  NOW console agent — sends the timing PC's own race file to NOW.

  WHAT IT DOES, and nothing else:
    · looks in ONE folder for SKI PRO's Event*.scdb files;
    · takes the pair that was written most recently — during a race that is the
      race being timed;
    · copies them to a temp folder and sends the copies to now-ski.com;
    · sends this PC's clock with them, because a console file contains a time of
      day from the console's own clock, which is not always the real time.

  WHAT IT NEVER DOES: it does not open the live database (a reader holding that
  file is how a program causes "database is locked" in the middle of a race), it
  does not look outside the one folder, and it sends nothing but Event*.scdb files.
  The only things it writes on this PC are its own settings.txt (when the
  timekeeper saves from the window), its own log, and the temp copies.

  Stop it at any time with the Detener button, Ctrl+C, or by closing the window.
  Nothing is installed.

  THE WINDOW (ps-0.8.0). Double-click start-agent.bat. One form for setting up and for
  using: pick the console, pick the folder, Iniciar. The same engine that ps-0.7.0
  ran in a black window now runs on its own thread (a runspace), so an upload that
  takes 20 s on a mountain link never freezes the window. Minimising sends it to the
  notification area, still sending; the icon colour is the connection state.

  USAGE
    start-agent.bat                                            the window
    powershell -ExecutionPolicy Bypass -File now-console-agent.ps1 -NoGui -Token <token>
    …and, when the events folder is somewhere else:
    powershell -ExecutionPolicy Bypass -File now-console-agent.ps1 -NoGui -Token <token> -Folder "D:\skipro\events"
    -NoGui -Once    send once and exit — the way to test

  Settings live beside the script in settings.txt (the window edits it):
    carpeta = C:\SkiPro\SkiPro222\Events
  (the old now-console-agent.config.json from ps-0.4.0/0.5.0 still works.)
  A value passed on the command line always wins over the file.

  ⚠️ THIS FILE IS SAVED AS UTF-8 WITH BOM, ON PURPOSE. Windows PowerShell 5.1 reads a
  BOM-less .ps1 as ANSI, so every accent in the window would arrive as mojibake.
  ps-0.7.0 avoided accents altogether; a window in Spanish cannot. If an editor
  drops the BOM, tests\Test-Agent.ps1 fails loudly — re-save as "UTF-8 with BOM".
#>
param(
  [string] $Token,
  [string] $Folder,
  [string] $Url,
  [int]    $IntervalSeconds = 0,
  [string] $Event,                  # pin one event number (e.g. 065) instead of "the newest"
  [switch] $Once,                   # send once and exit — the way to test (implies -NoGui)
  [switch] $NoGui                   # the ps-0.7.0 black window, for a server-side check
)

# THE VERSION IS THE ONLY WAY WE KNOW WHAT IS RUNNING in a timing hut we cannot see.
# It travels with every upload, is stored per file, and the server answers with the
# newest it knows about. Bump it in the same commit as any behaviour change, and add
# a line to CHANGELOG.md — lib/console-agent.ts on the server must learn the new
# number too, or the reply will keep telling this agent it is out of date.
$AgentVersion = "ps-0.8.0"
$ErrorActionPreference = "Stop"

# ============================================================================
#  SETTINGS
# ============================================================================
#
# SETTINGS.TXT, NOT JSON (2026-09-21, his ask: "if she ever wanted to edit the path,
# she would need to edit a json... why not have a txt"). Exactly right, and JSON was
# a worse choice than it looked on a Windows PC:
#   · a path has to be written C:\\skipro\\... with DOUBLED backslashes, and the one
#     thing a timekeeper will ever edit is a path;
#   · a stray comma or a missing quote makes the whole file unreadable, and the
#     agent then silently uses defaults;
#   · .json has no default program on Windows — double-clicking it may open a
#     browser, or nothing at all. .txt opens in Notepad, always.
# So: `clave = valor`, one per line, # for comments, single backslashes, and a bad
# line is skipped instead of poisoning the file. The keys are Spanish because the
# person editing this file is the timekeeper; English aliases are accepted too.
#
# THE WINDOW EDITS THIS FILE IN PLACE, line by line, and leaves every other line —
# above all the roster of tokens that pack.mjs generates — exactly as it found it.
$SettingAliases = @{
  "token"     = @("token")
  "folder"    = @("carpeta", "folder")
  "url"       = @("servidor", "url")
  "interval"  = @("cada", "every", "intervalseconds", "intervalsegundos")
  "event"     = @("evento", "event")
  "console"   = @("consola", "console")
  "autostart" = @("iniciar", "autostart")
}
$SettingNotes = @{
  "folder"    = "# Carpeta donde SKI PRO guarda los archivos Event*.scdb"
  "interval"  = "# Cada cuantos segundos mira si hay algo nuevo"
  "event"     = "# Numero de evento fijo (vacio = el mas reciente)"
  "console"   = "# Consola de esta PC (la elige el programa desde la ventana)"
  "autostart" = "# Empezar a enviar apenas se abre el programa (si / no)"
}
$KeyToSetting = @{}
foreach ($name in $SettingAliases.Keys) { foreach ($alias in $SettingAliases[$name]) { $KeyToSetting[$alias] = $name } }

# A TRAILING BACKSLASH IS THE NORMAL CASE, not a mistake: SKI PRO's own Directorios
# dialog displays "C:\SkiPro\SkiPro222\Events\", so anyone copying the path out of
# the program she is already looking at hands us one. Test-Path, Get-ChildItem and
# Join-Path all tolerate it — Join-Path does not double the separator — so this is
# belt and braces, and it also makes the banner print a clean path.
# ⚠️ Never strip it from a bare root: "C:\" means the root of C:, while "C:" means
# "whatever directory this process happens to be in on drive C:".
function Format-FolderPath {
  param([string] $Path)
  $p = "$Path".Trim()
  if ($p.Length -gt 3) { $p = $p.TrimEnd('\', '/', ' ') }
  return $p
}

# EVERY TOKEN IN THE FILE IS A CANDIDATE CONSOLE, whether its line is active or
# commented out. pack.mjs ships them all, one `# Name - Place   (vence YYYY-MM-DD)`
# comment above each. Reading that comment is what turns "comment the one that is
# not yours" — the mistake that put two live tokens in one file — into a dropdown.
function Read-SettingsFile {
  param([string] $Path)
  $r = @{ Values = @{}; Roster = @(); ActiveTokens = @(); Duplicates = @() }
  if (-not (Test-Path -LiteralPath $Path)) { return $r }
  # -Encoding UTF8 because Notepad has saved as UTF-8 by default since Windows 10
  # 1903, and a folder with an accent in it (C:\Cronometraje Ñandú\events) would
  # otherwise arrive as mojibake and the agent would report a folder that "does not
  # exist". Plain ASCII — which is what pack.mjs writes — reads identically either way.
  $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
  $roster = New-Object System.Collections.ArrayList
  for ($n = 0; $n -lt $lines.Count; $n++) {
    $s = "$($lines[$n])".Trim()
    if (-not $s) { continue }
    $above = if ($n -gt 0) { "$($lines[$n - 1])".Trim() } else { "" }
    $isComment = $s.StartsWith("#") -or $s.StartsWith(";")
    $tokenValue = $null
    $active = $false
    if ($isComment) {
      if ($s -match '^[#;]\s*token\s*=\s*(?<v>\S+)\s*$') { $tokenValue = $Matches.v }
    } else {
      $i = $s.IndexOf("=")
      if ($i -lt 1) { continue }
      $k = $s.Substring(0, $i).Trim().ToLower()
      $v = $s.Substring($i + 1).Trim()
      # quotes are not required, and are removed if somebody adds them anyway
      if ($v.Length -gt 1 -and $v.StartsWith('"') -and $v.EndsWith('"')) { $v = $v.Substring(1, $v.Length - 2) }
      if (-not $v) { continue }
      $setting = $KeyToSetting[$k]
      if (-not $setting) { continue }
      if ($setting -eq "token") { $tokenValue = $v; $active = $true }
      else {
        # FIRST ONE WINS, and a repeat is said out loud.
        if ($r.Values.ContainsKey($setting)) { $r.Duplicates += $setting } else { $r.Values[$setting] = $v }
        continue
      }
    }
    if ($tokenValue) {
      $name = ""; $expires = $null
      if ($above -match '^[#;]\s*(?<n>.+?)\s*\(vence\s+(?<d>\d{4}-\d{2}-\d{2})\)\s*$') {
        $name = $Matches.n
        $expires = [datetime]::ParseExact($Matches.d, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
      }
      # a token with no name above it gets its last four characters, so two of them
      # can still be told apart in the list without printing a secret
      if (-not $name) { $name = "Consola $($roster.Count + 1) (token ...$($tokenValue.Substring([Math]::Max(0, $tokenValue.Length - 4))))" }
      [void]$roster.Add(@{ Name = $name; Token = $tokenValue; Expires = $expires; Active = $active })
      if ($active) { $r.ActiveTokens += $tokenValue }
    }
  }
  $r.Roster = @($roster.ToArray())
  if ($r.ActiveTokens.Count -gt 1) { $r.Duplicates += "token" }
  return $r
}

# WHICH CONSOLE IS THIS PC? An explicit `consola =` wins. Failing that, exactly one
# active token is unambiguous. TWO ACTIVE TOKENS ARE NOT: the answer is "nobody yet",
# and the window makes her choose — never a silent default, because the files would
# land under the wrong console for a whole race day.
function Select-Console {
  param($Roster, [string] $Wanted)
  $Roster = @($Roster)
  if ($Wanted) {
    $m = $Roster | Where-Object { $_.Name -eq $Wanted } | Select-Object -First 1
    if ($m) { return $m }
  }
  $active = @($Roster | Where-Object { $_.Active })
  if ($active.Count -eq 1) { return $active[0] }
  return $null
}

function Read-LegacyJson {
  param([string] $Path)
  if (-not (Test-Path -LiteralPath $Path)) { return @{} }
  try {
    $j = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $h = @{}
    foreach ($p in $j.PSObject.Properties) { $h[$p.Name] = $p.Value }
    return $h
  } catch { return @{ "_error" = $true } }
}

# command line > settings.txt > the old JSON > default
function Get-AgentConfig {
  param([string] $Dir, [hashtable] $Cli)
  $txtPath = Join-Path $Dir "settings.txt"
  $cfgPath = Join-Path $Dir "now-console-agent.config.json"
  $s = Read-SettingsFile $txtPath
  $json = Read-LegacyJson $cfgPath
  $jsonProp = @{ token = "Token"; folder = "Folder"; url = "Url"; interval = "IntervalSeconds"; event = "Event" }
  $warnings = @()
  if ($json.ContainsKey("_error")) { $warnings += "No se pudo leer el archivo de configuracion; sigo con los valores por defecto"; $json = @{} }

  function Pick($setting, $cliValue, $fallback) {
    if ($cliValue) { return $cliValue }
    if ($s.Values.ContainsKey($setting)) { return $s.Values[$setting] }
    $jp = $jsonProp[$setting]
    if ($jp -and $json.ContainsKey($jp) -and $json[$jp]) { return $json[$jp] }
    return $fallback
  }

  $roster = @($s.Roster)
  $console = $null
  if ($Cli.Token) {
    $console = @{ Name = "(indicado en la linea de comandos)"; Token = $Cli.Token; Expires = $null; Active = $true }
    $roster = @($console) + $roster
  } else {
    $console = Select-Console $roster $s.Values["console"]
  }
  $token = $Cli.Token
  if (-not $token -and $console) { $token = $console.Token }
  if (-not $token -and $s.ActiveTokens.Count -gt 0) { $token = $s.ActiveTokens[0] }   # legacy: first one wins
  if (-not $token -and $json.ContainsKey("Token")) { $token = $json["Token"] }

  foreach ($d in ($s.Duplicates | Select-Object -Unique)) {
    if ($d -eq "token") {
      if (-not $s.Values["console"]) {
        $warnings += "hay mas de un 'token' activo en settings.txt - se usa el PRIMERO. Comenta con # los que no correspondan a esta PC."
      }
    } else { $warnings += "'$d' aparece mas de una vez en settings.txt - se usa el primero." }
  }

  # A FAST TICK IS A BETTER CLOCK, not just a fresher file. Each snapshot arrives
  # stamped with OUR clock, so the first snapshot that contains a given impulse
  # brackets when that impulse really happened: at 2 s the bracket is +-2 s, at 20 s
  # it is +-20 s. On a console that publishes to nothing (Antillanca has no VOLA
  # feed) that bracket is the ONLY independent check on the console's own clock, and
  # La Hoya's was 112.95 s out. So the floor is 1 s; a tick that finds nothing
  # changed costs one hash and no request.
  $cliInterval = $null
  if ($Cli.Interval -gt 0) { $cliInterval = $Cli.Interval }
  $interval = 1
  $parsed = 0
  if ([int]::TryParse("$(Pick 'interval' $cliInterval 1)", [ref]$parsed)) { $interval = $parsed }
  if ($interval -lt 1) { $interval = 1 }
  if ($interval -gt 3600) { $interval = 3600 }

  $auto = $true
  if ($s.Values.ContainsKey("autostart")) { $auto = @("si", "sí", "s", "yes", "true", "1") -contains $s.Values["autostart"].ToLower() }

  return @{
    Dir          = $Dir
    SettingsPath = $txtPath
    LegacyPath   = $cfgPath
    Token        = "$token"
    Console      = $console
    Roster       = $roster
    Folder       = (Format-FolderPath (Pick "folder" $Cli.Folder "C:\SkiPro\SkiPro222\Events"))
    Url          = "$(Pick 'url' $Cli.Url 'https://now-ski.com/api/console/file')"
    Interval     = $interval
    Event        = "$(Pick 'event' $Cli.Event '')"
    AutoStart    = $auto
    Warnings     = $warnings
    LogFile      = (Join-Path $Dir "now-console-agent.log")
  }
}

# Edits the file in place. Only the keys in $Changes are touched; a key that is not
# there yet is appended with a one-line note. CRLF and a UTF-8 BOM on the way out so
# an old Notepad reads a folder with an accent correctly. Written to a .tmp first, so
# a crash halfway can never leave the roster of tokens half-written.
# Returns $null on success, the error text otherwise.
function Save-SettingsFile {
  param([string] $Path, [hashtable] $Changes)
  try {
    $text = ""
    if (Test-Path -LiteralPath $Path) { $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8) }
    $lines = New-Object System.Collections.ArrayList
    if ($text) { foreach ($l in ($text -split "\r?\n")) { [void]$lines.Add($l) } }
    while ($lines.Count -gt 0 -and -not "$($lines[$lines.Count - 1])".Trim()) { $lines.RemoveAt($lines.Count - 1) }
    foreach ($setting in @($Changes.Keys)) {
      $value = "$($Changes[$setting])"
      $done = $false
      for ($i = 0; $i -lt $lines.Count; $i++) {
        $t = "$($lines[$i])".Trim()
        if (-not $t -or $t.StartsWith("#") -or $t.StartsWith(";")) { continue }
        $eq = $t.IndexOf("=")
        if ($eq -lt 1) { continue }
        $k = $t.Substring(0, $eq).Trim()
        if ($SettingAliases[$setting] -contains $k.ToLower()) { $lines[$i] = "$k = $value"; $done = $true; break }
      }
      if (-not $done) {
        [void]$lines.Add("")
        [void]$lines.Add($SettingNotes[$setting])
        [void]$lines.Add("$($SettingAliases[$setting][0]) = $value")
      }
    }
    $tmp = "$Path.tmp"
    [System.IO.File]::WriteAllText($tmp, (($lines -join "`r`n") + "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
    return $null
  } catch { return $_.Exception.Message }
}

function Get-FolderInfo {
  param([string] $Folder)
  $f = Format-FolderPath $Folder
  if (-not $f -or -not (Test-Path -LiteralPath $f -PathType Container)) {
    return @{ Exists = $false; Level = "bad"; Text = "La carpeta no existe." }
  }
  $ex = @(Get-ChildItem -LiteralPath $f -Filter "Event*Ex.scdb" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
  if ($ex.Count -eq 0) {
    return @{ Exists = $true; Level = "muted"; Text = "La carpeta existe, pero todavía no hay archivos Event*.scdb (es normal antes de la primera carrera)." }
  }
  return @{ Exists = $true; Level = "ok"; Text = "Correcto: $($ex.Count) evento(s). El más reciente: $($ex[0].Name -replace 'Ex\.scdb$', '')." }
}

function Get-ExpiryNote {
  param($Entry)
  if (-not $Entry -or -not $Entry.Expires) { return @{ Level = "muted"; Text = "" } }
  $days = [int][Math]::Floor(($Entry.Expires.Date - (Get-Date).Date).TotalDays)
  $d = $Entry.Expires.ToString("yyyy-MM-dd")
  if ($days -lt 0) { return @{ Level = "bad"; Text = "ATENCIÓN: el código de esta consola venció el $d. Pedile uno nuevo a NOW." } }
  if ($days -le 14) { return @{ Level = "warn"; Text = "El código vence en $days día(s) ($d)." } }
  return @{ Level = "muted"; Text = "Código válido hasta el $d." }
}

# ============================================================================
#  THE ENGINE — runs on its own thread, talks to the front end through a queue
# ============================================================================
#
# The engine is one script block so the window and the -NoGui console can both run
# it unchanged: it never touches the UI. It writes NEWS to a queue (Say = a line for
# the log, Dot = "nothing happened") and STATE to a synchronized hashtable ($Shared)
# that the front end polls. Stop = $Shared.Stop, which it honours within ~0.1 s
# outside of an upload.
$EngineScript = {
  param($Cfg, $Shared, $Q)
  $ErrorActionPreference = "Stop"
  # ⚠️ NOT $S: PowerShell variables are case-insensitive, so $S and the $s that
  # Sync-Clock and Send-Once use for "seconds" are the same variable.
  $St = @{
    LastWaitLog = [DateTime]::MinValue; LastPostAt = [DateTime]::MinValue; LastSyncAt = [DateTime]::MinValue
    SyncOffsetMs = $null; SyncRttMs = $null; Online = $true; LastSent = @{}; LastFailSayAt = [DateTime]::MinValue
    LastErr = ""; LastErrAt = [DateTime]::MinValue
  }

  # THE LOG. The window is the truth while somebody is watching it, and a race day is
  # exactly when nobody is: the timekeeper is timing. So every line also goes to a file
  # beside the script, with a date, and the whole day can be read afterwards or sent to
  # us as one attachment. Capped at 2 MB with a single .old behind it — a 1 s tick for
  # eight hours would otherwise sail past that, and the cap means an agent forgotten on
  # a PC for a season cannot fill a disk.
  function Limit-Log {
    try {
      if ((Test-Path $Cfg.LogFile) -and ((Get-Item $Cfg.LogFile).Length -gt 2MB)) { Move-Item $Cfg.LogFile "$($Cfg.LogFile).old" -Force }
    } catch {}
  }
  function Say {
    param([string] $Text, [string] $Color = "Gray")
    $Q.Enqueue([pscustomobject]@{ Kind = "say"; Time = (Get-Date); Text = $Text; Color = $Color })
    try { Add-Content -Path $Cfg.LogFile -Value ("{0}  {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Text) -Encoding UTF8 } catch {}
  }
  # A dot costs nothing on screen and NOTHING in the log: a log line per second would
  # make the file useless for the one job it has, which is reading a race day
  # afterwards. The log gets one "esperando" line every 5 minutes instead.
  function Dot {
    param([string] $Char = ".")
    $Q.Enqueue([pscustomobject]@{ Kind = "dot"; Char = $Char })
    $Shared.Tick = $Char
    $Shared.TickAt = Get-Date
    if (((Get-Date) - $St.LastWaitLog).TotalMinutes -ge 5) {
      $St.LastWaitLog = Get-Date
      try { Add-Content -Path $Cfg.LogFile -Value ("{0}  esperando cambios" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")) -Encoding UTF8 } catch {}
    }
  }

  # ⚠️ EVERY NATIVE CALL GOES THROUGH HERE. In Windows PowerShell 5.1, `2>&1` together
  # with $ErrorActionPreference = "Stop" THROWS on the first line curl writes to
  # stderr — which is exactly what curl does when the network is down. In ps-0.7.0
  # the heartbeat was called outside any try/catch, so a dropped connection killed
  # the agent the minute the "connection alarm" tried to sound. Relaxed here, and the
  # reply comes back as plain text either way.
  function Invoke-Curl {
    param([string[]] $CurlArgs)
    $ErrorActionPreference = "Continue"
    $out = & $Cfg.Curl @CurlArgs 2>&1
    return (($out | ForEach-Object { "$_" }) -join "`n")
  }

  # ---------- WHAT TIME IS IT, REALLY --------------------------------------------
  # His ask: know the best available time when the script opens. One tiny GET whose
  # round trip we measure and halve, the way NTP does:
  #     offset = serverMs - (t0 + t2)/2      uncertainty = (t2 - t0)/2
  # Three samples, keep the one with the fastest round trip — the fastest sample is
  # the least distorted, which is also how NTP picks. Repeated every 10 minutes,
  # because a PC clock drifts and a race is hours long.
  #
  # ⚠️ THIS IS THE PC'S CLOCK, NOT THE TIMING BOX'S. They come apart (La Hoya, 19 Sep:
  # the box ran 112.95 s behind while its PC was fine). What it buys is a PC clock good
  # to milliseconds, which makes the file's own mtime a tight bracket on when the
  # console committed each impulse — a better ruler for the box than our arrival time,
  # which carries the whole upload with it.
  $timeUrl = ($Cfg.Url -replace '/file$', '/time')
  function Sync-Clock {
    param([switch] $Quiet)
    $best = $null
    for ($i = 0; $i -lt 3; $i++) {
      try {
        $t0 = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $raw = Invoke-Curl @("--silent", "--show-error", "--max-time", "10", $timeUrl)
        $t2 = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        $j = $raw | ConvertFrom-Json
        if ($null -eq $j.ms) { continue }
        $rtt = $t2 - $t0
        if ($null -eq $best -or $rtt -lt $best.Rtt) {
          $best = @{ Rtt = $rtt; Offset = [int64]($j.ms - [Math]::Round(($t0 + $t2) / 2)) }
        }
      } catch {}
    }
    $St.LastSyncAt = Get-Date
    if ($null -eq $best) {
      if (-not $Quiet) { Say "  no se pudo consultar la hora del servidor (sigo igual)" "Yellow" }
      return
    }
    $St.SyncOffsetMs = $best.Offset
    $St.SyncRttMs = $best.Rtt
    $s = [Math]::Abs($best.Offset) / 1000
    if ([Math]::Abs($best.Offset) -lt 2000) {
      $Shared.ClockLevel = "ok"
      $Shared.ClockLine = ("Coincide con la hora real (diferencia {0:N1} s, medida +-{1:N1} s)" -f $s, ($best.Rtt / 2000))
      if (-not $Quiet) { Say ("  reloj    : la PC coincide con la hora real (diferencia {0:N1} s, medida +-{1:N1} s)" -f $s, ($best.Rtt / 2000)) "DarkGray" }
    } else {
      $dir = if ($best.Offset -gt 0) { "ATRASADA" } else { "ADELANTADA" }
      $Shared.ClockLevel = "warn"
      $Shared.ClockLine = ("AVISO: está {0:N1} s {1} respecto de la hora real. Conviene sincronizarla." -f $s, $dir)
      if (-not $Quiet) {
        Say ("  reloj    : AVISO - la PC esta {0:N1} s {1} respecto de la hora real (medida +-{2:N1} s)" -f $s, $dir, ($best.Rtt / 2000)) "Yellow"
        Say "             conviene sincronizarla: clic derecho en el reloj de Windows -> Ajustar fecha y hora -> Sincronizar ahora" "Yellow"
      }
    }
  }

  # ---------- THE HEARTBEAT --------------------------------------------------------
  # Until ps-0.7.0 the server heard from a console only when the FILE CHANGED, so "no
  # file for 30 minutes" read exactly the same as "nobody started it" — and on a race
  # morning those are opposite facts. One tiny request a minute, carrying no file,
  # says "I am here, nothing is happening", which is what an idle console between
  # races looks like.
  #
  # It is also the connection alarm. While the console is quiet nothing else touches
  # the network, so a link that died at 09:00 would otherwise be discovered by the
  # first racer at 10:00. The agent says so the minute it happens, and says so again
  # when it comes back. Silent otherwise: it must not spoil the waiting line.
  function Set-Online {
    param([bool] $Ok)
    $Shared.Online = $Ok
    if ($Ok -ne $St.Online) {
      $St.Online = $Ok
      if ($Ok) { Say "  conexion con NOW restablecida" "Green" }
      else { Say "  AVISO: sin conexion con NOW - se sigue intentando, y los archivos se envian cuando vuelva" "Yellow" }
    }
  }
  function Send-Heartbeat {
    $hb = @(
      "--silent", "--show-error", "--max-time", "20",
      "-H", "X-Console-Token: $($Cfg.Token)",
      "-F", "heartbeat=1",
      "-F", "machine=$env:COMPUTERNAME",
      "-F", "agentVersion=$($Cfg.AgentVersion)",
      "-F", "pcClockMs=$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())",
      "-F", "tzMinutes=$([int][System.TimeZoneInfo]::Local.GetUtcOffset([DateTime]::Now).TotalMinutes)",
      "-F", "pcSyncOffsetMs=$($St.SyncOffsetMs)",
      "-F", "pcSyncRttMs=$($St.SyncRttMs)",
      $Cfg.Url
    )
    $reply = Invoke-Curl $hb
    $ok = $false
    try { $ok = (($reply | ConvertFrom-Json).ok -eq $true) } catch {}
    $St.LastPostAt = Get-Date
    Set-Online $ok
  }

  function Send-Once {
    # THE RACE IN PROGRESS = the Ex file written most recently. SKI PRO appends to it
    # on every impulse, so its write time is the race clock as far as this script cares.
    if ($Cfg.Event) {
      $n = $Cfg.Event.PadLeft(3, "0")
      $ex = Get-Item (Join-Path $Cfg.Folder "Event$n`Ex.scdb") -ErrorAction SilentlyContinue
    } else {
      $ex = Get-ChildItem -Path $Cfg.Folder -Filter "Event*Ex.scdb" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    }
    if (-not $ex) { $Shared.CurrentEvent = ""; Dot "?"; return }   # ? = nothing to send yet

    if ($ex.Name -notmatch '^Event(\d+)Ex\.scdb$') { Say "  nombre de archivo inesperado: $($ex.Name)"; return }
    $no   = $Matches[1]
    $Shared.CurrentEvent = "Event$no"
    $main = Get-Item (Join-Path $Cfg.Folder "Event$no.scdb") -ErrorAction SilentlyContinue

    # A WRITE IS IN FLIGHT: SQLite keeps a -journal file beside the database while a
    # transaction is open, and a copy taken then can be half a transaction. Wait a tick.
    if ((Test-Path "$($ex.FullName)-journal") -or ($main -and (Test-Path "$($main.FullName)-journal"))) {
      Dot "w"   # w = SKI PRO is mid-write, we wait rather than copy half a transaction
      return
    }

    # COPY FIRST, ALWAYS. We read our copy; SKI PRO keeps the original to itself.
    $exCopy = Join-Path $Cfg.Temp $ex.Name
    try { Copy-Item $ex.FullName $exCopy -Force }
    catch { Say "Event$no esta en uso en este momento - reintento" "Yellow"; return }
    $mainCopy = $null
    if ($main) {
      $mainCopy = Join-Path $Cfg.Temp $main.Name
      try { Copy-Item $main.FullName $mainCopy -Force } catch { $mainCopy = $null }
    }

    $exSha   = (Get-FileHash $exCopy -Algorithm SHA256).Hash
    $mainSha = if ($mainCopy) { (Get-FileHash $mainCopy -Algorithm SHA256).Hash } else { "" }
    if ($St.LastSent[$ex.Name] -eq $exSha -and $St.LastSent["main$no"] -eq $mainSha) {
      Dot          # the ordinary case: nothing has changed since the last send
      return
    }

    # THE CLOCK, read as late as possible so the round trip is all that separates it
    # from the server's own stamp.
    $nowUtc   = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $tzMin    = [int][System.TimeZoneInfo]::Local.GetUtcOffset([DateTime]::Now).TotalMinutes
    $exMtime  = [DateTimeOffset]::new($ex.LastWriteTimeUtc, [TimeSpan]::Zero).ToUnixTimeMilliseconds()

    $curlArgs = @(
      "--silent", "--show-error", "--max-time", "120",
      "-H", "X-Console-Token: $($Cfg.Token)",
      "-F", "machine=$env:COMPUTERNAME",
      "-F", "agentVersion=$($Cfg.AgentVersion)",
      "-F", "eventNo=$no",
      "-F", "pcClockMs=$nowUtc",
      "-F", "tzMinutes=$tzMin",
      # the agent's OWN measurement of its clock, independent of how long this upload
      # takes — the server stores both and they answer different questions
      "-F", "pcSyncOffsetMs=$($St.SyncOffsetMs)",
      "-F", "pcSyncRttMs=$($St.SyncRttMs)",
      "-F", "exMtimeMs=$exMtime",
      "-F", "ex=@`"$exCopy`""
    )
    # THE FIELD FILE ONLY WHEN IT CHANGED. EventNNN.scdb holds the start list and the
    # title and barely moves; EventNNNEx.scdb holds the impulses and moves constantly.
    # At a 1 s tick, resending the field every time is most of the traffic on a
    # mountain link and none of the news. The server keeps the last one it received
    # and pairs it with each new Ex to read the race.
    if ($mainCopy -and $St.LastSent["main$no"] -ne $mainSha) {
      $mainMtime = [DateTimeOffset]::new($main.LastWriteTimeUtc, [TimeSpan]::Zero).ToUnixTimeMilliseconds()
      $curlArgs += @("-F", "mainMtimeMs=$mainMtime", "-F", "main=@`"$mainCopy`"")
    }
    $curlArgs += $Cfg.Url

    $Shared.Busy = $true
    try { $reply = Invoke-Curl $curlArgs } finally { $Shared.Busy = $false }
    try { $json = $reply | ConvertFrom-Json } catch { $json = $null }

    if ($json -and $json.ok) {
      $St.LastPostAt = Get-Date
      Set-Online $true
      $St.LastSent[$ex.Name] = $exSha
      $St.LastSent["main$no"] = $mainSha
      $sent = ($json.files | Where-Object { $_.stored } | Measure-Object).Count
      if ($sent -eq 0) {
        # the bytes changed on disk but we had already received them — normal, and it
        # used to print "enviado (0 archivo(s))", which reads like a failure
        Dot "="   # = the bytes moved but we already had them
      } else {
        $Shared.LastSendAt = Get-Date
        $Shared.LastSendEvent = "Event$no"
        Say "Event$no enviado ($sent archivo(s))" "Green"
      }
      if ($json.parsed) {
        $h = ($json.parsed.heats | ForEach-Object { "manga $($_.heat): $($_.started)/$($_.rows) largaron, $($_.timed) con tiempo" }) -join " | "
        $Shared.RaceLine = "$($json.parsed.title)  $($json.parsed.date)  $h"
        Say "     $($Shared.RaceLine)"
      }
      # EL RELOJ DE LA PC. La consola guarda la hora segun ESTE reloj, y en La Hoya
      # (2026-09-19) uno estuvo 112.95 s atrasado todo el dia sin que nadie lo notara,
      # firme como una roca, que es justamente lo que lo hace peligroso.
      if ($json.clock -and $null -ne $json.clock.pcAheadMs) {
        $ms = [double]$json.clock.pcAheadMs
        if ([Math]::Abs($ms) -lt 5000) {
          Say "     El reloj de la PC coincide con el nuestro (menos de 5 s)" "DarkGray"
        } else {
          $s = [Math]::Abs($ms) / 1000
          $dir = if ($ms -lt 0) { "ATRASADO" } else { "ADELANTADO" }
          Say ("     AVISO: el reloj de la PC esta {0:N1} s {1} respecto del nuestro" -f $s, $dir) "Yellow"
        }
      }
      if ($json.agent -and $json.agent.outdated) {
        $Shared.OutdatedLatest = "$($json.agent.latest)"
        Say "     Hay una version mas nueva ($($json.agent.latest)). Sigue funcionando; pedila cuando puedas." "DarkYellow"
      }
      if ($json.readError) { Say "     no se pudo leer la copia (se reintenta sola): $($json.readError)" "Yellow" }
    } elseif ($json -and $json.code -eq "agent_too_old") {
      # NO AUTO-UPDATE, BY DESIGN: a program on someone else's PC that downloads and
      # runs whatever we send it later is exactly what this agent refuses to be. So it
      # stops and asks for a person.
      Say "  Esta version del programa ($($Cfg.AgentVersion)) ya no se acepta." "Red"
      Say "  Pedile a NOW la version nueva ($($json.agent.latest)) y reemplaza los archivos de esta carpeta." "Red"
      $Shared.TooOld = $true
      $Shared.OutdatedLatest = "$($json.agent.latest)"
      $Shared.ExitCode = 3
      $Shared.Stop = $true
    } else {
      Set-Online $false
      # one line per 30 s, not one per tick: a link that is down for an hour would
      # otherwise write 3600 identical lines over the ones that matter
      if (((Get-Date) - $St.LastFailSayAt).TotalSeconds -ge 30) {
        $St.LastFailSayAt = Get-Date
        Say "no enviado: $reply" "Red"
      }
    }
  }

  # ---------- THE LOOP -------------------------------------------------------------
  try {
    $Shared.State = "running"
    Limit-Log
    foreach ($b in $Cfg.Banner) { Say $b.Text $b.Color }
    Sync-Clock
    if ($Cfg.Once) { Send-Once; return }
    $ticks = 0
    while (-not $Shared.Stop) {
      try { Send-Once } catch {
        # the same failure every second for an hour is one line, not 3600
        $msg = $_.Exception.Message
        if ($msg -ne $St.LastErr -or ((Get-Date) - $St.LastErrAt).TotalSeconds -ge 30) {
          $St.LastErr = $msg; $St.LastErrAt = Get-Date
          Say $msg "Red"
        }
      }
      $ticks++
      try { if (((Get-Date) - $St.LastPostAt).TotalSeconds -ge 60) { Send-Heartbeat } } catch { Say "latido: $($_.Exception.Message)" "Yellow" }
      try { if (((Get-Date) - $St.LastSyncAt).TotalMinutes -ge 10) { Sync-Clock -Quiet } } catch {}
      # the cap has to hold while it RUNS, not only when it starts: left on for a week
      # at a 1 s tick this file would sail past 2 MB and keep going
      if ($ticks % 500 -eq 0) { Limit-Log }
      $until = (Get-Date).AddSeconds($Cfg.Interval)
      while (-not $Shared.Stop -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 100 }
    }
  } catch {
    Say "El agente se detuvo por un error: $($_.Exception.Message)" "Red"
    $Shared.ExitCode = 1
  } finally {
    $Shared.State = "stopped"
  }
}

function New-SharedState {
  return [hashtable]::Synchronized(@{
    Stop = $false; State = "idle"; Online = $null; ExitCode = 0; Busy = $false
    Tick = ""; TickAt = $null; CurrentEvent = ""; LastSendAt = $null; LastSendEvent = ""
    RaceLine = ""; ClockLine = ""; ClockLevel = "muted"; OutdatedLatest = ""; TooOld = $false
  })
}

function New-EngineConfig {
  param([hashtable] $Cfg, [string] $Token, [string] $Folder, [int] $Interval, [string] $ConsoleName, [bool] $Once = $false)
  $temp = Join-Path $env:TEMP "now-console-agent"
  New-Item -ItemType Directory -Force -Path $temp | Out-Null
  $curl = Join-Path $env:SystemRoot "System32\curl.exe"
  if (-not (Test-Path $curl)) { $curl = "curl.exe" }   # PATH fallback (older Windows)
  $banner = @(
    @{ Text = "NOW - envio del archivo de cronometraje  ($AgentVersion)"; Color = "Cyan" }
    @{ Text = "  consola  : $(if ($ConsoleName) { $ConsoleName } else { '(sin nombre)' })"; Color = "Gray" }
    @{ Text = "  carpeta  : $Folder"; Color = "Gray" }
    @{ Text = "  enviando : $($Cfg.Url)"; Color = "Gray" }
    @{ Text = "  cada     : $Interval s"; Color = "Gray" }
    @{ Text = "  ajustes  : $(if (Test-Path $Cfg.SettingsPath) { $Cfg.SettingsPath } elseif (Test-Path $Cfg.LegacyPath) { $Cfg.LegacyPath } else { '(ninguno - valores por defecto)' })"; Color = "Gray" }
    @{ Text = "  registro : $($Cfg.LogFile)"; Color = "Gray" }
  )
  foreach ($w in $Cfg.Warnings) { $banner += @{ Text = "  AVISO: $w"; Color = "Yellow" } }
  return @{
    Token = $Token; Folder = $Folder; Url = $Cfg.Url; Interval = $Interval; Event = $Cfg.Event
    AgentVersion = $AgentVersion; LogFile = $Cfg.LogFile; Temp = $temp; Curl = $curl
    Once = $Once; Banner = $banner
  }
}

function Start-Engine {
  param([hashtable] $EngineCfg, $Shared, $Queue)
  $rs = [runspacefactory]::CreateRunspace()
  $rs.Open()
  $ps = [powershell]::Create()
  $ps.Runspace = $rs
  [void]$ps.AddScript($EngineScript.ToString()).AddArgument($EngineCfg).AddArgument($Shared).AddArgument($Queue)
  return @{ Ps = $ps; Runspace = $rs; Handle = $ps.BeginInvoke() }
}

function Stop-Engine {
  param($Engine, [switch] $Force)
  if (-not $Engine) { return }
  try { if ($Force -and -not $Engine.Handle.IsCompleted) { $Engine.Ps.Stop() } } catch {}
  try { $Engine.Ps.Dispose() } catch {}
  try { $Engine.Runspace.Dispose() } catch {}
}

# ============================================================================
#  THE OLD BLACK WINDOW (-NoGui) — the same engine, printed to the console
# ============================================================================
function Invoke-Headless {
  param([hashtable] $EngineCfg)
  $q = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
  $shared = New-SharedState
  $eng = Start-Engine $EngineCfg $shared $q
  $dots = 0
  # dot-sourced below (`. $print`), NOT called with &: a called script block gets its
  # own scope, so `$dots++` would bump a private copy and the line would never wrap
  $print = {
    $item = $null
    while ($q.TryDequeue([ref]$item)) {
      if ($item.Kind -eq "dot") {
        if ($dots -eq 0) { Write-Host ("  {0} " -f (Get-Date -Format "HH:mm:ss")) -NoNewline -ForegroundColor DarkGray }
        Write-Host $item.Char -NoNewline -ForegroundColor DarkGray
        $dots++
        if ($dots -ge 50) { Write-Host ""; $dots = 0 }
      } else {
        if ($dots -gt 0) { Write-Host ""; $dots = 0 }
        $prefix = if ($item.Text.StartsWith(" ")) { "" } else { "$($item.Time.ToString('HH:mm:ss'))  " }
        Write-Host ($prefix + $item.Text) -ForegroundColor $item.Color
      }
    }
  }
  try {
    while (-not $eng.Handle.IsCompleted) { . $print; Start-Sleep -Milliseconds 200 }
    . $print
  } finally {
    $shared.Stop = $true
    Stop-Engine $eng -Force
  }
  return [int]$shared.ExitCode
}

# ============================================================================
#  THE WINDOW
# ============================================================================
# Everything the handlers touch lives in $script:Ui (controls) and $script:App (state):
# a handler runs long after the function that defined it has returned, and a plain
# local would simply not be there.
function ConvertTo-UiColor {
  param([string] $Name)
  switch ($Name) {
    "Green"      { return [System.Drawing.Color]::FromArgb(0, 128, 0) }
    "Red"        { return [System.Drawing.Color]::FromArgb(192, 0, 0) }
    "Yellow"     { return [System.Drawing.Color]::FromArgb(176, 112, 0) }
    "DarkYellow" { return [System.Drawing.Color]::FromArgb(176, 112, 0) }
    "Cyan"       { return [System.Drawing.Color]::FromArgb(0, 96, 128) }
    "DarkGray"   { return [System.Drawing.Color]::FromArgb(128, 128, 128) }
    "bad"        { return [System.Drawing.Color]::FromArgb(192, 0, 0) }
    "warn"       { return [System.Drawing.Color]::FromArgb(176, 112, 0) }
    "ok"         { return [System.Drawing.Color]::FromArgb(0, 128, 0) }
    "muted"      { return [System.Drawing.Color]::FromArgb(110, 110, 110) }
    default      { return [System.Drawing.Color]::FromArgb(60, 60, 60) }
  }
}

function New-StateIcon {
  param($Color)
  $bmp = New-Object System.Drawing.Bitmap 16, 16
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = "AntiAlias"
  $g.Clear([System.Drawing.Color]::Transparent)
  $g.FillEllipse((New-Object System.Drawing.SolidBrush $Color), 1, 1, 14, 14)
  $g.DrawEllipse((New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(90, 0, 0, 0))), 1, 1, 14, 14)
  $g.Dispose()
  return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

function Add-UiLog {
  param($Time, [string] $Text, [string] $Color = "Gray")
  $rtb = $script:Ui.Log
  # continuation lines (indented) get no timestamp, like the console
  $stamp = if ($Text.StartsWith(" ")) { "" } else { "{0:HH:mm:ss}  " -f $Time }
  $rtb.SelectionStart = $rtb.TextLength
  $rtb.SelectionLength = 0
  $rtb.SelectionColor = ConvertTo-UiColor $Color
  $rtb.AppendText($stamp + $Text + "`n")
  # a day of sends is thousands of lines: keep the box light, the .log keeps everything
  if ($rtb.GetLineFromCharIndex($rtb.TextLength) -gt 2000) {
    $rtb.Select(0, $rtb.GetFirstCharIndexFromLine(500))
    $rtb.SelectedText = ""
  }
  $rtb.SelectionStart = $rtb.TextLength
  $rtb.ScrollToCaret()
}

function Set-Note {
  param($Label, $Info)
  $Label.Text = $Info.Text
  $Label.ForeColor = ConvertTo-UiColor $Info.Level
}

function Update-ConfigNotes {
  $ui = $script:Ui; $app = $script:App
  Set-Note $ui.FolderNote (Get-FolderInfo $ui.Folder.Text)
  $i = $ui.Console.SelectedIndex
  if ($i -ge 0) { Set-Note $ui.ConsoleNote (Get-ExpiryNote $app.Roster[$i]) }
  elseif ($app.Roster.Count -eq 0) { Set-Note $ui.ConsoleNote @{ Level = "bad"; Text = "No hay ninguna consola en settings.txt. Pedile el paquete a NOW." } }
  else { Set-Note $ui.ConsoleNote @{ Level = "warn"; Text = "Elegí la consola que corresponde a esta PC." } }
}

function Set-UiRunning {
  param([bool] $Running)
  $ui = $script:Ui
  foreach ($c in $ui.Console, $ui.Folder, $ui.Browse, $ui.Every, $ui.Auto, $ui.Save) { $c.Enabled = -not $Running }
  # a Flat button keeps its BackColor when disabled: it would stay bright green and
  # look pressable while the agent is already sending
  $ui.Start.Enabled = -not $Running
  $ui.Start.BackColor = if ($Running) { [System.Drawing.SystemColors]::Control } else { [System.Drawing.Color]::FromArgb(0, 128, 0) }
  $ui.Start.ForeColor = if ($Running) { [System.Drawing.SystemColors]::GrayText } else { [System.Drawing.Color]::White }
  $ui.Stop.Enabled = $Running
}

function Get-StartProblem {
  $ui = $script:Ui
  if ($ui.Console.SelectedIndex -lt 0) { return "Elegí la consola de esta PC." }
  $f = Format-FolderPath $ui.Folder.Text
  if (-not $f -or -not (Test-Path -LiteralPath $f -PathType Container)) { return "Esa carpeta no existe: $f`nBuscá en esta PC un archivo llamado Event*.scdb y elegí esa carpeta." }
  return $null
}

function Save-UiSettings {
  $ui = $script:Ui; $app = $script:App
  $changes = @{
    folder    = (Format-FolderPath $ui.Folder.Text)
    interval  = [int]$ui.Every.Value
    autostart = $(if ($ui.Auto.Checked) { "si" } else { "no" })
  }
  if ($ui.Console.SelectedIndex -ge 0) { $changes["console"] = $app.Roster[$ui.Console.SelectedIndex].Name }
  return (Save-SettingsFile $app.Cfg.SettingsPath $changes)
}

function Start-Sending {
  param([switch] $Auto)
  $ui = $script:Ui; $app = $script:App
  if ($app.Engine) { return }
  $problem = Get-StartProblem
  if ($problem) {
    if ($Auto) { Add-UiLog (Get-Date) "No se inició solo: $($problem -replace "`n", ' ')" "Yellow" }
    else { [void][System.Windows.Forms.MessageBox]::Show($problem, "NOW", "OK", "Warning") }
    return
  }
  $err = Save-UiSettings
  if ($err) { Add-UiLog (Get-Date) "No se pudieron guardar los ajustes: $err" "Yellow" }
  $entry = $app.Roster[$ui.Console.SelectedIndex]
  $engineCfg = New-EngineConfig -Cfg $app.Cfg -Token $entry.Token -Folder (Format-FolderPath $ui.Folder.Text) -Interval ([int]$ui.Every.Value) -ConsoleName $entry.Name
  $app.Shared = New-SharedState
  $app.Queue = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
  $app.Stopping = $false
  $app.PrevOnline = $null
  $app.Engine = Start-Engine $engineCfg $app.Shared $app.Queue
  Set-UiRunning $true
}

function Stop-Sending {
  $app = $script:App
  if (-not $app.Engine -or $app.Stopping) { return }
  $app.Stopping = $true
  $app.Shared.Stop = $true
  $script:Ui.Stop.Enabled = $false
}

# the engine has finished (Stop, or agent_too_old, or an error): give the window back
function Complete-Run {
  $ui = $script:Ui; $app = $script:App
  $shared = $app.Shared
  Stop-Engine $app.Engine
  $app.Engine = $null
  $app.Stopping = $false
  Set-UiRunning $false
  if ($shared.TooOld) {
    Show-MainForm
    [void][System.Windows.Forms.MessageBox]::Show("Esta versión del programa ($AgentVersion) ya no se acepta.`n`nPedile a NOW la versión nueva ($($shared.OutdatedLatest)) y reemplazá los archivos de esta carpeta.", "NOW", "OK", "Error")
  }
}

function Update-UiStatus {
  $ui = $script:Ui; $app = $script:App
  $sh = $app.Shared
  $key = "idle"; $text = "Detenido"; $color = "muted"
  if ($app.Engine -and $sh) {
    if ($app.Stopping) { $key = "gray"; $text = "Deteniendo..."; $color = "muted" }
    elseif ($sh.Online -eq $false) { $key = "red"; $text = "Sin conexión con NOW"; $color = "bad" }
    elseif ($null -eq $sh.Online) { $key = "yellow"; $text = "Conectando..."; $color = "warn" }
    else { $key = "green"; $text = "En marcha"; $color = "ok" }
  } else { $key = "gray" }
  $ui.State.Text = [char]0x25CF + "  " + $text
  $ui.State.ForeColor = ConvertTo-UiColor $color

  if ($app.Engine -and $sh) {
    $ui.Conn.Text = if ($null -eq $sh.Online) { "Comprobando..." } elseif ($sh.Online) { "Conectado" } else { "SIN CONEXIÓN. Reintenta solo; envía apenas vuelva." }
    $ui.Conn.ForeColor = ConvertTo-UiColor $(if ($sh.Online -eq $false) { "bad" } else { "default" })
    $ui.Last.Text = if ($sh.LastSendAt) { "{0:HH:mm:ss}  ({1})" -f $sh.LastSendAt, $sh.LastSendEvent } else { "todavía no se envió nada" }
    $ui.Race.Text = if ($sh.RaceLine) { $sh.RaceLine } else { "-" }
    $ui.Clock.Text = if ($sh.ClockLine) { $sh.ClockLine } else { "midiendo..." }
    $ui.Clock.ForeColor = ConvertTo-UiColor $sh.ClockLevel
    $watch = if ($sh.Busy) { "Enviando..." } else {
      switch ($sh.Tick) {
        "."     { "Mirando la carpeta: sin cambios" }
        "="     { "Mirando la carpeta: el archivo cambió, pero eso ya lo teníamos" }
        "w"     { "SKI PRO está escribiendo en este momento; espero" }
        "?"     { "Todavía no hay ningún archivo Event*.scdb en la carpeta" }
        default { "Iniciando..." }
      }
    }
    $ui.Watch.Text = if ($sh.CurrentEvent) { "$watch   [$($sh.CurrentEvent)]" } else { $watch }
  } else {
    $ui.Conn.Text = "-"; $ui.Conn.ForeColor = ConvertTo-UiColor "default"
    $ui.Watch.Text = "-"
  }

  $ui.Toggle.Text = if ($app.Engine) { "Detener el envío" } else { "Iniciar el envío" }
  # the icon carries the state when the window is hidden in the notification area;
  # only touched when the state really changes, or the tray icon flickers at 4 Hz
  $sig = "$key|$text"
  if ($app.PrevIconKey -ne $sig) {
    $app.PrevIconKey = $sig
    $ui.Tray.Icon = $app.Icons[$key]
    $ui.Form.Icon = $app.Icons[$key]
    $ui.Tray.Text = "NOW - $text"
  }
  # a balloon only when the window is hidden: with it open, the label already says so
  if ($app.Engine -and $sh -and -not $ui.Form.Visible -and $sh.Online -ne $app.PrevOnline) {
    if ($sh.Online -eq $false) { $ui.Tray.ShowBalloonTip(8000, "NOW", "Sin conexión con NOW. Se sigue intentando.", "Warning") }
    elseif ($sh.Online -eq $true -and $app.PrevOnline -eq $false) { $ui.Tray.ShowBalloonTip(4000, "NOW", "Conexión restablecida.", "Info") }
  }
  if ($app.Engine -and $sh) { $app.PrevOnline = $sh.Online }
}

function Show-MainForm {
  $f = $script:Ui.Form
  $f.Show()
  $f.WindowState = "Normal"
  $f.Activate()
}

function Request-Exit {
  Show-MainForm
  $script:Ui.Form.Close()
}

function New-MainWindow {
  param([hashtable] $Cfg)
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  [System.Windows.Forms.Application]::EnableVisualStyles()

  $app = @{
    Cfg = $Cfg; Roster = @($Cfg.Roster); Engine = $null; Shared = $null; Queue = $null
    Stopping = $false; ForceExit = $false; PrevOnline = $null; PrevIconKey = ""; Icons = @{}; HintShown = $false
  }
  $script:App = $app
  $ui = @{}
  $script:Ui = $ui

  $app.Icons["green"]  = New-StateIcon (ConvertTo-UiColor "ok")
  $app.Icons["yellow"] = New-StateIcon (ConvertTo-UiColor "warn")
  $app.Icons["red"]    = New-StateIcon (ConvertTo-UiColor "bad")
  $app.Icons["gray"]   = New-StateIcon (ConvertTo-UiColor "muted")

  $fontUi = New-Object System.Drawing.Font("Segoe UI", 9)
  $fontBig = New-Object System.Drawing.Font("Segoe UI Semibold", 13)
  $fontTitle = New-Object System.Drawing.Font("Segoe UI Semibold", 12)
  $fontLog = New-Object System.Drawing.Font("Consolas", 9)

  $form = New-Object System.Windows.Forms.Form
  $form.Text = "NOW - Envío del archivo de cronometraje  ($AgentVersion)"
  $form.StartPosition = "CenterScreen"
  $form.ClientSize = New-Object System.Drawing.Size(700, 660)
  $form.MinimumSize = New-Object System.Drawing.Size(640, 600)
  $form.Font = $fontUi
  $ui.Form = $form

  $root = New-Object System.Windows.Forms.TableLayoutPanel
  $root.Dock = "Fill"; $root.ColumnCount = 1; $root.RowCount = 5
  $root.Padding = New-Object System.Windows.Forms.Padding(12)
  [void]$root.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100)))
  foreach ($h in 40, 196, 172, 46) { [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", $h))) }
  [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Percent", 100)))
  $form.Controls.Add($root)

  function New-Lbl {
    param([string] $Text, $Font = $null, [string] $Color = "default")
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text; $l.AutoSize = $true; $l.Anchor = "Left"; $l.TextAlign = "MiddleLeft"
    if ($Font) { $l.Font = $Font }
    $l.ForeColor = ConvertTo-UiColor $Color
    return $l
  }
  function New-Value {
    $l = New-Object System.Windows.Forms.Label
    $l.AutoSize = $false; $l.Dock = "Fill"; $l.TextAlign = "MiddleLeft"; $l.AutoEllipsis = $true
    return $l
  }

  # ---- header
  $root.Controls.Add((New-Lbl "NOW - Envío del archivo de cronometraje" $fontTitle), 0, 0)

  # ---- configuration
  $gc = New-Object System.Windows.Forms.GroupBox
  $gc.Text = "Configuración"; $gc.Dock = "Fill"
  $t = New-Object System.Windows.Forms.TableLayoutPanel
  $t.Dock = "Fill"; $t.ColumnCount = 3; $t.RowCount = 6
  $t.Padding = New-Object System.Windows.Forms.Padding(8, 4, 8, 4)
  [void]$t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 132)))
  [void]$t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100)))
  [void]$t.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 92)))
  foreach ($h in 30, 20, 30, 20, 30, 28) { [void]$t.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", $h))) }
  $gc.Controls.Add($t)
  $root.Controls.Add($gc, 0, 1)

  $cmb = New-Object System.Windows.Forms.ComboBox
  $cmb.DropDownStyle = "DropDownList"; $cmb.Anchor = "Left,Right"
  foreach ($e in $app.Roster) {
    $label = $e.Name
    if ($e.Expires -and $e.Name -notmatch 'vence') { $label += "   (vence $($e.Expires.ToString('yyyy-MM-dd')))" }
    [void]$cmb.Items.Add($label)
  }
  $ui.Console = $cmb
  $ui.ConsoleNote = New-Value
  $ui.Folder = New-Object System.Windows.Forms.TextBox
  $ui.Folder.Anchor = "Left,Right"; $ui.Folder.Text = $Cfg.Folder
  $ui.Browse = New-Object System.Windows.Forms.Button
  $ui.Browse.Text = "Buscar..."; $ui.Browse.Anchor = "Left,Right"
  $ui.FolderNote = New-Value
  $ui.Every = New-Object System.Windows.Forms.NumericUpDown
  $ui.Every.Minimum = 1; $ui.Every.Maximum = 3600; $ui.Every.Width = 64; $ui.Every.Value = [Math]::Min(3600, [Math]::Max(1, $Cfg.Interval))
  $flow = New-Object System.Windows.Forms.FlowLayoutPanel
  $flow.AutoSize = $true; $flow.Anchor = "Left"; $flow.WrapContents = $false
  $flow.Controls.Add($ui.Every)
  $seg = New-Lbl "segundos   (1 es lo ideal: cuanto más rápido mira, mejor se mide la hora)" $null "muted"
  $seg.Margin = New-Object System.Windows.Forms.Padding(4, 6, 0, 0)
  $flow.Controls.Add($seg)
  $ui.Auto = New-Object System.Windows.Forms.CheckBox
  $ui.Auto.Text = "Empezar a enviar apenas se abre el programa"; $ui.Auto.AutoSize = $true; $ui.Auto.Anchor = "Left"
  $ui.Auto.Checked = [bool]$Cfg.AutoStart

  $t.Controls.Add((New-Lbl "Consola de esta PC:"), 0, 0)
  $t.Controls.Add($cmb, 1, 0); $t.SetColumnSpan($cmb, 2)
  $t.Controls.Add($ui.ConsoleNote, 1, 1); $t.SetColumnSpan($ui.ConsoleNote, 2)
  $t.Controls.Add((New-Lbl "Carpeta de eventos:"), 0, 2)
  $t.Controls.Add($ui.Folder, 1, 2)
  $t.Controls.Add($ui.Browse, 2, 2)
  $t.Controls.Add($ui.FolderNote, 1, 3); $t.SetColumnSpan($ui.FolderNote, 2)
  $t.Controls.Add((New-Lbl "Revisar cada:"), 0, 4)
  $t.Controls.Add($flow, 1, 4); $t.SetColumnSpan($flow, 2)
  $t.Controls.Add($ui.Auto, 0, 5); $t.SetColumnSpan($ui.Auto, 3)

  # ---- status
  $gs = New-Object System.Windows.Forms.GroupBox
  $gs.Text = "Estado"; $gs.Dock = "Fill"
  $st = New-Object System.Windows.Forms.TableLayoutPanel
  $st.Dock = "Fill"; $st.ColumnCount = 2; $st.RowCount = 6
  $st.Padding = New-Object System.Windows.Forms.Padding(8, 2, 8, 2)
  [void]$st.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Absolute", 132)))
  [void]$st.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle("Percent", 100)))
  foreach ($h in 32, 22, 22, 22, 22, 22) { [void]$st.RowStyles.Add((New-Object System.Windows.Forms.RowStyle("Absolute", $h))) }
  $gs.Controls.Add($st)
  $root.Controls.Add($gs, 0, 2)
  $ui.State = New-Lbl "" $fontBig
  $st.Controls.Add($ui.State, 0, 0); $st.SetColumnSpan($ui.State, 2)
  $ui.Conn = New-Value; $ui.Last = New-Value; $ui.Race = New-Value; $ui.Clock = New-Value; $ui.Watch = New-Value
  $row = 1
  foreach ($pair in @(@("Conexión:", $ui.Conn), @("Último envío:", $ui.Last), @("Carrera:", $ui.Race), @("Reloj de la PC:", $ui.Clock), @("Carpeta:", $ui.Watch))) {
    $st.Controls.Add((New-Lbl $pair[0] $null "muted"), 0, $row)
    $st.Controls.Add($pair[1], 1, $row)
    $row++
  }

  # ---- buttons
  $bar = New-Object System.Windows.Forms.FlowLayoutPanel
  $bar.Dock = "Fill"; $bar.FlowDirection = "LeftToRight"; $bar.WrapContents = $false
  function New-Btn {
    param([string] $Text, [int] $Width)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text; $b.Size = New-Object System.Drawing.Size($Width, 34)
    $b.Margin = New-Object System.Windows.Forms.Padding(0, 6, 8, 0)
    return $b
  }
  $ui.Start = New-Btn "Iniciar envío" 150
  $ui.Start.BackColor = [System.Drawing.Color]::FromArgb(0, 128, 0); $ui.Start.ForeColor = [System.Drawing.Color]::White
  $ui.Start.FlatStyle = "Flat"; $ui.Start.Font = New-Object System.Drawing.Font("Segoe UI Semibold", 9)
  $ui.Stop = New-Btn "Detener" 110
  $ui.Save = New-Btn "Guardar ajustes" 130
  $ui.OpenLog = New-Btn "Abrir el registro" 140
  foreach ($b in $ui.Start, $ui.Stop, $ui.Save, $ui.OpenLog) { $bar.Controls.Add($b) }
  $root.Controls.Add($bar, 0, 3)

  # ---- log
  $gl = New-Object System.Windows.Forms.GroupBox
  $gl.Text = "Registro"; $gl.Dock = "Fill"
  $ui.Log = New-Object System.Windows.Forms.RichTextBox
  $ui.Log.Dock = "Fill"; $ui.Log.ReadOnly = $true; $ui.Log.BackColor = [System.Drawing.Color]::White
  $ui.Log.Font = $fontLog; $ui.Log.DetectUrls = $false; $ui.Log.BorderStyle = "None"
  $gl.Controls.Add($ui.Log)
  $root.Controls.Add($gl, 0, 4)

  # ---- notification area
  $menu = New-Object System.Windows.Forms.ContextMenuStrip
  $miOpen = $menu.Items.Add("Abrir la ventana")
  $ui.Toggle = $menu.Items.Add("Iniciar el envío")
  [void]$menu.Items.Add("-")
  $miExit = $menu.Items.Add("Salir")
  $tray = New-Object System.Windows.Forms.NotifyIcon
  $tray.ContextMenuStrip = $menu; $tray.Visible = $true; $tray.Text = "NOW"
  $ui.Tray = $tray
  $ui.Timer = New-Object System.Windows.Forms.Timer
  $ui.Timer.Interval = 250

  # ---- initial state
  $sel = $Cfg.Console
  if ($sel) { for ($i = 0; $i -lt $app.Roster.Count; $i++) { if ($app.Roster[$i].Token -eq $sel.Token) { $cmb.SelectedIndex = $i; break } } }
  Set-UiRunning $false
  Update-ConfigNotes
  Update-UiStatus

  # ---- handlers. Every body is wrapped: an exception that escapes a WinForms
  # handler pops the .NET "unhandled exception" box in the timekeeper's face.
  $ui.Console.Add_SelectedIndexChanged({ try { Update-ConfigNotes } catch {} })
  $ui.Folder.Add_TextChanged({ try { Update-ConfigNotes } catch {} })
  $ui.Browse.Add_Click({
    try {
      $d = New-Object System.Windows.Forms.FolderBrowserDialog
      $d.Description = "Elegí la carpeta donde SKI PRO guarda los eventos (los archivos Event*.scdb)"
      $d.ShowNewFolderButton = $false
      if (Test-Path -LiteralPath $script:Ui.Folder.Text -PathType Container) { $d.SelectedPath = $script:Ui.Folder.Text }
      if ($d.ShowDialog() -eq "OK") { $script:Ui.Folder.Text = $d.SelectedPath }
    } catch {}
  })
  $ui.Save.Add_Click({
    try {
      $err = Save-UiSettings
      if ($err) { [void][System.Windows.Forms.MessageBox]::Show("No se pudieron guardar los ajustes:`n$err", "NOW", "OK", "Warning") }
      else { Add-UiLog (Get-Date) "Ajustes guardados en settings.txt" "DarkGray" }
    } catch {}
  })
  $ui.Start.Add_Click({ try { Start-Sending } catch { Add-UiLog (Get-Date) "$($_.Exception.Message)" "Red" } })
  $ui.Stop.Add_Click({ try { Stop-Sending } catch {} })
  $ui.OpenLog.Add_Click({
    try {
      if (Test-Path -LiteralPath $script:App.Cfg.LogFile) { Start-Process notepad.exe -ArgumentList "`"$($script:App.Cfg.LogFile)`"" }
      else { [void][System.Windows.Forms.MessageBox]::Show("Todavía no hay registro: se crea al iniciar el envío.", "NOW", "OK", "Information") }
    } catch {}
  })

  $ui.Timer.Add_Tick({
    try {
      $app = $script:App
      if ($app.Queue) {
        $item = $null; $n = 0
        while ($n -lt 200 -and $app.Queue.TryDequeue([ref]$item)) {
          $n++
          if ($item.Kind -eq "say") { Add-UiLog $item.Time $item.Text $item.Color }
        }
      }
      Update-UiStatus
      if ($app.Engine -and $app.Engine.Handle.IsCompleted -and $app.Queue.IsEmpty) { Complete-Run; Update-UiStatus }
    } catch {}
  })

  # MINIMISE = to the notification area, still sending. THE X IS DIFFERENT ON PURPOSE:
  # in ps-0.7.0 closing the window stopped the agent, so anyone who closes it expects
  # that — and a race whose file stopped going out because somebody tidied the screen
  # is the costly mistake. So the X asks, while sending.
  $form.Add_Resize({
    try {
      if ($script:Ui.Form.WindowState -eq "Minimized") {
        $script:Ui.Form.Hide()
        if (-not $script:App.HintShown) {
          $script:App.HintShown = $true
          $script:Ui.Tray.ShowBalloonTip(5000, "NOW", "Sigue funcionando acá abajo, junto al reloj. Doble clic en el ícono para abrir la ventana.", "Info")
        }
      }
    } catch {}
  })
  $form.Add_FormClosing({
    param($sender, $e)
    try {
      # UserClosing only: a question on the screen while Windows shuts down would
      # block the shutdown
      if ($e.CloseReason -eq "UserClosing" -and -not $script:App.ForceExit -and $script:App.Engine) {
        $r = [System.Windows.Forms.MessageBox]::Show("El envío está activo.`n`n¿Detenerlo y cerrar el programa?`n(Para dejarlo funcionando, minimizá la ventana en lugar de cerrarla.)", "NOW", "YesNo", "Warning", "Button2")
        if ($r -ne "Yes") { $e.Cancel = $true }
      }
    } catch {}
  })
  $form.Add_FormClosed({
    try {
      $script:Ui.Timer.Stop()
      $script:Ui.Tray.Visible = $false
      $script:Ui.Tray.Dispose()
      if ($script:App.Shared) { $script:App.Shared.Stop = $true }
      Stop-Engine $script:App.Engine -Force
    } catch {}
  })
  $tray.Add_DoubleClick({ try { Show-MainForm } catch {} })
  $miOpen.Add_Click({ try { Show-MainForm } catch {} })
  $miExit.Add_Click({ try { Request-Exit } catch {} })
  $ui.Toggle.Add_Click({ try { if ($script:App.Engine) { Stop-Sending } else { Start-Sending } } catch {} })
  $form.Add_Shown({
    try {
      if ($script:App.Cfg.AutoStart -and $script:Ui.Console.SelectedIndex -ge 0) { Start-Sending -Auto }
      elseif ($script:App.Cfg.AutoStart) { Add-UiLog (Get-Date) "Elegí la consola de esta PC y apretá Iniciar envío." "Yellow" }
    } catch {}
  })
  foreach ($w in $Cfg.Warnings) { Add-UiLog (Get-Date) "AVISO: $w" "Yellow" }
  $ui.Timer.Start()
}

# ============================================================================
#  MAIN
# ============================================================================
# dot-sourced by tests\Test-Agent.ps1: definitions only, nothing runs
if ($MyInvocation.InvocationName -eq ".") { return }

if ($Once) { $NoGui = $true }
$Cli = @{ Token = $Token; Folder = $Folder; Url = $Url; Interval = $IntervalSeconds; Event = $Event }
$Cfg = Get-AgentConfig -Dir $PSScriptRoot -Cli $Cli

# ONE AGENT PER PC. Two of them would upload every change twice, and a double-click on
# start-agent.bat while the first is minimised in the notification area is exactly
# what a hurried person does. (-Once is a test: it may run beside a live one.)
$mutex = $null
if (-not $Once) {
  $created = $false
  $mutex = New-Object System.Threading.Mutex($true, "Local\NOW-console-agent", [ref]$created)
  if (-not $created) {
    $msg = "Ya hay un agente abierto en esta PC. Buscá su ícono junto al reloj de Windows (puede estar escondido en la flecha ^)."
    if ($NoGui) { Write-Host $msg -ForegroundColor Yellow }
    else {
      Add-Type -AssemblyName System.Windows.Forms
      [void][System.Windows.Forms.MessageBox]::Show($msg, "NOW", "OK", "Information")
    }
    exit 4
  }
}

try {
  if ($NoGui) {
    if (-not $Cfg.Token) { Write-Host "No hay token. Pedile uno a NOW y ponelo en settings.txt" -ForegroundColor Red; exit 2 }
    if (-not (Test-Path -LiteralPath $Cfg.Folder)) {
      Write-Host "Esa carpeta no existe: $($Cfg.Folder)" -ForegroundColor Red
      Write-Host "Busca en esta PC un archivo llamado Event*.scdb y pone esa ruta en settings.txt"
      exit 2
    }
    $name = if ($Cfg.Console) { $Cfg.Console.Name } else { "" }
    $code = Invoke-Headless (New-EngineConfig -Cfg $Cfg -Token $Cfg.Token -Folder $Cfg.Folder -Interval $Cfg.Interval -ConsoleName $name -Once ([bool]$Once))
    exit $code
  } else {
    try {
      New-MainWindow -Cfg $Cfg
      [System.Windows.Forms.Application]::Run($script:Ui.Form)
    } catch {
      try { Add-Content -Path $Cfg.LogFile -Value ("{0}  ERROR en la ventana: {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $_.Exception.Message) -Encoding UTF8 } catch {}
      [void][System.Windows.Forms.MessageBox]::Show("El programa no pudo abrir su ventana:`n`n$($_.Exception.Message)`n`nMandale el archivo now-console-agent.log a NOW.", "NOW", "OK", "Error")
      exit 1
    }
  }
} finally {
  if ($mutex) { try { $mutex.ReleaseMutex() } catch {}; $mutex.Dispose() }
}
