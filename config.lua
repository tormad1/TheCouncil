local installed = require('system.fs').load('.local/toolchain/paths.json', {})
return {
 project_name = "UNNAMED_COLLECTIVE", timezone = "Europe/London", heartbeat_minutes = 5,
 -- First ideation observed; human explicitly authorized early unattended continuation.
 live_ai = true, live_ready = true, first_live_manual_done = true,
 models = {luna="gpt-6-luna",sol="gpt-6.1-sol",astra="gpt-6-astra"},
 routing = {
  ideate={model="luna",effort="high"}, ideate_retry={model="luna",effort="high"},
  static_build={model="luna",effort="high"}, defold_build={model="sol",effort="low"},
  simple_repair={model="luna",effort="high"}, complex_repair={model="sol",effort="medium"},
  astra_low={model="astra",effort="low",automatic=false}, astra_medium={model="astra",effort="medium",automatic=false}
 },
 context={recent_works=7,same_member_works=3,related_works=4,tendency_window=30},
 exhibition={maximum=14},
 budget={cooldown_minutes=10, five_hour_hard=4, max_creative_retries=1,max_automatic_repairs=1,max_infrastructure_retries=2,
  rolling_7d={luna_high_soft=10,sol_low_target=6,sol_low_hard=8,sol_medium_soft=1,sol_medium_hard=2,astra_low_hard=0,astra_medium_hard=0}},
 process={codex=installed.codex or "codex",python=installed.python or "python",windows_sandbox="mxc",timeout_seconds=1800,lock_timeout_seconds=21600},
 toolchain={bob=".local/toolchain/bob.jar",java=installed.java or "java",resvg=installed.resvg or ".local/toolchain/resvg.exe"},
 publication={git_commit=true,push=false}
}
