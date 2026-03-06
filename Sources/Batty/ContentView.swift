import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var monitor: BatteryMonitor
    @State private var selectedTab: Tab = .overview
    @State private var previousTab: Tab = .overview
    @Namespace private var tabNamespace

    enum Tab: CaseIterable, Hashable {
        case overview, details, settings

        var icon: String {
            switch self {
            case .overview: return "battery.100"
            case .details:  return "chart.bar"
            case .settings: return "slider.horizontal.3"
            }
        }

        var index: Int {
            switch self {
            case .overview: return 0
            case .details:  return 1
            case .settings: return 2
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sliding tab content
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LiquidGlassTabBar(
                selectedTab: $selectedTab,
                previousTab: $previousTab,
                namespace: tabNamespace
            )
        }
        .background {
            ZStack {
                // Base frosted material
                Rectangle()
                    .fill(.ultraThinMaterial)
                // White wash — push it toward bright liquid glass
                Rectangle()
                    .fill(Color.white.opacity(0.55))
            }
        }
        .frame(width: 320, height: 480)
    }

    // MARK: - Sliding Tab Content
    @ViewBuilder
    private var tabContent: some View {
        // We use a ZStack with offset-based sliding.
        // Each view sits at an offset based on its index relative to selected.
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Group {
                        switch tab {
                        case .overview: OverviewTab().environmentObject(monitor)
                        case .details:  DetailsTab(scrollToTopTrigger: selectedTab == .details).environmentObject(monitor)
                        case .settings: SettingsTab(scrollToTopTrigger: selectedTab == .settings).environmentObject(monitor)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .offset(x: -CGFloat(selectedTab.index) * geo.size.width)
            .animation(.spring(response: 0.38, dampingFraction: 0.82, blendDuration: 0), value: selectedTab)
        }
    }
}

// MARK: - Liquid Glass Tab Bar
struct LiquidGlassTabBar: View {
    @Binding var selectedTab: ContentView.Tab
    @Binding var previousTab: ContentView.Tab
    var namespace: Namespace.ID

    var body: some View {
        ZStack {
            // Glass pill background layer
            glassBackground

            // Tab buttons
            HStack(spacing: 0) {
                ForEach(ContentView.Tab.allCases, id: \.self) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 56)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Glass Background
    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                // White wash to push toward bright liquid glass, not gray
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.18))
            }
            .overlay {
                // Top specular highlight
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.10),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.07), radius: 6, x: 0, y: 3)
    }

    // MARK: - Tab Button
    private func tabButton(for tab: ContentView.Tab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            NSHapticFeedbackManager.defaultPerformer
                .perform(.alignment, performanceTime: .default)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                previousTab = selectedTab
                selectedTab = tab
            }
        } label: {
            ZStack {
                // Moving selection pill — matchedGeometryEffect for liquid morph
                if isSelected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(0.55))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color.white.opacity(0.75), lineWidth: 0.75)
                        }
                        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                        .matchedGeometryEffect(id: "tabSelection", in: namespace)
                }

                Image(systemName: tab.icon)
                    .font(.system(size: 15.5, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(
                        isSelected
                            ? Color.black.opacity(0.65)
                            : Color.primary.opacity(0.28)
                    )
                    .scaleEffect(isSelected ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

