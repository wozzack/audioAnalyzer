addToPlaylist: add audioObject to playlist
     loadAudio: readies audio in player
     playOrPause: plays or pauses audio in player depending on state
     convertToURL: converts string into audioObject type
     startTimer: starts global timer on player 
     pauseTimer: destroys timer and deallocate to prevent leaks, will save past time
     removeFromPlaylist: removes from playlist
     loopAudio: tells player to toggle isLooping, might be redunant
     manualSeek: pauses global timer, changes progress and related variables
     
     
implemented clamp seeking in order to stay within bounds, added previousSeekTime to prevent rapid successive seeks. added an explicit stopAudio vs pauseAudio method that resets the actual progress value too, and am attempting to simplify esstenial methods for debugging ease. also moving all audioManager logic from ContentView.swift to AudioManager.swift. created in moment instant variables in order to avoid operations with variables in constant flux

when attempting to seek backwards, it seems to add the inverse amount of time to reverse instead of subtracting, so if i want to reverse two seconds back, instead it will skip forward by (current duration minus two seconds)

idea: decouple slider value from player.currentTime temporarily and:
1. prevent overwrites during seeking
2. confirm value used in .seek(time:) is correct and up to date
3. make sure progress updates are one-way (user input -> player), not both
     
     TODO
     - seeking bar functionality
         - currently seeking forward from the slider works but going backwards glitches
         - previous flag not working
     - add indication that song from playlist is selected
     - add loop functionality
     - redo error detection system
         - further categorize different errors for ease of reading
     - manually unwrap initialization of audioObject struct for smoother coding
     - remove previousTime and rely on currentTime only (single source of truth)
     - send error messages to UI instead of console for viewability
     
     Note:
     String must be added to playlist before being played.
     To add to playlist, convert string into AudioObject,
     which requires converting the string into URL type and wrapping it as AudioObject.
     
     Note2: when an audio file is loaded, the buffering bar should be revealed and needs to be reset/configured everytime we change the loaded audio file
     */
