(*
updateAllPodcasts.scpt / updateAllPodcasts.applescript
A replacement for the iTunes verb updateAllPodcasts (broken by Apple in iTunes 11) which actually updates all podcasts again
*)

(*
Copyright (c) 2015 Richard Johnson <uthacalthing@gmail.com>
Copyright (c) 2020 Richard Johnson <uthacalthing@gmail.com>

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

(*
About:

This script attempts to work around one extremely unfriendly bit of iTunes behavior.  iTunes ceases downloading new episodes of podcasts some time (typically 5 days) after it mistakenly determines previous episodes aren't being listened to.

However, the podcasts are being listened to.

We listen either when time allows, always being assured that our systems will have the latest 3 or 5 ready when we are.  Or we listen via another device (c.f. Plex from shared storage, SlimServer/LMS, &c), and iTunes cannot see that.

So we want to keep downloading the episodes.  Even as Apple developers ham-handedly attempt to track listening metrics and inefficiently try to limit storage, we don't want to be (effectively) unsubscribed from the podcasts we deliberately want.

Our desire is especially strong when some podcast episodes are available only for a few days or weeks, and we might not notice until too late that iTunes left us out of crucial episodes in the series we're following.  And now we can't get them.  Grr.

This script is intended to be run via launchd, firing off once per day.
*)

(*
Issues and Plans:

TODO: Detect whether a track file is actually missing, and skip with optional error report rather than timing out in dialog. This is perhaps needed to handle situations where we've deleted a file in the Podcasts directory while leaving it listed in iTunes.
TODO: Determine whether podcasts with only played ("unplayed is false") episodes also expire, and try to play them too, in order to force an update
TODO: Sort out picked_podcast setup. Always a string now?  Or a list?

ENHANCEMENT: If the instant play eventually doesn't update the podcasts, then we can switch to playing longer, then also re-marking them unplayed. We'll need to beware of races with settings and devices where played podcasts can be deleted.
ENHANCEMENT: If the playing longer eventually still doesn't update the podcasts, we can switch to marking the episode played for a while, then re-marking them unplayed. We'll need to beware of races with settings and devices where played podcasts can be deleted.
*)

(*
Acknowledgements
We used Doug Adams' "Update Expired Podcasts" http://dougscripts.com/423 for years until Apple broke the updatePodcast verb in iTunes version 11. He has many other useful scripts. Consider donating to and learning from him.
*)

(*
History pre-github:

v1.1 2020-09-13
Handle renamed podcasts

v1.0 2015-09-11
Initial release
*)


(*
Design:

As a workaround to updateAllPodcasts verb being broken by design by Apple, we'll actually listen to unplayed podcasts for a smidgen. This loses playback position information, so we will only do this when iTunes is stopped to avoid breaking existing playback or losing position while paused.

For now, we listen only for a short time (no delay in script, so milliseconds).  So far, this is not long enough for iTunes to mark unplayed tracks as "played" (though we still re-set them unplayed anyway when appropriate).  This method currently, in practice, does update the podcast subscriptions timeout.

As a general rule, we fail silently to avoid as much as possible latching up iTunes in error reporting.  When we have empty data from crufty iTunes db, we move on.  When we have errors from missing lists, we move on.  This does run the risk of having some podcasts hit the subscription timeout still, but it's better than blocking other downloads.
*)


(* First, for iTunes to respond to the commands in this script, it must be running. *)
(* We note whether we will be the ones to launch iTunes, so we can leave the system in the same state when we're through *)
set itunes_was_running to 0
if isRunning("iTunes") then
	set itunes_was_running to 1
else
	(* We will launch iTunes. Pause a while because the macOS system might have just rebooted (and launchd might have decided to catch up on missed runs).  In this state the macOS system is busy with other things, so sleep it off. *)
	delay 900
	(* Recapture current state in case user launched iTunes while we slept *)
	if isRunning("iTunes") then
		set itunes_was_running to 1
	end if
end if

(* Invoke iTunes (implicitly launching iTunes if needed) and get to work *)
tell application "iTunes"
	
	(* As long as iTunes is not busy playing something, we can proceed. *)
	(* Note we deliberately do not queue up retries during an invocation, because iTunes may potentially be playing for days, and that user activity takes priority.  Retries are handled via launchd periodic invocation. *)
	if (get player state of application "iTunes") is stopped then
		set podcast_playlist to {}
		set podcast_albums to {}
		set podcast_albums_unique to {}
		
		(* Remember iTunes mute state for subsequent (bug work-around) restoration *)
		set orig_mute_state to (get mute of application "iTunes")
		(* Do our momentary plays quietly *)
		set mute of application "iTunes" to true
		
		(* If we don't get through all the podcasts in 10 minutes, we assume we're broken. Maybe we did something that caused iTunes to pause and pop a dialog or the like. *)
		with timeout of 600 seconds
			
			(* There can be only one playlist of kind Podcasts. Work it if it exists. *)
			set podcast_playlist to some playlist whose special kind is Podcasts
			if podcast_playlist is not "" then
				
				(* Build a "uniq"ed list of podcast album names.
				Skip blank names resulting from (past?) iTunes issues re podcast deletion.
				Skip name collision duplicates so we don't double-tap when finding by name later.
				The list potentially still includes now-bogus podcast album names, found when a podcast track's metadata encodes an old album name for the cast it's now in (we'll skip those names later). *)
				set podcast_albums to (get album of every track of podcast_playlist)
				if podcast_albums is not {} then
					repeat with inum from 1 to length of podcast_albums
						set this_album to item inum of podcast_albums
						if (this_album is not "") and (this_album is not in podcast_albums_unique) then
							set end of podcast_albums_unique to this_album
						end if
					end repeat
				end if
				
				(* Walk the list of podcast album names to play 1 track from each. Move on if we have null lists, blank names, or unavailable items in the lists (such as old names for current or deleted podcasts). *)
				if podcast_albums_unique is not {} then
					repeat with this_album in podcast_albums_unique
						if this_album is not "" then
							set picked_podcast to ""
							try
								set picked_podcast to (some track of podcast_playlist whose (album contains this_album) and (unplayed is true))
								try
									(* Sometimes we received a list when we asked for a randomish single track.  Correct gently with assumption that there is at least one track. *)
									if (get class of picked_podcast) is list then set picked_podcast to item 1 of picked_podcast
									if picked_podcast is not "" then
										set orig_unplayed_state to (get unplayed of picked_podcast)
										play picked_podcast
										stop
										set unplayed of picked_podcast to orig_unplayed_state
									end if
								on error
									(* Ignore error and just move on from more badly broken picked_podcast names. *)
								end try
							on error
								(* Ignore error and just move on from states like podcast renames leaving old names in track metadata. *)
							end try
						end if
					end repeat
				end if
			end if
		end timeout
		
		(* Work around mute restoration problem by explicitly turning it off *)
		set mute of application "iTunes" to false
		(* Then restore previous mute state *)
		set mute of application "iTunes" to orig_mute_state
	end if
end tell

if itunes_was_running = 0 then
	tell application "iTunes"
		quit
	end tell
end if

on isRunning(appName)
	tell application "System Events" to return (name of processes) contains appName
end isRunning

