param(
  [string]$EnvironmentFile = '.env.backup'
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not [IO.Path]::IsPathRooted($EnvironmentFile)) {
  $EnvironmentFile = Join-Path $projectRoot $EnvironmentFile
}
$environmentPath = [IO.Path]::GetFullPath($EnvironmentFile)
if (-not (Test-Path -LiteralPath $environmentPath -PathType Leaf)) {
  throw "Backup environment file does not exist: $environmentPath"
}

$allowedNames = @(
  'POS_BACKUP_KEY_BASE64',
  'OPEN_POS_BACKUP_REMOTE',
  'OPEN_POS_BACKUP_KEEP_LOCAL',
  'OPEN_POS_COMPOSE_FILE',
  'OPEN_POS_COMPOSE_ENV_FILE'
)
$settings = @{}
foreach ($line in Get-Content -LiteralPath $environmentPath) {
  $trimmed = $line.Trim()
  if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
  $separator = $trimmed.IndexOf('=')
  if ($separator -le 0) { throw 'Backup environment file has an invalid entry.' }
  $name = $trimmed.Substring(0, $separator).Trim()
  $value = $trimmed.Substring($separator + 1).Trim()
  if ($name -notin $allowedNames) { throw "Unsupported backup setting: $name" }
  if ($value.Length -ge 2 -and
      (($value.StartsWith('"') -and $value.EndsWith('"')) -or
       ($value.StartsWith("'") -and $value.EndsWith("'")))) {
    $value = $value.Substring(1, $value.Length - 2)
  }
  $settings[$name] = $value
}

if (-not $settings['POS_BACKUP_KEY_BASE64'] -or
    -not $settings['OPEN_POS_BACKUP_REMOTE']) {
  throw 'Set POS_BACKUP_KEY_BASE64 and OPEN_POS_BACKUP_REMOTE in the protected env file.'
}
try {
  $keyBytes = [Convert]::FromBase64String($settings['POS_BACKUP_KEY_BASE64'])
} catch {
  throw 'POS_BACKUP_KEY_BASE64 is not valid Base64.'
}
if ($keyBytes.Length -ne 32) { throw 'The backup key must decode to 32 bytes.' }

$keepLocalText = if ($settings['OPEN_POS_BACKUP_KEEP_LOCAL']) {
  $settings['OPEN_POS_BACKUP_KEEP_LOCAL']
} else {
  '30'
}
if ($keepLocalText -notmatch '^[1-9][0-9]*$') {
  throw 'OPEN_POS_BACKUP_KEEP_LOCAL must be a positive integer.'
}
$keepLocal = [int]$keepLocalText

foreach ($commandName in @('docker', 'rclone')) {
  if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
    throw "Required command is not installed: $commandName"
  }
}

$composeFile = if ($settings['OPEN_POS_COMPOSE_FILE']) {
  $settings['OPEN_POS_COMPOSE_FILE']
} else {
  'docker-compose.yml'
}
if (-not [IO.Path]::IsPathRooted($composeFile)) {
  $composeFile = Join-Path $projectRoot $composeFile
}
$composeFile = [IO.Path]::GetFullPath($composeFile)
if (-not (Test-Path -LiteralPath $composeFile -PathType Leaf)) {
  throw "Compose file does not exist: $composeFile"
}
$composeArguments = @()
if ($settings['OPEN_POS_COMPOSE_ENV_FILE']) {
  $composeEnvFile = $settings['OPEN_POS_COMPOSE_ENV_FILE']
  if (-not [IO.Path]::IsPathRooted($composeEnvFile)) {
    $composeEnvFile = Join-Path $projectRoot $composeEnvFile
  }
  $composeEnvFile = [IO.Path]::GetFullPath($composeEnvFile)
  if (-not (Test-Path -LiteralPath $composeEnvFile -PathType Leaf)) {
    throw "Compose env file does not exist: $composeEnvFile"
  }
  $composeArguments += @('--env-file', $composeEnvFile)
}
$composeArguments += @('-f', $composeFile)

$remoteDirectory = $settings['OPEN_POS_BACKUP_REMOTE'].TrimEnd('/')
$backupName = 'open-pos-{0}-{1}.sqlite.enc' -f `
  [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'), $PID
$containerBackup = "/data/backups/$backupName"
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
if (-not ($tempRoot.EndsWith('\') -or $tempRoot.EndsWith('/'))) {
  $tempRoot += [IO.Path]::DirectorySeparatorChar
}
$stagingDirectory = Join-Path $tempRoot "open-pos-backup-$([guid]::NewGuid().ToString('N'))"
$stagingDirectory = [IO.Path]::GetFullPath($stagingDirectory)
if (-not $stagingDirectory.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'Staging path is outside the system temporary directory.'
}
$stagedBackup = Join-Path $stagingDirectory $backupName
$remoteBackup = "$remoteDirectory/$backupName"
$previousKey = $env:POS_BACKUP_KEY_BASE64

function Invoke-OpenPosCompose {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )
  & docker compose @script:composeArguments @Arguments
  if ($LASTEXITCODE -ne 0) { throw 'Docker Compose backup operation failed.' }
}

try {
  New-Item -ItemType Directory -Path $stagingDirectory | Out-Null
  $env:POS_BACKUP_KEY_BASE64 = $settings['POS_BACKUP_KEY_BASE64']

  Invoke-OpenPosCompose -Arguments @(
    'exec', '-T', '-e', 'POS_BACKUP_KEY_BASE64', 'hub',
    '/maintenance/bin/maintenance', 'backup-encrypted',
    '/data/open_pos.sqlite', $containerBackup
  )
  Invoke-OpenPosCompose -Arguments @(
    'exec', '-T', '-e', 'POS_BACKUP_KEY_BASE64', 'hub',
    '/maintenance/bin/maintenance', 'verify-encrypted', $containerBackup
  )
  Invoke-OpenPosCompose -Arguments @('cp', "hub:$containerBackup", $stagedBackup)

  & rclone copyto --immutable $stagedBackup $remoteBackup
  if ($LASTEXITCODE -ne 0) { throw 'rclone could not upload the encrypted backup.' }
  & rclone check --download --one-way --include $backupName $stagingDirectory $remoteDirectory
  if ($LASTEXITCODE -ne 0) { throw 'The off-site backup verification failed.' }

  Invoke-OpenPosCompose -Arguments @(
    'exec', '-T', 'hub', '/maintenance/bin/maintenance',
    'prune-backups', '/data/backups', "$keepLocal"
  )
  Write-Output "Encrypted backup verified off-site: $remoteBackup"
} finally {
  if ($previousKey) {
    $env:POS_BACKUP_KEY_BASE64 = $previousKey
  } else {
    Remove-Item Env:POS_BACKUP_KEY_BASE64 -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $stagingDirectory) {
    $resolvedStaging = [IO.Path]::GetFullPath($stagingDirectory)
    if (-not $resolvedStaging.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
      throw 'Refusing to remove a staging path outside the system temporary directory.'
    }
    Remove-Item -LiteralPath $resolvedStaging -Recurse -Force
  }
}
