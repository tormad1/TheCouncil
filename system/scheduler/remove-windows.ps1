$ErrorActionPreference = 'Stop'
Unregister-ScheduledTask -TaskName 'ComputationalArtCollectiveHeartbeat' -Confirm:$false
