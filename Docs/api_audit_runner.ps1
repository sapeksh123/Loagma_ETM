$ErrorActionPreference = 'Stop'

$base = 'https://loagma-etm.onrender.com/api'
$now = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
$outJson = "D:/ADRS-ALL/Loagma_ETM/Docs/api_audit_$now.json"
$outMd = "D:/ADRS-ALL/Loagma_ETM/Docs/api_audit_$now.md"

function Clip([string]$s, [int]$max = 900) {
  if ($null -eq $s) { return '' }
  if ($s.Length -le $max) { return $s }
  return $s.Substring(0, $max) + ' ...<truncated>'
}

function Invoke-Probe {
  param(
    [string]$Method,
    [string]$Route,
    [hashtable]$Headers,
    [object]$Body,
    [int]$TimeoutSec = 30,
    [string]$Tag = ''
  )

  $uri = "$base$Route"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $status = 'ERR'
  $respBody = ''

  try {
    $params = @{ UseBasicParsing = $true; Method = $Method; Uri = $uri; TimeoutSec = $TimeoutSec }
    if ($Headers) { $params['Headers'] = $Headers }
    if ($null -ne $Body) {
      $params['ContentType'] = 'application/json'
      if ($Body -is [string]) { $params['Body'] = $Body }
      else { $params['Body'] = ($Body | ConvertTo-Json -Depth 10 -Compress) }
    }

    $r = Invoke-WebRequest @params
    $status = [int]$r.StatusCode
    $respBody = Clip $r.Content
  }
  catch {
    if ($_.Exception.Message -match 'timed out' -or $_.Exception.Message -match 'timeout') {
      $status = 'TIMEOUT'
      $respBody = Clip $_.Exception.Message
    }
    elseif ($_.Exception.Response) {
      $status = [int]$_.Exception.Response.StatusCode.value__
      try {
        $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $respBody = Clip ($sr.ReadToEnd())
      }
      catch {
        $respBody = Clip $_.Exception.Message
      }
    }
    else {
      $status = 'ERR'
      $respBody = Clip $_.Exception.Message
    }
  }

  $sw.Stop()

  [PSCustomObject]@{
    method = $Method
    route = $Route
    status = $status
    latency_ms = [int]$sw.Elapsed.TotalMilliseconds
    body = $respBody
    tag = $Tag
    timeout_sec = $TimeoutSec
  }
}

function Category([object]$status) {
  if ($status -is [int]) {
    if ($status -in 200, 201) { return 'PASS' }
    if ($status -in 400, 401, 403, 404, 422) { return 'VALIDATION_FAIL' }
    if ($status -ge 500) { return 'FAIL' }
    return 'UNTESTED'
  }

  if ($status -eq 'TIMEOUT' -or $status -eq 'ERR') { return 'FAIL' }
  return 'UNTESTED'
}

function FrontConsumer([string]$route) {
  switch -Regex ($route) {
    '^/health$' { 'none'; break }
    '^/db-test$' { 'none'; break }
    '^/users$' { 'auth_service, chat_service, employees_screen'; break }
    '^/users/by-contact/' { 'auth_service'; break }
    '^/roles$' { 'not observed in client'; break }
    '^/departments$' { 'not observed in client'; break }
    '^/tasks' { 'task_service'; break }
    '^/notes' { 'note_service'; break }
    '^/attendance' { 'attendance_service'; break }
    '^/dashboard/summary$' { 'dashboard_service'; break }
    '^/notifications' { 'notification_service'; break }
    '^/chat/realtime/auth$' { 'chat_service/chat_realtime_client'; break }
    '^/chat/threads/direct$' { 'chat_service'; break }
    '^/chat/threads/broadcast$' { 'not observed in client'; break }
    '^/chat/threads/.*/messages/.*/reactions$' { 'reaction endpoints not observed in client'; break }
    '^/chat/threads/.*/messages/.*/delivered$' { 'not observed in client (uses receipts)'; break }
    '^/chat/threads/.*/messages/.*/seen$' { 'not observed in client (uses receipts)'; break }
    '^/chat/threads/.*/read$' { 'not observed in client (uses receipts)'; break }
    '^/chat/threads/.*/messages$' { 'chat_service'; break }
    '^/chat/threads/.*/receipts$' { 'chat_service'; break }
    '^/chat/threads/.*/typing$' { 'chat_service'; break }
    '^/chat/threads$' { 'chat_service'; break }
    '^/chat/presence$' { 'chat_service'; break }
    default { 'unknown' }
  }
}

$results = New-Object System.Collections.Generic.List[object]
$publicHeaders = @{ 'Accept' = 'application/json' }

$usersProbe = Invoke-Probe -Method 'GET' -Route '/users?per_page=5&page=1' -Headers $publicHeaders -Body $null -TimeoutSec 30 -Tag 'bootstrap'
$results.Add($usersProbe)
$uid = 'U029'
$uid2 = 'U021'

if ($usersProbe.status -eq 200) {
  try {
    $uj = $usersProbe.body | ConvertFrom-Json
    if ($uj.data.Count -gt 0) { $uid = [string]$uj.data[0].id }
    if ($uj.data.Count -gt 1) { $uid2 = [string]$uj.data[1].id }
  }
  catch {}
}

$chatHeaders = @{ 'Accept' = 'application/json'; 'X-User-Id' = $uid; 'X-User-Role' = 'admin' }

$taskCreate = Invoke-Probe -Method 'POST' -Route '/tasks' -Headers $publicHeaders -Body @{ title = 'API Audit Task'; description = 'created by audit'; category = 'project'; priority = 'medium'; assigned_to = $uid2; created_by = $uid; subtasks = @('one', 'two') } -TimeoutSec 30 -Tag 'setup'
$results.Add($taskCreate)
$taskId = ''
if ($taskCreate.status -in 200, 201) {
  try { $taskId = ($taskCreate.body | ConvertFrom-Json).data.id }
  catch {}
}

if ([string]::IsNullOrWhiteSpace($taskId)) {
  $tasksList = Invoke-Probe -Method 'GET' -Route "/tasks?user_id=$uid&user_role=admin" -Headers $publicHeaders -Body $null -TimeoutSec 30 -Tag 'setup-fallback'
  $results.Add($tasksList)
  if ($tasksList.status -eq 200) {
    try { $taskId = ($tasksList.body | ConvertFrom-Json).data[0].id }
    catch {}
  }
}

$noteCreate = Invoke-Probe -Method 'POST' -Route '/notes' -Headers $publicHeaders -Body @{ user_id = $uid; folder_name = 'General'; title = 'API Audit Note'; content = 'hello' } -TimeoutSec 30 -Tag 'setup'
$results.Add($noteCreate)
$noteId = ''
if ($noteCreate.status -in 200, 201) {
  try { $noteId = ($noteCreate.body | ConvertFrom-Json).data.id }
  catch {}
}

$checks = @(
  @{ m = 'GET'; r = '/health'; b = $null; h = $publicHeaders },
  @{ m = 'GET'; r = '/db-test'; b = $null; h = $publicHeaders },
  @{ m = 'GET'; r = '/users?per_page=2&page=1'; b = $null; h = $publicHeaders },
  @{ m = 'GET'; r = '/users/by-contact/8019500007'; b = $null; h = $publicHeaders },
  @{ m = 'GET'; r = '/roles'; b = $null; h = $publicHeaders },
  @{ m = 'GET'; r = '/departments'; b = $null; h = $publicHeaders },
  @{ m = 'GET'; r = "/tasks?user_id=$uid&user_role=admin"; b = $null; h = $publicHeaders },
  @{ m = 'POST'; r = '/tasks'; b = @{ title = ''; created_by = $uid; assigned_to = $uid2 }; h = $publicHeaders },
  @{ m = 'GET'; r = $(if ($taskId) { "/tasks/$taskId" } else { '/tasks/__missing__' }); b = $null; h = $publicHeaders },
  @{ m = 'PUT'; r = $(if ($taskId) { "/tasks/$taskId" } else { '/tasks/__missing__' }); b = @{ title = 'API Audit Task Updated'; priority = 'high'; status = 'in_progress' }; h = $publicHeaders },
  @{ m = 'DELETE'; r = $(if ($taskId) { "/tasks/$taskId" } else { '/tasks/__missing__' }); b = $null; h = $publicHeaders },
  @{ m = 'PATCH'; r = $(if ($taskId) { "/tasks/$taskId/status" } else { '/tasks/__missing__/status' }); b = @{ status = 'completed' }; h = $publicHeaders },
  @{ m = 'GET'; r = "/notes?user_id=$uid"; b = $null; h = $publicHeaders },
  @{ m = 'POST'; r = '/notes'; b = @{ user_id = $uid; folder_name = 'General'; title = 'Another'; content = 'text' }; h = $publicHeaders },
  @{ m = 'GET'; r = "/notes/me?user_id=$uid"; b = $null; h = $publicHeaders },
  @{ m = 'PUT'; r = '/notes/me'; b = @{ user_id = $uid; content = 'me-updated' }; h = $publicHeaders },
  @{ m = 'GET'; r = $(if ($noteId) { "/notes/$noteId?user_id=$uid" } else { "/notes/__missing__?user_id=$uid" }); b = $null; h = $publicHeaders },
  @{ m = 'PUT'; r = $(if ($noteId) { "/notes/$noteId?user_id=$uid" } else { "/notes/__missing__?user_id=$uid" }); b = @{ title = 'updated-note' }; h = $publicHeaders },
  @{ m = 'DELETE'; r = $(if ($noteId) { "/notes/$noteId?user_id=$uid" } else { "/notes/__missing__?user_id=$uid" }); b = $null; h = $publicHeaders },
  @{ m = 'GET'; r = "/attendance/today?user_id=$uid"; b = $null; h = $publicHeaders },
  @{ m = 'GET'; r = '/attendance/overview'; b = $null; h = $publicHeaders },
  @{ m = 'POST'; r = '/attendance/punch-in'; b = @{ user_id = $uid }; h = $publicHeaders },
  @{ m = 'POST'; r = '/attendance/punch-out'; b = @{ user_id = $uid }; h = $publicHeaders },
  @{ m = 'POST'; r = '/attendance/break/start'; b = @{ user_id = $uid; break_type = 'tea' }; h = $publicHeaders },
  @{ m = 'POST'; r = '/attendance/break/end'; b = @{ user_id = $uid }; h = $publicHeaders },
  @{ m = 'GET'; r = "/dashboard/summary?user_id=$uid&user_role=admin"; b = $null; h = $publicHeaders },
  @{ m = 'GET'; r = "/notifications?employee_id=$uid"; b = $null; h = $publicHeaders },
  @{ m = 'POST'; r = '/notifications'; b = @{ sender_role = 'admin'; employee_id = $uid2; task_id = $(if ($taskId) { $taskId } else { 'T-TEST' }); type = 'reminder'; message = 'api audit reminder' }; h = $publicHeaders }
)

foreach ($c in $checks) {
  $results.Add((Invoke-Probe -Method $c.m -Route $c.r -Headers $c.h -Body $c.b -TimeoutSec 30))
}

$notifId = ''
$notifList = $results | Where-Object { $_.method -eq 'GET' -and $_.route -like '/notifications*' } | Select-Object -First 1
if ($notifList -and $notifList.status -eq 200) {
  try { $notifId = (($notifList.body | ConvertFrom-Json).data | Select-Object -First 1).id }
  catch {}
}

if ($notifId) {
  $results.Add((Invoke-Probe -Method 'PATCH' -Route "/notifications/$notifId/read" -Headers $publicHeaders -Body @{ employee_id = $uid } -TimeoutSec 30))
}
else {
  $results.Add([PSCustomObject]@{ method = 'PATCH'; route = '/notifications/{id}/read'; status = 'UNTESTED'; latency_ms = 0; body = 'No notification id available'; tag = ''; timeout_sec = 0 })
}

$threads = Invoke-Probe -Method 'GET' -Route '/chat/threads' -Headers $chatHeaders -Body $null -TimeoutSec 30
$results.Add($threads)
$threadId = ''
if ($threads.status -eq 200) {
  try { $threadId = ($threads.body | ConvertFrom-Json).data[0].id }
  catch {}
}

if ([string]::IsNullOrWhiteSpace($threadId)) {
  $directSetup = Invoke-Probe -Method 'POST' -Route '/chat/threads/direct' -Headers $chatHeaders -Body @{ user_a_id = $uid; user_b_id = $uid2 } -TimeoutSec 30 -Tag 'setup'
  $results.Add($directSetup)
  if ($directSetup.status -eq 200) {
    try { $threadId = ($directSetup.body | ConvertFrom-Json).data.id }
    catch {}
  }
}

$results.Add((Invoke-Probe -Method 'POST' -Route '/chat/realtime/auth' -Headers $chatHeaders -Body @{ socket_id = '1234.5678'; channel_name = "private-chat.user.$uid" } -TimeoutSec 20))
$results.Add((Invoke-Probe -Method 'POST' -Route '/chat/threads/direct' -Headers $chatHeaders -Body @{ user_a_id = $uid; user_b_id = $uid2 } -TimeoutSec 30))
$results.Add((Invoke-Probe -Method 'POST' -Route '/chat/threads/broadcast' -Headers $chatHeaders -Body @{ created_by = $uid; scope = 'all'; title = 'API Audit Broadcast' } -TimeoutSec 30))

if ($threadId) {
  $msgList = Invoke-Probe -Method 'GET' -Route "/chat/threads/$threadId/messages?limit=20&include_reactions=1" -Headers $chatHeaders -Body $null -TimeoutSec 30
  $results.Add($msgList)

  for ($i = 1; $i -le 3; $i++) {
    $results.Add((Invoke-Probe -Method 'POST' -Route "/chat/threads/$threadId/messages" -Headers $chatHeaders -Body @{ body = "audit send attempt $i"; client_message_id = "audit-$now-$i" } -TimeoutSec 12 -Tag "chat-send-attempt-$i"))
    $results.Add((Invoke-Probe -Method 'POST' -Route "/chat/threads/$threadId/typing" -Headers $chatHeaders -Body @{ is_typing = $true } -TimeoutSec 12 -Tag "chat-typing-attempt-$i"))

    $latest = Invoke-Probe -Method 'GET' -Route "/chat/threads/$threadId/messages?limit=1" -Headers $chatHeaders -Body $null -TimeoutSec 20 -Tag "chat-latest-msg-$i"
    $results.Add($latest)

    $latestMessageId = ''
    if ($latest.status -eq 200) {
      try { $latestMessageId = ($latest.body | ConvertFrom-Json).data[0].id }
      catch {}
    }

    if ($latestMessageId) {
      $results.Add((Invoke-Probe -Method 'POST' -Route "/chat/threads/$threadId/receipts" -Headers $chatHeaders -Body @{ delivered_message_id = $latestMessageId; seen_message_id = $latestMessageId } -TimeoutSec 12 -Tag "chat-receipts-attempt-$i"))
    }
    else {
      $results.Add([PSCustomObject]@{ method = 'POST'; route = '/chat/threads/{id}/receipts'; status = 'UNTESTED'; latency_ms = 0; body = 'No message id for receipts'; tag = "chat-receipts-attempt-$i"; timeout_sec = 12 })
    }
  }

  $msgId = ''
  $lastMsg = $results | Where-Object { $_.route -like "/chat/threads/$threadId/messages?limit=1" } | Select-Object -Last 1
  if ($lastMsg -and $lastMsg.status -eq 200) {
    try { $msgId = ($lastMsg.body | ConvertFrom-Json).data[0].id }
    catch {}
  }

  $results.Add((Invoke-Probe -Method 'POST' -Route "/chat/threads/$threadId/read" -Headers $chatHeaders -Body @{} -TimeoutSec 20))

  if ($msgId) {
    $results.Add((Invoke-Probe -Method 'POST' -Route "/chat/threads/$threadId/messages/$msgId/delivered" -Headers $chatHeaders -Body @{} -TimeoutSec 20))
    $results.Add((Invoke-Probe -Method 'POST' -Route "/chat/threads/$threadId/messages/$msgId/seen" -Headers $chatHeaders -Body @{} -TimeoutSec 20))
    $results.Add((Invoke-Probe -Method 'GET' -Route "/chat/threads/$threadId/messages/$msgId/reactions" -Headers $chatHeaders -Body $null -TimeoutSec 20))
    $results.Add((Invoke-Probe -Method 'POST' -Route "/chat/threads/$threadId/messages/$msgId/reactions" -Headers $chatHeaders -Body @{ reaction = 'like' } -TimeoutSec 20))
    $results.Add((Invoke-Probe -Method 'DELETE' -Route "/chat/threads/$threadId/messages/$msgId/reactions" -Headers $chatHeaders -Body @{ reaction = 'like' } -TimeoutSec 20))
  }
  else {
    $results.Add([PSCustomObject]@{ method = 'POST'; route = '/chat/threads/{id}/messages/{messageId}/delivered'; status = 'UNTESTED'; latency_ms = 0; body = 'No message id'; tag = ''; timeout_sec = 0 })
    $results.Add([PSCustomObject]@{ method = 'POST'; route = '/chat/threads/{id}/messages/{messageId}/seen'; status = 'UNTESTED'; latency_ms = 0; body = 'No message id'; tag = ''; timeout_sec = 0 })
    $results.Add([PSCustomObject]@{ method = 'GET'; route = '/chat/threads/{id}/messages/{messageId}/reactions'; status = 'UNTESTED'; latency_ms = 0; body = 'No message id'; tag = ''; timeout_sec = 0 })
    $results.Add([PSCustomObject]@{ method = 'POST'; route = '/chat/threads/{id}/messages/{messageId}/reactions'; status = 'UNTESTED'; latency_ms = 0; body = 'No message id'; tag = ''; timeout_sec = 0 })
    $results.Add([PSCustomObject]@{ method = 'DELETE'; route = '/chat/threads/{id}/messages/{messageId}/reactions'; status = 'UNTESTED'; latency_ms = 0; body = 'No message id'; tag = ''; timeout_sec = 0 })
  }

  $results.Add((Invoke-Probe -Method 'POST' -Route '/chat/presence' -Headers $chatHeaders -Body @{ is_online = $true } -TimeoutSec 20))
}
else {
  $results.Add([PSCustomObject]@{ method = 'GET'; route = '/chat/threads/{id}/messages'; status = 'UNTESTED'; latency_ms = 0; body = 'No thread id'; tag = ''; timeout_sec = 0 })
}

$final = @()
foreach ($r in $results) {
  $cat = if ($r.status -eq 'UNTESTED') { 'UNTESTED' } else { Category $r.status }
  $final += [PSCustomObject]@{
    method = $r.method
    route = $r.route
    status = $r.status
    category = $cat
    latency_ms = $r.latency_ms
    tag = $r.tag
    frontend = (FrontConsumer $r.route)
    body = $r.body
  }
}

$final | ConvertTo-Json -Depth 8 | Set-Content -Path $outJson -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# API Audit Report ($now)")
$lines.Add('')
$lines.Add("Base URL: $base")
$lines.Add('')
$lines.Add('## Summary')
$byCat = $final | Group-Object category | Sort-Object Name
foreach ($g in $byCat) { $lines.Add("- $($g.Name): $($g.Count)") }
$lines.Add('')
$lines.Add('## Route-by-Route Results')
$lines.Add('| Method | Route | HTTP | Category | Latency(ms) | Frontend | Tag |')
$lines.Add('|---|---|---:|---|---:|---|---|')
foreach ($r in $final) {
  $http = [string]$r.status
  $route = $r.route.Replace('|', '/')
  $fe = $r.frontend.Replace('|', '/')
  $tag = ([string]$r.tag).Replace('|', '/')
  $lines.Add("| $($r.method) | $route | $http | $($r.category) | $($r.latency_ms) | $fe | $tag |")
}

$lines.Add('')
$lines.Add('## Chat Timeout Focus (3 attempts each)')
$lines.Add('| Endpoint | Attempt | HTTP | Category | Latency(ms) | Body Snippet |')
$lines.Add('|---|---:|---:|---|---:|---|')
$focus = $final | Where-Object { $_.tag -like 'chat-send-attempt-*' -or $_.tag -like 'chat-typing-attempt-*' -or $_.tag -like 'chat-receipts-attempt-*' }
foreach ($f in $focus) {
  $ep = if ($f.tag -like 'chat-send-*') { 'POST /chat/threads/{id}/messages' } elseif ($f.tag -like 'chat-typing-*') { 'POST /chat/threads/{id}/typing' } else { 'POST /chat/threads/{id}/receipts' }
  $attempt = (($f.tag -split '-')[-1])
  $snippet = (Clip ([string]$f.body) 180).Replace("`n", ' ').Replace('|', '/').Replace('"', '\"')
  $lines.Add("| $ep | $attempt | $($f.status) | $($f.category) | $($f.latency_ms) | $snippet |")
}

$lines.Add('')
$lines.Add('## FAIL/Timeout Response Bodies')
foreach ($f in ($final | Where-Object { $_.category -eq 'FAIL' })) {
  $lines.Add("### $($f.method) $($f.route) [$($f.tag)]")
  $lines.Add('')
  $lines.Add("- HTTP: $($f.status)")
  $lines.Add("- Latency(ms): $($f.latency_ms)")
  $lines.Add('- Body:')
  $lines.Add('```json')
  $lines.Add((Clip ([string]$f.body) 1200))
  $lines.Add('```')
  $lines.Add('')
}

$lines | Set-Content -Path $outMd -Encoding UTF8

Write-Output "JSON=$outJson"
Write-Output "MD=$outMd"
Write-Output "TOTAL=$($final.Count)"
Write-Output "FAILS=$((($final | Where-Object category -eq 'FAIL') | Measure-Object).Count)"
