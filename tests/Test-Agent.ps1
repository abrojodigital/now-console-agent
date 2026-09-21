<#
  Tests for now-console-agent.ps1 — no framework, no network.

    powershell -STA -NoProfile -ExecutionPolicy Bypass -File tests\Test-Agent.ps1

  -STA because the window tests build real WinForms controls. Exit code = number of
  failures. The engine tests point the agent at http://127.0.0.1:9 (a closed local
  port) with FAKE tokens, so nothing here ever reaches now-ski.com.
#>
$agent = Join-Path $PSScriptRoot "..\now-console-agent.ps1"
$script:Pass = 0
$script:Fail = 0
function Assert {
  param($Condition, [string] $Name)
  if ($Condition) { $script:Pass++; Write-Host "  ok    $Name" -ForegroundColor Green }
  else { $script:Fail++; Write-Host "  FAIL  $Name" -ForegroundColor Red }
}
function Section { param([string] $t) Write-Host ""; Write-Host $t -ForegroundColor Cyan }

$work = Join-Path $env:TEMP ("now-agent-test-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $work | Out-Null

# a settings.txt shaped like the one pack.mjs ships: two ACTIVE tokens (the mistake we
# are designing out), three commented, one of them with no name above it. LF endings and
# no BOM, on purpose: that is what a generator writes.
$fixture = @"
carpeta = C:\Fake\Events\
cada = 1

# Ana Uno - Cerro A   (vence 2099-01-01)
token = nowc_FAKE_aaaaaaaaaaaaaaaa

# Beto Dos - Cerro B   (vence 2099-01-01)
token = nowc_FAKE_bbbbbbbbbbbbbbbb

# LENGA - consola sin asignar   (vence 2020-01-01)
# token = nowc_FAKE_cccccccccccccccc

# token = nowc_FAKE_dddd

servidor = https://now-ski.com/api/console/file
"@ -replace "`r`n", "`n"
function New-Fixture {
  param([string] $Dir, [string] $Text = $fixture)
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $Dir "settings.txt"), $Text, (New-Object System.Text.UTF8Encoding($false)))
}

Section "The file itself"
$bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $agent))
Assert ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) "now-console-agent.ps1 is UTF-8 WITH BOM (PS 5.1 reads BOM-less as ANSI: accents become mojibake)"
$errs = $null; $tok = $null
[void][System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $agent), [ref]$tok, [ref]$errs)
Assert ($errs.Count -eq 0) "parses without syntax errors"

. $agent    # definitions only: the script returns early when dot-sourced

Section "Format-FolderPath"
Assert ((Format-FolderPath "C:\SkiPro\Events\") -eq "C:\SkiPro\Events") "trailing backslash is removed"
Assert ((Format-FolderPath "C:\") -eq "C:\") "a bare drive root keeps its backslash (C:\ is not C:)"
Assert ((Format-FolderPath "  D:\x  ") -eq "D:\x") "surrounding spaces are trimmed"

Section "Read-SettingsFile: the roster"
$d1 = Join-Path $work "roster"; New-Fixture $d1
$s = Read-SettingsFile (Join-Path $d1 "settings.txt")
Assert ($s.Roster.Count -eq 4) "every token line is a candidate, active or commented (got $($s.Roster.Count))"
Assert ($s.Roster[0].Name -eq "Ana Uno - Cerro A" -and $s.Roster[0].Active) "name comes from the comment above; active flag read"
Assert ($s.Roster[0].Expires -eq [datetime]"2099-01-01") "expiry parsed from '(vence YYYY-MM-DD)'"
Assert (-not $s.Roster[2].Active -and $s.Roster[2].Token -eq "nowc_FAKE_cccccccccccccccc") "a commented token is in the roster, not active"
Assert ($s.Roster[3].Name -like "Consola 4 (token ...dddd)") "no name above: falls back to the last 4 characters, never the whole token"
Assert ($s.ActiveTokens.Count -eq 2) "two active tokens detected"
Assert ($s.Duplicates -contains "token") "two active tokens are reported as a duplicate"
Assert ($s.Values["folder"] -eq "C:\Fake\Events\") "plain settings still read"

Section "Select-Console"
Assert ($null -eq (Select-Console $s.Roster "")) "two active tokens and no choice: nobody (the window must ask)"
Assert ((Select-Console $s.Roster "Beto Dos - Cerro B").Token -eq "nowc_FAKE_bbbbbbbbbbbbbbbb") "an explicit choice wins over the file order"
Assert ((Select-Console $s.Roster "beto dos - cerro b") -ne $null) "the choice is matched ignoring case"
Assert ((Select-Console $s.Roster "does not exist") -eq $null) "an unknown name does not silently pick another console"
$one = @(@{ Name = "Solo"; Token = "t1"; Expires = $null; Active = $true }, @{ Name = "Otra"; Token = "t2"; Expires = $null; Active = $false })
Assert ((Select-Console $one "").Name -eq "Solo") "exactly one active token is unambiguous (legacy files keep working)"

Section "Get-AgentConfig"
$c = Get-AgentConfig -Dir $d1 -Cli @{}
Assert ($null -eq $c.Console) "ambiguous file: no console selected"
Assert ($c.Token -eq "nowc_FAKE_aaaaaaaaaaaaaaaa") "headless keeps the legacy rule: the first active token wins"
Assert (($c.Warnings -join " ") -like "*mas de un 'token'*") "and says so out loud"
Assert ($c.Folder -eq "C:\Fake\Events") "folder is cleaned"
Assert ($c.Interval -eq 1 -and $c.AutoStart) "defaults: 1 s tick, start on open"
$c2 = Get-AgentConfig -Dir $d1 -Cli @{ Token = "nowc_FAKE_cli"; Folder = "E:\cli\" ; Interval = 5 }
Assert ($c2.Token -eq "nowc_FAKE_cli" -and $c2.Folder -eq "E:\cli" -and $c2.Interval -eq 5) "command line wins over settings.txt"
Assert ($c2.Console.Name -like "*linea de comandos*") "a -Token appears as a console of its own"
$d0 = Join-Path $work "empty"; New-Item -ItemType Directory -Force -Path $d0 | Out-Null
$c0 = Get-AgentConfig -Dir $d0 -Cli @{}
Assert ($c0.Token -eq "" -and $c0.Folder -eq "C:\SkiPro\SkiPro222\Events" -and $c0.Roster.Count -eq 0) "no settings.txt at all: defaults, empty roster, no crash"
$dj = Join-Path $work "legacyjson"; New-Item -ItemType Directory -Force -Path $dj | Out-Null
[System.IO.File]::WriteAllText((Join-Path $dj "now-console-agent.config.json"), '{"Token":"nowc_FAKE_json","Folder":"F:\\json"}')
$cj = Get-AgentConfig -Dir $dj -Cli @{}
Assert ($cj.Token -eq "nowc_FAKE_json" -and $cj.Folder -eq "F:\json") "the ps-0.4/0.5 JSON still works"
$dc = Join-Path $work "clamp"; New-Fixture $dc "cada = 0`ntoken = t"
Assert ((Get-AgentConfig -Dir $dc -Cli @{}).Interval -eq 1) "interval below 1 s is raised to 1"
$dn = Join-Path $work "clamp2"; New-Fixture $dn "cada = banana`ntoken = t"
Assert ((Get-AgentConfig -Dir $dn -Cli @{}).Interval -eq 1) "a non-number interval falls back to 1 instead of crashing"

Section "Save-SettingsFile"
$p = Join-Path $d1 "settings.txt"
$err = Save-SettingsFile $p @{ folder = "D:\Otra Carpeta"; interval = 3; console = "Beto Dos - Cerro B"; autostart = "no" }
Assert ($null -eq $err) "saves without error ($err)"
$s2 = Read-SettingsFile $p
Assert ($s2.Values["folder"] -eq "D:\Otra Carpeta" -and $s2.Values["interval"] -eq "3") "existing keys are replaced in place"
Assert ($s2.Values["console"] -eq "Beto Dos - Cerro B" -and $s2.Values["autostart"] -eq "no") "missing keys are appended"
Assert ($s2.Roster.Count -eq 4 -and $s2.ActiveTokens.Count -eq 2) "the roster of tokens is untouched"
Assert ((($s2.Roster | ForEach-Object { $_.Token }) -join ",") -eq (($s.Roster | ForEach-Object { $_.Token }) -join ",")) "every token is byte-identical"
$raw = [System.IO.File]::ReadAllText($p)
Assert ($raw.Contains("# Ana Uno - Cerro A   (vence 2099-01-01)")) "comments are preserved exactly"
Assert (([regex]::Matches($raw, "(?<!\r)\n")).Count -eq 0) "line endings are CRLF, so Notepad shows it properly"
$rb = [System.IO.File]::ReadAllBytes($p)
Assert ($rb[0] -eq 0xEF -and $rb[1] -eq 0xBB -and $rb[2] -eq 0xBF) "written with a BOM (an accent in a folder name survives old Notepad)"
Assert (-not (Test-Path "$p.tmp")) "no .tmp left behind"
Save-SettingsFile $p @{ folder = "D:\Otra Carpeta"; interval = 3; console = "Beto Dos - Cerro B"; autostart = "no" } | Out-Null
Assert ([System.IO.File]::ReadAllText($p) -eq $raw) "saving the same values twice changes nothing (idempotent)"
$c3 = Get-AgentConfig -Dir $d1 -Cli @{}
Assert ($c3.Console.Name -eq "Beto Dos - Cerro B" -and $c3.Token -eq "nowc_FAKE_bbbbbbbbbbbbbbbb") "after choosing, that console's token is the one used"
Assert (-not (($c3.Warnings -join " ") -like "*mas de un 'token'*")) "and the two-active-tokens warning is gone: the choice is explicit"
Assert (-not $c3.AutoStart) "autostart = no is honoured"
$dz = Join-Path $work "accent"; New-Fixture $dz "token = t"
Save-SettingsFile (Join-Path $dz "settings.txt") @{ folder = "C:\Cronometraje Ñandú\events" } | Out-Null
Assert ((Get-AgentConfig -Dir $dz -Cli @{}).Folder -eq "C:\Cronometraje Ñandú\events") "a folder with accents round-trips"
$dnew = Join-Path $work "newfile"; New-Item -ItemType Directory -Force -Path $dnew | Out-Null
Assert ($null -eq (Save-SettingsFile (Join-Path $dnew "settings.txt") @{ folder = "X:\a" })) "creates settings.txt when there is none"

Section "Get-ExpiryNote"
Assert ((Get-ExpiryNote @{ Expires = [datetime]"2020-01-01" }).Level -eq "bad") "expired token: red"
Assert ((Get-ExpiryNote @{ Expires = (Get-Date).Date.AddDays(5) }).Level -eq "warn") "expires within 14 days: warning"
Assert ((Get-ExpiryNote @{ Expires = [datetime]"2099-01-01" }).Level -eq "muted") "far away: just informational"
Assert ((Get-ExpiryNote $null).Text -eq "") "no entry, no note"

Section "Get-FolderInfo"
$ev = Join-Path $work "Events"; New-Item -ItemType Directory -Force -Path $ev | Out-Null
Assert ((Get-FolderInfo (Join-Path $work "nope")).Level -eq "bad") "missing folder: red"
Assert ((Get-FolderInfo $ev).Level -eq "muted") "existing but empty folder is fine (before the first race)"
[System.IO.File]::WriteAllBytes((Join-Path $ev "Event001.scdb"), [byte[]](1..64))
[System.IO.File]::WriteAllBytes((Join-Path $ev "Event001Ex.scdb"), [byte[]](1..64))
$fi = Get-FolderInfo "$ev\"
Assert ($fi.Level -eq "ok" -and $fi.Text -like "*Event001*") "finds the newest event; a trailing backslash is fine"

Section "Engine: the network is down (regression: ps-0.7.0 died here)"
# ps-0.7.0 called Send-Heartbeat outside any try/catch, and Windows PowerShell 5.1 throws
# on curl's stderr under $ErrorActionPreference = Stop: a dropped connection killed the
# agent. Here the "server" is a closed local port, so curl fails exactly like that.
$de = Join-Path $work "engine"
New-Fixture $de "carpeta = $ev`nservidor = http://127.0.0.1:9/api/console/file`ntoken = nowc_FAKE_engine"
$ce = Get-AgentConfig -Dir $de -Cli @{}
function Wait-For {
  param([scriptblock] $Until, [int] $Seconds)
  $end = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $end) { if (& $Until) { return $true }; Start-Sleep -Milliseconds 100 }
  return $false
}
$q = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$sh = New-SharedState
$eng = Start-Engine (New-EngineConfig -Cfg $ce -Token $ce.Token -Folder $ce.Folder -Interval 1 -ConsoleName "test") $sh $q
$sawOffline = Wait-For { $sh.Online -eq $false } 30
Assert $sawOffline "engine notices the connection is down (Online = false)"
Start-Sleep -Seconds 4
Assert (-not $eng.Handle.IsCompleted) "engine is STILL RUNNING after failed uploads and a failed heartbeat"
$sh.Stop = $true
$stopped = Wait-For { $eng.Handle.IsCompleted } 10
Assert $stopped "Stop is honoured promptly"
Assert ($sh.State -eq "stopped") "state ends as stopped"
$lines = @(); $it = $null
while ($q.TryDequeue([ref]$it)) { if ($it.Kind -eq "say") { $lines += $it.Text } }
Assert (($lines -join "`n") -like "*sin conexion con NOW*") "the connection alarm is raised"
Assert (@($lines | Where-Object { $_ -like "no enviado*" }).Count -le 3) "failures are throttled, not one line per second (got $(@($lines | Where-Object { $_ -like 'no enviado*' }).Count))"
Assert ($eng.Ps.HadErrors -eq $false) "nothing escaped the engine as an error"
Stop-Engine $eng
Assert (Test-Path (Join-Path $de "now-console-agent.log")) "the log file is written"

Section "Engine: -Once"
$q2 = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$sh2 = New-SharedState
$eng2 = Start-Engine (New-EngineConfig -Cfg $ce -Token $ce.Token -Folder $ce.Folder -Interval 1 -ConsoleName "test" -Once $true) $sh2 $q2
Assert (Wait-For { $eng2.Handle.IsCompleted } 40) "-Once sends once and finishes by itself"
Stop-Engine $eng2

Section "Engine: no file yet, and a write in flight"
$empty = Join-Path $work "EmptyEvents"; New-Item -ItemType Directory -Force -Path $empty | Out-Null
$q3 = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$sh3 = New-SharedState
$cfg3 = New-EngineConfig -Cfg $ce -Token $ce.Token -Folder $empty -Interval 1 -ConsoleName "test"
$eng3 = Start-Engine $cfg3 $sh3 $q3
Assert (Wait-For { $sh3.Tick -eq "?" } 30) "empty folder: waits with '?', no crash"
$sh3.Stop = $true; [void](Wait-For { $eng3.Handle.IsCompleted } 10); Stop-Engine $eng3
$jf = Join-Path $ev "Event001Ex.scdb-journal"
[System.IO.File]::WriteAllText($jf, "x")
$q4 = New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]'
$sh4 = New-SharedState
$eng4 = Start-Engine (New-EngineConfig -Cfg $ce -Token $ce.Token -Folder $ev -Interval 1 -ConsoleName "test") $sh4 $q4
Assert (Wait-For { $sh4.Tick -eq "w" } 30) "a -journal beside the database: waits with 'w', does not copy half a transaction"
$sh4.Stop = $true; [void](Wait-For { $eng4.Handle.IsCompleted } 10); Stop-Engine $eng4
Remove-Item $jf -Force

Section "Window"
Add-Type -AssemblyName System.Windows.Forms
$dw = Join-Path $work "win"; New-Fixture $dw
$cw = Get-AgentConfig -Dir $dw -Cli @{}
New-MainWindow -Cfg $cw
Assert ($script:Ui.Console.Items.Count -eq 4) "the dropdown lists every console in the roster"
Assert ($script:Ui.Console.SelectedIndex -eq -1) "two active tokens: nothing is preselected"
Assert ($script:Ui.ConsoleNote.Text -like "Eleg*") "and the window asks her to choose"
Assert ($script:Ui.Start.Enabled -and -not $script:Ui.Stop.Enabled) "Iniciar enabled, Detener disabled while stopped"
Assert ((Get-StartProblem) -like "Eleg*") "Iniciar without a console is refused with a reason"
$script:Ui.Console.SelectedIndex = 1
Assert ($null -ne (Get-StartProblem) -and (Get-StartProblem) -like "*no existe*") "a console chosen but a missing folder is still refused"
$script:Ui.Folder.Text = $ev
Assert ($null -eq (Get-StartProblem)) "console + existing folder: ready to start"
Assert ($script:Ui.FolderNote.Text -like "Correcto*") "the folder note turns green"
$script:Ui.Timer.Stop(); $script:Ui.Tray.Visible = $false; $script:Ui.Tray.Dispose(); $script:Ui.Form.Dispose()
$dw2 = Join-Path $work "win2"; New-Fixture $dw2 ($fixture + "`nconsola = Beto Dos - Cerro B`n")
New-MainWindow -Cfg (Get-AgentConfig -Dir $dw2 -Cli @{})
Assert ($script:Ui.Console.SelectedIndex -eq 1) "a saved choice is preselected"
$script:Ui.Timer.Stop(); $script:Ui.Tray.Visible = $false; $script:Ui.Tray.Dispose(); $script:Ui.Form.Dispose()

Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
Write-Host ""
$color = if ($script:Fail -eq 0) { "Green" } else { "Red" }
Write-Host ("{0} passed, {1} failed" -f $script:Pass, $script:Fail) -ForegroundColor $color
exit $script:Fail
