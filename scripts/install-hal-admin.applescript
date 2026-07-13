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
		"(xattr -d com.apple.quarantine " & quoted form of halDest & " 2>/dev/null || true) && " & ¬
		"SRC_BIN=$(find " & quoted form of staged & "/Contents/MacOS -maxdepth 1 -type f | head -1) && " & ¬
		"DST_BIN=$(find " & quoted form of halDest & "/Contents/MacOS -maxdepth 1 -type f | head -1) && " & ¬
		"SRC_SHA=$(shasum -a 256 \"$SRC_BIN\" | awk '{print $1}') && " & ¬
		"DST_SHA=$(shasum -a 256 \"$DST_BIN\" | awk '{print $1}') && " & ¬
		"if [ \"$SRC_SHA\" != \"$DST_SHA\" ]; then echo installed driver hash mismatch >&2; exit 1; fi && " & ¬
		"rm -rf " & quoted form of staged & " && " & ¬
		"killall coreaudiod 2>/dev/null || true"

	do shell script shellCmd with administrator privileges
end run
