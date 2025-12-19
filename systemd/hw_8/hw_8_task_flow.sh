#!/bin/sh
#set -e

: "${USER_CURRENT:=admin}"

timstamp() { date +"%Y%m%d%H%M%S"; }

task_start() {
  TASK_NAME="$1"
  echo "================== START TASK: ${TASK_NAME} =================="
  echo
}

task_end() {
  TASK_NAME="$1"
  echo
  echo "================== END TASK: ${TASK_NAME} =================="
  echo
}

run_cmd() {
  printf "COMMAND: %s\n" "$*"
  "$@"
  echo
  echo "================================================"
  echo
}

if [ ! -d "./output_data" ]; then
  mkdir ./output_data
  chmod 2777 ./output_data
fi

make_log_file() {
  TIMESTAMP=$(timstamp)
  TASK_NAME="$1"
  LOG_FILE="./output_data/hw_8_${TASK_NAME}_${TIMESTAMP}.txt"
  export LOG_FILE
  if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
  fi
}

task_last_activity() {
  task_start "last_activity"
  run_cmd ps xawf
  run_cmd systemd-analyze
  run_cmd systemd-analyze blame
  run_cmd systemd-analyze critical-chain
  run_cmd sh -c 'systemd-analyze plot > bootup.svg'
  run_cmd sh -c "systemd-analyze dot --to-pattern='*.target' --from-pattern='*.target' | dot -Tsvg > targets.svg"
  run_cmd systemctl show-environment
  run_cmd systemctl cat ssh.service
  run_cmd systemctl show ssh.service
  run_cmd systemctl show ssh.service -p ExecMainPID
  run_cmd systemctl show ssh.service -p ExecMainPID --value
  run_cmd systemctl status cups || true
  run_cmd sudo systemctl stop cups
  run_cmd systemctl status cups || true
  run_cmd sudo systemctl start cups
  run_cmd systemctl cat cups.service
  run_cmd systemctl show cups -p MemoryMax
  run_cmd sudo systemctl set-property cups MemoryMax=2G
  run_cmd systemctl cat cups.service
  run_cmd systemctl show cups -p MemoryMax
  run_cmd sudo systemctl stop cups.service
  run_cmd sudo rm -rf /etc/systemd/system.control/cups.service.d
  run_cmd sudo systemctl daemon-reload
  run_cmd sudo systemctl restart cups.service
  run_cmd sudo systemctl cat cups.service
  run_cmd sudo systemctl status cups.service || true
  run_cmd runlevel
  run_cmd systemctl get-default
  run_cmd sudo systemctl set-default multi-user.target
  run_cmd sudo systemctl isolate default.target
  run_cmd runlevel
  run_cmd systemctl list-units -t target --state=active
  run_cmd systemctl list-units -t target --all
  run_cmd sudo systemctl isolate basic.target
  run_cmd systemctl status basic.target
  run_cmd systemctl cat basic.target
  run_cmd systemctl cat multi-user.target
  run_cmd ls /sbin/halt /sbin/poweroff /sbin/reboot /sbin/shutdown
  run_cmd ls -l /sbin/halt /sbin/poweroff /sbin/reboot /sbin/shutdown
  run_cmd sh -c 'ls -l /lib/systemd/system | wc -l'
  run_cmd sh -c 'ls -l /run/systemd/system | wc -l'
  run_cmd sh -c 'ls -l /etc/systemd/system | wc -l'
  run_cmd ls -l /etc/systemd/system
  task_end "last_activity"
}

task_systemd_timers() {
  task_start "systemd_timers"

  # existing timers
  run_cmd systemctl list-timers
  run_cmd systemctl cat fstrim.timer || true
  run_cmd systemctl cat fstrim.service || true

  # calendar
  run_cmd systemd-analyze calendar hourly
  run_cmd systemd-analyze calendar daily
  run_cmd systemd-analyze calendar weekly
  run_cmd systemd-analyze calendar monthly
  run_cmd systemd-analyze calendar "*-*-* 09..17:00/5"
  run_cmd systemd-analyze calendar "Mon..Fri *-*-* 09..17:00/5"

  # timer script
  run_cmd sh -c 'cat > /home/admin/journo.sh << "EOF"
#!/bin/sh
echo "Timer fired at $(date)" | systemd-cat -t blahwoof
EOF'
  run_cmd chmod a+x /home/admin/journo.sh

  # blahwoof.timer
  run_cmd sudo sh -c 'cat > /etc/systemd/system/blahwoof.timer << "EOF"
[Unit]
Description=Run the blahwoof service every 5 seconds

[Timer]
OnCalendar=*-*-* *:*:0/5
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF'

  # blahwoof.service
  run_cmd sudo sh -c 'cat > /etc/systemd/system/blahwoof.service << "EOF"
[Unit]
Description=Write a quick entry to the systemd journal

[Service]
Type=oneshot
User=admin
ExecStart=/home/admin/journo.sh

[Install]
WantedBy=blahwoof.timer
EOF'

  run_cmd sudo systemctl daemon-reload
  run_cmd systemctl cat blahwoof.timer
  run_cmd systemctl cat blahwoof.service

  # timer run
  run_cmd systemctl list-timers
  run_cmd sudo systemctl enable blahwoof.timer
  run_cmd sudo systemctl start blahwoof.timer
  run_cmd systemctl status blahwoof.timer || true

  # test journal entries
  run_cmd sleep 10
  run_cmd sudo journalctl -t blahwoof -n 10 --no-pager

  run_cmd systemctl list-timers --all

  task_end "systemd_timers"
}

journaling_task() {
  task_start "journaling"
  #query and view journal entries including boot sessions
  run_cmd journalctl
  run_cmd sudo journalctl
  run_cmd sudo journalctl --list-boots
  run_cmd sudo journalctl -b 0

  # monitor services, cgroups, and ranges
  run_cmd sudo journalctl -u dbus.service --no-pager -n 50

  run_cmd timeout 5 sudo journalctl -u dbus.service --follow || true
  run_cmd systemd-cgls --no-pager
  run_cmd sudo journalctl _SYSTEMD_CGROUP=/user.slice/user-1000.slice/session-1.scope --no-pager -n 50 || true
  run_cmd sudo journalctl --since=today --no-pager -n 50
  run_cmd sudo journalctl --since=-5m --no-pager
  run_cmd sudo journalctl --since="2024-01-15 16:31" --until=now --no-pager -n 50 || true

  # query user and process entries, and add explanations
  run_cmd id
  # get current user uid dynamically
  CURRENT_UID=$(id -u)
  run_cmd sudo journalctl _UID="$CURRENT_UID" --no-pager -n 50
  run_cmd journalctl --no-pager -n 50
  run_cmd pgrep ssh || true
  # get sshd pid and show its logs
  SSH_PID=$(pgrep ssh | head -1) || true
  if [ -n "$SSH_PID" ]; then
    run_cmd sudo journalctl _PID="$SSH_PID" --no-pager -n 20
  fi
  run_cmd journalctl -x --no-pager -n 50
  run_cmd journalctl --list-catalog --no-pager

  # disk usage
  run_cmd journalctl --disk-usage
  run_cmd sudo journalctl --disk-usage
  run_cmd sudo journalctl --vacuum-size=500M

  task_end "journaling"
}

task_systemd_cgroups() {
  task_start "systemd_cgroups"

  run_cmd sudo sh -c 'cat > /etc/systemd/system/stress1.service << "EOF"
[Unit]
Description=Stress test server1

[Service]
Type=forking
ExecStart=/usr/bin/daemonize -c /tmp -p /tmp/stressing.pid /usr/bin/stress -c 2
PIDFile=/tmp/stressing.pid

[Install]
WantedBy=multi-user.target
EOF'

  sudo systemctl daemon-reload
  sudo systemctl restart stress1.service || true
  sudo systemctl status stress1.service || true
  run_cmd systemd-cgtop -n 1 --batch

  # change memory
  run_cmd sudo sh -c 'cat > /etc/systemd/system/stress1.service << "EOF"
[Unit]
Description=Stress test server1

[Service]
Type=forking
ExecStart=/usr/bin/daemonize -c /tmp -p /tmp/stressing.pid /usr/bin/stress -c 2
PIDFile=/tmp/stressing.pid
MemoryMax=768K

[Install]
WantedBy=multi-user.target
EOF'

  sudo systemctl daemon-reload
  sudo systemctl restart stress1.service || true
  sudo systemctl status stress1.service || true
  run_cmd systemd-cgtop -n 1 --batch

  # create stress2.service with cpuweight=100, stress1 with cpuweight=50
  run_cmd sudo sh -c 'cat > /etc/systemd/system/stress1.service << "EOF"
[Unit]
Description=Stress test server1

[Service]
Type=forking
ExecStart=/usr/bin/daemonize -c /tmp -p /tmp/stressing1.pid /usr/bin/stress -c 2
PIDFile=/tmp/stressing1.pid
CPUWeight=50

[Install]
WantedBy=multi-user.target
EOF'

  run_cmd sudo sh -c 'cat > /etc/systemd/system/stress2.service << "EOF"
[Unit]
Description=Stress test server2

[Service]
Type=forking
ExecStart=/usr/bin/daemonize -c /tmp -p /tmp/stressing2.pid /usr/bin/stress -c 2
PIDFile=/tmp/stressing2.pid
CPUWeight=100

[Install]
WantedBy=multi-user.target
EOF'

  sudo systemctl daemon-reload
  sudo systemctl restart stress1.service || true
  sudo systemctl start stress2.service || true
  run_cmd sudo systemctl status stress1.service || true
  run_cmd sudo systemctl status stress2.service || true

  # create stress3.service with cpuweight=300
  run_cmd sudo sh -c 'cat > /etc/systemd/system/stress3.service << "EOF"
[Unit]
Description=Stress test server3

[Service]
Type=forking
ExecStart=/usr/bin/daemonize -c /tmp -p /tmp/stressing3.pid /usr/bin/stress -c 2
PIDFile=/tmp/stressing3.pid
CPUWeight=300

[Install]
WantedBy=multi-user.target
EOF'

  sudo systemctl daemon-reload
  sudo systemctl start stress3.service || true
  sudo systemctl status stress3.service || true

  run_cmd systemctl cat stress1.service
  run_cmd systemctl cat stress2.service
  run_cmd systemctl cat stress3.service
  run_cmd systemd-cgtop -n 3 --batch

  sudo systemctl stop stress1.service stress2.service stress3.service || true

  task_end "systemd_cgroups"
}

main() {

  if ! command -v ssh > /dev/null 2>&1; then
    sudo apt-get install -y openssh-server
  fi

  if ! command -v dot > /dev/null 2>&1; then
    sudo apt-get install -y graphviz
  fi

  if ! command -v daemonize > /dev/null 2>&1; then
    sudo apt-get install -y daemonize
  fi

  if ! command -v stress > /dev/null 2>&1; then
    sudo apt-get install -y stress
  fi

  make_log_file "last_activity"
  task_last_activity >> "$LOG_FILE" 2>&1

  make_log_file "systemd_timers"
  task_systemd_timers >> "$LOG_FILE" 2>&1

  sudo usermod -aG systemd-journal "${USER_CURRENT}"
  sudo usermod -aG adm "${USER_CURRENT}"

  make_log_file "journaling_task"
  journaling_task >> "$LOG_FILE"

  make_log_file "systemd_cgroups"
  task_systemd_cgroups >> "$LOG_FILE" 2>&1
}

main