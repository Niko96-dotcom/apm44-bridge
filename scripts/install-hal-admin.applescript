-- Reinstall stapled APM44Bridge.driver and reload coreaudiod (requires admin password once).
-- Stage under /tmp first: root cannot read ~/Documents without Full Disk Access on macOS 15+.
-- Usage: osascript install-hal-admin.applescript "/path/to/APM44Bridge.driver"
on run argv
	if (count of argv) < 1 then
		error "Usage: osascript install-hal-admin.applescript /path/to/APM44Bridge.driver"
	end if
	set driverSrc to item 1 of argv
	set staged to "/tmp/APM44Bridge.driver"
	set halDest to "/Library/Audio/Plug-Ins/HAL/APM44Bridge.driver"

	do shell script "rm -rf " & quoted form of staged & " && ditto " & quoted form of driverSrc & " " & quoted form of staged

	set shellCmd to "mkdir -p /Library/Audio/Plug-Ins/HAL && " & ¬
		"rm -rf " & quoted form of halDest & " && " & ¬
		"ditto " & quoted form of staged & " " & quoted form of halDest & " && " & ¬
		"chown -R root:wheel " & quoted form of halDest & " && " & ¬
		"xattr -cr " & quoted form of halDest & " && " & ¬
		"rm -rf " & quoted form of staged & " && " & ¬
		"killall coreaudiod"

	do shell script shellCmd with administrator privileges
end run
