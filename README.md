# updateAllPodcasts
A replacement for the iTunes verb updateAllPodcasts (broken by Apple in iTunes 11) which actually updates all podcasts again

## About

This script attempts to work around one extremely unfriendly bit of iTunes behavior.  iTunes ceases downloading new episodes of podcasts some time (typically 5 days) after it mistakenly determines previous episodes aren't being listened to.

However, the podcasts are being listened to.

We listen either when time allows, always being assured that our systems will have the latest 3 or 5 ready when we are.  Or we listen via another device (c.f. Plex from shared storage, SlimServer/LMS, &c), and iTunes cannot see that.

So we want to keep downloading the episodes.  Even as Apple developers ham-handedly attempt to track listening metrics and ineffeciently try to limit storage, we don't want to be (effectively) unsubscribed from the podcasts we deliberately want.

Our desire is especially strong when some podcast episodes are available only for a few days or weeks, and we might not notice until too late that iTunes left us out of crucial episodes in the series we're following.  And now we can't get them.  Grr.

This script is intended to be run via launchd, firing off once per day.

---
## launchd invocation

To run this automagically, compile the script in Script Editor to create `updateAllPodcasts.scpt`.

Then make a plaintext launchd plist to fire it off every day (every 86400 seconds).  Put the compiled script file (renamed as needed) into

    /Users/{YOURLOGIN}/Library/iTunes/Scripts/updateAllPodcasts.scpt

Replace `{YOURLOGIN}` with your login name here, and in subsequent steps.

Test it with

    osascript ~/Library/iTunes/Scripts/updateAllPodcasts.scpt

Second, put the following in `~/Library/LaunchAgents/updateAllPodcasts.plist`, with `{YOURLOGIN}` in the plist here replaced as above:

    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    	<key>Disabled</key>
    	<false/>
    	<key>Label</key>
    	<string>updateAllPodcasts</string>
    	<key>Program</key>
    	<string>/usr/bin/osascript</string>
    	<key>ProgramArguments</key>
    	<array>
    		<string>osascript</string>
    		<string>/Users/{YOURLOGIN}/Library/iTunes/Scripts/updateAllPodcasts.scpt</string>
    	</array>
    	<key>RunAtLoad</key>
    	<true/>
    	<key>StartInterval</key>
    	<integer>86400</integer>
    </dict>
    </plist>

Third, load the LaunchAgent you just created:

    launchctl load ~/Library/LaunchAgents/updateAllPodcasts.plist
