param([string]$ProjectRef = ((Get-Content "$PSScriptRoot/../supabase/.temp/project-ref" -Raw).Trim()))

$ErrorActionPreference = 'Stop'
$projectUrl = "https://$ProjectRef.supabase.co"
$keys = npx supabase projects api-keys --project-ref $ProjectRef -o json | ConvertFrom-Json
$anon = ($keys | Where-Object { $_.name -eq 'anon' }).api_key
$service = ($keys | Where-Object { $_.name -eq 'service_role' }).api_key
if (-not $anon -or -not $service) { throw 'Hosted API keys are unavailable.' }

function Invoke-Json($method, $url, $headers, $body = $null) {
  $parameters = @{ Method = $method; Uri = $url; Headers = $headers }
  if ($null -ne $body) {
    $parameters.ContentType = 'application/json'
    $parameters.Body = ($body | ConvertTo-Json -Depth 20 -Compress)
  }
  Invoke-RestMethod @parameters
}

function New-Session($action, $username, $password) {
  Invoke-Json POST "$projectUrl/functions/v1/username-auth" @{
    apikey = $anon
    authorization = "Bearer $anon"
  } @{ action = $action; username = $username; password = $password }
}

function Send-TestImage($url, $headers) {
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      Invoke-WebRequest -Method POST -Uri $url -Headers $headers -ContentType 'image/jpeg' -Body ([byte[]](0xff,0xd8,0xff,0xd9)) | Out-Null
      return
    }
    catch {
      if ($attempt -eq 3 -or $_.Exception.Response.StatusCode -ne 544) { throw }
      Start-Sleep -Seconds (2 * $attempt)
    }
  }
}

$suffix = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$password = "Phase7-$suffix-safe"
$first = $null
$second = $null
$legacyId = $null
$imageKey = $null
$bundleFile = $null
try {
  $first = New-Session signup "phase7a_$suffix" $password
  $login = New-Session login "phase7a_$suffix" $password
  if ($login.data.user.id -ne $first.data.user.id) { throw 'Login identity changed.' }
  $token = $first.data.supabaseSession.accessToken
  $userId = $first.data.user.id
  $headers = @{ apikey = $anon; authorization = "Bearer $token"; Prefer = 'return=representation' }

  $categoryId = [guid]::NewGuid().ToString()
  $habitId = [guid]::NewGuid().ToString()
  $optionId = [guid]::NewGuid().ToString()
  $scheduleId = [guid]::NewGuid().ToString()
  $ruleId = [guid]::NewGuid().ToString()
  $pauseId = [guid]::NewGuid().ToString()
  $reminderId = [guid]::NewGuid().ToString()
  $rewardId = [guid]::NewGuid().ToString()
  $checkInId = [guid]::NewGuid().ToString()
  $checkLedgerId = [guid]::NewGuid().ToString()
  $redemptionId = [guid]::NewGuid().ToString()
  $redemptionLedgerId = [guid]::NewGuid().ToString()

  Invoke-Json POST "$projectUrl/rest/v1/categories" $headers @{ id=$categoryId; user_id=$userId; name='Phase 7'; sort_order=0 } | Out-Null
  Invoke-Json POST "$projectUrl/rest/v1/habits" $headers @{ id=$habitId; user_id=$userId; category_id=$categoryId; name='Cutover habit'; measurement_type='yes_no'; sort_order=0; missed_penalty_enabled=$false; missed_penalty_points=0 } | Out-Null
  Invoke-Json POST "$projectUrl/rest/v1/habit_options" $headers @{ id=$optionId; user_id=$userId; habit_id=$habitId; label='Done'; numeric_value=1; sort_order=0 } | Out-Null
  Invoke-Json POST "$projectUrl/rest/v1/habit_schedules" $headers @{ id=$scheduleId; user_id=$userId; habit_id=$habitId; schedule_type='daily'; schedule_config=@{} } | Out-Null
  Invoke-Json POST "$projectUrl/rest/v1/point_rules" $headers @{ id=$ruleId; user_id=$userId; habit_id=$habitId; operator='completed'; value_min=$null; value_max=$null; points=10; sort_order=0 } | Out-Null
  Invoke-Json POST "$projectUrl/rest/v1/habit_pauses" $headers @{ id=$pauseId; user_id=$userId; habit_id=$habitId; start_date='2026-10-01'; end_date='2026-10-02' } | Out-Null
  Invoke-Json POST "$projectUrl/rest/v1/habit_reminders" $headers @{ id=$reminderId; user_id=$userId; habit_id=$habitId; enabled=$true; time_of_day='08:30:00' } | Out-Null
  Invoke-Json POST "$projectUrl/rest/v1/rewards" $headers @{ id=$rewardId; user_id=$userId; name='Hosted reward'; points_cost=5; monetary_cap=$null; sort_order=0 } | Out-Null

  $now = [DateTime]::UtcNow.ToString('o')
  $checkBody = @{
    p_ledger_id = $checkLedgerId
    p_check_in = @{ id=$checkInId; habit_id=$habitId; habit_date='2026-09-11'; option_id=$optionId; measured_value=1; note='phase7'; awarded_points=10; matched_rule_id=$ruleId; checked_in_at=$now; editable_until=([DateTime]::UtcNow.AddHours(24).ToString('o')); created_at=$now; updated_at=$now }
  }
  Invoke-Json POST "$projectUrl/rest/v1/rpc/upsert_check_in_with_ledger" $headers $checkBody | Out-Null
  Invoke-Json POST "$projectUrl/rest/v1/rpc/upsert_check_in_with_ledger" $headers $checkBody | Out-Null
  $redeemBody = @{ p_reward_id=$rewardId; p_redemption_id=$redemptionId; p_ledger_id=$redemptionLedgerId }
  Invoke-Json POST "$projectUrl/rest/v1/rpc/redeem_reward" $headers $redeemBody | Out-Null
  Invoke-Json POST "$projectUrl/rest/v1/rpc/redeem_reward" $headers $redeemBody | Out-Null

  $objectId = [guid]::NewGuid().ToString()
  $imageKey = "$userId/$rewardId/$objectId.jpg"
  Send-TestImage "$projectUrl/storage/v1/object/reward-images/$imageKey" $headers
  Invoke-Json PATCH "$projectUrl/rest/v1/rewards?id=eq.$rewardId" $headers @{ image_key=$imageKey } | Out-Null

  $ledger = Invoke-Json GET "$projectUrl/rest/v1/point_ledger?select=id,source_type,source_id,reward_id,points&order=created_at" $headers
  $ledgerSum = ($ledger | Measure-Object points -Sum).Sum
  if ($ledger.Count -ne 2 -or $ledgerSum -ne 5) { throw "Ledger replay changed wallet effects (count=$($ledger.Count), sum=$ledgerSum)." }
  $roundTrip = @('categories','habits','habit_options','habit_schedules','point_rules','check_ins','habit_pauses','rewards','habit_reminders')
  foreach ($table in $roundTrip) {
    if ((Invoke-Json GET "$projectUrl/rest/v1/${table}?select=id" $headers).Count -ne 1) { throw "$table did not round-trip." }
  }
  $changes = Invoke-Json GET "$projectUrl/rest/v1/sync_changes?select=sequence,entity_type&order=sequence.asc" $headers
  if ($changes.Count -lt 11) { throw 'Sync feed is incomplete.' }
  for ($index = 1; $index -lt $changes.Count; $index++) {
    if ([long]$changes[$index].sequence -le [long]$changes[$index - 1].sequence) { throw 'Sync sequence is not monotonic.' }
  }

  $second = New-Session signup "phase7b_$suffix" $password
  $secondHeaders = @{ apikey=$anon; authorization="Bearer $($second.data.supabaseSession.accessToken)"; Prefer='return=representation' }
  if ((Invoke-Json GET "$projectUrl/rest/v1/categories?id=eq.$categoryId&select=id" $secondHeaders).Count -ne 0) { throw 'RLS exposed another account.' }
  if ((Invoke-Json PATCH "$projectUrl/rest/v1/habit_reminders?id=eq.$reminderId" $secondHeaders @{ enabled=$false }).Count -ne 0) { throw 'RLS changed another account.' }

  # Exercise the real hosted checkpoint/import path with a migrated D1 identity.
  $legacyId = [guid]::NewGuid().ToString()
  $legacyName = "phase7legacy_$suffix"
  Invoke-Json POST "$projectUrl/auth/v1/admin/users" @{ apikey=$service; authorization="Bearer $service" } @{
    id=$legacyId
    email="$legacyId@auth.ruleup.invalid"
    password=$password
    email_confirm=$true
    user_metadata=@{ username=$legacyName }
    app_metadata=@{ identity_source='ruleup_legacy'; legacy_user_id=$legacyId }
  } | Out-Null
  $legacyCategoryId = [guid]::NewGuid().ToString()
  $bundle = @{
    user=@{ id=$legacyId; username=$legacyName; supabase_auth_email="$legacyId@auth.ruleup.invalid"; auth_migrated_at=[DateTime]::UtcNow.ToString('o') }
    tables=@{
      categories=@(@{ id=$legacyCategoryId; user_id=$legacyId; name='Imported'; sort_order=0; created_at=$now; updated_at=$now })
      habits=@(); habit_options=@(); habit_schedules=@(); point_rules=@(); check_ins=@(); habit_pauses=@(); rewards=@(); habit_reminders=@(); point_ledger=@()
    }
    images=@()
  }
  $bundleFile = [IO.Path]::GetTempFileName()
  [IO.File]::WriteAllText($bundleFile, ($bundle | ConvertTo-Json -Depth 20 -Compress))
  $previousUrl = $env:SUPABASE_URL
  $previousService = $env:SUPABASE_SERVICE_ROLE_KEY
  try {
    $env:SUPABASE_URL = $projectUrl
    $env:SUPABASE_SERVICE_ROLE_KEY = $service
    $firstImport = dart run tool/legacy_d1_import.dart $bundleFile
    if ($LASTEXITCODE -ne 0 -or $firstImport -notmatch '^Imported 1 rows') { throw 'Hosted historical import failed.' }
    $secondImport = dart run tool/legacy_d1_import.dart $bundleFile
    if ($LASTEXITCODE -ne 0 -or $secondImport -notmatch '^Already imported') { throw 'Hosted historical import replay was not idempotent.' }
    $legacySession = New-Session login $legacyName $password
    $legacyHeaders = @{ apikey=$anon; authorization="Bearer $($legacySession.data.supabaseSession.accessToken)" }
    $checkpointProbe = Invoke-WebRequest -Method GET -Uri "$projectUrl/rest/v1/legacy_import_runs?select=user_id" -Headers $legacyHeaders -SkipHttpErrorCheck
    if ($checkpointProbe.StatusCode -lt 400) { throw 'Import checkpoints are visible to an app user.' }
  }
  finally {
    $env:SUPABASE_URL = $previousUrl
    $env:SUPABASE_SERVICE_ROLE_KEY = $previousService
  }

  [pscustomobject]@{ status='PASS'; freshAuth=$true; historicalImport=$true; importReplay=$true; roundTrip=$roundTrip.Count; ledgerEffects=$ledger.Count; syncChanges=$changes.Count; isolation=$true } | ConvertTo-Json -Compress
}
finally {
  $admin = @{ apikey=$service; authorization="Bearer $service" }
  if ($imageKey) { try { Invoke-WebRequest -Method DELETE -Uri "$projectUrl/storage/v1/object/reward-images/$imageKey" -Headers $admin | Out-Null } catch {} }
  if ($first) { try { Invoke-Json DELETE "$projectUrl/auth/v1/admin/users/$($first.data.user.id)" $admin | Out-Null } catch {} }
  if ($second) { try { Invoke-Json DELETE "$projectUrl/auth/v1/admin/users/$($second.data.user.id)" $admin | Out-Null } catch {} }
  if ($legacyId) { try { Invoke-Json DELETE "$projectUrl/auth/v1/admin/users/$legacyId" $admin | Out-Null } catch {} }
  if ($bundleFile) { Remove-Item -LiteralPath $bundleFile -Force -ErrorAction SilentlyContinue }
}
