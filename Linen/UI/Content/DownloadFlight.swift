// SPDX-FileCopyrightText: 2026 Kavoye
// SPDX-License-Identifier: Apache-2.0

import AppKit
import SwiftUI

@MainActor
@Observable
final class DownloadFlights {
    struct Flight: Identifiable, Equatable {
        let id = UUID()
        let from: CGPoint
        let to: CGPoint
    }

    private(set) var flights: [Flight] = []

    @ObservationIgnored var target: CGPoint?
    @ObservationIgnored private var lastClick: CGPoint?
    @ObservationIgnored private var clickedAt: Date?
    @ObservationIgnored private var monitor: Any?

    static let duration: Double = 0.8

    private let lifetime: Double

    init(lifetime: Double = DownloadFlights.duration) {
        self.lifetime = lifetime
    }

    private static let freshness: TimeInterval = 5

    func watchClicks(in window: @escaping () -> NSWindow?) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            if let window = window(), let view = window.contentView {
                let inWindow = event.locationInWindow
                self?.noteClick(at: CGPoint(x: inWindow.x, y: view.bounds.height - inWindow.y))
            }
            return event
        }
    }

    func noteClick(at point: CGPoint, on date: Date = Date()) {
        lastClick = point
        clickedAt = date
    }

    func launch(now: Date = Date()) {
        guard let from = lastClick,
              let to = target,
              let clickedAt,
              now.timeIntervalSince(clickedAt) < Self.freshness,
              from != to
        else { return }
        let flight = Flight(from: from, to: to)
        flights.append(flight)
        Task {
            try? await Task.sleep(for: .seconds(lifetime))
            flights.removeAll { $0.id == flight.id }
        }
    }
}

struct DownloadFlightLayer: View {
    let flights: DownloadFlights

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(flights.flights) { flight in
                DownloadFlightMark(flight: flight)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct DownloadFlightMark: View {
    let flight: DownloadFlights.Flight

    @State private var progress: Double = 0

    private var scale: Double {
        0.85 + sin(progress * .pi) * 0.5 - progress * 0.05
    }

    var body: some View {
        Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: SidebarMetrics.controlHeight - 6, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .background(Circle().fill(.white).padding(3))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            .scaleEffect(scale)
            .opacity(progress > 0.85 ? (1 - progress) / 0.15 : 1)
            .modifier(FlightArc(progress: progress, from: flight.from, to: flight.to))
            .onAppear {
                withAnimation(.timingCurve(0.4, 0, 0.25, 1, duration: DownloadFlights.duration)) {
                    progress = 1
                }
            }
    }
}

private struct FlightArc: ViewModifier, Animatable {
    var progress: Double
    let from: CGPoint
    let to: CGPoint

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var control: CGPoint {
        let span = hypot(to.x - from.x, to.y - from.y)
        let sag = min(140, max(40, span * 0.3))
        return CGPoint(x: from.x + (to.x - from.x) * 0.3, y: min(from.y, to.y) - sag)
    }

    private var point: CGPoint {
        let rest = 1 - progress
        let control = control
        return CGPoint(
            x: rest * rest * from.x + 2 * rest * progress * control.x + progress * progress * to.x,
            y: rest * rest * from.y + 2 * rest * progress * control.y + progress * progress * to.y
        )
    }

    func body(content: Content) -> some View {
        content.position(point)
    }
}
