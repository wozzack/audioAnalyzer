[Recently Finished]
- Outline and flow control for visual model to canvas.
  - VisualProtocol classes process raw channel data from AVAudioFile through downsampling and wrap as SampleBuffer.
  - Each unique graph class dictates methodology on how to draw the visuals.
  - GraphManager handles the data and the drawing details and relays them to the UI (Canvas).

- Slider functionality

[Work In Progress]
- Implementation of waveform model display via Canvas.
- Refactoring AudioManager to fit general methods into HelperFunctions.swift

[Planned]
- Spectrogram display.
- Microphone input capability (recording and live).
- Refactor ErrorManager.
- Individual function documentation.
- Make decent looking UI.

