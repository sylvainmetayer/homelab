#!/usr/bin/env bash

vcgencmd measure_temp

echo "CPU $(($(</sys/class/thermal/thermal_zone0/temp)/1000))°"

vcgencmd measure_volts

echo "Current CPU Frequency : $(( $(sudo cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_cur_freq) / 1000 ))"

