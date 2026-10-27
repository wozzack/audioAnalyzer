import SwiftUI


struct GraphView: View {
    let model: SpectrogramGraph?
    let displayMode: DisplayMode
    let orientation: SpectrogramOrientation
    let isLive: Bool
    // whether a file is loaded and ready to render (ignored while live)
    let showContent: Bool
    // shown in the idle, non-live state when nothing is loaded
    let placeholder: String

    var body: some View {
        if isLive {
            // live mode: redraw on a timer so the scrolling spectrogram animates even though
            // warpedData changes aren't observed by this view
            TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { timeline in
                let tick = timeline.date
                Canvas { context, size in
                    _ = tick
                    renderCurrent(in: context, size: size)
                }
            }
        } else {
            Canvas { context, size in
                if showContent {
                    renderCurrent(in: context, size: size)
                } else {
                    context.draw(Text(placeholder), at: CGPoint(x: size.width / 2, y: size.height / 2))
                }
            }
        }
    }

    // picks how to render the current model based on displayMode: the 2D image for
    // spectrogram, a 1D curve for spectrum/LTAS (both pulled from SpectrogramGraph).
    private func renderCurrent(in context: GraphicsContext, size: CGSize) {
        guard let spec = model else { return }
        switch displayMode {
        case .spectrogram:
            // same margins as the curve views so the two look consistent
            let left: CGFloat = 40, bottom: CGFloat = 18, top: CGFloat = 8, right: CGFloat = 8
            let plot = CGRect(x: left, y: top, width: size.width - left - right, height: size.height - top - bottom)
            guard plot.width > 0, plot.height > 0 else { return }
            if let cg = try? spec.drawGraph(rect: CGRect(origin: .zero, size: size),
                                            color: Color(.red), lineWidth: 1.0) {
                drawSpectrogram(cg, in: context, plot: plot)
            }
            drawSpectrogramAxes(in: context, plot: plot, model: spec)
        case .spectrum, .ltas:
            let values = (displayMode == .spectrum) ? spec.createSpectrumColumn() : spec.createLTASColumn()
            drawCurve(values, in: context, size: size, model: spec)
        }
    }

    // draws a 0...1 curve with real axes: frequency (Hz, on the current log/mel/linear
    // scale) on x, level (dB) on y, with gridlines + labels in the margins.
    private func drawCurve(_ values: [Float], in context: GraphicsContext, size: CGSize, model spec: SpectrogramGraph) {
        // margins leave room for labels: wider on the left (dB) and bottom (Hz)
        let left: CGFloat = 40, bottom: CGFloat = 18, top: CGFloat = 8, right: CGFloat = 8
        let plot = CGRect(x: left, y: top, width: size.width - left - right, height: size.height - top - bottom)
        guard plot.width > 0, plot.height > 0 else { return }

        let floorDB = spec.floorDB
        let gridShading = GraphicsContext.Shading.color(.gray.opacity(0.35))
        func yFor(intensity v: CGFloat) -> CGFloat { plot.maxY - plot.height * max(0, min(1, v)) }
        func xFor(freq f: Float) -> CGFloat { plot.minX + plot.width * CGFloat(spec.targetNormalPosition(frequency: f)) }
        func label(_ s: String, at p: CGPoint, anchor: UnitPoint) {
            context.draw(Text(s).font(.system(size: 9)).foregroundColor(.gray), at: p, anchor: anchor)
        }

        // dB horizontal gridlines (0 down to floorDB in steps of 20)
        var db = Float(0)
        while db >= floorDB {
            let y = yFor(intensity: CGFloat((db - floorDB) / (-floorDB)))
            var line = Path(); line.move(to: CGPoint(x: plot.minX, y: y)); line.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(line, with: gridShading, lineWidth: 0.5)
            label("\(Int(db))", at: CGPoint(x: plot.minX - 4, y: y), anchor: .trailing)
            db -= 20
        }

        // frequency vertical gridlines (tick set comes from the model)
        for f in spec.frequencyTicks {
            let x = xFor(freq: f)
            var line = Path(); line.move(to: CGPoint(x: x, y: plot.minY)); line.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(line, with: gridShading, lineWidth: 0.5)
            label(freqLabel(f), at: CGPoint(x: x, y: plot.maxY + 3), anchor: .top)
        }

        // the curve itself (x = bin index across the plot, which is the warped axis)
        guard values.count > 1 else { return }
        var path = Path()
        let n = values.count
        for (i, v) in values.enumerated() {
            let x = plot.minX + plot.width * CGFloat(i) / CGFloat(n - 1)
            let y = yFor(intensity: CGFloat(v))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(.green), lineWidth: 1.5)
    }

    // draws the spectrogram image into the plot rect honoring the chosen orientation
    // orientation is same image data laid out differently. clipped to the plot so the
    // rotated draw can't spill into the axis-label margins.
    private func drawSpectrogram(_ image: CGImage, in context: GraphicsContext, plot: CGRect) {
        var ctx = context
        ctx.clip(to: Path(plot))
        let img = Image(decorative: image, scale: 1)
        switch orientation {
        case .horizontal:
            ctx.draw(img, in: plot)
        case .vertical:
            // rotate about the plot center and draw into a swapped-dimension rect so the
            // image fills the plot
            ctx.translateBy(x: plot.midX, y: plot.midY)
            ctx.rotate(by: .degrees(-90))
            ctx.draw(img, in: CGRect(x: -plot.height / 2, y: -plot.width / 2,
                                     width: plot.height, height: plot.width))
        }
    }

    // overlays frequency + time axes on the spectrogram. frequency uses the same Hz tick
    // set and warped positioning as the curve views; time is derived from how many columns
    // of history are shown (spec.historySeconds). in horizontal orientation frequency is
    // the vertical axis (low at bottom) and time the horizontal axis (now at right); in
    // vertical orientation the two swap (time flows bottom→top).
    private func drawSpectrogramAxes(in context: GraphicsContext, plot: CGRect, model spec: SpectrogramGraph) {
        let grid = GraphicsContext.Shading.color(.white.opacity(0.25))
        func label(_ s: String, at p: CGPoint, anchor: UnitPoint) {
            context.draw(Text(s).font(.system(size: 9)).foregroundColor(.gray), at: p, anchor: anchor)
        }
        func hLine(_ y: CGFloat) {
            var l = Path(); l.move(to: CGPoint(x: plot.minX, y: y)); l.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(l, with: grid, lineWidth: 0.5)
        }
        func vLine(_ x: CGFloat) {
            var l = Path(); l.move(to: CGPoint(x: x, y: plot.minY)); l.addLine(to: CGPoint(x: x, y: plot.maxY))
            context.stroke(l, with: grid, lineWidth: 0.5)
        }

        // time axis span + "nice" step both come from the model
        let totalSeconds = spec.historySeconds
        let timeStep = spec.timeTickStep(forSpan: totalSeconds)
        func timeText(_ age: Double) -> String {
            if age == 0 { return "0" }
            let v = timeStep < 1 ? String(format: "%.1f", age) : "\(Int(age))"
            return "-\(v)s"
        }

        switch orientation {
        case .horizontal:
            // frequency on Y (low at bottom)
            for f in spec.frequencyTicks {
                let y = plot.maxY - plot.height * CGFloat(spec.targetNormalPosition(frequency: f))
                hLine(y)
                label(freqLabel(f), at: CGPoint(x: plot.minX - 4, y: y), anchor: .trailing)
            }
            // time on X (now at right, older to the left)
            if totalSeconds > 0 {
                var age = 0.0
                while age <= totalSeconds {
                    let x = plot.maxX - plot.width * CGFloat(age / totalSeconds)
                    vLine(x)
                    label(timeText(age), at: CGPoint(x: x, y: plot.maxY + 3), anchor: .top)
                    age += timeStep
                }
            }
        case .vertical:
            // frequency on X
            for f in spec.frequencyTicks {
                let x = plot.minX + plot.width * CGFloat(spec.targetNormalPosition(frequency: f))
                vLine(x)
                label(freqLabel(f), at: CGPoint(x: x, y: plot.maxY + 3), anchor: .top)
            }
            // time on Y (now at top, older toward the bottom)
            if totalSeconds > 0 {
                var age = 0.0
                while age <= totalSeconds {
                    let y = plot.minY + plot.height * CGFloat(age / totalSeconds)
                    hLine(y)
                    label(timeText(age), at: CGPoint(x: plot.minX - 4, y: y), anchor: .trailing)
                    age += timeStep
                }
            }
        }
    }

    // formats a frequency tick for display ("500", "2k")
    private func freqLabel(_ f: Float) -> String { f >= 1000 ? "\(Int(f / 1000))k" : "\(Int(f))" }
}
