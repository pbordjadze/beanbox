import BeanCore
import Charts
import SwiftUI

/// Beans plotted along their two strongest colour differences. Both axes share one scale, so
/// distance on screen is colour distance: separate clouds are separate flavours.
struct GroupChart: View {
    let beans: [Sorting.Bean]
    let partition: Sorting.Partition
    @Binding var picked: Int?

    /// Plot width ÷ height; the axis domains are sized to it so one unit is as long on x as on y.
    private let aspect = 1.45

    private var domain: (x: ClosedRange<Double>, y: ClosedRange<Double>) {
        let xs = beans.map(\.principal.x), ys = beans.map(\.principal.y)
        func middle(_ v: [Double]) -> Double { ((v.min() ?? 0) + (v.max() ?? 0)) / 2 }
        func spread(_ v: [Double]) -> Double { (v.max() ?? 0) - (v.min() ?? 0) }
        // Never zoom in past 6 units across: one flavour's natural scatter should look like a
        // small tight cloud, not fill the plot.
        let height = max(spread(xs) * 1.2 / aspect, spread(ys) * 1.2, 6 / aspect)
        let width = height * aspect
        return (middle(xs) - width / 2...middle(xs) + width / 2, middle(ys) - height / 2...middle(ys) + height / 2)
    }

    var body: some View {
        let domain = self.domain
        let grouped = partition.groupCount > 1
        Chart {
            ForEach(beans.indices, id: \.self) { i in
                PointMark(x: .value("Strongest difference", beans[i].principal.x), y: .value("Second strongest", beans[i].principal.y))
                    .symbol {
                        // A ring in the surface colour keeps overlapping dots legible.
                        Circle()
                            .fill(grouped ? Theme.groups[partition.assignment[i]].color : Theme.ink.opacity(0.55))
                            .frame(width: 11, height: 11)
                            .overlay { Circle().strokeBorder(Theme.surface, lineWidth: 1.5) }
                    }
            }
            // Up to four groups are lettered on the plot itself; beyond that the letters
            // would crowd, and the list below is the legend.
            if grouped && partition.groupCount <= 4 {
                ForEach(0..<partition.groupCount, id: \.self) { group in
                    let members = beans.indices.filter { partition.assignment[$0] == group }
                    let cx = members.reduce(0) { $0 + beans[$1].principal.x } / Double(max(members.count, 1))
                    let top = members.map { beans[$0].principal.y }.max() ?? 0
                    PointMark(x: .value("Strongest difference", cx), y: .value("Second strongest", top))
                        .symbolSize(0)
                        .annotation(position: .top, spacing: 6) {
                            Text(Theme.letters[group]).font(.subheadline.weight(.bold))
                        }
                }
            }
            if let picked, beans.indices.contains(picked) {
                PointMark(x: .value("Strongest difference", beans[picked].principal.x), y: .value("Second strongest", beans[picked].principal.y))
                    .symbol {
                        Circle().strokeBorder(Theme.ink, lineWidth: 2).frame(width: 20, height: 20)
                    }
            }
        }
        .chartXScale(domain: domain.x)
        .chartYScale(domain: domain.y)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) {
                // Solid hairlines: the default vertical rule is dashed, which reads as a threshold.
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                AxisValueLabel()
            }
        }
        .chartXAxisLabel("biggest colour difference between beans → (ΔE units)", alignment: .center)
        .chartPlotStyle { $0.aspectRatio(aspect, contentMode: .fit) }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(.rect)
                    .onTapGesture { location in
                        guard let frame = proxy.plotFrame else { return }
                        let origin = geometry[frame].origin
                        // The nearest dot within a fingertip: nobody lands dead-centre on an 11-point mark.
                        let nearest = beans.indices
                            .compactMap { i -> (Int, CGFloat)? in
                                guard let x = proxy.position(forX: beans[i].principal.x), let y = proxy.position(forY: beans[i].principal.y) else { return nil }
                                return (i, hypot(x + origin.x - location.x, y + origin.y - location.y))
                            }
                            .min { $0.1 < $1.1 }
                        picked = nearest.flatMap { $0.1 < 28 ? $0.0 : nil }
                    }
            }
        }
        .frame(height: 270)
        .accessibilityLabel("Beans plotted by colour difference")
        .accessibilityValue(grouped ? "\(partition.groupCount) groups" : "one group")
    }
}
